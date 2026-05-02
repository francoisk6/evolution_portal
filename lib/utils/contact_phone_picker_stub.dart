class ContactPhonePickResult {
  final String fullName;
  final String phoneNumber;

  const ContactPhonePickResult({
    required this.fullName,
    required this.phoneNumber,
  });
}

class ContactPhonePicker {
  static bool get isSupported => false;

  static Future<ContactPhonePickResult?> pickPhoneNumber() async => null;

  static bool looksLikePhoneHint(String? value) {
    final normalized = _normalizeHint(value);
    if (normalized.isEmpty) return false;

    return normalized.contains('phone number') ||
        normalized.contains('phonenumber') ||
        normalized.contains('phone no') ||
        (normalized.contains('phone') && normalized.contains('number')) ||
        normalized.contains('mobile number') ||
        normalized.contains('mobilenumber') ||
        normalized.contains('mobile no') ||
        normalized.contains('mobile phone') ||
        normalized.contains('telephone') ||
        normalized.contains('رقم الهاتف') ||
        normalized.contains('رقم الجوال') ||
        normalized.contains('رقم الموبايل') ||
        normalized.contains('رقم التليفون') ||
        normalized.contains('رقم التلفون') ||
        normalized.contains('هاتف') ||
        normalized.contains('جوال') ||
        normalized.contains('موبايل') ||
        normalized.contains('تليفون') ||
        normalized.contains('تلفون');
  }

  static String normalizePhoneNumber(String value) {
    final input = value.trim();
    if (input.isEmpty) return '';

    final buffer = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      final isDigit = RegExp(r'\d').hasMatch(char);
      if (isDigit) {
        buffer.write(char);
      } else if (char == '+' && buffer.isEmpty) {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  static String _normalizeHint(String? value) {
    return (value ?? '')
        .toLowerCase()
        .replaceAll(RegExp(r'[_\-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
