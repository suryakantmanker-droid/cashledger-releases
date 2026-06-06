import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import '../../core/services/notification_service_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/domain/entities/user_entity.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/no_business_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/auth/presentation/screens/subscription_expired_screen.dart';
import '../../features/dashboard/presentation/screens/admin_dashboard_screen.dart';
import '../../features/dashboard/presentation/screens/employee_dashboard_screen.dart';
import '../../features/employees/data/models/employee_model.dart';
import '../../features/employees/presentation/screens/add_employee_screen.dart';
import '../../features/employees/presentation/screens/employee_detail_screen.dart';
import '../../features/employees/presentation/screens/employee_list_screen.dart';
import '../../features/expenses/presentation/screens/add_expense_screen.dart';
import '../../features/expenses/presentation/screens/expense_detail_screen.dart';
import '../../features/expenses/presentation/screens/expense_list_screen.dart';
import '../../features/sales/domain/entities/sale_entity.dart';
import '../../features/sales/presentation/screens/add_sale_screen.dart';
import '../../features/sales/presentation/screens/sale_detail_screen.dart'
    show SaleDetailScreen, SaleDetailByIdScreen;
import '../../features/sales/presentation/screens/sale_list_screen.dart';
import '../../features/funds/presentation/screens/fund_history_screen.dart';
import '../../features/funds/presentation/screens/fund_transfer_screen.dart';
import '../../features/ledger/presentation/screens/ledger_screen.dart';
import '../../features/reports/presentation/screens/reports_screen.dart';
import '../../features/approval/presentation/screens/approval_list_screen.dart';
import '../../features/auth/presentation/screens/profile_screen.dart';
import '../../features/notifications/presentation/screens/notification_screen.dart';
import '../constants/permission_matrix.dart';
import '../../shared/providers/business_context_provider.dart';
import '../../features/superadmin/presentation/screens/superadmin_dashboard_screen.dart';
import '../../features/superadmin/presentation/screens/create_business_screen.dart';
import '../../features/superadmin/presentation/screens/business_detail_screen.dart';
import '../../features/superadmin/presentation/screens/edit_business_screen.dart';
import '../../features/superadmin/presentation/screens/superadmin_notification_settings_screen.dart';
import '../../features/superadmin/data/datasources/superadmin_datasource.dart';
import '../../features/departments/presentation/screens/superadmin_departments_screen.dart';
import '../constants/app_constants.dart';
import '../constants/route_constants.dart';
import '../../features/auth/presentation/screens/update_password_screen.dart';
import '../services/app_update_service.dart';
import '../widgets/update_dialog.dart';

// Runs update check once per app session across all shells.
bool _updateChecked = false;

Future<void> _checkForUpdate(BuildContext context) async {
  if (_updateChecked) return;
  _updateChecked = true;
  final info = await AppUpdateService.check();
  if (info == null) return;
  if (!context.mounted) return;
  await UpdateDialog.show(context, info);
}

// Module-level navigator keys — must outlive the provider to keep GoRouter stable
final _adminShellKey    = GlobalKey<NavigatorState>();
final _employeeShellKey = GlobalKey<NavigatorState>();
final _superadminShellKey = GlobalKey<NavigatorState>();

// Notifies GoRouter when auth status OR business context status changes.
// Also triggers businessContextProvider.loadForUser() when a user is first detected.
class _RouterRefreshNotifier extends ChangeNotifier {
  bool isPasswordRecovery = false;

