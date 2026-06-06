import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/utils/app_utils.dart';
import '../models/employee_model.dart';

abstract class EmployeeRemoteDataSource {
  Future<List<EmployeeModel>> getAllEmployees({
    required String businessId,
    bool activeOnly = false,
  });
  Stream<List<EmployeeModel>> watchAllEmployees({required String businessId, bool activeOnly = false});
  Future<EmployeeModel> getEmployeeById(String id, {required String businessId});
  Stream<EmployeeModel> watchEmployeeById(String id, {required String businessId});
  /// Fetches the employee row by Firebase UID (employees.id = Firebase UID).
  /// No business filter — each Firebase UID maps to exactly one employees row.
  Future<EmployeeModel> getEmployeeByUserId(String userId);
  Future<String> addEmployee({
    required Map<String, dynamic> data,
    required String password,
    required String businessId,
  });
  Future<void> updateEmployee(String id, Map<String, dynamic> data, {required String businessId});
  Future<void> toggleEmployeeStatus(String id, bool isActive, {required String businessId});
  Future<void> deleteEmployee(String id, {required String businessId});
  Future<void> resetPassword(String uid, String newPassword);
}

class EmployeeRemoteDataSourceImpl implements EmployeeRemoteDataSource {
  final SupabaseClient _supabase;

  const EmployeeRemoteDataSourceImpl(this._supabase);

  @override
  Future<List<EmployeeModel>> getAllEmployees({
    required String businessId,
    bool activeOnly = false,
  }) async {
    try {
      var query = _supabase
          .from('employees')
          .select()
          .eq('business_id', businessId);
      if (activeOnly) query = query.eq('is_active', true);
      final rows = await query.order('created_at', ascending: false);
      return rows.map((r) => EmployeeModel.fromJson(r)).toList();
    } on PostgrestException catch (e) {
      throw FirestoreException(e.message, code: e.code);
    }
  }

  @override
  Stream<List<EmployeeModel>> watchAllEmployees({
    required String businessId,
    bool activeOnly = false,
  }) {
    return _supabase
        .from('employees')
        .stream(primaryKey: ['id'])
        .eq('business_id', businessId)
        .order('created_at', ascending: false)
        .map((rows) {
          final seen = <String>{};
          return rows
              .map((r) => EmployeeModel.fromJson(r))
              .where((e) => seen.add(e.id))
              .where((e) => !activeOnly || e.isActive)
              .toList();
        });
  }

  @override
  Future<EmployeeModel> getEmployeeById(String id, {required String businessId}) async {
    final row = await _supabase
        .from('employees')
        .select()
        .eq('id', id)
        .eq('business_id', businessId)
        .maybeSingle();
    if (row == null) throw const FirestoreException('Employee not found.');
    return EmployeeModel.fromJson(row);
  }

  @override
  Stream<EmployeeModel> watchEmployeeById(String id, {required String businessId}) {
    return _supabase
        .from('employees')
        .stream(primaryKey: ['id'])
        .eq('business_id', businessId)
        .map((rows) {
          final match = rows.where((r) => r['id'] == id).firstOrNull;
          if (match == null) throw const FirestoreException('Employee not found.');
          return EmployeeModel.fromJson(match);
        });
  }

  @override
  Future<EmployeeModel> getEmployeeByUserId(String userId) async {
    final row = await _supabase
        .from('employees')
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (row == null) throw const FirestoreException('Employee profile not found.');
    return EmployeeModel.fromJson(row);
  }

  @override
  Future<String> addEmployee({
    required Map<String, dynamic> data,
    required String password,
    required String businessId,
  }) async {
    try {
      // 1. Create Supabase Auth account + users row via Edge Function.
      //    The edge function uses the service_role key which bypasses RLS,
      //    so it can insert the users row for the new employee's uid without
      //    triggering the "uid = fn_current_user_uid()" RLS INSERT policy.
      final uid = await _createAuthUser(
        email:      data['email'] as String,
        password:   password,
        name:       data['name'] as String?,
        role:       AppConstants.roleEmployee,
        businessId: businessId,
      );

      final employeeId = AppUtils.generateEmployeeId();
      final now        = DateTime.now().toIso8601String();

      // 3. Create employee profile (id = Supabase auth UUID)
      await _supabase.from('employees').upsert({
        'id':             uid,
        'employee_id':    employeeId,
        'user_id':        uid,
        'name':           data['name'],
        'email':          data['email'],
        'phone':          data['phone'] ?? '',
        'department':     data['department'] ?? '',
        'address':        data['address']  ?? '',
        'city':           data['city']     ?? '',
        'district':       data['district'] ?? '',
        'state':          data['state']    ?? '',
        'created_by':     data['createdBy'] ?? '',
        'business_id':    businessId,
        'total_assigned': 0.0,
        'total_spent':    0.0,
        'balance':        0.0,
        'is_active':      true,
        'created_at':     now,
      });

      // 4. Create business_members row
      await _supabase.from('business_members').upsert({
        'business_id': businessId,
        'user_uid':    uid,
        'role':        AppConstants.roleEmployee,
        'is_active':   true,
        'invited_by':  data['createdBy'] ?? '',
        'created_at':  now,
      }, onConflict: 'business_id,user_uid');

      return uid;
    } on FirestoreException {
      rethrow;
    } on PostgrestException catch (e) {
      throw FirestoreException(e.message, code: e.code);
    }
  }

