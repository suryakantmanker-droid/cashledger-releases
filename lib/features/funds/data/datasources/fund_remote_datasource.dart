import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/utils/app_utils.dart';
import '../models/fund_model.dart';

abstract class FundRemoteDataSource {
  Future<String> transferFund(Map<String, dynamic> data, {required String businessId});
  Stream<List<FundModel>> watchFundsByEmployee(String employeeId, {required String businessId});
  Stream<List<FundModel>> watchAllFunds({required String businessId});
  Future<List<FundModel>> getAllFunds({required String businessId});
  Future<List<FundModel>> getFundsByEmployee(String employeeId, {required String businessId});
}

class FundRemoteDataSourceImpl implements FundRemoteDataSource {
  final SupabaseClient _supabase;
  const FundRemoteDataSourceImpl(this._supabase);

  @override
  Future<String> transferFund(Map<String, dynamic> data, {required String businessId}) async {
    try {
      final transferId = AppUtils.generateTransferId();
      final transferDateRaw = data['transferDate'];
      String transferDateStr;
      if (transferDateRaw is DateTime) {
        transferDateStr = transferDateRaw.toIso8601String();
      } else if (transferDateRaw is String) {
        transferDateStr = transferDateRaw;
      } else {
        transferDateStr = DateTime.now().toIso8601String();
      }

      // Atomic RPC — migration 010 hardened with cross-business guard (P0001)
      final result = await _supabase.rpc('transfer_fund', params: {
        'p_transfer_id': transferId,
        'p_amount': (data['amount'] as num).toDouble(),
        'p_given_by': data['givenBy'] as String,
        'p_given_by_name': data['givenByName'] as String,
        'p_given_to': data['givenTo'] as String,
        'p_given_to_name': data['givenToName'] as String,
        'p_purpose': data['purpose'] as String,
        'p_payment_mode': data['paymentMode'] as String,
        'p_notes': data['notes'] as String?,
        'p_status': data['status'] as String? ?? AppConstants.fundStatusActive,
        'p_transfer_date': transferDateStr,
        'p_business_id': businessId,
      });

      return result.toString();
    } on PostgrestException catch (e) {
      throw FirestoreException(e.message, code: e.code);
    }
  }

  @override
  Stream<List<FundModel>> watchFundsByEmployee(String employeeId, {required String businessId}) {
    // Supabase stream supports one .eq() — business_id is the security-critical filter.
    // Employee filter applied in Dart map.
    return _supabase
        .from('funds')
        .stream(primaryKey: ['id'])
        .eq('business_id', businessId)
        .order('created_at', ascending: false)
        .map((rows) => rows
            .where((r) => r['given_to'] == employeeId)
            .map((r) => FundModel.fromJson(r))
            .toList());
  }

  @override
  Stream<List<FundModel>> watchAllFunds({required String businessId}) {
    return _supabase
        .from('funds')
        .stream(primaryKey: ['id'])
        .eq('business_id', businessId)
        .order('created_at', ascending: false)
        .limit(AppConstants.pageSize)
        .map((rows) => rows.map((r) => FundModel.fromJson(r)).toList());
  }

  @override
  Future<List<FundModel>> getAllFunds({required String businessId}) async {
    final rows = await _supabase
        .from('funds')
        .select()
        .eq('business_id', businessId)
        .order('created_at', ascending: false);
    return rows.map((r) => FundModel.fromJson(r)).toList();
  }

  @override
  Future<List<FundModel>> getFundsByEmployee(String employeeId, {required String businessId}) async {
    final rows = await _supabase
        .from('funds')
        .select()
        .eq('business_id', businessId)
        .eq('given_to', employeeId)
        .order('created_at', ascending: false);
    return rows.map((r) => FundModel.fromJson(r)).toList();
  }
}
