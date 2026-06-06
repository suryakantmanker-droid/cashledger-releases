import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/services/notification_service_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../expenses/presentation/providers/expense_provider.dart';
import '../providers/dashboard_provider.dart';
import '../../../expenses/presentation/widgets/expense_list_tile.dart';

class EmployeeDashboardScreen extends ConsumerWidget {
  const EmployeeDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final statsAsync = user != null
        ? ref.watch(employeeDashboardStatsProvider(user.uid))
        : const AsyncValue<dynamic>.loading();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hello,',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13.sp,
                fontWeight: FontWeight.w400,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            Text(
              user?.name ?? '',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 17.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        actions: [
          _NotificationBell(route: RouteConstants.employeeNotifications),
          Padding(
            padding: EdgeInsets.only(right: 8.w),
            child: PopupMenuButton<String>(
              offset: const Offset(0, 40),
              onSelected: (value) async {
                if (value == 'profile') {
                  context.push(RouteConstants.employeeProfile);
                } else if (value == 'logout') {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Logout?'),
                      content: const Text('Are you sure you want to log out?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Logout', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  );
                  if (ok == true && context.mounted) {
                    await ref.read(authNotifierProvider.notifier).logout();
                    if (context.mounted) context.go(RouteConstants.login);
                  }
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'profile', child: Row(children: [Icon(Icons.person_rounded), SizedBox(width: 8), Text('My Profile')])),
                const PopupMenuItem(value: 'logout', child: Row(children: [Icon(Icons.logout_rounded, color: AppColors.error), SizedBox(width: 8), Text('Logout', style: TextStyle(color: AppColors.error))])),
              ],
              child: CircleAvatar(
                radius: 18.r,
                backgroundColor: AppColors.accent,
                backgroundImage: user?.photoUrl != null ? NetworkImage(user!.photoUrl!) : null,
                child: user?.photoUrl == null
                    ? Text(
                        AppUtils.getInitials(user?.name ?? 'E'),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (stats) => RefreshIndicator(
          onRefresh: () async {
            if (user != null) {
              ref.invalidate(employeeExpensesStreamProvider(user.uid));
              ref.invalidate(employeeDashboardStatsProvider(user.uid));
            }
            await Future.delayed(const Duration(milliseconds: 400));
          },
          child: ListView(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            children: [
              // Balance Card
              _BalanceCard(stats: stats),
              SizedBox(height: 16.h),

              // Stats Row
              Row(
                children: [
                  _MiniStatCard(
                    label: 'Total Assigned',
                    value: AppUtils.formatCurrencyCompact(stats.totalAssigned),
                    icon: Icons.upload_rounded,
                    color: AppColors.primary,
                  ),
                  SizedBox(width: 12.w),
                  _MiniStatCard(
                    label: 'Total Spent',
                    value: AppUtils.formatCurrencyCompact(stats.totalSpent),
                    icon: Icons.download_rounded,
                    color: AppColors.error,
                  ),
                ],
              ),
              SizedBox(height: 12.h),
              Row(
                children: [
                  _MiniStatCard(
                    label: 'Pending',
                    value: stats.pendingApprovals.toString(),
                    icon: Icons.access_time_rounded,
                    color: AppColors.warning,
                    isCount: true,
                  ),
                  SizedBox(width: 12.w),
                  _MiniStatCard(
                    label: 'Approved',
                    value: stats.approvedExpenses.toString(),
                    icon: Icons.check_circle_rounded,
                    color: AppColors.success,
                    isCount: true,
                  ),
                ],
              ),
              SizedBox(height: 20.h),

              // Add Expense Button
              Container(
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: AppColors.blueGradient),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add New Expense',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 15.sp,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Submit a new expense with bills',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12.sp,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => context.push(RouteConstants.addExpense),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                      ),
                      child: const Text(
                        'Add',
                        style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 20.h),

              // Recent Expenses
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Recent Expenses',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.go(RouteConstants.expenseList),
                    child: const Text('View All'),
                  ),
                ],
              ),
              SizedBox(height: 8.h),
              if (stats.recentExpenses.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.h),
                  child: Center(
                    child: Text(
                      'No expenses submitted yet',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13.sp,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                )
              else
                ...stats.recentExpenses.map(
                  (e) => Padding(
                    padding: EdgeInsets.only(bottom: 8.h),
                    child: ExpenseListTile(
                      expense: e,
                      onTap: () => context.push('/employee/expenses/${e.id}'),
                    ),
                  ),
                ),
              SizedBox(height: 24.h),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final dynamic stats;
  const _BalanceCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppColors.greenGradient,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.greenGradient.last.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Current Balance',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13.sp,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
              Container(
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.account_balance_wallet_rounded,
                    color: Colors.white, size: 18.sp),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Text(
            AppUtils.formatCurrency(stats.currentBalance),
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 32.sp,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -1,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            'Available to spend',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12.sp,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool isCount;

  const _MiniStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.isCount = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(14.w),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20.sp),
            SizedBox(width: 10.w),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: isCount ? 18.sp : 14.sp,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10.sp,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Notification Bell with unread badge ──────────────────────────────────────

class _NotificationBell extends ConsumerWidget {
  final String route;
  const _NotificationBell({required this.route});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider);

    return IconButton(
      onPressed: () => context.push(route),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_outlined),
          if (unread > 0)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
