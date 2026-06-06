import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/notification_mode.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/services/notification_service_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../shared/providers/business_context_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../superadmin/presentation/providers/superadmin_provider.dart';
import '../../data/models/notification_model.dart';

String _errorMessage(Object e) {
  final msg = e.toString().toLowerCase();
  if (msg.contains('permission') || msg.contains('insufficient')) {
    return 'Permission denied. Contact your administrator.';
  }
  if (msg.contains('index') || msg.contains('requires an index')) {
    return 'Database configuration error. Please contact support.';
  }
  if (msg.contains('network') || msg.contains('unavailable') || msg.contains('failed host lookup')) {
    return 'No internet connection. Check your network and try again.';
  }
  return 'Failed to load notifications. Please try again.';
}

class NotificationScreen extends ConsumerStatefulWidget {
  const NotificationScreen({super.key});

  @override
  ConsumerState<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends ConsumerState<NotificationScreen> {
  @override
  void initState() {
    super.initState();
    // Clear badge as soon as the screen is opened
    NotificationService.updateBadge(0);
  }

  @override
  Widget build(BuildContext context) {
    final notificationsAsync = ref.watch(notificationsStreamProvider);
    final user = ref.watch(currentUserProvider).valueOrNull;
    final businessId = ref.watch(activeBusinessIdProvider);
    final notifService = ref.read(notificationServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          notificationsAsync.maybeWhen(
            data: (list) {
              final hasUnread = list.any((n) => !n.isRead);
              if (!hasUnread) return const SizedBox.shrink();
              return TextButton(
                onPressed: () {
                  if (user != null) {
                    notifService.markAllAsRead(user.uid, businessId: businessId);
                  }
                },
                child: Text(
                  'Mark all read',
                  style: TextStyle(fontSize: 13.sp),
                ),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
          // Super-admin: quick link to business watch settings
          if (ref.watch(isSuperadminProvider)) ...[
            Consumer(builder: (context, ref, _) {
              final watchCount = ref
                  .watch(superAdminWatchProvider)
                  .watched
                  .length;
              return Padding(
                padding: EdgeInsets.only(right: 4.w),
                child: ActionChip(
                  avatar: Icon(Icons.business_rounded, size: 14.sp),
                  label: Text(
                    watchCount == 0 ? 'Watching none' : 'Watching $watchCount',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11.sp),
                  ),
                  onPressed: () =>
                      context.push(RouteConstants.superadminNotificationSettings),
                ),
              );
            }),
          ],
          IconButton(
            tooltip: 'Notification mode',
            icon: Consumer(
              builder: (context, ref, _) {
                final mode = ref.watch(notificationModeProvider);
                return Icon(_modeIcon(mode), size: 22.sp);
              },
            ),
            onPressed: () => _showModePicker(context),
          ),
        ],
      ),
      body: notificationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorStateWidget(
          message: _errorMessage(e),
          onRetry: () => ref.invalidate(notificationsStreamProvider),
        ),
        data: (notifications) {
          if (notifications.isEmpty) {
            return const EmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'No notifications yet',
              subtitle: 'You\'ll see expense approvals, fund transfers, and more here.',
            );
          }

          return ListView.separated(
            padding: EdgeInsets.symmetric(vertical: 8.h),
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
            itemBuilder: (ctx, i) {
              final n = notifications[i];
              return _NotifTile(
                notification: n,
                onTap: () {
                  if (!n.isRead) {
                    notifService.markAsRead(
                      n.id,
                      businessId: n.businessId.isNotEmpty ? n.businessId : null,
                    );
                  }
                  // Navigate to sale detail — use admin route if user is admin
                  if (n.isSaleCollection && n.saleId != null) {
                    final isAdmin = user?.isAdmin ?? false;
                    final route = isAdmin
                        ? '/admin/sales/${n.saleId}'
                        : '/employee/sales/${n.saleId}';
                    context.push(route);
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}

IconData _modeIcon(NotificationMode mode) {
  switch (mode) {
    case NotificationMode.silent:
      return Icons.notifications_off_rounded;
    case NotificationMode.sound:
      return Icons.volume_up_rounded;
    case NotificationMode.vibrate:
      return Icons.vibration_rounded;
  }
}

void _showModePicker(BuildContext context) {
  showModalBottomSheet(
    context: context,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
    ),
    builder: (_) => const _NotificationModePicker(),
  );
}

class _NotifTile extends StatelessWidget {
  final NotificationModel notification;
  final VoidCallback onTap;

  const _NotifTile({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isUnread = !notification.isRead;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: isUnread
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.05)
            : null,
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon circle
            Container(
              width: 44.w,
              height: 44.w,
              decoration: BoxDecoration(
                color: notification.iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(notification.icon, color: notification.iconColor, size: 22.sp),
            ),
            SizedBox(width: 14.w),

            // Text content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13.5.sp,
                            fontWeight: isUnread ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (isUnread)
                        Container(
                          width: 8.w,
                          height: 8.w,
                          margin: EdgeInsets.only(left: 8.w),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: 3.h),
                  Text(
                    notification.body,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12.sp,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  SizedBox(height: 5.h),
                  Text(
                    AppUtils.formatDateWithTime(notification.createdAt),
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11.sp,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationModePicker extends ConsumerWidget {
  const _NotificationModePicker();

  static const _options = [
    (mode: NotificationMode.sound,   label: 'Sound',   icon: Icons.volume_up_rounded),
    (mode: NotificationMode.vibrate, label: 'Vibrate', icon: Icons.vibration_rounded),
    (mode: NotificationMode.silent,  label: 'Silent',  icon: Icons.notifications_off_rounded),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(notificationModeProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 20.h, 16.w, 12.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notification Mode',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 16.h),
            Row(
              children: _options.map((opt) {
                final selected = current == opt.mode;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6.w),
                    child: GestureDetector(
                      onTap: () {
                        ref.read(notificationModeProvider.notifier).setMode(opt.mode);
                        Navigator.of(context).pop();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: EdgeInsets.symmetric(vertical: 16.h),
                        decoration: BoxDecoration(
                          color: selected
                              ? colorScheme.primary.withValues(alpha: 0.12)
                              : colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14.r),
                          border: Border.all(
                            color: selected ? colorScheme.primary : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              opt.icon,
                              size: 26.sp,
                              color: selected
                                  ? colorScheme.primary
                                  : AppColors.textSecondary,
                            ),
                            SizedBox(height: 8.h),
                            Text(
                              opt.label,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12.sp,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: selected
                                    ? colorScheme.primary
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            SizedBox(height: 8.h),
          ],
        ),
      ),
    );
  }
}
