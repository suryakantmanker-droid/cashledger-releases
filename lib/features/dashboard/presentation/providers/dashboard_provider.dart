import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../shared/providers/business_context_provider.dart';
import '../../../expenses/presentation/providers/expense_provider.dart';
import '../../data/dashboard_stats.dart';

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0.0;
  return 0.0;
}

// ── Admin Dashboard ────────────────────────────────────────────────────────
// Uses fn_get_dashboard_stats RPC (single round-trip) + two lightweight
// supplementary queries (recent expenses, pending bill counts).
//
// FutureProvider.autoDispose:
//   • disposed when the admin dashboard is not visible — no stale data
//   • automatically re-fetches when activeBusinessId changes
//   • ref.invalidate(adminDashboardStatsProvider) in the refresh handler
//     triggers a fresh fetch

final adminDashboardStatsProvider =
    FutureProvider.autoDispose<AdminDashboardStats>((ref) async {
  final businessId = ref.watch(activeBusinessIdProvider);
  if (businessId == null) return AdminDashboardStats.empty();

  final supabase = ref.watch(supabaseClientProvider);

  // Three parallel queries — all scoped to the active business.
  // Future.wait<dynamic> avoids type inference failure across heterogeneous Supabase builders.
  final results = await Future.wait<dynamic>([
    // 1. Aggregate stats via PostgreSQL function (migration 007)
    supabase.rpc(
      'fn_get_dashboard_stats',
      params: {'p_business_id': businessId},
    ),

    // 2. 5 most recent expenses for the dashboard list
    supabase
        .from('expenses')
        .select()
        .eq('business_id', businessId)
        .order('created_at', ascending: false)
        .limit(5),

    // 3. Pending expenses (bill_urls only) to compute missing-bill count
    supabase
        .from('expenses')
        .select('bill_urls')
        .eq('business_id', businessId)
        .eq('status', AppConstants.statusPending),
  ]);

  final rpc = (results[0] as Map<String, dynamic>?) ?? {};
  final recentRows = results[1] as List<dynamic>;
  final pendingRows = results[2] as List<dynamic>;

  return AdminDashboardStats.fromRpc(rpc, recentRows, pendingRows);
});

// ── Employee Dashboard ─────────────────────────────────────────────────────
// Balance/financial data comes from the employees table (REST API, always
// accurate — kept in sync by transfer_fund and approve_expense RPCs).
// Expense counts/list come from the expense stream.
//
// Using REST for balance avoids Realtime RLS edge cases where the funds
// stream may return empty rows even when funds exist in the database.

/// Fetches balance totals directly from the employees row (REST, not Realtime).
final _employeeBalanceProvider =
    FutureProvider.autoDispose.family<Map<String, double>, String>(
        (ref, employeeId) async {
  try {
    final supabase = ref.watch(supabaseClientProvider);
    final row = await supabase
        .from('employees')
        .select('balance, total_assigned, total_spent')
        .eq('id', employeeId)
        .maybeSingle();
    if (row == null) return {'balance': 0.0, 'total_assigned': 0.0, 'total_spent': 0.0};
    return {
      'balance':        _toDouble(row['balance']),
      'total_assigned': _toDouble(row['total_assigned']),
      'total_spent':    _toDouble(row['total_spent']),
    };
  } catch (_) {
    return {'balance': 0.0, 'total_assigned': 0.0, 'total_spent': 0.0};
  }
});

final employeeDashboardStatsProvider =
    Provider.autoDispose.family<AsyncValue<EmployeeDashboardStats>, String>(
        (ref, employeeId) {
  final expensesAsync = ref.watch(employeeExpensesStreamProvider(employeeId));
  final balanceAsync  = ref.watch(_employeeBalanceProvider(employeeId));

  if (expensesAsync.isLoading || balanceAsync.isLoading) {
    return const AsyncValue.loading();
  }

  if (expensesAsync.hasError) {
    return AsyncValue.error(expensesAsync.error!, StackTrace.current);
  }

  final expenses       = expensesAsync.value!;
  final balanceData    = balanceAsync.value ?? {};
  final totalAssigned  = balanceData['total_assigned'] ?? 0.0;
  final totalSpent     = balanceData['total_spent']    ?? 0.0;
  final currentBalance = balanceData['balance']        ?? 0.0;

  final pendingCount  = expenses.where((e) => e.isPending).length;
  final approvedCount = expenses.where((e) => e.isApproved).length;
  final rejectedCount = expenses.where((e) => e.isRejected).length;

  return AsyncValue.data(EmployeeDashboardStats(
    currentBalance: currentBalance,
    totalAssigned:  totalAssigned,
    totalSpent:     totalSpent,
    pendingApprovals:  pendingCount,
    approvedExpenses:  approvedCount,
    rejectedExpenses:  rejectedCount,
    recentExpenses:    expenses.take(5).toList(),
  ));
});
