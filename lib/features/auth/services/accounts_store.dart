import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/app_env.dart';
import '../models/saved_account.dart';

class AccountsStore {
  static const _kAccountsIndexBase = 'auth.saved_accounts';
  static const _kActiveUsernameBase = 'auth.active_username';
  static const _tokenPrefixBase = 'auth.token'; // auth.token.<WORKSPACE>.<USERNAME>

  // Legacy keys used before workspace namespacing. Keep them readable so old
  // saved accounts automatically appear under the default Main workspace.
  static const _kLegacyAccountsIndex = _kAccountsIndexBase;
  static const _kLegacyActiveUsername = _kActiveUsernameBase;

  final FlutterSecureStorage _secure;

  String get _workspaceSlug => AppEnv.selectedWorkspace.slug.toLowerCase();
  String get _kAccountsIndex => '$_kAccountsIndexBase.$_workspaceSlug';
  String get _kActiveUsername => '$_kActiveUsernameBase.$_workspaceSlug';
  bool get _isMainWorkspace =>
      _workspaceSlug == AppEnv.defaultWorkspace.slug.toLowerCase();

  AccountsStore({FlutterSecureStorage? secure})
      : _secure = secure ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  Future<List<SavedAccount>> listAccounts() async {
    await _migrateLegacyAccountsIntoMainIfNeeded();

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAccountsIndex);
    final list = SavedAccount.listFromPrefs(raw);

    // Sort by last used desc for nicer UX
    list.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
    return list;
  }

  Future<void> upsertAccount(SavedAccount account) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAccountsIndex);
    final list = SavedAccount.listFromPrefs(raw);

    final idx = list.indexWhere(
        (a) => a.username.toUpperCase() == account.username.toUpperCase());
    final updated = account.copyWith(lastUsedAt: DateTime.now());

    if (idx >= 0) {
      list[idx] = updated;
    } else {
      list.add(updated);
    }

    prefs.setString(_kAccountsIndex, SavedAccount.listToPrefs(list));
  }

  Future<void> removeAccount(String username) async {
    final uname = username.toUpperCase();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAccountsIndex);
    final list = SavedAccount.listFromPrefs(raw);

    list.removeWhere((a) => a.username.toUpperCase() == uname);
    await prefs.setString(_kAccountsIndex, SavedAccount.listToPrefs(list));

    await _deleteToken(uname);

    final active = prefs.getString(_kActiveUsername);
    if ((active ?? '').toUpperCase() == uname) {
      await prefs.remove(_kActiveUsername);
    }
  }

  Future<void> setActiveUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActiveUsername, username.toUpperCase());
  }

  Future<String?> getActiveUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kActiveUsername);
  }

  Future<void> writeToken(String username, String token) async {
    final uname = username.toUpperCase();

    // Flutter Web: flutter_secure_storage can be unavailable depending on
    // hosting context (non-HTTPS / storage restrictions). Use SharedPreferences
    // (localStorage) for reliable persistence.
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey(uname), token);
      return;
    }

    // Mobile/desktop: prefer secure storage, but keep a safe fallback.
    try {
      await _secure.write(key: _tokenKey(uname), value: token);
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey(uname), token);
    }
  }

  Future<String?> readToken(String username) async {
    final uname = username.toUpperCase();

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final workspaceToken = prefs.getString(_tokenKey(uname));
      if (workspaceToken != null && workspaceToken.isNotEmpty) {
        return workspaceToken;
      }
      if (_isMainWorkspace) return prefs.getString(_legacyTokenKey(uname));
      return null;
    }

    // Prefer secure storage, but fall back to SharedPreferences to support
    // migrations and rare secure-storage failures.
    try {
      final v = await _secure.read(key: _tokenKey(uname));
      if (v != null && v.isNotEmpty) return v;

      if (_isMainWorkspace) {
        final legacy = await _secure.read(key: _legacyTokenKey(uname));
        if (legacy != null && legacy.isNotEmpty) return legacy;
      }
    } catch (_) {
      // ignore
    }
    final prefs = await SharedPreferences.getInstance();
    final workspaceToken = prefs.getString(_tokenKey(uname));
    if (workspaceToken != null && workspaceToken.isNotEmpty) return workspaceToken;
    if (_isMainWorkspace) return prefs.getString(_legacyTokenKey(uname));
    return null;
  }

  String _tokenKey(String usernameUpper) =>
      '$_tokenPrefixBase.$_workspaceSlug.$usernameUpper';
  String _legacyTokenKey(String usernameUpper) => '$_tokenPrefixBase.$usernameUpper';

  Future<void> _migrateLegacyAccountsIntoMainIfNeeded() async {
    if (!_isMainWorkspace) return;

    final prefs = await SharedPreferences.getInstance();
    final legacyRaw = prefs.getString(_kLegacyAccountsIndex);
    if (legacyRaw == null || legacyRaw.trim().isEmpty) return;

    final legacyList = SavedAccount.listFromPrefs(legacyRaw);
    if (legacyList.isEmpty) return;

    final currentRaw = prefs.getString(_kAccountsIndex);
    final currentList = SavedAccount.listFromPrefs(currentRaw);

    var changed = false;
    for (final legacy in legacyList) {
      final usernameUpper = legacy.username.toUpperCase();
      final idx = currentList.indexWhere(
        (a) => a.username.toUpperCase() == usernameUpper,
      );
      if (idx < 0) {
        currentList.add(legacy);
        changed = true;
      }

      await _copyLegacyTokenToWorkspaceTokenIfNeeded(usernameUpper);
    }

    if (changed) {
      await prefs.setString(_kAccountsIndex, SavedAccount.listToPrefs(currentList));
    }

    final active = prefs.getString(_kActiveUsername);
    if (active == null || active.trim().isEmpty) {
      final legacyActive = prefs.getString(_kLegacyActiveUsername);
      if (legacyActive != null && legacyActive.trim().isNotEmpty) {
        await prefs.setString(_kActiveUsername, legacyActive.toUpperCase());
      }
    }
  }

  Future<void> _copyLegacyTokenToWorkspaceTokenIfNeeded(String usernameUpper) async {
    final workspaceKey = _tokenKey(usernameUpper);
    final legacyKey = _legacyTokenKey(usernameUpper);

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(workspaceKey);
      if (existing != null && existing.isNotEmpty) return;
      final legacy = prefs.getString(legacyKey);
      if (legacy != null && legacy.isNotEmpty) {
        await prefs.setString(workspaceKey, legacy);
      }
      return;
    }

    try {
      final existing = await _secure.read(key: workspaceKey);
      if (existing != null && existing.isNotEmpty) return;
      final legacy = await _secure.read(key: legacyKey);
      if (legacy != null && legacy.isNotEmpty) {
        await _secure.write(key: workspaceKey, value: legacy);
        return;
      }
    } catch (_) {
      // Fall through to SharedPreferences fallback.
    }

    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(workspaceKey);
    if (existing != null && existing.isNotEmpty) return;
    final legacy = prefs.getString(legacyKey);
    if (legacy != null && legacy.isNotEmpty) {
      await prefs.setString(workspaceKey, legacy);
    }
  }

  Future<void> _deleteToken(String usernameUpper) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey(usernameUpper));
      return;
    }
    try {
      await _secure.delete(key: _tokenKey(usernameUpper));
    } catch (_) {
      // ignore
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey(usernameUpper));
  }
}
