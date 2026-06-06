import '../../domain/entities/user_entity.dart';

class UserModel extends UserEntity {
  const UserModel({
    required super.uid,
    required super.name,
    required super.email,
    required super.role,
    super.photoUrl,
    super.fcmToken,
    required super.isActive,
    super.isSuperadmin = false,
    required super.createdAt,
    super.lastLoginAt,
    super.phone,
    super.address,
    super.city,
    super.district,
    super.state,
  });

  // ── Supabase ──────────────────────────────────────────────────────────────

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      uid:          json['uid'] as String? ?? '',
      name:         json['name'] as String? ?? '',
      email:        json['email'] as String? ?? '',
      role:         json['role'] as String? ?? 'employee',
      photoUrl:     json['photo_url'] as String?,
      fcmToken:     json['fcm_token'] as String?,
      isActive:     json['is_active'] as bool? ?? true,
      isSuperadmin: json['is_superadmin'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      lastLoginAt: json['last_login_at'] != null
          ? DateTime.parse(json['last_login_at'] as String)
          : null,
      phone:    json['phone']    as String?,
      address:  json['address']  as String?,
      city:     json['city']     as String?,
      district: json['district'] as String?,
      state:    json['state']    as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid':          uid,
      'name':         name,
      'email':        email,
      'role':         role,
      'photo_url':    photoUrl,
      'fcm_token':    fcmToken,
      'is_active':    isActive,
      'is_superadmin': isSuperadmin,
      'created_at':   createdAt.toIso8601String(),
      'last_login_at': lastLoginAt?.toIso8601String(),
    };
  }

  UserModel copyWith({
    String? name,
    String? email,
    String? role,
    String? photoUrl,
    String? fcmToken,
    bool? isActive,
    bool? isSuperadmin,
    DateTime? lastLoginAt,
    String? phone,
    String? address,
    String? city,
    String? district,
    String? state,
  }) {
    return UserModel(
      uid:          uid,
      name:         name         ?? this.name,
      email:        email        ?? this.email,
      role:         role         ?? this.role,
      photoUrl:     photoUrl     ?? this.photoUrl,
      fcmToken:     fcmToken     ?? this.fcmToken,
      isActive:     isActive     ?? this.isActive,
      isSuperadmin: isSuperadmin ?? this.isSuperadmin,
      createdAt:    createdAt,
      lastLoginAt:  lastLoginAt  ?? this.lastLoginAt,
      phone:        phone        ?? this.phone,
      address:      address      ?? this.address,
      city:         city         ?? this.city,
      district:     district     ?? this.district,
      state:        state        ?? this.state,
    );
  }

  factory UserModel.fromEntity(UserEntity entity) {
    return UserModel(
      uid:          entity.uid,
      name:         entity.name,
      email:        entity.email,
      role:         entity.role,
      photoUrl:     entity.photoUrl,
      fcmToken:     entity.fcmToken,
      isActive:     entity.isActive,
      isSuperadmin: entity.isSuperadmin,
      createdAt:    entity.createdAt,
      lastLoginAt:  entity.lastLoginAt,
      phone:        entity.phone,
      address:      entity.address,
      city:         entity.city,
      district:     entity.district,
      state:        entity.state,
    );
  }
}
