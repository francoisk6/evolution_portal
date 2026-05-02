class OnlineCvSlaveInfo {
  final String serial;
  final String accountType;
  final String expiryDate;

  const OnlineCvSlaveInfo({
    required this.serial,
    required this.accountType,
    required this.expiryDate,
  });
}

class OnlineCvReceiverInfo {
  final String fullName;
  final String type;
  final String master;
  final String masterAccountType;
  final String masterExpiryDate;

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
        ),
      );
    }

    return OnlineCvReceiverInfo(
      fullName: _pickString(j, ['fullName', 'full_name', 'name']),
      type: _pickString(j, ['type']),
      master: _pickString(j, ['master']),
      masterAccountType: _pickString(j, ['master_account_type']),
      masterExpiryDate: _pickString(j, ['master_expiry_date']),
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
