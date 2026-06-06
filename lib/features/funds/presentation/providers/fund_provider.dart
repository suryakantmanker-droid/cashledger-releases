import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/services/notification_service_provider.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../shared/providers/business_context_provider.dart';
import '../../../ledger/presentation/providers/ledger_provider.dart';
import '../../data/datasources/fund_remote_datasource.dart';
import '../../data/models/fund_model.dart';

final fundRemoteDataSourceProvider = Provider<FundRemoteDataSource>((ref) {
  return FundRemoteDataSourceImpl(ref.watch(supabaseClientProvider));
});

final allFundsStreamProvider =
    StreamProvider.autoDispose<List<FundModel>>((ref) {
  final businessId = ref.watch(activeBusinessIdProvider);
  if (businessId == null) return Stream.value(const []);
  return ref.read(fundRemoteDataSourceProvider)
      .watchAllFunds(businessId: businessId);
});

final employeeFundsStreamProvider =
    StreamProvider.autoDispose.family<List<FundModel>, String>((ref, employeeId) {
  final businessId = ref.watch(activeBusinessIdProvider);
  if (businessId == null) return Stream.value(const []);
  return ref.read(fundRemoteDataSourceProvider)
      .watchFundsByEmployee(employeeId, businessId: businessId);
});

class FundState {
  final bool isLoading;
  final String? errorMessage;
  final String? successMessage;

  const FundState({
    this.isLoading = false,
    this.errorMessage,
    this.successMessage,
  });

  FundState copyWith({
    bool? isLoading,
    String? errorMessage,
    String? successMessage,
  }) {
    return FundState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      successMessage: successMessage,
    );
  }
}

class FundNotifier extends StateNotifier<FundState> {
  final FundRemoteDataSource _dataSource;
  final NotificationService _notificationService;
  final Ref _ref;

  FundNotifier(this._dataSource, this._notificationService, this._ref)
      : super(const FundState());

  Future<bool> transferFund({
    required double amount,
    required String givenBy,
    required String givenByName,
    required String givenTo,
    required String givenToName,
    required String purpose,
    required String paymentMode,
    String? notes,
    required DateTime transferDate,
  }) async {
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

      final transferId = await _dataSource.transferFund(
        {
          'amount': amount,
          'givenBy': givenBy,
          'givenByName': givenByName,
          'givenTo': givenTo,
          'givenToName': givenToName,
          'purpose': purpose,
          'paymentMode': paymentMode,
          'notes': notes,
          'status': AppConstants.fundStatusActive,
          'transferDate': transferDate.toIso8601String(),
        },
        businessId: businessId,
      );

      _notificationService.notifyFundTransferred(
        employeeId: givenTo,
        amount: amount,
        transferId: transferId,
        businessId: businessId,
      ).ignore();

      _ref.invalidate(allFundsStreamProvider);
      _ref.invalidate(allLedgerProvider);
      _ref.invalidate(employeeFundsStreamProvider(givenTo));
      _ref.invalidate(ledgerByEmployeeProvider(givenTo));
      _ref.invalidate(ledgerSummaryProvider(givenTo));
      _ref.invalidate(employeeLedgerRestProvider(givenTo));
      _ref.invalidate(employeeLedgerSummaryProvider(givenTo));

      state = state.copyWith(
        isLoading: false,
        successMessage: '₹${amount.toStringAsFixed(2)} transferred to $givenToName.',
      );
      return true;
    } on Exception catch (e) {
      // Translate cross-business guard errors (P0001) to user-friendly message
      final msg = e.toString();
      final userMsg = msg.contains('Cross-business')
          ? 'Transfer failed: employee does not belong to this business.'
          : msg.contains('must be positive')
              ? 'Transfer amount must be greater than zero.'
              : msg;
      state = state.copyWith(isLoading: false, errorMessage: userMsg);
      return false;
    }
  }

  void clearMessages() => state = state.copyWith();
}

final fundNotifierProvider = StateNotifierProvider<FundNotifier, FundState>((ref) {
  return FundNotifier(
    ref.watch(fundRemoteDataSourceProvider),
    ref.watch(notificationServiceProvider),
    ref,
  );
});
