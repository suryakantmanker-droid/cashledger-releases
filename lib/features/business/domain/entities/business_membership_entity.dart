import 'package:equatable/equatable.dart';
import '../../../../core/constants/permission_matrix.dart';

// ── Subscription status ───────────────────────────────────────────────────────

enum SubscriptionStatus {
  active, // Paid, full access
  demo, // Time-limited trial
  expired, // Trial or subscription ended
  inactive; // Manually deactivated by superadmin

  static SubscriptionStatus fromString(String? value) =>
      SubscriptionStatus.values.firstWhere(
        (s) => s.name == value,
        orElse: () => SubscriptionStatus.active,
      );
}

// ── Entity ────────────────────────────────────────────────────────────────────

/// Represents a user's membership in a single business, including their role.
/// This is the central object that drives all business-scoped access in Phase 1.
class BusinessMembershipEntity extends Equatable {
  final String id;
  final String businessId;
  final String businessName;
  final String? businessLogoUrl;
  final String userUid;
  final UserRole role;
  final bool isActive;
  final DateTime joinedAt;
  final SubscriptionStatus subscriptionStatus;
  final DateTime? subscriptionExpiryDate;

  const BusinessMembershipEntity({
    required this.id,
    required this.businessId,
    required this.businessName,
    required this.userUid,
    required this.role,
    required this.isActive,
    required this.joinedAt,
    this.businessLogoUrl,
    this.subscriptionStatus = SubscriptionStatus.active,
    this.subscriptionExpiryDate,
  });

  // ── Subscription helpers ──────────────────────────────────────────────────

  /// Returns false when the business is blocked from access (expired or inactive).
  /// Also handles demo where the expiry date has passed client-side.
  bool get isSubscriptionValid {
    if (subscriptionStatus == SubscriptionStatus.inactive) return false;
    if (subscriptionStatus == SubscriptionStatus.expired) return false;
    if (subscriptionExpiryDate != null && DateTime.now().isAfter(subscriptionExpiryDate!)) return false;
    return true;
  }

  /// Non-null only when demo is active; returns 0 when demo is on the last day.
  int? get demoDaysRemaining {
    if (subscriptionStatus != SubscriptionStatus.demo) return null;
    if (subscriptionExpiryDate == null) return null;
    final diff = subscriptionExpiryDate!.difference(DateTime.now()).inDays;
    return diff >= 0 ? diff : 0;
  }

  // ── Permission helpers ────────────────────────────────────────────────────

  String get roleName => role.displayName;

  bool get canApproveExpenses => role.canApproveExpenses;
  bool get canTransferFunds => role.canTransferFunds;
  bool get canManageEmployees => role.canManageEmployees;
  bool get canViewReports => role.canViewReports;
  bool get isAdminLike => role.isAdminLike;

  @override
  List<Object?> get props => [
        id,
        businessId,
        userUid,
        role,
        isActive,
        subscriptionStatus,
        subscriptionExpiryDate
      ];
}
