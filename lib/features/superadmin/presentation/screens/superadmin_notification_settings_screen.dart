import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../core/theme/app_colors.dart';
import '../providers/superadmin_provider.dart';

class SuperadminNotificationSettingsScreen extends ConsumerStatefulWidget {
  const SuperadminNotificationSettingsScreen({super.key});

  @override
  ConsumerState<SuperadminNotificationSettingsScreen> createState() =>
      _SuperadminNotificationSettingsScreenState();
}

class _SuperadminNotificationSettingsScreenState
    extends ConsumerState<SuperadminNotificationSettingsScreen> {
  late TextEditingController _thresholdCtrl;

  @override
  void initState() {
    super.initState();
    final current = ref.read(superAdminWatchProvider.notifier).amountThreshold;
    _thresholdCtrl = TextEditingController(
      text: current != null ? current.toStringAsFixed(0) : '',
    );
  }

  @override
  void dispose() {
    _thresholdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final watchState     = ref.watch(superAdminWatchProvider);
    final businessesAsync = ref.watch(allBusinessesProvider);
    final colorScheme    = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Settings'),
        centerTitle: false,
      ),
      body: ListView(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        children: [
          // ── Section: Business Watch List ──────────────────────────────────
          _SectionHeader(title: 'Watch Businesses'),
          SizedBox(height: 4.h),
          Text(
            'You will only receive notifications from businesses you are watching. '
            'Default: none.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12.sp,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 12.h),

          businessesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error:   (_, __) => Text(
              'Failed to load businesses.',
              style: TextStyle(color: colorScheme.error, fontSize: 12.sp),
            ),
            data: (businesses) => Column(
              children: businesses.map((biz) {
                final isWatching = watchState.isWatching(biz.id);
                final entry      = watchState.entryFor(biz.id);
                return _BusinessWatchTile(
                  businessId:   biz.id,
                  businessName: biz.name,
                  isWatching:   isWatching,
                  watchUntil:   entry?.watchUntil,
                  onToggle: (value) async {
                    if (value) {
                      _showTimePicker(context, biz.id, biz.name);
                    } else {
                      await ref
                          .read(superAdminWatchProvider.notifier)
                          .unwatch(biz.id);
                    }
                  },
                  onTapExpiry: () => _showTimePicker(context, biz.id, biz.name),
                );
              }).toList(),
            ),
          ),

          SizedBox(height: 24.h),

          // ── Section: Amount Threshold ─────────────────────────────────────
          _SectionHeader(title: 'Amount Threshold Alert'),
          SizedBox(height: 4.h),
          Text(
            'Get notified only when a watched business has an expense or sale '
            'above this amount. Leave empty to receive all.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12.sp,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              Text(
                '₹',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: TextField(
                  controller: _thresholdCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 16.sp),
                  decoration: InputDecoration(
                    hintText: 'e.g. 10000',
                    hintStyle: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14.sp,
                      color: AppColors.textTertiary,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 14.w, vertical: 12.h,
                    ),
                    suffixIcon: _thresholdCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _thresholdCtrl.clear();
                              ref
                                  .read(superAdminWatchProvider.notifier)
                                  .setAmountThreshold(null);
                            },
                          )
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: _saveThreshold,
                ),
              ),
              SizedBox(width: 10.w),
              FilledButton(
                onPressed: () => _saveThreshold(_thresholdCtrl.text),
                child: Text(
                  'Save',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13.sp),
                ),
              ),
            ],
          ),
          SizedBox(height: 32.h),
        ],
      ),
    );
  }

  void _saveThreshold(String value) {
    final amount = double.tryParse(value.trim());
    ref.read(superAdminWatchProvider.notifier).setAmountThreshold(amount);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          amount != null
              ? 'Alert threshold set to ₹${amount.toStringAsFixed(0)}'
              : 'Threshold cleared — you will receive all notifications.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showTimePicker(BuildContext ctx, String businessId, String businessName) {
    showModalBottomSheet(
      context: ctx,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (_) => _WatchTimePicker(
        businessId:   businessId,
        businessName: businessName,
      ),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) => Text(
        title,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14.sp,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      );
}

class _BusinessWatchTile extends StatelessWidget {
  final String      businessId;
  final String      businessName;
  final bool        isWatching;
  final DateTime?   watchUntil;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTapExpiry;

  const _BusinessWatchTile({
    required this.businessId,
    required this.businessName,
    required this.isWatching,
    required this.watchUntil,
    required this.onToggle,
    required this.onTapExpiry,
  });

  String _expiryLabel() {
    if (!isWatching) return '';
    if (watchUntil == null) return 'Always';
    final diff = watchUntil!.difference(DateTime.now());
    if (diff.inDays >= 1) return 'Until ${_fmt(watchUntil!)}';
    if (diff.inHours >= 1) return 'Until ${_fmt(watchUntil!)}';
    return 'Expiring soon';
  }

  String _fmt(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year}';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin:    EdgeInsets.only(bottom: 8.h),
      padding:   EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: isWatching
            ? colorScheme.primary.withValues(alpha: 0.06)
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: isWatching ? colorScheme.primary.withValues(alpha: 0.3) : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  businessName,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (isWatching) ...[
                  SizedBox(height: 2.h),
                  GestureDetector(
                    onTap: onTapExpiry,
                    child: Text(
                      _expiryLabel(),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11.sp,
                        color: colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value:    isWatching,
            onChanged: onToggle,
          ),
        ],
      ),
    );
  }
}

class _WatchTimePicker extends ConsumerWidget {
  final String businessId;
  final String businessName;

  const _WatchTimePicker({
    required this.businessId,
    required this.businessName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = [
      ('Today only',  DateTime.now().add(const Duration(days: 1))),
      ('3 Days',      DateTime.now().add(const Duration(days: 3))),
      ('1 Week',      DateTime.now().add(const Duration(days: 7))),
      ('Always',      null as DateTime?),
    ];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 20.h, 16.w, 12.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Watch "$businessName" for:',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 14.h),
            ...options.map((opt) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    opt.$2 == null
                        ? Icons.all_inclusive_rounded
                        : Icons.schedule_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(
                    opt.$1,
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 13.sp),
                  ),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await ref
                        .read(superAdminWatchProvider.notifier)
                        .watch(businessId, until: opt.$2);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                          opt.$2 == null
                              ? 'Watching "$businessName" always'
                              : 'Watching "$businessName" until ${opt.$1.toLowerCase()}',
                        ),
                        behavior: SnackBarBehavior.floating,
                      ));
                    }
                  },
                )),
            SizedBox(height: 4.h),
          ],
        ),
      ),
    );
  }
}
