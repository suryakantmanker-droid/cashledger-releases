import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/notifications/data/models/notification_model.dart';
import '../../shared/providers/business_context_provider.dart';
import '../constants/notification_mode.dart';
import 'firebase_service.dart';
import 'hive_service.dart';
import 'notification_service.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(ref.watch(firebaseMessagingProvider));
});

/// Real-time stream of the current user's notifications from Supabase.
///
/// Filters by `user_id` (server-side) and optionally `business_id` (client-side).
/// Sorted by `created_at` descending, limited to 50 most recent.
final notificationsStreamProvider =
    StreamProvider.autoDispose<List<NotificationModel>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(const []);

  final businessId = ref.watch(activeBusinessIdProvider);

  return Supabase.instance.client
      .from('notifications')
      .stream(primaryKey: ['id'])
      .eq('user_id', user.uid)
      .order('created_at', ascending: false)
      .limit(50)
      .map((rows) {
        final all = rows.map(NotificationModel.fromJson).toList();
        if (businessId == null || businessId.isEmpty) return all;
        // Show notifications for this business OR notifications with no business scope
        return all
            .where((n) => n.businessId == businessId || n.businessId.isEmpty)
            .toList();
      });
});

/// Badge count: unread notifications
final unreadNotificationCountProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(notificationsStreamProvider).maybeWhen(
    data: (list) => list.where((n) => !n.isRead).length,
    orElse: () => 0,
  );
});

class NotificationModeNotifier extends StateNotifier<NotificationMode> {
  NotificationModeNotifier() : super(HiveService.instance.getNotificationMode());

  Future<void> setMode(NotificationMode mode) async {
    await HiveService.instance.saveNotificationMode(mode);
    state = mode;
  }
}

final notificationModeProvider =
    StateNotifierProvider<NotificationModeNotifier, NotificationMode>(
  (ref) => NotificationModeNotifier(),
);
