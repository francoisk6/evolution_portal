import '../data/models/transaction_history.dart';
import 'api_service.dart';

class TransactionService {
  TransactionService._();
  static final TransactionService instance = TransactionService._();

  Future<TransactionListResponse> list({
    String? dateFrom,
    String? dateTo,
    int limit = 50,
    String? cursor,
    bool includeSummary = true,
    bool includeFilters = true,
    bool includeBalance = true,
    String? currency,
    String? status,
    String? q,
    int? userId,
    int? sectorId,
    int? productId,
    int? brandId,
    bool? brandNotNull,
  }) async {
    final m = await ApiService.instance.getTransactions(
      dateFrom: dateFrom,
      dateTo: dateTo,
      limit: limit,
      cursor: cursor,
      includeSummary: includeSummary,
      includeFilters: includeFilters,
      includeBalance: includeBalance,
      currency: currency,
      status: status,
      q: q,
      userId: userId,
      sectorId: sectorId,
      productId: productId,
      brandId: brandId,
      brandNotNull: brandNotNull,
    );
    return TransactionListResponse.fromJson(m);
  }

  Future<TransactionDetail> detail(int id, {bool includeBalance = false}) async {
    final m = await ApiService.instance.getTransactionDetail(
      id: id,
      includeBalance: includeBalance,
    );
    return TransactionDetail.fromJson(m);
  }


  Future<DownloadedFile> exportExcel({
    String? dateFrom,
    String? dateTo,
    String? currency,
    String? status,
    String? q,
    int? userId,
    int? sectorId,
    int? productId,
    int? brandId,
    bool? brandNotNull,
    DownloadCancelToken? cancelToken,
  }) {
    return ApiService.instance.exportTransactionsExcel(
      dateFrom: dateFrom,
      dateTo: dateTo,
      currency: currency,
      status: status,
      q: q,
      userId: userId,
      sectorId: sectorId,
      productId: productId,
      brandId: brandId,
      brandNotNull: brandNotNull,
      cancelToken: cancelToken,
    );
  }

  Future<Map<String, dynamic>> onlinePurchaseOrderCheck({
    required String orderNumber,
    required String sectorName,
    required int transactionId,
  }) async {
    return ApiService.instance.postOnlinePurchaseOrderCheck(
      orderNumber: orderNumber,
      sectorName: sectorName,
      transactionId: transactionId,
    );
  }
}
