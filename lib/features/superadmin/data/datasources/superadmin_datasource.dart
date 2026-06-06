import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../features/business/domain/entities/business_membership_entity.dart';

class BusinessOverview {
  final String id;
  final String name;
  final String? logoUrl;
  final String? phone;
  final String? ownerUid;
  final String? ownerName;
  final String? ownerEmail;
  final String? address;
  final String? city;
  final String? district;
  final String? state;
  final bool isActive;
  final String plan;
  final int memberCount;
  final int employeeCount;
  final int maxEmployees;
  final DateTime createdAt;
  final SubscriptionStatus subscriptionStatus;
  final DateTime? subscriptionExpiryDate;

  const BusinessOverview({
    required this.id,
    required this.name,
    this.logoUrl,
    this.phone,
    this.ownerUid,
    this.ownerName,
    this.ownerEmail,
    this.address,
    this.city,
    this.district,
    this.state,
    required this.isActive,
    required this.plan,
    required this.memberCount,
    required this.employeeCount,
    this.maxEmployees = 50,
    required this.createdAt,
    required this.subscriptionStatus,
    this.subscriptionExpiryDate,
  });

  factory BusinessOverview.fromJson(Map<String, dynamic> json) {
    return BusinessOverview(
      id:            json['id'] as String,
      name:          json['name'] as String? ?? 'Unnamed',
      logoUrl:       json['logo_url'] as String?,
      phone:         json['phone'] as String?,
      ownerUid:      json['owner_uid'] as String?,
      ownerName:     json['owner_name'] as String?,
      ownerEmail:    json['owner_email'] as String?,
      address:       json['address']  as String?,
      city:          json['city']     as String?,
      district:      json['district'] as String?,
      state:         json['state']    as String?,
      isActive:      json['is_active'] as bool? ?? true,
      plan:          json['plan'] as String? ?? 'free',
      memberCount:   (json['member_count'] as num?)?.toInt() ?? 0,
      employeeCount: (json['employee_count'] as num?)?.toInt() ?? 0,
      maxEmployees:  (json['max_employees'] as num?)?.toInt() ?? 50,
      createdAt:     json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      subscriptionStatus: SubscriptionStatus.fromString(
          json['subscription_status'] as String?),
      subscriptionExpiryDate: json['subscription_expiry_date'] != null
          ? DateTime.tryParse(json['subscription_expiry_date'] as String)
          : null,
    );
  }

  /// True when demo is active and expiry date is known.
  int? get demoDaysRemaining {
    if (subscriptionStatus != SubscriptionStatus.demo) return null;
    if (subscriptionExpiryDate == null) return null;
    final diff = subscriptionExpiryDate!.difference(DateTime.now()).inDays;
    return diff >= 0 ? diff : 0;
  }

  bool get isAccessible {
    if (!isActive) return false;
    if (subscriptionStatus == SubscriptionStatus.inactive) return false;
    if (subscriptionStatus == SubscriptionStatus.expired) return false;
    if (subscriptionExpiryDate != null &&
        DateTime.now().isAfter(subscriptionExpiryDate!)) return false;
    return true;
  }
}

// ── Watch-list entry ──────────────────────────────────────────────────────

class WatchedBusiness {
  final String businessId;
  final DateTime? watchUntil; // null = always

  const WatchedBusiness({required this.businessId, this.watchUntil});

  bool get isActive =>
      watchUntil == null || watchUntil!.isAfter(DateTime.now());

  factory WatchedBusiness.fromJson(Map<String, dynamic> json) => WatchedBusiness(
        businessId: json['business_id'] as String,
        watchUntil: json['watch_until'] != null
            ? DateTime.tryParse(json['watch_until'] as String)
            : null,
      );
}

abstract class SuperadminDataSource {
  Future<List<BusinessOverview>> getAllBusinesses();
  Future<String> createBusiness({
    required String businessName,
    required String adminName,
    required String adminEmail,
    required String adminPassword,
    required String createdBy,
    int demoDays,
    String? phone,
    String? plan,
    String? address,
    String? city,
    String? district,
    String? state,
  });
  Future<void> toggleBusinessStatus(String businessId, {required bool isActive});
  Future<void> setSubscription(
    String businessId, {
    required String status,
    DateTime? expiryDate,
  });
  Future<void> updateBusiness(
    String businessId, {
    required String name,
    String? phone,
    String? plan,
    int? maxEmployees,
    String? address,
    String? city,
    String? district,
    String? state,
    String? ownerName,
    String? ownerEmail,
  });

  Future<void> resetUserPassword(String uid, String newPassword);

