import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;
import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../models/user_model.dart';

abstract class AuthRemoteDataSource {
  Future<UserModel> login({required String email, required String password});
  Future<void> logout();
  Future<void> sendPasswordResetEmail(String email);
  Stream<UserModel?> get authStateChanges;
  Future<UserModel> getCurrentUser();
  Future<void> updateLastLogin(String userId);
  Future<void> updateFcmToken(String userId, String token);
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final SupabaseClient _supabase;

  const AuthRemoteDataSourceImpl(this._supabase);

  @override
  Future<UserModel> login({required String email, required String password}) async {
    try {
      debugPrint('[AuthDS] Login attempt: $email');

      final response = await _supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );

      final supabaseUser = response.user;
      if (supabaseUser == null) {
        throw const AuthException('Login failed. Please try again.');
      }

      debugPrint('[AuthDS] Supabase Auth OK. UID: ${supabaseUser.id}');

      final user = await _getOrCreateUser(supabaseUser);

      if (!user.isActive) {
        await _supabase.auth.signOut();
        throw const AuthException('Your account has been deactivated. Contact admin.');
      }

      await updateLastLogin(supabaseUser.id);
      debugPrint('[AuthDS] Login complete. Role: ${user.role}, Name: ${user.name}');
      return user;
    } on AuthApiException catch (e) {
      debugPrint('[AuthDS] AuthApiException: ${e.message}');
      throw AuthException(_mapSupabaseError(e.message));
    } on AuthException {
      rethrow;
    } catch (e) {
      debugPrint('[AuthDS] Unexpected login error: $e');
      throw AuthException('Login failed: ${e.toString()}');
    }
  }

  @override
  Future<void> logout() async {
    debugPrint('[AuthDS] Signing out');
    await _supabase.auth.signOut();
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(
        email.trim(),
        // Deep link that Android opens when the user taps the email link.
        // Must also be added to Supabase Dashboard → Auth → URL Configuration → Redirect URLs.
        redirectTo: 'com.cashledger.app://login-callback',
      );
    } on AuthApiException catch (e) {
      throw AuthException(_mapSupabaseError(e.message));
    }
  }

  @override
  Stream<UserModel?> get authStateChanges {
    // asyncExpand pauses the outer stream while the inner stream is active.
    // Since Supabase .stream() never closes, the outer auth-state stream gets
    // permanently paused after the first event — subsequent signIn/signOut events
    // are buffered and never processed, leaving stale user data in the stream.
    // We implement switchMap manually: cancel the previous inner subscription
    // before subscribing to the new one.
    final controller = StreamController<UserModel?>();
    StreamSubscription? innerSub;

    final outerSub = _supabase.auth.onAuthStateChange.listen(
      (authState) async {
        await innerSub?.cancel();
        innerSub = null;

        final supabaseUser = authState.session?.user;

        if (supabaseUser == null) {
          debugPrint('[AuthDS] authStateChanges: signed out');
          if (!controller.isClosed) controller.add(null);
          return;
        }

        debugPrint('[AuthDS] authStateChanges: subscribing for uid=${supabaseUser.id}');

        // Seed the stream with the REST-fetched user immediately so the UI
        // never has to wait for the Realtime initial fetch (which runs through
        // the WebSocket and may briefly see empty rows if the JWT hasn't been
        // forwarded yet — that empty-row race condition was causing _createUser
        // to be called and UPSERT-overwriting the employee's role to 'admin').
        try {
          final initial = await _getOrCreateUser(supabaseUser);
          if (!controller.isClosed) controller.add(initial);
        } catch (e) {
          debugPrint('[AuthDS] Initial REST fetch failed: $e');
        }

        // Keep a live Realtime subscription for subsequent row changes
        // (FCM token updates, is_active changes, etc.).
        innerSub = _supabase
            .from('users')
            .stream(primaryKey: ['uid'])
            .eq('uid', supabaseUser.id)
            .asyncMap((rows) async {
              if (rows.isEmpty) {
                // Realtime stream returned empty — likely a transient RLS/JWT
                // issue on the WebSocket. Fall back to REST to get the real row
                // instead of calling _createUser which would overwrite the role.
                debugPrint('[AuthDS] Stream empty — fetching via REST for uid=${supabaseUser.id}');
                return await _getOrCreateUser(supabaseUser);
              }
              return UserModel.fromJson(rows.first);
            })
            .listen(
              (user) { if (!controller.isClosed) controller.add(user); },
              onError: (Object e) { if (!controller.isClosed) controller.addError(e); },
            );
      },
      onError: (Object e) { if (!controller.isClosed) controller.addError(e); },
    );

    controller.onCancel = () async {
      await innerSub?.cancel();
      await outerSub.cancel();
    };

    return controller.stream;
  }

  @override
  Future<UserModel> getCurrentUser() async {
    final supabaseUser = _supabase.auth.currentUser;
    if (supabaseUser == null) throw const AuthException('No authenticated user found.');
    return _getOrCreateUser(supabaseUser);
  }

  @override
  Future<void> updateLastLogin(String userId) async {
    try {
      await _supabase.from('users').update({
        'last_login_at': DateTime.now().toIso8601String(),
      }).eq('uid', userId);
    } catch (e) {
      debugPrint('[AuthDS] updateLastLogin non-fatal error: $e');
    }
  }

  @override
  Future<void> updateFcmToken(String userId, String token) async {
    try {
      await _supabase.from('users').update({
        'fcm_token': token,
      }).eq('uid', userId);
    } catch (e) {
      debugPrint('[AuthDS] updateFcmToken non-fatal error: $e');
    }
  }

  // ── Private helpers ──────────────────────────────────────────────────────────

  Future<UserModel> _getOrCreateUser(User supabaseUser) async {
    final rows = await _supabase
        .from('users')
        .select()
        .eq('uid', supabaseUser.id)
        .limit(1);

    if (rows.isNotEmpty) {
      debugPrint('[AuthDS] Supabase row found for uid=${supabaseUser.id}');
      return UserModel.fromJson(rows.first);
    }

    debugPrint('[AuthDS] No Supabase row — auto-creating for uid=${supabaseUser.id}');
    return await _createUser(supabaseUser);
  }

  Future<UserModel> _createUser(User supabaseUser) async {
    final now  = DateTime.now().toIso8601String();
    final meta = supabaseUser.userMetadata ?? {};

    final data = {
      'uid':           supabaseUser.id,
      'name':          (meta['full_name'] as String?)?.isNotEmpty == true
                           ? meta['full_name']
                           : (meta['name'] as String?)?.isNotEmpty == true
                               ? meta['name']
                               : supabaseUser.email?.split('@').first ?? 'User',
      'email':         supabaseUser.email ?? '',
      // Default to 'employee' — safer than 'admin'.
      // Admin/superadmin rows are always created explicitly by the superadmin
      // flow or edge function and will already exist before first login.
      // Using 'admin' here was causing employees to get admin role when the
      // Realtime stream returned empty rows due to a transient RLS/JWT issue.
      'role':          AppConstants.roleEmployee,
      'is_active':     true,
      'photo_url':     meta['avatar_url'] as String?,
      'fcm_token':     null,
      'created_at':    now,
      'last_login_at': now,
    };

    // Use INSERT + ignoreDuplicates instead of UPSERT.
    // If the row already exists (e.g. created by the edge function with
    // role='employee'), this is a no-op and preserves the existing role.
    // UPSERT would have overwritten role to 'employee' (or previously 'admin'),
    // silently corrupting the user's data.
    await _supabase
        .from('users')
        .insert(data, defaultToNull: false)
        .onError((_, __) {});   // ignore duplicate-key errors

    // Always SELECT the authoritative row from the DB after the insert attempt.
    final inserted = await _supabase
        .from('users')
        .select()
        .eq('uid', supabaseUser.id)
        .single();

    debugPrint('[AuthDS] Supabase user row created successfully');
    return UserModel.fromJson(inserted);
  }

  String _mapSupabaseError(String? message) {
    final msg = (message ?? '').toLowerCase();
    if (msg.contains('invalid login credentials') || msg.contains('invalid password')) {
      return 'Invalid email or password.';
    }
    if (msg.contains('email not confirmed')) {
      return 'Please verify your email address.';
    }
    if (msg.contains('user not found')) {
      return 'No account found with this email.';
    }
    if (msg.contains('too many requests') || msg.contains('rate limit') ||
        msg.contains('email rate limit') || msg.contains('over_email_send_rate_limit')) {
      return 'Too many attempts. Please wait a few minutes and try again.';
    }
    if (msg.contains('network') || msg.contains('connection')) {
      return 'Network error. Please check your connection.';
    }
    return message ?? 'Authentication failed. Please try again.';
  }
}
