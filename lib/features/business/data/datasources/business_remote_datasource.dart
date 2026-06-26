import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/permission_matrix.dart';
import '../../../../core/errors/exceptions.dart';
import '../models/business_membership_model.dart';

/// Lightweight view of a business_members row joined with the user's
/// display info — used for the "Business Admins" management UI.
class BusinessMemberInfo {
  final String userUid;
  final String name;
  final String email;
  final UserRole role;
  final DateTime joinedAt;
  /// The role this member held right before being promoted to owner/admin —
  /// null if there's nothing to revert to (fresh admin invite, or never promoted).
  final UserRole? previousRole;

  const BusinessMemberInfo({
    required this.userUid,
    required this.name,
    required this.email,
    required this.role,
    required this.joinedAt,
    this.previousRole,
  });

  factory BusinessMemberInfo.fromJson(
    Map<String, dynamic> json, {
    Map<String, Map<String, String>> userMap = const {},
  }) {
    final uid = json['user_uid'] as String? ?? '';
    final user = userMap[uid];
    return BusinessMemberInfo(
      userUid: uid,
      name:    user?['name']  ?? 'Unknown',
      email:   user?['email'] ?? '',
      role:    UserRole.fromString(json['role'] as String?),
      joinedAt: json['joined_at'] != null
          ? DateTime.parse(json['joined_at'] as String)
          : DateTime.now(),
      previousRole: json['previous_role'] != null
          ? UserRole.fromString(json['previous_role'] as String?)
          : null,
    );
  }
}

/// Result of looking up an email against the `users` table. [currentRole] is
/// null when the user exists globally but isn't yet a member of the business
/// being checked against.
class ExistingUserMatch {
  final String userUid;
  final String name;
  final String email;
  final UserRole? currentRole;

