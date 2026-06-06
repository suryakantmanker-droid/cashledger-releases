import '../../domain/entities/expense_entity.dart';

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0.0;
  return 0.0;
}

DateTime? _tryParseDate(dynamic value) {
  if (value is! String) return null;
  try {
    return DateTime.parse(value);
  } catch (_) {
    return null;
  }
}

class ExpenseModel extends ExpenseEntity {
  const ExpenseModel({
    required super.id,
    required super.expenseId,
    required super.title,
    required super.amount,
    required super.category,
    super.vendorName,
    super.description,
    required super.expenseDate,
    required super.paymentMethod,
    required super.billUrls,
    required super.status,
    required super.submittedBy,
    required super.submittedByName,
    super.approvedBy,
    super.approvedByName,
    super.rejectionReason,
    super.approvedAt,
    required super.createdAt,
    super.updatedAt,
  });

  factory ExpenseModel.fromJson(Map<String, dynamic> json) {
    return ExpenseModel(
      id: json['id']?.toString() ?? '',
      expenseId: json['expense_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      amount: _toDouble(json['amount']),
      category: json['category'] as String? ?? '',
      vendorName: json['vendor_name'] as String?,
      description: json['description'] as String?,
      expenseDate: _tryParseDate(json['expense_date']) ?? DateTime.now(),
      paymentMethod: json['payment_method'] as String? ?? '',
      billUrls: (json['bill_urls'] as List<dynamic>?)?.whereType<String>().toList() ?? [],
      status: json['status'] as String? ?? 'pending',
      submittedBy: json['submitted_by'] as String? ?? '',
      submittedByName: json['submitted_by_name'] as String? ?? '',
      approvedBy: json['approved_by'] as String?,
      approvedByName: json['approved_by_name'] as String?,
      rejectionReason: json['rejection_reason'] as String?,
      approvedAt: _tryParseDate(json['approved_at']),
      createdAt: _tryParseDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _tryParseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'expense_id': expenseId,
      'title': title,
      'amount': amount,
      'category': category,
      'vendor_name': vendorName,
      'description': description,
      'expense_date': expenseDate.toIso8601String(),
      'payment_method': paymentMethod,
      'bill_urls': billUrls,
      'status': status,
      'submitted_by': submittedBy,
      'submitted_by_name': submittedByName,
      'approved_by': approvedBy,
      'approved_by_name': approvedByName,
      'rejection_reason': rejectionReason,
      'approved_at': approvedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  ExpenseModel copyWith({
    String? title,
    double? amount,
    String? category,
    String? vendorName,
    String? description,
    DateTime? expenseDate,
    String? paymentMethod,
    List<String>? billUrls,
    String? status,
    String? approvedBy,
    String? approvedByName,
    String? rejectionReason,
    DateTime? approvedAt,
  }) {
    return ExpenseModel(
      id: id,
      expenseId: expenseId,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      vendorName: vendorName ?? this.vendorName,
      description: description ?? this.description,
      expenseDate: expenseDate ?? this.expenseDate,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      billUrls: billUrls ?? this.billUrls,
      status: status ?? this.status,
      submittedBy: submittedBy,
      submittedByName: submittedByName,
      approvedBy: approvedBy ?? this.approvedBy,
      approvedByName: approvedByName ?? this.approvedByName,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      approvedAt: approvedAt ?? this.approvedAt,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
