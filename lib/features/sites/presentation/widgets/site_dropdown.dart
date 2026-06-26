import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../shared/providers/business_context_provider.dart';
import '../../data/models/site_model.dart';
import '../providers/site_provider.dart';

/// Tappable tile that opens a bottom sheet with search + create, mirroring
/// DepartmentDropdown but returning a [SiteModel] (site changes need the id,
/// not just a display name) and showing each site's address as a subtitle.
class SiteDropdown extends ConsumerWidget {
  final SiteModel? value;
  final ValueChanged<SiteModel> onChanged;
  final bool enabled;
  final String? errorText;

  const SiteDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
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
          onTap: !enabled
              ? null
              : () async {
                  final picked = await showModalBottomSheet<SiteModel>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => ProviderScope(
                      parent: ProviderScope.containerOf(context),
                      child: _SitePickerSheet(currentValue: value, ref: ref),
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
              color: !enabled
                  ? theme.disabledColor.withValues(alpha: 0.04)
                  : value != null
                      ? AppColors.primary.withValues(alpha: 0.04)
                      : null,
            ),
            child: Row(
              children: [
                Icon(Icons.location_on_outlined,
                    size: 18.sp,
                    color: value != null ? AppColors.primary : AppColors.textSecondary),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    value?.name ?? 'Select site',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14.sp,
                      color: value != null ? theme.colorScheme.onSurface : AppColors.textSecondary,
                    ),
                  ),
                ),
                if (enabled)
                  Icon(Icons.keyboard_arrow_down_rounded,
                      size: 20.sp,
                      color: value != null ? AppColors.primary : AppColors.textSecondary),
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
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11.sp, color: AppColors.error),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Picker Sheet ──────────────────────────────────────────────────────────────

class _SitePickerSheet extends ConsumerStatefulWidget {
  final SiteModel? currentValue;
  final WidgetRef ref;
  const _SitePickerSheet({required this.currentValue, required this.ref});

  @override
  ConsumerState<_SitePickerSheet> createState() => _SitePickerSheetState();
}

class _SitePickerSheetState extends ConsumerState<_SitePickerSheet> {
  final _searchCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _createAndSelect(List<SiteModel> existing, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    final duplicate = existing.any((s) => s.name.toLowerCase() == trimmed.toLowerCase());
    if (duplicate) {
      final match = existing.firstWhere((s) => s.name.toLowerCase() == trimmed.toLowerCase());
      if (mounted) Navigator.pop(context, match);
      return;
    }

    final businessId = ref.read(activeBusinessIdProvider);
    if (businessId == null) return;
    final notifier = ref.read(siteNotifierProvider.notifier);
    final site = await notifier.create(
      name:       trimmed,
      address:    _addressCtrl.text,
      businessId: businessId,
      createdBy:  ref.read(currentUserProvider).valueOrNull?.uid ?? '',
    );
    if (site != null && mounted) Navigator.pop(context, site);
  }

  @override
  Widget build(BuildContext context) {
    final sitesAsync = ref.watch(sitesProvider);
    final notifierState = ref.watch(siteNotifierProvider);
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
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
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Text('Select Site',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 15.sp, fontWeight: FontWeight.w700)),
            ),
            SizedBox(height: 12.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 14.sp),
                decoration: InputDecoration(
                  hintText: 'Search or type new site name…',
                  hintStyle: TextStyle(fontFamily: 'Poppins', fontSize: 13.sp, color: AppColors.textSecondary),
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => _searchCtrl.clear())
                      : null,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: theme.dividerColor)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: theme.dividerColor)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  contentPadding: EdgeInsets.symmetric(vertical: 12.h),
                  isDense: true,
                ),
              ),
            ),
            SizedBox(height: 8.h),
            Divider(height: 1, color: theme.dividerColor),
            Expanded(
              child: sitesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (sites) {
                  final q = _query.toLowerCase().trim();
                  final filtered = q.isEmpty
                      ? sites
                      : sites.where((s) => s.name.toLowerCase().contains(q)).toList();
                  final exactMatch = sites.any((s) => s.name.toLowerCase() == q);
                  final showCreate = q.isNotEmpty && !exactMatch;

                  return ListView(
                    controller: scrollCtrl,
                    padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 16.h),
                    children: [
                      if (showCreate) ...[
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                          child: TextField(
                            controller: _addressCtrl,
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 13.sp),
                            decoration: InputDecoration(
                              hintText: 'Site address (optional)',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        _CreateTile(
                          name: _query.trim(),
                          isLoading: notifierState.isLoading,
                          onTap: () => _createAndSelect(sites, _query),
                        ),
                      ],
                      ...filtered.map((site) {
                        final isSelected = widget.currentValue?.id == site.id;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: CircleAvatar(
                                radius: 16.r,
                                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                child: Icon(Icons.location_on_outlined, size: 14.sp, color: AppColors.primary),
                              ),
                              title: Text(
                                site.name,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14.sp,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                ),
                              ),
                              subtitle: site.address.isNotEmpty
                                  ? Text(site.address,
                                      style: TextStyle(fontFamily: 'Poppins', fontSize: 10.sp, color: AppColors.textSecondary))
                                  : null,
                              trailing: isSelected
                                  ? Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20.sp)
                                  : null,
                              onTap: () => Navigator.pop(context, site),
                            ),
                            Divider(height: 1, indent: 56.w, color: theme.dividerColor),
                          ],
                        );
                      }),
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
  const _CreateTile({required this.name, required this.isLoading, required this.onTap});

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
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              isLoading
                  ? SizedBox(
                      width: 18.sp,
                      height: 18.sp,
                      child: const CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                  : Icon(Icons.add_circle_outline_rounded, color: AppColors.primary, size: 18.sp),
              SizedBox(width: 10.w),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 13.sp),
                    children: [
                      TextSpan(text: 'Create  ', style: TextStyle(color: AppColors.textSecondary)),
                      TextSpan(text: '"$name"', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
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
