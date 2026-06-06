import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../employees/presentation/providers/employee_provider.dart';
import '../../../employees/data/models/employee_model.dart';
import '../providers/fund_provider.dart';

// ── Payment mode metadata ──────────────────────────────────────────────────────

const _paymentIcons = <String, IconData>{
  'Cash':      Icons.payments_rounded,
  'UPI':       Icons.phone_android_rounded,
  'NEFT/IMPS': Icons.account_balance_rounded,
  'Cheque':    Icons.receipt_long_rounded,
  'Card':      Icons.credit_card_rounded,
  'Other':     Icons.more_horiz_rounded,
};

// ── Screen ────────────────────────────────────────────────────────────────────

class FundTransferScreen extends ConsumerStatefulWidget {
  final EmployeeModel? preselectedEmployee;
  const FundTransferScreen({super.key, this.preselectedEmployee});

  @override
  ConsumerState<FundTransferScreen> createState() => _FundTransferScreenState();
}

class _FundTransferScreenState extends ConsumerState<FundTransferScreen> {
  final _formKey      = GlobalKey<FormState>();
  final _amountCtrl   = TextEditingController();
  final _purposeCtrl  = TextEditingController();
  final _notesCtrl    = TextEditingController();
  String _selectedPaymentMode = AppConstants.paymentModes.first;
  DateTime _selectedDate = DateTime.now();
  EmployeeModel? _selectedEmployee;

  @override
  void initState() {
    super.initState();
    _selectedEmployee = widget.preselectedEmployee;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _purposeCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ── Employee picker bottom sheet ─────────────────────────────────────────────

  Future<void> _pickEmployee(List<EmployeeModel> employees) async {
    final picked = await showModalBottomSheet<EmployeeModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EmployeePickerSheet(employees: employees),
    );
    if (picked != null) setState(() => _selectedEmployee = picked);
  }

