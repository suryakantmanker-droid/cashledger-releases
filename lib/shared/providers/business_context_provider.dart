import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/permission_matrix.dart';
import '../../core/services/hive_service.dart';
import '../../core/services/supabase_service.dart';
import '../../features/business/data/datasources/business_remote_datasource.dart';
import '../../features/business/data/repositories/business_repository_impl.dart';
import '../../features/business/domain/entities/business_membership_entity.dart';
import '../../features/business/domain/repositories/business_repository.dart';

// =============================================================================
// BUSINESS CONTEXT — The spine of the multi-business architecture.
//
// Every repository, screen, and provider that needs to scope data to the
// current business reads from [activeBusinessIdProvider] or
// [currentUserRoleProvider]. They never receive businessId as a parameter
// through the widget tree.
//
// Bootstrap sequence (app start with existing session):
//   Firebase Auth emits user
//   → _RouterRefreshNotifier calls businessContextProvider.notifier.loadForUser()
//   → Supabase memberships fetched
//   → activeMembership set + persisted to Hive
//   → Router re-evaluates redirect → navigates to dashboard
//
// Explicit login sequence:
//   AuthNotifier.login() completes
//   → _RouterRefreshNotifier fires
//   → Same sequence as above
//
// Business switch:
//   businessContextProvider.notifier.switchTo(businessId)
//   → Updates activeMembership in state
//   → Persists new businessId to Hive
//   → Invalidates all business-scoped data providers
// =============================================================================

// ── Status ───────────────────────────────────────────────────────────────────

enum BusinessContextStatus {
  idle,           // Initial state — no load attempted
  loading,        // Fetching memberships from Supabase
  loaded,         // Active membership is set and ready
  noBusinessFound, // User is authenticated but has no business membership
  error,          // Network or Supabase error
}

// ── State ────────────────────────────────────────────────────────────────────

class BusinessContextState {
  final BusinessContextStatus status;
  final BusinessMembershipEntity? activeMembership;
  final List<BusinessMembershipEntity> memberships;
  final String? errorMessage;

  const BusinessContextState({
    this.status = BusinessContextStatus.idle,
    this.activeMembership,
    this.memberships = const [],
    this.errorMessage,
  });

  bool get isIdle    => status == BusinessContextStatus.idle;
  bool get isLoading => status == BusinessContextStatus.loading;
  bool get isLoaded  => status == BusinessContextStatus.loaded;
  bool get needsBusinessSetup => status == BusinessContextStatus.noBusinessFound;
  bool get hasError  => status == BusinessContextStatus.error;

