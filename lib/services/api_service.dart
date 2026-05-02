import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app/app_env.dart';
import '../data/models/online_brand_payload.dart';
import '../data/models/online_customer_info.dart';
import '../data/models/online_cv_receiver_info.dart';
import '../data/models/online_purchase_order.dart';
import '../data/models/version_info.dart';
import 'api_envelope.dart';

class DownloadedFile {
  final List<int> bytes;
  final String filename;
  final String? contentType;

  const DownloadedFile({
    required this.bytes,
    required this.filename,
    this.contentType,
  });
}

class DownloadCancelledException implements Exception {
  final String message;

  const DownloadCancelledException([this.message = 'Request cancelled.']);

  @override
  String toString() => message;
}

class DownloadCancelToken {
  bool _isCancelled = false;
  http.Client? _client;

  bool get isCancelled => _isCancelled;

  void attach(http.Client client) {
    if (_isCancelled) {
      client.close();
      return;
    }
    _client = client;
  }

  void detach(http.Client client) {
    if (identical(_client, client)) {
      _client = null;
    }
  }

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    _client?.close();
    _client = null;
  }
}

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  String get _base => AppEnv.base;
  String get _authBase => AppEnv.authBase;
  String get _balanceBase => AppEnv.balanceBase;

  String? _token;

  // Expose the last response so UI can read server {message}/{error}
  ApiEnvelope? _lastEnv;
  ApiEnvelope? get lastEnvelope => _lastEnv;
  String? get lastServerMessage => _lastEnv?.message;
  String? get lastServerError => _lastEnv?.humanError;

  // ───────────────── helpers ─────────────────
  Future<void> _ensureTokenLoaded() async {
    if (_token != null) return;
    final p = await SharedPreferences.getInstance();
    _token = p.getString('auth_token');
  }

  /// Force re-read of the persisted token.
  ///
  /// IMPORTANT (web): right after writing SharedPreferences, a subsequent read
  /// can briefly return an empty value. We must never clobber a valid in-memory
  /// token with that transient empty read, otherwise the next request will miss
  /// the Authorization header and trigger a false "Session expired".
  Future<void> _forceReloadToken({bool allowClear = false}) async {
    final p = await SharedPreferences.getInstance();
    final t = p.getString('auth_token');

    if (t != null && t.isNotEmpty) {
      _token = t;
      return;
    }

    // Keep existing non-empty token unless explicitly asked to clear.
    if (allowClear) {
      _token = null;
    }
  }

  Future<void> _saveToken(String? token) async {
    final p = await SharedPreferences.getInstance();
    if (token == null || token.isEmpty) {
      await p.remove('auth_token');
      _token = null;
    } else {
      await p.setString('auth_token', token);
      _token = token;
    }
  }

  Future<bool> isAuthenticated() async {
    await _ensureTokenLoaded();
    return _token != null && _token!.isNotEmpty;
  }

  Map<String, String> _jsonHeaders({
    bool auth = false,
    bool includeContentType = true,
  }) {
    final h = <String, String>{
      'Accept': 'application/json',
    };
    if (includeContentType) {
      h['Content-Type'] = 'application/json';
    }
    if (auth && _token != null && _token!.isNotEmpty) {
      h['Authorization'] = 'Token $_token';
    }
    return h;
  }

  String _bodyText(http.Response res) {
    // Some backend responses omit charset in Content-Type. When that happens,
    // package:http can default to ISO-8859-1, which corrupts Arabic text.
    // Decode using UTF-8 from raw bytes (fallback to res.body if needed).
    // NOTE (web): BrowserClient sometimes yields an empty bodyBytes while
    // res.body contains the response text. Never return empty if body exists.
    if (res.bodyBytes.isEmpty) {
      return res.body;
    }
    try {
      return utf8.decode(res.bodyBytes);
    } catch (_) {
      return res.body;
    }
  }

  Future<Map<String, dynamic>> _getJsonMap(
    Uri url, {
    bool auth = false,
  }) async {
    if (auth) await _ensureTokenLoaded();
    final res = await http.get(url,
        headers: _jsonHeaders(auth: auth, includeContentType: false));
    final text = _bodyText(res);
    Map<String, dynamic> body = const <String, dynamic>{};
    if (text.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) {
          body = decoded;
        } else if (decoded is Map) {
          body = decoded.cast<String, dynamic>();
        } else {
          body = <String, dynamic>{'data': decoded};
        }
      } catch (_) {
        body = <String, dynamic>{'detail': text};
      }
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final env = ApiEnvelope(status: res.statusCode, body: body);
      _lastEnv = env;
      _fail(env, 'Request failed (HTTP ${env.status}).');
    }
    return body;
  }

  ApiEnvelope _envelope(http.Response res) {
    final isJson = (res.headers['content-type'] ?? '')
        .toLowerCase()
        .contains('application/json');

    Map<String, dynamic>? body;
    if (isJson) {
      final text = _bodyText(res);
      if (text.isNotEmpty) {
        try {
          body = jsonDecode(text) as Map<String, dynamic>;
        } catch (_) {
          body = {'detail': text, 'status': res.statusCode};
        }
      }
    }

    final env = ApiEnvelope(status: res.statusCode, body: body);
    _lastEnv = env; // remember for UI notices
    return env;
  }

  Never _fail(ApiEnvelope env, String fallback) =>
      throw Exception(env.humanError ?? fallback);

  Future<void> _persistUserJsonFrom(Map<String, dynamic> payload) async {
    final prefs = await SharedPreferences.getInstance();
    final user = (payload['data'] is Map<String, dynamic>)
        ? payload['data'] as Map<String, dynamic>
        : payload;
    await prefs.setString('user_json', jsonEncode(user));
  }

  // ───────────────── VERSION ─────────────────

  /// GET /api/version/  → { api_version, gui_version, web_version }
  ///
  /// Endpoint is expected to return a plain JSON object (not wrapped in the
  /// standard {success,message,data} envelope).
  Future<VersionInfo> getVersionInfo() async {
    await _ensureTokenLoaded();

    final packageInfo = await PackageInfo.fromPlatform();
    final guiVersion = _composeGuiVersionPayload(packageInfo);
    final guiPlatform = _resolveGuiPlatform();

    final url = Uri.parse('${_base}version/').replace(
      queryParameters: <String, String>{
        'gui_version': guiVersion,
        'gui_platform': guiPlatform,
      },
    );

    final res = await http.get(
      url,
      headers: _jsonHeaders(auth: true, includeContentType: false),
    );

    // Try to decode JSON regardless of headers (some dev servers omit content-type).
    final text = _bodyText(res);
    Map<String, dynamic> body = const <String, dynamic>{};
    if (text.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) body = decoded;
      } catch (_) {
        body = const <String, dynamic>{};
      }
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      // Use ApiEnvelope to extract a human-friendly error if backend returns DRF shape.
      final env = ApiEnvelope(status: res.statusCode, body: body);
      _lastEnv = env;
      _fail(env, 'Failed to load versions (HTTP ${env.status}).');
    }

    return VersionInfo.fromJson(body);
  }

  String _composeGuiVersionPayload(PackageInfo info) {
    final version = info.version.trim();
    final build = info.buildNumber.trim();

    if (version.isEmpty && build.isEmpty) return 'UNKNOWN';
    if (version.isEmpty) return build;
    if (build.isEmpty) return version;

    return '$version+$build';
  }

  String _resolveGuiPlatform() {
    if (kIsWeb) return 'WEB';

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'ANDROID';
      case TargetPlatform.iOS:
        return 'IOS';
      case TargetPlatform.windows:
        return 'WINDOWS';
      case TargetPlatform.macOS:
        return 'MACOS';
      case TargetPlatform.linux:
        return 'LINUX';
      case TargetPlatform.fuchsia:
        return 'UNKNOWN';
    }
  }

  // ───────────────── AUTH ─────────────────

  /// POST /api/auth/login/  { username, password, pin }  (email tolerated)
  Future<Map<String, dynamic>> login({
    required String usernameOrEmail,
    required String password,
    required String pin,
  }) async {
    final url = Uri.parse('${_authBase}login/');
    final res = await http.post(
      url,
      headers: _jsonHeaders(),
      body: jsonEncode({
        'username': usernameOrEmail,
        'email': usernameOrEmail, // tolerated by your API
        'password': password,
        'pin': pin,
      }),
    );
    final env = _envelope(res);

    if (res.statusCode == 401) {
      await logout();
      _fail(env, 'Invalid credentials.');
    }
    if (!env.ok) _fail(env, 'Login failed (HTTP ${env.status}).');

    final t = env.token;
    if (t == null || t.isEmpty) {
      _fail(env, 'Login succeeded but token missing in response.');
    }
    await _saveToken(t);

    final me = env.dataMap; // includes profile + token
    await _persistUserJsonFrom(me);
    return me;
  }

  /// Set the currently-active auth token (used for account switching).
  ///
  /// This updates both in-memory token and SharedPreferences('auth_token').
  Future<void> setAuthToken(String? token) async {
    await _saveToken(token);
  }

  /// POST /api/auth/register/  { username, email, password, password2, first_name?, last_name? }
  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String password2,
    String? firstName,
    String? lastName,
  }) async {
    final url = Uri.parse('${_authBase}register/');
    final res = await http.post(
      url,
      headers: _jsonHeaders(),
      body: jsonEncode({
        'username': username,
        'email': email,
        'password': password,
        'password2': password2,
        'first_name': firstName ?? '',
        'last_name': lastName ?? '',
      }),
    );
    final env = _envelope(res);
    if (!env.ok) _fail(env, 'Registration failed (HTTP ${env.status}).');

    // If token returned after register → auto-login
    final t = env.token;
    if (t != null && t.isNotEmpty) {
      await _saveToken(t);
      await _persistUserJsonFrom(env.dataMap);
    }
    return env.dataMap;
  }

  /// GET /api/auth/me/
  Future<Map<String, dynamic>> getMe() async {
    await _ensureTokenLoaded();
    final url = Uri.parse('${_authBase}me/');
    final res = await http.get(url,
        headers: _jsonHeaders(auth: true, includeContentType: false));
    final env = _envelope(res);

    if (res.statusCode == 401) {
      await logout();
      _fail(env, 'Session expired. Please login again.');
    }
    if (!env.ok) _fail(env, 'Failed to load profile.');
    return env.dataMap;
  }

  /// POST /api/auth/logout/  (204)
  Future<void> logout() async {
    // IMPORTANT: call server logout *with* the current token first.
    // If we clear the token before the POST, the backend will return 401.
    await _ensureTokenLoaded();
    final token = _token;

    try {
      if (token != null && token.isNotEmpty) {
        final url = Uri.parse('${_authBase}logout/');
        await http.post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Token $token',
          },
        );
      }
    } catch (_) {
      // Ignore network errors on logout
    }

    // Then wipe local session data
    await _saveToken(null);
    final p = await SharedPreferences.getInstance();
    await p.remove('user_json');
  }

  /// POST /api/auth/change-password/  { old_password, new_password } → rotates token
  Future<String> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _ensureTokenLoaded();
    final url = Uri.parse('${_authBase}change-password/');
    final res = await http.post(
      url,
      headers: _jsonHeaders(auth: true),
      body: jsonEncode(
          {'old_password': oldPassword, 'new_password': newPassword}),
    );
    final env = _envelope(res);
    if (!env.ok) {
      if (res.statusCode == 401) await logout();
      _fail(env, 'Failed to change password (HTTP ${env.status}).');
    }
    final newToken = env.dataMap['token']?.toString();
    if (newToken == null || newToken.isEmpty) {
      _fail(env, 'Password changed, but no token returned.');
    }
    await _saveToken(newToken);
    return newToken;
  }

  /// POST /api/auth/set-pin/  { pin: "1234" }  (null/empty to clear)
  Future<void> setPin(String? pin) async {
    await _ensureTokenLoaded();
    final url = Uri.parse('${_authBase}set-pin/');
    final res = await http.post(
      url,
      headers: _jsonHeaders(auth: true),
      body: jsonEncode({'pin': pin}),
    );
    final env = _envelope(res);
    if (!env.ok) {
      if (res.statusCode == 401) await logout();
      _fail(env, 'Failed to set PIN (HTTP ${env.status}).');
    }
  }

  /// PATCH /api/auth/profile/ — JSON (nested) or form (flat) compatibility
  /// If JSON nested fails with 400, we retry with flat JSON like your test.py.
  Future<Map<String, dynamic>> updateProfileJson({
    String? username,
    String? firstName,
    String? lastName,
    String? email,
    String? pin,
    bool? usePinOnOrder,
    bool? hideDealerPrice,
    String? bio,
    String? phoneNumber,
    String? defaultCurrency,
    int? uiVersion,
  }) async {
    await _ensureTokenLoaded();
    final url = Uri.parse('${_authBase}profile/');

    // Try nested JSON first
    final nested = {
      'user': {
        if (username != null) 'username': username,
        if (firstName != null) 'first_name': firstName,
        if (lastName != null) 'last_name': lastName,
        if (email != null) 'email': email,
      },
      'profile': {
        if (pin != null) 'pin': pin,
        if (usePinOnOrder != null) 'use_pin_on_order': usePinOnOrder,
        if (hideDealerPrice != null) 'hide_dealer_price': hideDealerPrice,
        if (bio != null) 'bio': bio,
        if (phoneNumber != null) 'phone_number': phoneNumber,
        if (defaultCurrency != null) 'default_currency': defaultCurrency,
        if (uiVersion != null) 'ui_version': uiVersion,
      },
    };

    var res = await http.patch(url,
        headers: _jsonHeaders(auth: true), body: jsonEncode(nested));
    var env = _envelope(res);

    // If view prefers flat (like your test.py with form-data), retry with flat JSON
    if (res.statusCode == 400) {
      final flat = {
        if (username != null) 'username': username,
        if (firstName != null) 'first_name': firstName,
        if (lastName != null) 'last_name': lastName,
        if (email != null) 'email': email,
        if (pin != null) 'pin': pin,
        if (usePinOnOrder != null) 'use_pin_on_order': usePinOnOrder,
        if (hideDealerPrice != null) 'hide_dealer_price': hideDealerPrice,
        if (bio != null) 'bio': bio,
        if (phoneNumber != null) 'phone_number': phoneNumber,
        if (defaultCurrency != null) 'default_currency': defaultCurrency,
        if (uiVersion != null) 'ui_version': uiVersion,
      };
      res = await http.patch(url,
          headers: _jsonHeaders(auth: true), body: jsonEncode(flat));
      env = _envelope(res);
    }

    if (!env.ok) {
      if (res.statusCode == 401) await logout();
      _fail(env, 'Failed to update profile (HTTP ${env.status}).');
    }
    await _persistUserJsonFrom(env.dataMap);
    return env.dataMap;
  }

  /// PATCH /api/auth/profile/ — Multipart (avatar upload, flat fields)
  /// (Use JSON version on web; fromPath isn’t supported on Flutter Web)
  Future<Map<String, dynamic>> updateProfileMultipart({
    String? username,
    String? firstName,
    String? lastName,
    String? email,
    String? pin,
    bool? usePinOnOrder,
    bool? hideDealerPrice,
    String? bio,
    String? phoneNumber,
    String? defaultCurrency,
    int? uiVersion,
    Uri? avatarFileUri, // Uri.file(path) on mobile/desktop
  }) async {
    await _ensureTokenLoaded();
    final url = Uri.parse('${_authBase}profile/');
    final req = http.MultipartRequest('PATCH', url);

    if (_token != null && _token!.isNotEmpty) {
      req.headers['Authorization'] = 'Token $_token';
      req.headers['Accept'] = 'application/json';
    }

    if (username != null) req.fields['username'] = username;
    if (firstName != null) req.fields['first_name'] = firstName;
    if (lastName != null) req.fields['last_name'] = lastName;
    if (email != null) req.fields['email'] = email;
    if (pin != null) req.fields['pin'] = pin;
    if (usePinOnOrder != null) {
      req.fields['use_pin_on_order'] = usePinOnOrder ? 'true' : 'false';
    }
    if (hideDealerPrice != null) {
      req.fields['hide_dealer_price'] = hideDealerPrice ? 'true' : 'false';
    }
    if (bio != null) req.fields['bio'] = bio;
    if (phoneNumber != null) req.fields['phone_number'] = phoneNumber;
    if (defaultCurrency != null) {
      req.fields['default_currency'] = defaultCurrency;
    }
    if (uiVersion != null) {
      req.fields['ui_version'] = uiVersion.toString();
    }

    if (avatarFileUri != null) {
      final file = await http.MultipartFile.fromPath(
          'avatar', avatarFileUri.toFilePath());
      req.files.add(file);
    }

    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    final env = _envelope(res);

    if (!env.ok) {
      if (res.statusCode == 401) await logout();
      _fail(env, 'Failed to update profile (HTTP ${env.status}).');
    }
    await _persistUserJsonFrom(env.dataMap);
    return env.dataMap;
  }

  /// PATCH /api/auth/profile/ — Multipart (avatar upload from bytes, works on web)
  Future<Map<String, dynamic>> updateProfileMultipartBytes({
    String? username,
    String? firstName,
    String? lastName,
    String? email,
    String? pin,
    bool? usePinOnOrder,
    bool? hideDealerPrice,
    String? bio,
    String? phoneNumber,
    String? defaultCurrency,
    int? uiVersion,
    List<int>? avatarBytes,
    String? avatarFilename,
  }) async {
    await _ensureTokenLoaded();
    final url = Uri.parse('${_authBase}profile/');
    final req = http.MultipartRequest('PATCH', url);

    if (_token != null && _token!.isNotEmpty) {
      req.headers['Authorization'] = 'Token $_token';
      req.headers['Accept'] = 'application/json';
    }

    if (username != null) req.fields['username'] = username;
    if (firstName != null) req.fields['first_name'] = firstName;
    if (lastName != null) req.fields['last_name'] = lastName;
    if (email != null) req.fields['email'] = email;
    if (pin != null) req.fields['pin'] = pin;
    if (usePinOnOrder != null) {
      req.fields['use_pin_on_order'] = usePinOnOrder ? 'true' : 'false';
    }
    if (hideDealerPrice != null) {
      req.fields['hide_dealer_price'] = hideDealerPrice ? 'true' : 'false';
    }
    if (bio != null) req.fields['bio'] = bio;
    if (phoneNumber != null) req.fields['phone_number'] = phoneNumber;
    if (defaultCurrency != null)
      req.fields['default_currency'] = defaultCurrency;
    if (uiVersion != null) req.fields['ui_version'] = uiVersion.toString();

    if (avatarBytes != null && avatarBytes.isNotEmpty) {
      req.files.add(http.MultipartFile.fromBytes(
        'avatar',
        avatarBytes,
        filename: avatarFilename ?? 'avatar.jpg',
      ));
    }

    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    final env = _envelope(res);

    if (!env.ok) {
      if (res.statusCode == 401) await logout();
      _fail(env, 'Failed to update profile (HTTP ${env.status}).');
    }

    await _persistUserJsonFrom(env.dataMap);
    return env.dataMap;
  }

  /// POST /api/auth/revoke-token/
  Future<void> revokeToken() async {
    await _ensureTokenLoaded();
    final url = Uri.parse('${_authBase}revoke-token/');
    final res = await http.post(url, headers: _jsonHeaders(auth: true));
    final env = _envelope(res);
    if (!env.ok) _fail(env, 'Failed to revoke token (HTTP ${env.status}).');
    await logout();
  }

  /// GET /api/auth/online-users/
  Future<List<dynamic>> onlineUsers() async {
    await _ensureTokenLoaded();
    final url = Uri.parse('${_authBase}online-users/');
    final res = await http.get(url, headers: _jsonHeaders(auth: true));
    final env = _envelope(res);
    if (!env.ok) {
      if (res.statusCode == 401) await logout();
      _fail(env, 'Failed to fetch online users (HTTP ${env.status}).');
    }
    return env.dataList;
  }

  /// POST /api/auth/force-logout-all/
  Future<String?> forceLogoutAllUsers() async {
    await _ensureTokenLoaded();
    final url = Uri.parse('${_authBase}force-logout-all/');
    final res = await http.post(url, headers: _jsonHeaders(auth: true));
    final env = _envelope(res);
    if (!env.ok) _fail(env, 'Failed to force logout (HTTP ${env.status}).');
    return env.message;
  }

  /// POST /api/auth/change-currency/  { currency: "USD" }
  Future<String?> changeCurrency(dynamic currency) async {
    await _ensureTokenLoaded();
    final url = Uri.parse('${_authBase}change-currency/');
    final payload = {'currency': currency?.toString()};
    final res = await http.post(url,
        headers: _jsonHeaders(auth: true), body: jsonEncode(payload));
    final env = _envelope(res);
    if (!env.ok) {
      if (res.statusCode == 401) await logout();
      _fail(env, 'Failed to change currency (HTTP ${env.status}).');
    }
    return env.currentCurrency; // {data: {current_currency: "..."}}
  }

  // ───────────────── BALANCE ─────────────────

  /// GET /api/balance/current-balance/
  /// Returns: { user_id, default_currency, items:[{currency,balance,...}] }
  Future<Map<String, dynamic>> getCurrentBalance({int? userId}) async {
    await _ensureTokenLoaded();
    final qp = (userId != null) ? '?user=$userId' : '';
    final url = Uri.parse('${_balanceBase}current-balance/$qp');
    final res = await http.get(url, headers: _jsonHeaders(auth: true));
    final env = _envelope(res);

    if (res.statusCode == 401) {
      await logout();
      _fail(env, 'Session expired. Please login again.');
    }
    if (!env.ok) _fail(env, 'Failed to load current balance.');
    return env.dataMap;
  }

  /// POST /api/balance/add/  { lbp_amount: "5000", usd_amount: "5" }
  Future<Map<String, dynamic>> addBalance({
    String? lbpAmount,
    String? usdAmount,
  }) async {
    await _ensureTokenLoaded();
    final url = Uri.parse('${_balanceBase}add/');
    final payload = {
      if (lbpAmount != null) 'lbp_amount': lbpAmount,
      if (usdAmount != null) 'usd_amount': usdAmount,
    };
    final res = await http.post(url,
        headers: _jsonHeaders(auth: true), body: jsonEncode(payload));
    final env = _envelope(res);

    if (res.statusCode == 401) {
      await logout();
      _fail(env, 'Session expired. Please login again.');
    }
    if (!env.ok) _fail(env, 'Failed to add balance.');
    // Usually returns { message, new_balances: [...] } under data
    return env.dataMap;
  }

  /// GET /api/balance/schema/
  Future<Map<String, dynamic>> getBalanceSchema() async {
    await _ensureTokenLoaded();
    final url = Uri.parse('${_balanceBase}schema/');
    final res = await http.get(url, headers: _jsonHeaders(auth: true));
    final env = _envelope(res);

    if (res.statusCode == 401) {
      await logout();
      _fail(env, 'Session expired. Please login again.');
    }
    if (!env.ok) _fail(env, 'Failed to load balance schema.');
    return env.dataMap;
  }

  /// GET /api/balance/history/?page=...&date_from=YYYY-MM-DD&...
  /// Returns the inner `data`: { count, page, page_size, results: [...] }
  Future<Map<String, dynamic>> getBalanceHistory({
    int page = 1,
    int? pageSize,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool? status,
    int? currencyId,
    bool? distinctUsers,
    int? userId,
    bool? includeFilters,
  }) async {
    await _ensureTokenLoaded();

    String fmt(DateTime dt) {
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }

    final qp = <String, String>{'page': page.toString()};
    if (pageSize != null) qp['page_size'] = pageSize.toString();
    if (dateFrom != null) qp['date_from'] = fmt(dateFrom);
    if (dateTo != null) qp['date_to'] = fmt(dateTo);
    if (status != null) qp['status'] = status.toString(); // "true"/"false"
    if (currencyId != null) qp['currency'] = currencyId.toString();
    if (distinctUsers != null) qp['distinct_users'] = distinctUsers.toString();
    if (userId != null) qp['user'] = userId.toString();
    if (includeFilters != null) {
      qp['include_filters'] = includeFilters ? '1' : '0';
    }

    final uri =
        Uri.parse('${_balanceBase}history/').replace(queryParameters: qp);
    final res = await http.get(uri, headers: _jsonHeaders(auth: true));
    final env = _envelope(res);

    if (res.statusCode == 401) {
      await logout();
      _fail(env, 'Session expired. Please login again.');
    }
    if (!env.ok) _fail(env, 'Failed to load balance history.');
    return env.dataMap;
  }

  // ───────────────── HOME ─────────────────

  /// GET /api/home/groups-with-products/
  /// Returns a list of sections:
  /// [ { id, name, details: [ { id, name, avatar } ] } ]
  Future<List<dynamic>> getGroupsWithProducts() async {
    await _ensureTokenLoaded();

    // Prefer a dedicated base if you expose it; otherwise fall back to base + "home/".
    final String base =
        (AppEnv.homeBase.isNotEmpty) ? AppEnv.homeBase : '${AppEnv.base}home/';

    final url = Uri.parse('${base}groups-with-products/');
    final res = await http.get(url, headers: _jsonHeaders(auth: true));

    // Auth handling
    if (res.statusCode == 401) {
      await logout();
      throw Exception('Session expired. Please login again.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Failed to load groups (HTTP ${res.statusCode}).');
    }

    // Decode raw JSON (this endpoint returns a plain list)
    final ct = (res.headers['content-type'] ?? '').toLowerCase();
    if (!ct.contains('application/json')) {
      throw Exception('Unexpected response type from server.');
    }

    final decoded = jsonDecode(_bodyText(res));

    if (decoded is List) {
      return decoded; // happy path (plain list)
    }

    if (decoded is Map<String, dynamic>) {
      // Be tolerant if backend wraps under {data: [...] } or {results: [...] }
      final maybe = decoded['data'] ?? decoded['results'];
      if (maybe is List) return maybe;
    }

    // Nothing usable
    return <dynamic>[];
  }

  /// GET /api/home/products-without-groups/
  /// Returns a plain list:
  /// [ { id: <string>, name, alt, sector_name, ... } ]
  Future<List<dynamic>> getProductsWithoutGroups() async {
    await _ensureTokenLoaded();

    final String base =
        (AppEnv.homeBase.isNotEmpty) ? AppEnv.homeBase : '${AppEnv.base}home/';

    final url = Uri.parse('${base}products-without-groups/');
    final res = await http.get(url, headers: _jsonHeaders(auth: true));

    if (res.statusCode == 401) {
      await logout();
      throw Exception('Session expired. Please login again.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(
          'Failed to load products without groups (HTTP ${res.statusCode}).');
    }

    final ct = (res.headers['content-type'] ?? '').toLowerCase();
    if (!ct.contains('application/json')) {
      throw Exception('Unexpected response type from server.');
    }

    final decoded = jsonDecode(_bodyText(res));

    if (decoded is List) {
      return decoded;
    }

    if (decoded is Map<String, dynamic>) {
      final maybe = decoded['data'] ?? decoded['results'];
      if (maybe is List) return maybe;
    }

    return <dynamic>[];
  }

