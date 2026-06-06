import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../employees/presentation/providers/employee_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/profile_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameCtrl     = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _phoneCtrl    = TextEditingController();
  final _addressCtrl  = TextEditingController();
  final _cityCtrl     = TextEditingController();
  final _districtCtrl = TextEditingController();
  final _stateCtrl    = TextEditingController();
  final _currentPassCtrl  = TextEditingController();
  final _newPassCtrl      = TextEditingController();
  final _confirmPassCtrl  = TextEditingController();
  bool _editingProfile = false;
  bool _obscureCurrent = true;
  bool _obscureNew     = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _districtCtrl.dispose();
    _stateCtrl.dispose();
    _currentPassCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final profileState = ref.watch(profileNotifierProvider);
    final isEmployee = user?.isEmployee ?? false;

    // For employees: watch their employee record for balance/department
    final employeeAsync = isEmployee && user != null
        ? ref.watch(employeeByIdProvider(user.uid))
        : null;

    ref.listen<ProfileState>(profileNotifierProvider, (_, next) {
      if (next.successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(next.successMessage!),
          backgroundColor: AppColors.success,
        ));
        ref.read(profileNotifierProvider.notifier).clearMessages();
        if (_editingProfile) setState(() => _editingProfile = false);
      }
      if (next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(next.errorMessage!),
          backgroundColor: AppColors.error,
        ));
        ref.read(profileNotifierProvider.notifier).clearMessages();
      }
    });

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          if (!_editingProfile && !isEmployee)
            TextButton.icon(
              icon: const Icon(Icons.edit_rounded, size: 16),
              label: const Text('Edit'),
              onPressed: () {
                _nameCtrl.text     = user.name;
                _emailCtrl.text    = user.email;
                _phoneCtrl.text    = user.phone    ?? '';
                _addressCtrl.text  = user.address  ?? '';
                _cityCtrl.text     = user.city     ?? '';
                _districtCtrl.text = user.district ?? '';
                _stateCtrl.text    = user.state    ?? '';
                setState(() => _editingProfile = true);
              },
            ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(16.w),
        children: [
          // ── Avatar section ──────────────────────────────────────────────
          Center(
            child: Stack(
              children: [
                GestureDetector(
                  onTap: () => _pickPhoto(user.uid),
                  child: CircleAvatar(
                    radius: 52.r,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                    backgroundImage: user.photoUrl != null
                        ? NetworkImage(user.photoUrl!)
                        : null,
                    child: user.photoUrl == null
                        ? Text(
                            AppUtils.getInitials(user.name),
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 28.sp,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          )
                        : null,
                  ),
                ),
                if (profileState.isUploadingPhoto)
                  Positioned.fill(
                    child: CircleAvatar(
                      radius: 52.r,
                      backgroundColor: Colors.black45,
                      child: const CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () => _pickPhoto(user.uid),
                    child: Container(
                      padding: EdgeInsets.all(8.w),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.camera_alt_rounded,
                          color: Colors.white, size: 14.sp),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12.h),

          // Name & role
          Center(
            child: Column(
              children: [
                Text(
                  user.name,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  user.email,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13.sp,
                    color: AppColors.textSecondary,
                  ),
                ),
                SizedBox(height: 8.h),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 5.h),
                  decoration: BoxDecoration(
                    color: user.isSuperadmin
                        ? Colors.purple.withValues(alpha: 0.12)
                        : user.isAdmin
                            ? AppColors.primary.withValues(alpha: 0.12)
                            : AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    user.isSuperadmin
                        ? 'Super Admin'
                        : user.isAdmin
                            ? 'Business Admin'
                            : 'Staff',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: user.isSuperadmin
                          ? Colors.purple
                          : user.isAdmin
                              ? AppColors.primary
                              : AppColors.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 24.h),

          // ── Employee balance card ────────────────────────────────────────
          if (isEmployee && employeeAsync != null)
            employeeAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (emp) => Column(
                children: [
                  Container(
                    padding: EdgeInsets.all(16.w),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: AppColors.greenGradient),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.account_balance_wallet_rounded,
                            color: Colors.white, size: 28.sp),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Current Balance',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12.sp,
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              ),
                              Text(
                                AppUtils.formatCurrency(emp.balance),
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 22.sp,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              emp.employeeId,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              emp.department,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11.sp,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16.h),
                ],
              ),
            ),

          // ── Info card ────────────────────────────────────────────────────
          if (!_editingProfile) ...[
            _InfoCard(
              title: 'Profile Details',
              items: [
                _InfoRow(Icons.person_outline_rounded, 'Name', user.name),
                _InfoRow(Icons.email_outlined, 'Email', user.email),
                if (user.phone?.isNotEmpty == true)
                  _InfoRow(Icons.phone_outlined, 'Phone', user.phone!),
                if (isEmployee && employeeAsync != null)
                  ...employeeAsync.maybeWhen(
                    data: (emp) => [
                      _InfoRow(Icons.business_rounded, 'Department', emp.department),
                    ],
                    orElse: () => [],
                  ),
                if (user.address?.isNotEmpty == true)
                  _InfoRow(Icons.location_on_outlined, 'Address', user.address!),
                if (user.city?.isNotEmpty == true || user.district?.isNotEmpty == true || user.state?.isNotEmpty == true)
                  _InfoRow(
                    Icons.map_outlined,
                    'Location',
                    [user.city, user.district, user.state]
                        .where((s) => s?.isNotEmpty == true)
                        .join(', '),
                  ),
              ],
            ),
            SizedBox(height: 16.h),
          ],

          // ── Edit form (admin/owner only — employees are read-only) ──────────
          if (_editingProfile && !isEmployee) ...[
            _SectionLabel('Edit Profile'),
            SizedBox(height: 12.h),
            AppTextField(
              label: 'Full Name',
              hint: 'Enter your name',
              controller: _nameCtrl,
              prefixIcon: const Icon(Icons.person_outline_rounded),
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            SizedBox(height: 12.h),
            AppTextField(
              label: isEmployee ? 'Email Address (Contact admin to change)' : 'Email Address',
              hint: 'Enter email address',
              controller: _emailCtrl,
              prefixIcon: const Icon(Icons.email_outlined),
              keyboardType: TextInputType.emailAddress,
              readOnly: isEmployee,
              validator: isEmployee
                  ? null
                  : (v) {
                      if (v == null || v.trim().isEmpty) return 'Email is required';
                      final regex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
                      if (!regex.hasMatch(v.trim())) return 'Enter a valid email';
                      return null;
                    },
            ),
            SizedBox(height: 12.h),
            AppTextField(
              label: 'Phone Number',
              hint: '+91 9876543210',
              controller: _phoneCtrl,
              prefixIcon: const Icon(Icons.phone_outlined),
              keyboardType: TextInputType.phone,
            ),
            SizedBox(height: 12.h),
            AppTextField(
              label: 'Street Address',
              hint: 'House / Flat / Street',
              controller: _addressCtrl,
              prefixIcon: const Icon(Icons.location_on_outlined),
              textCapitalization: TextCapitalization.sentences,
            ),
            SizedBox(height: 12.h),
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    label: 'City',
                    hint: 'City',
                    controller: _cityCtrl,
                    prefixIcon: const Icon(Icons.location_city_outlined),
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: AppTextField(
                    label: 'District',
                    hint: 'District',
                    controller: _districtCtrl,
                    prefixIcon: const Icon(Icons.map_outlined),
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            AppTextField(
              label: 'State',
              hint: 'State',
              controller: _stateCtrl,
              prefixIcon: const Icon(Icons.flag_outlined),
              textCapitalization: TextCapitalization.words,
            ),
            SizedBox(height: 16.h),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _editingProfile = false),
                    child: const Text('Cancel'),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: AppButton(
                    label: 'Save Changes',
                    onPressed: () async {
                      if (_nameCtrl.text.trim().isEmpty) return;
                      if (!isEmployee && _emailCtrl.text.trim().isEmpty) return;
                      await ref.read(profileNotifierProvider.notifier).updateProfile(
                        uid:       user.uid,
                        name:      _nameCtrl.text.trim(),
                        email:     isEmployee ? user.email : _emailCtrl.text.trim(),
                        phone:     _phoneCtrl.text.trim(),
                        address:   _addressCtrl.text.trim(),
                        city:      _cityCtrl.text.trim(),
                        district:  _districtCtrl.text.trim(),
                        stateName: _stateCtrl.text.trim(),
                      );
                    },
                    isLoading: profileState.isLoading,
                    prefixIcon: Icons.save_rounded,
                  ),
                ),
              ],
            ),
            SizedBox(height: 20.h),
          ],

          // ── Change Password ───────────────────────────────────────────────
          _SectionLabel('Security'),
          SizedBox(height: 12.h),
          _ChangePasswordSection(
            currentPassCtrl: _currentPassCtrl,
            newPassCtrl: _newPassCtrl,
            confirmPassCtrl: _confirmPassCtrl,
            obscureCurrent: _obscureCurrent,
            obscureNew: _obscureNew,
            obscureConfirm: _obscureConfirm,
            onToggleCurrent: () => setState(() => _obscureCurrent = !_obscureCurrent),
            onToggleNew: () => setState(() => _obscureNew = !_obscureNew),
            onToggleConfirm: () => setState(() => _obscureConfirm = !_obscureConfirm),
            isLoading: profileState.isLoading,
            onSubmit: () async {
              if (_newPassCtrl.text != _confirmPassCtrl.text) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('New passwords do not match.'),
                  backgroundColor: AppColors.error,
                ));
                return;
              }
              if (_newPassCtrl.text.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Password must be at least 6 characters.'),
                  backgroundColor: AppColors.error,
                ));
                return;
              }
              final ok = await ref.read(profileNotifierProvider.notifier).changePassword(
                newPassword: _newPassCtrl.text,
              );
              if (ok) {
                _currentPassCtrl.clear();
                _newPassCtrl.clear();
                _confirmPassCtrl.clear();
              }
            },
          ),
          SizedBox(height: 24.h),

          // ── Logout ────────────────────────────────────────────────────────
          AppButton(
            label: 'Logout',
            onPressed: () => _confirmLogout(context, ref),
            variant: ButtonVariant.danger,
            prefixIcon: Icons.logout_rounded,
          ),
          SizedBox(height: 32.h),
        ],
      ),
    );
  }

  Future<void> _pickPhoto(String uid) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 90,
    );
    if (picked == null) return;
    await ref.read(profileNotifierProvider.notifier).uploadProfilePhoto(
      uid: uid,
      file: File(picked.path),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout?'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(authNotifierProvider.notifier).logout();
              if (context.mounted) context.go(RouteConstants.login);
            },
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ── Info Card ─────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final String title;
  final List<Widget> items;
  const _InfoCard({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          SizedBox(height: 12.h),
          ...items,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Row(
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
        fontWeight: FontWeight.w700,
        color: AppColors.primary,
        letterSpacing: 0.5,
      ),
    );
  }
}

