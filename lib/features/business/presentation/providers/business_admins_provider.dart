import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/providers/business_context_provider.dart';
import '../../data/datasources/business_remote_datasource.dart';

// ── List of current admins for a business ──────────────────────────────────

final businessAdminsProvider =
    FutureProvider.family.autoDispose<List<BusinessMemberInfo>, String>(
  (ref, businessId) async {
    final result =
        await ref.watch(businessRepositoryProvider).getBusinessAdmins(businessId);
    return result.fold((failure) => throw Exception(failure.message), (r) => r);
  },
);

// ── Add/remove actions ──────────────────────────────────────────────────────

class BusinessAdminsActionsState {
  final bool isLoading;
  final String? errorMessage;
  final String? successMessage;

  const BusinessAdminsActionsState({
    this.isLoading = false,
    this.errorMessage,
    this.successMessage,
  });

  BusinessAdminsActionsState copyWith({
    bool? isLoading,
    String? errorMessage,
    String? successMessage,
  }) =>
      BusinessAdminsActionsState(
        isLoading:      isLoading      ?? this.isLoading,
        errorMessage:   errorMessage,
        successMessage: successMessage,
      );
}

class BusinessAdminsActionsNotifier extends StateNotifier<BusinessAdminsActionsState> {
  final Ref _ref;

  BusinessAdminsActionsNotifier(this._ref) : super(const BusinessAdminsActionsState());

  Future<bool> inviteAdmin({
    required String businessId,
    required String name,
    required String email,
    required String password,
    required String invitedBy,
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      final result = await _ref.read(businessRepositoryProvider).inviteAdmin(
        businessId: businessId,
        name:       name.trim(),
        email:      email.trim(),
        password:   password,
        invitedBy:  invitedBy,
      );
      return result.fold(
        (failure) {
          state = state.copyWith(isLoading: false, errorMessage: failure.message);
          return false;
        },
        (_) {
          _ref.invalidate(businessAdminsProvider(businessId));
          state = state.copyWith(
            isLoading:      false,
            successMessage: 'Admin "$name" added successfully.',
          );
          return true;
        },
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> removeAdmin({
    required String businessId,
    required String userUid,
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      final result = await _ref
          .read(businessRepositoryProvider)
          .removeAdmin(businessId: businessId, userUid: userUid);
      return result.fold(
        (failure) {
          state = state.copyWith(isLoading: false, errorMessage: failure.message);
          return false;
        },
        (_) {
          _ref.invalidate(businessAdminsProvider(businessId));
          state = state.copyWith(isLoading: false, successMessage: 'Admin removed.');
          return true;
        },
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  /// Looks up [email]. Returns null on lookup failure (with errorMessage set)
  /// as well as on "no such user" — callers distinguish via [hadError].
  Future<ExistingUserMatch?> findUserByEmail({
    required String businessId,
    required String email,
  }) async {
    final result = await _ref
        .read(businessRepositoryProvider)
        .findUserByEmail(businessId: businessId, email: email.trim());
    return result.fold(
      (failure) {
        state = state.copyWith(errorMessage: failure.message);
        return null;
      },
      (match) => match,
    );
  }

  /// Attaches an already-existing user (not yet a member of this business)
  /// as an admin — no new Auth account needed.
  Future<bool> addExistingUserAsAdmin({
    required String businessId,
    required String userUid,
    required String invitedBy,
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      final result = await _ref.read(businessRepositoryProvider).addMember(
        businessId: businessId,
        userUid:    userUid,
        role:       AppConstants.roleAdmin,
        invitedBy:  invitedBy,
      );
      return await result.fold<Future<bool>>(
        (failure) async {
          state = state.copyWith(isLoading: false, errorMessage: failure.message);
          return false;
        },
        (_) async {
          await _deactivateEmployeeRecordIfAny(businessId: businessId, userUid: userUid);
          _ref.invalidate(businessAdminsProvider(businessId));
          state = state.copyWith(isLoading: false, successMessage: 'Admin added successfully.');
          return true;
        },
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  /// Switches an existing member's role to admin.
  Future<bool> switchToAdmin({
    required String businessId,
    required String userUid,
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      final result = await _ref.read(businessRepositoryProvider).updateMemberRole(
        businessId: businessId,
        userUid:    userUid,
        newRole:    AppConstants.roleAdmin,
      );
      // updateMemberRole already handles the employees-record
      // deactivation/reactivation and previous_role bookkeeping centrally.
      return result.fold(
        (failure) {
          state = state.copyWith(isLoading: false, errorMessage: failure.message);
          return false;
        },
        (_) {
          _ref.invalidate(businessAdminsProvider(businessId));
          state = state.copyWith(isLoading: false, successMessage: 'Switched to Admin.');
          return true;
        },
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  /// Switches a member back to the role they held before being promoted.
  Future<bool> revertToPreviousRole({
    required String businessId,
    required String userUid,
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      final result = await _ref.read(businessRepositoryProvider).revertToPreviousRole(
        businessId: businessId,
        userUid:    userUid,
      );
      return result.fold(
        (failure) {
          state = state.copyWith(isLoading: false, errorMessage: failure.message);
          return false;
        },
        (_) {
          _ref.invalidate(businessAdminsProvider(businessId));
          state = state.copyWith(isLoading: false, successMessage: 'Reverted to previous role.');
          return true;
        },
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  /// Best-effort — an admin promotion has already succeeded by this point,
  /// so a failure here shouldn't surface as an error to the user.
  Future<void> _deactivateEmployeeRecordIfAny({
    required String businessId,
    required String userUid,
  }) async {
    try {
      await _ref.read(businessRepositoryProvider).deactivateEmployeeRecordIfAny(
        businessId: businessId,
        userUid:    userUid,
      );
    } catch (_) {}
  }

  void clearMessages() => state = state.copyWith();
}

final businessAdminsActionsProvider =
    StateNotifierProvider<BusinessAdminsActionsNotifier, BusinessAdminsActionsState>(
  (ref) => BusinessAdminsActionsNotifier(ref),
);
