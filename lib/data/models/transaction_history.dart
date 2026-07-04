/// Models for /api/account/transactions/ and /api/account/transactions/<id>/
///
/// Designed to be tolerant to backend variations:
/// - numeric values can be strings, ints, doubles
/// - note can be Map/List/string/null
/// - summary / filters blocks may be missing entirely

Map<String, dynamic> _asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.cast<String, dynamic>();
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _asMapList(dynamic v) {
  final raw = (v as List?) ?? const <dynamic>[];
  return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
}

String? _asCleanString(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

int? _asIntOrNull(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  return int.tryParse(s);
}

bool? _asBoolOrNull(dynamic v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().trim().toLowerCase();
  if (s.isEmpty) return null;
  if (s == 'true' || s == '1' || s == 'yes' || s == 'y') return true;
  if (s == 'false' || s == '0' || s == 'no' || s == 'n') return false;
  return null;
}

class TransactionMeta {
  final String? dateFrom;
  final String? dateTo;
  final int limit;
  final String? nextCursor;
  final bool hasMore;
  final bool filtersIncluded;

  const TransactionMeta({
    required this.dateFrom,
    required this.dateTo,
    required this.limit,
    required this.nextCursor,
    required this.hasMore,
    required this.filtersIncluded,
  });

  factory TransactionMeta.fromJson(Map<String, dynamic> m) {
    final range = _asMap(m['range']);

    return TransactionMeta(
      dateFrom: range['from']?.toString(),
      dateTo: range['to']?.toString(),
      limit: int.tryParse('${m['limit'] ?? 50}') ?? 50,
      nextCursor: _asCleanString(m['next_cursor']),
      hasMore: _asBoolOrNull(m['has_more']) ?? false,
      filtersIncluded: _asBoolOrNull(m['filters_included']) ?? false,
    );
  }
}

class TransactionBalanceItem {
  final String currency;
  final String amount;
  const TransactionBalanceItem({required this.currency, required this.amount});

  factory TransactionBalanceItem.fromJson(Map<String, dynamic> m) {
    return TransactionBalanceItem(
      currency: (m['currency'] ?? '').toString(),
      amount: (m['amount'] ?? '0').toString(),
    );
  }
}

class TransactionTotals {
  final int count;
  final String costPrice;
  final String dealerPrice;
  final String customerPrice;
  final String dProfit;
  final String aProfit;
  final String costPriceOriginal;
  final String costPriceOriginalByBrandCurrency;

  const TransactionTotals({
    required this.count,
    required this.costPrice,
    required this.dealerPrice,
    required this.customerPrice,
    required this.dProfit,
    required this.aProfit,
    required this.costPriceOriginal,
    required this.costPriceOriginalByBrandCurrency,
  });

  static int _parseInt(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    final s = v.toString().trim();
    if (s.isEmpty) return fallback;
    final asInt = int.tryParse(s);
    if (asInt != null) return asInt;
    final asDouble = double.tryParse(s);
    if (asDouble != null) return asDouble.toInt();
    return fallback;
  }

  factory TransactionTotals.fromJson(Map<String, dynamic> m) {
    return TransactionTotals(
      count: _parseInt(m['count'], fallback: 0),
      costPrice: (m['cost_price'] ?? '0').toString(),
      dealerPrice: (m['dealer_price'] ?? '0').toString(),
      customerPrice: (m['customer_price'] ?? '0').toString(),
      dProfit: (m['d_profit'] ?? '0').toString(),
      aProfit: (m['a_profit'] ?? '0').toString(),
      costPriceOriginal: (m['cost_price_original'] ?? '0').toString(),
      costPriceOriginalByBrandCurrency:
          (m['cost_price_original_by_brand_currency'] ??
                  m['cost_price_original'] ??
                  '0')
              .toString(),
    );
  }
}

class TransactionSummary {
  final List<TransactionBalanceItem> balances;
  final Map<String, TransactionTotals> totals;

  const TransactionSummary({required this.balances, required this.totals});

  factory TransactionSummary.fromJson(Map<String, dynamic> m) {
    final totalsMap = _asMap(m['totals']);
    final totals = <String, TransactionTotals>{};

    for (final entry in totalsMap.entries) {
      totals[entry.key.toString()] =
          TransactionTotals.fromJson(_asMap(entry.value));
    }

    return TransactionSummary(
      balances: _asMapList(m['balances'])
          .map(TransactionBalanceItem.fromJson)
          .toList(),
      totals: totals,
    );
  }
}

class TransactionFilterUserOption {
  final int id;
  final String username;
  final String label;

  const TransactionFilterUserOption({
    required this.id,
    required this.username,
    required this.label,
  });

  factory TransactionFilterUserOption.fromJson(Map<String, dynamic> m) {
    return TransactionFilterUserOption(
      id: _asIntOrNull(m['id']) ?? 0,
      username: (m['username'] ?? '').toString(),
      label: (m['label'] ?? m['username'] ?? '').toString(),
    );
  }
}

class TransactionFilterSectorOption {
  final int id;
  final String name;
  final String alt;
  final String label;

  const TransactionFilterSectorOption({
    required this.id,
    required this.name,
    required this.alt,
    required this.label,
  });

  factory TransactionFilterSectorOption.fromJson(Map<String, dynamic> m) {
    return TransactionFilterSectorOption(
      id: _asIntOrNull(m['id']) ?? 0,
      name: (m['name'] ?? '').toString(),
      alt: (m['alt'] ?? '').toString(),
      label: (m['label'] ?? m['name'] ?? m['alt'] ?? '').toString(),
    );
  }
}

class TransactionFilterCategoryOption {
  final int id;
  final String name;
  final String alt;
  final String label;
  final int? sectorId;

  const TransactionFilterCategoryOption({
    required this.id,
    required this.name,
    required this.alt,
    required this.label,
    required this.sectorId,
  });

  factory TransactionFilterCategoryOption.fromJson(Map<String, dynamic> m) {
    return TransactionFilterCategoryOption(
      id: _asIntOrNull(m['id']) ?? 0,
      name: (m['name'] ?? '').toString(),
      alt: (m['alt'] ?? '').toString(),
      label: (m['label'] ?? m['name'] ?? m['alt'] ?? '').toString(),
      sectorId: _asIntOrNull(m['sector_id']),
    );
  }
}

class TransactionFilterProductOption {
  final int id;
  final String name;
  final String alt;
  final String label;
  final int? sectorId;

  const TransactionFilterProductOption({
    required this.id,
    required this.name,
    required this.alt,
    required this.label,
    required this.sectorId,
  });

  factory TransactionFilterProductOption.fromJson(Map<String, dynamic> m) {
    return TransactionFilterProductOption(
      id: _asIntOrNull(m['id']) ?? 0,
      name: (m['name'] ?? '').toString(),
      alt: (m['alt'] ?? '').toString(),
      label: (m['label'] ?? m['name'] ?? m['alt'] ?? '').toString(),
      sectorId: _asIntOrNull(m['sector_id']),
    );
  }
}

class TransactionFilterBrandOption {
  final int id;
  final String name;
  final String alt;
  final String label;
  final int? productId;
  final int? sectorId;
  final int? sortNumber;

  const TransactionFilterBrandOption({
    required this.id,
    required this.name,
    required this.alt,
    required this.label,
    required this.productId,
    required this.sectorId,
    required this.sortNumber,
  });

  factory TransactionFilterBrandOption.fromJson(Map<String, dynamic> m) {
    return TransactionFilterBrandOption(
      id: _asIntOrNull(m['id']) ?? 0,
      name: (m['name'] ?? '').toString(),
      alt: (m['alt'] ?? '').toString(),
      label: (m['label'] ?? m['name'] ?? m['alt'] ?? '').toString(),
      productId: _asIntOrNull(m['product_id']),
      sectorId: _asIntOrNull(m['sector_id']),
      sortNumber: _asIntOrNull(m['sort_number']),
    );
  }
}

class TransactionFilterSelected {
  final int? userId;
  final String? currency;
  final String? status;
  final String? q;
  final bool? brandNotNull;
  final int? sectorId;
  final int? categoryId;
  final int? productId;
  final int? brandId;

  const TransactionFilterSelected({
    this.userId,
    this.currency,
    this.status,
    this.q,
    this.brandNotNull,
    this.sectorId,
    this.categoryId,
    this.productId,
    this.brandId,
  });

  factory TransactionFilterSelected.fromJson(Map<String, dynamic> m) {
    return TransactionFilterSelected(
      userId: _asIntOrNull(m['user_id']),
      currency: _asCleanString(m['currency'])?.toUpperCase(),
      status: _asCleanString(m['status']),
      q: _asCleanString(m['q']),
      brandNotNull: _asBoolOrNull(m['brand_not_null']),
      sectorId: _asIntOrNull(m['sector_id'] ?? m['sector']),
      categoryId: _asIntOrNull(m['category_id'] ?? m['category']),
      productId: _asIntOrNull(m['product_id'] ?? m['product']),
      brandId: _asIntOrNull(m['brand_id'] ?? m['brand']),
    );
  }
}

class TransactionFilterAvailable {
  final List<TransactionFilterUserOption> users;
  final List<TransactionFilterSectorOption> sectors;
  final List<TransactionFilterCategoryOption> categories;
  final List<TransactionFilterProductOption> products;
  final List<TransactionFilterBrandOption> brands;

  const TransactionFilterAvailable({
    required this.users,
    required this.sectors,
    required this.categories,
    required this.products,
    required this.brands,
  });

  bool get hasAnyOptions =>
      users.isNotEmpty ||
      sectors.isNotEmpty ||
      categories.isNotEmpty ||
      products.isNotEmpty ||
      brands.isNotEmpty;

  factory TransactionFilterAvailable.fromJson(Map<String, dynamic> m) {
    return TransactionFilterAvailable(
      users: _asMapList(m['users'])
          .map(TransactionFilterUserOption.fromJson)
          .toList(),
      sectors: _asMapList(m['sectors'])
          .map(TransactionFilterSectorOption.fromJson)
          .toList(),
      categories: _asMapList(m['categories'])
          .map(TransactionFilterCategoryOption.fromJson)
          .toList(),
      products: _asMapList(m['products'])
          .map(TransactionFilterProductOption.fromJson)
          .toList(),
      brands: _asMapList(m['brands'])
          .map(TransactionFilterBrandOption.fromJson)
          .toList(),
    );
  }
}

class TransactionFilterData {
  final TransactionFilterSelected? selected;
  final TransactionFilterAvailable? available;

  const TransactionFilterData({required this.selected, required this.available});

  factory TransactionFilterData.fromJson(Map<String, dynamic> m) {
    final selectedMap = _asMap(m['selected']);
    final availableMap = _asMap(m['available']);
    return TransactionFilterData(
      selected:
          selectedMap.isEmpty ? null : TransactionFilterSelected.fromJson(selectedMap),
      available: availableMap.isEmpty
          ? null
          : TransactionFilterAvailable.fromJson(availableMap),
    );
  }
}

class TxClient {
  final String name;
  final String number;
  const TxClient({required this.name, required this.number});

  factory TxClient.fromJson(Map<String, dynamic> m) {
    return TxClient(
      name: (m['name'] ?? '').toString(),
      number: (m['number'] ?? '').toString(),
    );
  }
}

class TxAmounts {
  final String cost;
  final String dealer;
  final String customer;
  final String dProfit;
  final String aProfit;
  final String costOriginal;
  final String costOriginalCurrency;

  const TxAmounts({
    required this.cost,
    required this.dealer,
    required this.customer,
    required this.dProfit,
    required this.aProfit,
    required this.costOriginal,
    required this.costOriginalCurrency,
  });

  factory TxAmounts.fromJson(Map<String, dynamic> m) {
    String pick(List<String> keys, {required String fallback}) {
      for (final k in keys) {
        if (!m.containsKey(k)) continue;
        final v = m[k];
        if (v == null) continue;
        final s = v.toString();
        if (s.trim().isEmpty) continue;
        return s;
      }
      return fallback;
    }

    return TxAmounts(
      cost: (m['cost'] ?? '0').toString(),
      dealer: (m['dealer'] ?? '0').toString(),
      customer: (m['customer'] ?? '0').toString(),
      dProfit: pick(
        const [
          'dealer_profit',
          'd_profit',
          'dProfit',
          'Dprofit',
          'dprofit',
          'dealerProfit',
          'DealerProfit',
        ],
        fallback: '0',
      ),
      aProfit: pick(
        const [
          'admin_profit',
          'a_profit',
          'aProfit',
          'Aprofit',
          'aprofit',
          'adminProfit',
          'AdminProfit',
          'AProfit',
        ],
        fallback: '0',
      ),
      costOriginal: (m['cost_original'] ?? '0').toString(),
      costOriginalCurrency: (m['cost_original_currency'] ?? '').toString(),
    );
  }
}

class TxContext {
  final int brandId;
  final String brandLabel;
  final String productLabel;
  final String categoryLabel;
  final String sectorLabel;
  final String brandCurrency;

  const TxContext({
    required this.brandId,
    required this.brandLabel,
    required this.productLabel,
    required this.categoryLabel,
    required this.sectorLabel,
    required this.brandCurrency,
  });

  factory TxContext.fromJson(Map<String, dynamic> m) {
    return TxContext(
      brandId: int.tryParse('${m['brand_id'] ?? 0}') ?? 0,
      brandLabel: (m['brand_label'] ?? '').toString(),
      productLabel: (m['product_label'] ?? '').toString(),
      categoryLabel: (m['category_label'] ?? '').toString(),
      sectorLabel: (m['sector_label'] ?? m['sector_name'] ?? '').toString(),
      brandCurrency: (m['brand_currency'] ?? '').toString(),
    );
  }
}

class TxUi {
  final String? title;
  final String? subtitle;
  final String? badge;

  const TxUi({this.title, this.subtitle, this.badge});

  factory TxUi.fromJson(Map<String, dynamic> m) {
    return TxUi(
      title: _asCleanString(m['title']),
      subtitle: _asCleanString(m['subtitle']),
      badge: _asCleanString(m['badge']),
    );
  }
}

class TransactionListItem {
  final int id;
  final DateTime ts;
  final String? username;
  final String currency;
  final int quantity;
  final String status;
  final TxClient client;
  final TxAmounts amounts;
  final TxContext context;
  final Map<String, String>? balance;
  final TxUi? ui;

  const TransactionListItem({
    required this.id,
    required this.ts,
    required this.username,
    required this.currency,
    required this.quantity,
    required this.status,
    required this.client,
    required this.amounts,
    required this.context,
    required this.balance,
    required this.ui,
  });

  static DateTime _parseTs(dynamic v) {
    if (v == null) return DateTime.now();
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return DateTime.now();
    }
  }

  static Map<String, String>? _parseBalance(dynamic v, {String? currencyHint}) {
    if (v == null) return null;

    if (v is Map) {
      final out = <String, String>{};
      for (final e in v.entries) {
        final k = e.key.toString();
        out[k] = e.value?.toString() ?? '';
      }
      return out;
    }

    final s = v.toString().trim();
    if (s.isEmpty) return null;
    final cur = (currencyHint ?? '').toString().trim();
    if (cur.isEmpty) return null;
    return {cur.toUpperCase(): s};
  }

  factory TransactionListItem.fromJson(Map<String, dynamic> m) {
    String? username;
    final u = m['user'];
    if (u is Map) {
      final um = u.cast<String, dynamic>();
      username = um['username']?.toString() ?? um['name']?.toString();
    }
    username ??= m['username']?.toString();
    username = (username?.trim().isEmpty ?? true) ? null : username?.trim();

    final cur = (m['currency'] ?? '').toString();
    final uiMap = _asMap(m['ui']);

    return TransactionListItem(
      id: int.tryParse('${m['id'] ?? 0}') ?? 0,
      ts: _parseTs(m['ts']),
      username: username,
      currency: cur,
      quantity: int.tryParse('${m['quantity'] ?? 1}') ?? 1,
      status: (m['status'] ?? '').toString(),
      client: TxClient.fromJson(_asMap(m['client'])),
      amounts: TxAmounts.fromJson(_asMap(m['amounts'])),
      context: TxContext.fromJson(_asMap(m['context'])),
      balance: _parseBalance(m['balance'], currencyHint: cur),
      ui: uiMap.isEmpty ? null : TxUi.fromJson(uiMap),
    );
  }
}

