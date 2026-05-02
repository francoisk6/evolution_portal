class UserBrandProfitOption {
  final int id;
  final String label;
  final String? name;
  final String? username;
  final String? fullName;
  final String? code;
  final String? currency;

  const UserBrandProfitOption({
    required this.id,
    required this.label,
    this.name,
    this.username,
    this.fullName,
    this.code,
    this.currency,
  });

  factory UserBrandProfitOption.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as num?)?.toInt() ?? 0;
    final label = (json['label'] ?? json['name'] ?? json['username'] ?? json['code'] ?? id)
        .toString();
    return UserBrandProfitOption(
      id: id,
      label: label,
      name: json['name']?.toString(),
      username: json['username']?.toString(),
      fullName: json['full_name']?.toString(),
      code: json['code']?.toString(),
      currency: json['currency']?.toString(),
    );
  }
}

class UserBrandProfitItem {
  final int id;
  final UserBrandProfitOption? user;
  final UserBrandProfitOption? sector;
  final UserBrandProfitOption? category;
  final UserBrandProfitOption? product;
  final UserBrandProfitOption? productType;
  final UserBrandProfitOption? brand;
  final String profitPercentage;
  final String sellingProfitPercentage;
  final String roundDealerPrice;
  final String defaultSellingPrice;
  final String nativeDealerPrice;
  final String nativeCustomerPrice;
  final bool deactivated;
  final Map<String, String> brandDefaults;

  const UserBrandProfitItem({
    required this.id,
    required this.user,
    required this.sector,
    required this.category,
    required this.product,
    required this.productType,
    required this.brand,
    required this.profitPercentage,
    required this.sellingProfitPercentage,
    required this.roundDealerPrice,
    required this.defaultSellingPrice,
    required this.nativeDealerPrice,
    required this.nativeCustomerPrice,
    required this.deactivated,
    required this.brandDefaults,
  });

  factory UserBrandProfitItem.fromJson(Map<String, dynamic> json) {
    Map<String, String> defaults = const <String, String>{};
    final rawDefaults = json['brand_defaults'];
    if (rawDefaults is Map<String, dynamic>) {
      defaults = rawDefaults.map(
        (key, value) => MapEntry(key, value?.toString() ?? ''),
      );
    } else if (rawDefaults is Map) {
      defaults = rawDefaults.map(
        (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
      );
    }

    UserBrandProfitOption? nested(dynamic raw) {
      if (raw is Map<String, dynamic>) return UserBrandProfitOption.fromJson(raw);
      if (raw is Map) return UserBrandProfitOption.fromJson(raw.cast<String, dynamic>());
      return null;
    }

    bool asBool(dynamic v) {
      if (v is bool) return v;
      final s = v?.toString().trim().toLowerCase();
      return s == 'true' || s == '1' || s == 'yes' || s == 'y';
    }

    return UserBrandProfitItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      user: nested(json['user']),
      sector: nested(json['sector']),
      category: nested(json['category']),
      product: nested(json['product']),
      productType: nested(json['product_type']),
      brand: nested(json['brand']),
      profitPercentage: json['profit_percentage']?.toString() ?? '',
      sellingProfitPercentage: json['selling_profit_percentage']?.toString() ?? '',
      roundDealerPrice: json['round_dealer_price']?.toString() ?? '',
      defaultSellingPrice: json['default_selling_price']?.toString() ?? '',
      nativeDealerPrice: json['native_dealer_price']?.toString() ?? '',
      nativeCustomerPrice: json['native_customer_price']?.toString() ?? '',
      deactivated: asBool(json['deactivated']),
      brandDefaults: defaults,
    );
  }
}

class UserBrandProfitFilterOptionsResponse {
  final bool success;
  final String message;
  final Map<String, dynamic> applied;
  final List<UserBrandProfitOption> groups;
  final List<UserBrandProfitOption> users;
  final List<UserBrandProfitOption> sectors;
  final List<UserBrandProfitOption> categories;
  final List<UserBrandProfitOption> products;
  final List<UserBrandProfitOption> productTypes;
  final List<UserBrandProfitOption> brands;

