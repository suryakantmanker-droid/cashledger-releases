import 'package:equatable/equatable.dart';

class FundEntity extends Equatable {
  final String id;
  final String transferId;
  final double amount;
  final String givenBy;       // Admin UID
  final String givenByName;
  final String givenTo;       // Employee UID
  final String givenToName;
  final String purpose;
  final String paymentMode;
  final String? notes;
  final String status;
  final DateTime transferDate;
  final DateTime createdAt;

  const FundEntity({
    required this.id,
    required this.transferId,
    required this.amount,
    required this.givenBy,
    required this.givenByName,
    required this.givenTo,
    required this.givenToName,
    required this.purpose,
    required this.paymentMode,
    this.notes,
    required this.status,
    required this.transferDate,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [id, transferId];
}
