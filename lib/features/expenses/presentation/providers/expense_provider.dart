import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/services/notification_service_provider.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../shared/providers/business_context_provider.dart';
import '../../../ledger/presentation/providers/ledger_provider.dart';
import '../../data/datasources/expense_remote_datasource.dart';
import '../../data/models/expense_model.dart';

// ── Dependency Providers ───────────────────────────────────────────────────

final expenseRemoteDataSourceProvider = Provider<ExpenseRemoteDataSource>((ref) {
  return ExpenseRemoteDataSourceImpl(ref.watch(supabaseClientProvider));
});

final storageServiceProvider = Provider<StorageService>((ref) => StorageService());

// ── Stream Providers ───────────────────────────────────────────────────────
// All streams are autoDispose + scoped to activeBusinessId.
// When active business changes, the old Realtime subscription is cancelled
// and a new one is opened — no cross-business data leakage.

final allExpensesStreamProvider =
    StreamProvider.autoDispose<List<ExpenseModel>>((ref) {
  final businessId = ref.watch(activeBusinessIdProvider);
  if (businessId == null) return Stream.value(const []);
  return ref.read(expenseRemoteDataSourceProvider)
      .watchAllExpenses(businessId: businessId);
});

final pendingExpensesStreamProvider =
    StreamProvider.autoDispose<List<ExpenseModel>>((ref) {
  final businessId = ref.watch(activeBusinessIdProvider);
  if (businessId == null) return Stream.value(const []);
  return ref.read(expenseRemoteDataSourceProvider)
      .watchAllPendingExpenses(businessId: businessId);
});

final employeeExpensesStreamProvider =
    StreamProvider.autoDispose.family<List<ExpenseModel>, String>((ref, employeeId) {
  final businessId = ref.watch(activeBusinessIdProvider);
  if (businessId == null) return Stream.value(const []);
  return ref.read(expenseRemoteDataSourceProvider)
      .watchExpensesByEmployee(employeeId, businessId: businessId);
});

final expenseByIdProvider =
    FutureProvider.autoDispose.family<ExpenseModel, String>((ref, id) {
  final businessId =
      ref.watch(activeBusinessIdProvider) ?? AppConstants.defaultBusinessId;
  return ref.read(expenseRemoteDataSourceProvider)
      .getExpenseById(id, businessId: businessId);
});

// ── Upload Progress ────────────────────────────────────────────────────────

final uploadProgressProvider = StateProvider<double>((ref) => 0.0);

// ── Expense State ──────────────────────────────────────────────────────────

class ExpenseState {
  final bool isLoading;
  final bool isUploading;
  final double uploadProgress;
  final String? errorMessage;
  final String? successMessage;

  const ExpenseState({
    this.isLoading = false,
    this.isUploading = false,
    this.uploadProgress = 0.0,
    this.errorMessage,
    this.successMessage,
  });

  ExpenseState copyWith({
    bool? isLoading,
    bool? isUploading,
    double? uploadProgress,
    String? errorMessage,
    String? successMessage,
  }) {
    return ExpenseState(
      isLoading: isLoading ?? this.isLoading,
      isUploading: isUploading ?? this.isUploading,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      errorMessage: errorMessage,
      successMessage: successMessage,
    );
  }
}

// ── Expense Notifier ───────────────────────────────────────────────────────

class ExpenseNotifier extends StateNotifier<ExpenseState> {
  final ExpenseRemoteDataSource _dataSource;
  final StorageService _storageService;
  final NotificationService _notificationService;
  final Ref _ref;

  ExpenseNotifier(
    this._dataSource,
    this._storageService,
    this._notificationService,
    this._ref,
  ) : super(const ExpenseState());

  String get _businessId =>
      _ref.read(activeBusinessIdProvider) ?? AppConstants.defaultBusinessId;