class TransactionListResponse {
  final TransactionMeta meta;
  final TransactionSummary? summary;
  final List<TransactionListItem> items;
  final TransactionFilterData? filters;

  const TransactionListResponse({
    required this.meta,
    required this.summary,
    required this.items,
    required this.filters,
  });

  factory TransactionListResponse.fromJson(Map<String, dynamic> m) {
    final meta = TransactionMeta.fromJson(_asMap(m['meta']));

    final summaryMap = _asMap(m['summary']);
    final filtersMap = _asMap(m['filters']);

    return TransactionListResponse(
      meta: meta,
      summary: summaryMap.isEmpty ? null : TransactionSummary.fromJson(summaryMap),
      items: _asMapList(m['items'])
          .map(TransactionListItem.fromJson)
          .toList(),
      filters: filtersMap.isEmpty ? null : TransactionFilterData.fromJson(filtersMap),
    );
  }
}

class TxUser {
  final int id;
  final String username;
  const TxUser({required this.id, required this.username});

  factory TxUser.fromJson(Map<String, dynamic> m) {
    return TxUser(
      id: int.tryParse('${m['id'] ?? 0}') ?? 0,
      username: (m['username'] ?? '').toString(),
    );
  }
}

class TransactionDetail {
  final int id;
  final DateTime ts;
  final DateTime created;
  final DateTime modified;
  final TxUser user;
  final String currency;
  final int quantity;
  final String status;
  final TxClient client;
  final TxAmounts amounts;
  final TxContext context;
  final dynamic note;
  final Map<String, String>? balance;