// ── Change Password Section ───────────────────────────────────────────────────

class _ChangePasswordSection extends StatefulWidget {
  final TextEditingController currentPassCtrl;
  final TextEditingController newPassCtrl;
  final TextEditingController confirmPassCtrl;
  final bool obscureCurrent;
  final bool obscureNew;
  final bool obscureConfirm;
  final VoidCallback onToggleCurrent;
  final VoidCallback onToggleNew;
  final VoidCallback onToggleConfirm;
  final bool isLoading;
  final VoidCallback onSubmit;

  const _ChangePasswordSection({
    required this.currentPassCtrl,
    required this.newPassCtrl,
    required this.confirmPassCtrl,
    required this.obscureCurrent,
    required this.obscureNew,
    required this.obscureConfirm,
    required this.onToggleCurrent,
    required this.onToggleNew,
    required this.onToggleConfirm,
    required this.isLoading,
    required this.onSubmit,
  });

  @override
  State<_ChangePasswordSection> createState() => _ChangePasswordSectionState();
}

class _ChangePasswordSectionState extends State<_ChangePasswordSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: EdgeInsets.all(16.w),
              child: Row(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 20.sp, color: AppColors.primary),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Text(
                      'Change Password',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(height: 1, color: Theme.of(context).dividerColor),
            Padding(
              padding: EdgeInsets.all(16.w),
              child: Column(
                children: [
                  AppTextField(
                    label: 'Current Password',
                    hint: 'Enter current password',
                    controller: widget.currentPassCtrl,
                    obscureText: widget.obscureCurrent,
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(widget.obscureCurrent
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: widget.onToggleCurrent,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  AppTextField(
                    label: 'New Password',
                    hint: 'Min 6 characters',
                    controller: widget.newPassCtrl,
                    obscureText: widget.obscureNew,
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(widget.obscureNew
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: widget.onToggleNew,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  AppTextField(
                    label: 'Confirm New Password',
                    hint: 'Re-enter new password',
                    controller: widget.confirmPassCtrl,
                    obscureText: widget.obscureConfirm,
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(widget.obscureConfirm
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: widget.onToggleConfirm,
                    ),
                  ),
                  SizedBox(height: 16.h),
                  AppButton(
                    label: 'Update Password',
                    onPressed: widget.onSubmit,
                    isLoading: widget.isLoading,
                    prefixIcon: Icons.key_rounded,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
