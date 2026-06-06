import 'package:equatable/equatable.dart';

class EmployeeEntity extends Equatable {
  final String id;
  final String employeeId;  // EMP001
  final String name;
  final String email;
  final String phone;
  final String department;
  final String? profileImageUrl;
  final String? address;
  final String? city;
  final String? district;
  final String? state;
  final bool isActive;
  final double totalAssigned;
  final double totalSpent;
  final double balance;
  final String createdBy;   // Admin UID
  final DateTime createdAt;
  final DateTime? updatedAt;

  const EmployeeEntity({
    required this.id,
    required this.employeeId,
    required this.name,
    required this.email,
    required this.phone,
    required this.department,
    this.profileImageUrl,
    this.address,
    this.city,
    this.district,
    this.state,
    required this.isActive,
    required this.totalAssigned,
    required this.totalSpent,
    required this.balance,
    required this.createdBy,
    required this.createdAt,
    this.updatedAt,
  });

  @override
  List<Object?> get props => [id, employeeId, email];
}