  _RouterRefreshNotifier(Ref ref) {
    // Listen for Supabase passwordRecovery event (deep link from reset email).
    // When fired, set the flag so the redirect sends the user to /update-password.
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        isPasswordRecovery = true;
        notifyListeners();
      } else if (data.event == AuthChangeEvent.userUpdated ||
          data.event == AuthChangeEvent.signedOut) {
        if (isPasswordRecovery) {
          isPasswordRecovery = false;
          notifyListeners();
        }
      }
    });

    String? prevStatus;

    void check(UserEntity? user) {
      final status = user != null ? '${user.uid}:${user.role}' : null;
      if (status != prevStatus) {
        prevStatus = status;
        if (user != null) {
          ref.read(businessContextProvider.notifier).loadForUser(
            user.uid,
            isSuperadmin: user.isSuperadmin,
          );
        }
        notifyListeners();
      }
    }

    // Stream-based auth state (Firebase realtime)
    ref.listen<AsyncValue<UserEntity?>>(currentUserProvider, (_, next) {
      if (next.isLoading) return;
      check(next.valueOrNull);
    });

    // Notifier-based auth state — fires immediately after login/logout,
    // before the Firebase stream has a chance to emit.
    ref.listen<AuthState>(authNotifierProvider, (_, next) {
      if (!next.isLoading) check(next.user);
    });

    // Re-evaluate router whenever business context status changes
    // (e.g. idle → loading → loaded, or loaded → needsBusinessSetup)
    ref.listen<BusinessContextState>(businessContextProvider, (prev, next) {
      if (prev?.status != next.status) notifyListeners();
    });

    // ref.listen does NOT fire for the already-current value — only for
    // subsequent changes. On a warm restart or hot reload, both auth
    // providers may already be resolved, so we do an immediate check here
    // to ensure loadForUser is called even if no change event fires.
    final existingUser = ref.read(currentUserProvider).valueOrNull
        ?? ref.read(authNotifierProvider).user;
    if (existingUser != null) {
      check(existingUser);
    }
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterRefreshNotifier(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: RouteConstants.splash,
    debugLogDiagnostics: false,
    refreshListenable: notifier,
    redirect: (context, state) {
      final authAsync = ref.read(currentUserProvider);
      final notifierState = ref.read(authNotifierProvider);

      // Use stream user when available; fall back to notifier user so that
      // navigation triggered right after login (before the stream emits) is
      // not blocked.
      final user = authAsync.valueOrNull ?? notifierState.user;
      final isAuthenticated = user != null;

      final loc = state.matchedLocation;
      final isOnAuthScreen = loc == RouteConstants.login ||
          loc == RouteConstants.forgotPassword ||
          loc == RouteConstants.splash;

      if (authAsync.isLoading) return null;

      // ── Password-recovery deep link ──────────────────────────────────────
      // Supabase fired AuthChangeEvent.passwordRecovery — keep user on the
      // update-password screen regardless of auth state.
      if (notifier.isPasswordRecovery) {
        return loc == RouteConstants.updatePassword
            ? null
            : RouteConstants.updatePassword;
      }

      // ── Not authenticated ────────────────────────────────────────────────
      if (!isAuthenticated) {
        return isOnAuthScreen ? null : RouteConstants.login;
      }

      // ── Authenticated — wait for business context to settle ──────────────
      final businessCtx = ref.read(businessContextProvider);
      final isSuperadmin = user.isSuperadmin;

      if (businessCtx.isIdle || businessCtx.isLoading) return null;

      // ── Superadmin routing ───────────────────────────────────────────────
      if (isSuperadmin) {
        if (loc.startsWith('/superadmin')) return null;
        if (isOnAuthScreen) return RouteConstants.superadminDashboard;
        // Only allow admin/employee routes when superadmin explicitly entered a business
        if (businessCtx.activeMembership != null) return null;
        return RouteConstants.superadminDashboard;
      }

      // ── No business membership ───────────────────────────────────────────
      if (businessCtx.needsBusinessSetup) {
        return loc == RouteConstants.noBusinessSetup
            ? null
            : RouteConstants.noBusinessSetup;
      }

      // ── Subscription / demo expiry check ─────────────────────────────────
      final membership = businessCtx.activeMembership;
      final subscriptionBlocked =
          membership != null && !membership.isSubscriptionValid;

      if (subscriptionBlocked) {
        return loc == RouteConstants.subscriptionExpired
            ? null
            : RouteConstants.subscriptionExpired;
      }
      if (loc == RouteConstants.subscriptionExpired) {
        // Subscription was re-activated — redirect to dashboard
        final role = ref.read(currentUserRoleProvider);
        return role.isAdminLike
            ? RouteConstants.adminDashboard
            : RouteConstants.employeeDashboard;
      }

      // ── Business loaded — route away from auth/setup screens ─────────────
      if (isOnAuthScreen || loc == RouteConstants.noBusinessSetup) {
        final role = ref.read(currentUserRoleProvider);
        return role.isAdminLike
            ? RouteConstants.adminDashboard
            : RouteConstants.employeeDashboard;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: RouteConstants.splash,
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: RouteConstants.login,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: RouteConstants.forgotPassword,
        builder: (_, __) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: RouteConstants.updatePassword,
        builder: (_, __) => const UpdatePasswordScreen(),
      ),
      GoRoute(
        path: RouteConstants.noBusinessSetup,
        builder: (_, __) => const NoBusinessScreen(),
      ),
      GoRoute(
        path: RouteConstants.unauthorized,
        builder: (_, __) => const _UnauthorizedScreen(),
      ),
      GoRoute(
        path: RouteConstants.subscriptionExpired,
        builder: (_, __) => const SubscriptionExpiredScreen(),
      ),

      // ── Admin Shell ───────────────────────────────────────────────────────
      ShellRoute(
        navigatorKey: _adminShellKey,
        builder: (context, state, child) => AdminShell(
          navigatorKey: _adminShellKey,
          child: child,
        ),
        routes: [
          GoRoute(
            path: RouteConstants.adminDashboard,
            builder: (_, __) => const AdminDashboardScreen(),
          ),
          GoRoute(
            path: RouteConstants.employeeList,
            builder: (_, __) => const EmployeeListScreen(),
          ),
          GoRoute(
            path: RouteConstants.addEmployee,
            builder: (_, __) => const AddEmployeeScreen(),
          ),
          GoRoute(
            path: '/admin/employees/edit/:id',
            builder: (_, state) =>
                AddEmployeeScreen(employeeId: state.pathParameters['id']),
          ),
          GoRoute(
            path: '/admin/employees/:id',
            builder: (_, state) =>
                EmployeeDetailScreen(employeeId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: RouteConstants.fundTransfer,
            builder: (_, state) => FundTransferScreen(
              preselectedEmployee: state.extra is EmployeeModel
                  ? state.extra as EmployeeModel
                  : null,
            ),
          ),
          GoRoute(
            path: RouteConstants.fundHistory,
            builder: (_, __) => const FundHistoryScreen(),
          ),
          GoRoute(
            path: RouteConstants.approvalList,
            builder: (_, __) => const ApprovalListScreen(),
          ),
          GoRoute(
            path: '/admin/expenses/:id',
            builder: (_, state) =>
                ExpenseDetailScreen(expenseId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: RouteConstants.adminLedger,
            builder: (_, __) => const LedgerScreen(),
          ),
          GoRoute(
            path: '/admin/sales/:id',
            builder: (_, state) {
              final saleId = state.pathParameters['id']!;
              if (state.extra is SaleEntity) {
                return SaleDetailScreen(sale: state.extra as SaleEntity);
              }
              return SaleDetailByIdScreen(saleId: saleId);
            },
          ),
          GoRoute(
            path: RouteConstants.adminReports,
            builder: (_, __) => const ReportsScreen(),
          ),
          GoRoute(
            path: RouteConstants.adminNotifications,
            builder: (_, __) => const NotificationScreen(),
          ),
          GoRoute(
            path: RouteConstants.adminProfile,
            builder: (_, __) => const ProfileScreen(),
          ),
        ],
      ),

      // ── Employee Shell ────────────────────────────────────────────────────
      ShellRoute(
        navigatorKey: _employeeShellKey,
        builder: (context, state, child) => EmployeeShell(
          navigatorKey: _employeeShellKey,
          child: child,
        ),
        routes: [
          GoRoute(
            path: RouteConstants.employeeDashboard,
            builder: (_, __) => const EmployeeDashboardScreen(),
          ),
          GoRoute(
            path: RouteConstants.addExpense,
            builder: (_, __) => const AddExpenseScreen(),
          ),
          GoRoute(
            path: '/employee/expenses/edit/:id',
            builder: (_, state) =>
                AddExpenseScreen(expenseId: state.pathParameters['id']),
          ),
          GoRoute(
            path: RouteConstants.expenseList,
            builder: (_, __) => const ExpenseListScreen(),
          ),
          GoRoute(
            path: '/employee/expenses/:id',
            builder: (_, state) =>
                ExpenseDetailScreen(expenseId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: RouteConstants.employeeLedger,
            builder: (_, __) => const LedgerScreen(),
          ),
          GoRoute(
            path: RouteConstants.saleList,
            builder: (_, __) => const SaleListScreen(),
          ),
          GoRoute(
            path: RouteConstants.addSale,
            builder: (_, __) => const AddSaleScreen(),
          ),
          GoRoute(
            path: '/employee/sales/:id',
            builder: (_, state) {
              final saleId = state.pathParameters['id']!;
              if (state.extra is SaleEntity) {
                return SaleDetailScreen(sale: state.extra as SaleEntity);
              }
              return SaleDetailByIdScreen(saleId: saleId);
            },
          ),
          GoRoute(
            path: RouteConstants.employeeNotifications,
            builder: (_, __) => const NotificationScreen(),
          ),
          GoRoute(
            path: RouteConstants.employeeProfile,
            builder: (_, __) => const ProfileScreen(),
          ),
        ],
      ),

      // ── Superadmin Shell ──────────────────────────────────────────────────
      ShellRoute(
        navigatorKey: _superadminShellKey,
        builder: (context, state, child) => SuperadminShell(
          navigatorKey: _superadminShellKey,
          child: child,
        ),
        routes: [
          GoRoute(
            path: RouteConstants.superadminDashboard,
            builder: (_, __) => const SuperadminDashboardScreen(),
          ),
          GoRoute(
            path: RouteConstants.superadminCreateBusiness,
            builder: (_, __) => const CreateBusinessScreen(),
          ),
          GoRoute(
            path: RouteConstants.superadminBusinessDetail,
            builder: (_, state) {
              final business = state.extra is BusinessOverview
                  ? state.extra as BusinessOverview
                  : null;
              if (business == null) return const SuperadminDashboardScreen();
              return BusinessDetailScreen(business: business);
            },
            routes: [
              GoRoute(
                path: 'edit',
                builder: (_, state) {
                  final business = state.extra is BusinessOverview
                      ? state.extra as BusinessOverview
                      : null;
                  if (business == null) return const SuperadminDashboardScreen();
                  return EditBusinessScreen(business: business);
                },
              ),
            ],
          ),
          GoRoute(
            path: RouteConstants.superadminDepartments,
            builder: (_, __) => const SuperadminDepartmentsScreen(),
          ),
          GoRoute(
            path: RouteConstants.superadminProfile,
            builder: (_, __) => const ProfileScreen(),
          ),
          GoRoute(
            path: RouteConstants.superadminNotificationSettings,
            builder: (_, __) => const SuperadminNotificationSettingsScreen(),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Page not found: ${state.error}'),
      ),
    ),
  );
});

// ── Navigation Shell Widgets ───────────────────────────────────────────────

class AdminShell extends ConsumerStatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  const AdminShell({super.key, required this.child, required this.navigatorKey});

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  DateTime? _lastBackPress;
  StreamSubscription? _tapSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initFcm();
      _checkForUpdate(context);
    });
  }

  Future<void> _initFcm() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    final businessId =
        ref.read(activeBusinessIdProvider) ?? AppConstants.defaultBusinessId;
    final notifService = ref.read(notificationServiceProvider);
    await notifService.initialize();
    await notifService.saveTokenToDatabase(user.uid);
    await notifService.subscribeToTopic('admin_$businessId');
    await notifService.subscribeToTopic('business_$businessId');
    _tapSubscription = notifService.onNotificationTap.listen((_) {
      if (mounted) context.push(RouteConstants.adminNotifications);
    });
  }

  @override
  void dispose() {
    _tapSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSuperadmin = ref.watch(isSuperadminProvider);

    ref.listen<String?>(activeBusinessIdProvider, (prev, next) async {
      final notifService = ref.read(notificationServiceProvider);
      if (next != null) {
        await notifService.subscribeToTopic('admin_$next');
        await notifService.subscribeToTopic('business_$next');
      }
      if (prev != null && prev != next) {
        await notifService.unsubscribeFromTopic('admin_$prev');
        await notifService.unsubscribeFromTopic('business_$prev');
      }
    });

    final tabs = [
      RouteConstants.adminDashboard,
      RouteConstants.employeeList,
      RouteConstants.approvalList,
      RouteConstants.adminLedger,
      RouteConstants.adminReports,
    ];

    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard_rounded),
        label: 'Home',
      ),
      const NavigationDestination(
        icon: Icon(Icons.people_outline_rounded),
        selectedIcon: Icon(Icons.people_rounded),
        label: 'Team',
      ),
      const NavigationDestination(
        icon: Icon(Icons.task_alt_outlined),
        selectedIcon: Icon(Icons.task_alt_rounded),
        label: 'Approvals',
      ),
      const NavigationDestination(
        icon: Icon(Icons.account_balance_outlined),
        selectedIcon: Icon(Icons.account_balance_rounded),
        label: 'Ledger',
      ),
      const NavigationDestination(
        icon: Icon(Icons.bar_chart_outlined),
        selectedIcon: Icon(Icons.bar_chart_rounded),
        label: 'Reports',
      ),
    ];

    if (isSuperadmin) {
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.apps_outlined),
        selectedIcon: Icon(Icons.apps_rounded),
        label: 'All Biz',
      ));
    }

    // Compute active tab index from the current route location so that
    // navigating to a tab's page via a dashboard card highlights the right tab.
    final loc = GoRouterState.of(context).matchedLocation;
    int activeIndex = 0;
    for (int i = tabs.length - 1; i >= 0; i--) {
      if (loc.startsWith(tabs[i])) {
        activeIndex = i;
        break;
      }
    }

    return BackButtonListener(
      onBackButtonPressed: () async {
        if (widget.navigatorKey.currentState?.canPop() == true) {
          widget.navigatorKey.currentState!.pop();
          return true;
        }
        final curLoc = GoRouterState.of(context).matchedLocation;
        if (curLoc != tabs[0]) {
          context.go(tabs[0]);
          return true;
        }
        final now = DateTime.now();
        if (_lastBackPress != null &&
            now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
          await SystemNavigator.pop();
          return true;
        }
        _lastBackPress = now;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Press back again to exit'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return true;
      },
      child: Scaffold(
        body: Column(
          children: [
            _DemoBanner(),
            Expanded(child: widget.child),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: activeIndex.clamp(0, destinations.length - 1),
          labelBehavior:
              NavigationDestinationLabelBehavior.onlyShowSelected,
          height: 64,
          onDestinationSelected: (index) {
            // Last tab for superadmin = return to business hub
            if (isSuperadmin && index == tabs.length) {
              ref.read(businessContextProvider.notifier).clearActiveBusiness();
              context.go(RouteConstants.superadminDashboard);
              return;
            }
            context.go(tabs[index]);
          },
          destinations: destinations,
        ),
      ),
    );
  }
}