// ───────────────── ONLINE ─────────────────

  /// GET /api/online/group-details/{groupDetailId}/brands/?gsd={optionalSubdetailId}&currency={LBP|USD}
  /// Returns a single "screen payload" (tabs + brands for active tab only).
  Future<OnlineBrandsPayload> getOnlineBrandsPayload({
    required int groupDetailId,
    required String currency,
    int? gsd,
  }) async {
    // Ensure we have an in-memory token. Do NOT blindly overwrite a valid
    // in-memory token with a transient empty SharedPreferences read.
    await _ensureTokenLoaded();
    if (_token == null || _token!.isEmpty) {
      await _forceReloadToken();
    }

    // Prefer a dedicated base if you expose it; otherwise fall back to base + "home/".
    final String base = (AppEnv.onlineBase.isNotEmpty)
        ? AppEnv.onlineBase
        : '${AppEnv.base}online/';

    final qp = <String, String>{'currency': currency.toUpperCase()};
    if (gsd != null) qp['gsd'] = gsd.toString();

    final url = Uri.parse('${base}group-details/$groupDetailId/brands/')
        .replace(queryParameters: qp);

    http.Response res = await http.get(url, headers: _jsonHeaders(auth: true));

    // If credentials were not provided right after login, retry a couple times
    // with a short backoff and a token reload.
    if (res.statusCode == 401) {
      for (final ms in const [60, 180]) {
        await Future.delayed(Duration(milliseconds: ms));
        await _forceReloadToken();
        if (_token == null || _token!.isEmpty) continue;
        res = await http.get(url, headers: _jsonHeaders(auth: true));
        if (res.statusCode != 401) break;
      }
    }

    if (res.statusCode == 401) {
      // Only clear the session if we *actually* have a token and it's still rejected.
      if (_token != null && _token!.isNotEmpty) {
        await logout();
      }
      throw Exception('Session expired. Please login again.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Failed to load brands (HTTP ${res.statusCode}).');
    }

    final ct = (res.headers['content-type'] ?? '').toLowerCase();
    if (!ct.contains('application/json')) {
      throw Exception('Unexpected response type from server.');
    }

    final decoded = jsonDecode(_bodyText(res));
    if (decoded is Map<String, dynamic>) {
      return OnlineBrandsPayload.fromJson(decoded);
    }

    throw Exception('Unexpected brands response shape.');
  }

  /// GET /api/online/product-details/brands/?q=<string>&search=<mode>&gsd=<optionalSubdetailId>&currency={LBP|USD}
  ///
  /// Used by Home "Other Products" cards where we don't have a numeric groupDetailId.
  /// The backend response schema matches getOnlineBrandsPayload().
  Future<OnlineBrandsPayload> getOnlineProductBrandsPayload({
    required String q,
    String? searchMode,
    required String currency,
    int? gsd,
  }) async {
    await _ensureTokenLoaded();
    if (_token == null || _token!.isEmpty) {
      await _forceReloadToken();
    }

    final String base = (AppEnv.onlineBase.isNotEmpty)
        ? AppEnv.onlineBase
        : '${AppEnv.base}online/';

    final qp = <String, String>{
      'currency': currency.toUpperCase(),
      'q': q,
    };
    final sm = (searchMode ?? '').trim();
    if (sm.isNotEmpty) qp['search'] = sm;
    if (gsd != null) qp['gsd'] = gsd.toString();

    final url = Uri.parse('${base}product-details/brands/')
        .replace(queryParameters: qp);

    http.Response res = await http.get(url, headers: _jsonHeaders(auth: true));

    if (res.statusCode == 401) {
      for (final ms in const [60, 180]) {
        await Future.delayed(Duration(milliseconds: ms));
        await _forceReloadToken();
        if (_token == null || _token!.isEmpty) continue;
        res = await http.get(url, headers: _jsonHeaders(auth: true));
        if (res.statusCode != 401) break;
      }
    }

    if (res.statusCode == 401) {
      if (_token != null && _token!.isNotEmpty) {
        await logout();
      }
      throw Exception('Session expired. Please login again.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      // Backend typically returns {"detail": "..."} for no match; keep it readable.
      Map<String, dynamic>? decoded;
      try {
        final text = _bodyText(res);
        if (text.isNotEmpty) {
          final d = jsonDecode(text);
          if (d is Map<String, dynamic>) decoded = d;
        }
      } catch (_) {
        // ignore JSON parse errors; fall back to generic HTTP message
      }

      final detail = decoded?['detail']?.toString().trim();
      if (detail != null && detail.isNotEmpty) {
        throw Exception(detail);
      }
      throw Exception('Failed to load brands (HTTP ${res.statusCode}).');
    }

    final ct = (res.headers['content-type'] ?? '').toLowerCase();
    if (!ct.contains('application/json')) {
      throw Exception('Unexpected response type from server.');
    }

    final decoded = jsonDecode(_bodyText(res));
    if (decoded is Map<String, dynamic>) {
      return OnlineBrandsPayload.fromJson(decoded);
    }

    throw Exception('Unexpected brands response shape.');
  }

  /// GET /api/online/customer-info/?account_number=...&group_subdetail_id=...
  ///
  /// Used when a subdetail tab has `has_info=true` (customer lookup before showing brands).
  Future<OnlineCustomerInfoResponse> getOnlineCustomerInfo({
    required String accountNumber,
    required int groupSubdetailId,
    String? currency,
  }) async {
    await _ensureTokenLoaded();

    final base = AppEnv.onlineBase;
    final qp = <String, String>{
      'account_number': accountNumber.trim(),
      'group_subdetail_id': groupSubdetailId.toString(),
    };

    final c = (currency ?? '').trim();
    if (c.isNotEmpty) {
      qp['currency'] = c;
    }

    final url = Uri.parse('${base}customer-info/').replace(queryParameters: qp);

    http.Response res = await http.get(url, headers: _jsonHeaders(auth: true));

    // Retry on early 401 right after login (same pattern as other online endpoints).
    if (res.statusCode == 401) {
      for (final ms in const [60, 180]) {
        await Future.delayed(Duration(milliseconds: ms));
        await _forceReloadToken();
        if (_token == null || _token!.isEmpty) continue;
        res = await http.get(url, headers: _jsonHeaders(auth: true));
        if (res.statusCode != 401) break;
      }
    }

    if (res.statusCode == 401) {
      if (_token != null && _token!.isNotEmpty) {
        await logout();
      }
      throw Exception('Session expired. Please login again.');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      Map<String, dynamic>? decoded;
      try {
        final text = _bodyText(res);
        if (text.isNotEmpty) {
          final d = jsonDecode(text);
          if (d is Map<String, dynamic>) decoded = d;
        }
      } catch (_) {
        // fallthrough
      }

      String? _firstNonEmpty(Map<String, dynamic>? m) {
        if (m == null) return null;
        for (final k in const ['message', 'error', 'detail']) {
          final v = m[k];
          if (v == null) continue;
          final s = v.toString().trim();
          if (s.isNotEmpty) return s;
        }
        return null;
      }

      final msg = _firstNonEmpty(decoded);
      if (msg != null && msg.isNotEmpty) {
        throw Exception(msg);
      }

      throw Exception('Failed to load customer info (HTTP ${res.statusCode}).');
    }

    final decoded = jsonDecode(_bodyText(res));
    if (decoded is Map<String, dynamic>) {
      return OnlineCustomerInfoResponse.fromJson(decoded);
    }
    throw Exception('Unexpected customer-info response shape.');
  }

  /// POST /api/online/cv/receiver-info/
  ///
  /// Body: {"receiver_number": "..."}
  Future<OnlineCvReceiverInfoResponse> postOnlineCvReceiverInfo({
    required String receiverNumber,
  }) async {
    await _ensureTokenLoaded();
    if (_token == null || _token!.isEmpty) {
      await _forceReloadToken();
    }

    final base = AppEnv.onlineBase;
    final url = Uri.parse('${base}cv/receiver-info/');

    http.Response res = await http.post(
      url,
      headers: _jsonHeaders(auth: true),
      body: jsonEncode({'receiver_number': receiverNumber.trim()}),
    );

    // Retry on early 401 right after login (same pattern as other online endpoints).
    if (res.statusCode == 401) {
      for (final ms in const [60, 180]) {
        await Future.delayed(Duration(milliseconds: ms));
        await _forceReloadToken();
        if (_token == null || _token!.isEmpty) continue;
        res = await http.post(
          url,
          headers: _jsonHeaders(auth: true),
          body: jsonEncode({'receiver_number': receiverNumber.trim()}),
        );
        if (res.statusCode != 401) break;
      }
    }

    if (res.statusCode == 401) {
      if (_token != null && _token!.isNotEmpty) {
        await logout();
      }
      throw Exception('Session expired. Please login again.');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      Map<String, dynamic>? decoded;
      try {
        final t = _bodyText(res);
        if (t.isNotEmpty) {
          final d = jsonDecode(t);
          if (d is Map<String, dynamic>) decoded = d;
        }
      } catch (_) {
        // ignore
      }

      String? _firstNonEmpty(Map<String, dynamic>? m) {
        if (m == null) return null;
        for (final k in const ['message', 'error', 'detail']) {
          final v = m[k];
          if (v == null) continue;
          final s = v.toString().trim();
          if (s.isNotEmpty) return s;
        }
        return null;
      }

      final msg = _firstNonEmpty(decoded);
      if (msg != null && msg.isNotEmpty) {
        throw Exception(msg);
      }

      throw Exception('Receiver lookup failed (HTTP ${res.statusCode}).');
    }

    final decoded = jsonDecode(_bodyText(res));
    if (decoded is Map<String, dynamic>) {
      return OnlineCvReceiverInfoResponse.fromJson(decoded);
    }

    throw Exception('Unexpected receiver-info response shape.');
  }

  // ───────────────── ACCOUNT / ORDER ─────────────────

  /// GET /api/account/online-purchase/
  ///
  /// Used to render the purchase page (pricing + required params) before submitting the order.
  Future<OnlinePurchaseOrderResponse> getOnlinePurchaseOrder({
    required String currency,
    required int brandId,
    required int groupSubdetailId,
    required int quantity,
    Map<String, dynamic>? criteriaInfo,
  }) async {
    await _ensureTokenLoaded();
    if (_token == null || _token!.isEmpty) {
      await _forceReloadToken();
    }

    final String base = '${AppEnv.base}account/';

    final qp = <String, String>{
      'brand_id': brandId.toString(),
      'currency': currency.trim().toUpperCase(),
      'quantity': quantity.toString(),
      'group_subdetail_id': groupSubdetailId.toString(),
    };

    if (criteriaInfo != null && criteriaInfo.isNotEmpty) {
      qp['criteria_info'] = jsonEncode(criteriaInfo);
    }

    final url =
        Uri.parse('${base}online-purchase/').replace(queryParameters: qp);

    http.Response res = await http.get(url, headers: _jsonHeaders(auth: true));

    if (res.statusCode == 401) {
      await logout();
      throw Exception('Session expired. Please login again.');
    }

    final decodedAny = () {
      try {
        return jsonDecode(_bodyText(res));
      } catch (_) {
        return null;
      }
    }();

    _lastEnv = ApiEnvelope(
      status: res.statusCode,
      body: decodedAny is Map<String, dynamic> ? decodedAny : null,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      String? _firstNonEmpty(Map<String, dynamic>? m) {
        if (m == null) return null;
        for (final k in const ['message', 'error', 'detail']) {
          final v = m[k];
          if (v == null) continue;
          final s = v.toString().trim();
          if (s.isNotEmpty) return s;
        }
        return null;
      }

      final msg = _firstNonEmpty(
          decodedAny is Map<String, dynamic> ? decodedAny : null);
      if (msg != null && msg.isNotEmpty) {
        throw Exception(msg);
      }
      throw Exception('Order preview failed (HTTP ${res.statusCode}).');
    }

    if (decodedAny is Map<String, dynamic>) {
      final r = OnlinePurchaseOrderResponse.fromJson(decodedAny);
      if (!r.success) {
        throw Exception(r.error ?? r.message);
      }
      return r;
    }

    throw Exception('Unexpected order preview response shape.');
  }

  /// POST /api/account/online-purchase/
  ///
  /// Submits an order created by the purchase page.
  Future<OnlinePurchasePostResponse> postOnlinePurchaseOrder({
    required String orderUuid,
    required String currency,
    required int brandId,
    required int groupSubdetailId,
    required int quantity,
    String? pin,
    String? clientname,
    required Map<String, String> params,
    Map<String, dynamic>? criteriaInfo,
  }) async {
    await _ensureTokenLoaded();
    if (_token == null || _token!.isEmpty) {
      await _forceReloadToken();
    }

    final String base = '${AppEnv.base}account/';
    final url = Uri.parse('${base}online-purchase/');

    final body = <String, dynamic>{
      'order_uuid': orderUuid,
      'brand_id': brandId,
      'currency': currency.trim().toUpperCase(),
      'quantity': quantity,
      'group_subdetail_id': groupSubdetailId,
      'clientname': (clientname ?? '').trim(),
      'params': params,
    };

    // Only include PIN when it's used (backend can decide to enforce/ignore).
    if (pin != null) {
      body['pin'] = pin;
    }

    if (criteriaInfo != null && criteriaInfo.isNotEmpty) {
      body['criteria_info'] = criteriaInfo;
    }

    http.Response res = await http.post(
      url,
      headers: _jsonHeaders(auth: true),
      body: jsonEncode(body),
    );

    if (res.statusCode == 401) {
      await logout();
      throw Exception('Session expired. Please login again.');
    }

    final decodedAny = () {
      try {
        return jsonDecode(_bodyText(res));
      } catch (_) {
        return null;
      }
    }();

    _lastEnv = ApiEnvelope(
      status: res.statusCode,
      body: decodedAny is Map<String, dynamic> ? decodedAny : null,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      String? _firstNonEmpty(Map<String, dynamic>? m) {
        if (m == null) return null;
        for (final k in const ['message', 'error', 'detail']) {
          final v = m[k];
          if (v == null) continue;
          final s = v.toString().trim();
          if (s.isNotEmpty) return s;
        }
        return null;
      }

      final msg = _firstNonEmpty(
          decodedAny is Map<String, dynamic> ? decodedAny : null);
      if (msg != null && msg.isNotEmpty) {
        throw Exception(msg);
      }
      throw Exception('Purchase failed (HTTP ${res.statusCode}).');
    }

    if (decodedAny is Map<String, dynamic>) {
      final r = OnlinePurchasePostResponse.fromJson(decodedAny);
      if (!r.success) {
        throw Exception(r.error ?? r.message);
      }
      return r;
    }

    throw Exception('Unexpected purchase response shape.');
  }

  /// POST /api/account/online-purchase/order-check/
  ///
  /// IMPORTANT: this endpoint can return HTTP 400 with a valid JSON body
  /// like {success:false, message:"Order not found"}. We must NOT throw on
  /// non-2xx here; the caller decides how to present the message.
  Future<Map<String, dynamic>> postOnlinePurchaseOrderCheck({
    required String orderNumber,
    required String sectorName,
    required int transactionId,
  }) async {
    await _ensureTokenLoaded();
    if (_token == null || _token!.isEmpty) {
      await _forceReloadToken();
    }

    final url = Uri.parse('${AppEnv.base}account/online-purchase/order-check/');

    http.Response res = await http.post(
      url,
      headers: _jsonHeaders(auth: true),
      body: jsonEncode({
        'order_number': orderNumber,
        'sector_name': sectorName,
        'transaction_id': transactionId,
      }),
    );

    if (res.statusCode == 401) {
      await logout();
      throw Exception('Session expired. Please login again.');
    }

    final text = _bodyText(res);
    dynamic decodedAny;
    if (text.trim().isNotEmpty) {
      try {
        decodedAny = jsonDecode(text);
      } catch (_) {
        decodedAny = null;
      }
    }

    Map<String, dynamic> body;
    if (decodedAny is Map<String, dynamic>) {
      body = decodedAny;
    } else if (decodedAny is Map) {
      body = decodedAny.cast<String, dynamic>();
    } else {
      // Non-JSON body or JSON that isn't an object.
      body = <String, dynamic>{
        'success': false,
        'message': 'Invalid provider response',
        if (text.trim().isNotEmpty) 'detail': text,
      };
    }

    // Remember server message for UI banners/snackbars.
    _lastEnv = ApiEnvelope(status: res.statusCode, body: body);

    // Return body regardless of HTTP status; caller uses success/message.
    return body;
  }

  String? _parseFilenameFromContentDisposition(String? header) {
    final raw = header?.trim();
    if (raw == null || raw.isEmpty) return null;

    final star = RegExp(r"filename\*=UTF-8''([^;]+)", caseSensitive: false)
        .firstMatch(raw);
    if (star != null) {
      final encoded = star.group(1)?.trim();
      if (encoded != null && encoded.isNotEmpty) {
        return Uri.decodeFull(encoded).replaceAll('"', '').trim();
      }
    }

    final normal =
        RegExp(r'filename="?([^";]+)"?', caseSensitive: false).firstMatch(raw);
    final value = normal?.group(1)?.trim();
    if (value == null || value.isEmpty) return null;
    return value.replaceAll('"', '').trim();
  }

  Future<DownloadedFile> _getBinary(
    Uri url, {
    bool auth = false,
    String? fallbackFilename,
    DownloadCancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled ?? false) {
      throw const DownloadCancelledException();
    }
    if (auth) await _ensureTokenLoaded();

    final headers = <String, String>{
      'Accept':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet, application/octet-stream, application/json',
    };
    if (auth && _token != null && _token!.isNotEmpty) {
      headers['Authorization'] = 'Token $_token';
    }

    final client = http.Client();
    cancelToken?.attach(client);

    late final http.Response res;
    try {
      res = await client.get(url, headers: headers);
    } catch (e) {
      if (cancelToken?.isCancelled ?? false) {
        throw const DownloadCancelledException();
      }
      rethrow;
    } finally {
      cancelToken?.detach(client);
      client.close();
    }

    if (cancelToken?.isCancelled ?? false) {
      throw const DownloadCancelledException();
    }

    final contentType = res.headers['content-type']?.trim();

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final text = _bodyText(res);
      Map<String, dynamic> body = const <String, dynamic>{};
      if (text.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(text);
          if (decoded is Map<String, dynamic>) {
            body = decoded;
          } else if (decoded is Map) {
            body = decoded.cast<String, dynamic>();
          } else {
            body = <String, dynamic>{'detail': text};
          }
        } catch (_) {
          body = <String, dynamic>{'detail': text};
        }
      }
      final env = ApiEnvelope(status: res.statusCode, body: body);
      _lastEnv = env;
      _fail(env, 'Request failed (HTTP ${env.status}).');
    }

    if ((contentType ?? '').toLowerCase().contains('application/json')) {
      final text = _bodyText(res);
      Map<String, dynamic> body = const <String, dynamic>{};
      if (text.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(text);
          if (decoded is Map<String, dynamic>) {
            body = decoded;
          } else if (decoded is Map) {
            body = decoded.cast<String, dynamic>();
          } else {
            body = <String, dynamic>{'detail': text};
          }
        } catch (_) {
          body = <String, dynamic>{'detail': text};
        }
      }
      final env = ApiEnvelope(status: res.statusCode, body: body);
      _lastEnv = env;
      _fail(env, 'Export returned JSON instead of a file.');
    }

    final filename = _parseFilenameFromContentDisposition(
          res.headers['content-disposition'],
        ) ??
        fallbackFilename ??
        'export.bin';

    return DownloadedFile(
      bytes: res.bodyBytes,
      filename: filename,
      contentType: contentType,
    );
  }

  // ───────────────── ACCOUNT / TRANSACTIONS ─────────────────

  /// GET /api/account/transactions/
  ///
  /// Returns a plain JSON object:
  /// { meta, summary?, items: [...] }
  Future<Map<String, dynamic>> getTransactions({
    String? dateFrom,
    String? dateTo,
    int limit = 50,
    String? cursor,
    bool includeSummary = true,
    bool includeFilters = true,
    bool includeBalance = true,
    String? currency,
    String? status,
    String? q,
    int? userId,
    int? sectorId,
    int? productId,
    int? brandId,
    bool? brandNotNull,
  }) async {
    final qp = <String, String>{
      if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
      if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
      'limit': '$limit',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      'include_summary': includeSummary ? '1' : '0',
      'include_filters': includeFilters ? '1' : '0',
      'include_balance': includeBalance ? '1' : '0',
      if (currency != null && currency.trim().isNotEmpty)
        'currency': currency.trim().toUpperCase(),
      if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      if (userId != null) 'user_id': '$userId',
      if (sectorId != null) 'sector_id': '$sectorId',
      if (productId != null) 'product_id': '$productId',
      if (brandId != null) 'brand_id': '$brandId',
      if (brandNotNull != null) 'brand_not_null': brandNotNull ? '1' : '0',
    };

    final url = Uri.parse('${AppEnv.base}account/transactions/')
        .replace(queryParameters: qp);
    return _getJsonMap(url, auth: true);
  }

  /// GET /api/account/transactions/<id>/
  Future<Map<String, dynamic>> getTransactionDetail({
    required int id,
    bool includeBalance = false,
  }) async {
    final url = Uri.parse('${AppEnv.base}account/transactions/$id/')
        .replace(queryParameters: {
      'include_balance': includeBalance ? '1' : '0',
    });
    return _getJsonMap(url, auth: true);
  }

  /// Export filtered transactions to Excel.
  ///
  /// Tries a few common endpoint shapes to tolerate backend route differences.
  Future<DownloadedFile> exportTransactionsExcel({
    String? dateFrom,
    String? dateTo,
    String? currency,
    String? status,
    String? q,
    int? userId,
    int? sectorId,
    int? productId,
    int? brandId,
    bool? brandNotNull,
    DownloadCancelToken? cancelToken,
  }) async {
    final qp = <String, String>{
      if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
      if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
      if (currency != null && currency.trim().isNotEmpty)
        'currency': currency.trim().toUpperCase(),
      if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      if (userId != null) 'user_id': '$userId',
      if (sectorId != null) 'sector_id': '$sectorId',
      if (productId != null) 'product_id': '$productId',
      if (brandId != null) 'brand_id': '$brandId',
      if (brandNotNull != null) 'brand_not_null': brandNotNull ? '1' : '0',
    };

    final fallbackFilename = [
          'transaction_history',
          if (dateFrom != null && dateFrom.isNotEmpty) dateFrom,
          if (dateTo != null && dateTo.isNotEmpty) dateTo,
        ].join('_') +
        '.xlsx';

    final candidates = <Uri>[
      Uri.parse('${AppEnv.base}account/transactions/export/excel/')
          .replace(queryParameters: qp),
      Uri.parse('${AppEnv.base}account/transactions/export/')
          .replace(queryParameters: qp),
      Uri.parse('${AppEnv.base}account/transactions/excel/')
          .replace(queryParameters: qp),
    ];

    Object? lastError;
    for (var i = 0; i < candidates.length; i++) {
      final url = candidates[i];
      try {
        return await _getBinary(
          url,
          auth: true,
          fallbackFilename: fallbackFilename,
          cancelToken: cancelToken,
        );
      } catch (e) {
        lastError = e;
        final msg = e.toString().toLowerCase();
        final isLast = i == candidates.length - 1;
        final looksLike404 = msg.contains('404') || msg.contains('not found');
        if (!looksLike404 || isLast) rethrow;
      }
    }

    throw Exception(lastError?.toString() ?? 'Failed to export Excel file.');
  }

  /// GET /api/account/dashboard/
  ///
  /// Returns a plain JSON object:
  /// { meta, data: { ...top lists... } }
  Future<Map<String, dynamic>> getDashboard({
    String? dateFrom,
    String? dateTo,
    String? currency,
    String? status,
    int top = 10,
    int? userId,
    String? userIds,
  }) async {
    final safeTop = top < 1 ? 1 : (top > 50 ? 50 : top);
    final qp = <String, String>{
      if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
      if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
      if (currency != null && currency.trim().isNotEmpty)
        'currency': currency.trim().toUpperCase(),
      if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
      'top': '$safeTop',
      if (userId != null) 'user_id': '$userId',
      if (userIds != null && userIds.trim().isNotEmpty)
        'user_ids': userIds.trim(),
    };

    final url = Uri.parse('${AppEnv.base}account/dashboard/')
        .replace(queryParameters: qp);
    return _getJsonMap(url, auth: true);
  }

  Future<Map<String, dynamic>> _sendJsonMap(
    Uri url, {
    required String method,
    bool auth = false,
    Map<String, dynamic>? body,
  }) async {
    if (auth) await _ensureTokenLoaded();

    late final http.Response res;
    switch (method.toUpperCase()) {
      case 'POST':
        res = await http.post(
          url,
          headers: _jsonHeaders(auth: auth),
          body: body == null ? null : jsonEncode(body),
        );
        break;
      case 'PATCH':
        res = await http.patch(
          url,
          headers: _jsonHeaders(auth: auth),
          body: body == null ? null : jsonEncode(body),
        );
        break;
      case 'DELETE':
        res = await http.delete(
          url,
          headers: _jsonHeaders(auth: auth),
          body: body == null ? null : jsonEncode(body),
        );
        break;
      case 'GET':
        res = await http.get(url, headers: _jsonHeaders(auth: auth));
        break;
      default:
        throw Exception('Unsupported method: $method');
    }

    final text = _bodyText(res);
    Map<String, dynamic> parsed = const <String, dynamic>{};
    if (text.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) {
          parsed = decoded;
        } else if (decoded is Map) {
          parsed = decoded.cast<String, dynamic>();
        } else {
          parsed = <String, dynamic>{'data': decoded};
        }
      } catch (_) {
        parsed = <String, dynamic>{'detail': text};
      }
    }

    if (res.statusCode == 401) {
      await logout();
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final env = ApiEnvelope(status: res.statusCode, body: parsed);
      _lastEnv = env;
      _fail(env, 'Request failed (HTTP ${env.status}).');
    }

    return parsed;
  }

  // ───────────────── WORKSPACE OPS ─────────────────

  Future<Map<String, dynamic>> getWorkspaceStatus() {
    final url = Uri.parse('${AppEnv.base}account/workspace-status/');
    return _sendJsonMap(url, method: 'GET', auth: true);
  }

  Future<Map<String, dynamic>> getWorkspaceAuditSummary({
    bool verifyRemote = false,
    int limit = 200,
    int sampleLimit = 20,
  }) {
    final safeLimit = limit < 1 ? 1 : (limit > 10000 ? 10000 : limit);
    final safeSampleLimit = sampleLimit < 1 ? 1 : (sampleLimit > 500 ? 500 : sampleLimit);
    final qp = <String, String>{
      if (verifyRemote) 'verify_remote': '1',
      'limit': '$safeLimit',
      'sample_limit': '$safeSampleLimit',
    };
    final url = Uri.parse('${AppEnv.base}account/workspace-audit-summary/')
        .replace(queryParameters: qp);
    return _sendJsonMap(url, method: 'GET', auth: true);
  }

  // ───────────────── ONLINE / USER BRAND PROFIT ─────────────────

  Future<Map<String, dynamic>> getUserBrandProfitFilters({
    int? groupId,
    int? sectorId,
    int? categoryId,
    int? productId,
    int? productTypeId,
    int? brandId,
  }) {
    final qp = <String, String>{
      if (groupId != null) 'group_id': '$groupId',
      if (sectorId != null) 'sector_id': '$sectorId',
      if (categoryId != null) 'category_id': '$categoryId',
      if (productId != null) 'product_id': '$productId',
      if (productTypeId != null) 'product_type_id': '$productTypeId',
      if (brandId != null) 'brand_id': '$brandId',
    };
    final url = Uri.parse('${AppEnv.onlineBase}user-brand-profit/filters/')
        .replace(queryParameters: qp.isEmpty ? null : qp);
    return _sendJsonMap(url, method: 'GET', auth: true);
  }

  Future<Map<String, dynamic>> getUserBrandProfitList({
    int? groupId,
    int? userId,
    List<int>? userIds,
    int? sectorId,
    int? categoryId,
    int? productId,
    int? productTypeId,
    int? brandId,
    bool? deactivated,
    String? search,
    int page = 1,
    int pageSize = 20,
  }) {
    final qp = <String, String>{
      if (groupId != null) 'group_id': '$groupId',
      if (userId != null) 'user_id': '$userId',
      if (userIds != null && userIds.isNotEmpty) 'user_ids': userIds.join(','),
      if (sectorId != null) 'sector_id': '$sectorId',
      if (categoryId != null) 'category_id': '$categoryId',
      if (productId != null) 'product_id': '$productId',
      if (productTypeId != null) 'product_type_id': '$productTypeId',
      if (brandId != null) 'brand_id': '$brandId',
      if (deactivated != null) 'deactivated': deactivated ? 'true' : 'false',
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      'page': '$page',
      'page_size': '$pageSize',
    };
    final url = Uri.parse('${AppEnv.onlineBase}user-brand-profit/')
        .replace(queryParameters: qp);
    return _sendJsonMap(url, method: 'GET', auth: true);
  }

  Future<Map<String, dynamic>> bulkUpsertUserBrandProfit({
    int? groupId,
    int? userId,
    List<int>? userIds,
    int? sectorId,
    int? categoryId,
    int? productId,
    int? productTypeId,
    int? brandId,
    required String profitPercentage,
    required String sellingProfitPercentage,
    bool overrideExisting = false,
  }) {
    final url = Uri.parse('${AppEnv.onlineBase}user-brand-profit/bulk-upsert/');
    return _sendJsonMap(
      url,
      method: 'POST',
      auth: true,
      body: <String, dynamic>{
        if (groupId != null) 'group_id': groupId,
        if (userId != null) 'user_id': userId,
        if (userIds != null && userIds.isNotEmpty) 'user_ids': userIds,
        if (sectorId != null) 'sector_id': sectorId,
        if (categoryId != null) 'category_id': categoryId,
        if (productId != null) 'product_id': productId,
        if (productTypeId != null) 'product_type_id': productTypeId,
        if (brandId != null) 'brand_id': brandId,
        'profit_percentage': profitPercentage.trim(),
        'selling_profit_percentage': sellingProfitPercentage.trim(),
        'override_existing': overrideExisting,
      },
    );
  }

  Future<Map<String, dynamic>> getUserBrandProfitDetail(int id) {
    final url = Uri.parse('${AppEnv.onlineBase}user-brand-profit/$id/');
    return _sendJsonMap(url, method: 'GET', auth: true);
  }

  Future<Map<String, dynamic>> updateUserBrandProfit(
    int id,
    Map<String, dynamic> body,
  ) {
    final url = Uri.parse('${AppEnv.onlineBase}user-brand-profit/$id/');
    return _sendJsonMap(url, method: 'PATCH', auth: true, body: body);
  }

  Future<void> deleteUserBrandProfit(int id) async {
    final url = Uri.parse('${AppEnv.onlineBase}user-brand-profit/$id/');
    await _sendJsonMap(url, method: 'DELETE', auth: true);
  }

  // ───────────────── NOTIFICATIONS ─────────────────

  Future<Map<String, dynamic>> getNotifications({
    int limit = 20,
    int offset = 0,
    bool unreadOnly = false,
    DateTime? since,
  }) {
    final safeLimit = limit < 1 ? 20 : (limit > 200 ? 200 : limit);
    final safeOffset = offset < 0 ? 0 : offset;
    final qp = <String, String>{
      'limit': '$safeLimit',
      'offset': '$safeOffset',
      if (unreadOnly) 'unread_only': 'true',
      if (since != null) 'since': since.toUtc().toIso8601String(),
    };
    final url =
        Uri.parse('${AppEnv.base}notifications/').replace(queryParameters: qp);
    return _sendJsonMap(url, method: 'GET', auth: true);
  }

  Future<Map<String, dynamic>> getNotificationUnreadCount() {
    final url = Uri.parse('${AppEnv.base}notifications/unread-count/');
    return _sendJsonMap(url, method: 'GET', auth: true);
  }

  Future<Map<String, dynamic>> pollNotifications() {
    final url = Uri.parse('${AppEnv.base}notifications/poll/');
    return _sendJsonMap(url, method: 'GET', auth: true);
  }

  Future<Map<String, dynamic>> markNotificationsRead(List<int> ids) {
    final url = Uri.parse('${AppEnv.base}notifications/mark-read/');
    return _sendJsonMap(
      url,
      method: 'POST',
      auth: true,
      body: <String, dynamic>{'ids': ids},
    );
  }

  Future<Map<String, dynamic>> markAllNotificationsRead() {
    final url = Uri.parse('${AppEnv.base}notifications/mark-all-read/');
    return _sendJsonMap(url, method: 'POST', auth: true);
  }

  Future<Map<String, dynamic>> markSingleNotificationRead(int id) {
    final url = Uri.parse('${AppEnv.base}notifications/mark-read/$id/');
    return _sendJsonMap(url, method: 'POST', auth: true);
  }

  Future<Map<String, dynamic>> deleteNotification(int id) {
    final url = Uri.parse('${AppEnv.base}notifications/delete/$id/');
    return _sendJsonMap(url, method: 'POST', auth: true);
  }

  Future<Map<String, dynamic>> runNotificationAction(
    String rawUrl, {
    String method = 'POST',
  }) {
    final url = _resolveAgainstApiBase(rawUrl);
    final normalizedMethod =
        method.trim().isEmpty ? 'POST' : method.trim().toUpperCase();
    return _sendJsonMap(url, method: normalizedMethod, auth: true);
  }

  Uri _resolveAgainstApiBase(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      throw Exception('Notification action URL is empty.');
    }
    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.hasScheme) {
      return parsed;
    }
    final baseUri = Uri.parse(AppEnv.base);
    return baseUri.resolve(trimmed);
  }
}