  /// Upserts superadmin into business_members so Supabase RLS allows data access.
  Future<void> ensureSuperadminMembership({
    required String businessId,
    required String superadminUid,
  });

  // ── Watch list ─────────────────────────────────────────────────────────────

  /// Returns watched businesses for [superadminUid] that are still active.
  Future<List<WatchedBusiness>> getWatchedBusinesses(String superadminUid);

  /// Upserts a watch entry. [watchUntil] null = watch always.
  Future<void> watchBusiness({
    required String superadminUid,
    required String businessId,
    DateTime? watchUntil,
  });

  /// Removes a watch entry for [businessId].
  Future<void> unwatchBusiness({
    required String superadminUid,
    required String businessId,
  });

  /// Returns UIDs of all super-admins actively watching [businessId].
  Future<List<String>> getSuperadminsWatching(String businessId);
}

class SuperadminDataSourceImpl implements SuperadminDataSource {
  final SupabaseClient _supabase;

  const SuperadminDataSourceImpl(this._supabase);

  @override
  Future<List<BusinessOverview>> getAllBusinesses() async {
    try {
      final rows = await _supabase
          .from(SupabaseTables.businesses)
          .select('''
            id, name, logo_url, phone, owner_uid, address, city, district, state,
            is_active, plan, max_employees, created_at,
            subscription_status, subscription_expiry_date,
            business_members(count),
            employees(count)
          ''')
          .order('created_at', ascending: false);

      final bizList = (rows as List<dynamic>).map((r) {
        final memberList   = r['business_members'] as List<dynamic>? ?? [];
        final employeeList = r['employees']        as List<dynamic>? ?? [];
        return BusinessOverview.fromJson({
          ...Map<String, dynamic>.from(r as Map),
          'member_count':   memberList.isNotEmpty
              ? (memberList.first['count'] as num?)?.toInt() ?? 0
              : 0,
          'employee_count': employeeList.isNotEmpty
              ? (employeeList.first['count'] as num?)?.toInt() ?? 0
              : 0,
        });
      }).toList();

      // Batch-fetch owner details for all businesses that have an owner_uid
      final ownerUids = bizList
          .where((b) => b.ownerUid != null)
          .map((b) => b.ownerUid!)
          .toSet()
          .toList();

      Map<String, Map<String, String>> ownerMap = {};
      if (ownerUids.isNotEmpty) {
        try {
          final users = await _supabase
              .from(SupabaseTables.users)
              .select('uid, name, email')
              .inFilter('uid', ownerUids);
          for (final u in users as List<dynamic>) {
            final uid = u['uid'] as String? ?? '';
            if (uid.isNotEmpty) {
              ownerMap[uid] = {
                'name':  u['name']  as String? ?? '',
                'email': u['email'] as String? ?? '',
              };
            }
          }
        } catch (_) {}
      }

      return bizList.map((b) {
        if (b.ownerUid != null && ownerMap.containsKey(b.ownerUid)) {
          final owner = ownerMap[b.ownerUid!]!;
          return BusinessOverview.fromJson({
            'id': b.id, 'name': b.name, 'logo_url': b.logoUrl,
            'phone': b.phone, 'owner_uid': b.ownerUid,
            'owner_name': owner['name'], 'owner_email': owner['email'],
            'address': b.address, 'city': b.city,
            'district': b.district, 'state': b.state,
            'is_active': b.isActive, 'plan': b.plan,
            'max_employees': b.maxEmployees,
            'created_at': b.createdAt.toIso8601String(),
            'subscription_status': b.subscriptionStatus.name,
            'subscription_expiry_date': b.subscriptionExpiryDate?.toIso8601String(),
            'member_count': b.memberCount,
            'employee_count': b.employeeCount,
          });
        }
        return b;
      }).toList();
    } on PostgrestException catch (e) {
      debugPrint('[SuperadminDS] getAllBusinesses error: ${e.message}');
      throw ServerException('Failed to load businesses: ${e.message}');
    } catch (e) {
      throw ServerException('Failed to load businesses: $e');
    }
  }

