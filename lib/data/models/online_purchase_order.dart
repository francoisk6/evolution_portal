class OnlinePurchaseBrand {
  final int id;
  final String name;
  final String cleanName;
  final String nameAlt;
  final String code;
  final String sector;
  final String product;
  final String productType;
  final String brandCurrency;
  final bool byEmail;
  final bool prePaid;

  const OnlinePurchaseBrand({
    required this.id,
    required this.name,
    required this.cleanName,
    required this.nameAlt,
    required this.code,
    required this.sector,
    required this.product,
    required this.productType,
    required this.brandCurrency,
    required this.byEmail,
    required this.prePaid,
  });

  factory OnlinePurchaseBrand.fromJson(Map<String, dynamic> j) {
    return OnlinePurchaseBrand(
      id: j['id'] is int ? j['id'] as int : int.tryParse('${j['id']}') ?? 0,
      name: (j['name'] ?? '').toString(),
      cleanName: (j['clean_name'] ?? '').toString(),
      nameAlt: (j['name_alt'] ?? '').toString(),
      code: (j['code'] ?? '').toString(),
      sector: (j['sector'] ?? '').toString(),
      product: (j['product'] ?? '').toString(),
      productType: (j['product_type'] ?? '').toString(),
      brandCurrency: (j['brand_currency'] ?? '').toString(),
      byEmail: j['by_email'] == true,
      prePaid: j['pre_paid'] == true,
    );
  }
}

class OnlinePurchaseTotals {
  final String totalNativeCost;
  final String totalNativeCostOriginalCurrency;
  final String totalDealer;
  final String totalCustomer;

  const OnlinePurchaseTotals({
    required this.totalNativeCost,
    required this.totalNativeCostOriginalCurrency,
    required this.totalDealer,
    required this.totalCustomer,
  });

  factory OnlinePurchaseTotals.fromJson(Map<String, dynamic> j) {
    return OnlinePurchaseTotals(
      totalNativeCost: (j['total_native_cost'] ?? '').toString(),
      totalNativeCostOriginalCurrency:
          (j['total_native_cost_original_currency'] ?? '').toString(),
      totalDealer: (j['total_dealer'] ?? '').toString(),
      totalCustomer: (j['total_customer'] ?? '').toString(),
    );
  }
}

class OnlinePurchaseOrderData {
  final String currency;
  final String balance;
  final OnlinePurchaseBrand brand;

  // Pricing percentages returned by the API (optional)
  // - profit_percentage: dealer profit percentage
  // - selling_profit_percentage: customer selling profit percentage
  final double profitPercentage;
  final double sellingProfitPercentage;

  final int quantity;
  final int quantityMin;
  final int quantityMax;
  final bool quantityValuesIsList;
  final List<String> quantityValues;
  final bool disableQuantity;

  final List<String> params;
  final Map<String, dynamic> paramsDefaults;

  final Map<String, dynamic> criteriaInfo;
  final OnlinePurchaseTotals totals;

  final Map<String, dynamic> cvNoteJson;

  const OnlinePurchaseOrderData({
    required this.currency,
    required this.balance,
    required this.brand,
    required this.profitPercentage,
    required this.sellingProfitPercentage,
    required this.quantity,
    required this.quantityMin,
    required this.quantityMax,
    required this.quantityValuesIsList,
    required this.quantityValues,
    required this.disableQuantity,
    required this.params,
    required this.paramsDefaults,
    required this.criteriaInfo,
    required this.totals,
    required this.cvNoteJson,
  });

  static int _asInt(dynamic v) =>
      v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;

