import 'package:shared_preferences/shared_preferences.dart';

class InputHistoryStore {
  InputHistoryStore._();

  static const String _prefix = 'input_history.';
  static const int _defaultMaxItems = 8;

  static String _key(String historyKey) => '$_prefix$historyKey';

  static Future<List<String>> load(String historyKey) async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_key(historyKey)) ?? const <String>[];
    return values
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  static Future<void> saveValue(
    String historyKey,
    String value, {
    int maxItems = _defaultMaxItems,
  }) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_key(historyKey)) ?? const <String>[];

    final next = <String>[trimmed];
    for (final item in current) {
      final s = item.trim();
      if (s.isEmpty) continue;
      if (s.toLowerCase() == trimmed.toLowerCase()) continue;
      next.add(s);
      if (next.length >= maxItems) break;
    }

    await prefs.setStringList(_key(historyKey), next);
  }

  static Future<void> removeValue(String historyKey, String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_key(historyKey)) ?? const <String>[];
    final next = current
        .where((item) => item.trim().toLowerCase() != trimmed.toLowerCase())
        .toList(growable: false);

    await prefs.setStringList(_key(historyKey), next);
  }

  static Future<void> clear(String historyKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(historyKey));
  }
}
