import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Formats a JSON-like note into a readable layout (string form).
///
/// Output rules:
/// - Map => "Key: Value" per line
/// - List => bullets (•) on separate lines
/// - Nested structures are indented (2 spaces per level)
/// - No surrounding "{" / "[" characters
String prettyNote(dynamic note) {
  if (note == null) return '';

  var obj = _decodeAny(note);

  // If provider returns a single-item list holding one object, flatten it.
  if (obj is List && obj.length == 1 && (obj.first is Map || obj.first is List)) {
    obj = obj.first;
  }

  final buf = StringBuffer();
  _writeValueText(buf, obj, indent: 0);
  final out = buf.toString().trimRight();
  return out == '-' ? '' : out;
}

/// Rich, selectable note view:
/// - Keys are bold red
/// - Keys are formatted (underscores -> spaces, Title Case)
/// - Lists are bullets and indented to preserve hierarchy
/// - URLs inside scalar values are clickable
Widget buildPrettyNoteWidget(
  dynamic note, {
  TextStyle? baseStyle,
  TextStyle? keyStyle,
  TextStyle? linkStyle,
}) {
  final base = baseStyle ?? const TextStyle(fontSize: 12, height: 1.25);
  final keyS = keyStyle ??
      base.copyWith(
        fontWeight: FontWeight.w900,
        color: Colors.red,
      );
  final linkS = linkStyle ??
      base.copyWith(
        color: Colors.blue,
        decoration: TextDecoration.underline,
      );

  var obj = _decodeAny(note);

  // Flatten single-item list wrappers to avoid a lonely bullet line at top.
  if (obj is List && obj.length == 1 && (obj.first is Map || obj.first is List)) {
    obj = obj.first;
  }

  final spans = <InlineSpan>[];
  _writeValueSpans(
    spans,
    obj,
    indent: 0,
    base: base,
    keyStyle: keyS,
    linkStyle: linkS,
  );

  final isEmpty = spans.isEmpty ||
      (spans.length == 1 &&
          (spans.first is TextSpan) &&
          (spans.first as TextSpan).text?.trim().isEmpty == true);

  if (isEmpty) {
    return SelectableText('-', style: base, showCursor: false);
  }

  return SelectableText.rich(
    TextSpan(style: base, children: spans),
    showCursor: false,
    cursorWidth: 0,
    cursorColor: Colors.transparent,
  );
}

dynamic _decodeAny(dynamic note) {
  if (note is String) {
    final s = note.trim();
    if (s.isEmpty || s == '-' || s.toLowerCase() == 'null') return '';
    return _parseJsonishString(s) ?? s;
  }

  // Also decode nested json-ish strings later via _maybeDecodeJsonish().
  return note;
}

String _formatKey(String key) {
  var k = key.trim();
  if (k.isEmpty) return k;

  k = k.replaceAll('_', ' ');
  k = k.replaceAll(RegExp(r'\s+'), ' ');

  final parts = k.split(' ');
  final capped = parts.map((w) {
    if (w.isEmpty) return w;
    final lower = w.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }).join(' ');

  return capped;
}

String _scalarToString(dynamic v) {
  if (v == null) return '—';
  if (v is bool) return v ? 'Yes' : 'No';
  final s = '$v'.trim();
  return s.isEmpty ? '—' : s;
}

final RegExp _urlRx = RegExp(
  r'((?:https?:\/\/|www\.)[^\s<>{}\[\]"]+)',
  caseSensitive: false,
);

/// Attempts to decode a string that looks like:
/// - JSON: {"a":1} or [1,2]
/// - Python-ish: {'a': 1, 'b': None}
/// - Provider-ish: {order_id: 1, created_at: 2026-02-16 11:08:27, replay_api: [1323 70322845]}
dynamic _parseJsonishString(String s0) {
  final s = s0.trim();
  final looksLikeObj =
      (s.startsWith('{') && s.endsWith('}')) || (s.startsWith('[') && s.endsWith(']'));
  if (!looksLikeObj) return null;

  // 1) Strict JSON
  try {
    return jsonDecode(s);
  } catch (_) {}

  // 2) Python-ish -> JSON-ish
  try {
    var t = s;
    t = t.replaceAll("'", '"');
    t = t.replaceAll(RegExp(r'\bNone\b'), 'null');
    t = t.replaceAll(RegExp(r'\bTrue\b'), 'true');
    t = t.replaceAll(RegExp(r'\bFalse\b'), 'false');

    // Quote bare keys: {a: 1} -> {"a": 1}
    t = t.replaceAllMapped(
      RegExp(r'([{\s,])([A-Za-z_][A-Za-z0-9_]*)(\s*:)'),
      (m) => '${m.group(1)}"${m.group(2)}"${m.group(3)}',
    );

    return jsonDecode(t);
  } catch (_) {}

  // 3) Loose parser for "provider-ish" dict/list repr (handles space-separated lists).
  try {
    if (s.startsWith('[')) return _looseParseList(s);
    if (s.startsWith('{')) return _looseParseMap(s);
  } catch (_) {}

  return null;
}

