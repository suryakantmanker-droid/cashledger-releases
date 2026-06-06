import '../../domain/entities/employee_entity.dart';

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0.0;
  return 0.0;
}

DateTime? _tryParseDate(dynamic v) {
  if (v is! String) return null;
  try { return DateTime.parse(v); } catch (_) { return null; }
}

class EmployeeModel extends EmployeeEntity {
  const EmployeeModel({
    required super.id,
    required super.employeeId,
    required super.name,
    required super.email,
    required super.phone,
    required super.department,
    super.profileImageUrl,
    super.address,
    super.city,
    super.district,
    super.state,
    required super.isActive,
    required super.totalAssigned,
    required super.totalSpent,
    required super.balance,
    required super.createdBy,
    required super.createdAt,
    super.updatedAt,
  });

  factory EmployeeModel.fromJson(Map<String, dynamic> json) {
    return EmployeeModel(
      id: json['id'] as String? ?? '',
      employeeId: json['employee_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      department: json['department'] as String? ?? '',
      profileImageUrl: json['profile_image_url'] as String?,
      address:  json['address']  as String?,
      city:     json['city']     as String?,
      district: json['district'] as String?,
      state:    json['state']    as String?,
      isActive: json['is_active'] as bool? ?? true,
      totalAssigned: _toDouble(json['total_assigned']),
      totalSpent: _toDouble(json['total_spent']),
      balance: _toDouble(json['balance']),
      createdBy: json['created_by'] as String? ?? '',
      createdAt: _tryParseDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _tryParseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'employee_id': employeeId,
      'name': name,
      'email': email,
      'phone': phone,
      'department': department,
      'profile_image_url': profileImageUrl,
      'address':  address,
      'city':     city,
      'district': district,
      'state':    state,
      'is_active': isActive,
      'total_assigned': totalAssigned,
      'total_spent': totalSpent,
      'balance': balance,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  EmployeeModel copyWith({
    String? name,
    String? email,
    String? phone,
    String? department,
    String? profileImageUrl,
    String? address,
    String? city,
    String? district,
    String? state,
    bool? isActive,
    double? totalAssigned,
    double? totalSpent,
    double? balance,
  }) {
    return EmployeeModel(
      id: id,
      employeeId: employeeId,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      department: department ?? this.department,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      address:  address  ?? this.address,
      city:     city     ?? this.city,
      district: district ?? this.district,
      state:    state    ?? this.state,
      isActive: isActive ?? this.isActive,
      totalAssigned: totalAssigned ?? this.totalAssigned,
      totalSpent: totalSpent ?? this.totalSpent,
      balance: balance ?? this.balance,
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
