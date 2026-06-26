import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/services/notification_service_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../shared/providers/business_context_provider.dart';
import '../providers/dashboard_provider.dart';
import '../widgets/stat_card.dart';
import '../../../expenses/presentation/widgets/expense_list_tile.dart';
import '../../data/dashboard_stats.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final statsAsync = ref.watch(adminDashboardStatsProvider);

    return Scaffold(
      appBar: _buildAppBar(context, ref, user),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(message: e.toString()),
        data: (stats) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(adminDashboardStatsProvider);
            await Future.delayed(const Duration(milliseconds: 400));
          },
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Balance hero card
                    _BalanceHeroCard(stats: stats),
                    SizedBox(height: 20.h),

                    // Quick Actions
                    _SectionHeader(title: 'Quick Actions'),
                    SizedBox(height: 10.h),
                    _QuickActionsGrid(),
                    SizedBox(height: 20.h),

                    // Overview Stats
                    _SectionHeader(title: 'Overview'),
                    SizedBox(height: 10.h),
                    _StatsGrid(stats: stats),
                    SizedBox(height: 16.h),

                    // Alerts
                    if (stats.pendingApprovals > 0 || stats.missingBills > 0) ...[
                      _AlertsSection(
                        pendingApprovals: stats.pendingApprovals,
                        missingBills: stats.missingBills,
                      ),
                      SizedBox(height: 4.h),
                    ],

                    // Recent Expenses header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _SectionHeader(title: 'Recent Expenses'),
                        TextButton(
                          onPressed: () => context.go(RouteConstants.approvalList),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              horizontal: 10.w,
                              vertical: 4.h,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'View All',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 10.h),
                  ]),
                ),
              ),

              // Expense list
              if (stats.recentExpenses.isEmpty)
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  sliver: SliverToBoxAdapter(
                    child: _EmptyExpenses(),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 24.h),
                  sliver: SliverList.separated(
                    itemCount: stats.recentExpenses.length,
                    separatorBuilder: (_, __) => SizedBox(height: 8.h),
                    itemBuilder: (context, i) {
                      final e = stats.recentExpenses[i];
                      return ExpenseListTile(
                        expense: e,
                        onTap: () => context.push('/admin/expenses/${e.id}'),
                      );
                    },
                  ),
                ),

              SliverToBoxAdapter(child: SizedBox(height: 16.h)),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    WidgetRef ref,
    dynamic user,
  ) {
    final isSuperadmin = ref.watch(isSuperadminProvider);
    final membership = ref.watch(activeMembershipProvider);

    if (isSuperadmin && membership != null) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'All Businesses',
          onPressed: () async {
            await ref.read(businessContextProvider.notifier).clearActiveBusiness();
            if (!context.mounted) return;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) context.go(RouteConstants.superadminDashboard);
            });
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Viewing business',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11.sp,
                fontWeight: FontWeight.w400,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
            Text(
              membership.businessName,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15.sp,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          _NotificationBell(route: RouteConstants.adminNotifications),
          SizedBox(width: 4.w),
          Padding(
            padding: EdgeInsets.only(right: 12.w),
            child: _AvatarMenu(user: user),
          ),
        ],
      );
    }

    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Good ${_greeting()}',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12.sp,
              fontWeight: FontWeight.w400,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.55),
            ),
          ),
          Text(
            user?.name ?? 'Admin',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 16.sp,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: [
        _NotificationBell(route: RouteConstants.adminNotifications),
        SizedBox(width: 4.w),
        Padding(
          padding: EdgeInsets.only(right: 12.w),
          child: _AvatarMenu(user: user),
        ),
      ],
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Morning ☀️';
    if (h < 17) return 'Afternoon';
    return 'Evening 🌙';
  }
}

// ── Balance Hero Card ─────────────────────────────────────────────────────────

