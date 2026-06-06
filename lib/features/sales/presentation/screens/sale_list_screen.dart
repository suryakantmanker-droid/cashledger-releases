import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/sale_provider.dart';

class SaleListScreen extends ConsumerWidget {
  const SaleListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    if (user == null) return const SizedBox.shrink();

    final salesAsync = ref.watch(employeeSalesStreamProvider(user.uid));

    return Scaffold(
      appBar: AppBar(title: const Text('My Sales')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(employeeSalesStreamProvider(user.uid));
          await Future.delayed(const Duration(milliseconds: 400));
        },
        child: salesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorStateWidget(message: e.toString()),
          data: (sales) {
            if (sales.isEmpty) {
              return LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: constraints.maxHeight,
                    child: EmptyState(
                      icon: Icons.sell_rounded,
                      title: 'No sales logged yet',
                      subtitle: 'Log a sale to credit your wallet instantly',
                      actionLabel: 'Log Sale',
                      onAction: () => context.push(RouteConstants.addSale),
                    ),
                  ),
                ),
              );
            }

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.all(16.w),
              itemCount: sales.length,
              separatorBuilder: (_, __) => SizedBox(height: 10.h),
              itemBuilder: (_, i) {
                final sale = sales[i];
                return InkWell(
                  onTap: () =>
                      context.push('/employee/sales/${sale.id}', extra: sale),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: EdgeInsets.all(14.w),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: Theme.of(context).dividerColor),
                    ),
                    child: Row(
                      children: [
                        // Icon
                        Container(
                          width: 44.w,
                          height: 44.w,
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.sell_rounded,
                              color: AppColors.success, size: 22.sp),
                        ),
                        SizedBox(width: 12.w),

                        // Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                sale.itemDescription,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: 3.h),
                              Text(
                                AppUtils.formatDate(sale.saleDate),
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11.sp,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              if (sale.buyerName != null) ...[
                                SizedBox(height: 2.h),
                                Text(
                                  'Buyer: ${sale.buyerName}',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 11.sp,
                                    color: AppColors.textSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),

                        // Amount + proof indicator
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '+${AppUtils.formatCurrency(sale.amount)}',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w700,
                                color: AppColors.success,
                              ),
                            ),
                            if (sale.hasProof) ...[
                              SizedBox(height: 4.h),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.attach_file_rounded,
                                      size: 11.sp,
                                      color: AppColors.textTertiary),
                                  Text(
                                    '${sale.proofUrls.length}',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 10.sp,
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
