class RouteConstants {
  RouteConstants._();

  static const String splash = '/';
  static const String login = '/login';
  static const String forgotPassword  = '/forgot-password';
  static const String updatePassword  = '/update-password';

  // Admin Routes
  static const String adminDashboard = '/admin/dashboard';
  static const String employeeList = '/admin/employees';
  static const String addEmployee = '/admin/employees/add';
  static const String editEmployee = '/admin/employees/edit/:id';
  static const String employeeDetail = '/admin/employees/:id';
  static const String fundTransfer = '/admin/funds/transfer';
  static const String fundHistory = '/admin/funds/history';
  static const String approvalList = '/admin/approvals';
  static const String expenseDetailAdmin = '/admin/expenses/:id';
  static const String adminLedger = '/admin/ledger';
  static const String adminReports = '/admin/reports';
  static const String adminNotifications = '/admin/notifications';
  static const String adminProfile = '/admin/profile';
  static const String adminBusinessAdmins = '/admin/business-admins';

  // Employee Routes
  static const String employeeDashboard = '/employee/dashboard';
  static const String addExpense = '/employee/expenses/add';
  static const String editExpense = '/employee/expenses/edit/:id';
  static const String expenseList = '/employee/expenses';
  static const String expenseDetail = '/employee/expenses/:id';
  static const String employeeLedger = '/employee/ledger';
  static const String employeeNotifications = '/employee/notifications';
  static const String employeeProfile = '/employee/profile';

  // Sale / Collection Routes (employee)
  static const String saleList = '/employee/sales';
  static const String addSale = '/employee/sales/add';
  static const String saleDetail = '/employee/sales/:id';

  // Shared
  static const String billPreview = '/bill-preview';

  // Multi-business (Phase 1+)
  static const String noBusinessSetup  = '/setup-business';
  static const String businessSelector = '/select-business';
  static const String unauthorized     = '/unauthorized';

  // Superadmin Routes
  static const String superadminDashboard        = '/superadmin/businesses';
  static const String superadminCreateBusiness   = '/superadmin/businesses/create';
  static const String superadminBusinessDetail   = '/superadmin/businesses/:id';
  static const String superadminEditBusiness     = '/superadmin/businesses/:id/edit';
  static const String superadminDepartments            = '/superadmin/departments';
  static const String superadminProfile               = '/superadmin/profile';
  static const String superadminNotificationSettings  = '/superadmin/notification-settings';

  static String superadminBusinessDetailPath(String id) => '/superadmin/businesses/$id';
  static String superadminEditBusinessPath(String id)   => '/superadmin/businesses/$id/edit';

  // Subscription
  static const String subscriptionExpired = '/subscription-expired';
}
