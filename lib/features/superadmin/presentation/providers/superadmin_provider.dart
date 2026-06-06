import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/services/hive_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../shared/providers/business_context_provider.dart';
import '../../data/datasources/superadmin_datasource.dart';

// ── Dependency provider ────────────────────────────────────────────────────

final superadminDataSourceProvider = Provider<SuperadminDataSource>((ref) {
  return SuperadminDataSourceImpl(ref.watch(supabaseClientProvider));
});

// ── Business list ──────────────────────────────────────────────────────────

final allBusinessesProvider =
    FutureProvider.autoDispose<List<BusinessOverview>>((ref) async {
  return ref.watch(superadminDataSourceProvider).getAllBusinesses();
});

// ── Create-business notifier ───────────────────────────────────────────────

class CreateBusinessState {
  final bool isLoading;
  final String? errorMessage;
  final String? successMessage;

  const CreateBusinessState({
    this.isLoading = false,
    this.errorMessage,
    this.successMessage,
  });

  CreateBusinessState copyWith({
    bool? isLoading,
    String? errorMessage,
    String? successMessage,
  }) =>
      CreateBusinessState(
        isLoading:      isLoading      ?? this.isLoading,
        errorMessage:   errorMessage,
        successMessage: successMessage,
      );
}

class CreateBusinessNotifier extends StateNotifier<CreateBusinessState> {
  final SuperadminDataSource _dataSource;
  final Ref _ref;

  CreateBusinessNotifier(this._dataSource, this._ref)
      : super(const CreateBusinessState());

  Future<bool> create({
    required String businessName,
    required String adminName,
    required String adminEmail,
    required String adminPassword,
    int demoDays = 14,
    String? phone,
    String? plan,
    String? address,
    String? city,
    String? district,
    String? stateName,
  }) async {
    state = state.copyWith(isLoading: true);

    final currentUser = _ref.read(currentUserProvider).valueOrNull;
    if (currentUser == null) {
      state = state.copyWith(isLoading: false, errorMessage: 'Not logged in.');
      return false;
    }

    try {
      await _dataSource.createBusiness(
        businessName:  businessName.trim(),
        adminName:     adminName.trim(),
        adminEmail:    adminEmail.trim(),
        adminPassword: adminPassword,
        createdBy:     currentUser.uid,
        demoDays:      demoDays,
        phone:         phone?.trim(),
        plan:          plan,
        address:       address?.trim(),
        city:          city?.trim(),
        district:      district?.trim(),
        state:         stateName?.trim(),
      );

      _ref.invalidate(allBusinessesProvider);

      final businessCtx = _ref.read(businessContextProvider.notifier);
      businessCtx.reload(currentUser.uid);

      state = state.copyWith(
        isLoading:      false,
        successMessage: 'Business "$businessName" created successfully.',
      );
      return true;
    } on ServerException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  void clearMessages() => state = state.copyWith();
}

final createBusinessProvider =
    StateNotifierProvider<CreateBusinessNotifier, CreateBusinessState>((ref) {
  return CreateBusinessNotifier(
    ref.watch(superadminDataSourceProvider),
    ref,
  );
});

// ── Subscription management notifier ──────────────────────────────────────

class SubscriptionState {
  final bool isLoading;
  final String? errorMessage;
  final String? successMessage;

  const SubscriptionState({
    this.isLoading = false,
    this.errorMessage,
    this.successMessage,
  });

  SubscriptionState copyWith({
    bool? isLoading,
    String? errorMessage,
    String? successMessage,
  }) =>
      SubscriptionState(
        isLoading:      isLoading    ?? this.isLoading,
        errorMessage:   errorMessage,
        successMessage: successMessage,
      );
}

class SubscriptionNotifier extends StateNotifier<SubscriptionState> {
  final SuperadminDataSource _dataSource;
  final Ref _ref;

  SubscriptionNotifier(this._dataSource, this._ref)
      : super(const SubscriptionState());

