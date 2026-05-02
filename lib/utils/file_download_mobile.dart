import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:share_plus/share_plus.dart';

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
    final file = File('${Directory.systemTemp.path}/$safeName');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: safeName,
      text: safeName,
    );
    return true;
  } catch (_) {
    return false;
  }
}
