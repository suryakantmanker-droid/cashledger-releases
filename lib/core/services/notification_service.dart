import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/app_constants.dart';
import '../constants/notification_mode.dart';
import 'hive_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background messages handled by OS; no action needed here
}

class NotificationService {
  final FirebaseMessaging _messaging;

  bool _initialized = false;

  static final _localNotifications = FlutterLocalNotificationsPlugin();

  static const _androidChannel = AndroidNotificationChannel(
    'expense_tracker_channel',
    'ExpenseTrack Pro',
    description: 'Expense & fund notifications',
    importance: Importance.max,
    playSound: true,
  );

  final _tapController = StreamController<RemoteMessage>.broadcast();
  Stream<RemoteMessage> get onNotificationTap => _tapController.stream;

  NotificationService(this._messaging);

  SupabaseClient get _supabase => Supabase.instance.client;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (Platform.isAndroid) {
      final status = await Permission.notification.status;
      if (!status.isGranted) await Permission.notification.request();
    }

    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit    = DarwinInitializationSettings();
    await _localNotifications.initialize(
      settings: const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (_) {},
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    _messaging.onTokenRefresh.listen((newToken) async {
      final uid = _supabase.auth.currentUser?.id;
      if (uid != null) await saveTokenToDatabase(uid);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _tapController.add(message);
    });

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) _tapController.add(initialMessage);
  }

  void dispose() => _tapController.close();

  Future<String?> getToken() => _messaging.getToken();

  /// Updates the app icon badge count. Pass 0 to clear the badge.
  static Future<void> updateBadge(int count) async {
    try {
      await AppBadgePlus.updateBadge(count);
    } catch (e) {
      debugPrint('[NotifService] Badge update error: $e');
    }
  }

  Future<void> saveTokenToDatabase(String userId) async {
    String? token;
    for (int attempt = 1; attempt <= 5; attempt++) {
      token = await _messaging.getToken();
      if (token != null) break;
      debugPrint('[NotifService] FCM token null — retry $attempt/5');
      await Future.delayed(const Duration(seconds: 2));
    }

    if (token == null) {
      debugPrint('[NotifService] FCM token unavailable — permission may be denied');
      return;
    }

    debugPrint('[NotifService] FCM token: ${token.substring(0, 20)}...');

    try {
      await _supabase.from('users').update({
        'fcm_token':  token,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('uid', userId);
      debugPrint('[NotifService] FCM token saved to Supabase');
    } catch (e) {
      debugPrint('[NotifService] Token save error: $e');
    }
  }

  Future<void> subscribeToTopic(String topic)   => _messaging.subscribeToTopic(topic);
  Future<void> unsubscribeFromTopic(String topic) => _messaging.unsubscribeFromTopic(topic);

  /// Writes a notification to Supabase `notifications` table and
  /// triggers FCM push via the `send-notification` Edge Function.
  Future<void> sendNotificationToUser({
    required String userId,
    required String title,
    required String body,
    required String type,
    Map<String, dynamic>? data,
    String? businessId,
  }) async {
    // 1. Persist notification in Supabase
    try {
      await _supabase.from('notifications').insert({
        'user_id':     userId,
        'business_id': businessId ?? '',
        'title':       title,
        'body':        body,
        'type':        type,
        'data':        data ?? {},
        'is_read':     false,
        'created_at':  DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[NotifService] Supabase notification insert error: $e');
    }

    // 2. Send FCM push via Edge Function
    try {
      final safeData = (data ?? <String, dynamic>{})
          .map((k, v) => MapEntry(k, v.toString()));

      final response = await _supabase.functions.invoke(
        'send-notification',
        body: <String, dynamic>{
          'userId': userId,
          'title':  title,
          'body':   body,
          'type':   type,
          'data':   safeData,
        },
        headers: {'Content-Type': 'application/json'},
      );
      debugPrint('[NotifService] Edge Function status: ${response.status}');
    } catch (e) {
      debugPrint('[NotifService] Edge Function push error: $e');
    }
  }

  /// Notifies all admin/manager/owner members of [businessId].
  /// Super-admins are excluded — they receive notifications only via their watch list.
  Future<void> notifyAllAdmins({
    required String employeeName,
    required double amount,
    required String expenseId,
    String? businessId,
  }) async {
    try {
      if (businessId != null && businessId.isNotEmpty) {
        final members = await _supabase
            .from('business_members')
            .select('user_uid')
            .eq('business_id', businessId)
            .inFilter('role', [
              AppConstants.roleOwner,
              AppConstants.roleAdmin,
              AppConstants.roleManager,
            ])
            .eq('is_active', true);

        final memberUids = (members as List)
            .map((r) => r['user_uid'] as String)
            .toList();

        final nonSuperAdminUids =
            await _filterOutSuperAdmins(memberUids);

        for (final uid in nonSuperAdminUids) {
          await notifyPendingApprovalToAdmin(
            adminId:      uid,
            employeeName: employeeName,
            amount:       amount,
            expenseId:    expenseId,
            businessId:   businessId,
          );
        }

        // Also notify any super-admin watching this business
        await _notifyWatchingSuperAdmins(
          businessId:   businessId,
          title:        'New Expense Pending',
          body:         '$employeeName submitted ₹${amount.toStringAsFixed(2)} for approval.',
          type:         'expense_pending',
          data:         {'expenseId': expenseId},
          amount:       amount,
        );
      } else {
        final admins = await _supabase
            .from('users')
            .select('uid')
            .eq('role', AppConstants.roleAdmin)
            .eq('is_active', true)
            .eq('is_superadmin', false);

        for (final admin in admins) {
          await notifyPendingApprovalToAdmin(
            adminId:      admin['uid'] as String,
            employeeName: employeeName,
            amount:       amount,
            expenseId:    expenseId,
          );
        }
      }
    } catch (e) {
      debugPrint('[NotifService] notifyAllAdmins error: $e');
    }
  }

  Future<void> markAsRead(String notificationId, {String? businessId}) async {
    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notificationId);
    } catch (e) {
      debugPrint('[NotifService] markAsRead error: $e');
    }
  }

  Future<void> markAllAsRead(String userId, {String? businessId}) async {
    try {
      var query = _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);

      if (businessId != null && businessId.isNotEmpty) {
        query = query.eq('business_id', businessId);
      }

      await query;
    } catch (e) {
      debugPrint('[NotifService] markAllAsRead error: $e');
    }
  }

  // ── Typed notification helpers ─────────────────────────────────────────────

  Future<void> notifyExpenseApproved({
    required String employeeId,
    required String expenseTitle,
    required String expenseId,
    String? businessId,
  }) =>
      sendNotificationToUser(
        userId:     employeeId,
        title:      'Expense Approved',
        body:       'Your expense "$expenseTitle" has been approved.',
        type:       'expense_approved',
        data:       {'expenseId': expenseId},
        businessId: businessId,
      );

  Future<void> notifyExpenseRejected({
    required String employeeId,
    required String expenseTitle,
    required String expenseId,
    required String reason,
    String? businessId,
  }) =>
      sendNotificationToUser(
        userId:     employeeId,
        title:      'Expense Rejected',
        body:       'Your expense "$expenseTitle" was rejected: $reason',
        type:       'expense_rejected',
        data:       {'expenseId': expenseId},
        businessId: businessId,
      );

  Future<void> notifyFundTransferred({
    required String employeeId,
    required double amount,
    required String transferId,
    String? businessId,
  }) =>
      sendNotificationToUser(
        userId:     employeeId,
        title:      'Funds Assigned',
        body:       '₹${amount.toStringAsFixed(2)} has been assigned to you.',
        type:       'fund_transferred',
        data:       {'transferId': transferId},
        businessId: businessId,
      );

  Future<void> notifyPendingApprovalToAdmin({
    required String adminId,
    required String employeeName,
    required double amount,
    required String expenseId,
    String? businessId,
  }) =>
      sendNotificationToUser(
        userId:     adminId,
        title:      'New Expense Pending',
        body:       '$employeeName submitted ₹${amount.toStringAsFixed(2)} for approval.',
        type:       'expense_pending',
        data:       {'expenseId': expenseId},
        businessId: businessId,
      );

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Removes super-admin UIDs from [uids] by querying the users table.
  Future<List<String>> _filterOutSuperAdmins(List<String> uids) async {
    if (uids.isEmpty) return [];
    try {
      final rows = await _supabase
          .from('users')
          .select('uid')
          .inFilter('uid', uids)
          .eq('is_superadmin', false);
      return (rows as List).map((r) => r['uid'] as String).toList();
    } catch (_) {
      return uids; // fail open — better to over-notify than miss
    }
  }

  /// Sends a notification to every super-admin watching [businessId].
  /// Skips super-admins whose device amount threshold would filter it out
  /// (threshold is device-local so we can't check it here — always send,
  /// the UI filters on display).
  Future<void> _notifyWatchingSuperAdmins({
    required String businessId,
    required String title,
    required String body,
    required String type,
    required Map<String, dynamic> data,
    double? amount,
  }) async {
    try {
      final rows = await _supabase
          .from('superadmin_watched_businesses')
          .select('superadmin_uid, watch_until')
          .eq('business_id', businessId)
          .or('watch_until.is.null,watch_until.gt.${DateTime.now().toIso8601String()}');

      for (final row in rows as List) {
        final uid = row['superadmin_uid'] as String;
        await sendNotificationToUser(
          userId:     uid,
          title:      title,
          body:       body,
          type:       type,
          data:       data,
          businessId: businessId,
        );
      }
    } catch (e) {
      debugPrint('[NotifService] _notifyWatchingSuperAdmins error: $e');
    }
  }

  /// Notifies all admin/manager/owner members when an employee logs a sale.
  /// Super-admins are excluded — they receive notifications only via their watch list.
  Future<void> notifySaleCollectionToAdmins({
    required String employeeName,
    required double amount,
    required String itemDescription,
    required String saleId,
    required String businessId,
  }) async {
    try {
      final members = await _supabase
          .from('business_members')
          .select('user_uid')
          .eq('business_id', businessId)
          .inFilter('role', [
            AppConstants.roleOwner,
            AppConstants.roleAdmin,
            AppConstants.roleManager,
          ])
          .eq('is_active', true);

      final memberUids = (members as List)
          .map((r) => r['user_uid'] as String)
          .toList();

      final nonSuperAdminUids = await _filterOutSuperAdmins(memberUids);

      final title = 'Sale Collected';
      final body  = '$employeeName collected ₹${amount.toStringAsFixed(2)} from "$itemDescription".';

      for (final uid in nonSuperAdminUids) {
        await sendNotificationToUser(
          userId:     uid,
          title:      title,
          body:       body,
          type:       'sale_collection',
          data:       {'saleId': saleId},
          businessId: businessId,
        );
      }

      await _notifyWatchingSuperAdmins(
        businessId: businessId,
        title:      title,
        body:       body,
        type:       'sale_collection',
        data:       {'saleId': saleId},
        amount:     amount,
      );
    } catch (e) {
      debugPrint('[NotifService] notifySaleCollectionToAdmins error: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    final mode = HiveService.instance.getNotificationMode();

    final playSound       = mode == NotificationMode.sound;
    final enableVibration = mode == NotificationMode.vibrate;
    final badgeCount     = (message.data['badgeCount'] as int?) ?? 1;

    _localNotifications.show(
      id: notification.hashCode,
      title: notification.title,
      body:  notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance:       Importance.max,
          priority:         Priority.high,
          icon:             '@mipmap/ic_launcher',
          number:           badgeCount,
          playSound:        playSound,
          enableVibration:  enableVibration,
        ),
        iOS: DarwinNotificationDetails(
          badgeNumber:  badgeCount,
          presentSound: playSound,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }
}
