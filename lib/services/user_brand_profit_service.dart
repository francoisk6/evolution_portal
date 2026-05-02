import '../data/models/user_brand_profit.dart';
import 'api_service.dart';

class UserBrandProfitService {
  UserBrandProfitService._();
  static final UserBrandProfitService instance = UserBrandProfitService._();

  Future<UserBrandProfitFilterOptionsResponse> getFilters({
    int? groupId,
    int? sectorId,
    int? categoryId,
    int? productId,
    int? productTypeId,
    int? brandId,
  }) async {
    final m = await ApiService.instance.getUserBrandProfitFilters(
      groupId: groupId,
      sectorId: sectorId,
      categoryId: categoryId,
      productId: productId,
      productTypeId: productTypeId,
      brandId: brandId,
    );
    return UserBrandProfitFilterOptionsResponse.fromJson(m);
  }

  Future<UserBrandProfitListResponse> list({
    int? groupId,
    int? userId,
    List<int>? userIds,
    int? sectorId,
    int? categoryId,
    int? productId,
    int? productTypeId,
    int? brandId,
    bool? deactivated,
    String? search,
    int page = 1,
    int pageSize = 20,
  }) async {
    final m = await ApiService.instance.getUserBrandProfitList(
      groupId: groupId,
      userId: userId,
      userIds: userIds,
      sectorId: sectorId,
      categoryId: categoryId,
      productId: productId,
      productTypeId: productTypeId,
      brandId: brandId,
      deactivated: deactivated,
      search: search,
      page: page,
      pageSize: pageSize,
    );
    return UserBrandProfitListResponse.fromJson(m);
  }

  Future<UserBrandProfitBulkUpsertResponse> bulkUpsert({
    int? groupId,
    int? userId,
    List<int>? userIds,
    int? sectorId,
    int? categoryId,
    int? productId,
    int? productTypeId,
    int? brandId,
    required String profitPercentage,
    required String sellingProfitPercentage,
    bool overrideExisting = false,
  }) async {
    final m = await ApiService.instance.bulkUpsertUserBrandProfit(
      groupId: groupId,
      userId: userId,
      userIds: userIds,
      sectorId: sectorId,
      categoryId: categoryId,
      productId: productId,
      productTypeId: productTypeId,
      brandId: brandId,
      profitPercentage: profitPercentage,
      sellingProfitPercentage: sellingProfitPercentage,
      overrideExisting: overrideExisting,
    );
    return UserBrandProfitBulkUpsertResponse.fromJson(m);
  }

  Future<UserBrandProfitItem> detail(int id) async {
    final m = await ApiService.instance.getUserBrandProfitDetail(id);
    final raw = m['item'];
    if (raw is Map<String, dynamic>) return UserBrandProfitItem.fromJson(raw);
    if (raw is Map) return UserBrandProfitItem.fromJson(raw.cast<String, dynamic>());
    return UserBrandProfitItem.fromJson(m);
  }

  Future<UserBrandProfitItem> update(int id, Map<String, dynamic> body) async {
    final m = await ApiService.instance.updateUserBrandProfit(id, body);
    final raw = m['item'];
    if (raw is Map<String, dynamic>) return UserBrandProfitItem.fromJson(raw);
    if (raw is Map) return UserBrandProfitItem.fromJson(raw.cast<String, dynamic>());
    return detail(id);
  }

  Future<void> delete(int id) => ApiService.instance.deleteUserBrandProfit(id);
}
