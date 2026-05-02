class OnlineCustomerInfoResponse {
  final bool success;
  final String message;
  final String? error;
  final Map<String, dynamic>? data;

  /// Brand IDs allowed for this account.
  ///
  /// - null => don't filter (show all)
  /// - []   => no brands allowed
  /// - [..] => restrict to these brand IDs
  final List<int>? availableBrands;

  const OnlineCustomerInfoResponse({
    required this.success,
    required this.message,
    required this.error,
    required this.data,
    required this.availableBrands,
  });

  factory OnlineCustomerInfoResponse.fromJson(Map<String, dynamic> j) {
    final raw = j['available_brands'];
    List<int>? parsed;

    if (raw == null) {
      parsed = null;
    } else if (raw is List) {
      parsed = raw
          .map((e) => e is int ? e : int.tryParse('$e'))
          .whereType<int>()
          .toList(growable: false);
    } else {
      // unexpected type => treat as "no filter"
      parsed = null;
    }

    final d = j['data'];
    return OnlineCustomerInfoResponse(
      success: j['success'] == true,
      message: (j['message'] ?? '').toString(),
      error: (j['error'] ?? '').toString().isEmpty ? null : (j['error'] ?? '').toString(),
      data: d is Map<String, dynamic> ? d : null,
      availableBrands: parsed,
    );
  }
}
