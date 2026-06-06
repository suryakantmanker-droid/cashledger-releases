import 'package:equatable/equatable.dart';

class ExpenseEntity extends Equatable {
  final String id;
  final String expenseId;
  final String title;
  final double amount;
  final String category;
  final String? vendorName;
  final String? description;
  final DateTime expenseDate;
  final String paymentMethod;
  final List<String> billUrls;    // Firebase Storage URLs
  final String status;            // pending | approved | rejected | draft
  final String submittedBy;       // Employee UID
  final String submittedByName;
  final String? approvedBy;       // Admin UID
  final String? approvedByName;
  final String? rejectionReason;
  final DateTime? approvedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const ExpenseEntity({
    required this.id,
    required this.expenseId,
    required this.title,
    required this.amount,
    required this.category,
    this.vendorName,
    this.description,
    required this.expenseDate,
    required this.paymentMethod,
    required this.billUrls,
    required this.status,
    required this.submittedBy,
    required this.submittedByName,
    this.approvedBy,
    this.approvedByName,
    this.rejectionReason,
    this.approvedAt,
    required this.createdAt,
    this.updatedAt,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isDraft => status == 'draft';
  bool get hasBills => billUrls.isNotEmpty;

  @override
  List<Object?> get props => [id, expenseId];
}
