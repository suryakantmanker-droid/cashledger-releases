import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/services/supabase_service.dart';

class ProfileState {
  final bool isLoading;
  final bool isUploadingPhoto;
  final String? errorMessage;
  final String? successMessage;

  const ProfileState({
    this.isLoading       = false,
    this.isUploadingPhoto = false,
    this.errorMessage,
    this.successMessage,
  });

  ProfileState copyWith({
    bool?   isLoading,
    bool?   isUploadingPhoto,
    String? errorMessage,
    String? successMessage,
  }) {
    return ProfileState(
      isLoading:        isLoading        ?? this.isLoading,
      isUploadingPhoto: isUploadingPhoto ?? this.isUploadingPhoto,
      errorMessage:  errorMessage,
      successMessage: successMessage,
    );
  }
}

class ProfileNotifier extends StateNotifier<ProfileState> {
  final SupabaseClient _supabase;
  final StorageService _storage;

  ProfileNotifier(this._supabase, this._storage)
      : super(const ProfileState());

  Future<bool> updateProfile({
    required String uid,
    required String name,
    String? email,
    String? phone,
    String? address,
    String? city,
    String? district,
    String? stateName,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null, successMessage: null);
    try {
      final now = DateTime.now().toIso8601String();
      final userUpdate = <String, dynamic>{'name': name, 'updated_at': now};
      if (email     != null && email.isNotEmpty)    userUpdate['email']    = email;
      if (phone     != null) userUpdate['phone']    = phone;
      if (address   != null) userUpdate['address']  = address;
      if (city      != null) userUpdate['city']     = city;
      if (district  != null) userUpdate['district'] = district;
      if (stateName != null) userUpdate['state']    = stateName;

      await _supabase.from('users').update(userUpdate).eq('uid', uid);

      // Sync to employees table if this uid has an employee row
      final empRow = await _supabase
          .from('employees')
          .select('id')
          .eq('id', uid)
          .maybeSingle();

      if (empRow != null) {
        final empUpdate = <String, dynamic>{'name': name, 'updated_at': now};
        if (phone     != null && phone.isNotEmpty)     empUpdate['phone']    = phone;
        if (address   != null && address.isNotEmpty)   empUpdate['address']  = address;
        if (city      != null && city.isNotEmpty)      empUpdate['city']     = city;
        if (district  != null && district.isNotEmpty)  empUpdate['district'] = district;
        if (stateName != null && stateName.isNotEmpty) empUpdate['state']    = stateName;
        await _supabase.from('employees').update(empUpdate).eq('id', uid);
      }

      state = state.copyWith(isLoading: false, successMessage: 'Profile updated successfully.');
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> uploadProfilePhoto({
    required String uid,
    required File file,
  }) async {
    state = state.copyWith(isUploadingPhoto: true, errorMessage: null, successMessage: null);
    try {
      final url = await _storage.uploadProfileImage(file: file, userId: uid);

      await _supabase.from('users').update({'photo_url': url}).eq('uid', uid);

      final empRow = await _supabase
          .from('employees')
          .select('id')
          .eq('id', uid)
          .maybeSingle();

      if (empRow != null) {
        await _supabase.from('employees').update({'profile_image_url': url}).eq('id', uid);
      }

      state = state.copyWith(isUploadingPhoto: false, successMessage: 'Profile photo updated.');
      return true;
    } catch (e) {
      state = state.copyWith(isUploadingPhoto: false, errorMessage: e.toString());
      return false;
    }
  }

  /// Change password via Supabase Auth.
  /// Supabase requires the user to be logged in with a valid session.
  Future<bool> changePassword({
    required String newPassword,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null, successMessage: null);
    try {
      await _supabase.auth.updateUser(UserAttributes(password: newPassword));
      state = state.copyWith(isLoading: false, successMessage: 'Password changed successfully.');
      return true;
    } on AuthApiException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  void clearMessages() =>
      state = state.copyWith(errorMessage: null, successMessage: null);
}

final profileNotifierProvider =
    StateNotifierProvider<ProfileNotifier, ProfileState>((ref) {
  return ProfileNotifier(
    ref.watch(supabaseClientProvider),
    StorageService(),
  );
});
