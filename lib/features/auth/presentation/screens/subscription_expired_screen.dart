import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../shared/providers/business_context_provider.dart';

class SubscriptionExpiredScreen extends ConsumerWidget {
  const SubscriptionExpiredScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final isAdmin = currentUser?.role == 'admin';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 24.h),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon
              Container(
                width: 100.w,
                height: 100.w,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_clock_outlined,
                  size: 48.sp,
                  color: AppColors.error,
                ),
              ),
              SizedBox(height: 32.h),

              // Title
              Text(
                isAdmin ? 'Subscription Ended' : 'Access Suspended',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 22.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 12.h),

              // Message
              Text(
                isAdmin
                    ? 'Your demo or subscription period has ended.\nTo continue using the app, please contact support to purchase a subscription.'
                    : 'Your business subscription has ended.\nPlease contact your business owner to renew access.',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14.sp,
                  color: AppColors.textSecondary,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 40.h),

              // Check again button (in case superadmin reactivated)
              OutlinedButton.icon(
                onPressed: () {
                  if (currentUser != null) {
                    ref.read(businessContextProvider.notifier).reload(currentUser.uid);
                  }
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Check Again'),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(double.infinity, 48.h),
                ),
              ),
              SizedBox(height: 12.h),

              // Logout
              TextButton.icon(
                onPressed: () =>
                    ref.read(authNotifierProvider.notifier).logout(),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign Out'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  minimumSize: Size(double.infinity, 48.h),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