  /// Calls the `create-auth-user` Supabase Edge Function which uses the
  /// service_role key server-side to create an auth account without
  /// affecting the currently signed-in admin session.
  /// Also inserts the users table row server-side to bypass RLS.
  Future<String> _createAuthUser({
    required String email,
    required String password,
    String? name,
    String? role,
    String? businessId,
  }) async {
    final response = await _supabase.functions.invoke(
      'create-auth-user',
      body: {
        'email':      email,
        'password':   password,
        if (name       != null) 'name':       name,
        if (role       != null) 'role':       role,
        if (businessId != null) 'businessId': businessId,
      },
      headers: {'Content-Type': 'application/json'},
    );

    if (response.status != 200) {
      final d = response.data;
      final error = (d is Map ? d['error'] : null)?.toString();
      throw FirestoreException(error ?? 'Failed to create user account');
    }

    final d = response.data;
    final uid = (d is Map ? d['uid'] : null)?.toString();
    if (uid == null) throw const FirestoreException('Invalid response from auth service');
    return uid;
  }

  @override
  Future<void> updateEmployee(
    String id,
    Map<String, dynamic> data, {
    required String businessId,
  }) async {
    try {
      final now = DateTime.now().toIso8601String();

      final employeeUpdate = <String, dynamic>{'updated_at': now};
      if (data.containsKey('name')) employeeUpdate['name'] = data['name'];
      if (data.containsKey('email')) employeeUpdate['email'] = data['email'];
      if (data.containsKey('phone')) employeeUpdate['phone'] = data['phone'];
      if (data.containsKey('department')) employeeUpdate['department'] = data['department'];
      if (data.containsKey('address'))  employeeUpdate['address']  = data['address'];
      if (data.containsKey('city'))     employeeUpdate['city']     = data['city'];
      if (data.containsKey('district')) employeeUpdate['district'] = data['district'];
      if (data.containsKey('state'))    employeeUpdate['state']    = data['state'];
      if (data.containsKey('profileImageUrl')) {
        employeeUpdate['profile_image_url'] = data['profileImageUrl'];
      }

      await _supabase
          .from('employees')
          .update(employeeUpdate)
          .eq('id', id)
          .eq('business_id', businessId);

      // Sync relevant fields to users table
      final usersUpdate = <String, dynamic>{};
      if (data.containsKey('name')) usersUpdate['name'] = data['name'];
      if (data.containsKey('email')) usersUpdate['email'] = data['email'];
      if (data.containsKey('profileImageUrl')) usersUpdate['photo_url'] = data['profileImageUrl'];
      if (usersUpdate.isNotEmpty) {
        await _supabase.from('users').update(usersUpdate).eq('uid', id);
      }
    } on PostgrestException catch (e) {
      throw FirestoreException(e.message, code: e.code);
    }
  }

  @override
  Future<void> toggleEmployeeStatus(
    String id,
    bool isActive, {
    required String businessId,
  }) async {
    final now = DateTime.now().toIso8601String();
    await _supabase
        .from('employees')
        .update({'is_active': isActive, 'updated_at': now})
        .eq('id', id)
        .eq('business_id', businessId);
    await _supabase.from('users').update({'is_active': isActive}).eq('uid', id);
  }

  @override
  Future<void> deleteEmployee(String id, {required String businessId}) async {
    await toggleEmployeeStatus(id, false, businessId: businessId);
  }

  @override
  Future<void> resetPassword(String uid, String newPassword) async {
    final response = await _supabase.functions.invoke(
      'update-user-password',
      body: {'uid': uid, 'newPassword': newPassword},
      headers: {'Content-Type': 'application/json'},
    );
    if (response.status != 200) {
      final d = response.data;
      final error = (d is Map ? d['error'] : null)?.toString();
      throw FirestoreException(error ?? 'Failed to reset password');
    }
  }
}
