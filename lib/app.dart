import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'core/router/app_router.dart';
import 'core/services/notification_service.dart';
import 'core/services/notification_service_provider.dart';
import 'core/theme/app_theme.dart';

// Theme mode provider
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) => _BadgeSyncWidget(
        child: GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          behavior: HitTestBehavior.translucent,
          child: MaterialApp.router(
            title: 'ExpenseTrack Pro',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeMode,
            routerConfig: router,
          ),
        ),
      ),
    );
  }
}

/// Listens to the unread notification count and keeps the app icon
/// badge in sync automatically — works when the app is in the foreground
/// or resuming from background.
class _BadgeSyncWidget extends ConsumerWidget {
  final Widget child;
  const _BadgeSyncWidget({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<int>(unreadNotificationCountProvider, (_, count) {
      NotificationService.updateBadge(count);
    });
    return child;
  }
}
