import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/expense_provider.dart';
import '../widgets/expense_list_tile.dart';

class ExpenseListScreen extends ConsumerStatefulWidget {
  const ExpenseListScreen({super.key});

  @override
  ConsumerState<ExpenseListScreen> createState() => _ExpenseListScreenState();
}

class _ExpenseListScreenState extends ConsumerState<ExpenseListScreen> {
  String _statusFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    if (user == null) return const SizedBox.shrink();

    final expensesAsync = ref.watch(employeeExpensesStreamProvider(user.uid));

    return Scaffold(
      appBar: AppBar(title: const Text('My Expenses')),
      body: Column(
        children: [
          // Filter Chips
          SizedBox(
            height: 50.h,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
              children: [
                _FilterChip(
                  label: 'All',
                  selected: _statusFilter == 'all',
                  onTap: () => setState(() => _statusFilter = 'all'),
                ),
                SizedBox(width: 8.w),
                _FilterChip(
                  label: 'Pending',
                  selected: _statusFilter == AppConstants.statusPending,
                  onTap: () => setState(() => _statusFilter = AppConstants.statusPending),
                ),
                SizedBox(width: 8.w),
                _FilterChip(
                  label: 'Approved',
                  selected: _statusFilter == AppConstants.statusApproved,
                  onTap: () => setState(() => _statusFilter = AppConstants.statusApproved),
                ),
                SizedBox(width: 8.w),
                _FilterChip(
                  label: 'Rejected',
                  selected: _statusFilter == AppConstants.statusRejected,
                  onTap: () => setState(() => _statusFilter = AppConstants.statusRejected),
                ),
                SizedBox(width: 8.w),
                _FilterChip(
                  label: 'Draft',
                  selected: _statusFilter == AppConstants.statusDraft,
                  onTap: () => setState(() => _statusFilter = AppConstants.statusDraft),
                ),
              ],
            ),
          ),

          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(employeeExpensesStreamProvider(user.uid));
                await Future.delayed(const Duration(milliseconds: 400));
              },
              child: expensesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorStateWidget(message: e.toString()),
                data: (expenses) {
                  final filtered = _statusFilter == 'all'
                      ? expenses
                      : expenses.where((e) => e.status == _statusFilter).toList();

                  if (filtered.isEmpty) {
                    return LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: SizedBox(
                          height: constraints.maxHeight,
                          child: EmptyState(
                            icon: Icons.receipt_long_rounded,
                            title: _statusFilter == 'all'
                                ? 'No expenses yet'
                                : 'No $_statusFilter expenses',
                            subtitle: _statusFilter == 'all'
                                ? 'Submit your first expense'
                                : null,
                            actionLabel: _statusFilter == 'all' ? 'Add Expense' : null,
                            onAction: _statusFilter == 'all'
                                ? () => context.push(RouteConstants.addExpense)
                                : null,
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.all(16.w),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => SizedBox(height: 8.h),
                    itemBuilder: (_, i) => ExpenseListTile(
                      expense: filtered[i],
                      onTap: () =>
                          context.push('/employee/expenses/${filtered[i].id}'),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12.sp,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
