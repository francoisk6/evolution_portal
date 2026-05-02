class ApiEnvelope {
  final int status;
  final Map<String, dynamic>? body;

  ApiEnvelope({required this.status, required this.body});

  bool get ok => status >= 200 && status < 300;

  String? get error => body?['error']?.toString();
  String? get message => body?['message']?.toString();
  dynamic get data => body?['data'];

  Map<String, dynamic> get dataMap => (data is Map<String, dynamic>)
      ? data as Map<String, dynamic>
      : const <String, dynamic>{};
  List<dynamic> get dataList => (data is List) ? data as List : const [];

  /// token may come as data.token / data.key / data.access
  String? get token {
    final d = data;
    if (d is Map<String, dynamic>) {
      for (final k in const ['token', 'key', 'access']) {
        final v = d[k];
        if (v is String && v.isNotEmpty) return v;
      }
    }
    final t = body?['token'];
    return (t is String && t.isNotEmpty) ? t : null;
  }

  /// avatar: data.profile.avatar OR data.avatar(_url)/profile_image
  String? get avatarUrl {
    final d = dataMap;
    final profile = d['profile'];
    if (profile is Map<String, dynamic>) {
      final v = profile['avatar'] ??
          profile['avatar_url'] ??
          profile['profile_image'];
      if (v is String && v.isNotEmpty) return v;
    }
    final v2 = d['avatar'] ?? d['avatar_url'] ?? d['profile_image'];
    return (v2 is String && v2.isNotEmpty) ? v2 : null;
  }

  /// currency: data.profile.default_currency OR data.default_currency/current_currency
  String? get currentCurrency {
    final d = dataMap;
    final profile = d['profile'];
    if (profile is Map<String, dynamic>) {
      final v = profile['default_currency'];
      if (v is String && v.isNotEmpty) return v;
    }
    final v2 = d['default_currency'] ?? d['current_currency'];
    return v2?.toString();
  }

  /// Best-effort human error text across:
  /// {error}, {message}, {detail}, field errors (Map/List), non_field_errors, etc.
  String? get humanError {
    if (error != null && error!.trim().isNotEmpty) return error;
    final d = body;
    if (d == null) return null;
    final detail = d['detail'];
    if (detail is String && detail.trim().isNotEmpty) return detail;

    // DRF field errors can be like {"email": ["This field is required."], "password": ["..."]}
    final parts = <String>[];
    void addPart(String k, dynamic v) {
      if (v is List) {
        parts.add('$k: ${v.join(", ")}');
      } else if (v is String) {
        parts.add('$k: $v');
      } else if (v != null) {
        parts.add('$k: $v');
      }
    }

    for (final key in const ['errors', 'non_field_errors']) {
      final v = d[key];
      if (v is String && v.trim().isNotEmpty) return v;
      if (v is List && v.isNotEmpty) return v.join(', ');
      if (v is Map<String, dynamic>) {
        v.forEach(addPart);
        if (parts.isNotEmpty) return parts.join(' • ');
      }
    }

    // Fallback: scan any map entries that look like field errors
    d.forEach((k, v) {
      if (k == 'data' || k == 'message' || k == 'error') return;
      if (v is List || v is String) addPart(k, v);
    });
    if (parts.isNotEmpty) return parts.join(' • ');
    return message; // last resort
  }
}
