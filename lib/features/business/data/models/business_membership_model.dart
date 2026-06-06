import '../../../../core/constants/permission_matrix.dart';
import '../../domain/entities/business_membership_entity.dart';

/// Supabase model for business_members joined with businesses.
///
/// Query that produces this JSON:
/// ```
/// supabase
///   .from('business_members')
///   .select('*, businesses(name, logo_url, subscription_status, subscription_expiry_date)')
///   .eq('user_uid', uid)
///   .eq('is_active', true)
/// ```
class BusinessMembershipModel extends BusinessMembershipEntity {
  const BusinessMembershipModel({
    required super.id,
    required super.businessId,
    required super.businessName,
    required super.userUid,
    required super.role,
    required super.isActive,
    required super.joinedAt,
    super.businessLogoUrl,
    super.subscriptionStatus,
    super.subscriptionExpiryDate,
  });

  factory BusinessMembershipModel.fromJson(Map<String, dynamic> json) {
    final biz = json['businesses'] as Map<String, dynamic>? ?? {};

    return BusinessMembershipModel(
      id:              json['id']?.toString() ?? '',
      businessId:      json['business_id']?.toString() ?? '',
      businessName:    biz['name'] as String? ?? 'Unknown Business',
      businessLogoUrl: biz['logo_url'] as String?,
      userUid:         json['user_uid'] as String? ?? '',
      role:            UserRole.fromString(json['role'] as String?),
      isActive:        json['is_active'] as bool? ?? true,
      joinedAt:        json['joined_at'] != null
          ? DateTime.parse(json['joined_at'] as String)
          : DateTime.now(),
      subscriptionStatus: SubscriptionStatus.fromString(
          biz['subscription_status'] as String?),
      subscriptionExpiryDate: biz['subscription_expiry_date'] != null
          ? DateTime.tryParse(biz['subscription_expiry_date'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id':          id,
    'business_id': businessId,
    'user_uid':    userUid,
    'role':        role.name,
    'is_active':   isActive,
    'joined_at':   joinedAt.toIso8601String(),
  };

  factory BusinessMembershipModel.fromEntity(BusinessMembershipEntity e) {
    return BusinessMembershipModel(
      id:                    e.id,
      businessId:            e.businessId,
      businessName:          e.businessName,
      businessLogoUrl:       e.businessLogoUrl,
      userUid:               e.userUid,
      role:                  e.role,
      isActive:              e.isActive,
      joinedAt:              e.joinedAt,
      subscriptionStatus:    e.subscriptionStatus,
      subscriptionExpiryDate: e.subscriptionExpiryDate,
    );
  }
}
