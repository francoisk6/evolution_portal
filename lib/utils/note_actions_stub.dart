/// Non-web implementation stubs.
///
/// These functions return false so the caller can fallback (e.g., copy).
Future<bool> shareText(String text, {String? title}) async => false;

Future<bool> printText(String title, String text) async => false;
