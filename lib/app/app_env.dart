import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show kIsWeb, debugPrint, defaultTargetPlatform, TargetPlatform;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum AppEnvMode { dev, prod }

class WorkspaceConfig {
  final String slug;
  final String displayName;

  /// Workspace API root, without the trailing /api path.
  /// Example: https://api.evolution-portal.com
  final String apiBaseUrl;

  const WorkspaceConfig({
    required this.slug,
    required this.displayName,
    required this.apiBaseUrl,
  });

  String get apiRoot => _trimRightSlash(apiBaseUrl);
  String get apiPathBase => '${_trimRightSlash(apiBaseUrl)}/api/';

  static String _trimRightSlash(String value) =>
      value.trim().replaceFirst(RegExp(r'/+$'), '');
}

class AppEnv {
  AppEnv._();

  /// Switch to [AppEnvMode.dev] for local development, [AppEnvMode.prod] for release builds.
  /// **************************************************************************************

  static const AppEnvMode envMode = AppEnvMode.prod;

  /// **************************************************************************************
  /// ****************************e**********************************************************

  static const String _workspacePrefsKey = 'selected_workspace_slug';
  static const String _workspaceCachePrefsKey = 'workspace_list_cache';

  /// Build-time workspace lock, for standalone branded builds:
  ///
  ///   flutter build apk --flavor dmp \
  ///     --dart-define=WORKSPACE_SLUG=dmp \
  ///     --dart-define=WORKSPACE_NAME=DMP \
  ///     --dart-define=API_BASE_URL=https://dmpapi.evolution-portal.com
  ///
  /// A locked build talks only to its own workspace: no switcher, and no call
  /// to any other host. Workspace API domains are fixed, so there is nothing to
  /// resolve at runtime and nothing to depend on being reachable.
  static const String _buildWorkspaceSlug =
      String.fromEnvironment('WORKSPACE_SLUG');
  static const String _buildWorkspaceName =
      String.fromEnvironment('WORKSPACE_NAME');
  static const String _buildApiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// True when this build was pinned to a single workspace at compile time.
  static bool get isBuildLocked =>
      _buildWorkspaceSlug.isNotEmpty && _buildApiBaseUrl.isNotEmpty;

  /// Public web root used by Flutter Web workspace auto-selection.
  ///
  /// Rules:
  /// - evolution-portal.com / www.evolution-portal.com => Main
  /// - <workspace-slug>.evolution-portal.com => matching workspace
  /// - API host aliases below are also accepted for safety.
  static const String webRootHost = 'evolution-portal.com';

  // Android emulator can't reach the host via 'localhost' — use 10.0.2.2.
  // Physical Android device: change this to your machine's LAN IP instead.
  static String get _devHost {
    if (kIsWeb) return 'localhost';
    if (defaultTargetPlatform == TargetPlatform.android) return '10.0.2.2';
    return 'localhost';
  }

  /// Compile-time fallback. Also the seed the app starts from before any
  /// cached or fetched list is available, so a cold start with no network
  /// still reaches Main.
  static WorkspaceConfig get _bakedWorkspace {
    if (isBuildLocked) {
      return WorkspaceConfig(
        slug: _buildWorkspaceSlug,
        displayName: _buildWorkspaceName.isNotEmpty
            ? _buildWorkspaceName
            : _buildWorkspaceSlug,
        apiBaseUrl: _buildApiBaseUrl,
      );
    }
    return WorkspaceConfig(
      slug: 'main',
      displayName: 'Main',
      apiBaseUrl: envMode == AppEnvMode.prod
          ? 'https://api.evolution-portal.com'
          : 'http://$_devHost:8010',
    );
  }

  static List<WorkspaceConfig> _workspaces = <WorkspaceConfig>[_bakedWorkspace];

  static List<WorkspaceConfig> get workspaces =>
      List<WorkspaceConfig>.unmodifiable(_workspaces);

  static WorkspaceConfig get defaultWorkspace => _workspaces.first;

  static WorkspaceConfig _selectedWorkspace = defaultWorkspace;
  static bool _webHostWorkspaceLocked = false;

  static WorkspaceConfig get selectedWorkspace => _selectedWorkspace;
  static bool get isWebHostWorkspaceLocked => _webHostWorkspaceLocked;

