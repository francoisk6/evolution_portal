class OnlineGroupHead {
  final int id;
  final String name;
  final String alt;

  OnlineGroupHead({required this.id, required this.name, required this.alt});

  factory OnlineGroupHead.fromJson(Map<String, dynamic> j) => OnlineGroupHead(
        id: j['id'] is int ? j['id'] as int : int.tryParse('${j['id']}') ?? 0,
        name: (j['name'] ?? '').toString(),
        alt: (j['alt'] ?? '').toString(),
      );
}

class OnlineGroupDetail {
  final int id;
  final String name;
  final String alt;
  final String avatar;

  OnlineGroupDetail({
    required this.id,
    required this.name,
    required this.alt,
    required this.avatar,
  });

  factory OnlineGroupDetail.fromJson(Map<String, dynamic> j) =>
      OnlineGroupDetail(
        id: j['id'] is int ? j['id'] as int : int.tryParse('${j['id']}') ?? 0,
        name: (j['name'] ?? '').toString(),
        alt: (j['alt'] ?? '').toString(),
        avatar: (j['avatar'] ?? '').toString(),
      );
}

class OnlineSubdetailTab {
  final int id;
  final String name;
  final String alt;
  final String avatar;
  final int sortNumber;
  final bool hasInfo;
  final List<dynamic> params;
  final bool isActive;
  final int brandCount;

  OnlineSubdetailTab({
    required this.id,
    required this.name,
    required this.alt,
    required this.avatar,
    required this.sortNumber,
    required this.hasInfo,
    required this.params,
    required this.isActive,
    required this.brandCount,
  });

  factory OnlineSubdetailTab.fromJson(Map<String, dynamic> j) =>
      OnlineSubdetailTab(
        id: j['id'] is int ? j['id'] as int : int.tryParse('${j['id']}') ?? 0,
        name: (j['name'] ?? '').toString(),
        alt: (j['alt'] ?? '').toString(),
        avatar: (j['avatar'] ?? '').toString(),
        sortNumber: j['sort_number'] is int
            ? j['sort_number'] as int
            : int.tryParse('${j['sort_number']}') ?? 9999,
        hasInfo: j['has_info'] == true,
        params: (j['params'] as List? ?? const []).toList(),
        isActive: j['is_active'] == true,
        brandCount: j['brand_count'] is int
            ? j['brand_count'] as int
            : int.tryParse('${j['brand_count']}') ?? 0,
      );
}

class OnlineCardTheme {
  final String themeType; // e.g. "triple"
  final int angleDeg; // CSS-style angle: 0=up, 90=right
  final String colorFrom; // "#RRGGBB" or "#AARRGGBB"
  final String colorMid;  // optional
  final String colorTo;   // "#RRGGBB" or "#AARRGGBB"
  final String fontColor; // "#RRGGBB" or "#AARRGGBB"

  const OnlineCardTheme({
    required this.themeType,
    required this.angleDeg,
    required this.colorFrom,
    required this.colorMid,
    required this.colorTo,
    required this.fontColor,
  });

  factory OnlineCardTheme.fromJson(Map<String, dynamic> j) => OnlineCardTheme(
        themeType: (j['theme_type'] ?? '').toString(),
        angleDeg: j['angle_deg'] is int
            ? j['angle_deg'] as int
            : int.tryParse('${j['angle_deg']}') ?? 135,
        colorFrom: (j['color_from'] ?? '').toString(),
        colorMid: (j['color_mid'] ?? '').toString(),
        colorTo: (j['color_to'] ?? '').toString(),
        fontColor: (j['font_color'] ?? '').toString(),
      );
}

class OnlineBrand {
  final int id;
  final String name;
  final String alt;

  // New fields (aligned with Django API)
  final String displayTitle;
  final String description;
  final String details;

  // Back-compat (older payloads might still send display_name)
  final String displayName;

  // Media
  final String avatar; // product/card image (may be empty)
  final String logo2; // back-compat: filename or path
  final String logo2Url; // preferred: full media URL or /media path

  // Pricing / ordering
  final int productId;
  final String productName;
  final String unit;
  final String unitValue;
  final int quantityValuesMin;
  final int quantityValuesMax;
  final String? quantityValues;
  final String currency;

  // Keep as String (API returns strings)
  final String customerPrice;
  final String customerPriceCurrency;
  final String nativeCostPrice;

  final bool isPrepaid;
  final int sortNumber;

  final OnlineCardTheme? cardTheme;

  const OnlineBrand({
    required this.id,
    required this.name,
    required this.alt,
    required this.displayTitle,
    required this.description,
    required this.details,
    required this.displayName,
    required this.avatar,
    required this.logo2,
    required this.logo2Url,
    required this.productId,
    required this.productName,
    required this.unit,
    required this.unitValue,
    required this.quantityValuesMin,
    required this.quantityValuesMax,
    required this.quantityValues,
    required this.currency,
    required this.customerPrice,
    required this.customerPriceCurrency,
    required this.nativeCostPrice,
    required this.isPrepaid,
    required this.sortNumber,
    required this.cardTheme,
  });

