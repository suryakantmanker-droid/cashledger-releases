import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_update_service.dart';
import '../theme/app_colors.dart';

class UpdateDialog extends StatelessWidget {
  final UpdateInfo info;
  const UpdateDialog({super.key, required this.info});

  /// Show the dialog. Force update = not dismissable.
  static Future<void> show(BuildContext context, UpdateInfo info) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,         // never dismiss by tapping outside
      barrierColor: Colors.black54,
      builder: (_) => UpdateDialog(info: info),
    );
  }

  Future<void> _openDownload() async {
    if (info.apkUrl.isEmpty) return;
    final uri = Uri.parse(info.apkUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // fallback — open in in-app browser
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isForce = info.isForceUpdate;

    return PopScope(
      canPop: !isForce,          // block Android back button on force update
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              // Icon
              Container(
                width: 72.w,
                height: 72.w,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: AppColors.blueGradient),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(Icons.system_update_rounded,
                    color: Colors.white, size: 36.sp),
              ),
              SizedBox(height: 18.h),

              // Title
              Text(
                isForce ? 'Update Required' : 'Update Available',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8.h),

              // Version badge
              Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 5.h),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  'v${info.currentVersion}  →  v${info.latestVersion}',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
              SizedBox(height: 14.h),

              // Description
              Text(
                isForce
                    ? 'This version is no longer supported. Please update the app to continue.'
                    : 'A new version of the app is available with improvements and bug fixes.',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13.sp,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),

              // Release notes
              if (info.releaseNotes.isNotEmpty) ...[
                SizedBox(height: 14.h),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "What's new",
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        info.releaseNotes,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12.sp,
                          color: AppColors.textPrimary,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              SizedBox(height: 22.h),

              // Update button
              SizedBox(
                width: double.infinity,
                height: 48.h,
                child: ElevatedButton.icon(
                  onPressed: info.apkUrl.isNotEmpty ? _openDownload : null,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text(
                    'Download Update',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              // Skip button — only for optional updates
              if (!isForce) ...[
                SizedBox(height: 10.h),
                SizedBox(
                  width: double.infinity,
                  height: 44.h,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Later',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13.sp,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
