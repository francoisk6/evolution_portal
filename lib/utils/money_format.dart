import 'package:intl/intl.dart';

/// Centralized currency formatting rules for Evolution Portal.
///
/// Requirements:
/// - LBP: round UP to nearest 250, no decimals, thousands separators.
/// - USD: round UP to 0.01, 2 decimals, thousands separators.
///
/// NOTE: Unit values in brand cards are intentionally NOT formatted via this.
class MoneyFormat {
  MoneyFormat._();

  static final NumberFormat _lbp = NumberFormat('#,##0', 'en_US');
  static final NumberFormat _usd = NumberFormat('#,##0.00', 'en_US');
  static final NumberFormat _generic = NumberFormat('#,##0.##', 'en_US');

  /// Parse numeric strings that may contain commas.
  static double? tryParse(String? raw) {
    if (raw == null) return null;
    final s = raw.replaceAll(',', '').trim();
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  /// Round UP to next multiple of [step]. (E.g. 1270 with step 250 => 1500)
  static num _ceilToStep(num value, num step) {
    if (step == 0) return value;
    return (value / step).ceil() * step;
  }

  static num roundLbp(num value) => _ceilToStep(value, 250);

  static num roundUsd(num value) => (value * 100).ceil() / 100;

  static String format(num value, {required String currencyCode}) {
    final code = currencyCode.trim().toUpperCase();
    if (code == 'LBP') {
      final v = roundLbp(value);
      return _lbp.format(v);
    }
    if (code == 'USD') {
      final v = roundUsd(value);
      final safe = (v.abs() < 0.00001) ? 0 : v;
      return _usd.format(safe);
    }
    return _generic.format(value);
  }
}