class _BalanceHeroCard extends StatelessWidget {
  final AdminDashboardStats stats;
  const _BalanceHeroCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(18.w),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1565C0), Color(0xFF1A73E8), Color(0xFF42A5F5)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.32),
            blurRadius: 20,
            offset: const Offset(0, 8),
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
                'Net Balance',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle,
                        color: Colors.greenAccent, size: 7.sp),
                    SizedBox(width: 4.w),
                    Text(
                      'Live',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 6.h),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              AppUtils.formatCurrencyCompact(stats.totalBalance),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 32.sp,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -1,
              ),
            ),
          ),
          SizedBox(height: 14.h),
          Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          SizedBox(height: 14.h),
          Row(
            children: [
              Expanded(
                child: _HeroStat(
                  label: 'Assigned',
                  value: AppUtils.formatCurrencyCompact(stats.totalAssigned),
                  icon: Icons.upload_rounded,
                ),
              ),
              Container(
                width: 1,
                height: 32.h,
                color: Colors.white.withValues(alpha: 0.2),
              ),
              Expanded(
                child: _HeroStat(
                  label: 'Spent',
                  value: AppUtils.formatCurrencyCompact(stats.totalSpent),
                  icon: Icons.download_rounded,
                  alignment: MainAxisAlignment.end,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final MainAxisAlignment alignment;

  const _HeroStat({
    required this.label,
    required this.value,
    required this.icon,
    this.alignment = MainAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: alignment,
      children: [
        if (alignment == MainAxisAlignment.start) ...[
          Icon(icon, color: Colors.white70, size: 14.sp),
          SizedBox(width: 6.w),
        ],
        Column(
          crossAxisAlignment: alignment == MainAxisAlignment.start
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15.sp,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10.sp,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        if (alignment == MainAxisAlignment.end) ...[
          SizedBox(width: 6.w),
          Icon(icon, color: Colors.white70, size: 14.sp),
        ],
      ],
    );
  }
}

// ── Section Header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontFamily: 'Poppins',
        fontSize: 15.sp,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface,
        letterSpacing: -0.2,
      ),
    );
  }
}

// ── Quick Actions Grid ────────────────────────────────────────────────────────

