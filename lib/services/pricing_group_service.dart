import '../data/models/pricing_group.dart';
import 'api_service.dart';

/// A save was refused because a dealer would get the same brands from two
/// groups. Send it again with `onOverlap` ('move' / 'keep') to resolve it.
class PricingOverlapException implements Exception {
  final String message;
  final List<PricingConflict> conflicts;

  const PricingOverlapException(this.message, this.conflicts);

  @override
  String toString() => message;
}

/// Typed wrapper around the pricing-group endpoints.
class PricingGroupService {
  PricingGroupService._();
  static final PricingGroupService instance = PricingGroupService._();

  final _api = ApiService.instance;

  /// Turns the server's overlap refusal into a [PricingOverlapException].
  Future<Map<String, dynamic>> _guard(Future<Map<String, dynamic>> Function() call) async {
    try {
      return await call();
    } catch (e) {
      final body = _api.lastEnvelope?.body;
      final raw = body?['conflicts'];
      final detail = body?['detail']?.toString() ?? '';
      if (raw is List && raw.isNotEmpty && detail.isNotEmpty && e.toString().contains(detail)) {
        throw PricingOverlapException(
          detail,
          raw
              .whereType<Map>()
              .map((m) => PricingConflict.fromJson(m.cast<String, dynamic>()))
              .toList(),
        );
      }
      rethrow;
    }
  }

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
    String? onOverlap,
    bool dryRun = false,
  }) async {
    final body = <String, dynamic>{
      'name': name.trim(),
      'note': note,
      'items': items,
      if (onOverlap != null) 'on_overlap': onOverlap,
      'dry_run': dryRun,
    };
    return PricingSaveResult.fromJson(await _guard(() => _api.savePricingGroup(id, body)));
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
    int? categoryId,
    List<int>? productIds,
  }) async {
    final m = await _api.getPricingGroupOptions(
      kind: kind.apiName,
      search: search,
      withinGroup: withinGroup,
      all: all,
      limit: limit,
      offset: offset,
      categoryId: categoryId,
      productIds: productIds,
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

  /// `items` = the dealer's complete Only / Except list
  /// ([{kind, id, state: 'only' | 'except'}]); null keeps it.
  Future<PricingSaveResult> saveLink({
    required int userId,
    required int groupId,
    bool? active,
    List<Map<String, dynamic>>? items,
    String? onOverlap,
    bool dryRun = false,
  }) async {
    final body = <String, dynamic>{
      if (active != null) 'active': active,
      if (items != null) 'items': items,
      if (onOverlap != null) 'on_overlap': onOverlap,
      'dry_run': dryRun,
    };
    return PricingSaveResult.fromJson(
        await _guard(() => _api.savePricingGroupLink(userId, groupId, body)));
  }

}
