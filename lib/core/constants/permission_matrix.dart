// =============================================================================
// Permission Matrix — UserRole enum + permission helpers
// =============================================================================
// Single source of truth for the six-level role hierarchy.
// All role checks in the app MUST go through this file.
// Never compare role strings directly (e.g. role == 'admin') after Phase 1.
// =============================================================================

enum UserRole {
  owner,
  admin,
  manager,
  accountant,
  employee,
  viewer;

  // ── Construction ────────────────────────────────────────────────────────────

  /// Parse a role string from Supabase. Unknown values map to [viewer].
  static UserRole fromString(String? value) {
    return UserRole.values.firstWhere(
      (r) => r.name == value,
      orElse: () => UserRole.viewer,
    );
  }

  // ── Hierarchy ───────────────────────────────────────────────────────────────

  /// Numeric level. Higher = more privileged.
  int get level => switch (this) {
    UserRole.owner      => 50,
    UserRole.admin      => 40,
    UserRole.manager    => 30,
    UserRole.accountant => 20,
    UserRole.employee   => 10,
    UserRole.viewer     => 0,
  };

  /// True if this role is at least as privileged as [other].
  bool isAtLeast(UserRole other) => level >= other.level;

  /// True if this role is strictly above [other].
  bool isAbove(UserRole other) => level > other.level;

  // ── Display ─────────────────────────────────────────────────────────────────

  String get displayName => name[0].toUpperCase() + name.substring(1);
}

// ── Permission Extensions ────────────────────────────────────────────────────
// One getter per business capability. Add new capabilities here, not inline.

extension UserRolePermissions on UserRole {
  // Expense management
  bool get canSubmitExpenses    => isAtLeast(UserRole.employee);
  bool get canViewOwnExpenses   => isAtLeast(UserRole.employee);
  bool get canViewAllExpenses   => isAtLeast(UserRole.accountant);
  bool get canApproveExpenses   => isAtLeast(UserRole.accountant);
  bool get canDeleteExpenses    => isAtLeast(UserRole.admin);

  // Fund management
  bool get canTransferFunds     => isAtLeast(UserRole.manager);
  bool get canViewAllFunds      => isAtLeast(UserRole.accountant);

  // Ledger
  bool get canViewOwnLedger     => isAtLeast(UserRole.employee);
  bool get canViewAllLedger     => isAtLeast(UserRole.accountant);

  // Employees
  bool get canViewEmployees     => isAtLeast(UserRole.employee);
  bool get canManageEmployees   => isAtLeast(UserRole.admin);

  // Salary & attendance
  bool get canViewSalary        => isAtLeast(UserRole.manager);
  bool get canManageSalary      => isAtLeast(UserRole.manager);
  bool get canManageAttendance  => isAtLeast(UserRole.manager);

  // Reports
  bool get canViewReports       => isAtLeast(UserRole.accountant);

  // Notifications
  bool get canSendBroadcast     => isAtLeast(UserRole.admin);

  // Business management
  bool get canInviteMembers     => isAtLeast(UserRole.admin);
  bool get canManageRoles       => isAtLeast(UserRole.admin);
  bool get canManageBusiness    => this == UserRole.owner;
  bool get canManageCategories  => isAtLeast(UserRole.admin);

  // Shell routing helpers
  bool get isAdminLike          => isAtLeast(UserRole.admin);
  bool get isManagerLike        => isAtLeast(UserRole.manager);
}