  const UserBrandProfitFilterOptionsResponse({
    required this.success,
    required this.message,
    required this.applied,
    required this.groups,
    required this.users,
    required this.sectors,
    required this.categories,
    required this.products,
    required this.productTypes,
    required this.brands,
  });

  static List<UserBrandProfitOption> _parseOptions(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => UserBrandProfitOption.fromJson(e.cast<String, dynamic>()))
          .toList();
    }
    return const <UserBrandProfitOption>[];
  }

  factory UserBrandProfitFilterOptionsResponse.fromJson(Map<String, dynamic> json) {
    final applied = json['applied'];
    return UserBrandProfitFilterOptionsResponse(
      success: json['success'] == true,
      message: json['message']?.toString() ?? '',
      applied: applied is Map<String, dynamic>
          ? applied
          : (applied is Map ? applied.cast<String, dynamic>() : const <String, dynamic>{}),
      groups: _parseOptions(json['groups']),
      users: _parseOptions(json['users']),
      sectors: _parseOptions(json['sectors']),
      categories: _parseOptions(json['categories']),
      products: _parseOptions(json['products']),
      productTypes: _parseOptions(json['product_types']),
      brands: _parseOptions(json['brands']),
    );
  }
}

class UserBrandProfitListResponse {
  final bool success;
  final String message;
  final List<UserBrandProfitItem> items;
  final int page;
  final int pageSize;
  final int total;
  final bool hasNext;
  final bool hasPrevious;
  final Map<String, dynamic> applied;

  const UserBrandProfitListResponse({
    required this.success,
    required this.message,
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.hasNext,
    required this.hasPrevious,
    required this.applied,
  });

  factory UserBrandProfitListResponse.fromJson(Map<String, dynamic> json) {
    final itemsRaw = json['items'];
    final meta = json['meta'];
    final applied = json['applied'];

    final items = (itemsRaw is List)
        ? itemsRaw
            .whereType<Map>()
            .map((e) => UserBrandProfitItem.fromJson(e.cast<String, dynamic>()))
            .toList()
        : const <UserBrandProfitItem>[];

    final metaMap = meta is Map<String, dynamic>
        ? meta
        : (meta is Map ? meta.cast<String, dynamic>() : const <String, dynamic>{});

    bool asBool(dynamic v) {
      if (v is bool) return v;
      final s = v?.toString().trim().toLowerCase();
      return s == 'true' || s == '1' || s == 'yes' || s == 'y';
    }

    return UserBrandProfitListResponse(
      success: json['success'] == true,
      message: json['message']?.toString() ?? '',
      items: items,
      page: (metaMap['page'] as num?)?.toInt() ?? 1,
      pageSize: (metaMap['page_size'] as num?)?.toInt() ?? 20,
      total: (metaMap['total'] as num?)?.toInt() ?? items.length,
      hasNext: asBool(metaMap['has_next']),
      hasPrevious: asBool(metaMap['has_previous']),
      applied: applied is Map<String, dynamic>
          ? applied
          : (applied is Map ? applied.cast<String, dynamic>() : const <String, dynamic>{}),
    );
  }
}

class UserBrandProfitBulkUpsertResponse {
  final bool success;
  final String message;
  final Map<String, dynamic> summary;
  final Map<String, dynamic> applied;

  const UserBrandProfitBulkUpsertResponse({
    required this.success,
    required this.message,
    required this.summary,
    required this.applied,
  });

  factory UserBrandProfitBulkUpsertResponse.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'];
    final applied = json['applied'];
    return UserBrandProfitBulkUpsertResponse(
      success: json['success'] == true,
      message: json['message']?.toString() ?? '',
      summary: summary is Map<String, dynamic>
          ? summary
          : (summary is Map ? summary.cast<String, dynamic>() : const <String, dynamic>{}),
      applied: applied is Map<String, dynamic>
          ? applied
          : (applied is Map ? applied.cast<String, dynamic>() : const <String, dynamic>{}),
    );
  }
}
