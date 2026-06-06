import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/services/app_update_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/update_dialog.dart';
import '../../../../shared/providers/business_context_provider.dart';
import '../providers/auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0, 0.6, curve: Curves.easeOut)),
    );

    _scaleAnimation = Tween<double>(begin: 0.7, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0, 0.6, curve: Curves.easeOutBack)),
    );

    _controller.forward();
    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;

    // ── Version check ────────────────────────────────────────────────────────
    // Runs before auth check so even unauthenticated users must update.
    final updateInfo = await AppUpdateService.check();
    if (!mounted) return;

    if (updateInfo != null) {
      await UpdateDialog.show(context, updateInfo);
      if (!mounted) return;
      // Force update: dialog is not dismissable — user taps download and leaves
      // the app. If somehow still mounted after force dialog, block navigation.
      if (updateInfo.isForceUpdate) return;
    }
    // ────────────────────────────────────────────────────────────────────────

    // Wait for auth then business context — both must be settled before navigating.
    // Timeout after 10 s to avoid an infinite freeze.
    final deadline = DateTime.now().add(const Duration(seconds: 10));

    while (mounted && DateTime.now().isBefore(deadline)) {
      final authState = ref.read(currentUserProvider);

      if (authState.isLoading) {
        await Future.delayed(const Duration(milliseconds: 150));
        continue;
      }

      final user = authState.valueOrNull;
      if (user == null) {
        if (mounted) context.go(RouteConstants.login);
        return;
      }

      // Auth settled — also wait for business context to finish loading so
      // activeBusinessIdProvider is non-null when the dashboard mounts.
      final businessCtx = ref.read(businessContextProvider);
      if (businessCtx.isIdle || businessCtx.isLoading) {
        await Future.delayed(const Duration(milliseconds: 150));
        continue;
      }

      if (!mounted) return;
      if (user.isSuperadmin) {
        context.go(RouteConstants.superadminDashboard);
      } else if (user.isAdmin) {
        context.go(RouteConstants.adminDashboard);
      } else {
        context.go(RouteConstants.employeeDashboard);
      }
      return;
    }

    // Timeout fallback — go to login
    if (mounted) context.go(RouteConstants.login);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppColors.blueGradient,
          ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (_, __) => FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 88.w,
                      height: 88.w,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.account_balance_wallet_rounded,
                        size: 48.sp,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(height: 24.h),
                    Text(
                      AppConstants.appName,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 26.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      'Business Expense Tracking',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14.sp,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                    SizedBox(height: 60.h),
                    SizedBox(
                      width: 28.w,
                      height: 28.w,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