  @override
  Widget build(BuildContext context) {
    final fundState     = ref.watch(fundNotifierProvider);
    final employeesAsync = ref.watch(activeEmployeesStreamProvider);
    final currentUser   = ref.watch(currentUserProvider).valueOrNull;
    final colorScheme   = Theme.of(context).colorScheme;

    ref.listen<FundState>(fundNotifierProvider, (_, next) {
      if (next.successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(next.successMessage!),
          backgroundColor: AppColors.success,
        ));
        context.pop();
      }
      if (next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(next.errorMessage!),
          backgroundColor: AppColors.error,
        ));
        ref.read(fundNotifierProvider.notifier).clearMessages();
      }
    });

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(title: const Text('Transfer Funds')),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 32.h),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Amount card ────────────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 20.h),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: AppColors.blueGradient),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Amount to Transfer',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13.sp,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          '₹',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 28.sp,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 4.w),
                        Expanded(
                          child: TextFormField(
                            controller: _amountCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                            ],
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 32.sp,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                            decoration: InputDecoration(
                              hintText: '0.00',
                              hintStyle: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 32.sp,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withValues(alpha: 0.4),
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              contentPadding: EdgeInsets.zero,
                            ),
                            validator: AppValidators.amount,
                          ),
                        ),
                      ],
                    ),
                    if (_selectedEmployee != null) ...[
                      SizedBox(height: 12.h),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.account_balance_wallet_rounded,
                                color: Colors.white.withValues(alpha: 0.8), size: 14.sp),
                            SizedBox(width: 6.w),
                            Text(
                              'Balance: ${AppUtils.formatCurrencyCompact(_selectedEmployee!.balance)}',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12.sp,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: 22.h),

              // ── Transfer To ────────────────────────────────────────────────
              _SectionLabel('Transfer To'),
              SizedBox(height: 10.h),
              employeesAsync.when(
                loading: () => const LinearProgressIndicator(),
                error:   (e, _) => Text('Error: $e'),
                data:    (employees) => _EmployeeSelectorTile(
                  selected: _selectedEmployee,
                  hasError: _formKey.currentState != null &&
                      _selectedEmployee == null,
                  onTap: () => _pickEmployee(employees),
                ),
              ),
              SizedBox(height: 16.h),

              // ── Purpose ────────────────────────────────────────────────────
              AppTextField(
                label: 'Purpose',
                hint: 'E.g. Travel expenses, office supplies…',
                controller: _purposeCtrl,
                validator: (v) => AppValidators.required(v, fieldName: 'Purpose'),
                prefixIcon: const Icon(Icons.description_outlined),
                textCapitalization: TextCapitalization.sentences,
              ),
              SizedBox(height: 16.h),

              // ── Payment Mode ───────────────────────────────────────────────
              _SectionLabel('Payment Mode'),
              SizedBox(height: 10.h),
              _PaymentModeSelector(
                selected: _selectedPaymentMode,
                onChanged: (mode) => setState(() => _selectedPaymentMode = mode),
              ),
              SizedBox(height: 16.h),

              // ── Date ───────────────────────────────────────────────────────
              _SectionLabel('Transfer Date'),
              SizedBox(height: 10.h),
              InkWell(
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (date != null) setState(() => _selectedDate = date);
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_rounded,
                          size: 18.sp, color: AppColors.textSecondary),
                      SizedBox(width: 12.w),
                      Text(
                        AppUtils.formatDate(_selectedDate),
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 14.sp),
                      ),
                      const Spacer(),
                      Icon(Icons.chevron_right_rounded,
                          size: 18.sp, color: AppColors.textSecondary),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 16.h),

              // ── Notes ──────────────────────────────────────────────────────
              AppTextField(
                label: 'Notes (Optional)',
                hint: 'Additional notes',
                controller: _notesCtrl,
                maxLines: 3,
                prefixIcon: const Icon(Icons.notes_rounded),
                textCapitalization: TextCapitalization.sentences,
              ),
              SizedBox(height: 28.h),

              // ── Submit ─────────────────────────────────────────────────────
              AppButton(
                label: 'Transfer Funds',
                onPressed: () async {
                  if (!_formKey.currentState!.validate()) return;
                  if (_selectedEmployee == null) {
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Please select an employee'),
                      backgroundColor: AppColors.error,
                    ));
                    return;
                  }
                  if (currentUser == null) return;
                  await ref.read(fundNotifierProvider.notifier).transferFund(
                    amount:       double.tryParse(_amountCtrl.text) ?? 0.0,
                    givenBy:      currentUser.uid,
                    givenByName:  currentUser.name,
                    givenTo:      _selectedEmployee!.id,
                    givenToName:  _selectedEmployee!.name,
                    purpose:      _purposeCtrl.text.trim(),
                    paymentMode:  _selectedPaymentMode,
                    notes:        _notesCtrl.text.isNotEmpty ? _notesCtrl.text.trim() : null,
                    transferDate: _selectedDate,
                  );
                },
                isLoading: fundState.isLoading,
                prefixIcon: Icons.send_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Employee Selector Tile ────────────────────────────────────────────────────

