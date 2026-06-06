import '../../domain/entities/sale_entity.dart';

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0.0;
  return 0.0;
}

DateTime _parseDate(dynamic v) {
  if (v is String) {
    try {
      return DateTime.parse(v);
    } catch (_) {}
  }
  return DateTime.now();
}

class SaleModel extends SaleEntity {
  const SaleModel({
    required super.id,
    required super.saleId,
    required super.employeeId,
    required super.employeeName,
    required super.amount,
    required super.itemDescription,
    super.buyerName,
    super.notes,
    required super.proofUrls,
    required super.saleDate,
    required super.businessId,
    required super.createdAt,
  });

  factory SaleModel.fromJson(Map<String, dynamic> json) {
    return SaleModel(
      id: json['id']?.toString() ?? '',
      saleId: json['sale_id'] as String? ?? '',
      employeeId: json['employee_id'] as String? ?? '',
      employeeName: json['employee_name'] as String? ?? '',
      amount: _toDouble(json['amount']),
      itemDescription: json['item_description'] as String? ?? '',
      buyerName: json['buyer_name'] as String?,
      notes: json['notes'] as String?,
      proofUrls: (json['proof_urls'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
          [],
      saleDate: _parseDate(json['sale_date']),
      businessId: json['business_id']?.toString() ?? '',
      createdAt: _parseDate(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sale_id': saleId,
      'employee_id': employeeId,
      'employee_name': employeeName,
      'amount': amount,
      'item_description': itemDescription,
      'buyer_name': buyerName,
      'notes': notes,
      'proof_urls': proofUrls,
      'sale_date': saleDate.toIso8601String(),
      'business_id': businessId,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