class _QuickActionsGrid extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = [
      _QAData(
        icon: Icons.send_rounded,
        label: 'Transfer',
        color: AppColors.primary,
        onTap: () => context.push(RouteConstants.fundTransfer),
      ),
      _QAData(
        icon: Icons.person_add_rounded,
        label: 'Add Staff',
        color: AppColors.accent,
        onTap: () => context.push(RouteConstants.addEmployee),
      ),
      _QAData(
        icon: Icons.task_alt_rounded,
        label: 'Approvals',
        color: AppColors.warning,
        onTap: () => context.go(RouteConstants.approvalList),
      ),
      _QAData(
        icon: Icons.bar_chart_rounded,
        label: 'Reports',
        color: AppColors.purpleGradient[0],
        onTap: () => context.go(RouteConstants.adminReports),
      ),
      _QAData(
        icon: Icons.admin_panel_settings_outlined,
        label: 'Admins',
        color: AppColors.success,
        onTap: () => context.push(RouteConstants.adminBusinessAdmins),
      ),
    ];

    return Row(
      children: actions
          .map(
            (a) => Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 4.w),
                child: _QuickActionTile(data: a),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _QAData {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QAData({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

class _QuickActionTile extends StatelessWidget {
  final _QAData data;
  const _QuickActionTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: isDark
                ? data.color.withValues(alpha: 0.12)
                : data.color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: data.color.withValues(alpha: 0.18),
            ),
          ),
          child: Padding(
            padding:
                EdgeInsets.symmetric(horizontal: 4.w, vertical: 12.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40.w,
                  height: 40.w,
                  decoration: BoxDecoration(
                    color: data.color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(data.icon, color: data.color, size: 20.sp),
                ),
                SizedBox(height: 7.h),
                Text(
                  data.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w600,
                    color: data.color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Stats Grid ────────────────────────────────────────────────────────────────

class _StatsGrid extends StatelessWidget {
  final AdminDashboardStats stats;
  const _StatsGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12.h,
      crossAxisSpacing: 12.w,
      childAspectRatio: 1.38,
      children: [
        StatCard(
          title: 'Total Assigned',
          value: AppUtils.formatCurrencyCompact(stats.totalAssigned),
          icon: Icons.upload_rounded,
          gradientColors: AppColors.blueGradient,
        ),
        StatCard(
          title: 'Total Spent',
          value: AppUtils.formatCurrencyCompact(stats.totalSpent),
          icon: Icons.download_rounded,
          gradientColors: AppColors.orangeGradient,
        ),
        StatCard(
          title: 'Net Balance',
          value: AppUtils.formatCurrencyCompact(stats.totalBalance),
          icon: Icons.account_balance_rounded,
          gradientColors: AppColors.greenGradient,
        ),
        StatCard(
          title: 'Active Employees',
          value: '${stats.activeEmployees}',
          icon: Icons.people_rounded,
          gradientColors: AppColors.purpleGradient,
          subtitle: 'of ${stats.totalEmployees} total',
        ),
      ],
    );
  }
}

// ── Alerts ────────────────────────────────────────────────────────────────────

class _AlertsSection extends StatelessWidget {
  final int pendingApprovals;
  final int missingBills;
  const _AlertsSection({
    required this.pendingApprovals,
    required this.missingBills,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (pendingApprovals > 0)
          _AlertBanner(
            icon: Icons.pending_actions_rounded,
            title: '$pendingApprovals pending approval${pendingApprovals > 1 ? 's' : ''}',
            subtitle: 'Tap to review',
            color: AppColors.warning,
            onTap: () => context.go(RouteConstants.approvalList),
          ),
        if (missingBills > 0) ...[
          SizedBox(height: 8.h),
          _AlertBanner(
            icon: Icons.receipt_long_rounded,
            title:
                '$missingBills expense${missingBills > 1 ? 's' : ''} missing bills',
            subtitle: 'Bills required for approval',
            color: AppColors.error,
            onTap: () => context.go(RouteConstants.approvalList),
          ),
        ],
        SizedBox(height: 16.h),
      ],
    );
  }
}

class _AlertBanner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _AlertBanner({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          child: Padding(
            padding:
                EdgeInsets.symmetric(horizontal: 14.w, vertical: 11.h),
            child: Row(
              children: [
                Container(
                  width: 34.w,
                  height: 34.w,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 17.sp),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10.sp,
                          color: color.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: color, size: 18.sp),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyExpenses extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 32.h),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 40.sp,
            color: AppColors.textTertiary,
          ),
          SizedBox(height: 10.h),
          Text(
            'No expenses yet',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            'Approved expenses will appear here',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11.sp,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Error View ────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 44.sp, color: AppColors.error),
            SizedBox(height: 12.h),
            Text(
              'Failed to load dashboard',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.sp,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Avatar Popup Menu ─────────────────────────────────────────────────────────

class _AvatarMenu extends ConsumerWidget {
  final dynamic user;
  const _AvatarMenu({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      offset: const Offset(0, 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (value) async {
        if (value == 'profile') {
          context.push(RouteConstants.adminProfile);
        } else if (value == 'logout') {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Text('Logout?'),
              content: const Text('Are you sure you want to log out?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Logout',
                      style: TextStyle(color: Colors.white)),
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
        const PopupMenuItem(
          value: 'profile',
          child: Row(children: [
            Icon(Icons.person_rounded),
            SizedBox(width: 10),
            Text('My Profile'),
          ]),
        ),
        PopupMenuItem(
          value: 'logout',
          child: Row(children: [
            Icon(Icons.logout_rounded, color: AppColors.error),
            const SizedBox(width: 10),
            Text('Logout',
                style: TextStyle(color: AppColors.error)),
          ]),
        ),
      ],
      child: CircleAvatar(
        radius: 18.r,
        backgroundColor: AppColors.primary,
        backgroundImage:
            user?.photoUrl != null ? NetworkImage(user!.photoUrl!) : null,
        child: user?.photoUrl == null
            ? Text(
                AppUtils.getInitials(user?.name ?? 'A'),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              )
            : null,
      ),
    );
  }
}

// ── Notification Bell ─────────────────────────────────────────────────────────

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
                  color: AppColors.error,
                  shape: BoxShape.circle,
                ),
                constraints:
                    const BoxConstraints(minWidth: 16, minHeight: 16),
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