  const ExistingUserMatch({
    required this.userUid,
    required this.name,
    required this.email,
    required this.currentRole,
  });
}

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

  /// Returns all active owner/admin members of [businessId], joined with
  /// their user display info.
  Future<List<BusinessMemberInfo>> getBusinessAdmins(String businessId);

  /// Creates a brand-new login (Supabase Auth account + users row) and
  /// attaches it to [businessId] with role=admin. Mirrors the
  /// employee-invite flow in EmployeeRemoteDataSourceImpl.addEmployee().
  Future<BusinessMemberInfo> inviteAdmin({
    required String businessId,
    required String name,
    required String email,
    required String password,
    required String invitedBy,
  });

  /// Deactivates an admin's membership entirely. Refuses to remove the owner.
  Future<void> removeAdmin({
    required String businessId,
    required String userUid,
  });

  /// Switches a member back to the role they held before being promoted to
  /// owner/admin (`previous_role`). Throws if there's nothing to revert to.
  Future<void> revertToPreviousRole({
    required String businessId,
    required String userUid,
  });

  /// Looks up [email] in the `users` table and, if found, reports their
  /// current role (if any) in [businessId]. Used by the Add Admin flow to
  /// avoid trying to create a duplicate Auth account for an existing user.
  Future<ExistingUserMatch?> findUserByEmail({
    required String businessId,
    required String email,
  });

  /// Deactivates [userUid]'s `employees` row in [businessId], if one exists —
  /// a promoted admin is no longer a fund-transfer-target employee, but their
  /// balance/expense history is preserved (soft-deactivate, not delete).
  Future<void> deactivateEmployeeRecordIfAny({
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

      await _syncLegacyUserRole(userUid: userUid, role: role);

      return BusinessMembershipModel.fromJson(
          Map<String, dynamic>.from(inserted));
    } on PostgrestException catch (e) {
      throw ServerException('Failed to add member: ${e.message}');
    }
  }

  static bool _isAdminLike(String? role) =>
      role == AppConstants.roleOwner || role == AppConstants.roleAdmin;

  @override
  Future<void> updateMemberRole({
    required String businessId,
    required String userUid,
    required String newRole,
  }) async {
    try {
      final current = await _supabase
          .from(SupabaseTables.businessMembers)
          .select('role')
          .eq('business_id', businessId)
          .eq('user_uid', userUid)
          .maybeSingle();
      final oldRole = current?['role'] as String?;
      final wasAdminLike = _isAdminLike(oldRole);
      final willBeAdminLike = _isAdminLike(newRole);

      await _supabase
          .from(SupabaseTables.businessMembers)
          .update({
            'role': newRole,
            // Remember the pre-promotion role so it can be reverted to later;
            // clears itself once no longer admin-like.
            'previous_role': willBeAdminLike ? oldRole : null,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('business_id', businessId)
          .eq('user_uid', userUid);

      await _syncLegacyUserRole(userUid: userUid, role: newRole);

      // Admin-level roles manage the business — they're no longer tracked as
      // a fund-transfer-target employee. Demoting back reverses this.
      if (!wasAdminLike && willBeAdminLike) {
        await deactivateEmployeeRecordIfAny(businessId: businessId, userUid: userUid);
      } else if (wasAdminLike && !willBeAdminLike) {
        await _reactivateEmployeeRecordIfAny(businessId: businessId, userUid: userUid);
      }
    } on PostgrestException catch (e) {
      throw ServerException('Failed to update role: ${e.message}');
    }
  }

  @override
  Future<void> revertToPreviousRole({
    required String businessId,
    required String userUid,
  }) async {
    final row = await _supabase
        .from(SupabaseTables.businessMembers)
        .select('role, previous_role')
        .eq('business_id', businessId)
        .eq('user_uid', userUid)
        .maybeSingle();

    if (row == null) throw const ServerException('Member not found.');
    if (row['role'] == AppConstants.roleOwner) {
      throw const ServerException('The business owner cannot be changed this way.');
    }
    final previousRole = row['previous_role'] as String?;
    if (previousRole == null) {
      throw const ServerException('No previous role to revert to — remove instead.');
    }

    await updateMemberRole(businessId: businessId, userUid: userUid, newRole: previousRole);
  }

  /// Keeps the legacy `users.role` column (admin/employee two-tier flag —
  /// still read by `UserEntity.isAdmin`/`isEmployee` in several screens) in
  /// sync with the real per-business role in `business_members`. Owner/Admin
  /// collapse to the legacy 'admin'; everything else (manager, accountant,
  /// employee, viewer) collapses to 'employee', matching how the router's
  /// `isAdminLike` check already treats them.
  Future<void> _syncLegacyUserRole({required String userUid, required String role}) async {
    final isAdminLike = role == AppConstants.roleOwner || role == AppConstants.roleAdmin;
    try {
      await _supabase
          .from(SupabaseTables.users)
          .update({'role': isAdminLike ? AppConstants.roleAdmin : AppConstants.roleEmployee})
          .eq('uid', userUid);
    } on PostgrestException catch (e) {
      debugPrint('[BusinessDS] _syncLegacyUserRole error: ${e.message}');
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

  @override
  Future<List<BusinessMemberInfo>> getBusinessAdmins(String businessId) async {
    try {
      final rows = await _supabase
          .from(SupabaseTables.businessMembers)
          .select('user_uid, role, joined_at, previous_role')
          .eq('business_id', businessId)
          .eq('is_active', true)
          .inFilter('role', [AppConstants.roleOwner, AppConstants.roleAdmin])
          .order('joined_at', ascending: true);

      var memberRows = (rows as List<dynamic>)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();

      final uids = memberRows.map((r) => r['user_uid'] as String).toSet().toList();
      final userMap = await _fetchUserMap(uids);
      final superadminUids = await _fetchSuperadminUids(uids);

      // Superadmin's membership (granted via ensureSuperadminMembership when
      // they view a business) is for support access — it doesn't count as a
      // real business admin and shouldn't count toward maxBusinessAdmins.
      memberRows = memberRows
          .where((r) => !superadminUids.contains(r['user_uid'] as String))
          .toList();

      return memberRows
          .map((r) => BusinessMemberInfo.fromJson(r, userMap: userMap))
          .toList();
    } on PostgrestException catch (e) {
      throw ServerException('Failed to load business admins: ${e.message}');
    }
  }

  /// Batch-fetches name/email for [uids] from the `users` table.
  /// (business_members.user_uid has no FK to users.uid in the schema,
  /// so PostgREST can't embed `users(...)` in a single select — fetched separately.)
  Future<Map<String, Map<String, String>>> _fetchUserMap(List<String> uids) async {
    if (uids.isEmpty) return {};
    final rows = await _supabase
        .from(SupabaseTables.users)
        .select('uid, name, email')
        .inFilter('uid', uids);
    final map = <String, Map<String, String>>{};
    for (final u in rows as List<dynamic>) {
      final uid = u['uid'] as String? ?? '';
      if (uid.isNotEmpty) {
        map[uid] = {
          'name':  u['name']  as String? ?? '',
          'email': u['email'] as String? ?? '',
        };
      }
    }
    return map;
  }

  /// Returns which of [uids] are flagged `is_superadmin` in the `users` table.
  Future<Set<String>> _fetchSuperadminUids(List<String> uids) async {
    if (uids.isEmpty) return {};
    final rows = await _supabase
        .from(SupabaseTables.users)
        .select('uid, is_superadmin')
        .inFilter('uid', uids)
        .eq('is_superadmin', true);
    return (rows as List<dynamic>)
        .map((u) => u['uid'] as String? ?? '')
        .where((uid) => uid.isNotEmpty)
        .toSet();
  }

  @override
  Future<BusinessMemberInfo> inviteAdmin({
    required String businessId,
    required String name,
    required String email,
    required String password,
    required String invitedBy,
  }) async {
    try {
      final uid = await _createAuthUser(
        email:      email,
        password:   password,
        name:       name,
        role:       AppConstants.roleAdmin,
        businessId: businessId,
      );

      final now = DateTime.now().toIso8601String();
      await _supabase.from(SupabaseTables.businessMembers).upsert({
        'business_id': businessId,
        'user_uid':    uid,
        'role':        AppConstants.roleAdmin,
        'is_active':   true,
        'invited_by':  invitedBy,
        'joined_at':   now,
        'created_at':  now,
        'updated_at':  now,
      }, onConflict: 'business_id,user_uid');

      return BusinessMemberInfo(
        userUid:  uid,
        name:     name,
        email:    email,
        role:     UserRole.admin,
        joinedAt: DateTime.parse(now),
      );
    } on ServerException {
      rethrow;
    } on PostgrestException catch (e) {
      throw ServerException('Failed to invite admin: ${e.message}');
    }
  }

  @override
  Future<void> removeAdmin({
    required String businessId,
    required String userUid,
  }) async {
    try {
      final row = await _supabase
          .from(SupabaseTables.businessMembers)
          .select('role')
          .eq('business_id', businessId)
          .eq('user_uid', userUid)
          .maybeSingle();

      if (row != null && row['role'] == AppConstants.roleOwner) {
        throw const ServerException('The business owner cannot be removed.');
      }

      await deactivateMember(businessId: businessId, userUid: userUid);
    } on ServerException {
      rethrow;
    } on PostgrestException catch (e) {
      throw ServerException('Failed to remove admin: ${e.message}');
    }
  }

  @override
  Future<ExistingUserMatch?> findUserByEmail({
    required String businessId,
    required String email,
  }) async {
    try {
      final userRow = await _supabase
          .from(SupabaseTables.users)
          .select('uid, name, email')
          .ilike('email', email.trim())
          .maybeSingle();
      if (userRow == null) return null;

      final uid = userRow['uid'] as String;
      final memberRow = await _supabase
          .from(SupabaseTables.businessMembers)
          .select('role')
          .eq('business_id', businessId)
          .eq('user_uid', uid)
          .eq('is_active', true)
          .maybeSingle();

      return ExistingUserMatch(
        userUid: uid,
        name:    userRow['name'] as String? ?? 'Unknown',
        email:   userRow['email'] as String? ?? email,
        currentRole: memberRow != null
            ? UserRole.fromString(memberRow['role'] as String?)
            : null,
      );
    } on PostgrestException catch (e) {
      throw ServerException('Failed to look up user: ${e.message}');
    }
  }

  @override
  Future<void> deactivateEmployeeRecordIfAny({
    required String businessId,
    required String userUid,
  }) async {
    try {
      await _supabase
          .from('employees')
          .update({'is_active': false, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', userUid)
          .eq('business_id', businessId);
    } on PostgrestException catch (e) {
      debugPrint('[BusinessDS] deactivateEmployeeRecordIfAny error: ${e.message}');
    }
  }

  /// Counterpart to [deactivateEmployeeRecordIfAny] — reactivates an employee
  /// row when a member is demoted out of an admin-like role. Best-effort.
  Future<void> _reactivateEmployeeRecordIfAny({
    required String businessId,
    required String userUid,
  }) async {
    try {
      await _supabase
          .from('employees')
          .update({'is_active': true, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', userUid)
          .eq('business_id', businessId);
    } on PostgrestException catch (e) {
      debugPrint('[BusinessDS] _reactivateEmployeeRecordIfAny error: ${e.message}');
    }
  }

  /// Calls the `create-auth-user` Supabase Edge Function which uses the
  /// service_role key server-side to create an auth account without
  /// affecting the currently signed-in admin session.
  Future<String> _createAuthUser({
    required String email,
    required String password,
    String? name,
    String? role,
    String? businessId,
  }) async {
    final response = await _supabase.functions.invoke(
      'create-auth-user',
      body: {
        'email':      email,
        'password':   password,
        if (name       != null) 'name':       name,
        if (role       != null) 'role':       role,
        if (businessId != null) 'businessId': businessId,
      },
      headers: {'Content-Type': 'application/json'},
    );

    if (response.status != 200) {
      final d = response.data;
      final error = (d is Map ? d['error'] : null)?.toString();
      throw ServerException(error ?? 'Failed to create admin account');
    }

    final d = response.data;
    final uid = (d is Map ? d['uid'] : null)?.toString();
    if (uid == null) throw const ServerException('Invalid response from auth service');
    return uid;
  }
}