  /// True when the user must not be offered a workspace choice: either the web
  /// host pins it, or this is a standalone branded build.
  static bool get isWorkspaceLocked => _webHostWorkspaceLocked || isBuildLocked;

  /// Slug of the product's own workspace (the non-tenant one).
  static String get mainSlug => _bakedWorkspace.slug;

  /// Product brand shown in the header when no tenant name applies.
  /// Overridable per build: --dart-define=BRAND_NAME=...
  static const String _brandName =
      String.fromEnvironment('BRAND_NAME', defaultValue: 'Evolution');

  /// Name rendered by the header wordmark.
  ///
  /// A standalone build always shows its own workspace name. The
  /// multi-workspace build keeps the product brand while Main is selected and
  /// shows the workspace name otherwise, so a switch is visible in the header.
  static String get brandName {
    if (isBuildLocked) {
      return _buildWorkspaceName.isNotEmpty
          ? _buildWorkspaceName
          : _buildWorkspaceSlug;
    }
    if (_selectedWorkspace.slug.toLowerCase() ==
        _bakedWorkspace.slug.toLowerCase()) {
      return _brandName;
    }
    return _selectedWorkspace.displayName;
  }

  /// True when a switcher is worth showing at all.
  static bool get canSwitchWorkspace =>
      !isWorkspaceLocked && _workspaces.length > 1;

  /// Runtime API base with the existing app contract: must end with /api/.
  static String get base => _selectedWorkspace.apiPathBase;
  static String get authBase => '${base}auth/';
  static String get balanceBase => '${base}balance/';
  static String get homeBase => '${base}home/';
  static String get onlineBase => '${base}online/';

  static String get batchBase => '${base}batch/';

  static String get adminBase => '${_selectedWorkspace.apiRoot}/admin/';
  static String get adminAutologinUrl =>
      '${_selectedWorkspace.apiRoot}/admin-autologin/';

  static Future<void> initWorkspace() async {
    // Standalone branded build: exactly one workspace, no switching, and no
    // call to any other host.
    if (isBuildLocked) {
      _workspaces = <WorkspaceConfig>[_bakedWorkspace];
      _selectedWorkspace = _workspaces.first;
      _webHostWorkspaceLocked = false;
      return;
    }

    // Reset to the baked seed first so init is idempotent: a second call with
    // an unreadable cache must fall back cleanly rather than inherit whatever
    // the previous call left behind.
    _workspaces = <WorkspaceConfig>[_bakedWorkspace];

    // Restore the last known list, so a cold start with no network still offers
    // whatever was available last time instead of collapsing to Main.
    await _loadCachedWorkspaces();

    final hostWorkspace = _workspaceFromCurrentWebHost();
    if (hostWorkspace != null) {
      _selectedWorkspace = hostWorkspace;
      _webHostWorkspaceLocked = true;
      return;
    }

    _webHostWorkspaceLocked = false;
    final prefs = await SharedPreferences.getInstance();
    final savedSlug = prefs.getString(_workspacePrefsKey);
    _selectedWorkspace = workspaceBySlug(savedSlug) ?? defaultWorkspace;
  }

  /// Refresh the workspace list from the server.
  ///
  /// Deliberately best-effort: it never throws and never blocks login. A
  /// failure just leaves the cached (or baked) list in place. Returns whether
  /// the list was actually updated.
  static Future<bool> refreshWorkspaces({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    // A locked build has nothing to discover, and dev mode points at localhost
    // ports the server knows nothing about.
    if (isBuildLocked || envMode != AppEnvMode.prod) return false;

    final uri = Uri.parse('${_bakedWorkspace.apiRoot}/api/workspaces/');
    try {
      final response = await http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(timeout);
      if (response.statusCode != 200) return false;

      final parsed = _parseWorkspaces(response.body);
      if (parsed.isEmpty) return false;

      _workspaces = parsed;
      _reconcileSelection();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_workspaceCachePrefsKey, response.body);
      return true;
    } catch (error) {
      debugPrint('AppEnv.refreshWorkspaces failed: $error');
      return false;
    }
  }