  @override
  Future<String> createBusiness({
    required String businessName,
    required String adminName,
    required String adminEmail,
    required String adminPassword,
    required String createdBy,
    int demoDays = 14,
    String? phone,
    String? plan,
    String? address,
    String? city,
    String? district,
    String? state,
  }) async {
    try {
      // 1. Create Supabase Auth account via Edge Function (admin session untouched)
      final adminUid = await _createAuthUser(
        email:    adminEmail.trim(),
        password: adminPassword,
      );

      final now        = DateTime.now().toIso8601String();
      final expiryDate = DateTime.now().add(Duration(days: demoDays));
      var slug = businessName
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      if (slug.isEmpty) slug = 'business';
      final uniqueSlug = '$slug-${DateTime.now().millisecondsSinceEpoch}';

      // 2. Create users row for the new admin
      await _supabase.from('users').upsert({
        'uid':           adminUid,
        'name':          adminName,
        'email':         adminEmail.trim(),
        'role':          AppConstants.roleAdmin,
        'is_active':     true,
        'is_superadmin': false,
        'created_at':    now,
      });

      // 3. Create the business with demo subscription
      final bizRow = await _supabase
          .from(SupabaseTables.businesses)
          .insert({
            'name':                     businessName,
            'slug':                     uniqueSlug,
            'owner_uid':                adminUid,
            'phone':                    phone ?? '',
            'address':                  address ?? '',
            'city':                     city ?? '',
            'district':                 district ?? '',
            'state':                    state ?? '',
            'plan':                     plan ?? 'starter',
            'max_employees':            50,
            'is_active':                true,
            'subscription_status':      demoDays > 0 ? 'demo' : 'active',
            'subscription_expiry_date': demoDays > 0
                ? expiryDate.toIso8601String()
                : null,
            'settings':   {'currency': 'INR', 'timezone': 'Asia/Kolkata'},
            'created_at': now,
            'updated_at': now,
          })
          .select('id')
          .single();

      final businessId = bizRow['id'] as String;

      // 4. Add admin as owner of this business
      await _supabase.from(SupabaseTables.businessMembers).upsert({
        'business_id': businessId,
        'user_uid':    adminUid,
        'role':        AppConstants.roleAdmin,
        'is_active':   true,
        'invited_by':  createdBy,
        'joined_at':   now,
        'created_at':  now,
        'updated_at':  now,
      }, onConflict: 'business_id,user_uid');

      debugPrint('[SuperadminDS] Business "$businessName" created: $businessId (demo: $demoDays days)');
      return businessId;
    } on ServerException {
      rethrow;
    } on PostgrestException catch (e) {
      throw ServerException('DB error: ${e.message}', code: e.code);
    }
  }

  /// Calls `create-auth-user` Edge Function (service_role key is server-side only).
  Future<String> _createAuthUser({
    required String email,
    required String password,
  }) async {
    final response = await _supabase.functions.invoke(
      'create-auth-user',
      body: {'email': email, 'password': password},
      headers: {'Content-Type': 'application/json'},
    );

    if (response.status != 200) {
      final error = (response.data as Map?)?['error'] as String?;
      throw ServerException(error ?? 'Failed to create admin account');
    }

    final uid = (response.data as Map?)?['uid'] as String?;
    if (uid == null) throw const ServerException('Invalid response from auth service');
    return uid;
  }