class EmployeeShell extends ConsumerStatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  const EmployeeShell({super.key, required this.child, required this.navigatorKey});

  @override
  ConsumerState<EmployeeShell> createState() => _EmployeeShellState();
}

class _EmployeeShellState extends ConsumerState<EmployeeShell> {
  DateTime? _lastBackPress;
  StreamSubscription? _tapSubscription;

  final _tabs = [
    RouteConstants.employeeDashboard,
    RouteConstants.expenseList,
    RouteConstants.saleList,
    RouteConstants.employeeLedger,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initFcm();
      _checkForUpdate(context);
    });
  }

  Future<void> _initFcm() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    final businessId =
        ref.read(activeBusinessIdProvider) ?? AppConstants.defaultBusinessId;
    final notifService = ref.read(notificationServiceProvider);
    await notifService.initialize();
    await notifService.saveTokenToDatabase(user.uid);
    await notifService.subscribeToTopic('business_$businessId');
    _tapSubscription = notifService.onNotificationTap.listen((_) {
      if (mounted) context.push(RouteConstants.employeeNotifications);
    });
  }

  @override
  void dispose() {
    _tapSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(activeBusinessIdProvider, (prev, next) async {
      final notifService = ref.read(notificationServiceProvider);
      if (next != null) {
        await notifService.subscribeToTopic('business_$next');
      }
      if (prev != null && prev != next) {
        await notifService.unsubscribeFromTopic('business_$prev');
      }
    });

    final loc = GoRouterState.of(context).matchedLocation;
    int activeIndex = 0;
    for (int i = _tabs.length - 1; i >= 0; i--) {
      if (loc.startsWith(_tabs[i])) {
        activeIndex = i;
        break;
      }
    }

    return BackButtonListener(
      onBackButtonPressed: () async {
        if (widget.navigatorKey.currentState?.canPop() == true) {
          widget.navigatorKey.currentState!.pop();
          return true;
        }
        final curLoc = GoRouterState.of(context).matchedLocation;
        if (curLoc != _tabs[0]) {
          context.go(_tabs[0]);
          return true;
        }
        final now = DateTime.now();
        if (_lastBackPress != null &&
            now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
          await SystemNavigator.pop();
          return true;
        }
        _lastBackPress = now;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Press back again to exit'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return true;
      },
      child: Scaffold(
        body: Column(
          children: [
            _DemoBanner(),
            Expanded(child: widget.child),
          ],
        ),
        floatingActionButton: activeIndex == 1
            ? FloatingActionButton(
                onPressed: () => context.push(RouteConstants.addExpense),
                child: const Icon(Icons.add),
              )
            : activeIndex == 2
                ? FloatingActionButton(
                    onPressed: () => context.push(RouteConstants.addSale),
                    backgroundColor: AppColors.success,
                    child: const Icon(Icons.add),
                  )
                : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: activeIndex,
          labelBehavior:
              NavigationDestinationLabelBehavior.onlyShowSelected,
          height: 64,
          onDestinationSelected: (index) {
            context.go(_tabs[index]);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded),
              label: 'Expenses',
            ),
            NavigationDestination(
              icon: Icon(Icons.sell_outlined),
              selectedIcon: Icon(Icons.sell_rounded),
              label: 'Sales',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_balance_outlined),
              selectedIcon: Icon(Icons.account_balance_rounded),
              label: 'Ledger',
            ),
          ],
        ),
      ),
    );
  }
}

