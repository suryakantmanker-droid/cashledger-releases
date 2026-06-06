import '../../expenses/data/models/expense_model.dart';

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0.0;
  return 0.0;
}

int _toInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

class AdminDashboardStats {
  final double totalAssigned;   // Phase 3: populated from funds migration
  final double totalSpent;
  final double totalBalance;    // Phase 3: totalAssigned - totalSpent
  final int totalEmployees;
  final int activeEmployees;
  final int pendingApprovals;
  final int missingBills;
  final List<ExpenseModel> recentExpenses;

  const AdminDashboardStats({
    required this.totalAssigned,
    required this.totalSpent,
    required this.totalBalance,
    required this.totalEmployees,
    required this.activeEmployees,
    required this.pendingApprovals,
    required this.missingBills,
    required this.recentExpenses,
  });

  factory AdminDashboardStats.empty() => const AdminDashboardStats(
    totalAssigned: 0,
    totalSpent: 0,
    totalBalance: 0,
    totalEmployees: 0,
    activeEmployees: 0,
    pendingApprovals: 0,
    missingBills: 0,
    recentExpenses: [],
  );

  /// Constructs from fn_get_dashboard_stats RPC result + supplementary queries.
  ///
  /// [rpc]         — the JSON map returned by the RPC
  /// [recentRows]  — rows from a .limit(5) expenses select
  /// [pendingRows] — rows from a status=pending expenses select (bill_urls only)
  factory AdminDashboardStats.fromRpc(
    Map<String, dynamic> rpc,
    List<dynamic> recentRows,
    List<dynamic> pendingRows,
  ) {
    final totalEmployees = _toInt(rpc['total_employees']);
    final totalSpent = _toDouble(rpc['total_approved_amount']);
    final pendingApprovals = _toInt(rpc['pending_approvals']);

    final recentExpenses = recentRows
        .map((r) => ExpenseModel.fromJson(r as Map<String, dynamic>))
        .toList();

    final missingBills = pendingRows
        .where((r) => ((r['bill_urls'] as List?) ?? []).isEmpty)
        .length;

    return AdminDashboardStats(
      totalAssigned: 0.0,   // Phase 3: funds not yet migrated
      totalSpent: totalSpent,
      totalBalance: 0.0,    // Phase 3
      totalEmployees: totalEmployees,
      activeEmployees: totalEmployees, // Phase 3: distinguish active count
      pendingApprovals: pendingApprovals,
      missingBills: missingBills,
      recentExpenses: recentExpenses,
    );
  }
}

class EmployeeDashboardStats {
  final double currentBalance;
  final double totalAssigned;
  final double totalSpent;
  final int pendingApprovals;
  final int approvedExpenses;
  final int rejectedExpenses;
  final List<ExpenseModel> recentExpenses;

  const EmployeeDashboardStats({
    required this.currentBalance,
    required this.totalAssigned,
    required this.totalSpent,
    required this.pendingApprovals,
    required this.approvedExpenses,
    required this.rejectedExpenses,
    required this.recentExpenses,
  });
}
