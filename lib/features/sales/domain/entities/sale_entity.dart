import 'package:equatable/equatable.dart';

class SaleEntity extends Equatable {
  final String id;
  final String saleId;
  final String employeeId;
  final String employeeName;
  final double amount;
  final String itemDescription;
  final String? buyerName;
  final String? notes;
  final List<String> proofUrls;
  final DateTime saleDate;
  final String businessId;
  final DateTime createdAt;

  const SaleEntity({
    required this.id,
    required this.saleId,
    required this.employeeId,
    required this.employeeName,
    required this.amount,
    required this.itemDescription,
    this.buyerName,
    this.notes,
    required this.proofUrls,
    required this.saleDate,
    required this.businessId,
    required this.createdAt,
  });

  bool get hasProof => proofUrls.isNotEmpty;

  @override
  List<Object?> get props => [id, saleId];
}
