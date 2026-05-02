import 'dart:html' as html;

Future<bool> reloadCurrentPage() async {
  try {
    html.window.location.reload();
    return true;
  } catch (_) {
    return false;
  }
}