  static Future<void> _loadCachedWorkspaces() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_workspaceCachePrefsKey);
      if (cached == null || cached.isEmpty) return;
      final parsed = _parseWorkspaces(cached);
      if (parsed.isNotEmpty) _workspaces = parsed;
    } catch (error) {
      debugPrint('AppEnv._loadCachedWorkspaces failed: $error');
    }
  }

  static List<WorkspaceConfig> _parseWorkspaces(String body) {
    final result = <WorkspaceConfig>[];
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return result;
      final entries = decoded['workspaces'];
      if (entries is! List) return result;

      for (final entry in entries) {
        if (entry is! Map) continue;
        final slug = (entry['slug'] ?? '').toString().trim();
        final url = (entry['api_base_url'] ?? '').toString().trim();
        if (slug.isEmpty || url.isEmpty) continue;
        final name = (entry['name'] ?? '').toString().trim();
        result.add(WorkspaceConfig(
          slug: slug,
          displayName: name.isNotEmpty ? name : slug,
          apiBaseUrl: url,
        ));
      }
    } catch (error) {
      debugPrint('AppEnv._parseWorkspaces failed: $error');
    }
    return result;
  }

  /// Keep the current selection pointing at a workspace that still exists,
  /// picking up any change to its base URL. Falls back to the first entry when
  /// the selected workspace is gone from the list.
  static void _reconcileSelection() {
    final current = _selectedWorkspace.slug.toLowerCase();
    for (final workspace in _workspaces) {
      if (workspace.slug.toLowerCase() == current) {
        _selectedWorkspace = workspace;
        return;
      }
    }
    _selectedWorkspace = _workspaces.first;
  }

  static Future<void> selectWorkspace(String slug) async {
    // A locked build or a host-pinned web session must never change workspace.
    if (isBuildLocked) return;

    final next = workspaceBySlug(slug) ?? defaultWorkspace;
    _selectedWorkspace = next;

    if (_webHostWorkspaceLocked) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_workspacePrefsKey, next.slug);
  }

  static WorkspaceConfig? workspaceBySlug(String? slug) {
    if (slug == null || slug.trim().isEmpty) return null;
    final normalized = slug.trim().toLowerCase();
    for (final workspace in workspaces) {
      if (workspace.slug.toLowerCase() == normalized) return workspace;
    }
    return null;
  }

  static WorkspaceConfig? _workspaceFromCurrentWebHost() {
    if (!kIsWeb) return null;

    final host = Uri.base.host.trim().toLowerCase();
    if (_isLocalOrEmptyWebHost(host)) return null;

    // Root production web host must always use Main and must not allow manual
    // workspace switching on web.
    if (host == webRootHost || host == 'www.$webRootHost') {
      return defaultWorkspace;
    }

    // Keep the previous API-host safety behavior. This is useful if the web app
    // is ever opened through an API alias during testing/deployment.
    for (final workspace in workspaces) {
      final apiHost = Uri.tryParse(workspace.apiBaseUrl)?.host.toLowerCase();
      if (apiHost != null && apiHost.isNotEmpty && host == apiHost) {
        return workspace;
      }
    }

    // Production subdomain routing:
    // <slug>.evolution-portal.com => workspace with that slug, when one is
    // registered in [workspaces] above.
    final suffix = '.$webRootHost';
    if (host.endsWith(suffix)) {
      final subdomain = host.substring(0, host.length - suffix.length);
      if (subdomain.isEmpty || subdomain == 'www') {
        return defaultWorkspace;
      }

      final workspace = workspaceBySlug(subdomain);
      if (workspace != null) return workspace;
    }

    // Unknown web hosts keep the existing manual selector behavior. This keeps
    // localhost, staging, preview, and IP-based deployments flexible.
    return null;
  }

  static bool _isLocalOrEmptyWebHost(String host) {
    if (host.isEmpty || host == 'localhost' || host == '127.0.0.1') {
      return true;
    }
    if (host == '[::1]' || host == '::1') return true;
    return false;
  }

  /// Optional shared store URL fallback.
  ///
  /// Keep empty to let Android auto-build the Google Play URL from the package
  /// name. For iOS you should fill [iosStoreUrl] with the App Store link.
  static const String storeUrl = '';

  /// Optional platform-specific store URLs.
  static const String androidStoreUrl = '';
  static const String iosStoreUrl = '';

  /// How often the app should re-check the version endpoint while running.
  static const Duration forceUpdateCheckInterval = Duration(minutes: 2);
}
