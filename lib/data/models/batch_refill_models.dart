class BatchBrand {
  final int id;
  final String code;
  final String name;
  final String? alt;
  final String product;
  final int productId;
  final String currency;
  final int currencyId;
  final String dealerPrice;
  final String customerPrice;
  final bool active;
  final bool available;

  const BatchBrand({
    required this.id,
    required this.code,
    required this.name,
    this.alt,
    required this.product,
    required this.productId,
    required this.currency,
    required this.currencyId,
    required this.dealerPrice,
    required this.customerPrice,
    required this.active,
    required this.available,
  });

  factory BatchBrand.fromJson(Map<String, dynamic> j) => BatchBrand(
        id: (j['id'] as num?)?.toInt() ?? 0,
        code: j['code']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        alt: j['alt']?.toString(),
        product: j['product']?.toString() ?? '',
        productId: (j['product_id'] as num?)?.toInt() ?? 0,
        currency: j['currency']?.toString() ?? '',
        currencyId: (j['currency_id'] as num?)?.toInt() ?? 0,
        dealerPrice: j['dealer_price']?.toString() ?? '0',
        customerPrice: j['customer_price']?.toString() ?? '0',
        active: j['active'] as bool? ?? true,
        available: j['available'] as bool? ?? true,
      );

  String get searchLabel => '$code – $name ($product)';
}

class BatchBalance {
  final String currency;
  final int currencyId;
  final String balance;

  const BatchBalance({
    required this.currency,
    required this.currencyId,
    required this.balance,
  });

  factory BatchBalance.fromJson(Map<String, dynamic> j) => BatchBalance(
        currency: j['currency']?.toString() ?? '',
        currencyId: (j['currency_id'] as num?)?.toInt() ?? 0,
        balance: j['balance']?.toString() ?? '0',
      );
}

class BatchSheet {
  final int id;
  final String name;
  final bool locked;
  final String created;
  final String modified;
  final int recordCount;

  const BatchSheet({
    required this.id,
    required this.name,
    required this.locked,
    required this.created,
    required this.modified,
    required this.recordCount,
  });

  factory BatchSheet.fromJson(Map<String, dynamic> j) => BatchSheet(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: j['name']?.toString() ?? '',
        locked: j['locked'] as bool? ?? false,
        created: j['created']?.toString() ?? '',
        modified: j['modified']?.toString() ?? '',
        recordCount: (j['record_count'] as num?)?.toInt() ?? 0,
      );
}

class BatchRecord {
  final int id;
  final int sheetId;
  final String clientname;
  final String clientnumber;
  final String clientDsl;
  final String code;
  final String clientActive;
  final String note;
  final int? brandId;
  final String brandCode;
  final String brandName;
  final String productName;
  final String currency;
  final String costPrice;
  final String dealerPrice;
  final String customerPrice;
  final String? refillDate;
  final String created;
  final String modified;

  const BatchRecord({
    required this.id,
    required this.sheetId,
    required this.clientname,
    required this.clientnumber,
    required this.clientDsl,
    required this.code,
    required this.clientActive,
    required this.note,
    this.brandId,
    required this.brandCode,
    required this.brandName,
    required this.productName,
    required this.currency,
    required this.costPrice,
    required this.dealerPrice,
    required this.customerPrice,
    this.refillDate,
    required this.created,
    required this.modified,
  });

  factory BatchRecord.fromJson(Map<String, dynamic> j) => BatchRecord(
        id: (j['id'] as num?)?.toInt() ?? 0,
        sheetId: (j['sheet_id'] as num?)?.toInt() ?? 0,
        clientname: j['clientname']?.toString() ?? '',
        clientnumber: j['clientnumber']?.toString() ?? '',
        clientDsl: j['client_dsl']?.toString() ?? '',
        code: j['code']?.toString() ?? '',
        clientActive: j['client_active']?.toString() ?? 'Inactive',
        note: j['note']?.toString() ?? '',
        brandId: (j['brand_id'] as num?)?.toInt(),
        brandCode: j['brand_code']?.toString() ?? '',
        brandName: j['brand_name']?.toString() ?? '',
        productName: j['product_name']?.toString() ?? '',
        currency: j['currency']?.toString() ?? '',
        costPrice: j['cost_price']?.toString() ?? '',
        dealerPrice: j['dealer_price']?.toString() ?? '',
        customerPrice: j['customer_price']?.toString() ?? '',
        refillDate: j['refill_date']?.toString(),
        created: j['created']?.toString() ?? '',
        modified: j['modified']?.toString() ?? '',
      );

