/// One subscribed option as returned by the (live) receiver-info path.
///
/// Present only in the NEW response shape (backend kill-switch
/// `CV_LIVE_RECEIVER_INFO` on). The OLD / cached shape has no `*_options`
/// arrays, so callers must treat an empty list as "no per-option data".
class CvOptionInfo {
  /// Canonical display name (matches the pricing option labels).
  final String name;

  /// Stable key to match on (e.g. `cv_back_to_basic`, `cv+_family`).
  final String optionName;

  /// This option's own expiry (ISO `YYYY-MM-DD`).
  final String expiryDate;

  /// Mandatory for the brand.
  final bool mandatory;

  /// `expiry_date >= today` (still valid); `false` = lapsed.
  final bool active;

  const CvOptionInfo({
    required this.name,
    required this.optionName,
    required this.expiryDate,
    required this.mandatory,
    required this.active,
  });

  factory CvOptionInfo.fromJson(Map<String, dynamic> j) {
    String pick(String k) {
      final v = j[k];
      if (v == null) return '';
      final s = v.toString().trim();
      return (s.isEmpty || s == 'null') ? '' : s;
    }

    return CvOptionInfo(
      name: pick('name'),
      optionName: pick('option_name'),
      expiryDate: pick('expiry_date'),
      mandatory: j['mandatory'] == true,
      active: j['active'] == true,
    );
  }

  /// Defensive parse: `value` must be a `List` of maps; anything else ⇒ `[]`.
  static List<CvOptionInfo> parseList(dynamic value) {
    if (value is! List) return const [];
    final out = <CvOptionInfo>[];
    for (final e in value) {
      if (e is Map) {
        out.add(CvOptionInfo.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    return out;
  }
}

class OnlineCvSlaveInfo {
  final String serial;
  final String accountType;
  final String expiryDate;

  /// Per-option expiry for this slave (NEW format only; OLD ⇒ empty).
  final List<CvOptionInfo> options;

  const OnlineCvSlaveInfo({
    required this.serial,
    required this.accountType,
    required this.expiryDate,
    this.options = const [],
  });
}

class OnlineCvReceiverInfo {
  final String fullName;
  final String type;
  final String master;
  final String masterAccountType;
  final String masterExpiryDate;

  /// Per-option expiry for the master (NEW format only; OLD ⇒ empty).
  final List<CvOptionInfo> masterOptions;

  /// Parsed slave blocks (slave_1..slave_N).
  /// Only slaves with a non-empty serial are included.
  final List<OnlineCvSlaveInfo> slaves;

  const OnlineCvReceiverInfo({
    required this.fullName,
    required this.type,
    required this.master,
    required this.masterAccountType,
    required this.masterExpiryDate,
    required this.slaves,
    this.masterOptions = const [],
  });

  static String _pickString(Map<String, dynamic> j, List<String> keys) {
    for (final k in keys) {
      final v = j[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty && s != 'null') return s;
    }
    return '';
  }

  factory OnlineCvReceiverInfo.fromJson(Map<String, dynamic> j) {
    final slaves = <OnlineCvSlaveInfo>[];

    // Defensive parse: support up to 10 slaves (backend currently uses <= 3).
    for (int i = 1; i <= 10; i++) {
      final serial = _pickString(j, ['slave_$i']);
      if (serial.isEmpty) continue;
      final accountType = _pickString(j, ['slave_${i}_account_type']);
      final expiryDate = _pickString(j, ['slave_${i}_expiry_date']);
      slaves.add(
        OnlineCvSlaveInfo(
          serial: serial,
          accountType: accountType,
          expiryDate: expiryDate,
          options: CvOptionInfo.parseList(j['slave_${i}_options']),
        ),
      );
    }

    return OnlineCvReceiverInfo(
      fullName: _pickString(j, ['fullName', 'full_name', 'name']),
      type: _pickString(j, ['type']),
      master: _pickString(j, ['master']),
      masterAccountType: _pickString(j, ['master_account_type']),
      masterExpiryDate: _pickString(j, ['master_expiry_date']),
      masterOptions: CvOptionInfo.parseList(j['master_options']),
      slaves: slaves,
    );
  }
}

class OnlineCvReceiverInfoResponse {
  final bool success;
  final String message;
  final String? error;
  final OnlineCvReceiverInfo? data;

  const OnlineCvReceiverInfoResponse({
    required this.success,
    required this.message,
    required this.error,
    required this.data,
  });

  factory OnlineCvReceiverInfoResponse.fromJson(Map<String, dynamic> j) {
    final d = j['data'];
    final err = (j['error'] ?? '').toString().trim();
    return OnlineCvReceiverInfoResponse(
      success: j['success'] == true,
      message: (j['message'] ?? '').toString(),
      error: err.isEmpty ? null : err,
      data: d is Map<String, dynamic> ? OnlineCvReceiverInfo.fromJson(d) : null,
    );
  }
}
