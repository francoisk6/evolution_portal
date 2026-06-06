// ignore: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<({List<int> bytes, String filename})?> pickCsvFile() async {
  final completer = Completer<({List<int> bytes, String filename})?>();

  final input = html.FileUploadInputElement()
    ..accept = '.csv,text/csv,text/plain'
    ..style.display = 'none';

  html.document.body?.append(input);

  input.onChange.listen((event) {
    final file = input.files?.first;
    if (file == null) {
      completer.complete(null);
      input.remove();
      return;
    }
    final reader = html.FileReader();
    reader.readAsDataUrl(file);
    reader.onLoad.listen((_) {
      try {
        final dataUrl = reader.result as String? ?? '';
        final comma = dataUrl.indexOf(',');
        if (comma == -1) throw Exception('invalid data url');
        final bytes = base64.decode(dataUrl.substring(comma + 1));
        completer.complete((bytes: bytes.toList(), filename: file.name));
      } catch (_) {
        completer.complete(null);
      }
      input.remove();
    });
    reader.onError.listen((_) {
      completer.complete(null);
      input.remove();
    });
  });

  input.click();
  return completer.future;
}
