import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionState extends ChangeNotifier {
  bool _ready = false;
  bool _loggedIn = false;
  String? _avatarUrl;
  bool? _usePinOnOrder;
  bool _hideDealerPrice = false;
  bool _isStaff = false;
  bool _isSuperuser = false;

  bool get ready => _ready;
  bool get loggedIn => _loggedIn;
  String? get avatarUrl => _avatarUrl;
  bool get usePinOnOrder => _usePinOnOrder ?? true;
  bool get hideDealerPrice => _hideDealerPrice;
  bool get showDealerPrice => !_hideDealerPrice;
  bool get isStaff => _isStaff;
  bool get isSuperuser => _isSuperuser;
  bool get isAdmin => _isStaff || _isSuperuser;

  SessionState() {
    _bootstrap();
  }

  Map<String, dynamic> _extractData(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      final data = raw['data'];
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return data.cast<String, dynamic>();
      return raw;
    }
    if (raw is Map) return raw.cast<String, dynamic>();
    return const <String, dynamic>{};
  }

  void _applyUserFlags(Map<String, dynamic> data) {
    final profile = data['profile'];
    final profileMap = profile is Map<String, dynamic>
        ? profile
        : (profile is Map ? profile.cast<String, dynamic>() : const <String, dynamic>{});

    _usePinOnOrder = _asBool(profileMap['use_pin_on_order'] ?? data['use_pin_on_order']);
    _hideDealerPrice = _asBool(profileMap['hide_dealer_price'] ?? data['hide_dealer_price']);
    _isStaff = _asBool(data['is_staff'] ?? profileMap['is_staff']);
    _isSuperuser = _asBool(data['is_superuser'] ?? profileMap['is_superuser']);
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    _loggedIn = token != null && token.isNotEmpty;
    _avatarUrl = prefs.getString('user_avatar_url');

    // Best-effort: load persisted user_json and extract profile.use_pin_on_order
    try {
      final raw = prefs.getString('user_json');
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        final data = _extractData(decoded);
        _applyUserFlags(data);
      }
    } catch (_) {
      // ignore
    }

    _ready = true;
    notifyListeners();
  }

  bool _asBool(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    final s = v.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes' || s == 'y';
  }

  Future<void> setLoggedIn(bool v) async {
    _loggedIn = v;
    notifyListeners();
  }

  Future<void> setAvatarUrl(String? url) async {
    _avatarUrl = url;
    final prefs = await SharedPreferences.getInstance();
    if (url == null || url.isEmpty) {
      await prefs.remove('user_avatar_url');
    } else {
      await prefs.setString('user_avatar_url', url);
    }
    notifyListeners();
  }

  /// Call this right after a successful login.
  /// Expects the "me" dict you already store in SharedPreferences.
  Future<void> afterLogin(Map<String, dynamic> me) async {
    _loggedIn = true;
    final data = _extractData(me);
    final profile = data['profile'];
    final profileMap = profile is Map<String, dynamic>
        ? profile
        : (profile is Map ? profile.cast<String, dynamic>() : const <String, dynamic>{});
    final avatar = profileMap['avatar']?.toString();
    await setAvatarUrl(avatar);
    _applyUserFlags(data);
    notifyListeners();
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_json');
    await prefs.remove('user_avatar_url');
    _loggedIn = false;
    _avatarUrl = null;
    _usePinOnOrder = null;
    _hideDealerPrice = false;
    _isStaff = false;
    _isSuperuser = false;
    notifyListeners();
  }
}

final sessionProvider =
    ChangeNotifierProvider<SessionState>((ref) => SessionState());
