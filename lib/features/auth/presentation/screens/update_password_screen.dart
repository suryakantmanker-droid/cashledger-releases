import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/constants/route_constants.dart';

// Tracks whether we are in a password-recovery session.
// Set to true by _RouterRefreshNotifier when Supabase fires passwordRecovery.
// Set back to false here after a successful update.
final passwordRecoveryActiveProvider = StateProvider<bool>((ref) => false);

class UpdatePasswordScreen extends ConsumerStatefulWidget {
  const UpdatePasswordScreen({super.key});

  @override
  ConsumerState<UpdatePasswordScreen> createState() =>
      _UpdatePasswordScreenState();
}

class _UpdatePasswordScreenState extends ConsumerState<UpdatePasswordScreen> {
  final _formKey        = GlobalKey<FormState>();
  final _newPassCtrl    = TextEditingController();
  final _confirmCtrl    = TextEditingController();
  bool _obscureNew      = true;
  bool _obscureConfirm  = true;
  bool _isLoading       = false;

  @override
  void dispose() {
    _newPassCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _newPassCtrl.text.trim()),
      );
      if (!mounted) return;
      // Clear recovery state so router stops redirecting here
      ref.read(passwordRecoveryActiveProvider.notifier).state = false;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Password updated successfully. Please log in.'),
        backgroundColor: AppColors.success,
      ));
      // Sign out so the user logs in fresh with the new password
      await Supabase.instance.client.auth.signOut();
      if (mounted) context.go(RouteConstants.login);
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message),
        backgroundColor: AppColors.error,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to update password: $e'),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set New Password'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(24.w),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 16.h),

              // Info banner
              Container(
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_reset_rounded,
                        color: AppColors.primary, size: 22.sp),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Text(
                        'Enter a new password for your account.',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13.sp,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 28.h),

              AppTextField(
                label: 'New Password',
                hint: 'Minimum 6 characters',
                controller: _newPassCtrl,
                obscureText: _obscureNew,
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscureNew
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () =>
                      setState(() => _obscureNew = !_obscureNew),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Password is required';
                  if (v.trim().length < 6) return 'Minimum 6 characters';
                  return null;
                },
              ),
              SizedBox(height: 14.h),

              AppTextField(
                label: 'Confirm Password',
                hint: 'Re-enter new password',
                controller: _confirmCtrl,
                obscureText: _obscureConfirm,
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirm
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
                validator: (v) {
                  if (v != _newPassCtrl.text) return 'Passwords do not match';
                  return null;
                },
              ),
              SizedBox(height: 28.h),

              AppButton(
                label: 'Update Password',
                onPressed: _submit,
                isLoading: _isLoading,
                prefixIcon: Icons.check_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
