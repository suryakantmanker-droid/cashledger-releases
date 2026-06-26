import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/permission_matrix.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../shared/providers/business_context_provider.dart';
import '../../../business/presentation/providers/business_admins_provider.dart';
import '../../data/datasources/employee_remote_datasource.dart';
import '../../data/models/employee_model.dart';

// ── Dependency Providers ───────────────────────────────────────────────────

final employeeRemoteDataSourceProvider = Provider<EmployeeRemoteDataSource>((ref) {
  return EmployeeRemoteDataSourceImpl(ref.watch(supabaseClientProvider));
});

// ── Stream Providers ───────────────────────────────────────────────────────
// All streams are autoDispose + scoped to activeBusinessId.
// When the active business changes, the old Supabase Realtime subscription
// is automatically cancelled and a new one is opened for the new business.

/// All employees (active + inactive) — used in employee list screen
final employeesStreamProvider = StreamProvider.autoDispose<List<EmployeeModel>>((ref) {
  final businessId = ref.watch(activeBusinessIdProvider);
  if (businessId == null) return Stream.value(const []);
  return ref.read(employeeRemoteDataSourceProvider)
      .watchAllEmployees(businessId: businessId, activeOnly: false);
});

/// Active employees only — used in fund transfer dropdown and any pickers
final activeEmployeesStreamProvider = StreamProvider.autoDispose<List<EmployeeModel>>((ref) {
  final businessId = ref.watch(activeBusinessIdProvider);
  if (businessId == null) return Stream.value(const []);
  return ref.read(employeeRemoteDataSourceProvider)
      .watchAllEmployees(businessId: businessId, activeOnly: true);
});

final employeeByIdProvider =
    StreamProvider.autoDispose.family<EmployeeModel, String>((ref, id) {
  final businessId = ref.watch(activeBusinessIdProvider);
  if (businessId == null) return Stream.error(const FirestoreException('No active business'));
  return ref.read(employeeRemoteDataSourceProvider)
      .watchEmployeeById(id, businessId: businessId);
});

/// The employee's current role in the active business (business_members.role),
/// independent of their `employees` table record — used by the "Change Role" UI.
final employeeCurrentRoleProvider =
    FutureProvider.autoDispose.family<UserRole?, String>((ref, userUid) async {
  final businessId = ref.watch(activeBusinessIdProvider);
  if (businessId == null) return null;
  final result = await ref.watch(businessRepositoryProvider).getMembershipsForUser(userUid);
  return result.fold(
    (_) => null,
    (memberships) => memberships.where((m) => m.businessId == businessId).firstOrNull?.role,
  );
});

// ── State Notifier ─────────────────────────────────────────────────────────

class EmployeeState {
  final bool isLoading;
  final String? errorMessage;
  final String? successMessage;

  const EmployeeState({
    this.isLoading = false,
    this.errorMessage,
    this.successMessage,
  });

  EmployeeState copyWith({
    bool? isLoading,
    String? errorMessage,
    String? successMessage,
  }) {
    return EmployeeState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      successMessage: successMessage,
    );
  }
}

class EmployeeNotifier extends StateNotifier<EmployeeState> {
  final EmployeeRemoteDataSource _dataSource;
  final Ref _ref;

  EmployeeNotifier(this._dataSource, this._ref) : super(const EmployeeState());

  String? get _businessId => _ref.read(activeBusinessIdProvider);

  static const _bizNotLoaded = 'Business not loaded yet. Please wait a moment and try again.';

