import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/permission_matrix.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../data/datasources/business_remote_datasource.dart';
import '../providers/business_admins_provider.dart';

/// Lists a business's owner/admin members and lets the caller add up to
/// [AppConstants.maxBusinessAdmins] total. Shared by the superadmin
/// "Edit Business" screen and the in-app "Business Admins" screen.
class BusinessAdminsPanel extends ConsumerStatefulWidget {
  final String businessId;
  final String currentUserUid;
  final String invitedBy;

  const BusinessAdminsPanel({
    super.key,
    required this.businessId,
    required this.currentUserUid,
    required this.invitedBy,
  });

  @override
  ConsumerState<BusinessAdminsPanel> createState() => _BusinessAdminsPanelState();
}

class _BusinessAdminsPanelState extends ConsumerState<BusinessAdminsPanel> {
  @override
  Widget build(BuildContext context) {
    final adminsAsync = ref.watch(businessAdminsProvider(widget.businessId));
    final actionsState = ref.watch(businessAdminsActionsProvider);

    ref.listen<BusinessAdminsActionsState>(businessAdminsActionsProvider, (_, next) {
      if (!context.mounted) return;
      if (next.successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(next.successMessage!),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ));
        ref.read(businessAdminsActionsProvider.notifier).clearMessages();
      }
      if (next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(next.errorMessage!),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ));
        ref.read(businessAdminsActionsProvider.notifier).clearMessages();
      }
    });

    return adminsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: EdgeInsets.symmetric(vertical: 12.h),
        child: Text('Failed to load admins: $e',
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ),
      data: (admins) {
        final atCap = admins.length >= AppConstants.maxBusinessAdmins;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Business Admins (${admins.length}/${AppConstants.maxBusinessAdmins})',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            ...admins.map((a) => _AdminRow(
                  admin: a,
                  isSelf: a.userUid == widget.currentUserUid,
                  isLoading: actionsState.isLoading,
                  onRevert: () => _confirmRevert(a),
                  onRemove: () => _confirmRemove(a),
                )),
            SizedBox(height: 8.h),
            if (atCap)
              Text(
                'Maximum of ${AppConstants.maxBusinessAdmins} admins reached.',
                style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
              )
            else
              AppButton(
                label: 'Add Admin',
                variant: ButtonVariant.outlined,
                prefixIcon: Icons.person_add_alt_1_outlined,
                isLoading: actionsState.isLoading,
                onPressed: _openAddAdminDialog,
              ),
          ],
        );
      },
    );
  }

  void _confirmRevert(BusinessMemberInfo admin) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revert to previous role?'),
        content: Text(
          '${admin.name} will go back to ${admin.previousRole!.displayName} '
          'and lose admin access to this business.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(businessAdminsActionsProvider.notifier).revertToPreviousRole(
                businessId: widget.businessId,
                userUid: admin.userUid,
              );
            },
            child: const Text('Revert'),
          ),
        ],
      ),
    );
  }

  void _confirmRemove(BusinessMemberInfo admin) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from business?'),
        content: Text('${admin.name} will lose all access to this business entirely.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(businessAdminsActionsProvider.notifier).removeAdmin(
                businessId: widget.businessId,
                userUid: admin.userUid,
              );
            },
            child: Text('Remove', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }

  void _openAddAdminDialog() {
    showDialog(
      context: context,
      builder: (_) => _AddAdminDialog(
        businessId: widget.businessId,
        invitedBy: widget.invitedBy,
      ),
    );
  }
}

enum _AdminRowAction { revert, remove }

class _AdminRow extends StatelessWidget {
  final BusinessMemberInfo admin;
  final bool isSelf;
  final bool isLoading;
  final VoidCallback onRevert;
  final VoidCallback onRemove;

