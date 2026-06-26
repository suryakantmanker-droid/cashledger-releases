import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/site_assignment_model.dart';
import '../models/site_model.dart';

class SiteDataSource {
  final SupabaseClient _supabase;
  const SiteDataSource(this._supabase);

  /// Returns active sites for [businessId].
  Future<List<SiteModel>> getSites(String businessId) async {
    final rows = await _supabase
        .from('sites')
        .select()
        .eq('business_id', businessId)
        .eq('is_active', true)
        .order('name');
    return rows.map((r) => SiteModel.fromJson(r)).toList();
  }

  /// Creates a site for [businessId].
  Future<SiteModel> createSite({
    required String name,
    required String address,
    required String businessId,
    required String createdBy,
  }) async {
    final row = await _supabase.from('sites').insert({
      'name':        name.trim(),
      'address':     address.trim(),
      'business_id': businessId,
      'created_by':  createdBy,
    }).select().single();
    return SiteModel.fromJson(row);
  }

  /// Soft-delete (set is_active = false).
  Future<void> deleteSite(String id) async {
    await _supabase.from('sites').update({'is_active': false}).eq('id', id);
    debugPrint('[SiteDS] Deleted site $id');
  }

  /// The employee's current (open) site assignment, if any.
  Future<SiteAssignmentModel?> getCurrentAssignment(String employeeId) async {
    final row = await _supabase
        .from('employee_site_assignments')
        .select('*, sites(name, address)')
        .eq('employee_id', employeeId)
        .isFilter('end_date', null)
        .maybeSingle();
    return row != null ? SiteAssignmentModel.fromJson(row) : null;
  }

  /// Full assignment history for the employee, most recent first.
  Future<List<SiteAssignmentModel>> getAssignmentHistory(String employeeId) async {
    final rows = await _supabase
        .from('employee_site_assignments')
        .select('*, sites(name, address)')
        .eq('employee_id', employeeId)
        .order('start_date', ascending: false);
    return rows.map((r) => SiteAssignmentModel.fromJson(r)).toList();
  }

  /// Atomically closes the current assignment and opens a new one via RPC.
  Future<void> changeEmployeeSite({
    required String employeeId,
    required String businessId,
    required String newSiteId,
    required String assignedBy,
  }) async {
    await _supabase.rpc('fn_change_employee_site', params: {
      'p_employee_id': employeeId,
      'p_business_id': businessId,
      'p_new_site_id': newSiteId,
      'p_assigned_by': assignedBy,
    });
  }
}
