import '../data/models/balance_add_result.dart';
import 'api_service.dart';

class BalanceService {
  BalanceService._();
  static final BalanceService instance = BalanceService._();

  Future<Map<String, dynamic>> current() =>
      ApiService.instance.getCurrentBalance();
  Future<Map<String, dynamic>> schema() =>
      ApiService.instance.getBalanceSchema();

  Future<AddBalanceResult> addRequest({
    String? lbpAmount,
    String? usdAmount,
  }) async {
    final map = await ApiService.instance.addBalance(
      lbpAmount: lbpAmount,
      usdAmount: usdAmount,
    );
    return AddBalanceResult.fromJson(map);
  }

  Future<Map<String, dynamic>> history({
    int page = 1,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool? status,
    int? currencyId,
    bool? distinctUsers,
    int? userId,
    bool? includeFilters,
  }) =>
      ApiService.instance.getBalanceHistory(
        page: page,
        dateFrom: dateFrom,
        dateTo: dateTo,
        status: status,
        currencyId: currencyId,
        distinctUsers: distinctUsers,
        userId: userId,
        includeFilters: includeFilters,
      );
}
