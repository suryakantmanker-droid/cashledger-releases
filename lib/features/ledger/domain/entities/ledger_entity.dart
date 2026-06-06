import 'package:equatable/equatable.dart';

class LedgerEntity extends Equatable {
  final String id;
  final String employeeId;
  final String employeeName;
  final String type;          // 'credit' | 'debit'
  final double amount;
  final double balanceAfter;
  final String remarks;
  final String referenceId;   // Fund transfer ID or Expense ID
  final String referenceType; // 'fund_transfer' | 'expense'
  final DateTime date;
  final DateTime createdAt;

  const LedgerEntity({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    required this.remarks,
    required this.referenceId,
    required this.referenceType,
    required this.date,
    required this.createdAt,
  });

  bool get isCredit => type == 'credit';
  bool get isDebit => type == 'debit';

  @override
  List<Object?> get props => [id, referenceId];
}
