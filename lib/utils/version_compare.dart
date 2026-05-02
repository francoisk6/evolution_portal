class ParsedAppVersion {
  final String raw;
  final String version;
  final int? buildNumber;
  final List<int> parts;

  const ParsedAppVersion({
    required this.raw,
    required this.version,
    required this.buildNumber,
    required this.parts,
  });

  String get display {
    if (buildNumber == null) return version;
    return '$version ($buildNumber)';
  }

  bool get isValid => version.isNotEmpty;

  factory ParsedAppVersion.parse(String input) {
    final raw = input.trim();
    if (raw.isEmpty || raw == '-') {
      return const ParsedAppVersion(
        raw: '',
        version: '',
        buildNumber: null,
        parts: <int>[],
      );
    }

    String version = raw;
    int? build;

    final paren = RegExp(r'^(.*?)\s*\((\d+)\)\s*$').firstMatch(raw);
    if (paren != null) {
      version = paren.group(1)?.trim() ?? raw;
      build = int.tryParse(paren.group(2) ?? '');
    } else if (raw.contains('+')) {
      final bits = raw.split('+');
      version = bits.first.trim();
      if (bits.length > 1) build = int.tryParse(bits[1].trim());
    }

    version = version.replaceFirst(RegExp(r'^[vV]\s*'), '').trim();

    final partStrings = version
        .split('.')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    final parts = <int>[];
    for (final p in partStrings) {
      final m = RegExp(r'\d+').firstMatch(p);
      parts.add(int.tryParse(m?.group(0) ?? '') ?? 0);
    }

    return ParsedAppVersion(
      raw: raw,
      version: version,
      buildNumber: build,
      parts: parts,
    );
  }
}

int compareParsedVersions(ParsedAppVersion a, ParsedAppVersion b) {
  final maxLen = a.parts.length > b.parts.length ? a.parts.length : b.parts.length;
  for (var i = 0; i < maxLen; i++) {
    final av = i < a.parts.length ? a.parts[i] : 0;
    final bv = i < b.parts.length ? b.parts[i] : 0;
    if (av != bv) return av.compareTo(bv);
  }

  // Only compare build numbers when both semantic versions are equal and the
  // remote version explicitly carries a build number requirement.
  if (a.buildNumber != null || b.buildNumber != null) {
    final ab = a.buildNumber ?? 0;
    final bb = b.buildNumber ?? 0;
    if (ab != bb) return ab.compareTo(bb);
  }

  return 0;
}

ParsedAppVersion maxParsedVersion(ParsedAppVersion a, ParsedAppVersion b) {
  return compareParsedVersions(a, b) >= 0 ? a : b;
}
