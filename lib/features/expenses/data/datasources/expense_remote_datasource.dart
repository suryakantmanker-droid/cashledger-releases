import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/utils/app_utils.dart';
import '../models/expense_model.dart';

abstract class ExpenseRemoteDataSource {
  Stream<List<ExpenseModel>> watchExpensesByEmployee(
    String employeeId, {
    required String businessId,
  });
  Stream<List<ExpenseModel>> watchAllPendingExpenses({required String businessId});
  Stream<List<ExpenseModel>> watchAllExpenses({required String businessId});
  Future<List<ExpenseModel>> getExpensesByEmployee(
    String employeeId, {
    required String businessId,
  });
  Future<ExpenseModel> getExpenseById(String id, {required String businessId});
  Future<String> addExpense(Map<String, dynamic> data, {required String businessId});
  Future<void> updateExpense(String id, Map<String, dynamic> data, {required String businessId});
  Future<void> approveExpense({
    required String expenseId,
    required String approvedBy,
    required String approvedByName,
    required String businessId,
  });
  Future<void> rejectExpense({
    required String expenseId,
    required String rejectedBy,
    required String rejectedByName,
    required String reason,
    required String businessId,
  });
  Future<void> deleteExpense(String id, {required String businessId});
  Future<List<ExpenseModel>> getExpensesForReport({
    required String? employeeId,
    required DateTime? startDate,
    required DateTime? endDate,
    String? category,
    String? status,
    required String businessId,
  });
}

class ExpenseRemoteDataSourceImpl implements ExpenseRemoteDataSource {
  final SupabaseClient _supabase;
  const ExpenseRemoteDataSourceImpl(this._supabase);

  // ── Streams ────────────────────────────────────────────────────────────────
  // Supabase Realtime only supports one .eq() filter on a stream.
  // Primary filter is always business_id (data isolation); secondary filters
  // (status, submitted_by) are applied in Dart.

  @override
  Stream<List<ExpenseModel>> watchExpensesByEmployee(
    String employeeId, {
    required String businessId,
  }) {
    return _supabase
        .from('expenses')
        .stream(primaryKey: ['id'])
        .eq('business_id', businessId)
        .order('created_at', ascending: false)
        .map((rows) => rows
            .where((r) => r['submitted_by'] == employeeId)
            .map((r) => ExpenseModel.fromJson(r))
            .toList());
  }

  @override
  Stream<List<ExpenseModel>> watchAllPendingExpenses({required String businessId}) {
    return _supabase
        .from('expenses')
        .stream(primaryKey: ['id'])
        .eq('business_id', businessId)
        .order('created_at', ascending: false)
        .map((rows) => rows
            .where((r) => r['status'] == AppConstants.statusPending)
            .map((r) => ExpenseModel.fromJson(r))
            .toList());
  }

  @override
  Stream<List<ExpenseModel>> watchAllExpenses({required String businessId}) {
    return _supabase
        .from('expenses')
        .stream(primaryKey: ['id'])
        .eq('business_id', businessId)
        .order('created_at', ascending: false)
        .limit(AppConstants.pageSize)
        .map((rows) => rows.map((r) => ExpenseModel.fromJson(r)).toList());
  }

  // ── Futures ────────────────────────────────────────────────────────────────

  @override
  Future<List<ExpenseModel>> getExpensesByEmployee(
    String employeeId, {
    required String businessId,
  }) async {
    final rows = await _supabase
        .from('expenses')
        .select()
        .eq('business_id', businessId)
        .eq('submitted_by', employeeId)
        .order('created_at', ascending: false);
    return rows.map((r) => ExpenseModel.fromJson(r)).toList();
  }

  @override
  Future<ExpenseModel> getExpenseById(String id, {required String businessId}) async {
    final row = await _supabase
        .from('expenses')
        .select()
        .eq('id', id)
        .eq('business_id', businessId)
        .maybeSingle();
    if (row == null) throw const FirestoreException('Expense not found.');
    return ExpenseModel.fromJson(row);
  }

