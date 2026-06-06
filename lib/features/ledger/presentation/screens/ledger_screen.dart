import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../employees/presentation/providers/employee_provider.dart';
import '../../../employees/data/models/employee_model.dart';
import '../providers/ledger_provider.dart';
import '../../data/models/ledger_model.dart';

class LedgerScreen extends ConsumerStatefulWidget {
  const LedgerScreen({super.key});

  @override
  ConsumerState<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends ConsumerState<LedgerScreen> {
  String? _selectedEmployeeId;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final isAdmin = user?.isAdmin ?? false;

    // Keep employees stream alive so filter sheet always has data
    if (isAdmin) ref.watch(employeesStreamProvider);

    final employeeId = isAdmin ? _selectedEmployeeId : user?.uid;

    // Employees use REST to avoid Realtime RLS JWT issues; admins use Realtime stream.
    final ledgerAsync = !isAdmin && employeeId != null
        ? ref.watch(employeeLedgerRestProvider(employeeId))
        : employeeId != null
            ? ref.watch(ledgerByEmployeeProvider(employeeId))
            : ref.watch(allLedgerProvider);

    final summaryAsync = employeeId != null
        ? (!isAdmin
            ? ref.watch(employeeLedgerSummaryProvider(employeeId))
            : ref.watch(ledgerSummaryProvider(employeeId)))
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ledger'),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.filter_list_rounded),
              onPressed: () => _showEmployeeFilterSheet(context),
            ),
        ],
      ),
      body: Column(
        children: [
          // Summary Bar
          if (summaryAsync != null)
            summaryAsync.when(
              data: (summary) => _SummaryBar(summary: summary),
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const SizedBox.shrink(),
            ),

          // Ledger List
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                if (employeeId != null) {
                  if (!isAdmin) {
                    ref.invalidate(employeeLedgerRestProvider(employeeId));
                    ref.invalidate(employeeLedgerSummaryProvider(employeeId));
                  } else {
                    ref.invalidate(ledgerByEmployeeProvider(employeeId));
                    ref.invalidate(ledgerSummaryProvider(employeeId));
                  }
                } else {
                  ref.invalidate(allLedgerProvider);
                }
                await Future.delayed(const Duration(milliseconds: 400));
              },
              child: ledgerAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorStateWidget(message: e.toString()),
                data: (entries) {
                  if (entries.isEmpty) {
                    return LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: SizedBox(
                          height: constraints.maxHeight,
                          child: const EmptyState(
                            icon: Icons.account_balance_rounded,
                            title: 'No transactions yet',
                            subtitle: 'Transactions will appear here once funds are assigned',
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.all(16.w),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => SizedBox(height: 8.h),
                    itemBuilder: (_, i) => _LedgerEntry(
                      entry: entries[i],
                      isAdmin: isAdmin,
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

  void _showEmployeeFilterSheet(BuildContext context) {
    final employees = ref.read(employeesStreamProvider).valueOrNull ?? [];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EmployeeFilterSheet(
        employees: employees,
        selectedId: _selectedEmployeeId,
        onSelected: (id) => setState(() => _selectedEmployeeId = id),
      ),
    );
  }
}

// ── Employee Filter Sheet (with search) ──────────────────────────────────────

class _EmployeeFilterSheet extends StatefulWidget {
  final List<EmployeeModel> employees;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  const _EmployeeFilterSheet({
    required this.employees,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  State<_EmployeeFilterSheet> createState() => _EmployeeFilterSheetState();
}

class _EmployeeFilterSheetState extends State<_EmployeeFilterSheet> {
  final _searchCtrl = TextEditingController();
  late List<EmployeeModel> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.employees;
    _searchCtrl.addListener(_onSearch);
  }

  void _onSearch() {
    final q = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      _filtered = q.isEmpty
          ? widget.employees
          : widget.employees
              .where((e) =>
                  e.name.toLowerCase().contains(q) ||
                  e.employeeId.toLowerCase().contains(q) ||
                  e.department.toLowerCase().contains(q))
              .toList();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _select(String? id) {
    widget.onSelected(id);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: EdgeInsets.only(top: 12.h, bottom: 14.h),
                width: 40.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title row
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Row(
                children: [
                  Text(
                    'Filter by Employee',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${widget.employees.length} members',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12.sp,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12.h),

            // Search bar
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: TextField(
                controller: _searchCtrl,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 14.sp),
                decoration: InputDecoration(
                  hintText: 'Search by name, ID or department…',
                  hintStyle: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13.sp,
                    color: AppColors.textSecondary,
                  ),
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _filtered = widget.employees);
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: theme.dividerColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: theme.dividerColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.4),
                  contentPadding: EdgeInsets.symmetric(vertical: 12.h),
                  isDense: true,
                ),
              ),
            ),
            SizedBox(height: 10.h),

            Divider(height: 1, color: theme.dividerColor),

            // List
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + 16.h,
                ),
                children: [
                  // "All Employees" option
                  ListTile(
                    leading: CircleAvatar(
                      radius: 18.r,
                      backgroundColor:
                          AppColors.primary.withValues(alpha: 0.1),
                      child: Icon(Icons.people_rounded,
                          size: 16.sp, color: AppColors.primary),
                    ),
                    title: Text(
                      'All Employees',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: widget.selectedId == null
                        ? Icon(Icons.check_circle_rounded,
                            color: AppColors.primary, size: 20.sp)
                        : null,
                    selected: widget.selectedId == null,
                    onTap: () => _select(null),
                  ),
                  Divider(height: 1, color: theme.dividerColor),

                  if (_filtered.isEmpty)
                    Padding(
                      padding: EdgeInsets.all(32.w),
                      child: Center(
                        child: Text(
                          'No employees match "${_searchCtrl.text}"',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13.sp,
                            color: AppColors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    ..._filtered.map((e) {
                      final isSelected = widget.selectedId == e.id;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: CircleAvatar(
                              radius: 18.r,
                              backgroundColor: isSelected
                                  ? AppColors.primary
                                  : AppColors.primary.withValues(alpha: 0.1),
                              backgroundImage: e.profileImageUrl != null
                                  ? NetworkImage(e.profileImageUrl!)
                                  : null,
                              child: e.profileImageUrl == null
                                  ? Text(
                                      AppUtils.getInitials(e.name),
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 11.sp,
                                        fontWeight: FontWeight.w700,
                                        color: isSelected
                                            ? Colors.white
                                            : AppColors.primary,
                                      ),
                                    )
                                  : null,
                            ),
                            title: Text(
                              e.name,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 14.sp,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                            subtitle: Text(
                              '${e.employeeId}  ·  ${e.department}',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11.sp,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            trailing: isSelected
                                ? Icon(Icons.check_circle_rounded,
                                    color: AppColors.primary, size: 20.sp)
                                : null,
                            selected: isSelected,
                            onTap: () => _select(e.id),
                          ),
                          Divider(
                            height: 1,
                            indent: 58.w,
                            color: theme.dividerColor,
                          ),
                        ],
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  final LedgerSummary summary;
  const _SummaryBar({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      color: Theme.of(context).cardColor,
      child: Row(
        children: [
          _SummaryChip(
            label: 'Credit',
            value: AppUtils.formatCurrencyCompact(summary.totalCredit),
            color: AppColors.success,
            icon: Icons.add_circle_rounded,
          ),
          SizedBox(width: 8.w),
          _SummaryChip(
            label: 'Debit',
            value: AppUtils.formatCurrencyCompact(summary.totalDebit),
            color: AppColors.error,
            icon: Icons.remove_circle_rounded,
          ),
          SizedBox(width: 8.w),
          _SummaryChip(
            label: 'Balance',
            value: AppUtils.formatCurrencyCompact(summary.currentBalance),
            color: AppColors.primary,
            icon: Icons.account_balance_rounded,
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _SummaryChip({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14.sp, color: color),
            SizedBox(width: 6.w),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 9.sp,
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

class _LedgerEntry extends StatelessWidget {
  final LedgerModel entry;
  final bool isAdmin;
  const _LedgerEntry({required this.entry, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    final isCredit = entry.isCredit;
    final color = isCredit ? AppColors.success : AppColors.error;

    return InkWell(
      onTap: () => _showDetail(context),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: EdgeInsets.all(14.w),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          children: [
            Container(
              width: 44.w,
              height: 44.w,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                color: color,
                size: 20.sp,
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.remarks,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 3.h),
                  Text(
                    AppUtils.formatDateWithTime(entry.createdAt),
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10.sp,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 8.w),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${isCredit ? '+' : '-'}${AppUtils.formatCurrency(entry.amount)}',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                Text(
                  'Bal: ${AppUtils.formatCurrency(entry.balanceAfter)}',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10.sp,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            SizedBox(width: 6.w),
            Icon(Icons.chevron_right_rounded,
                size: 18.sp, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LedgerDetailSheet(
        entry: entry,
        isAdmin: isAdmin,
      ),
    );
  }
}

// ── Ledger Entry Detail Sheet ─────────────────────────────────────────────────

class _LedgerDetailSheet extends StatelessWidget {
  final LedgerModel entry;
  final bool isAdmin;
  const _LedgerDetailSheet({required this.entry, required this.isAdmin});

  bool get _isExpense    => entry.referenceType == 'expense';
  bool get _isSale       => entry.referenceType == 'sale_collection';
  bool get _isFundTransfer => entry.referenceType == 'fund_transfer';

  String get _typeLabel {
    if (_isExpense)     return 'Expense';
    if (_isSale)        return 'Sale Collection';
    if (_isFundTransfer) return 'Fund Transfer';
    return entry.referenceType;
  }

  IconData get _typeIcon {
    if (_isExpense)      return Icons.receipt_long_rounded;
    if (_isSale)         return Icons.sell_rounded;
    if (_isFundTransfer) return Icons.account_balance_wallet_rounded;
    return Icons.swap_horiz_rounded;
  }

  Color get _typeColor {
    if (_isExpense)      return AppColors.error;
    if (_isSale)         return AppColors.success;
    if (_isFundTransfer) return AppColors.primary;
    return AppColors.textSecondary;
  }

  bool get _hasDetailPage =>
      ((_isExpense || _isSale) && entry.referenceId.isNotEmpty);

  void _navigateToDetail(BuildContext context) {
    Navigator.pop(context);
    if (_isExpense) {
      final route = isAdmin
          ? '/admin/expenses/${entry.referenceId}'
          : '/employee/expenses/${entry.referenceId}';
      context.push(route);
    } else if (_isSale) {
      final route = isAdmin
          ? '/admin/sales/${entry.referenceId}'
          : '/employee/sales/${entry.referenceId}';
      context.push(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCredit = entry.isCredit;
    final amountColor = isCredit ? AppColors.success : AppColors.error;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20.w,
        right: 20.w,
        top: 12.h,
        bottom: MediaQuery.of(context).padding.bottom + 20.h,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          SizedBox(height: 18.h),

          // Header
          Row(
            children: [
              Container(
                width: 46.w,
                height: 46.w,
                decoration: BoxDecoration(
                  color: _typeColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(_typeIcon, color: _typeColor, size: 22.sp),
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _typeLabel,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11.sp,
                        color: _typeColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${isCredit ? '+' : '-'}${AppUtils.formatCurrency(entry.amount)}',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 22.sp,
                        fontWeight: FontWeight.w700,
                        color: amountColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 20.h),

          // Details list
          _Row('Remarks',    entry.remarks),
          _Divider(),
          _Row('Date',       AppUtils.formatDateWithTime(entry.date)),
          _Divider(),
          _Row('Balance After', AppUtils.formatCurrency(entry.balanceAfter)),
          _Divider(),
          _Row('Employee',   entry.employeeName),
          if (entry.referenceId.isNotEmpty) ...[
            _Divider(),
            _Row('Reference', entry.referenceId),
          ],
          SizedBox(height: 20.h),

          // Navigate to full detail
          if (_hasDetailPage)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _navigateToDetail(context),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text('View ${_isExpense ? 'Expense' : 'Sale'} Detail'),
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110.w,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.sp,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, color: Theme.of(context).dividerColor);
}