  factory OnlineBrand.fromJson(Map<String, dynamic> j) {
    final displayTitle = (j['display_title'] ?? '').toString();
    final displayName = (j['display_name'] ?? '').toString();

    final ctRaw = j['card_theme'];
    OnlineCardTheme? theme;
    if (ctRaw is Map) {
      theme = OnlineCardTheme.fromJson(ctRaw.cast<String, dynamic>());
    }

    return OnlineBrand(
      id: j['id'] is int ? j['id'] as int : int.tryParse('${j['id']}') ?? 0,
      name: (j['name'] ?? '').toString(),
      alt: (j['alt'] ?? '').toString(),
      displayTitle: displayTitle,
      description: (j['description'] ?? '').toString(),
      details: (j['details'] ?? '').toString(),
      displayName: displayName,
      avatar: (j['avatar'] ?? '').toString(),
      logo2: (j['logo_2'] ?? '').toString(),
      logo2Url: (j['logo_2_url'] ?? '').toString(),
      productId: j['product_id'] is int
          ? j['product_id'] as int
          : int.tryParse('${j['product_id']}') ?? 0,
      productName: (j['product_name'] ?? '').toString(),
      unit: (j['unit'] ?? '').toString(),
      unitValue: (j['unit_value'] ?? '').toString(),
      quantityValuesMin: j['quantity_values_min'] is int
          ? j['quantity_values_min'] as int
          : int.tryParse('${j['quantity_values_min']}') ?? 1,
      quantityValuesMax: j['quantity_values_max'] is int
          ? j['quantity_values_max'] as int
          : int.tryParse('${j['quantity_values_max']}') ?? 1,
      quantityValues: j['quantity_values']?.toString(),
      currency: (j['currency'] ?? '').toString(),
      customerPrice: (j['customer_price'] ?? '').toString(),
      customerPriceCurrency: (j['customer_price_currency'] ?? '').toString(),
      nativeCostPrice: (j['native_cost_price'] ?? '').toString(),
      isPrepaid: j['is_prepaid'] == true,
      sortNumber: j['sort_number'] is int
          ? j['sort_number'] as int
          : int.tryParse('${j['sort_number']}') ?? 9999,
      cardTheme: theme,
    );
  }
}

class OnlineBrandsActiveBlock {
  final int subdetailId;
  final List<OnlineBrand> brands;
  final List<dynamic> cvPricing;
  final int maxSlaves;
  final String slaveCustomerPriceDay;

  OnlineBrandsActiveBlock({
    required this.subdetailId,
    required this.brands,
    required this.cvPricing,
    required this.maxSlaves,
    required this.slaveCustomerPriceDay,
  });

  factory OnlineBrandsActiveBlock.fromJson(Map<String, dynamic> j) =>
      OnlineBrandsActiveBlock(
        subdetailId: j['subdetail_id'] is int
            ? j['subdetail_id'] as int
            : int.tryParse('${j['subdetail_id']}') ?? 0,
        brands: (j['brands'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(OnlineBrand.fromJson)
            .toList(),
        cvPricing: (j['cv_pricing'] as List? ?? const []).toList(),
        maxSlaves: j['max_slaves'] is int
            ? j['max_slaves'] as int
            : int.tryParse('${j['max_slaves']}') ?? 0,
        slaveCustomerPriceDay:
            (j['slave_customer_price_day'] ?? '0').toString(),
      );
}

class OnlineBrandsPayload {
  final DateTime? asOf;
  final String currency;
  final OnlineGroupHead groupHead;
  final OnlineGroupDetail groupDetail;
  final List<OnlineSubdetailTab> tabs;
  final int activeSubdetailId;
  final OnlineBrandsActiveBlock active;

  OnlineBrandsPayload({
    required this.asOf,
    required this.currency,
    required this.groupHead,
    required this.groupDetail,
    required this.tabs,
    required this.activeSubdetailId,
    required this.active,
  });

  factory OnlineBrandsPayload.fromJson(Map<String, dynamic> j) =>
      OnlineBrandsPayload(
        asOf: j['as_of'] == null ? null : DateTime.tryParse('${j['as_of']}'),
        currency: (j['currency'] ?? '').toString(),
        groupHead: OnlineGroupHead.fromJson(
            (j['group_head'] as Map<String, dynamic>? ?? const {})),
        groupDetail: OnlineGroupDetail.fromJson(
            (j['group_detail'] as Map<String, dynamic>? ?? const {})),
        tabs: (j['tabs'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(OnlineSubdetailTab.fromJson)
            .toList(),
        activeSubdetailId: j['active_subdetail_id'] is int
            ? j['active_subdetail_id'] as int
            : int.tryParse('${j['active_subdetail_id']}') ?? 0,
        active: OnlineBrandsActiveBlock.fromJson(
            (j['active'] as Map<String, dynamic>? ?? const {})),
      );
}
