// Models for GET /api/online/prepaid/stock-by-brand/
//
// Each result row carries full sector→category→product→brand context so the
// client can drive cascading filters from a single payload.

class PrepaidStockRef {
  final int id;
  final String name;
  final String label;

  const PrepaidStockRef({
    required this.id,
    required this.name,
    required this.label,
  });

  factory PrepaidStockRef.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as num?)?.toInt() ?? 0;
    final name = json['name']?.toString() ?? '';
    final label = (json['label'] ?? json['name'] ?? id).toString();
    return PrepaidStockRef(id: id, name: name, label: label);
  }
}

class PrepaidStockRow {
  final PrepaidStockRef? brand;
  final PrepaidStockRef? product;
  final PrepaidStockRef? category;
  final PrepaidStockRef? sector;
  final int quantity;

  const PrepaidStockRow({
    required this.brand,
    required this.product,
    required this.category,
    required this.sector,
    required this.quantity,
  });

  factory PrepaidStockRow.fromJson(Map<String, dynamic> json) {
    PrepaidStockRef? nested(dynamic raw) {
      if (raw is Map<String, dynamic>) return PrepaidStockRef.fromJson(raw);
      if (raw is Map) return PrepaidStockRef.fromJson(raw.cast<String, dynamic>());
      return null;
    }

    return PrepaidStockRow(
      brand: nested(json['brand']),
      product: nested(json['product']),
      category: nested(json['category']),
      sector: nested(json['sector']),
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
    );
  }
}

class PrepaidStockResponse {
  final bool success;
  final String message;
  final Map<String, dynamic> applied;
  final int brandCount;
  final int totalQuantity;
  final List<PrepaidStockRow> results;

  const PrepaidStockResponse({
    required this.success,
    required this.message,
    required this.applied,
    required this.brandCount,
    required this.totalQuantity,
    required this.results,
  });

  factory PrepaidStockResponse.fromJson(Map<String, dynamic> json) {
    final resultsRaw = json['results'];
    final applied = json['applied'];

    final results = (resultsRaw is List)
        ? resultsRaw
            .whereType<Map>()
            .map((e) => PrepaidStockRow.fromJson(e.cast<String, dynamic>()))
            .toList()
        : const <PrepaidStockRow>[];

    return PrepaidStockResponse(
      success: json['success'] == true,
      message: json['message']?.toString() ?? '',
      applied: applied is Map<String, dynamic>
          ? applied
          : (applied is Map
              ? applied.cast<String, dynamic>()
              : const <String, dynamic>{}),
      brandCount: (json['brand_count'] as num?)?.toInt() ?? results.length,
      totalQuantity: (json['total_quantity'] as num?)?.toInt() ?? 0,
      results: results,
    );
  }
}
