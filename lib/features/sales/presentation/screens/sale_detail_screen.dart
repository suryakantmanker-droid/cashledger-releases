import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_utils.dart';
import '../../domain/entities/sale_entity.dart';
import '../providers/sale_provider.dart';

class SaleDetailScreen extends StatelessWidget {
  final SaleEntity sale;
  const SaleDetailScreen({super.key, required this.sale});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sale Detail')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Amount card
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 24.h),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.success,
                    AppColors.success.withValues(alpha: 0.75),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(Icons.sell_rounded, color: Colors.white, size: 36.sp),
                  SizedBox(height: 10.h),
                  Text(
                    '+${AppUtils.formatCurrency(sale.amount)}',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 28.sp,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Credited to Wallet',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12.sp,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 20.h),

            // Details card
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Column(
                children: [
                  _DetailRow(
                    icon: Icons.sell_rounded,
                    label: 'Item / Material',
                    value: sale.itemDescription,
                  ),
                  _Divider(),
                  _DetailRow(
                    icon: Icons.calendar_today_rounded,
                    label: 'Sale Date',
                    value: AppUtils.formatDate(sale.saleDate),
                  ),
                  if (sale.buyerName != null) ...[
                    _Divider(),
                    _DetailRow(
                      icon: Icons.person_outline_rounded,
                      label: 'Buyer',
                      value: sale.buyerName!,
                    ),
                  ],
                  _Divider(),
                  _DetailRow(
                    icon: Icons.tag_rounded,
                    label: 'Sale ID',
                    value: sale.saleId,
                  ),
                  _Divider(),
                  _DetailRow(
                    icon: Icons.access_time_rounded,
                    label: 'Logged On',
                    value: AppUtils.formatDateWithTime(sale.createdAt),
                  ),
                  if (sale.notes != null) ...[
                    _Divider(),
                    _DetailRow(
                      icon: Icons.notes_rounded,
                      label: 'Notes',
                      value: sale.notes!,
                    ),
                  ],
                ],
              ),
            ),

            // Proof attachments
            if (sale.hasProof) ...[
              SizedBox(height: 20.h),
              Text(
                'Proof Attachments',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 10.h),
              SizedBox(
                height: 110.h,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: sale.proofUrls.length,
                  separatorBuilder: (_, __) => SizedBox(width: 10.w),
                  itemBuilder: (_, i) {
                    final url = sale.proofUrls[i];
                    final isPdf = url.toLowerCase().contains('.pdf') ||
                        url.toLowerCase().contains('/raw/');
                    return Container(
                      width: 100.w,
                      height: 100.h,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Theme.of(context).dividerColor),
                        color: isPdf
                            ? AppColors.error.withValues(alpha: 0.08)
                            : null,
                      ),
                      child: isPdf
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.picture_as_pdf_rounded,
                                    color: AppColors.error, size: 30.sp),
                                Text('PDF',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 10.sp,
                                      color: AppColors.error,
                                    )),
                              ],
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: CachedNetworkImage(
                                imageUrl: url,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => const Center(
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)),
                                errorWidget: (_, __, ___) => const Icon(
                                    Icons.broken_image_rounded),
                              ),
                            ),
                    );
                  },
                ),
              ),
            ],

            SizedBox(height: 32.h),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18.sp, color: AppColors.textSecondary),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11.sp,
                    color: AppColors.textSecondary,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
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

/// Loads a sale by ID — used when navigating from notifications (no extra object).
class SaleDetailByIdScreen extends ConsumerWidget {
  final String saleId;
  const SaleDetailByIdScreen({super.key, required this.saleId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saleAsync = ref.watch(saleByIdProvider(saleId));

    return saleAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Scaffold(
        appBar: AppBar(title: const Text('Sale Detail')),
        body: Center(
          child: Text(
            'Could not load sale details.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14.sp,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
      data: (sale) {
        if (sale == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Sale Detail')),
            body: Center(
              child: Text(
                'Sale not found.',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14.sp,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          );
        }
        return SaleDetailScreen(sale: sale);
      },
    );
  }
}