class _EmployeeSelectorTile extends StatelessWidget {
  final EmployeeModel? selected;
  final bool hasError;
  final VoidCallback onTap;
  const _EmployeeSelectorTile({
    required this.selected,
    required this.hasError,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = hasError
        ? AppColors.error
        : selected != null
            ? AppColors.primary
            : theme.dividerColor;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
        decoration: BoxDecoration(
          border: Border.all(color: borderColor, width: selected != null ? 1.5 : 1),
          borderRadius: BorderRadius.circular(12),
          color: selected != null
              ? AppColors.primary.withValues(alpha: 0.04)
              : null,
        ),
        child: Row(
          children: [
            if (selected != null) ...[
              CircleAvatar(
                radius: 18.r,
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                backgroundImage: selected!.profileImageUrl != null
                    ? NetworkImage(selected!.profileImageUrl!)
                    : null,
                child: selected!.profileImageUrl == null
                    ? Text(
                        AppUtils.getInitials(selected!.name),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      )
                    : null,
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected!.name,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${selected!.employeeId}  ·  Bal: ${AppUtils.formatCurrencyCompact(selected!.balance)}',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11.sp,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Icon(Icons.person_search_rounded,
                  size: 20.sp, color: AppColors.textSecondary),
              SizedBox(width: 12.w),
              Expanded(
                child: Text(
                  'Select employee',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14.sp,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
            Icon(Icons.keyboard_arrow_down_rounded,
                size: 20.sp,
                color: selected != null ? AppColors.primary : AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

// ── Employee Picker Bottom Sheet ──────────────────────────────────────────────

class _EmployeePickerSheet extends StatefulWidget {
  final List<EmployeeModel> employees;
  const _EmployeePickerSheet({required this.employees});

  @override
  State<_EmployeePickerSheet> createState() => _EmployeePickerSheetState();
}

class _EmployeePickerSheetState extends State<_EmployeePickerSheet> {
  final _searchCtrl = TextEditingController();
  List<EmployeeModel> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.employees;
    _searchCtrl.addListener(_onSearch);
  }

  void _onSearch() {
    final q = _searchCtrl.text.toLowerCase();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle bar
            Center(
              child: Container(
                margin: EdgeInsets.only(top: 12.h, bottom: 16.h),
                width: 40.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: Row(
                children: [
                  Text(
                    'Select Employee',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16.sp,
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
                autofocus: false,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 14.sp),
                decoration: InputDecoration(
                  hintText: 'Search by name, ID or department…',
                  hintStyle: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13.sp,
                    color: AppColors.textSecondary,
                  ),
                  prefixIcon: const Icon(Icons.search_rounded),
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
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  contentPadding: EdgeInsets.symmetric(vertical: 12.h),
                  isDense: true,
                ),
              ),
            ),
            SizedBox(height: 12.h),

            Divider(height: 1, color: theme.dividerColor),

            // Employee list
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No employees found',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14.sp,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      padding: EdgeInsets.symmetric(vertical: 8.h),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, indent: 70.w, color: theme.dividerColor),
                      itemBuilder: (_, i) {
                        final emp = _filtered[i];
                        return ListTile(
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16.w, vertical: 4.h),
                          leading: CircleAvatar(
                            radius: 22.r,
                            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                            backgroundImage: emp.profileImageUrl != null
                                ? NetworkImage(emp.profileImageUrl!)
                                : null,
                            child: emp.profileImageUrl == null
                                ? Text(
                                    AppUtils.getInitials(emp.name),
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 13.sp,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                    ),
                                  )
                                : null,
                          ),
                          title: Text(
                            emp.name,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '${emp.employeeId}  ·  ${emp.department}',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11.sp,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                AppUtils.formatCurrencyCompact(emp.balance),
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 13.sp,
                                  fontWeight: FontWeight.w700,
                                  color: emp.balance >= 0
                                      ? AppColors.success
                                      : AppColors.error,
                                ),
                              ),
                              Text(
                                'balance',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 10.sp,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          onTap: () => Navigator.pop(context, emp),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Payment Mode Selector ─────────────────────────────────────────────────────

class _PaymentModeSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  const _PaymentModeSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children: AppConstants.paymentModes.map((mode) {
        final isSelected = selected == mode;
        final icon = _paymentIcons[mode] ?? Icons.circle_outlined;
        return GestureDetector(
          onTap: () => onChanged(mode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 9.h),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary : Colors.transparent,
              border: Border.all(
                color: isSelected ? AppColors.primary : Theme.of(context).dividerColor,
                width: isSelected ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(50),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 15.sp,
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                ),
                SizedBox(width: 6.w),
                Text(
                  mode,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Section Label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontFamily: 'Poppins',
        fontSize: 13.sp,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
      ),
    );
  }
}
