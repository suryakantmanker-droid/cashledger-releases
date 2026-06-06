import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/permission_matrix.dart';
import '../../../../core/errors/exceptions.dart';
import '../models/business_membership_model.dart';

abstract class BusinessRemoteDataSource {
  /// Returns all active memberships for [userUid], joined with business info.
  Future<List<BusinessMembershipModel>> getMembershipsForUser(String userUid);

  /// Returns ALL businesses as virtual owner memberships for the superadmin.
  Future<List<BusinessMembershipModel>> getAllBusinessesAsSuperadmin(String superadminUid);

  /// Adds [userUid] to [businessId] with the given [role].
  Future<BusinessMembershipModel> addMember({
    required String businessId,
    required String userUid,
    required String role,
    String? invitedBy,
  });

  /// Updates a member's role within a business.
  Future<void> updateMemberRole({
    required String businessId,
    required String userUid,
    required String newRole,
  });

  /// Deactivates a member (soft remove — preserves audit trail).
  Future<void> deactivateMember({
    required String businessId,
    required String userUid,
  });
}

class BusinessRemoteDataSourceImpl implements BusinessRemoteDataSource {
  final SupabaseClient _supabase;

  const BusinessRemoteDataSourceImpl(this._supabase);

  @override
  Future<List<BusinessMembershipModel>> getMembershipsForUser(
      String userUid) async {
    try {
      debugPrint('[BusinessDS] Fetching memberships for uid=$userUid');

      final rows = await _supabase
          .from(SupabaseTables.businessMembers)
          .select('*, ${SupabaseTables.businesses}(name, logo_url, settings, subscription_status, subscription_expiry_date)')
          .eq('user_uid', userUid)
          .eq('is_active', true)
          .order('joined_at', ascending: true);

      final memberships = (rows as List<dynamic>)
          .map((e) => BusinessMembershipModel.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList();

      debugPrint('[BusinessDS] Found ${memberships.length} memberships');
      return memberships;
    } on PostgrestException catch (e) {
      debugPrint('[BusinessDS] Supabase error: ${e.message}');
      throw ServerException('Failed to load business memberships: ${e.message}');
    } catch (e) {
      debugPrint('[BusinessDS] Unexpected error: $e');
      throw ServerException('Failed to load business memberships: $e');
    }
  }

  @override
  Future<List<BusinessMembershipModel>> getAllBusinessesAsSuperadmin(
      String superadminUid) async {
    try {
      debugPrint('[BusinessDS] Superadmin: loading all businesses');
      final rows = await _supabase
          .from(SupabaseTables.businesses)
          .select('id, name, logo_url, is_active, created_at')
          .order('created_at', ascending: false);

      return (rows as List<dynamic>).map((b) {
        // Build a synthetic membership so the rest of the app works unchanged.
        // Superadmin is treated as 'owner' of every business.
        return BusinessMembershipModel(
          id:              'superadmin_${b['id']}',
          businessId:      b['id'] as String,
          businessName:    b['name'] as String? ?? 'Unnamed Business',
          businessLogoUrl: b['logo_url'] as String?,
          userUid:         superadminUid,
          role:            UserRole.owner,
          isActive:        b['is_active'] as bool? ?? true,
          joinedAt:        b['created_at'] != null
              ? DateTime.parse(b['created_at'] as String)
              : DateTime.now(),
        );
      }).toList();
    } on PostgrestException catch (e) {
      debugPrint('[BusinessDS] getAllBusinessesAsSuperadmin error: ${e.message}');
      throw ServerException('Failed to load businesses: ${e.message}');
    } catch (e) {
      throw ServerException('Failed to load businesses: $e');
    }
  }

  @override
  Future<BusinessMembershipModel> addMember({
    required String businessId,
    required String userUid,
    required String role,
    String? invitedBy,
  }) async {
    try {
      final inserted = await _supabase
          .from(SupabaseTables.businessMembers)
          .upsert({
            'business_id': businessId,
            'user_uid':    userUid,
            'role':        role,
            'is_active':   true,
            'invited_by':  invitedBy,
          })
          .select('*, ${SupabaseTables.businesses}(name, logo_url)')
          .single();

      return BusinessMembershipModel.fromJson(
          Map<String, dynamic>.from(inserted));
    } on PostgrestException catch (e) {
      throw ServerException('Failed to add member: ${e.message}');
    }
  }

  @override
  Future<void> updateMemberRole({
    required String businessId,
    required String userUid,
    required String newRole,
  }) async {
    try {
      await _supabase
          .from(SupabaseTables.businessMembers)
          .update({'role': newRole, 'updated_at': DateTime.now().toIso8601String()})
          .eq('business_id', businessId)
          .eq('user_uid', userUid);
    } on PostgrestException catch (e) {
      throw ServerException('Failed to update role: ${e.message}');
    }
  }

  @override
  Future<void> deactivateMember({
    required String businessId,
    required String userUid,
  }) async {
    try {
      await _supabase
          .from(SupabaseTables.businessMembers)
          .update({
            'is_active':  false,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('business_id', businessId)
          .eq('user_uid', userUid);
    } on PostgrestException catch (e) {
      throw ServerException('Failed to deactivate member: ${e.message}');
    }
  }
}