  BusinessContextState copyWith({
    BusinessContextStatus? status,
    BusinessMembershipEntity? activeMembership,
    bool clearActiveMembership = false,
    List<BusinessMembershipEntity>? memberships,
    String? errorMessage,
  }) {
    return BusinessContextState(
      status:           status          ?? this.status,
      activeMembership: clearActiveMembership ? null : (activeMembership ?? this.activeMembership),
      memberships:      memberships     ?? this.memberships,
      errorMessage:     errorMessage    ?? this.errorMessage,
    );
  }
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class BusinessContextNotifier extends StateNotifier<BusinessContextState> {
  final BusinessRepository _repo;
  final HiveService _hive;
  bool _isSuperadmin = false;  // stored so reload() can reuse the same path
  String? _loadedForUid;       // tracks which user the context was loaded for

  BusinessContextNotifier(this._repo, this._hive)
      : super(const BusinessContextState());

  /// Loads business memberships for [userUid].
  /// Superadmins load ALL businesses; regular users load only their own.
  /// Idempotent: if already loading or loaded for the SAME user, this is a no-op.
  Future<void> loadForUser(String userUid, {bool isSuperadmin = false}) async {
    // If the context was loaded for a DIFFERENT user (e.g. admin → employee
    // switch without app restart), force a full reset so the old user's
    // activeMembership and role are never shown to the new user.
    if (state.isLoaded && _loadedForUid != null && _loadedForUid != userUid) {
      debugPrint('[BusinessCtx] User changed ($_loadedForUid → $userUid) — forcing reload');
      state = const BusinessContextState();
      _loadedForUid = null;
    }

    // Skip if already loading or if superadmin is currently inside a business
    // (activeMembership set via switchToForSuperadmin). Re-running loadForUser
    // while the superadmin is in a business would evict them via _applyMemberships.
    if (state.isLoading) {
      debugPrint('[BusinessCtx] Already loading — skipping load');
      return;
    }
    if (state.isLoaded && isSuperadmin && state.activeMembership != null) {
      debugPrint('[BusinessCtx] Superadmin in a business — skipping reload');
      return;
    }
    if (state.isLoaded && !isSuperadmin) {
      debugPrint('[BusinessCtx] Already loaded — skipping load');
      return;
    }
    // error / idle / noBusinessFound / (superadmin at hub while loaded) → retry

    _isSuperadmin = isSuperadmin;
    _loadedForUid = userUid;
    debugPrint('[BusinessCtx] Loading context for uid=$userUid superadmin=$isSuperadmin');
    state = state.copyWith(status: BusinessContextStatus.loading);

    final result = isSuperadmin
        ? await _repo.getAllBusinessesAsSuperadmin(userUid)
        : await _repo.getMembershipsForUser(userUid);

    try {
      result.fold(
        (failure) {
          debugPrint('[BusinessCtx] Load failed: ${failure.message}');
          final cached = _hive.getCachedMemberships();
          if (cached != null && cached.isNotEmpty) {
            _restoreFromCache(cached);
          } else {
            state = state.copyWith(
              status: BusinessContextStatus.error,
              errorMessage: failure.message,
            );
          }
        },
        (memberships) {
          if (memberships.isEmpty && !isSuperadmin) {
            debugPrint('[BusinessCtx] No memberships — needs business setup');
            state = state.copyWith(
              status: BusinessContextStatus.noBusinessFound,
              memberships: [],
            );
            return;
          }
          _applyMemberships(memberships);
        },
      );
    } catch (e, st) {
      debugPrint('[BusinessCtx] Unexpected error applying memberships: $e\n$st');
      state = state.copyWith(
        status: BusinessContextStatus.error,
        errorMessage: 'Failed to load business context. Please try again.',
      );
    }
  }

  /// Switches the active business to [businessId].
  Future<void> switchTo(String businessId) async {
    final target = state.memberships.firstWhere(
      (m) => m.businessId == businessId,
      orElse: () => throw ArgumentError('Business $businessId not in memberships'),
    );

    debugPrint('[BusinessCtx] Switching to businessId=$businessId role=${target.role.name}');
    state = state.copyWith(activeMembership: target);
    await _hive.saveActiveBusinessId(businessId);
  }

  /// Switches directly to a business for superadmin without requiring memberships to be loaded.
  /// Creates a synthetic owner membership on the fly.
  Future<void> switchToForSuperadmin({
    required String businessId,
    required String businessName,
    required String userUid,
    String? businessLogoUrl,
  }) async {
    final membership = BusinessMembershipEntity(
      id: 'superadmin_$businessId',
      businessId: businessId,
      businessName: businessName,
      userUid: userUid,
      role: UserRole.owner,
      isActive: true,
      joinedAt: DateTime.now(),
      businessLogoUrl: businessLogoUrl,
    );
    debugPrint('[BusinessCtx] Superadmin switching to businessId=$businessId');
    state = state.copyWith(
      status: BusinessContextStatus.loaded,
      activeMembership: membership,
    );
    await _hive.saveActiveBusinessId(businessId);
  }

  /// Clears the active business selection (superadmin returning to hub).
  Future<void> clearActiveBusiness() async {
    debugPrint('[BusinessCtx] Clearing active business selection');
    state = state.copyWith(clearActiveMembership: true);
    await _hive.clearActiveBusinessId();
  }

  /// Reloads memberships from the server.
  Future<void> reload(String userUid) async {
    state = state.copyWith(status: BusinessContextStatus.idle);
    await loadForUser(userUid, isSuperadmin: _isSuperadmin);
  }

  /// Clears all business context on logout.
  Future<void> clear() async {
    debugPrint('[BusinessCtx] Clearing business context');
    _isSuperadmin = false;
    _loadedForUid = null;
    state = const BusinessContextState();
    await _hive.clearActiveBusinessId();
    await _hive.clearMembershipsCache();
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  void _applyMemberships(List<BusinessMembershipEntity> memberships) {
    if (_isSuperadmin) {
      if (state.activeMembership != null) {
        // Superadmin is currently inside a business (via switchToForSuperadmin).
        // A background reload (e.g. after creating a new business) must NOT
        // evict them — just refresh the business list.
        state = state.copyWith(
          status: BusinessContextStatus.loaded,
          memberships: memberships,
        );
      } else {
        // No active business yet → start at the hub.
        state = state.copyWith(
          status: BusinessContextStatus.loaded,
          clearActiveMembership: true,
          memberships: memberships,
        );
      }
      return;
    }

    // Restore previously active business or default to first.
    // Avoid firstWhere+orElse: at runtime the list is List<BusinessMembershipModel>
    // and orElse returning the base Entity type causes a TypeError.
    final savedId = _hive.getActiveBusinessId();
    final active = memberships.where((m) => m.businessId == savedId).firstOrNull
        ?? memberships.first;

    // Persist for next launch
    _hive.saveActiveBusinessId(active.businessId);
    _hive.cacheMemberships(
      memberships.map((m) => {'business_id': m.businessId, 'role': m.role.name}).toList(),
    );

    debugPrint('[BusinessCtx] Active: ${active.businessName} (${active.role.name})');
    state = state.copyWith(
      status:           BusinessContextStatus.loaded,
      activeMembership: active,
      memberships:      memberships,
      errorMessage:     null,
    );
  }

  void _restoreFromCache(List<Map<String, dynamic>> cached) {
    // Build minimal entities from the cache (enough to bootstrap the UI)
    // Find the matching cached entry or fall back to first (result not used —
    // cache is too sparse to rebuild full entities; we signal an error state)
    final savedId = _hive.getActiveBusinessId();
    cached.firstWhere(
      (e) => e['business_id'] == savedId,
      orElse: () => cached.first,
    );

    debugPrint('[BusinessCtx] Restored from Hive cache');
    // We don't have full entity data from the cache so we set status to error
    // and let the UI retry — but the app won't crash.
    state = state.copyWith(
      status: BusinessContextStatus.error,
      errorMessage: 'Offline — showing cached data',
    );
  }
}

// ── Dependency providers ──────────────────────────────────────────────────────

final _businessDataSourceProvider = Provider<BusinessRemoteDataSource>((ref) {
  return BusinessRemoteDataSourceImpl(ref.watch(supabaseClientProvider));
});

final businessRepositoryProvider = Provider<BusinessRepository>((ref) {
  return BusinessRepositoryImpl(
    ref.watch(_businessDataSourceProvider),
    Connectivity(),
  );
});

final hiveServiceProvider = Provider<HiveService>((ref) {
  return HiveService.instance;
});

// ── The main provider ─────────────────────────────────────────────────────────

/// Holds the full business context: active membership, all memberships, status.
/// This is a global keepAlive provider (StateNotifierProvider is not autoDispose).
final businessContextProvider =
    StateNotifierProvider<BusinessContextNotifier, BusinessContextState>((ref) {
  return BusinessContextNotifier(
    ref.watch(businessRepositoryProvider),
    ref.watch(hiveServiceProvider),
  );
});

// ── Derived providers — read these in UI and repositories ─────────────────────

/// The currently active business membership (null while bootstrapping).
final activeMembershipProvider = Provider<BusinessMembershipEntity?>((ref) {
  return ref.watch(businessContextProvider).activeMembership;
});

/// The currently active businessId. Throws if no business is loaded.
/// Repositories must only be called when this is non-null.
final activeBusinessIdProvider = Provider<String?>((ref) {
  return ref.watch(businessContextProvider).activeMembership?.businessId;
});

/// Current user's role in the active business.
final currentUserRoleProvider = Provider<UserRole>((ref) {
  return ref.watch(businessContextProvider).activeMembership?.role
      ?? UserRole.viewer;
});

/// All businesses the current user belongs to (for the business switcher).
final userMembershipsProvider = Provider<List<BusinessMembershipEntity>>((ref) {
  return ref.watch(businessContextProvider).memberships;
});

/// True while business context is being bootstrapped from Supabase.
final isBusinessLoadingProvider = Provider<bool>((ref) {
  return ref.watch(businessContextProvider).isLoading;
});

/// True when the user needs to create or join a business.
final needsBusinessSetupProvider = Provider<bool>((ref) {
  return ref.watch(businessContextProvider).needsBusinessSetup;
});
