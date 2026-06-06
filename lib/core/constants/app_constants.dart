class AppConstants {
  AppConstants._();

  static const String appName = 'ExpenseTrack Pro';
  static const String appVersion = '1.0.0';

  // ── Multi-business ──────────────────────────────────────────────────────────
  // Fixed UUID for the default (legacy) business created during Phase 0 backfill.
  // All data that existed before multi-business migration lives under this ID.
  static const String defaultBusinessId = '11111111-1111-1111-1111-111111111111';

  // ── Supabase table names ────────────────────────────────────────────────────
  // Use SupabaseTables constants (below) instead of these for new code.
  // Firestore Collection Names (existing — Firestore used ONLY for notifications)
  static const String usersCollection = 'users';
  static const String employeesCollection = 'employees';
  static const String fundsCollection = 'funds';
  static const String expensesCollection = 'expenses';
  static const String ledgerCollection = 'ledger';
  static const String notificationsCollection = 'notifications';
  static const String reportsCollection = 'reports';
  static const String settingsCollection = 'settings';

  // Firebase Storage Paths
  static const String profileImagesPath = 'profile_images';
  static const String billImagesPath = 'bill_images';
  static const String billPdfsPath = 'bill_pdfs';

  // User Roles — legacy two-role values (still valid in business_members)
  static const String roleAdmin = 'admin';
  static const String roleEmployee = 'employee';

  // User Roles — full six-role hierarchy (Phase 1+)
  static const String roleOwner      = 'owner';
  static const String roleManager    = 'manager';
  static const String roleAccountant = 'accountant';
  static const String roleViewer     = 'viewer';

  // Expense Statuses
  static const String statusPending = 'pending';
  static const String statusApproved = 'approved';
  static const String statusRejected = 'rejected';
  static const String statusDraft = 'draft';

  // Fund Transfer Statuses
  static const String fundStatusActive = 'active';
  static const String fundStatusCompleted = 'completed';

  // Transaction Types
  static const String txnCredit = 'credit';
  static const String txnDebit = 'debit';

  // Payment Modes
  static const List<String> paymentModes = [
    'Cash',
    'UPI',
    'NEFT/IMPS',
    'Cheque',
    'Card',
    'Other',
  ];

  // Expense Categories
  static const List<String> expenseCategories = [
    'Travel',
    'Food & Beverage',
    'Office Supplies',
    'Utilities',
    'Rent',
    'Vendor Payment',
    'Maintenance',
    'Marketing',
    'Salaries',
    'Miscellaneous',
  ];

  // Pagination
  static const int pageSize = 20;

  // Cache Duration
  static const Duration cacheDuration = Duration(minutes: 5);

  // File Size Limits
  static const int maxImageSizeBytes = 5 * 1024 * 1024; // 5MB
  static const int maxPdfSizeBytes = 10 * 1024 * 1024;  // 10MB

  // Hive Box Names
  static const String userBox           = 'user_box';
  static const String settingsBox       = 'settings_box';
  static const String draftExpenseBox   = 'draft_expense_box';
  static const String activeBusinessBox = 'active_business_box'; // NEW (Phase 1)
  static const String syncQueueBox      = 'sync_queue_box';      // NEW (Phase 1)

  // Notification Topics — must be per-business from Phase 1 onward
  // Legacy (single-business):
  static const String adminTopic    = 'admin_notifications';
  static const String allUsersTopic = 'all_users';
  // Per-business pattern (Phase 1): 'admin_$businessId', 'business_$businessId'

  // Expense statuses (full set for multi-business)
  static const String statusCancelled = 'cancelled';

  // Fund transfer statuses
  static const String fundStatusCancelled = 'cancelled';

  // Ledger reference types (new in multi-business)
  static const String refTypeSalary    = 'salary';
  static const String refTypeAdvance   = 'advance';
  static const String refTypeDeduction = 'deduction';

  // Attendance statuses
  static const List<String> attendanceStatuses = [
    'present', 'absent', 'half_day', 'holiday', 'leave', 'work_from_home',
  ];

  // Salary record statuses
  static const List<String> salaryStatuses = ['pending', 'paid', 'cancelled'];
}

// ── Supabase table name constants ─────────────────────────────────────────────
// Single source of truth for all Supabase table names used in queries.
abstract class SupabaseTables {
  SupabaseTables._();

  // Existing tables
  static const String users      = 'users';
  static const String employees  = 'employees';
  static const String expenses   = 'expenses';
  static const String funds      = 'funds';
  static const String ledger     = 'ledger';

  // New multi-business tables (Phase 0+)
  static const String businesses        = 'businesses';
  static const String businessMembers   = 'business_members';
  static const String expenseCategories = 'expense_categories';
  static const String salaryRecords     = 'salary_records';
  static const String attendance        = 'attendance';
}
