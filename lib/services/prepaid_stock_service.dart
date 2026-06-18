import '../data/models/prepaid_stock.dart';
import 'api_service.dart';

class PrepaidStockService {
  PrepaidStockService._();
  static final PrepaidStockService instance = PrepaidStockService._();

  /// Fetch prepaid card stock grouped by brand.
  ///
  /// [consumed] accepts 'false' (default), 'true', or 'all'.
  /// [order] accepts 'quantity' (default, desc) or 'name' (asc).
  Future<PrepaidStockResponse> stockByBrand({
    List<int>? sectorIds,
    List<int>? categoryIds,
    List<int>? productIds,
    List<int>? brandIds,
    String? search,
    String? consumed,
    String? order,
  }) async {
    final m = await ApiService.instance.getPrepaidStockByBrand(
      sectorIds: sectorIds,
      categoryIds: categoryIds,
      productIds: productIds,
      brandIds: brandIds,
      search: search,
      consumed: consumed,
      order: order,
    );
    return PrepaidStockResponse.fromJson(m);
  }
}
