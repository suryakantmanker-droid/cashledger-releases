import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
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
}