// ── Superadmin Shell ──────────────────────────────────────────────────────

class SuperadminShell extends ConsumerStatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  const SuperadminShell(
      {super.key, required this.child, required this.navigatorKey});

  @override
  ConsumerState<SuperadminShell> createState() => _SuperadminShellState();
}

class _SuperadminShellState extends ConsumerState<SuperadminShell> {
  DateTime? _lastBackPress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate(context));
  }

  @override
  Widget build(BuildContext context) {
    return BackButtonListener(
      onBackButtonPressed: () async {
        if (widget.navigatorKey.currentState?.canPop() == true) {
          widget.navigatorKey.currentState!.pop();
          return true;
        }
        final now = DateTime.now();
        if (_lastBackPress != null &&
            now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
          await SystemNavigator.pop();
          return true;
        }
        _lastBackPress = now;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Press back again to exit'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return true;
      },
      child: Scaffold(body: widget.child),
    );
  }
}

// ── Demo banner — shown at top of shell when in demo mode ─────────────────

class _DemoBanner extends ConsumerWidget {
  const _DemoBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membership = ref.watch(activeMembershipProvider);
    if (membership == null) return const SizedBox.shrink();

    final daysLeft = membership.demoDaysRemaining;
    if (daysLeft == null) return const SizedBox.shrink();

    final isUrgent = daysLeft <= 3;
    final bg = isUrgent ? Colors.red.shade700 : Colors.orange.shade700;

    return Material(
      color: bg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.timer_outlined, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  daysLeft == 0
                      ? 'Trial ends today! Contact support to continue.'
                      : 'Trial: $daysLeft day${daysLeft == 1 ? '' : 's'} remaining',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Unauthorized Screen ────────────────────────────────────────────────────

class _UnauthorizedScreen extends StatelessWidget {
  const _UnauthorizedScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 72,
                  color: Theme.of(context).colorScheme.error.withValues(alpha: 0.7),
                ),
                const SizedBox(height: 24),
                Text(
                  'Access Denied',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'You do not have permission to view this page.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: () => context.pop(),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