dynamic _maybeDecodeJsonish(dynamic v) {
  if (v is! String) return v;
  final s = v.trim();
  if (s.isEmpty) return v;

  final decoded = _parseJsonishString(s);
  return decoded ?? v;
}

dynamic _parseScalar(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return '';
  final low = s.toLowerCase();

  if (low == 'null' || low == 'none') return null;
  if (low == 'true') return true;
  if (low == 'false') return false;

  // Strip surrounding quotes (single or double)
  if ((s.startsWith('"') && s.endsWith('"')) || (s.startsWith("'") && s.endsWith("'"))) {
    return s.substring(1, s.length - 1);
  }

  final i = int.tryParse(s);
  if (i != null) return i;

  final d = double.tryParse(s);
  if (d != null) return d;

  return s;
}

List<dynamic> _looseParseList(String s0) {
  final s = s0.trim();
  var inner = s.substring(1, s.length - 1).trim();
  if (inner.isEmpty) return <dynamic>[];

  final items = <dynamic>[];
  final buf = StringBuffer();

  int brace = 0;
  int bracket = 0;
  String? quote;

  void flush() {
    final t = buf.toString().trim();
    buf.clear();
    if (t.isEmpty) return;
    final decoded = _parseJsonishString(t);
    items.add(decoded ?? _parseScalar(t));
  }

  for (var i = 0; i < inner.length; i++) {
    final ch = inner[i];

    if (quote != null) {
      buf.write(ch);
      if (ch == quote) quote = null;
      continue;
    }

    if (ch == '"' || ch == "'") {
      quote = ch;
      buf.write(ch);
      continue;
    }

    if (ch == '{') brace++;
    if (ch == '}') brace = (brace > 0) ? brace - 1 : 0;
    if (ch == '[') bracket++;
    if (ch == ']') bracket = (bracket > 0) ? bracket - 1 : 0;

    final atTop = brace == 0 && bracket == 0;

    // Split on comma OR whitespace at top-level.
    if (atTop && (ch == ',' || ch == ' ' || ch == '\n' || ch == '\t' || ch == '\r')) {
      flush();
      continue;
    }

    buf.write(ch);
  }

  flush();
  return items;
}

Map<String, dynamic> _looseParseMap(String s0) {
  final s = s0.trim();
  var inner = s.substring(1, s.length - 1).trim();
  final out = <String, dynamic>{};
  if (inner.isEmpty) return out;

  int i = 0;

  void skipWs() {
    while (i < inner.length) {
      final c = inner[i];
      if (c == ' ' || c == '\n' || c == '\t' || c == '\r' || c == ',') {
        i++;
      } else {
        break;
      }
    }
  }

  String readUntilColon() {
    final start = i;
    while (i < inner.length && inner[i] != ':') {
      i++;
    }
    if (i >= inner.length) return inner.substring(start).trim();
    return inner.substring(start, i).trim();
  }

  String readValueChunk() {
    final start = i;
    int brace = 0;
    int bracket = 0;
    String? quote;

    while (i < inner.length) {
      final ch = inner[i];

      if (quote != null) {
        if (ch == quote) quote = null;
        i++;
        continue;
      }

      if (ch == '"' || ch == "'") {
        quote = ch;
        i++;
        continue;
      }

      if (ch == '{') brace++;
      if (ch == '}') brace = (brace > 0) ? brace - 1 : 0;
      if (ch == '[') bracket++;
      if (ch == ']') bracket = (bracket > 0) ? bracket - 1 : 0;

      final atTop = brace == 0 && bracket == 0;

      if (atTop && ch == ',') {
        break;
      }

      i++;
    }

    return inner.substring(start, i).trim();
  }

  while (i < inner.length) {
    skipWs();
    if (i >= inner.length) break;

    var key = readUntilColon();
    if (i < inner.length && inner[i] == ':') i++; // consume ':'
    key = key.trim();
    if ((key.startsWith('"') && key.endsWith('"')) || (key.startsWith("'") && key.endsWith("'"))) {
      key = key.substring(1, key.length - 1);
    }

    skipWs();
    final valChunk = readValueChunk();

    dynamic val;
    final decoded = _parseJsonishString(valChunk);
    if (decoded != null) {
      val = decoded;
    } else {
      val = _parseScalar(valChunk);
    }

    out[key] = val;

    // If current char is comma, consume it and continue.
    if (i < inner.length && inner[i] == ',') i++;
  }

  return out;
}

