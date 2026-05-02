import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

Future<bool> copyText(String text) async {
  final t = text.trim();
  if (t.isEmpty) return false;
  try {
    await Clipboard.setData(ClipboardData(text: t));
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> shareText(String text, {String? title}) async {
  final t = text.trim();
  if (t.isEmpty) return false;
  try {
    await Share.share(t, subject: title);
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> printText(String title, String text) async {
  final t = text.trim();
  if (t.isEmpty) return false;

  try {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            t,
            style: const pw.TextStyle(fontSize: 11),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      name: title,
      onLayout: (_) => doc.save(),
    );
    return true;
  } catch (_) {
    return false;
  }
}
