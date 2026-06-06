import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../shared/providers/business_context_provider.dart';
import '../../data/datasources/department_datasource.dart';
import '../../data/models/department_model.dart';

// ── Datasource ────────────────────────────────────────────────────────────────

final _deptDataSourceProvider = Provider<DepartmentDataSource>((ref) {
  return DepartmentDataSource(ref.watch(supabaseClientProvider));
});

// ── Business departments (global + own business) ──────────────────────────────

final departmentsProvider =
    FutureProvider.autoDispose<List<DepartmentModel>>((ref) async {
  final businessId = ref.watch(activeBusinessIdProvider);
  final ds = ref.watch(_deptDataSourceProvider);
  return ds.getDepartments(businessId: businessId);
});

// ── Global departments only (superadmin) ──────────────────────────────────────

final globalDepartmentsProvider =
    FutureProvider.autoDispose<List<DepartmentModel>>((ref) async {
  final ds = ref.watch(_deptDataSourceProvider);
  return ds.getGlobalDepartments();
});

// ── Notifier for create / delete ──────────────────────────────────────────────

class DepartmentNotifierState {
  final bool isLoading;
  final String? error;
  final String? success;

  const DepartmentNotifierState({
    this.isLoading = false,
    this.error,
    this.success,
  });

  DepartmentNotifierState copyWith({
    bool? isLoading,
    String? error,
    String? success,
  }) =>
      DepartmentNotifierState(
        isLoading: isLoading ?? this.isLoading,
        error:     error,
        success:   success,
      );
}

class DepartmentNotifier extends StateNotifier<DepartmentNotifierState> {
  final DepartmentDataSource _ds;
  final Ref _ref;

  DepartmentNotifier(this._ds, this._ref)
      : super(const DepartmentNotifierState());

  Future<DepartmentModel?> create({
    required String name,
    required String createdBy,
    String? businessId, // null = global (superadmin)
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      final dept = await _ds.createDepartment(
        name:       name,
        createdBy:  createdBy,
        businessId: businessId,
      );
      // Refresh the relevant list
      if (businessId == null) {
        _ref.invalidate(globalDepartmentsProvider);
      }
      _ref.invalidate(departmentsProvider);
      state = state.copyWith(
          isLoading: false, success: '\'${dept.name}\' created successfully');
      return dept;
    } catch (e) {
      final msg = e.toString().contains('unique')
          ? '\'$name\' already exists'
          : 'Failed to create department';
      state = state.copyWith(isLoading: false, error: msg);
      return null;
    }
  }

  Future<void> delete(String id) async {
    state = state.copyWith(isLoading: true);
    try {
      await _ds.deleteDepartment(id);
      _ref.invalidate(globalDepartmentsProvider);
      _ref.invalidate(departmentsProvider);
      state = state.copyWith(isLoading: false, success: 'Department removed');
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to delete');
    }
  }

  void clearMessages() => state = state.copyWith();
}

final departmentNotifierProvider =
    StateNotifierProvider<DepartmentNotifier, DepartmentNotifierState>((ref) {
  return DepartmentNotifier(ref.watch(_deptDataSourceProvider), ref);
});