  /// Returns the new employee UID on success, null on failure.
  Future<String?> addEmployee({
    required String name,
    required String email,
    required String phone,
    required String department,
    required String password,
    required String createdBy,
    String? address,
    String? city,
    String? district,
    String? stateName,
  }) async {
    final businessId = _businessId;
    if (businessId == null) {
      state = state.copyWith(isLoading: false, errorMessage: _bizNotLoaded);
      return null;
    }
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final uid = await _dataSource.addEmployee(
        data: {
          'name':       name,
          'email':      email,
          'phone':      phone,
          'department': department,
          'createdBy':  createdBy,
          'address':    address ?? '',
          'city':       city    ?? '',
          'district':   district ?? '',
          'state':      stateName ?? '',
        },
        password: password,
        businessId: businessId,
      );
      state = state.copyWith(
        isLoading: false,
        successMessage: 'Employee added successfully.',
      );
      // Invalidate so the list refreshes immediately even if Realtime hasn't fired.
      _ref.invalidate(employeesStreamProvider);
      return uid;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return null;
    }
  }

  Future<bool> updateEmployee(String id, Map<String, dynamic> data) async {
    final businessId = _businessId;
    if (businessId == null) {
      state = state.copyWith(isLoading: false, errorMessage: _bizNotLoaded);
      return false;
    }
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _dataSource.updateEmployee(id, data, businessId: businessId);
      state = state.copyWith(
        isLoading: false,
        successMessage: 'Employee updated successfully.',
      );
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> toggleStatus(String id, bool isActive) async {
    final businessId = _businessId;
    if (businessId == null) {
      state = state.copyWith(isLoading: false, errorMessage: _bizNotLoaded);
      return false;
    }
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _dataSource.toggleEmployeeStatus(id, isActive, businessId: businessId);
      state = state.copyWith(
        isLoading: false,
        successMessage: isActive ? 'Employee activated.' : 'Employee deactivated.',
      );
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> changeRole(String userUid, UserRole newRole) async {
    final businessId = _businessId;
    if (businessId == null) {
      state = state.copyWith(isLoading: false, errorMessage: _bizNotLoaded);
      return false;
    }
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      // updateMemberRole already handles the employees-record
      // deactivation/reactivation and previous_role bookkeeping centrally.
      final result = await _ref.read(businessRepositoryProvider).updateMemberRole(
        businessId: businessId,
        userUid:    userUid,
        newRole:    newRole.name,
      );
      return result.fold(
        (failure) {
          state = state.copyWith(isLoading: false, errorMessage: failure.message);
          return false;
        },
        (_) {
          _ref.invalidate(employeeCurrentRoleProvider(userUid));
          _ref.invalidate(businessAdminsProvider(businessId));
          state = state.copyWith(
            isLoading: false,
            successMessage: 'Role changed to ${newRole.displayName}.',
          );
          return true;
        },
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> resetPassword(String employeeUid, String newPassword) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _dataSource.resetPassword(employeeUid, newPassword);
      state = state.copyWith(isLoading: false, successMessage: 'Password reset successfully.');
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  void clearMessages() => state = state.copyWith();
}

final employeeNotifierProvider =
    StateNotifierProvider<EmployeeNotifier, EmployeeState>((ref) {
  return EmployeeNotifier(ref.watch(employeeRemoteDataSourceProvider), ref);
});

// ── Search ─────────────────────────────────────────────────────────────────

final employeeSearchQueryProvider = StateProvider<String>((ref) => '');

bool _matchesQuery(EmployeeModel e, String query) {
  return e.name.toLowerCase().contains(query) ||
      e.email.toLowerCase().contains(query) ||
      e.employeeId.toLowerCase().contains(query) ||
      e.department.toLowerCase().contains(query);
}

final filteredEmployeesProvider =
    Provider.autoDispose<AsyncValue<List<EmployeeModel>>>((ref) {
  final query = ref.watch(employeeSearchQueryProvider).toLowerCase();
  final employees = ref.watch(employeesStreamProvider);

  return employees.whenData((list) {
    final filtered = query.isEmpty
        ? list
        : list.where((e) => _matchesQuery(e, query)).toList();
    // Active first, then inactive — preserves order within each group
    return [
      ...filtered.where((e) => e.isActive),
      ...filtered.where((e) => !e.isActive),
    ];
  });
});
