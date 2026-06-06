import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/hive_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../shared/providers/business_context_provider.dart';
import '../../data/datasources/auth_remote_datasource.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';

// ── Dependency Providers ───────────────────────────────────────────────────

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  return AuthRemoteDataSourceImpl(ref.watch(supabaseClientProvider));
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(
    ref.watch(authRemoteDataSourceProvider),
    Connectivity(),
  );
});

// ── Auth Stream ────────────────────────────────────────────────────────────
// Emits the current Firebase + Supabase user profile on every auth change.
// This is the canonical source for "is anyone logged in?"

final currentUserProvider = StreamProvider<UserEntity?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

// ── Auth State ─────────────────────────────────────────────────────────────

class AuthState {
  final bool isLoading;
  final String? errorMessage;
  final String? successMessage;
  final UserEntity? user;

  const AuthState({
    this.isLoading = false,
    this.errorMessage,
    this.successMessage,
    this.user,
  });

  AuthState copyWith({
    bool? isLoading,
    String? errorMessage,
    String? successMessage,
    UserEntity? user,
  }) {
    return AuthState(
      isLoading:      isLoading      ?? this.isLoading,
      // Explicit null clears the messages
      errorMessage:   errorMessage,
      successMessage: successMessage,
      user:           user           ?? this.user,
    );
  }
}

// ── Auth Notifier ─────────────────────────────────────────────────────────

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repository;
  final Ref _ref;

  AuthNotifier(this._repository, this._ref) : super(const AuthState());

  Future<bool> login({required String email, required String password}) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    final result = await _repository.login(email: email, password: password);

    return result.fold(
      (failure) {
        state = state.copyWith(isLoading: false, errorMessage: failure.message);
        return false;
      },
      (user) {
        state = state.copyWith(isLoading: false, user: user);
        // Business context loading is triggered by _RouterRefreshNotifier
        // when it detects the auth state change. No duplicate call needed here.
        return true;
      },
    );
  }

  Future<void> logout() async {
    // Clear auth state FIRST so the router immediately sees no user.
    // If we clear it after signOut, there is a window where the stream
    // emits null but notifierState.user is still the old user — the router
    // reads both and falls back to the stale notifier value, keeping the
    // previous user's shell on screen until the next tick.
    state = const AuthState();
    await _ref.read(businessContextProvider.notifier).clear();
    await HiveService.instance.clearAll();
    await _repository.logout();
  }

  Future<bool> sendPasswordResetEmail(String email) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    final result = await _repository.sendPasswordResetEmail(email);
    return result.fold(
      (failure) {
        state = state.copyWith(isLoading: false, errorMessage: failure.message);
        return false;
      },
      (_) {
        state = state.copyWith(
          isLoading: false,
          successMessage: 'Password reset email sent. Check your inbox.',
        );
        return true;
      },
    );
  }

  void clearError() => state = state.copyWith(errorMessage: null);
}

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(authRepositoryProvider), ref);
});

/// True when the current user is the platform superadmin.
final isSuperadminProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProvider).valueOrNull?.isSuperadmin ?? false;
});
