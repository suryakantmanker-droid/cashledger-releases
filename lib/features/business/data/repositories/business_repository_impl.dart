import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/business_membership_entity.dart';
import '../../domain/repositories/business_repository.dart';
import '../datasources/business_remote_datasource.dart';

class BusinessRepositoryImpl implements BusinessRepository {
  final BusinessRemoteDataSource _dataSource;
  final Connectivity _connectivity;

  const BusinessRepositoryImpl(this._dataSource, this._connectivity);

  @override
  Future<Either<Failure, List<BusinessMembershipEntity>>> getMembershipsForUser(
      String userUid) async {
    try {
      final results = await _connectivity.checkConnectivity();
      if (results.contains(ConnectivityResult.none)) {
        return const Left(NetworkFailure('No internet connection.'));
      }

      final memberships = await _dataSource.getMembershipsForUser(userUid);
      return Right(memberships);
    } on ServerException catch (e) {
      debugPrint('[BusinessRepo] ServerException: ${e.message}');
      return Left(ServerFailure(e.message));
    } catch (e) {
      debugPrint('[BusinessRepo] Unexpected: $e');
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<BusinessMembershipEntity>>> getAllBusinessesAsSuperadmin(
      String superadminUid) async {
    try {
      final results = await _connectivity.checkConnectivity();
      if (results.contains(ConnectivityResult.none)) {
        return const Left(NetworkFailure('No internet connection.'));
      }
      final memberships =
          await _dataSource.getAllBusinessesAsSuperadmin(superadminUid);
      return Right(memberships);
    } on ServerException catch (e) {
      debugPrint('[BusinessRepo] getAllBusinessesAsSuperadmin error: ${e.message}');
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, BusinessMembershipEntity>> addMember({
    required String businessId,
    required String userUid,
    required String role,
    String? invitedBy,
  }) async {
    try {
      final result = await _dataSource.addMember(
        businessId: businessId,
        userUid:    userUid,
        role:       role,
        invitedBy:  invitedBy,
      );
      return Right(result);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    }
  }

  @override
  Future<Either<Failure, void>> updateMemberRole({
    required String businessId,
    required String userUid,
    required String newRole,
  }) async {
    try {
      await _dataSource.updateMemberRole(
        businessId: businessId,
        userUid:    userUid,
        newRole:    newRole,
      );
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    }
  }

  @override
  Future<Either<Failure, void>> deactivateMember({
    required String businessId,
    required String userUid,
  }) async {
    try {
      await _dataSource.deactivateMember(
        businessId: businessId,
        userUid:    userUid,
      );
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    }
  }
}
