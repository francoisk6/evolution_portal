import 'dart:convert';

class SavedAccount {
  final int id;
  final String
      username; // store server-returned username (often uppercase in your API)
  final String email;
  final String firstName;
  final String lastName;
  final String avatarUrl;
  final DateTime lastUsedAt;

  const SavedAccount({
    required this.id,
    required this.username,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.avatarUrl,
    required this.lastUsedAt,
  });

  String get displayName {
    final fn = firstName.trim();
    final ln = lastName.trim();
    final full = ('$fn $ln').trim();
    return full.isEmpty ? username : full;
  }

  SavedAccount copyWith({DateTime? lastUsedAt}) {
    return SavedAccount(
      id: id,
      username: username,
      email: email,
      firstName: firstName,
      lastName: lastName,
      avatarUrl: avatarUrl,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'email': email,
        'firstName': firstName,
        'lastName': lastName,
        'avatarUrl': avatarUrl,
        'lastUsedAt': lastUsedAt.toIso8601String(),
      };

  static SavedAccount fromJson(Map<String, dynamic> j) {
    return SavedAccount(
      id: (j['id'] as num?)?.toInt() ?? 0,
      username: (j['username'] as String?) ?? '',
      email: (j['email'] as String?) ?? '',
      firstName: (j['firstName'] as String?) ?? '',
      lastName: (j['lastName'] as String?) ?? '',
      avatarUrl: (j['avatarUrl'] as String?) ?? '',
      lastUsedAt: DateTime.tryParse((j['lastUsedAt'] as String?) ?? '') ??
          DateTime.now(),
    );
  }

  static List<SavedAccount> listFromPrefs(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((m) =>
            SavedAccount.fromJson(m.map((k, v) => MapEntry(k.toString(), v))))
        .toList();
  }

  static String listToPrefs(List<SavedAccount> items) {
    return jsonEncode(items.map((e) => e.toJson()).toList());
  }
}
