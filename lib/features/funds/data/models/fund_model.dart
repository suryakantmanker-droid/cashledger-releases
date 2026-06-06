import '../../domain/entities/fund_entity.dart';

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0.0;
  return 0.0;
}

DateTime? _tryParseDate(dynamic v) {
  if (v is! String) return null;
  try { return DateTime.parse(v); } catch (_) { return null; }
}

class FundModel extends FundEntity {
  const FundModel({
    required super.id,
    required super.transferId,
    required super.amount,
    required super.givenBy,
    required super.givenByName,
    required super.givenTo,
    required super.givenToName,
    required super.purpose,
    required super.paymentMode,
    super.notes,
    required super.status,
    required super.transferDate,
    required super.createdAt,
  });

  factory FundModel.fromJson(Map<String, dynamic> json) {
    return FundModel(
      id: json['id']?.toString() ?? '',
      transferId: json['transfer_id'] as String? ?? '',
      amount: _toDouble(json['amount']),
      givenBy: json['given_by'] as String? ?? '',
      givenByName: json['given_by_name'] as String? ?? '',
      givenTo: json['given_to'] as String? ?? '',
      givenToName: json['given_to_name'] as String? ?? '',
      purpose: json['purpose'] as String? ?? '',
      paymentMode: json['payment_mode'] as String? ?? '',
      notes: json['notes'] as String?,
      status: json['status'] as String? ?? 'active',
      transferDate: _tryParseDate(json['transfer_date']) ?? DateTime.now(),
      createdAt: _tryParseDate(json['created_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'transfer_id': transferId,
      'amount': amount,
      'given_by': givenBy,
      'given_by_name': givenByName,
      'given_to': givenTo,
      'given_to_name': givenToName,
      'purpose': purpose,
      'payment_mode': paymentMode,
      'notes': notes,
      'status': status,
      'transfer_date': transferDate.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}
