import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/department_model.dart';

class DepartmentDataSource {
  final SupabaseClient _supabase;
  const DepartmentDataSource(this._supabase);

  /// Returns global + business-specific departments merged and sorted.
  Future<List<DepartmentModel>> getDepartments({String? businessId}) async {
    final rows = businessId != null
        ? await _supabase
            .from('departments')
            .select()
            .or('business_id.is.null,business_id.eq.$businessId')
            .eq('is_active', true)
            .order('name')
        : await _supabase
            .from('departments')
            .select()
            .isFilter('business_id', null)
            .eq('is_active', true)
            .order('name');

    return rows
        .map((r) => DepartmentModel.fromJson(r))
        .toList();
  }

  /// Returns only global departments (superadmin view).
  Future<List<DepartmentModel>> getGlobalDepartments() async {
    final rows = await _supabase
        .from('departments')
        .select()
        .isFilter('business_id', null)
        .eq('is_active', true)
        .order('name');
    return rows.map((r) => DepartmentModel.fromJson(r)).toList();
  }

  /// Creates a department. Pass businessId=null for global (superadmin only).
  Future<DepartmentModel> createDepartment({
    required String name,
    required String createdBy,
    String? businessId,
  }) async {
    final row = await _supabase.from('departments').insert({
      'name':        name.trim(),
      'business_id': businessId,
      'created_by':  createdBy,
    }).select().single();
    return DepartmentModel.fromJson(row);
  }

  /// Soft-delete (set is_active = false).
  Future<void> deleteDepartment(String id) async {
    await _supabase
        .from('departments')
        .update({'is_active': false})
        .eq('id', id);
    debugPrint('[DeptDS] Deleted department $id');
  }
}
