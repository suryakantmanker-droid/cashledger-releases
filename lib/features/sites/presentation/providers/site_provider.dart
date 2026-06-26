import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/notification_service_provider.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../shared/providers/business_context_provider.dart';
import '../../data/datasources/site_datasource.dart';
import '../../data/models/site_assignment_model.dart';
import '../../data/models/site_model.dart';

// ── Datasource ──────────────────────────────────────────────────────────────

final _siteDataSourceProvider = Provider<SiteDataSource>((ref) {
  return SiteDataSource(ref.watch(supabaseClientProvider));
});

// ── Sites list (current business) ────────────────────────────────────────────

final sitesProvider = FutureProvider.autoDispose<List<SiteModel>>((ref) async {
  final businessId = ref.watch(activeBusinessIdProvider);
  if (businessId == null) return [];
  return ref.watch(_siteDataSourceProvider).getSites(businessId);
});

// ── Site notifier (create / delete) ──────────────────────────────────────────

class SiteNotifierState {
  final bool isLoading;
  final String? error;
  final String? success;

  const SiteNotifierState({this.isLoading = false, this.error, this.success});

  SiteNotifierState copyWith({bool? isLoading, String? error, String? success}) =>
      SiteNotifierState(
        isLoading: isLoading ?? this.isLoading,
        error:     error,
        success:   success,
      );
}

class SiteNotifier extends StateNotifier<SiteNotifierState> {
  final SiteDataSource _ds;
  final Ref _ref;

  SiteNotifier(this._ds, this._ref) : super(const SiteNotifierState());

  Future<SiteModel?> create({
    required String name,
    required String address,
    required String businessId,
    required String createdBy,
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      final site = await _ds.createSite(
        name:       name,
        address:    address,
        businessId: businessId,
        createdBy:  createdBy,
      );
      _ref.invalidate(sitesProvider);
      state = state.copyWith(isLoading: false, success: '"${site.name}" created successfully');
      return site;
    } catch (e) {
      final msg = e.toString().contains('unique') ? '"$name" already exists' : 'Failed to create site';
      state = state.copyWith(isLoading: false, error: msg);
      return null;
    }
  }

  Future<void> delete(String id) async {
    state = state.copyWith(isLoading: true);
    try {
      await _ds.deleteSite(id);
      _ref.invalidate(sitesProvider);
      state = state.copyWith(isLoading: false, success: 'Site removed');
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to delete');
    }
  }

  void clearMessages() => state = state.copyWith();
}

final siteNotifierProvider = StateNotifierProvider<SiteNotifier, SiteNotifierState>((ref) {
  return SiteNotifier(ref.watch(_siteDataSourceProvider), ref);
});

// ── Per-employee assignment (current + history) ──────────────────────────────

final currentSiteAssignmentProvider =
    FutureProvider.autoDispose.family<SiteAssignmentModel?, String>((ref, employeeId) {
  return ref.watch(_siteDataSourceProvider).getCurrentAssignment(employeeId);
});

final siteAssignmentHistoryProvider =
    FutureProvider.autoDispose.family<List<SiteAssignmentModel>, String>((ref, employeeId) {
  return ref.watch(_siteDataSourceProvider).getAssignmentHistory(employeeId);
});

// ── Change-site notifier (writes + notification) ─────────────────────────────

class SiteAssignmentNotifierState {
  final bool isLoading;
  final String? error;
  final String? success;

  const SiteAssignmentNotifierState({this.isLoading = false, this.error, this.success});

  SiteAssignmentNotifierState copyWith({bool? isLoading, String? error, String? success}) =>
      SiteAssignmentNotifierState(
        isLoading: isLoading ?? this.isLoading,
        error:     error,
        success:   success,
      );
}

class SiteAssignmentNotifier extends StateNotifier<SiteAssignmentNotifierState> {
  final SiteDataSource _ds;
  final Ref _ref;

  SiteAssignmentNotifier(this._ds, this._ref) : super(const SiteAssignmentNotifierState());

  /// Assigns [employeeId] to [newSite]. Pass [notifyChange] = false for an
  /// employee's very first assignment (nothing to be "changed" from yet).
  Future<bool> changeSite({
    required String employeeId,
    required String businessId,
    required SiteModel newSite,
    required String assignedBy,
    required String changedByName,
    bool notifyChange = true,
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      await _ds.changeEmployeeSite(
        employeeId: employeeId,
        businessId: businessId,
        newSiteId:  newSite.id,
        assignedBy: assignedBy,
      );

      if (notifyChange) {
        await _ref.read(notificationServiceProvider).sendNotificationToUser(
          userId: employeeId,
          title:  'Site Changed',
          body:   'Your site has been changed to ${newSite.name} by $changedByName.',
          type:   'site_changed',
          businessId: businessId,
        );
      }

      _ref.invalidate(currentSiteAssignmentProvider(employeeId));
      _ref.invalidate(siteAssignmentHistoryProvider(employeeId));
      state = state.copyWith(isLoading: false, success: 'Site updated.');
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  void clearMessages() => state = state.copyWith();
}

final siteAssignmentActionsProvider =
    StateNotifierProvider<SiteAssignmentNotifier, SiteAssignmentNotifierState>((ref) {
  return SiteAssignmentNotifier(ref.watch(_siteDataSourceProvider), ref);
});
