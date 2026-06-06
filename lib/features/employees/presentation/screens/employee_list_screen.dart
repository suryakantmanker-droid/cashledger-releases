import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../core/widgets/empty_state.dart';
import '../providers/employee_provider.dart';
import '../../data/models/employee_model.dart';

class EmployeeListScreen extends ConsumerWidget {
  const EmployeeListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filteredAsync = ref.watch(filteredEmployeesProvider);
    final query = ref.watch(employeeSearchQueryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Employees'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_rounded),
            onPressed: () => context.push(RouteConstants.addEmployee),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by name, email, department...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => ref
                            .read(employeeSearchQueryProvider.notifier)
                            .state = '',
                      )
                    : null,
              ),
              onChanged: (val) =>
                  ref.read(employeeSearchQueryProvider.notifier).state = val,
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(employeesStreamProvider);
                await Future.delayed(const Duration(milliseconds: 400));
              },
              child: filteredAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorStateWidget(message: e.toString()),
                data: (employees) {
                  if (employees.isEmpty) {
                    return LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: SizedBox(
                          height: constraints.maxHeight,
                          child: EmptyState(
                            icon: Icons.people_outline_rounded,
                            title: query.isNotEmpty ? 'No results found' : 'No employees yet',
                            subtitle: query.isNotEmpty
                                ? 'Try different search terms'
                                : 'Add your first employee to get started',
                            actionLabel: query.isEmpty ? 'Add Employee' : null,
                            onAction: query.isEmpty
                                ? () => context.push(RouteConstants.addEmployee)
                                : null,
                          ),
                        ),
                      ),
                    );
                  }

                  final active   = employees.where((e) => e.isActive).toList();
                  final inactive = employees.where((e) => !e.isActive).toList();

                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                    children: [
                      ...active.map((e) => Padding(
                        padding: EdgeInsets.only(bottom: 8.h),
                        child: _EmployeeTile(
                          employee: e,
                          onTap: () => context.push('/admin/employees/${e.id}'),
                        ),
                      )),
                      if (inactive.isNotEmpty) ...[
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.h),
                          child: Row(children: [
                            Expanded(child: Divider(color: Theme.of(context).dividerColor)),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10.w),
                              child: Text(
                                'Inactive (${inactive.length})',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11.sp,
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                                ),
                              ),
                            ),
                            Expanded(child: Divider(color: Theme.of(context).dividerColor)),
                          ]),
                        ),
                        ...inactive.map((e) => Padding(
                          padding: EdgeInsets.only(bottom: 8.h),
                          child: Opacity(
                            opacity: 0.5,
                            child: _EmployeeTile(
                              employee: e,
                              onTap: () => context.push('/admin/employees/${e.id}'),
                            ),
                          ),
                        )),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmployeeTile extends StatelessWidget {
  final EmployeeModel employee;
  final VoidCallback onTap;

  const _EmployeeTile({required this.employee, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: EdgeInsets.all(14.w),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          children: [
            employee.profileImageUrl != null
                ? CircleAvatar(
                    radius: 24.r,
                    backgroundImage: NetworkImage(employee.profileImageUrl!),
                  )
                : CircleAvatar(
                    radius: 24.r,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                    child: Text(
                      AppUtils.getInitials(employee.name),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        employee.name,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 6.w),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                        decoration: BoxDecoration(
                          color: employee.isActive
                              ? AppColors.approvedBg
                              : AppColors.rejectedBg,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          employee.isActive ? 'Active' : 'Inactive',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 9.sp,
                            fontWeight: FontWeight.w600,
                            color: employee.isActive
                                ? AppColors.approvedText
                                : AppColors.rejectedText,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${employee.employeeId}  •  ${employee.department}',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11.sp,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  AppUtils.formatCurrencyCompact(employee.balance),
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                    color: employee.balance >= 0 ? AppColors.success : AppColors.error,
                  ),
                ),
                Text(
                  'Balance',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10.sp,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
