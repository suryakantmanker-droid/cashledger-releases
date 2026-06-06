import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/providers/business_context_provider.dart';
import '../../data/models/department_model.dart';
import '../providers/department_provider.dart';

/// Tappable tile that opens a bottom sheet with search + create.
class DepartmentDropdown extends ConsumerWidget {
  final String? value;
  final ValueChanged<String> onChanged;
  final String? errorText;

  const DepartmentDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    this.errorText,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hasError = errorText != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () async {
            final picked = await showModalBottomSheet<String>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => ProviderScope(
                parent: ProviderScope.containerOf(context),
                child: _DepartmentPickerSheet(
                  currentValue: value,
                  ref: ref,
                ),
              ),
            );
            if (picked != null) onChanged(picked);
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
            decoration: BoxDecoration(
              border: Border.all(
                color: hasError
                    ? AppColors.error
                    : value != null
                        ? AppColors.primary
                        : theme.dividerColor,
                width: value != null ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(12),
              color: value != null
                  ? AppColors.primary.withValues(alpha: 0.04)
                  : null,
            ),
            child: Row(
              children: [
                Icon(Icons.work_outline_rounded,
                    size: 18.sp,
                    color: value != null
                        ? AppColors.primary
                        : AppColors.textSecondary),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    value ?? 'Select department',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14.sp,
                      color: value != null
                          ? theme.colorScheme.onSurface
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
                Icon(Icons.keyboard_arrow_down_rounded,
                    size: 20.sp,
                    color: value != null
                        ? AppColors.primary
                        : AppColors.textSecondary),
              ],
            ),
          ),
        ),
        if (hasError) ...[
          SizedBox(height: 4.h),
          Padding(
            padding: EdgeInsets.only(left: 14.w),
            child: Text(
              errorText!,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11.sp,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Picker Sheet ──────────────────────────────────────────────────────────────

class _DepartmentPickerSheet extends ConsumerStatefulWidget {
  final String? currentValue;
  final WidgetRef ref;
  const _DepartmentPickerSheet(
      {required this.currentValue, required this.ref});

  @override
  ConsumerState<_DepartmentPickerSheet> createState() =>
      _DepartmentPickerSheetState();
}

class _DepartmentPickerSheetState
    extends ConsumerState<_DepartmentPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _createAndSelect(
      List<DepartmentModel> existing, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    // Check duplicate locally first
    final duplicate =
        existing.any((d) => d.name.toLowerCase() == trimmed.toLowerCase());
    if (duplicate) {
      if (mounted) Navigator.pop(context, trimmed);
      return;
    }

    final businessId = ref.read(activeBusinessIdProvider);
    final notifier = ref.read(departmentNotifierProvider.notifier);
    final dept = await notifier.create(
      name:       trimmed,
      createdBy:  ref.read(activeBusinessIdProvider) ?? '',
      businessId: businessId,
    );
    if (dept != null && mounted) Navigator.pop(context, dept.name);
  }

  @override
  Widget build(BuildContext context) {
    final deptAsync = ref.watch(departmentsProvider);
    final notifierState = ref.watch(departmentNotifierProvider);
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
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
            // Handle
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

            // Title
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Row(
                children: [
                  Text(
                    'Select Department',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w700,
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
                autofocus: true,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 14.sp),
                decoration: InputDecoration(
                  hintText: 'Search or type new department…',
                  hintStyle: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13.sp,
                      color: AppColors.textSecondary),
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => _searchCtrl.clear(),
                        )
                      : null,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: theme.dividerColor)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: theme.dividerColor)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: AppColors.primary, width: 1.5)),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.4),
                  contentPadding: EdgeInsets.symmetric(vertical: 12.h),
                  isDense: true,
                ),
              ),
            ),
            SizedBox(height: 8.h),
            Divider(height: 1, color: theme.dividerColor),

            // List
            Expanded(
              child: deptAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (departments) {
                  final q = _query.toLowerCase().trim();
                  final filtered = q.isEmpty
                      ? departments
                      : departments
                          .where((d) => d.name.toLowerCase().contains(q))
                          .toList();

                  final exactMatch = departments.any(
                    (d) => d.name.toLowerCase() == q,
                  );
                  final showCreate =
                      q.isNotEmpty && !exactMatch && filtered.isEmpty;
                  final showCreateBelow =
                      q.isNotEmpty && !exactMatch && filtered.isNotEmpty;

                  return ListView(
                    controller: scrollCtrl,
                    padding: EdgeInsets.only(
                      bottom:
                          MediaQuery.of(context).padding.bottom + 16.h,
                    ),
                    children: [
                      // Create button at top when nothing matches
                      if (showCreate)
                        _CreateTile(
                          name: _query.trim(),
                          isLoading: notifierState.isLoading,
                          onTap: () => _createAndSelect(departments, _query),
                        ),

                      // Filtered list
                      ...filtered.map((dept) {
                        final isSelected =
                            widget.currentValue == dept.name;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: CircleAvatar(
                                radius: 16.r,
                                backgroundColor: dept.isGlobal
                                    ? AppColors.primary.withValues(alpha: 0.1)
                                    : AppColors.accent.withValues(alpha: 0.1),
                                child: Icon(
                                  dept.isGlobal
                                      ? Icons.public_rounded
                                      : Icons.business_rounded,
                                  size: 14.sp,
                                  color: dept.isGlobal
                                      ? AppColors.primary
                                      : AppColors.accent,
                                ),
                              ),
                              title: Text(
                                dept.name,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14.sp,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                              subtitle: Text(
                                dept.isGlobal ? 'Global' : 'Custom',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 10.sp,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              trailing: isSelected
                                  ? Icon(Icons.check_circle_rounded,
                                      color: AppColors.primary, size: 20.sp)
                                  : null,
                              onTap: () =>
                                  Navigator.pop(context, dept.name),
                            ),
                            Divider(
                                height: 1,
                                indent: 56.w,
                                color: theme.dividerColor),
                          ],
                        );
                      }),

                      // Create button below list when query doesn't exactly match
                      if (showCreateBelow)
                        _CreateTile(
                          name: _query.trim(),
                          isLoading: notifierState.isLoading,
                          onTap: () => _createAndSelect(departments, _query),
                        ),
                    ],
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

class _CreateTile extends StatelessWidget {
  final String name;
  final bool isLoading;
  final VoidCallback onTap;
  const _CreateTile(
      {required this.name, required this.isLoading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              isLoading
                  ? SizedBox(
                      width: 18.sp,
                      height: 18.sp,
                      child: const CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary),
                    )
                  : Icon(Icons.add_circle_outline_rounded,
                      color: AppColors.primary, size: 18.sp),
              SizedBox(width: 10.w),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 13.sp),
                    children: [
                      TextSpan(
                          text: 'Create  ',
                          style: TextStyle(
                              color: AppColors.textSecondary)),
                      TextSpan(
                          text: '"$name"',
                          style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