  Future<bool> submitExpense({
    required Map<String, dynamic> data,
    required List<File> billFiles,
    required String submittedBy,
  }) async {
    if (submittedBy.isEmpty) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'User session expired. Please log in again.',
      );
      return false;
    }

    final businessId = _ref.read(activeBusinessIdProvider);
    if (businessId == null) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Business not loaded yet. Please wait a moment and try again.',
      );
      return false;
    }

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final List<String> billUrls = [];
      bool anyUploadFailed = false;

      if (billFiles.isNotEmpty) {
        state = state.copyWith(isUploading: true, uploadProgress: 0.0);
        final tempId = DateTime.now().millisecondsSinceEpoch.toString();

        for (int i = 0; i < billFiles.length; i++) {
          final file = billFiles[i];
          final isPdf = file.path.toLowerCase().endsWith('.pdf');
          try {
            final url = isPdf
                ? await _storageService.uploadBillPdf(
                    file: file,
                    expenseId: tempId,
                    onProgress: (p) =>
                        state = state.copyWith(uploadProgress: (i + p) / billFiles.length),
                  )
                : await _storageService.uploadBillImage(
                    file: file,
                    expenseId: tempId,
                    onProgress: (p) =>
                        state = state.copyWith(uploadProgress: (i + p) / billFiles.length),
                  );
            billUrls.add(url);
          } catch (uploadErr) {
            anyUploadFailed = true;
            debugPrint('[ExpenseNotifier] Bill upload failed: $uploadErr');
          }
        }
        state = state.copyWith(isUploading: false, uploadProgress: 0.0);
      }

      final expenseId = await _dataSource.addExpense(
        {
          ...data,
          'billUrls': billUrls,
          'submittedBy': submittedBy,
          'status': AppConstants.statusPending,
        },
        businessId: businessId,
      );

      _notificationService.notifyAllAdmins(
        employeeName: data['submittedByName'] as String? ?? '',
        amount: (data['amount'] as num?)?.toDouble() ?? 0,
        expenseId: expenseId,
        businessId: businessId,
      ).ignore();

      _ref.invalidate(allExpensesStreamProvider);
      _ref.invalidate(pendingExpensesStreamProvider);
      _ref.invalidate(employeeExpensesStreamProvider(submittedBy));

      state = state.copyWith(
        isLoading: false,
        successMessage: anyUploadFailed
            ? 'Expense submitted. Bill upload failed — you can add bills later.'
            : 'Expense submitted successfully.',
      );
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> saveDraft(Map<String, dynamic> data) async {
    final businessId = _ref.read(activeBusinessIdProvider);
    if (businessId == null) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Business not loaded yet. Please wait a moment and try again.',
      );
      return false;
    }
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _dataSource.addExpense(
        {...data, 'status': AppConstants.statusDraft},
        businessId: businessId,
      );
      state = state.copyWith(isLoading: false, successMessage: 'Draft saved.');
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> updateDraft({
    required String id,
    required Map<String, dynamic> data,
    required List<File> billFiles,
    required String submittedBy,
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
      final List<String> newBillUrls = [];

      if (billFiles.isNotEmpty) {
        state = state.copyWith(isUploading: true, uploadProgress: 0.0);
        for (int i = 0; i < billFiles.length; i++) {
          final file = billFiles[i];
          final isPdf = file.path.toLowerCase().endsWith('.pdf');
          try {
            final url = isPdf
                ? await _storageService.uploadBillPdf(
                    file: file,
                    expenseId: id,
                    onProgress: (p) =>
                        state = state.copyWith(uploadProgress: (i + p) / billFiles.length),
                  )
                : await _storageService.uploadBillImage(
                    file: file,
                    expenseId: id,
                    onProgress: (p) =>
                        state = state.copyWith(uploadProgress: (i + p) / billFiles.length),
                  );
            newBillUrls.add(url);
          } catch (_) {}
        }
        state = state.copyWith(isUploading: false, uploadProgress: 0.0);
      }

      final updateData = Map<String, dynamic>.from(data);
      if (newBillUrls.isNotEmpty) {
        updateData['billUrls'] = newBillUrls;
      }

      await _dataSource.updateExpense(id, updateData, businessId: businessId);

      _ref.invalidate(allExpensesStreamProvider);
      _ref.invalidate(pendingExpensesStreamProvider);
      _ref.invalidate(employeeExpensesStreamProvider(submittedBy));
      _ref.invalidate(expenseByIdProvider(id));

      final isDraft = data['status'] == AppConstants.statusDraft;
      state = state.copyWith(
        isLoading: false,
        successMessage: isDraft ? 'Draft updated.' : 'Expense submitted successfully.',
      );
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> approveExpense({
    required String expenseId,
    required String approvedBy,
    required String approvedByName,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final businessId = _businessId;

      // Fetch before approval to get submittedBy for notification + stream invalidation
      final expense = await _dataSource.getExpenseById(expenseId, businessId: businessId);

      await _dataSource.approveExpense(
        expenseId: expenseId,
        approvedBy: approvedBy,
        approvedByName: approvedByName,
        businessId: businessId,
      );

      _notificationService.notifyExpenseApproved(
        employeeId: expense.submittedBy,
        expenseTitle: expense.title,
        expenseId: expenseId,
        businessId: businessId,
      ).ignore();

      _ref.invalidate(allExpensesStreamProvider);
      _ref.invalidate(pendingExpensesStreamProvider);
      _ref.invalidate(employeeExpensesStreamProvider(expense.submittedBy));
      _ref.invalidate(allLedgerProvider);
      _ref.invalidate(ledgerByEmployeeProvider(expense.submittedBy));
      _ref.invalidate(ledgerSummaryProvider(expense.submittedBy));
      _ref.invalidate(employeeLedgerRestProvider(expense.submittedBy));
      _ref.invalidate(employeeLedgerSummaryProvider(expense.submittedBy));

      state = state.copyWith(isLoading: false, successMessage: 'Expense approved.');
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> rejectExpense({
    required String expenseId,
    required String rejectedBy,
    required String rejectedByName,
    required String reason,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final businessId = _businessId;

      final expense = await _dataSource.getExpenseById(expenseId, businessId: businessId);

      await _dataSource.rejectExpense(
        expenseId: expenseId,
        rejectedBy: rejectedBy,
        rejectedByName: rejectedByName,
        reason: reason,
        businessId: businessId,
      );

      _notificationService.notifyExpenseRejected(
        employeeId: expense.submittedBy,
        expenseTitle: expense.title,
        expenseId: expenseId,
        reason: reason,
        businessId: businessId,
      ).ignore();

      _ref.invalidate(allExpensesStreamProvider);
      _ref.invalidate(pendingExpensesStreamProvider);
      _ref.invalidate(employeeExpensesStreamProvider(expense.submittedBy));

      state = state.copyWith(isLoading: false, successMessage: 'Expense rejected.');
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> deleteExpense(String id) async {
    state = state.copyWith(isLoading: true);
    try {
      await _dataSource.deleteExpense(id, businessId: _businessId);
      state = state.copyWith(isLoading: false, successMessage: 'Expense deleted.');
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  void clearMessages() => state = state.copyWith();
}

final expenseNotifierProvider =
    StateNotifierProvider<ExpenseNotifier, ExpenseState>((ref) {
  return ExpenseNotifier(
    ref.watch(expenseRemoteDataSourceProvider),
    ref.watch(storageServiceProvider),
    ref.watch(notificationServiceProvider),
    ref,
  );
});
