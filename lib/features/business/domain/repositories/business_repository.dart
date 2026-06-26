import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../data/datasources/business_remote_datasource.dart';
import '../entities/business_membership_entity.dart';

abstract class BusinessRepository {
  /// Returns all active business memberships for the given Firebase UID.
  Future<Either<Failure, List<BusinessMembershipEntity>>> getMembershipsForUser(
      String userUid);

  /// Returns ALL businesses as owner memberships (superadmin only).
  Future<Either<Failure, List<BusinessMembershipEntity>>> getAllBusinessesAsSuperadmin(
      String superadminUid);

  /// Adds a user to a business with the specified role.
  Future<Either<Failure, BusinessMembershipEntity>> addMember({
    required String businessId,
    required String userUid,
    required String role,
    String? invitedBy,
  });

  /// Updates a member's role.
  Future<Either<Failure, void>> updateMemberRole({
    required String businessId,
    required String userUid,
    required String newRole,
  });

  /// Soft-removes a member from a business.
  Future<Either<Failure, void>> deactivateMember({
    required String businessId,
    required String userUid,
  });

  /// Returns all active owner/admin members of [businessId].
  Future<Either<Failure, List<BusinessMemberInfo>>> getBusinessAdmins(
      String businessId);

  /// Creates a new login and attaches it to [businessId] with role=admin.
  Future<Either<Failure, BusinessMemberInfo>> inviteAdmin({
    required String businessId,
    required String name,
    required String email,
    required String password,
    required String invitedBy,
  });

  /// Deactivates an admin's membership entirely. Refuses to remove the owner.
  Future<Either<Failure, void>> removeAdmin({
    required String businessId,
    required String userUid,
  });

  /// Switches a member back to the role they held before being promoted.
  Future<Either<Failure, void>> revertToPreviousRole({
    required String businessId,
    required String userUid,
  });

  /// Looks up an email against existing users, reporting their current role
  /// in [businessId] if they're already a member.
  Future<Either<Failure, ExistingUserMatch?>> findUserByEmail({
    required String businessId,
    required String email,
  });

  /// Deactivates [userUid]'s `employees` row in [businessId], if one exists.
  Future<Either<Failure, void>> deactivateEmployeeRecordIfAny({
    required String businessId,
    required String userUid,
  });
}
