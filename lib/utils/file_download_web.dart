// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

String _safeFilename(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return 'transactions.xlsx';
  return trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_');
}

Future<bool> saveDownloadedFile({
  required List<int> bytes,
  required String filename,
  String? mimeType,
}) async {
  try {
    final safeName = _safeFilename(filename);
    final blob = html.Blob(
      [Uint8List.fromList(bytes)],
      mimeType ?? 'application/octet-stream',
    );
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..download = safeName
      ..style.display = 'none';

    html.document.body?.children.add(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
    return true;
  } catch (_) {
    return false;
  }
}