  const TransactionDetail({
    required this.id,
    required this.ts,
    required this.created,
    required this.modified,
    required this.user,
    required this.currency,
    required this.quantity,
    required this.status,
    required this.client,
    required this.amounts,
    required this.context,
    required this.note,
    required this.balance,
  });

  static DateTime _parseTs(dynamic v) {
    if (v == null) return DateTime.now();
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return DateTime.now();
    }
  }

  factory TransactionDetail.fromJson(Map<String, dynamic> m) {
    final cur = (m['currency'] ?? '').toString();
    return TransactionDetail(
      id: int.tryParse('${m['id'] ?? 0}') ?? 0,
      ts: _parseTs(m['ts']),
      created: _parseTs(m['created']),
      modified: _parseTs(m['modified']),
      user: TxUser.fromJson(_asMap(m['user'])),
      currency: cur,
      quantity: int.tryParse('${m['quantity'] ?? 1}') ?? 1,
      status: (m['status'] ?? '').toString(),
      client: TxClient.fromJson(_asMap(m['client'])),
      amounts: TxAmounts.fromJson(_asMap(m['amounts'])),
      context: TxContext.fromJson(_asMap(m['context'])),
      note: m['note'],
      balance: TransactionListItem._parseBalance(m['balance'], currencyHint: cur),
    );
  }
}
