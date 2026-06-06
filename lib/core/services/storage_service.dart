import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../errors/exceptions.dart';

// ── Cloudinary Config ──────────────────────────────────────────────────────
class _Cloudinary {
  static const cloudName    = 'duxvqvh97';
  static const uploadPreset = 'cashledger_upload';
  static const _base = 'https://api.cloudinary.com/v1_1/$cloudName';

  static const imageUpload = '$_base/image/upload';
  static const rawUpload   = '$_base/raw/upload';
}

// ── StorageService ─────────────────────────────────────────────────────────
class StorageService {
  final Dio _dio;

  StorageService()
      : _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 90),
            sendTimeout:    const Duration(minutes: 3),
          ),
        );

  // ── Bill Image Upload ────────────────────────────────────────────────────

  Future<String> uploadBillImage({
    required File file,
    required String expenseId,
    void Function(double progress)? onProgress,
  }) async {
    try {
      final compressed = await _compressImage(file, quality: 85);
      final fileName = '${const Uuid().v4()}.jpg';

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          compressed.path,
          filename: fileName,
          contentType: DioMediaType('image', 'jpeg'),
        ),
        'upload_preset': _Cloudinary.uploadPreset,
        'folder': 'expense_bills/$expenseId',
        'resource_type': 'image',
      });

      final response = await _dio.post(
        _Cloudinary.imageUpload,
        data: formData,
        onSendProgress: (sent, total) {
          if (total > 0) onProgress?.call(sent / total);
        },
      );

      return _extractUrl(response.data);
    } on DioException catch (e) {
      throw StorageException(_cloudinaryError(e), code: 'cloudinary_image_upload');
    }
  }

  // ── Bill PDF Upload ──────────────────────────────────────────────────────

  Future<String> uploadBillPdf({
    required File file,
    required String expenseId,
    void Function(double progress)? onProgress,
  }) async {
    try {
      final fileName = '${const Uuid().v4()}.pdf';

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          filename: fileName,
          contentType: DioMediaType('application', 'pdf'),
        ),
        'upload_preset': _Cloudinary.uploadPreset,
        'folder': 'expense_bills/$expenseId',
        'resource_type': 'raw',
      });

      final response = await _dio.post(
        _Cloudinary.rawUpload,
        data: formData,
        onSendProgress: (sent, total) {
          if (total > 0) onProgress?.call(sent / total);
        },
      );

      return _extractUrl(response.data);
    } on DioException catch (e) {
      throw StorageException(_cloudinaryError(e), code: 'cloudinary_pdf_upload');
    }
  }

  // ── Profile Image Upload ─────────────────────────────────────────────────

  Future<String> uploadProfileImage({
    required File file,
    required String userId,
  }) async {
    try {
      final compressed = await _compressImage(file, quality: 75);
      final fileName = 'avatar_${const Uuid().v4()}.jpg';

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          compressed.path,
          filename: fileName,
          contentType: DioMediaType('image', 'jpeg'),
        ),
        'upload_preset': _Cloudinary.uploadPreset,
        'folder': 'profile_images/$userId',
        'public_id': 'avatar',
      });

      final response = await _dio.post(_Cloudinary.imageUpload, data: formData);
      return _extractUrl(response.data);
    } on DioException catch (e) {
      throw StorageException(_cloudinaryError(e), code: 'cloudinary_profile_upload');
    }
  }

  // ── Generic upload ───────────────────────────────────────────────────────

  Future<String> uploadFile({
    required File file,
    required String folder,
    void Function(double progress)? onProgress,
  }) async {
    final isPdf = file.path.toLowerCase().endsWith('.pdf');
    if (isPdf) {
      return uploadBillPdf(file: file, expenseId: folder, onProgress: onProgress);
    } else {
      return uploadBillImage(file: file, expenseId: folder, onProgress: onProgress);
    }
  }

  // ── Delete ───────────────────────────────────────────────────────────────

  Future<void> deleteFile(String url) async {
    // Cloudinary deletion requires server-side Admin API (API secret).
    // Implement via a Firebase Cloud Function if needed.
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _extractUrl(dynamic data) {
    final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final url = map['secure_url'] as String?;
    if (url == null || url.isEmpty) throw StorageException('Upload failed: no URL returned');
    return url;
  }

  Future<File> _compressImage(File file, {int quality = 85}) async {
    final ext = p.extension(file.path).toLowerCase();
    if (ext == '.gif') return file;

    final targetPath =
        '${file.parent.path}/cld_${p.basenameWithoutExtension(file.path)}.jpg';
    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: quality,
      minWidth: 1280,
      minHeight: 1280,
      keepExif: false,
    );
    return result != null ? File(result.path) : file;
  }

  String _cloudinaryError(DioException e) {
    try {
      final data = e.response?.data;
      if (data is Map) {
        return (data['error']?['message'] as String?) ??
            'Upload failed (${e.response?.statusCode})';
      }
    } catch (_) {}
    if (e.type == DioExceptionType.connectionTimeout) {
      return 'Upload timed out. Check your internet connection.';
    }
    if (e.type == DioExceptionType.sendTimeout) {
      return 'Upload timed out. File may be too large.';
    }
    return e.message ?? 'Upload failed. Please try again.';
  }
}
