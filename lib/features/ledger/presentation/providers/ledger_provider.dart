import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../shared/providers/business_context_provider.dart';
import '../../data/models/ledger_model.dart';

// Supabase stream supports one .eq() — business_id is the security-critical filter.
// Employee filter applied in Dart map.
final ledgerByEmployeeProvider =
    StreamProvider.autoDispose.family<List<LedgerModel>, String>((ref, employeeId) {
  final businessId = ref.watch(activeBusinessIdProvider);
  if (businessId == null) return Stream.value(const []);

  return ref
      .watch(supabaseClientProvider)
      .from('ledger')
      .stream(primaryKey: ['id'])
      .eq('business_id', businessId)
      .order('created_at', ascending: false)
      .map((rows) => rows
          .where((r) => r['employee_id'] == employeeId)
          .map((r) => LedgerModel.fromJson(r))
          .toList());
});

/// REST-based ledger fetch for employees — avoids Realtime RLS JWT issues.
/// Pull-to-refresh triggers a new fetch via ref.invalidate.
final employeeLedgerRestProvider =
    FutureProvider.autoDispose.family<List<LedgerModel>, String>((ref, employeeId) async {
  final businessId = ref.watch(activeBusinessIdProvider);
  if (businessId == null) return [];
  try {
    final rows = await ref
        .watch(supabaseClientProvider)
        .from('ledger')
        .select()
        .eq('business_id', businessId)
        .eq('employee_id', employeeId)
        .order('created_at', ascending: false);
    return (rows as List<dynamic>).map((r) => LedgerModel.fromJson(r as Map<String, dynamic>)).toList();
  } catch (e, st) {
    debugPrint('[LedgerProvider] fetch error: $e\n$st');
    rethrow;
  }
});

final allLedgerProvider = StreamProvider.autoDispose<List<LedgerModel>>((ref) {
  final businessId = ref.watch(activeBusinessIdProvider);
  if (businessId == null) return Stream.value(const []);

  return ref
      .watch(supabaseClientProvider)
      .from('ledger')
      .stream(primaryKey: ['id'])
      .eq('business_id', businessId)
      .order('created_at', ascending: false)
      .limit(AppConstants.pageSize)
      .map((rows) => rows.map((r) => LedgerModel.fromJson(r)).toList());
});

// Summary stats for an employee
class LedgerSummary {
  final double totalCredit;
  final double totalDebit;
  final double currentBalance;

  const LedgerSummary({
    required this.totalCredit,
    required this.totalDebit,
    required this.currentBalance,
  });
}

final ledgerSummaryProvider =
    Provider.autoDispose.family<AsyncValue<LedgerSummary>, String>((ref, employeeId) {
  final ledger = ref.watch(ledgerByEmployeeProvider(employeeId));

  return ledger.whenData((entries) => _buildSummary(entries));
});

/// REST-based summary for employees — avoids Realtime RLS JWT issues.
final employeeLedgerSummaryProvider =
    Provider.autoDispose.family<AsyncValue<LedgerSummary>, String>((ref, employeeId) {
  final ledger = ref.watch(employeeLedgerRestProvider(employeeId));

  return ledger.whenData((entries) => _buildSummary(entries));
});

LedgerSummary _buildSummary(List<LedgerModel> entries) {
  double totalCredit = 0;
  double totalDebit = 0;

  for (final entry in entries) {
    if (entry.isCredit) {
      totalCredit += entry.amount;
    } else {
      totalDebit += entry.amount;
    }
  }

  final balance = entries.isNotEmpty ? entries.first.balanceAfter : 0.0;

  return LedgerSummary(
    totalCredit: totalCredit,
    totalDebit: totalDebit,
    currentBalance: balance,
  );
}