  @override
  Future<String> addExpense(
    Map<String, dynamic> data, {
    required String businessId,
  }) async {
    try {
      final now = DateTime.now().toIso8601String();
      final expenseId = AppUtils.generateExpenseId();

      final billUrls = data['billUrls'] as List? ?? [];
      final expenseDateRaw = data['expenseDate'];
      final expenseDateStr = expenseDateRaw is DateTime
          ? expenseDateRaw.toIso8601String()
          : expenseDateRaw?.toString() ?? now;

      final inserted = await _supabase.from('expenses').insert({
        'expense_id': expenseId,
        'title': data['title'],
        'amount': data['amount'],
        'category': data['category'],
        'vendor_name': data['vendorName'],
        'description': data['description'],
        'expense_date': expenseDateStr,
        'payment_method': data['paymentMethod'] ?? '',
        'bill_urls': billUrls,
        'status': data['status'] ?? AppConstants.statusPending,
        'submitted_by': data['submittedBy'],
        'submitted_by_name': data['submittedByName'] ?? '',
        'business_id': businessId,
        'created_at': now,
        'updated_at': now,
      }).select('id').single();

      return inserted['id'].toString();
    } on PostgrestException catch (e) {
      throw FirestoreException(e.message, code: e.code);
    }
  }

  @override
  Future<void> updateExpense(
    String id,
    Map<String, dynamic> data, {
    required String businessId,
  }) async {
    try {
      final now = DateTime.now().toIso8601String();
      final update = <String, dynamic>{'updated_at': now};
      data.forEach((key, value) {
        if (key == 'businessId') return; // never overwrite business_id
        final snakeKey = _toSnakeCase(key);
        update[snakeKey] = value is DateTime ? value.toIso8601String() : value;
      });
      await _supabase
          .from('expenses')
          .update(update)
          .eq('id', id)
          .eq('business_id', businessId);
    } on PostgrestException catch (e) {
      throw FirestoreException(e.message, code: e.code);
    }
  }

  @override
  Future<void> approveExpense({
    required String expenseId,
    required String approvedBy,
    required String approvedByName,
    required String businessId,
  }) async {
    // Atomic PostgreSQL function (migration 009) — scoped to business
    await _supabase.rpc('approve_expense', params: {
      'p_expense_id': expenseId,
      'p_approved_by': approvedBy,
      'p_approved_by_name': approvedByName,
      'p_business_id': businessId,
    });
  }

  @override
  Future<void> rejectExpense({
    required String expenseId,
    required String rejectedBy,
    required String rejectedByName,
    required String reason,
    required String businessId,
  }) async {
    await _supabase.from('expenses').update({
      'status': AppConstants.statusRejected,
      'approved_by': rejectedBy,
      'approved_by_name': rejectedByName,
      'rejection_reason': reason,
      'updated_at': DateTime.now().toIso8601String(),
    })
        .eq('id', expenseId)
        .eq('business_id', businessId);
  }

  @override
  Future<void> deleteExpense(String id, {required String businessId}) async {
    await _supabase
        .from('expenses')
        .delete()
        .eq('id', id)
        .eq('business_id', businessId);
  }

  @override
  Future<List<ExpenseModel>> getExpensesForReport({
    required String? employeeId,
    required DateTime? startDate,
    required DateTime? endDate,
    String? category,
    String? status,
    required String businessId,
  }) async {
    // Build query with server-side business + employee filters, then apply
    // date/category/status filters in Dart (PostgREST range queries need timestamps).
    var query = _supabase.from('expenses').select().eq('business_id', businessId);

    if (employeeId != null) {
      query = query.eq('submitted_by', employeeId);
    }

    final rows = await query;
    var results = rows.map((r) => ExpenseModel.fromJson(r)).toList();

    if (status != null) results = results.where((e) => e.status == status).toList();
    if (category != null) results = results.where((e) => e.category == category).toList();
    if (startDate != null) {
      results = results.where((e) => !e.expenseDate.isBefore(startDate)).toList();
    }
    if (endDate != null) {
      results = results.where((e) => !e.expenseDate.isAfter(endDate)).toList();
    }

    results.sort((a, b) => b.expenseDate.compareTo(a.expenseDate));
    return results;
  }

  String _toSnakeCase(String camel) {
    final exp = RegExp(r'(?<=[a-z])[A-Z]');
    return camel.replaceAllMapped(exp, (m) => '_${m.group(0)!.toLowerCase()}');
  }
}