  BatchRecord copyWith({
    String? clientname,
    String? clientnumber,
    String? clientDsl,
    String? code,
    String? clientActive,
    String? note,
    int? brandId,
    bool clearBrandId = false,
    String? brandCode,
    String? brandName,
    String? productName,
    String? currency,
    String? costPrice,
    String? dealerPrice,
    String? customerPrice,
    String? refillDate,
    bool clearRefillDate = false,
    String? modified,
  }) =>
      BatchRecord(
        id: id,
        sheetId: sheetId,
        clientname: clientname ?? this.clientname,
        clientnumber: clientnumber ?? this.clientnumber,
        clientDsl: clientDsl ?? this.clientDsl,
        code: code ?? this.code,
        clientActive: clientActive ?? this.clientActive,
        note: note ?? this.note,
        brandId: clearBrandId ? null : (brandId ?? this.brandId),
        brandCode: brandCode ?? this.brandCode,
        brandName: brandName ?? this.brandName,
        productName: productName ?? this.productName,
        currency: currency ?? this.currency,
        costPrice: costPrice ?? this.costPrice,
        dealerPrice: dealerPrice ?? this.dealerPrice,
        customerPrice: customerPrice ?? this.customerPrice,
        refillDate:
            clearRefillDate ? null : (refillDate ?? this.refillDate),
        created: created,
        modified: modified ?? this.modified,
      );

  Map<String, dynamic> toApiJson() => {
        'clientname': clientname,
        'clientnumber': clientnumber,
        'client_dsl': clientDsl,
        'code': code,
        'client_active': clientActive,
        'note': note,
        if (brandId != null) 'brand_id': brandId,
        'brand_code': brandCode,
        'brand_name': brandName,
        'product_name': productName,
        'dealer_price': dealerPrice,
        'customer_price': customerPrice,
      };
}

class BatchCheckRecordResult {
  final int recordId;
  final String status;
  final String note;

  const BatchCheckRecordResult({
    required this.recordId,
    required this.status,
    required this.note,
  });

  factory BatchCheckRecordResult.fromJson(Map<String, dynamic> j) =>
      BatchCheckRecordResult(
        recordId: (j['record_id'] as num?)?.toInt() ?? 0,
        status: j['status']?.toString() ?? '',
        note: j['note']?.toString() ?? '',
      );
}

class BatchCheckResult {
  final int checked;
  final int valid;
  final int invalid;
  final List<BatchCheckRecordResult> results;
  final List<BatchRecord> records;

  const BatchCheckResult({
    required this.checked,
    required this.valid,
    required this.invalid,
    required this.results,
    this.records = const [],
  });

  factory BatchCheckResult.fromJson(Map<String, dynamic> j) =>
      BatchCheckResult(
        checked: (j['checked'] as num?)?.toInt() ?? 0,
        valid: (j['valid'] as num?)?.toInt() ?? 0,
        invalid: (j['invalid'] as num?)?.toInt() ?? 0,
        results: (j['results'] as List? ?? [])
            .map((e) => BatchCheckRecordResult.fromJson(
                e as Map<String, dynamic>))
            .toList(),
        records: (j['records'] as List? ?? [])
            .map((e) => BatchRecord.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class BatchRefillRecordResult {
  final int recordId;
  final String status;
  final String note;

  const BatchRefillRecordResult({
    required this.recordId,
    required this.status,
    required this.note,
  });

  factory BatchRefillRecordResult.fromJson(Map<String, dynamic> j) =>
      BatchRefillRecordResult(
        recordId: (j['record_id'] as num?)?.toInt() ?? 0,
        status: j['status']?.toString() ?? '',
        note: j['note']?.toString() ?? '',
      );
}

class BatchRefillResult {
  final int processed;
  final int success;
  final int failed;
  final List<BatchRefillRecordResult> results;
  final List<BatchRecord> records;

  const BatchRefillResult({
    required this.processed,
    required this.success,
    required this.failed,
    required this.results,
    this.records = const [],
  });

  factory BatchRefillResult.fromJson(Map<String, dynamic> j) =>
      BatchRefillResult(
        processed: (j['processed'] as num?)?.toInt() ?? 0,
        success: (j['success'] as num?)?.toInt() ?? 0,
        failed: (j['failed'] as num?)?.toInt() ?? 0,
        results: (j['results'] as List? ?? [])
            .map((e) => BatchRefillRecordResult.fromJson(
                e as Map<String, dynamic>))
            .toList(),
        records: (j['records'] as List? ?? [])
            .map((e) => BatchRecord.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
