import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/exceptions.dart';
import '../models/sale_model.dart';

abstract class SaleRemoteDataSource {
  Stream<List<SaleModel>> watchSalesByEmployee(
    String employeeId, {
    required String businessId,
  });
  Stream<List<SaleModel>> watchAllSales({required String businessId});
  Future<String> logSale(Map<String, dynamic> data, {required String businessId});
  Future<SaleModel> getSaleById(String id, {required String businessId});
}

class SaleRemoteDataSourceImpl implements SaleRemoteDataSource {
  final SupabaseClient _supabase;
  const SaleRemoteDataSourceImpl(this._supabase);

  @override
  Stream<List<SaleModel>> watchSalesByEmployee(
    String employeeId, {
    required String businessId,
  }) {
    return _supabase
        .from('sales')
        .stream(primaryKey: ['id'])
        .eq('business_id', businessId)
        .order('sale_date', ascending: false)
        .map((rows) => rows
            .where((r) => r['employee_id'] == employeeId)
            .map((r) => SaleModel.fromJson(r))
            .toList());
  }

  @override
  Stream<List<SaleModel>> watchAllSales({required String businessId}) {
    return _supabase
        .from('sales')
        .stream(primaryKey: ['id'])
        .eq('business_id', businessId)
        .order('sale_date', ascending: false)
        .map((rows) => rows.map((r) => SaleModel.fromJson(r)).toList());
  }

  @override
  Future<String> logSale(
    Map<String, dynamic> data, {
    required String businessId,
  }) async {
    try {
      final result = await _supabase.rpc('log_sale_collection', params: {
        'p_sale_id': data['saleId'],
        'p_amount': data['amount'],
        'p_employee_id': data['employeeId'],
        'p_employee_name': data['employeeName'],
        'p_item_description': data['itemDescription'],
        'p_buyer_name': data['buyerName'],
        'p_notes': data['notes'],
        'p_proof_urls': data['proofUrls'] ?? [],
        'p_sale_date': (data['saleDate'] as DateTime).toIso8601String(),
        'p_business_id': businessId,
      });
      return result?.toString() ?? '';
    } on PostgrestException catch (e) {
      throw FirestoreException(e.message, code: e.code);
    }
  }

  @override
  Future<SaleModel> getSaleById(String id, {required String businessId}) async {
    final row = await _supabase
        .from('sales')
        .select()
        .eq('id', id)
        .eq('business_id', businessId)
        .maybeSingle();
    if (row == null) throw const FirestoreException('Sale not found.');
    return SaleModel.fromJson(row);
  }
}