  @override
  Future<void> toggleBusinessStatus(String businessId,
      {required bool isActive}) async {
    try {
      await _supabase
          .from(SupabaseTables.businesses)
          .update({'is_active': isActive, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', businessId);
    } on PostgrestException catch (e) {
      throw ServerException('Failed to update business: ${e.message}');
    }
  }

  @override
  Future<void> setSubscription(
    String businessId, {
    required String status,
    DateTime? expiryDate,
  }) async {
    try {
      final update = <String, dynamic>{
        'subscription_status': status,
        'subscription_expiry_date': expiryDate?.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (status == 'active') {
        update['is_active'] = true;
      } else if (status == 'inactive') {
        update['is_active'] = false;
      }
      await _supabase
          .from(SupabaseTables.businesses)
          .update(update)
          .eq('id', businessId);
    } on PostgrestException catch (e) {
      throw ServerException('Failed to update subscription: ${e.message}');
    }
  }

  @override
  Future<void> updateBusiness(
    String businessId, {
    required String name,
    String? phone,
    String? plan,
    int? maxEmployees,
    String? address,
    String? city,
    String? district,
    String? state,
    String? ownerName,
    String? ownerEmail,
  }) async {
    try {
      final now = DateTime.now().toIso8601String();

      // Update businesses table
      final bizData = <String, dynamic>{
        'name':       name,
        'updated_at': now,
      };
      if (phone != null) bizData['phone'] = phone;
      if (plan != null) bizData['plan'] = plan;
      if (maxEmployees != null) bizData['max_employees'] = maxEmployees;
      if (address != null) bizData['address'] = address;
      if (city != null) bizData['city'] = city;
      if (district != null) bizData['district'] = district;
      if (state != null) bizData['state'] = state;

      await _supabase
          .from(SupabaseTables.businesses)
          .update(bizData)
          .eq('id', businessId);

      // Update owner details in users table (if ownerUid is resolvable)
      if (ownerName != null || ownerEmail != null) {
        // Fetch owner_uid from businesses
        final biz = await _supabase
            .from(SupabaseTables.businesses)
            .select('owner_uid')
            .eq('id', businessId)
            .maybeSingle();
        final ownerUid = biz?['owner_uid'] as String?;
        if (ownerUid != null && ownerUid.isNotEmpty) {
          final userUpdate = <String, dynamic>{'updated_at': now};
          if (ownerName != null && ownerName.isNotEmpty) userUpdate['name'] = ownerName;
          if (ownerEmail != null && ownerEmail.isNotEmpty) userUpdate['email'] = ownerEmail;
          await _supabase
              .from(SupabaseTables.users)
              .update(userUpdate)
              .eq('uid', ownerUid);
        }
      }
    } on PostgrestException catch (e) {
      throw ServerException('Failed to update business: ${e.message}');
    }
  }

  @override
  Future<void> resetUserPassword(String uid, String newPassword) async {
    final response = await _supabase.functions.invoke(
      'update-user-password',
      body: {'uid': uid, 'newPassword': newPassword},
      headers: {'Content-Type': 'application/json'},
    );
    if (response.status != 200) {
      final error = (response.data as Map?)?['error'] as String?;
      throw ServerException(error ?? 'Failed to reset password');
    }
  }

  @override
  Future<void> ensureSuperadminMembership({
    required String businessId,
    required String superadminUid,
  }) async {
    try {
      final now = DateTime.now().toIso8601String();
      await _supabase.from(SupabaseTables.businessMembers).upsert({
        'business_id': businessId,
        'user_uid':    superadminUid,
        'role':        AppConstants.roleAdmin,
        'is_active':   true,
        'joined_at':   now,
        'created_at':  now,
        'updated_at':  now,
      }, onConflict: 'business_id,user_uid');
      debugPrint('[SuperadminDS] Superadmin membership ensured for business=$businessId');
    } on PostgrestException catch (e) {
      debugPrint('[SuperadminDS] ensureSuperadminMembership error: ${e.message}');
    }
  }

  // ── Watch list ─────────────────────────────────────────────────────────────

  @override
  Future<List<WatchedBusiness>> getWatchedBusinesses(String superadminUid) async {
    try {
      final rows = await _supabase
          .from('superadmin_watched_businesses')
          .select('business_id, watch_until')
          .eq('superadmin_uid', superadminUid);
      return (rows as List)
          .map((r) => WatchedBusiness.fromJson(Map<String, dynamic>.from(r as Map)))
          .where((w) => w.isActive)
          .toList();
    } on PostgrestException catch (e) {
      debugPrint('[SuperadminDS] getWatchedBusinesses error: ${e.message}');
      return [];
    }
  }

  @override
  Future<void> watchBusiness({
    required String superadminUid,
    required String businessId,
    DateTime? watchUntil,
  }) async {
    try {
      await _supabase.from('superadmin_watched_businesses').upsert({
        'superadmin_uid': superadminUid,
        'business_id':    businessId,
        'watch_until':    watchUntil?.toIso8601String(),
        'created_at':     DateTime.now().toIso8601String(),
      }, onConflict: 'superadmin_uid,business_id');
    } on PostgrestException catch (e) {
      debugPrint('[SuperadminDS] watchBusiness error: ${e.message}');
    }
  }

  @override
  Future<void> unwatchBusiness({
    required String superadminUid,
    required String businessId,
  }) async {
    try {
      await _supabase
          .from('superadmin_watched_businesses')
          .delete()
          .eq('superadmin_uid', superadminUid)
          .eq('business_id', businessId);
    } on PostgrestException catch (e) {
      debugPrint('[SuperadminDS] unwatchBusiness error: ${e.message}');
    }
  }

  @override
  Future<List<String>> getSuperadminsWatching(String businessId) async {
    try {
      final now = DateTime.now().toIso8601String();
      final rows = await _supabase
          .from('superadmin_watched_businesses')
          .select('superadmin_uid, watch_until')
          .eq('business_id', businessId)
          .or('watch_until.is.null,watch_until.gt.$now');
      return (rows as List)
          .map((r) => r['superadmin_uid'] as String)
          .toList();
    } on PostgrestException catch (e) {
      debugPrint('[SuperadminDS] getSuperadminsWatching error: ${e.message}');
      return [];
    }
  }
}