  static double _asDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().trim()) ?? 0;
  }

  static bool _asBool(dynamic v) =>
      v == true || v?.toString().toLowerCase() == 'true';

  factory OnlinePurchaseOrderData.fromJson(Map<String, dynamic> j) {
    final brandRaw = j['brand'];
    final totalsRaw = j['totals'];

    return OnlinePurchaseOrderData(
      currency: (j['currency'] ?? '').toString(),
      balance: (j['balance'] ?? '').toString(),
      brand: (brandRaw is Map<String, dynamic>)
          ? OnlinePurchaseBrand.fromJson(brandRaw)
          : OnlinePurchaseBrand.fromJson(const <String, dynamic>{}),
      profitPercentage: _asDouble(j['profit_percentage']),
      sellingProfitPercentage: _asDouble(j['selling_profit_percentage']),
      quantity: _asInt(j['quantity']),
      quantityMin: _asInt(j['quantity_min']),
      quantityMax: _asInt(j['quantity_max']),
      quantityValuesIsList: _asBool(j['quantity_values_is_list']),
      quantityValues: (j['quantity_values'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      disableQuantity: _asBool(j['disable_quantity']),
      params: (j['params'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      paramsDefaults: (j['params_defaults'] is Map)
          ? (j['params_defaults'] as Map).cast<String, dynamic>()
          : const <String, dynamic>{},
      criteriaInfo: (j['criteria_info'] is Map)
          ? (j['criteria_info'] as Map).cast<String, dynamic>()
          : const <String, dynamic>{},
      totals: (totalsRaw is Map<String, dynamic>)
          ? OnlinePurchaseTotals.fromJson(totalsRaw)
          : OnlinePurchaseTotals.fromJson(const <String, dynamic>{}),
      cvNoteJson: (j['cv_note_json'] is Map)
          ? (j['cv_note_json'] as Map).cast<String, dynamic>()
          : const <String, dynamic>{},
    );
  }
}

class OnlinePurchaseOrderResponse {
  final bool success;
  final String message;
  final String? error;
  final OnlinePurchaseOrderData? data;

  const OnlinePurchaseOrderResponse({
    required this.success,
    required this.message,
    required this.error,
    required this.data,
  });

  factory OnlinePurchaseOrderResponse.fromJson(Map<String, dynamic> j) {
    final d = j['data'];
    final err = (j['error'] ?? '').toString().trim();
    return OnlinePurchaseOrderResponse(
      success: j['success'] == true,
      message: (j['message'] ?? '').toString(),
      error: err.isEmpty ? null : err,
      data: d is Map<String, dynamic> ? OnlinePurchaseOrderData.fromJson(d) : null,
    );
  }
}

class OnlinePurchaseTransaction {
  final int id;
  final String status;
  final String clientnumber;
  final String currency;
  final String dealerPrice;
  final String customerPrice;
  final Map<String, dynamic> note;

  const OnlinePurchaseTransaction({
    required this.id,
    required this.status,
    required this.clientnumber,
    required this.currency,
    required this.dealerPrice,
    required this.customerPrice,
    required this.note,
  });

  factory OnlinePurchaseTransaction.fromJson(Map<String, dynamic> j) {
    return OnlinePurchaseTransaction(
      id: j['id'] is int ? j['id'] as int : int.tryParse('${j['id']}') ?? 0,
      status: (j['status'] ?? '').toString(),
      clientnumber: (j['clientnumber'] ?? '').toString(),
      currency: (j['currency'] ?? '').toString(),
      dealerPrice: (j['dealer_price'] ?? '').toString(),
      customerPrice: (j['customer_price'] ?? '').toString(),
      note: (j['note'] is Map)
          ? (j['note'] as Map).cast<String, dynamic>()
          : const <String, dynamic>{},
    );
  }
}

class OnlinePurchasePostResponse {
  final bool success;
  final String message;
  final String? error;
  final OnlinePurchaseTransaction? transaction;

  const OnlinePurchasePostResponse({
    required this.success,
    required this.message,
    required this.error,
    required this.transaction,
  });

  factory OnlinePurchasePostResponse.fromJson(Map<String, dynamic> j) {
    final t = j['transaction'];
    final err = (j['error'] ?? '').toString().trim();
    return OnlinePurchasePostResponse(
      success: j['success'] == true,
      message: (j['message'] ?? '').toString(),
      error: err.isEmpty ? null : err,
      transaction: t is Map<String, dynamic> ? OnlinePurchaseTransaction.fromJson(t) : null,
    );
  }
}