  const _AdminRow({
    required this.admin,
    required this.isSelf,
    required this.isLoading,
    required this.onRevert,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final canRemove = admin.role != UserRole.owner && !isSelf;
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18.r,
            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
            child: Icon(Icons.person_outline_rounded, color: AppColors.primary, size: 18.sp),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(admin.name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.sp)),
                Text(admin.email, style: TextStyle(fontSize: 11.sp, color: Colors.grey[600])),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              admin.role.displayName,
              style: TextStyle(fontSize: 11.sp, color: AppColors.primary, fontWeight: FontWeight.w600),
            ),
          ),
          if (canRemove)
            PopupMenuButton<_AdminRowAction>(
              enabled: !isLoading,
              icon: Icon(Icons.more_vert_rounded, size: 18, color: Colors.grey[600]),
              onSelected: (action) {
                switch (action) {
                  case _AdminRowAction.revert:
                    onRevert();
                  case _AdminRowAction.remove:
                    onRemove();
                }
              },
              itemBuilder: (context) => [
                if (admin.previousRole != null)
                  PopupMenuItem(
                    value: _AdminRowAction.revert,
                    child: Text('Revert to ${admin.previousRole!.displayName}'),
                  ),
                const PopupMenuItem(
                  value: _AdminRowAction.remove,
                  child: Text('Remove from Business'),
                ),
              ],
            )
          else
            SizedBox(width: 40.w),
        ],
      ),
    );
  }
}

class _AddAdminDialog extends ConsumerStatefulWidget {
  final String businessId;
  final String invitedBy;

  const _AddAdminDialog({required this.businessId, required this.invitedBy});

  @override
  ConsumerState<_AddAdminDialog> createState() => _AddAdminDialogState();
}

class _AddAdminDialogState extends ConsumerState<_AddAdminDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _checking = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actionsState = ref.watch(businessAdminsActionsProvider);
    final isBusy = actionsState.isLoading || _checking;

    return AlertDialog(
      title: const Text('Add Business Admin'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(
                label: 'Full Name *',
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              SizedBox(height: 14.h),
              AppTextField(
                label: 'Email *',
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Email is required';
                  final re = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
                  if (!re.hasMatch(v.trim())) return 'Invalid email';
                  return null;
                },
              ),
              SizedBox(height: 14.h),
              AppTextField(
                label: 'Password *',
                controller: _passwordCtrl,
                obscureText: _obscure,
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Password is required';
                  if (v.length < 8) return 'Minimum 8 characters';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: isBusy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: isBusy ? null : _submit,
          child: isBusy
              ? const SizedBox(
                  height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Add'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final notifier = ref.read(businessAdminsActionsProvider.notifier);

    setState(() => _checking = true);
    final match = await notifier.findUserByEmail(
      businessId: widget.businessId,
      email: _emailCtrl.text,
    );
    if (!mounted) return;
    setState(() => _checking = false);

    // No existing account with this email — create a brand-new login.
    if (match == null) {
      final success = await notifier.inviteAdmin(
        businessId: widget.businessId,
        name: _nameCtrl.text,
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
        invitedBy: widget.invitedBy,
      );
      if (success && mounted) Navigator.pop(context);
      return;
    }

    // Already an admin/owner here — nothing to do.
    if (match.currentRole == UserRole.admin || match.currentRole == UserRole.owner) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${match.name} is already ${match.currentRole == UserRole.owner ? 'the Owner' : 'an Admin'} of this business.'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
      return;
    }

    // Existing account (different role, or not yet a member here) — confirm.
    final confirmed = await _confirmSwitchToAdmin(match);
    if (confirmed != true) return;

    final success = match.currentRole == null
        ? await notifier.addExistingUserAsAdmin(
            businessId: widget.businessId,
            userUid: match.userUid,
            invitedBy: widget.invitedBy,
          )
        : await notifier.switchToAdmin(
            businessId: widget.businessId,
            userUid: match.userUid,
          );
    if (success && mounted) Navigator.pop(context);
  }

  Future<bool?> _confirmSwitchToAdmin(ExistingUserMatch match) {
    final roleText = match.currentRole?.displayName ?? 'not yet a member of this business';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('User already exists'),
        content: Text(
          '${match.name} (${match.email}) already has an account — currently $roleText. '
          'Switch them to Admin for this business instead of creating a new login?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Switch to Admin'),
          ),
        ],
      ),
    );
  }
}
