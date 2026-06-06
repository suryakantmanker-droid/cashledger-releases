import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../core/widgets/empty_state.dart';
import '../providers/fund_provider.dart';
import '../../data/models/fund_model.dart';

class FundHistoryScreen extends ConsumerWidget {
  const FundHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fundsAsync = ref.watch(allFundsStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Fund History')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(allFundsStreamProvider);
          await Future.delayed(const Duration(milliseconds: 400));
        },
        child: fundsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorStateWidget(message: e.toString()),
          data: (funds) {
            if (funds.isEmpty) {
              return LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: constraints.maxHeight,
                    child: const EmptyState(
                      icon: Icons.history_rounded,
                      title: 'No fund transfers yet',
                      subtitle: 'Transfer funds to employees to see history here',
                    ),
                  ),
                ),
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.all(16.w),
              itemCount: funds.length,
              separatorBuilder: (_, __) => SizedBox(height: 8.h),
              itemBuilder: (_, i) => _FundTile(fund: funds[i]),
            );
          },
        ),
      ),
    );
  }
}

class _FundTile extends StatelessWidget {
  final FundModel fund;
  const _FundTile({required this.fund});

  @override
  Widget build(BuildContext context) {
    return Container(
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
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.send_rounded, color: AppColors.success, size: 20.sp),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fund.givenToName,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  fund.purpose,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12.sp,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Icon(Icons.credit_card_rounded, size: 11.sp, color: AppColors.textTertiary),
                    SizedBox(width: 3.w),
                    Text(
                      fund.paymentMode,
                      style: TextStyle(fontSize: 10.sp, color: AppColors.textTertiary, fontFamily: 'Poppins'),
                    ),
                    Text(
                      '  •  ${AppUtils.formatDate(fund.transferDate)}',
                      style: TextStyle(fontSize: 10.sp, color: AppColors.textTertiary, fontFamily: 'Poppins'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            AppUtils.formatCurrency(fund.amount),
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 15.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }
}
