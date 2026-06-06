import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/business/domain/entities/business_membership_entity.dart';
import '../../data/datasources/superadmin_datasource.dart';
import '../providers/superadmin_provider.dart';

class SuperadminDashboardScreen extends ConsumerWidget {
  const SuperadminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final businessesAsync = ref.watch(allBusinessesProvider);
    final theme = Theme.of(context);

    ref.listen<SubscriptionState>(subscriptionProvider, (_, next) {
      if (!context.mounted) return;
      if (next.successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(next.successMessage!),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            ref.read(subscriptionProvider.notifier).clearMessages();
          }
        });
      }
      if (next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(next.errorMessage!),
          backgroundColor: theme.colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            ref.read(subscriptionProvider.notifier).clearMessages();
          }
        });
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Businesses'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(allBusinessesProvider),
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.notifications_active_outlined),
            tooltip: 'Notification Settings',
            onPressed: () => context.push(RouteConstants.superadminNotificationSettings),
          ),
          IconButton(
            icon: const Icon(Icons.work_outline_rounded),
            tooltip: 'Manage Departments',
            onPressed: () => context.push(RouteConstants.superadminDepartments),
          ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'My Profile',
            onPressed: () => context.push(RouteConstants.superadminProfile),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign Out',
            onPressed: () =>
                ref.read(authNotifierProvider.notifier).logout(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(RouteConstants.superadminCreateBusiness),
        icon: const Icon(Icons.add_business),
        label: const Text('New Business'),
      ),
      body: businessesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline,
                    size: 48, color: theme.colorScheme.error),
                const SizedBox(height: 16),
                Text('Failed to load businesses',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(e.toString(),
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(allBusinessesProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (businesses) {
          if (businesses.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.business_outlined,
                        size: 72,
                        color: theme.colorScheme.primary.withValues(alpha: 0.4)),
                    const SizedBox(height: 24),
                    Text('No businesses yet', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      'Tap "New Business" to create your first client business.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(allBusinessesProvider),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              itemCount: businesses.length,
              itemBuilder: (context, index) =>
                  _BusinessCard(business: businesses[index]),
            ),
          );
        },
      ),
    );
  }
}

// ── Business Card ─────────────────────────────────────────────────────────────

class _BusinessCard extends ConsumerWidget {
  final BusinessOverview business;

  const _BusinessCard({required this.business});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final subLoading = ref.watch(subscriptionProvider).isLoading;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          context.push(
            RouteConstants.superadminBusinessDetailPath(business.id),
            extra: business,
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              // Logo / avatar
              CircleAvatar(
                radius: 26,
                backgroundColor: theme.colorScheme.primaryContainer,
                backgroundImage: business.logoUrl != null
                    ? NetworkImage(business.logoUrl!)
                    : null,
                child: business.logoUrl == null
                    ? Text(
                        business.name.isNotEmpty
                            ? business.name[0].toUpperCase()
                            : 'B',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),

              // Name + stats + badge
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            business.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _SubscriptionBadge(business: business),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.people_outline,
                            size: 13, color: Colors.grey[600]),
                        const SizedBox(width: 3),
                        Text('${business.employeeCount} emp',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: Colors.grey[600])),
                        const SizedBox(width: 10),
                        Icon(Icons.badge_outlined,
                            size: 13, color: Colors.grey[600]),
                        const SizedBox(width: 3),
                        Text('${business.memberCount} members',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: Colors.grey[600])),
                      ],
                    ),
                  ],
                ),
              ),

              // Action menu
              subLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (action) =>
                          _handleAction(context, ref, action),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'demo',
                          child: ListTile(
                            leading: Icon(Icons.timer_outlined),
                            title: Text('Set Demo'),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'activate',
                          child: ListTile(
                            leading: Icon(Icons.check_circle_outline,
                                color: Colors.green),
                            title: Text('Activate'),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'deactivate',
                          child: ListTile(
                            leading: Icon(Icons.block_outlined,
                                color: Colors.red),
                            title: Text('Deactivate'),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleAction(
      BuildContext context, WidgetRef ref, String action) async {
    final notifier = ref.read(subscriptionProvider.notifier);

    if (action == 'activate') {
      await notifier.activate(business.id);
    } else if (action == 'deactivate') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Deactivate Business?'),
          content: Text(
              '${business.name} and all its users will lose access immediately.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.red),
              child: const Text('Deactivate'),
            ),
          ],
        ),
      );
      if (confirm == true) await notifier.deactivate(business.id);
    } else if (action == 'demo') {
      await _showSetDemoDialog(context, ref);
    }
  }

  Future<void> _showSetDemoDialog(BuildContext context, WidgetRef ref) async {
    int selectedDays = 14;
    bool useCustom = false;
    final customCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Set Demo Period'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Choose demo duration for ${business.name}:',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [7, 14, 30].map((d) {
                  return ChoiceChip(
                    label: Text('$d days'),
                    selected: !useCustom && selectedDays == d,
                    onSelected: (_) => setDialogState(() {
                      selectedDays = d;
                      useCustom = false;
                    }),
                  );
                }).toList()
                  ..add(ChoiceChip(
                    label: const Text('Custom'),
                    selected: useCustom,
                    onSelected: (_) =>
                        setDialogState(() => useCustom = true),
                  )),
              ),
              if (useCustom) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: customCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Days',
                    border: OutlineInputBorder(),
                    suffixText: 'days',
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final days = useCustom
                    ? (int.tryParse(customCtrl.text.trim()) ?? 14)
                    : selectedDays;
                Navigator.pop(ctx);
                ref.read(subscriptionProvider.notifier).setDemo(
                      business.id,
                      days: days,
                    );
              },
              child: const Text('Set Demo'),
            ),
          ],
        ),
      ),
    ).then((_) => customCtrl.dispose());
  }
}

// ── Subscription badge ─────────────────────────────────────────────────────

class _SubscriptionBadge extends StatelessWidget {
  final BusinessOverview business;

  const _SubscriptionBadge({required this.business});

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color color;

    final daysLeft = business.demoDaysRemaining;

    if (!business.isActive ||
        business.subscriptionStatus == SubscriptionStatus.inactive) {
      label = 'Inactive';
      color = Colors.grey;
    } else if (business.subscriptionStatus == SubscriptionStatus.expired ||
        (business.subscriptionExpiryDate != null &&
            DateTime.now().isAfter(business.subscriptionExpiryDate!))) {
      label = 'Expired';
      color = Colors.red.shade700;
    } else if (business.subscriptionStatus == SubscriptionStatus.demo) {
      label = daysLeft != null ? 'Demo: ${daysLeft}d' : 'Demo';
      color = daysLeft != null && daysLeft <= 3
          ? Colors.orange.shade700
          : Colors.blue.shade700;
    } else {
      label = 'Active';
      color = Colors.green.shade700;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}