  Future<bool> setDemo(String businessId, {required int days}) async {
    state = state.copyWith(isLoading: true);
    try {
      final expiry = DateTime.now().add(Duration(days: days));
      await _dataSource.setSubscription(
        businessId,
        status: 'demo',
        expiryDate: expiry,
      );
      _ref.invalidate(allBusinessesProvider);
      state = state.copyWith(
        isLoading:      false,
        successMessage: 'Demo set for $days days.',
      );
      return true;
    } on ServerException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> activate(String businessId) async {
    state = state.copyWith(isLoading: true);
    try {
      await _dataSource.setSubscription(businessId, status: 'active');
      _ref.invalidate(allBusinessesProvider);
      state = state.copyWith(isLoading: false, successMessage: 'Business activated.');
      return true;
    } on ServerException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> deactivate(String businessId) async {
    state = state.copyWith(isLoading: true);
    try {
      await _dataSource.setSubscription(businessId, status: 'inactive');
      _ref.invalidate(allBusinessesProvider);
      state = state.copyWith(isLoading: false, successMessage: 'Business deactivated.');
      return true;
    } on ServerException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> updateBusiness(
    String businessId, {
    required String name,
    String? phone,
    String? plan,
    int? maxEmployees,
    String? address,
    String? city,
    String? district,
    String? stateName,
    String? ownerName,
    String? ownerEmail,
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      await _dataSource.updateBusiness(
        businessId,
        name:         name.trim(),
        phone:        phone?.trim(),
        plan:         plan,
        maxEmployees: maxEmployees,
        address:      address?.trim(),
        city:         city?.trim(),
        district:     district?.trim(),
        state:        stateName?.trim(),
        ownerName:    ownerName?.trim(),
        ownerEmail:   ownerEmail?.trim(),
      );
      state = state.copyWith(isLoading: false, successMessage: 'Business updated successfully.');
      // Defer list refresh outside the Riverpod notification cycle.
      Future.microtask(() => _ref.invalidate(allBusinessesProvider));
      return true;
    } on ServerException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> resetAdminPassword(String ownerUid, String newPassword) async {
    state = state.copyWith(isLoading: true);
    try {
      await _dataSource.resetUserPassword(ownerUid, newPassword);
      state = state.copyWith(isLoading: false, successMessage: 'Admin password reset successfully.');
      return true;
    } on ServerException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  void clearMessages() => state = state.copyWith();
}

final subscriptionProvider =
    StateNotifierProvider<SubscriptionNotifier, SubscriptionState>((ref) {
  return SubscriptionNotifier(
    ref.watch(superadminDataSourceProvider),
    ref,
  );
});

// ── Super-admin watch list ─────────────────────────────────────────────────

class SuperAdminWatchState {
  final List<WatchedBusiness> watched;
  final bool isLoading;

  const SuperAdminWatchState({this.watched = const [], this.isLoading = false});

  SuperAdminWatchState copyWith({List<WatchedBusiness>? watched, bool? isLoading}) =>
      SuperAdminWatchState(
        watched:   watched   ?? this.watched,
        isLoading: isLoading ?? this.isLoading,
      );

  bool isWatching(String businessId) =>
      watched.any((w) => w.businessId == businessId && w.isActive);

  WatchedBusiness? entryFor(String businessId) =>
      watched.where((w) => w.businessId == businessId).firstOrNull;
}

class SuperAdminWatchNotifier extends StateNotifier<SuperAdminWatchState> {
  final SuperadminDataSource _ds;
  final Ref _ref;

  SuperAdminWatchNotifier(this._ds, this._ref) : super(const SuperAdminWatchState()) {
    _load();
  }

  String? get _uid => _ref.read(currentUserProvider).valueOrNull?.uid;

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) return;
    state = state.copyWith(isLoading: true);
    final list = await _ds.getWatchedBusinesses(uid);
    state = state.copyWith(watched: list, isLoading: false);
  }

  Future<void> watch(String businessId, {DateTime? until}) async {
    final uid = _uid;
    if (uid == null) return;
    await _ds.watchBusiness(
      superadminUid: uid,
      businessId:    businessId,
      watchUntil:    until,
    );
    await _load();
  }

  Future<void> unwatch(String businessId) async {
    final uid = _uid;
    if (uid == null) return;
    await _ds.unwatchBusiness(superadminUid: uid, businessId: businessId);
    state = state.copyWith(
      watched: state.watched.where((w) => w.businessId != businessId).toList(),
    );
  }

  // Amount threshold stored locally on super-admin's device only
  double? get amountThreshold => HiveService.instance.getAmountThreshold();

  Future<void> setAmountThreshold(double? amount) =>
      HiveService.instance.saveAmountThreshold(amount);
}

final superAdminWatchProvider =
    StateNotifierProvider<SuperAdminWatchNotifier, SuperAdminWatchState>((ref) {
  return SuperAdminWatchNotifier(ref.watch(superadminDataSourceProvider), ref);
});
