import 'package:equatable/equatable.dart';

class UserEntity extends Equatable {
  final String uid;
  final String name;
  final String email;
  final String role;       // 'admin' | 'employee'
  final String? photoUrl;
  final String? fcmToken;
  final bool isActive;
  final bool isSuperadmin;
  final DateTime createdAt;
  final DateTime? lastLoginAt;
  // Extended profile fields (optional — populated from users table)
  final String? phone;
  final String? address;
  final String? city;
  final String? district;
  final String? state;

  const UserEntity({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.photoUrl,
    this.fcmToken,
    required this.isActive,
    this.isSuperadmin = false,
    required this.createdAt,
    this.lastLoginAt,
    this.phone,
    this.address,
    this.city,
    this.district,
    this.state,
  });

  bool get isAdmin => role == 'admin';
  bool get isEmployee => role == 'employee';

  @override
  List<Object?> get props => [uid, name, email, role, isActive, isSuperadmin];
}