void _writeValueText(StringBuffer out, dynamic v, {required int indent}) {
  final pad = '  ' * indent;

  if (v == null) {
    out.writeln('${pad}—');
    return;
  }

  if (v is Map) {
    for (final entry in v.entries) {
      final key = _formatKey('${entry.key}');
      var val = entry.value;

      // Expand scalar strings that contain JSON/Python/provider-ish objects.
      val = _maybeDecodeJsonish(val);

      if (val is List || val is Map) {
        out.writeln('$pad$key:');
        _writeValueText(out, val, indent: indent + 1);
      } else {
        out.writeln('$pad$key: ${_scalarToString(val)}');
      }
    }
    return;
  }

  if (v is List) {
    for (final item0 in v) {
      var item = _maybeDecodeJsonish(item0);

      if (item is Map || item is List) {
        out.writeln('${pad}•');
        _writeValueText(out, item, indent: indent + 1);
      } else {
        out.writeln('$pad• ${_scalarToString(item)}');
      }
    }
    return;
  }

  // Scalar
  if (v is String) {
    final decoded = _maybeDecodeJsonish(v);
    if (decoded is Map || decoded is List) {
      _writeValueText(out, decoded, indent: indent);
      return;
    }
  }

  out.writeln('$pad${_scalarToString(v)}');
}

Future<void> _openUrl(String raw) async {
  var s = raw.trim();
  if (s.isEmpty) return;
  if (!s.contains('://')) {
    s = 'https://$s';
  }
  final uri = Uri.tryParse(s);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.platformDefault);
}

void _appendLinkedScalarSpans(
  List<InlineSpan> out,
  String text, {
  required TextStyle base,
  required TextStyle linkStyle,
}) {
  final matches = _urlRx.allMatches(text).toList(growable: false);
  if (matches.isEmpty) {
    out.add(TextSpan(text: text, style: base));
    return;
  }

  var cursor = 0;
  for (final m in matches) {
    if (m.start > cursor) {
      out.add(TextSpan(text: text.substring(cursor, m.start), style: base));
    }

    final url = m.group(0) ?? '';
    out.add(
      TextSpan(
        text: url,
        style: linkStyle,
        recognizer: TapGestureRecognizer()
          ..onTap = () {
            _openUrl(url);
          },
      ),
    );
    cursor = m.end;
  }

  if (cursor < text.length) {
    out.add(TextSpan(text: text.substring(cursor), style: base));
  }
}

void _writeValueSpans(
  List<InlineSpan> out,
  dynamic v, {
  required int indent,
  required TextStyle base,
  required TextStyle keyStyle,
  required TextStyle linkStyle,
}) {
  final pad = '  ' * indent;

  if (v == null) {
    out.add(TextSpan(text: '${pad}—\n', style: base));
    return;
  }

  if (v is Map) {
    for (final entry in v.entries) {
      final key = _formatKey('${entry.key}');
      var val = _maybeDecodeJsonish(entry.value);

      out.add(TextSpan(text: pad, style: base));
      out.add(TextSpan(text: key, style: keyStyle));
      out.add(TextSpan(text: ':', style: base));

      if (val is Map || val is List) {
        out.add(TextSpan(text: '\n', style: base));
        _writeValueSpans(
          out,
          val,
          indent: indent + 1,
          base: base,
          keyStyle: keyStyle,
          linkStyle: linkStyle,
        );
      } else {
        out.add(TextSpan(text: ' ', style: base));
        _appendLinkedScalarSpans(
          out,
          _scalarToString(val),
          base: base,
          linkStyle: linkStyle,
        );
        out.add(TextSpan(text: '\n', style: base));
      }
    }
    return;
  }

  if (v is List) {
    for (final item0 in v) {
      var item = _maybeDecodeJsonish(item0);

      out.add(TextSpan(text: pad, style: base));
      out.add(TextSpan(text: '•', style: base));

      if (item is Map || item is List) {
        out.add(TextSpan(text: '\n', style: base));
        _writeValueSpans(
          out,
          item,
          indent: indent + 1,
          base: base,
          keyStyle: keyStyle,
          linkStyle: linkStyle,
        );
      } else {
        out.add(TextSpan(text: ' ', style: base));
        _appendLinkedScalarSpans(
          out,
          _scalarToString(item),
          base: base,
          linkStyle: linkStyle,
        );
        out.add(TextSpan(text: '\n', style: base));
      }
    }
    return;
  }

  // Scalar
  if (v is String) {
    final decoded = _maybeDecodeJsonish(v);
    if (decoded is Map || decoded is List) {
      _writeValueSpans(
        out,
        decoded,
        indent: indent,
        base: base,
        keyStyle: keyStyle,
        linkStyle: linkStyle,
      );
      return;
    }
  }

  out.add(TextSpan(text: pad, style: base));
  _appendLinkedScalarSpans(
    out,
    _scalarToString(v),
    base: base,
    linkStyle: linkStyle,
  );
  out.add(TextSpan(text: '\n', style: base));
}
