import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../expenses/presentation/providers/expense_provider.dart';
import '../../../expenses/presentation/widgets/expense_list_tile.dart';

class ApprovalListScreen extends ConsumerWidget {
  const ApprovalListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingExpensesStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: pendingAsync.when(
          data: (list) => Text('Pending Approvals (${list.length})'),
          loading: () => const Text('Pending Approvals'),
          error: (_, __) => const Text('Pending Approvals'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(pendingExpensesStreamProvider);
          await Future.delayed(const Duration(milliseconds: 400));
        },
        child: pendingAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorStateWidget(message: e.toString()),
          data: (expenses) {
            if (expenses.isEmpty) {
              return LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: constraints.maxHeight,
                    child: const EmptyState(
                      icon: Icons.check_circle_outline_rounded,
                      title: 'All caught up!',
                      subtitle: 'No pending expenses to review right now.',
                    ),
                  ),
                ),
              );
            }

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.all(16.w),
              itemCount: expenses.length,
              separatorBuilder: (_, __) => SizedBox(height: 8.h),
              itemBuilder: (_, i) => ExpenseListTile(
                expense: expenses[i],
                onTap: () => context.push('/admin/expenses/${expenses[i].id}'),
              ),
            );
          },
        ),
      ),
    );
  }
}
