import '../../domain/entities/ledger_entity.dart';

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0.0;
  return 0.0;
}

DateTime? _tryParseDate(dynamic v) {
  if (v is! String) return null;
  try { return DateTime.parse(v); } catch (_) { return null; }
}

class LedgerModel extends LedgerEntity {
  const LedgerModel({
    required super.id,
    required super.employeeId,
    required super.employeeName,
    required super.type,
    required super.amount,
    required super.balanceAfter,
    required super.remarks,
    required super.referenceId,
    required super.referenceType,
    required super.date,
    required super.createdAt,
  });

  factory LedgerModel.fromJson(Map<String, dynamic> json) {
    return LedgerModel(
      id: json['id']?.toString() ?? '',
      employeeId: json['employee_id'] as String? ?? '',
      employeeName: json['employee_name'] as String? ?? '',
      type: json['type'] as String? ?? 'credit',
      amount: _toDouble(json['amount']),
      balanceAfter: _toDouble(json['balance_after']),
      remarks: json['remarks'] as String? ?? '',
      referenceId: json['reference_id'] as String? ?? '',
      referenceType: json['reference_type'] as String? ?? '',
      date: _tryParseDate(json['date']) ?? DateTime.now(),
      createdAt: _tryParseDate(json['created_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'employee_id': employeeId,
      'employee_name': employeeName,
      'type': type,
      'amount': amount,
      'balance_after': balanceAfter,
      'remarks': remarks,
      'reference_id': referenceId,
      'reference_type': referenceType,
      'date': date.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}
