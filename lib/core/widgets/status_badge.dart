import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../constants/app_constants.dart';
import '../theme/app_colors.dart';

class StatusBadge extends StatelessWidget {
  final String status;
  final bool compact;

  const StatusBadge({
    super.key,
    required this.status,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color textColor;
    IconData icon;
    String label;

    switch (status.toLowerCase()) {
      case AppConstants.statusPending:
        bg = AppColors.pendingBg;
        textColor = AppColors.pendingText;
        icon = Icons.access_time_rounded;
        label = 'Pending';
        break;
      case AppConstants.statusApproved:
        bg = AppColors.approvedBg;
        textColor = AppColors.approvedText;
        icon = Icons.check_circle_rounded;
        label = 'Approved';
        break;
      case AppConstants.statusRejected:
        bg = AppColors.rejectedBg;
        textColor = AppColors.rejectedText;
        icon = Icons.cancel_rounded;
        label = 'Rejected';
        break;
      case AppConstants.statusDraft:
        bg = AppColors.borderLight;
        textColor = AppColors.textSecondary;
        icon = Icons.edit_rounded;
        label = 'Draft';
        break;
      default:
        bg = AppColors.borderLight;
        textColor = AppColors.textSecondary;
        icon = Icons.circle;
        label = status;
    }

    if (compact) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 11.sp,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14.sp, color: textColor),
          SizedBox(width: 4.w),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
