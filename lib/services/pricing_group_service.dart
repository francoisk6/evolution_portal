import '../data/models/pricing_group.dart';
import 'api_service.dart';

/// Typed wrapper around the pricing-group endpoints.
class PricingGroupService {
  PricingGroupService._();
  static final PricingGroupService instance = PricingGroupService._();

  final _api = ApiService.instance;

  Future<PricingGroupListResponse> list({String? search}) async =>
      PricingGroupListResponse.fromJson(await _api.getPricingGroups(search: search));

  Future<PricingGroupDetail> detail(int id) async =>
      PricingGroupDetail.fromJson(await _api.getPricingGroup(id));

  /// Create (id == null) or update a group. `items` is the complete item
  /// list with each item's own settings (see [PricingItemDraft.toJson]).
  Future<PricingSaveResult> save({
    int? id,
    required String name,
    required String note,
    required List<Map<String, dynamic>> items,
    bool dryRun = false,
  }) async {
    final body = <String, dynamic>{
      'name': name.trim(),
      'note': note,
      'items': items,
      'dry_run': dryRun,
    };
    return PricingSaveResult.fromJson(await _api.savePricingGroup(id, body));
  }

  Future<String> delete(int id) async =>
      (await _api.deletePricingGroup(id))['message']?.toString() ?? 'Deleted.';

  Future<String> reapply(int id) async =>
      (await _api.reapplyPricingGroup(id))['message']?.toString() ?? 'Re-applied.';

  Future<List<PricingGroupLog>> logs(int id) async {
    final m = await _api.getPricingGroupLogs(id);
    final raw = m['logs'];
    if (raw is! List) return const <PricingGroupLog>[];
    return raw
        .whereType<Map>()
        .map((e) => PricingGroupLog.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<String> undo(int logId) async =>
      (await _api.undoPricingGroupLog(logId))['message']?.toString() ?? 'Undone.';

  /// `all: true` returns every match (server cap 2000) for "Select all".
  Future<PricingOptions> options({
    required PricingItemKind kind,
    String? search,
    int? withinGroup,
    bool all = false,
    int limit = 50,
    int offset = 0,
  }) async {
    final m = await _api.getPricingGroupOptions(
      kind: kind.apiName,
      search: search,
      withinGroup: withinGroup,
      all: all,
      limit: limit,
      offset: offset,
    );
    return PricingOptions.fromJson(m);
  }

  Future<List<PricingDealer>> dealers({String? search, int? groupId}) async {
    final m = await _api.getPricingGroupDealers(search: search, groupId: groupId);
    final raw = m['users'];
    if (raw is! List) return const <PricingDealer>[];
    return raw
        .whereType<Map>()
        .map((e) => PricingDealer.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<PricingUserDetail> dealer(int userId) async =>
      PricingUserDetail.fromJson(await _api.getPricingGroupDealer(userId));

  Future<PricingSaveResult> saveLink({
    required int userId,
    required int groupId,
    bool? active,
    List<int>? excludedCategoryIds,
    List<int>? excludedProductIds,
    List<int>? excludedBrandIds,
    bool dryRun = false,
  }) async {
    final body = <String, dynamic>{
      if (active != null) 'active': active,
      if (excludedCategoryIds != null) 'excluded_category_ids': excludedCategoryIds,
      if (excludedProductIds != null) 'excluded_product_ids': excludedProductIds,
      if (excludedBrandIds != null) 'excluded_brand_ids': excludedBrandIds,
      'dry_run': dryRun,
    };
    return PricingSaveResult.fromJson(await _api.savePricingGroupLink(userId, groupId, body));
  }

}
