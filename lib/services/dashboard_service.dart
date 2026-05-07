import '../data/models/dashboard_aggregates.dart';
import 'api_service.dart';

class DashboardService {
  DashboardService._();
  static final DashboardService instance = DashboardService._();

  Future<DashboardResponse> get({
    String? dateFrom,
    String? dateTo,
    String? currency,
    String? reportCurrency,
    String? status,
    int top = 10,
    int? userId,
    String? userIds,
  }) async {
    final m = await ApiService.instance.getDashboard(
      dateFrom: dateFrom,
      dateTo: dateTo,
      currency: currency,
      reportCurrency: reportCurrency,
      status: status,
      top: top,
      userId: userId,
      userIds: userIds,
    );
    return DashboardResponse.fromJson(m);
  }
}
