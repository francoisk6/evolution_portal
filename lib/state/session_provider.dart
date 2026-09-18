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
  String _workspaceTiers = 'dealers';
  bool _isStaff = false;
  bool _isSuperuser = false;
  String _username = '';

  bool get ready => _ready;
  bool get loggedIn => _loggedIn;
  // Upgrade http:// → https:// so mixed-content errors don't crash
  // CachedNetworkImage on HTTPS deployments.
  String? get avatarUrl {
    final u = _avatarUrl;
    if (u == null || u.isEmpty) return u;
    return u.startsWith('http:') ? u.replaceFirst('http:', 'https:') : u;
  }
  bool get usePinOnOrder => _usePinOnOrder ?? true;
  /// Selling tiers of the workspace this session belongs to.
  /// 'dealers'   - super-dealer -> dealers -> customers
  /// 'end_users' - admin sells to customers directly, no middle dealer
  String get workspaceTiers => _workspaceTiers;

  /// True when the signed-in user buys for themselves rather than to resell.
  /// They see one price and are addressed as a customer, not a dealer.
  bool get isEndUserWorkspace => _workspaceTiers == 'end_users';

  /// In an end-user workspace the buyer is the customer, so only the customer
  /// column is shown. The server already holds the two equal there: the catalog
  /// sync clears brand.native_customer_price and seeds
  /// selling_profit_percentage=1, so customer_price == dealer_price.
  ///
  /// Staff are exempt: they run the workspace and need their own cost and
  /// dealer price. The API sends those to child staff, so collapsing the view
  /// for everyone would blind the operator to figures it is deliberately
  /// returning.
  bool get hideDealerPrice =>
      _hideDealerPrice || (isEndUserWorkspace && !isAdmin);
  bool get showDealerPrice => !hideDealerPrice;
  bool get isStaff => _isStaff;
  bool get isSuperuser => _isSuperuser;
  bool get isAdmin => _isStaff || _isSuperuser;
  String get username => _username;

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
    final tiers = (profileMap['workspace_tiers'] ?? data['workspace_tiers'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (tiers.isNotEmpty) _workspaceTiers = tiers;
    _isStaff = _asBool(data['is_staff'] ?? profileMap['is_staff']);
    _isSuperuser = _asBool(data['is_superuser'] ?? profileMap['is_superuser']);
    final u = (data['username'] ?? profileMap['username'] ?? '').toString().trim();
    if (u.isNotEmpty) _username = u;
  }

  Future<void> _bootstrap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      _loggedIn = token != null && token.isNotEmpty;
      _avatarUrl = prefs.getString('user_avatar_url');

      // Best-effort: load persisted user_json and extract profile flags.
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
    } catch (_) {
      // SharedPreferences unavailable — treat as logged out.
    } finally {
      _ready = true;
      notifyListeners();
    }
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
    // Only update when the server returned the field; null means absent, not "no avatar".
    if (avatar != null) await setAvatarUrl(avatar.isEmpty ? null : avatar);
    _applyUserFlags(data);
    notifyListeners();
  }

  /// Save avatar URL from a login response to SharedPreferences WITHOUT
  /// notifying listeners. Called before AppStateScope.reset() so the new
  /// ProviderScope's _bootstrap() picks up the avatar from prefs directly.
  Future<void> persistLoginDataForReset(Map<String, dynamic> me) async {
    final data = _extractData(me);
    final profile = data['profile'];
    final profileMap = profile is Map<String, dynamic>
        ? profile
        : (profile is Map ? profile.cast<String, dynamic>() : const <String, dynamic>{});
    final avatar = profileMap['avatar']?.toString();
    final prefs = await SharedPreferences.getInstance();
    if (avatar == null || avatar.isEmpty) {
      await prefs.remove('user_avatar_url');
    } else {
      final url = avatar.startsWith('http:')
          ? avatar.replaceFirst('http:', 'https:')
          : avatar;
      await prefs.setString('user_avatar_url', url);
    }
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
    _workspaceTiers = 'dealers';
    _isStaff = false;
    _isSuperuser = false;
    notifyListeners();
  }
}

final sessionProvider =
    ChangeNotifierProvider<SessionState>((ref) => SessionState());
