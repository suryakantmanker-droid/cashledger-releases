import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/department_provider.dart';
import '../../data/models/department_model.dart';

class SuperadminDepartmentsScreen extends ConsumerStatefulWidget {
  const SuperadminDepartmentsScreen({super.key});

  @override
  ConsumerState<SuperadminDepartmentsScreen> createState() =>
      _SuperadminDepartmentsScreenState();
}

class _SuperadminDepartmentsScreenState
    extends ConsumerState<SuperadminDepartmentsScreen> {
  final _nameCtrl = TextEditingController();
  final _formKey  = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    final user = ref.read(currentUserProvider).valueOrNull;
    final dept = await ref.read(departmentNotifierProvider.notifier).create(
      name:       _nameCtrl.text.trim(),
      createdBy:  user?.uid ?? 'superadmin',
      businessId: null, // null = global
    );
    if (dept != null && mounted) {
      _nameCtrl.clear();
      Navigator.pop(context);
    }
  }

  void _showAddSheet() {
    _nameCtrl.clear();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.all(20.w),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40.w,
                    height: 4.h,
                    decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                SizedBox(height: 16.h),
                Text(
                  'Add Global Department',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  'Visible to all businesses.',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12.sp,
                    color: AppColors.textSecondary,
                  ),
                ),
                SizedBox(height: 16.h),
                TextFormField(
                  controller: _nameCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 14.sp),
                  decoration: InputDecoration(
                    labelText: 'Department Name',
                    hintText: 'e.g. Electrician, Driver…',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    prefixIcon:
                        const Icon(Icons.work_outline_rounded),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Name is required';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _create(),
                ),
                SizedBox(height: 16.h),
                Consumer(builder: (_, ref, __) {
                  final isLoading =
                      ref.watch(departmentNotifierProvider).isLoading;
                  return AppButton(
                    label: 'Add Department',
                    onPressed: _create,
                    isLoading: isLoading,
                    prefixIcon: Icons.add_rounded,
                  );
                }),
                SizedBox(height: 8.h),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deptAsync   = ref.watch(globalDepartmentsProvider);
    final notifState  = ref.watch(departmentNotifierProvider);

    ref.listen<DepartmentNotifierState>(departmentNotifierProvider, (_, next) {
      if (next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(next.error!),
          backgroundColor: AppColors.error,
        ));
        ref.read(departmentNotifierProvider.notifier).clearMessages();
      }
      if (next.success != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(next.success!),
          backgroundColor: AppColors.success,
        ));
        ref.read(departmentNotifierProvider.notifier).clearMessages();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Departments'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add global department',
            onPressed: _showAddSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          // Info banner
          Container(
            width: double.infinity,
            margin: EdgeInsets.all(16.w),
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.public_rounded,
                    color: AppColors.primary, size: 18.sp),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    'Global departments are visible to all businesses when creating employees.',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12.sp,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // List
          Expanded(
            child: deptAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorStateWidget(message: e.toString()),
              data: (departments) {
                if (departments.isEmpty) {
                  return const EmptyState(
                    icon: Icons.work_outline_rounded,
                    title: 'No departments yet',
                    subtitle:
                        'Add global departments that all businesses can use',
                  );
                }
                return ListView.separated(
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  itemCount: departments.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: Theme.of(context).dividerColor),
                  itemBuilder: (_, i) {
                    final dept = departments[i];
                    return _DeptTile(
                      dept: dept,
                      isDeleting: notifState.isLoading,
                      onDelete: () => _confirmDelete(dept),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddSheet,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Department'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  void _confirmDelete(DepartmentModel dept) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Department?'),
        content: Text(
            '"${dept.name}" will be removed from all businesses.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        ref.read(departmentNotifierProvider.notifier).delete(dept.id);
      }
    });
  }
}

class _DeptTile extends StatelessWidget {
  final DepartmentModel dept;
  final bool isDeleting;
  final VoidCallback onDelete;
  const _DeptTile(
      {required this.dept,
      required this.isDeleting,
      required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding:
          EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
      leading: CircleAvatar(
        radius: 18.r,
        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
        child: Icon(Icons.work_outline_rounded,
            size: 16.sp, color: AppColors.primary),
      ),
      title: Text(
        dept.name,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14.sp,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        'Global · Added ${_fmt(dept.createdAt)}',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 11.sp,
          color: AppColors.textSecondary,
        ),
      ),
      trailing: IconButton(
        icon: Icon(Icons.delete_outline_rounded,
            color: AppColors.error, size: 20.sp),
        onPressed: isDeleting ? null : onDelete,
        tooltip: 'Remove',
      ),
    );
  }

  String _fmt(DateTime dt) {
    final months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}
