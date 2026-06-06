import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/business/domain/entities/business_membership_entity.dart';
import '../../../../shared/providers/business_context_provider.dart';
import '../../data/datasources/superadmin_datasource.dart';
import '../providers/superadmin_provider.dart';

class BusinessDetailScreen extends ConsumerWidget {
  final BusinessOverview business;
  const BusinessDetailScreen({super.key, required this.business});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final subState = ref.watch(subscriptionProvider);

    ref.listen<SubscriptionState>(subscriptionProvider, (_, next) {
      if (!context.mounted) return;
      if (next.successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(next.successMessage!),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ));
        // Defer clearMessages to avoid mutating provider state during the
        // Riverpod notification phase, which can corrupt InheritedElement dependents.
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
        title: Text(business.name),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            tooltip: 'Edit Business',
            onPressed: subState.isLoading
                ? null
                : () => context.push(
                      RouteConstants.superadminEditBusinessPath(business.id),
                      extra: business,
                    ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BusinessHeader(business: business),
            const SizedBox(height: 16),
            _StatsRow(business: business),
            const SizedBox(height: 16),
            _SubscriptionCard(business: business),
            const SizedBox(height: 24),
            Text(
              'Manage Subscription',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _SubscriptionActions(business: business, isLoading: subState.isLoading),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: subState.isLoading ? null : () => _enterAsAdmin(context, ref),
                icon: const Icon(Icons.manage_accounts_rounded),
                label: const Text('Enter as Admin'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _enterAsAdmin(BuildContext context, WidgetRef ref) async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;

    // Add superadmin to business_members so Supabase RLS allows data access.
    // Uses upsert — safe to call even if already a member.
    await ref.read(superadminDataSourceProvider).ensureSuperadminMembership(
      businessId: business.id,
      superadminUid: user.uid,
    );

    await ref.read(businessContextProvider.notifier).switchToForSuperadmin(
      businessId: business.id,
      businessName: business.name,
      userUid: user.uid,
      businessLogoUrl: business.logoUrl,
    );
    if (!context.mounted) return;
    // Defer navigation to next frame so the router finishes processing the
    // businessContextProvider state change before we trigger a second update.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) context.go(RouteConstants.adminDashboard);
    });
  }

}


// ── Business Header ────────────────────────────────────────────────────────────

class _BusinessHeader extends StatelessWidget {
  final BusinessOverview business;
  const _BusinessHeader({required this.business});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: theme.colorScheme.primaryContainer,
          backgroundImage:
              business.logoUrl != null ? NetworkImage(business.logoUrl!) : null,
          child: business.logoUrl == null
              ? Text(
                  business.name.isNotEmpty ? business.name[0].toUpperCase() : 'B',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                business.name,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _StatusBadge(business: business),
                  const SizedBox(width: 8),
                  Text(
                    business.plan.toUpperCase(),
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Created ${_fmtDate(business.createdAt)}',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

// ── Stats Row ─────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final BusinessOverview business;
  const _StatsRow({required this.business});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.people_rounded,
            label: 'Employees',
            value: '${business.employeeCount}',
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            icon: Icons.badge_rounded,
            label: 'Members',
            value: '${business.memberCount}',
            color: Colors.purple,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700, color: color),
              ),
              Text(label, style: theme.textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Subscription Card ─────────────────────────────────────────────────────────

class _SubscriptionCard extends StatelessWidget {
  final BusinessOverview business;
  const _SubscriptionCard({required this.business});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final daysLeft = business.demoDaysRemaining;

    final String statusLabel;
    final String statusDetail;
    final Color statusColor;

    if (!business.isActive ||
        business.subscriptionStatus == SubscriptionStatus.inactive) {
      statusLabel = 'Inactive';
      statusDetail = 'Business is deactivated';
      statusColor = Colors.grey;
    } else if (business.subscriptionStatus == SubscriptionStatus.expired ||
        (business.subscriptionExpiryDate != null &&
            DateTime.now().isAfter(business.subscriptionExpiryDate!))) {
      statusLabel = 'Expired';
      statusDetail = 'Subscription has expired';
      statusColor = Colors.red;
    } else if (business.subscriptionStatus == SubscriptionStatus.demo) {
      statusLabel = 'Demo';
      statusDetail = daysLeft != null
          ? '$daysLeft day${daysLeft == 1 ? '' : 's'} remaining'
          : 'Demo mode active';
      statusColor = (daysLeft != null && daysLeft <= 3) ? Colors.orange : Colors.blue;
    } else {
      statusLabel = 'Active';
      statusDetail = business.subscriptionExpiryDate != null
          ? 'Expires ${_fmtDate(business.subscriptionExpiryDate!)}'
          : 'Subscription active';
      statusColor = Colors.green;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_rounded, color: statusColor, size: 28),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                statusLabel,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
              Text(
                statusDetail,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: statusColor.withValues(alpha: 0.8)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

// ── Subscription Actions ──────────────────────────────────────────────────────

class _SubscriptionActions extends ConsumerWidget {
  final BusinessOverview business;
  final bool isLoading;

  const _SubscriptionActions({required this.business, required this.isLoading});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: () => _showSetDemoDialog(context, ref),
          icon: const Icon(Icons.timer_outlined, size: 16),
          label: const Text('Set Demo'),
        ),
        OutlinedButton.icon(
          onPressed: () =>
              ref.read(subscriptionProvider.notifier).activate(business.id),
          icon: const Icon(Icons.check_circle_outline, size: 16, color: Colors.green),
          label: const Text('Activate', style: TextStyle(color: Colors.green)),
          style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.green)),
        ),
        OutlinedButton.icon(
          onPressed: () => _confirmDeactivate(context, ref),
          icon: const Icon(Icons.block_outlined, size: 16, color: Colors.red),
          label: const Text('Deactivate', style: TextStyle(color: Colors.red)),
          style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
        ),
        if (business.ownerUid != null)
          OutlinedButton.icon(
            onPressed: () => _showResetAdminPasswordDialog(context, ref),
            icon: const Icon(Icons.lock_reset_rounded, size: 16, color: Colors.orange),
            label: const Text('Reset Admin Password', style: TextStyle(color: Colors.orange)),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.orange)),
          ),
      ],
    );
  }

  Future<void> _confirmDeactivate(BuildContext context, WidgetRef ref) async {
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      ref.read(subscriptionProvider.notifier).deactivate(business.id);
    }
  }

  Future<void> _showResetAdminPasswordDialog(BuildContext context, WidgetRef ref) async {
    final newPassCtrl     = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    bool obscureNew     = true;
    bool obscureConfirm = true;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Reset Admin Password\n${business.name}',
              style: const TextStyle(fontSize: 15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: newPassCtrl,
                obscureText: obscureNew,
                decoration: InputDecoration(
                  labelText: 'New Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(obscureNew
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () =>
                        setDialogState(() => obscureNew = !obscureNew),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmPassCtrl,
                obscureText: obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(obscureConfirm
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () =>
                        setDialogState(() => obscureConfirm = !obscureConfirm),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final newPass = newPassCtrl.text;
                if (newPass.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Password must be at least 6 characters.'),
                    backgroundColor: Colors.red,
                  ));
                  return;
                }
                if (newPass != confirmPassCtrl.text) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Passwords do not match.'),
                    backgroundColor: Colors.red,
                  ));
                  return;
                }
                Navigator.pop(ctx);
                await ref
                    .read(subscriptionProvider.notifier)
                    .resetAdminPassword(business.ownerUid!, newPass);
              },
              child: const Text('Reset Password'),
            ),
          ],
        ),
      ),
    ).then((_) {
      newPassCtrl.dispose();
      confirmPassCtrl.dispose();
    });
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
              Text('Choose duration for ${business.name}:',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [7, 14, 30].map((d) {
                  final sel = !useCustom && selectedDays == d;
                  return ChoiceChip(
                    label: Text('$d days'),
                    selected: sel,
                    selectedColor: Theme.of(ctx).colorScheme.primary,
                    labelStyle: TextStyle(
                      color: sel ? Colors.white : Theme.of(ctx).colorScheme.onSurface,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                    ),
                    onSelected: (_) => setDialogState(() {
                      selectedDays = d;
                      useCustom = false;
                    }),
                  );
                }).toList()
                  ..add(ChoiceChip(
                    label: const Text('Custom'),
                    selected: useCustom,
                    selectedColor: Theme.of(ctx).colorScheme.primary,
                    labelStyle: TextStyle(
                      color: useCustom ? Colors.white : Theme.of(ctx).colorScheme.onSurface,
                      fontWeight: useCustom ? FontWeight.w600 : FontWeight.normal,
                    ),
                    onSelected: (_) => setDialogState(() => useCustom = true),
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

// ── Status Badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final BusinessOverview business;
  const _StatusBadge({required this.business});

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
      color = (daysLeft != null && daysLeft <= 3)
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
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
      ),
    );
  }
}
