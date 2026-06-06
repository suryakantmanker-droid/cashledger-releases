import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/permission_matrix.dart';
import '../providers/business_context_provider.dart';

// =============================================================================
// RoleGuard — Inline permission gate for widgets
// =============================================================================
// Usage:
//   RoleGuard(
//     minimumRole: UserRole.manager,
//     child: TransferFundsButton(),
//   )
//
//   RoleGuard.permission(
//     canAccess: (p) => p.canApproveExpenses,
//     child: ApproveButton(),
//   )
// =============================================================================

class RoleGuard extends ConsumerWidget {
  /// The user must be at least this role to see [child].
  final UserRole minimumRole;

  /// Shown when access is denied. Defaults to [SizedBox.shrink].
  final Widget? fallback;

  final Widget child;

  const RoleGuard({
    required this.minimumRole,
    required this.child,
    this.fallback,
    super.key,
  });

  /// Convenience constructor that takes a predicate on [UserRole].
  /// Example:
  ///   RoleGuard.can(test: (r) => r.canApproveExpenses, child: ...)
  factory RoleGuard.can({
    required bool Function(UserRole role) test,
    required Widget child,
    Widget? fallback,
    Key? key,
  }) =>
      _PredicateRoleGuard(
        test: test,
        fallback: fallback,
        key: key,
        child: child,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentUserRoleProvider);
    if (role.isAtLeast(minimumRole)) return child;
    return fallback ?? const SizedBox.shrink();
  }
}

class _PredicateRoleGuard extends RoleGuard {
  final bool Function(UserRole) test;

  const _PredicateRoleGuard({
    required this.test,
    required super.child,
    super.fallback,
    super.key,
  }) : super(minimumRole: UserRole.viewer); // not used

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentUserRoleProvider);
    if (test(role)) return child;
    return fallback ?? const SizedBox.shrink();
  }
}

// =============================================================================
// RoleGuardRoute — Used inside GoRouter redirect for route-level protection
// =============================================================================

/// Returns a redirect path if the user's role is below [minimumRole].
/// Returns null (allow navigation) if access is permitted.
///
/// Usage inside GoRouter route:
///   redirect: (context, state) => RoleGuardRoute.check(
///     ref: ref,
///     minimumRole: UserRole.manager,
///     fallbackRoute: RouteConstants.unauthorized,
///   ),
class RoleGuardRoute {
  static String? check({
    required Ref ref,
    required UserRole minimumRole,
    required String fallbackRoute,
  }) {
    final role = ref.read(currentUserRoleProvider);
    return role.isAtLeast(minimumRole) ? null : fallbackRoute;
  }
}

// =============================================================================
// BusinessGuard — Ensures business context is loaded before rendering
// =============================================================================

/// Shows [loadingWidget] while business is being bootstrapped.
/// Shows [noBusinessWidget] if the user has no memberships.
/// Shows [child] once business context is ready.
class BusinessGuard extends ConsumerWidget {
  final Widget child;
  final Widget? loadingWidget;
  final Widget? noBusinessWidget;

  const BusinessGuard({
    required this.child,
    this.loadingWidget,
    this.noBusinessWidget,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctx = ref.watch(businessContextProvider);

    if (ctx.isLoading || ctx.isIdle) {
      return loadingWidget ??
          const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
    }

    if (ctx.needsBusinessSetup) {
      return noBusinessWidget ??
          const Scaffold(
            body: Center(
              child: Text('No business found. Contact your administrator.'),
            ),
          );
    }

    return child;
  }
}
