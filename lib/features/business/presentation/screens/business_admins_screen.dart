import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../core/constants/permission_matrix.dart';
import '../../../../shared/providers/business_context_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../widgets/business_admins_panel.dart';

class BusinessAdminsScreen extends ConsumerWidget {
  const BusinessAdminsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManageRoles = ref.watch(currentUserRoleProvider).canManageRoles;
    final businessId = ref.watch(activeBusinessIdProvider);
    final uid = ref.watch(currentUserProvider).valueOrNull?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Business Admins')),
      body: !canManageRoles
          ? const Center(child: Text('You are not authorized to manage business admins.'))
          : businessId == null || uid == null
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: EdgeInsets.all(16.w),
                  child: BusinessAdminsPanel(
                    businessId: businessId,
                    currentUserUid: uid,
                    invitedBy: uid,
                  ),
                ),
    );
  }
}
