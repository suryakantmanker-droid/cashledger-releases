import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/user_entity.dart';

abstract class AuthRepository {
  Future<Either<Failure, UserEntity>> login({
    required String email,
    required String password,
  });

  Future<Either<Failure, void>> logout();

  Future<Either<Failure, void>> sendPasswordResetEmail(String email);

  Stream<UserEntity?> get authStateChanges;

  Future<Either<Failure, UserEntity>> getCurrentUser();

  Future<Either<Failure, void>> updateFcmToken(String userId, String token);
}
