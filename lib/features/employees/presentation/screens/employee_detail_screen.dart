import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../expenses/presentation/providers/expense_provider.dart';
import '../../../expenses/presentation/widgets/expense_list_tile.dart';
import '../providers/employee_provider.dart';

class EmployeeDetailScreen extends ConsumerWidget {
  final String employeeId;
  const EmployeeDetailScreen({super.key, required this.employeeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employeeAsync = ref.watch(employeeByIdProvider(employeeId));
    final expensesAsync = ref.watch(employeeExpensesStreamProvider(employeeId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Employee Detail'),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_reset_rounded),
            tooltip: 'Reset Password',
            onPressed: () => _showResetPasswordDialog(context, ref, employeeId),
          ),
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            onPressed: () => context.push('/admin/employees/edit/$employeeId'),
          ),
        ],
      ),
      body: employeeAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorStateWidget(message: e.toString()),
        data: (employee) => ListView(
          padding: EdgeInsets.all(16.w),
          children: [
            // Profile Header
            Container(
              padding: EdgeInsets.all(20.w),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: AppColors.blueGradient),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: CircleAvatar(
                      radius: 36.r,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      backgroundImage: employee.profileImageUrl != null
                          ? NetworkImage(employee.profileImageUrl!)
                          : null,
                      child: employee.profileImageUrl == null
                          ? Text(
                              AppUtils.getInitials(employee.name),
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 22.sp,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            )
                          : null,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  Text(
                    employee.name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    '${employee.employeeId}  •  ${employee.department}',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12.sp,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  SizedBox(height: 16.h),
                  // crossAxisAlignment.stretch gives this Row a tight width
                  // constraint (= container inner width), preventing sub-pixel
                  // accumulation from flutter_screenutil fractional values.
                  Row(
                    children: [
                      Expanded(
                        child: _StatChip(
                          label: 'Balance',
                          value: AppUtils.formatCurrencyCompact(employee.balance),
                        ),
                      ),
                      _StatDivider(),
                      Expanded(
                        child: _StatChip(
                          label: 'Assigned',
                          value: AppUtils.formatCurrencyCompact(employee.totalAssigned),
                        ),
                      ),
                      _StatDivider(),
                      Expanded(
                        child: _StatChip(
                          label: 'Spent',
                          value: AppUtils.formatCurrencyCompact(employee.totalSpent),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: 16.h),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Transfer Funds',
                    onPressed: () => context.push(
                      RouteConstants.fundTransfer,
                      extra: employee,
                    ),
                    prefixIcon: Icons.send_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppButton(
                    label: employee.isActive ? 'Deactivate' : 'Activate',
                    onPressed: () {
                      showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(employee.isActive
                              ? 'Deactivate Employee?'
                              : 'Activate Employee?'),
                          content: Text(employee.isActive
                              ? 'This will block ${employee.name} from logging in.'
                              : 'This will restore ${employee.name}\'s login access.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: employee.isActive
                                    ? AppColors.error
                                    : AppColors.success,
                              ),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(
                                employee.isActive ? 'Deactivate' : 'Activate',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ).then((confirmed) {
                        if (confirmed == true) {
                          ref
                              .read(employeeNotifierProvider.notifier)
                              .toggleStatus(employee.id, !employee.isActive);
                        }
                      });
                    },
                    variant: employee.isActive
                        ? ButtonVariant.danger
                        : ButtonVariant.outlined,
                    prefixIcon: employee.isActive
                        ? Icons.block_rounded
                        : Icons.check_circle_rounded,
                  ),
                ),
              ],
            ),
            SizedBox(height: 20.h),

            // Info Cards
            _InfoCard(
              items: [
                _InfoItem(Icons.email_outlined, 'Email', employee.email),
                _InfoItem(Icons.phone_outlined, 'Phone', employee.phone),
                _InfoItem(Icons.calendar_today_rounded, 'Joined',
                    AppUtils.formatDate(employee.createdAt)),
                if (employee.address?.isNotEmpty == true)
                  _InfoItem(Icons.location_on_outlined, 'Address', employee.address!),
                if ([employee.city, employee.district, employee.state]
                    .any((s) => s?.isNotEmpty == true))
                  _InfoItem(
                    Icons.map_outlined,
                    'Location',
                    [employee.city, employee.district, employee.state]
                        .where((s) => s?.isNotEmpty == true)
                        .join(', '),
                  ),
              ],
            ),
            SizedBox(height: 16.h),

            // Recent Expenses
            Text(
              'Recent Expenses',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8.h),
            expensesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e'),
              data: (expenses) {
                if (expenses.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: Text('No expenses yet')),
                  );
                }
                return Column(
                  children: expenses
                      .take(5)
                      .map((e) => Padding(
                            padding: EdgeInsets.only(bottom: 8.h),
                            child: ExpenseListTile(
                              expense: e,
                              onTap: () =>
                                  context.push('/admin/expenses/${e.id}'),
                            ),
                          ))
                      .toList(),
                );
              },
            ),
            SizedBox(height: 24.h),
          ],
        ),
      ),
    );
  }
}

Future<void> _showResetPasswordDialog(
    BuildContext context, WidgetRef ref, String employeeId) async {
  final newPassCtrl     = TextEditingController();
  final confirmPassCtrl = TextEditingController();
  bool obscureNew     = true;
  bool obscureConfirm = true;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('Reset Employee Password'),
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
                  icon: Icon(obscureNew ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setDialogState(() => obscureNew = !obscureNew),
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
                  icon: Icon(obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setDialogState(() => obscureConfirm = !obscureConfirm),
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
                  .read(employeeNotifierProvider.notifier)
                  .resetPassword(employeeId, newPass);
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    ),
  ).then((_) {
    newPassCtrl.dispose();
    confirmPassCtrl.dispose();
  });
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 15.sp,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 10.sp,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 32,
      color: Colors.white.withValues(alpha: 0.25),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<_InfoItem> items;
  const _InfoCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: items
            .map((item) => Padding(
                  padding: EdgeInsets.only(bottom: 12.h),
                  child: Row(
                    children: [
                      Icon(item.icon, size: 18.sp, color: AppColors.textSecondary),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.label,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 10.sp,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            Text(
                              item.value,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _InfoItem {
  final IconData icon;
  final String label;
  final String value;
  const _InfoItem(this.icon, this.label, this.value);
}
