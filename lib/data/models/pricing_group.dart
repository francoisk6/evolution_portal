// Models for the pricing-group admin API (/api/online/pricing-groups/...).
//
// A pricing group = categories / products / brands, each with its own
// dealer % and selling % (or excluded). The most specific item wins: brand,
// then product, then category. Turning a group on for a dealer writes the
// resulting % into the dealer's user-x-brand rows. Percentages are
// multipliers ("1.05" = +5%); a blank % is taken from the item above it, and
// blank all the way up means "leave that value alone on existing rows".

int _asInt(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

int? _asIntOrNull(dynamic v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));

bool _asBool(dynamic v) {
  if (v is bool) return v;
  final s = v?.toString().trim().toLowerCase();
  return s == 'true' || s == '1' || s == 'yes';
}

String? _asStrOrNull(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

Map<String, dynamic> _asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.cast<String, dynamic>();
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _asMapList(dynamic v) {
  if (v is! List) return const <Map<String, dynamic>>[];
  return v.map(_asMap).toList();
}

/// One pickable / listed item: a category, a product (or, for workspace
/// admins, a product prefix covering several products) or a brand.
class PricingGroupItem {
  final int? id;
  final String key;
  final String label;
  final String subtitle;
  final List<int> productIds;

  /// Parents, for showing inherited percentages (catalog rows only).
  final int? categoryId;
  final int? productId;

  const PricingGroupItem({
    required this.id,
    required this.key,
    required this.label,
    required this.subtitle,
    this.productIds = const <int>[],
    this.categoryId,
    this.productId,
  });

  factory PricingGroupItem.fromJson(Map<String, dynamic> j) {
    final ids = (j['product_ids'] is List)
        ? (j['product_ids'] as List).map(_asInt).toList()
        : const <int>[];
    final id = j['id'] == null ? null : _asInt(j['id']);
    return PricingGroupItem(
      id: id,
      key: _asStrOrNull(j['key']) ?? 'id:${id ?? ''}',
      label: j['label']?.toString() ?? '',
      subtitle: j['subtitle']?.toString() ?? '',
      productIds: ids,
      categoryId: _asIntOrNull(j['category_id']),
      productId: _asIntOrNull(j['product_id']),
    );
  }

  @override
  bool operator ==(Object other) => other is PricingGroupItem && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// One page of picker options plus how many match in total.
class PricingOptions {
  final List<PricingGroupItem> items;
  final int total;

  const PricingOptions({required this.items, required this.total});

  bool get isEmpty => items.isEmpty;

  factory PricingOptions.fromJson(Map<String, dynamic> j) {
    final items = _asMapList(j['options']).map(PricingGroupItem.fromJson).toList();
    // Older servers send no total: fall back to what came back.
    final total = j.containsKey('total') ? _asInt(j['total']) : items.length;
    return PricingOptions(items: items, total: total);
  }
}

enum PricingItemKind { category, product, brand }

extension PricingItemKindX on PricingItemKind {
  String get apiName => switch (this) {
        PricingItemKind.category => 'category',
        PricingItemKind.product => 'product',
        PricingItemKind.brand => 'brand',
      };

  String get title => switch (this) {
        PricingItemKind.category => 'Categories',
        PricingItemKind.product => 'Products',
        PricingItemKind.brand => 'Brands',
      };
}

PricingItemKind? pricingKindFromApi(String? v) => switch (v) {
      'category' => PricingItemKind.category,
      'product' => PricingItemKind.product,
      'brand' => PricingItemKind.brand,
      _ => null,
    };

/// One item of a group with its own settings (per-item grid).
class PricingGroupEntry {
  final PricingItemKind kind;
  final int id;
  final String label;
  final String subtitle;
  final int? categoryId;
  final int? productId;
  final bool excluded;
  final String? profitPercentage;
  final String? sellingProfitPercentage;
  final bool editable;

  const PricingGroupEntry({
    required this.kind,
    required this.id,
    required this.label,
    required this.subtitle,
    this.categoryId,
    this.productId,
    this.excluded = false,
    this.profitPercentage,
    this.sellingProfitPercentage,
    this.editable = true,
  });

  static PricingGroupEntry? fromJson(Map<String, dynamic> j) {
    final kind = pricingKindFromApi(j['kind']?.toString());
    if (kind == null || j['id'] == null) return null;
    return PricingGroupEntry(
      kind: kind,
      id: _asInt(j['id']),
      label: j['label']?.toString() ?? '',
      subtitle: j['subtitle']?.toString() ?? '',
      categoryId: _asIntOrNull(j['category_id']),
      productId: _asIntOrNull(j['product_id']),
      excluded: _asBool(j['excluded']),
      profitPercentage: _asStrOrNull(j['profit_percentage']),
      sellingProfitPercentage: _asStrOrNull(j['selling_profit_percentage']),
      editable: j.containsKey('editable') ? _asBool(j['editable']) : true,
    );
  }
}

class PricingGroupItems {
  final List<PricingGroupItem> categories;
  final List<PricingGroupItem> products;
  final List<PricingGroupItem> brands;
  final int hiddenItemCount;

  /// Every item with its own % (null on servers without per-item %).
  final List<PricingGroupEntry>? entries;

  const PricingGroupItems({
    this.categories = const <PricingGroupItem>[],
    this.products = const <PricingGroupItem>[],
    this.brands = const <PricingGroupItem>[],
    this.hiddenItemCount = 0,
    this.entries,
  });

  factory PricingGroupItems.fromJson(Map<String, dynamic> j) {
    List<PricingGroupItem> list(String k) =>
        _asMapList(j[k]).map(PricingGroupItem.fromJson).toList();
    return PricingGroupItems(
      categories: list('categories'),
      products: list('products'),
      brands: list('brands'),
      hiddenItemCount: j.containsKey('hidden_entry_count')
          ? _asInt(j['hidden_entry_count'])
          : _asInt(j['hidden_item_count']),
      entries: j['entries'] is List
          ? _asMapList(j['entries'])
              .map(PricingGroupEntry.fromJson)
              .whereType<PricingGroupEntry>()
              .toList()
          : null,
    );
  }

  List<PricingGroupItem> of(PricingItemKind kind) => switch (kind) {
        PricingItemKind.category => categories,
        PricingItemKind.product => products,
        PricingItemKind.brand => brands,
      };

  int get total => categories.length + products.length + brands.length;
}

class PricingGroupCounts {
  final int categories;
  final int products;
  final int brands;
  final int excluded;
  final int membersActive;
  final int membersTotal;

  const PricingGroupCounts({
    this.categories = 0,
    this.products = 0,
    this.brands = 0,
    this.excluded = 0,
    this.membersActive = 0,
    this.membersTotal = 0,
  });

  String get itemsLabel => '$categories cat · $products prod · $brands brand'
      '${excluded > 0 ? ' · $excluded excluded' : ''}';

  factory PricingGroupCounts.fromJson(Map<String, dynamic> j) => PricingGroupCounts(
        categories: _asInt(j['categories']),
        products: _asInt(j['products']),
        brands: _asInt(j['brands']),
        excluded: _asInt(j['excluded']),
        membersActive: _asInt(j['members_active']),
        membersTotal: _asInt(j['members_total']),
      );
}

class PricingGroup {
  final int id;
  final String name;
  final String? profitPercentage;
  final String? sellingProfitPercentage;
  final String note;
  final PricingGroupCounts counts;
  final PricingGroupItems? items;

  const PricingGroup({
    required this.id,
    required this.name,
    required this.profitPercentage,
    required this.sellingProfitPercentage,
    required this.note,
    required this.counts,
    this.items,
  });

  factory PricingGroup.fromJson(Map<String, dynamic> j) => PricingGroup(
        id: _asInt(j['id']),
        name: j['name']?.toString() ?? '',
        profitPercentage: _asStrOrNull(j['profit_percentage']),
        sellingProfitPercentage: _asStrOrNull(j['selling_profit_percentage']),
        note: j['note']?.toString() ?? '',
        counts: PricingGroupCounts.fromJson(_asMap(j['counts'])),
        items: j['items'] == null ? null : PricingGroupItems.fromJson(_asMap(j['items'])),
      );

  /// Every item shares one %: show it; otherwise the % is set per item.
  bool get hasSinglePercent => profitPercentage != null || sellingProfitPercentage != null;

  String get percentLabel => hasSinglePercent
      ? 'Dealer ${profitPercentage ?? 'per item'} · Selling ${sellingProfitPercentage ?? 'per item'}'
      : 'Percentages per item';
}

/// Result counts of an apply run or a preview.
class PricingApplySummary {
  final int activeUsers;
  final int brandsInScope;
  final int created;
  final int updated;
  final int claimed;
  final int released;
  final int unchanged;
  final int fixedPriceRows;
  final int skippedOtherGroup;
  final bool dryRun;

  const PricingApplySummary({
    this.activeUsers = 0,
    this.brandsInScope = 0,
    this.created = 0,
    this.updated = 0,
    this.claimed = 0,
    this.released = 0,
    this.unchanged = 0,
    this.fixedPriceRows = 0,
    this.skippedOtherGroup = 0,
    this.dryRun = false,
  });

  factory PricingApplySummary.fromJson(Map<String, dynamic> j) => PricingApplySummary(
        activeUsers: _asInt(j['active_users']),
        brandsInScope: _asInt(j['brands_in_scope']),
        created: _asInt(j['created']),
        updated: _asInt(j['updated']),
        claimed: _asInt(j['claimed']),
        released: _asInt(j['released']),
        unchanged: _asInt(j['unchanged']),
        fixedPriceRows: _asInt(j['fixed_price_rows']),
        skippedOtherGroup: _asInt(j['skipped_owned_by_other_group']),
        dryRun: _asBool(j['dry_run']),
      );

  int get changes => created + updated + claimed + released;

  /// Plain-language lines for the preview / result panel.
  List<String> lines() => <String>[
        '$brandsInScope brand(s) in scope · $activeUsers active member(s)',
        if (created > 0) '$created row(s) will be created (gives access to the brand)',
        if (updated > 0) '$updated row(s) will get the new percentages',
        if (claimed > 0) '$claimed existing row(s) will be taken over by the group',
        if (released > 0) '$released row(s) will be released (keep their price, managed by hand)',
        if (fixedPriceRows > 0) '$fixedPriceRows row(s) have a fixed price - the fixed price still wins',
        if (skippedOtherGroup > 0) '$skippedOtherGroup row(s) skipped - managed by another group',
        if (changes == 0) 'Nothing to change.',
      ];
}

class PricingGroupMember {
  final int userId;
  final String username;
  final String fullName;
  final bool isActiveUser;
  final bool active;
  final int exclusionCount;

  const PricingGroupMember({
    required this.userId,
    required this.username,
    required this.fullName,
    required this.isActiveUser,
    required this.active,
    required this.exclusionCount,
  });

  factory PricingGroupMember.fromJson(Map<String, dynamic> j) => PricingGroupMember(
        userId: _asInt(j['id']),
        username: j['username']?.toString() ?? '',
        fullName: j['full_name']?.toString() ?? '',
        isActiveUser: _asBool(j['is_active']),
        active: _asBool(j['active']),
        exclusionCount: _asInt(j['exclusion_count']),
      );
}

class PricingGroupLog {
  final int id;
  final String trigger;
  final String? actor;
  final DateTime? createdAt;
  final PricingApplySummary summary;
  final DateTime? undoneAt;
  final bool canUndo;

  const PricingGroupLog({
    required this.id,
    required this.trigger,
    required this.actor,
    required this.createdAt,
    required this.summary,
    required this.undoneAt,
    required this.canUndo,
  });

  factory PricingGroupLog.fromJson(Map<String, dynamic> j) => PricingGroupLog(
        id: _asInt(j['id']),
        trigger: j['trigger']?.toString() ?? '',
        actor: _asStrOrNull(j['actor']),
        createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '')?.toLocal(),
        summary: PricingApplySummary.fromJson(_asMap(j['summary'])),
        undoneAt: DateTime.tryParse(j['undone_at']?.toString() ?? '')?.toLocal(),
        canUndo: _asBool(j['can_undo']),
      );

  String get triggerLabel => switch (trigger) {
        'group_created' => 'Group created',
        'group_saved' => 'Group saved',
        'link' => 'Member changed',
        'reapply' => 'Re-applied',
        'brand_created' => 'New brand',
        _ => trigger,
      };
}

class PricingGroupDetail {
  final PricingGroup group;
  final List<PricingGroupMember> members;
  final PricingApplySummary impact;
  final bool inSync;
  final List<PricingGroupLog> recentLogs;

  const PricingGroupDetail({
    required this.group,
    required this.members,
    required this.impact,
    required this.inSync,
    required this.recentLogs,
  });

  factory PricingGroupDetail.fromJson(Map<String, dynamic> j) => PricingGroupDetail(
        group: PricingGroup.fromJson(_asMap(j['group'])),
        members: _asMapList(j['members']).map(PricingGroupMember.fromJson).toList(),
        impact: PricingApplySummary.fromJson(_asMap(j['impact'])),
        inSync: _asBool(j['in_sync']),
        recentLogs: _asMapList(j['recent_logs']).map(PricingGroupLog.fromJson).toList(),
      );
}

class PricingGroupListResponse {
  final List<PricingGroup> groups;
  final bool canEdit;
  final bool canUseCategories;

  const PricingGroupListResponse({
    required this.groups,
    required this.canEdit,
    required this.canUseCategories,
  });

  factory PricingGroupListResponse.fromJson(Map<String, dynamic> j) {
    final perms = _asMap(j['permissions']);
    return PricingGroupListResponse(
      groups: _asMapList(j['groups']).map(PricingGroup.fromJson).toList(),
      canEdit: _asBool(perms['can_edit']),
      canUseCategories: _asBool(perms['can_use_categories']),
    );
  }
}

/// Server reply to a save / preview.
class PricingSaveResult {
  final String message;
  final PricingApplySummary summary;
  final int prunedCount;
  final Map<String, dynamic> raw;

  const PricingSaveResult({
    required this.message,
    required this.summary,
    required this.prunedCount,
    required this.raw,
  });

  factory PricingSaveResult.fromJson(Map<String, dynamic> j) => PricingSaveResult(
        message: j['message']?.toString() ?? '',
        summary: PricingApplySummary.fromJson(_asMap(j['summary'])),
        prunedCount: (j['pruned'] is List) ? (j['pruned'] as List).length : 0,
        raw: j,
      );
}

class PricingDealer {
  final int id;
  final String username;
  final String fullName;
  final bool isActiveUser;
  final List<String> activeGroups;

  const PricingDealer({
    required this.id,
    required this.username,
    required this.fullName,
    required this.isActiveUser,
    required this.activeGroups,
  });

  factory PricingDealer.fromJson(Map<String, dynamic> j) => PricingDealer(
        id: _asInt(j['id']),
        username: j['username']?.toString() ?? '',
        fullName: j['full_name']?.toString() ?? '',
        isActiveUser: _asBool(j['is_active']),
        activeGroups: _asMapList(j['active_groups'])
            .map((g) => g['name']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList(),
      );
}

/// One group as seen from one dealer.
class PricingUserLink {
  final PricingGroup group;
  final bool linked;
  final bool active;
  final PricingGroupItems exclusions;
  final int scopeCount;
  final int managedRows;

  const PricingUserLink({
    required this.group,
    required this.linked,
    required this.active,
    required this.exclusions,
    required this.scopeCount,
    required this.managedRows,
  });

  factory PricingUserLink.fromJson(Map<String, dynamic> j) => PricingUserLink(
        group: PricingGroup.fromJson(_asMap(j['group'])),
        linked: _asBool(j['linked']),
        active: _asBool(j['active']),
        exclusions: PricingGroupItems.fromJson(_asMap(j['exclusions'])),
        scopeCount: _asInt(j['scope_count']),
        managedRows: _asInt(j['managed_rows']),
      );
}

class PricingUserDetail {
  final PricingDealer user;
  final List<PricingUserLink> groups;

  const PricingUserDetail({required this.user, required this.groups});

  factory PricingUserDetail.fromJson(Map<String, dynamic> j) => PricingUserDetail(
        user: PricingDealer.fromJson(_asMap(j['user'])),
        groups: _asMapList(j['groups']).map(PricingUserLink.fromJson).toList(),
      );
}
