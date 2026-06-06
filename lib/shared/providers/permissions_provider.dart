import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/permission_matrix.dart';
import 'business_context_provider.dart';

// =============================================================================
// Permissions providers
// =============================================================================
// Thin computed providers that delegate to UserRolePermissions extension.
// UI widgets watch these instead of calling role.canXxx directly, so they
// automatically rebuild when the active business or role changes.
// =============================================================================

/// True if the current user can approve or reject expenses.
final canApproveExpensesProvider = Provider<bool>((ref) {
  return ref.watch(currentUserRoleProvider).canApproveExpenses;
});

/// True if the current user can initiate fund transfers.
final canTransferFundsProvider = Provider<bool>((ref) {
  return ref.watch(currentUserRoleProvider).canTransferFunds;
});

/// True if the current user can add/edit/deactivate employees.
final canManageEmployeesProvider = Provider<bool>((ref) {
  return ref.watch(currentUserRoleProvider).canManageEmployees;
});

/// True if the current user can view the full reports screen.
final canViewReportsProvider = Provider<bool>((ref) {
  return ref.watch(currentUserRoleProvider).canViewReports;
});

/// True if the current user can submit expenses.
final canSubmitExpensesProvider = Provider<bool>((ref) {
  return ref.watch(currentUserRoleProvider).canSubmitExpenses;
});

/// True if the current user can see all employees' expenses (not just their own).
final canViewAllExpensesProvider = Provider<bool>((ref) {
  return ref.watch(currentUserRoleProvider).canViewAllExpenses;
});

/// True if the current user can see all ledger entries.
final canViewAllLedgerProvider = Provider<bool>((ref) {
  return ref.watch(currentUserRoleProvider).canViewAllLedger;
});

/// True if the current user can manage salary records.
final canManageSalaryProvider = Provider<bool>((ref) {
  return ref.watch(currentUserRoleProvider).canManageSalary;
});

/// True if the current user can invite members to the business.
final canInviteMembersProvider = Provider<bool>((ref) {
  return ref.watch(currentUserRoleProvider).canInviteMembers;
});

/// True if the current user is admin-level or above (admin, owner).
final isAdminLikeProvider = Provider<bool>((ref) {
  return ref.watch(currentUserRoleProvider).isAdminLike;
});

/// A single permission bundle used by screens that check multiple permissions.
/// Avoids multiple provider.watch calls when a screen needs many checks.
class PermissionBundle {
  final UserRole role;
  final bool canApproveExpenses;
  final bool canTransferFunds;
  final bool canManageEmployees;
  final bool canViewReports;
  final bool canSubmitExpenses;
  final bool canViewAllExpenses;
  final bool canViewAllLedger;
  final bool canManageSalary;
  final bool isAdminLike;

  const PermissionBundle({
    required this.role,
    required this.canApproveExpenses,
    required this.canTransferFunds,
    required this.canManageEmployees,
    required this.canViewReports,
    required this.canSubmitExpenses,
    required this.canViewAllExpenses,
    required this.canViewAllLedger,
    required this.canManageSalary,
    required this.isAdminLike,
  });
}

/// Single-watch permissions bundle for screens needing many checks.
final permissionsProvider = Provider<PermissionBundle>((ref) {
  final role = ref.watch(currentUserRoleProvider);
  return PermissionBundle(
    role:                role,
    canApproveExpenses:  role.canApproveExpenses,
    canTransferFunds:    role.canTransferFunds,
    canManageEmployees:  role.canManageEmployees,
    canViewReports:      role.canViewReports,
    canSubmitExpenses:   role.canSubmitExpenses,
    canViewAllExpenses:  role.canViewAllExpenses,
    canViewAllLedger:    role.canViewAllLedger,
    canManageSalary:     role.canManageSalary,
    isAdminLike:         role.isAdminLike,
  );
});
