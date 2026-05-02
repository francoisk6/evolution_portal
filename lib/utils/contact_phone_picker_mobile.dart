import 'package:flutter/foundation.dart';
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';

class ContactPhonePickResult {
  final String fullName;
  final String phoneNumber;

  const ContactPhonePickResult({
    required this.fullName,
    required this.phoneNumber,
  });
}

class ContactPhonePicker {
  static final FlutterNativeContactPicker _picker = FlutterNativeContactPicker();

  static bool get isSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  static Future<ContactPhonePickResult?> pickPhoneNumber() async {
    if (!isSupported) return null;

    final contact = await _picker.selectPhoneNumber();
    if (contact == null) return null;

    final selected = contact.selectedPhoneNumber;
    final fallback = contact.phoneNumbers?.isNotEmpty == true
        ? contact.phoneNumbers!.first
        : '';
    final rawPhone = (selected?.trim().isNotEmpty == true ? selected : fallback)
            ?.trim() ??
        '';
    final phone = normalizePhoneNumber(rawPhone);
    if (phone.isEmpty) return null;

    return ContactPhonePickResult(
      fullName: contact.fullName?.trim() ?? '',
      phoneNumber: phone,
    );
  }

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
