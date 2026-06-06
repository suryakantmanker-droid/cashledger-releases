import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/services/notification_service_provider.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../shared/providers/business_context_provider.dart';
import '../../../expenses/presentation/providers/expense_provider.dart';
import '../../../ledger/presentation/providers/ledger_provider.dart';
import '../../data/datasources/sale_remote_datasource.dart';
import '../../data/models/sale_model.dart';

// ── Dependency Providers ───────────────────────────────────────────────────

final saleRemoteDataSourceProvider = Provider<SaleRemoteDataSource>((ref) {
  return SaleRemoteDataSourceImpl(ref.watch(supabaseClientProvider));
});

// ── Stream Providers ───────────────────────────────────────────────────────

final employeeSalesStreamProvider =
    StreamProvider.autoDispose.family<List<SaleModel>, String>((ref, employeeId) {
  final businessId = ref.watch(activeBusinessIdProvider);
  if (businessId == null) return Stream.value(const []);
  return ref
      .read(saleRemoteDataSourceProvider)
      .watchSalesByEmployee(employeeId, businessId: businessId);
});

final allSalesStreamProvider =
    StreamProvider.autoDispose<List<SaleModel>>((ref) {
  final businessId = ref.watch(activeBusinessIdProvider);
  if (businessId == null) return Stream.value(const []);
  return ref
      .read(saleRemoteDataSourceProvider)
      .watchAllSales(businessId: businessId);
});

// ── Sale State ─────────────────────────────────────────────────────────────

class SaleState {
  final bool isLoading;
  final bool isUploading;
  final double uploadProgress;
  final String? errorMessage;
  final String? successMessage;

  const SaleState({
    this.isLoading = false,
    this.isUploading = false,
    this.uploadProgress = 0.0,
    this.errorMessage,
    this.successMessage,
  });

  SaleState copyWith({
    bool? isLoading,
    bool? isUploading,
    double? uploadProgress,
    String? errorMessage,
    String? successMessage,
  }) {
    return SaleState(
      isLoading: isLoading ?? this.isLoading,
      isUploading: isUploading ?? this.isUploading,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      errorMessage: errorMessage,
      successMessage: successMessage,
    );
  }
}

// ── Sale Notifier ──────────────────────────────────────────────────────────

class SaleNotifier extends StateNotifier<SaleState> {
  final SaleRemoteDataSource _dataSource;
  final StorageService _storageService;
  final Ref _ref;

  SaleNotifier(this._dataSource, this._storageService, this._ref)
      : super(const SaleState());

  NotificationService get _notifService => _ref.read(notificationServiceProvider);

  Future<bool> logSale({
    required Map<String, dynamic> data,
    required List<File> proofFiles,
    required String employeeId,
    required String employeeName,
  }) async {
    final businessId = _ref.read(activeBusinessIdProvider);
    if (businessId == null) {
      state = state.copyWith(
        errorMessage: 'Business not loaded yet. Please wait and try again.',
      );
      return false;
    }

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final List<String> proofUrls = [];
      bool anyUploadFailed = false;

      if (proofFiles.isNotEmpty) {
        state = state.copyWith(isUploading: true, uploadProgress: 0.0);
        final tempId = DateTime.now().millisecondsSinceEpoch.toString();

        for (int i = 0; i < proofFiles.length; i++) {
          final file = proofFiles[i];
          final isPdf = file.path.toLowerCase().endsWith('.pdf');
          try {
            final url = isPdf
                ? await _storageService.uploadBillPdf(
                    file: file,
                    expenseId: 'sale_$tempId',
                    onProgress: (p) => state = state.copyWith(
                        uploadProgress: (i + p) / proofFiles.length),
                  )
                : await _storageService.uploadBillImage(
                    file: file,
                    expenseId: 'sale_$tempId',
                    onProgress: (p) => state = state.copyWith(
                        uploadProgress: (i + p) / proofFiles.length),
                  );
            proofUrls.add(url);
          } catch (e) {
            anyUploadFailed = true;
            debugPrint('[SaleNotifier] Proof upload failed: $e');
          }
        }
        state = state.copyWith(isUploading: false, uploadProgress: 0.0);
      }

      final saleId = AppUtils.generateSaleId();

      await _dataSource.logSale(
        {
          ...data,
          'saleId': saleId,
          'employeeId': employeeId,
          'employeeName': employeeName,
          'proofUrls': proofUrls,
        },
        businessId: businessId,
      );

      // Notify all admins about the sale (fire-and-forget)
      _notifService.notifySaleCollectionToAdmins(
        employeeName:    employeeName,
        amount:          (data['amount'] as num?)?.toDouble() ?? 0,
        itemDescription: data['itemDescription'] as String? ?? '',
        saleId:          saleId,
        businessId:      businessId,
      ).ignore();

      // Invalidate ledger so balance updates immediately
      _ref.invalidate(allLedgerProvider);
      _ref.invalidate(ledgerByEmployeeProvider(employeeId));
      _ref.invalidate(ledgerSummaryProvider(employeeId));
      _ref.invalidate(employeeLedgerRestProvider(employeeId));
      _ref.invalidate(employeeLedgerSummaryProvider(employeeId));
      _ref.invalidate(employeeSalesStreamProvider(employeeId));
      _ref.invalidate(allSalesStreamProvider);

      state = state.copyWith(
        isLoading: false,
        successMessage: anyUploadFailed
            ? 'Sale logged & wallet credited. Proof upload failed — retry later.'
            : 'Sale logged successfully. Wallet credited!',
      );
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  void clearMessages() => state = state.copyWith();
}

// ── Single-sale fetch (used by notification tap → sale detail) ────────────────

final saleByIdProvider =
    FutureProvider.autoDispose.family<SaleModel?, String>((ref, saleId) async {
  final businessId = ref.watch(activeBusinessIdProvider);
  if (businessId == null) return null;
  try {
    return await ref
        .read(saleRemoteDataSourceProvider)
        .getSaleById(saleId, businessId: businessId);
  } catch (_) {
    return null;
  }
});

final saleNotifierProvider =
    StateNotifierProvider<SaleNotifier, SaleState>((ref) {
  return SaleNotifier(
    ref.watch(saleRemoteDataSourceProvider),
    ref.watch(storageServiceProvider),
    ref,
  );
});
