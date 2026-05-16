import 'package:flutter/foundation.dart' show kIsWeb;
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
  /// **************************************************************************************

  static const String _workspacePrefsKey = 'selected_workspace_slug';

  /// Public web root used by Flutter Web workspace auto-selection.
  ///
  /// Rules:
  /// - evolution-portal.com / www.evolution-portal.com => Main
  /// - <workspace-slug>.evolution-portal.com => matching workspace
  /// - API host aliases below are also accepted for safety.
  static const String webRootHost = 'evolution-portal.com';

  static const List<WorkspaceConfig> workspaces = <WorkspaceConfig>[
    WorkspaceConfig(
      slug: 'main',
      displayName: 'Main',
      apiBaseUrl: envMode == AppEnvMode.prod
          ? 'https://api.evolution-portal.com'
          : 'http://localhost:8010',
    ),
    WorkspaceConfig(
      slug: 'horizon',
      displayName: 'Horizon',
      apiBaseUrl: envMode == AppEnvMode.prod
          ? 'https://horizonapi.evolution-portal.com'
          : 'http://localhost:8810',
    ),
  ];

  static WorkspaceConfig get defaultWorkspace => workspaces.first;

  static WorkspaceConfig _selectedWorkspace = defaultWorkspace;
  static bool _webHostWorkspaceLocked = false;

  static WorkspaceConfig get selectedWorkspace => _selectedWorkspace;
  static bool get isWebHostWorkspaceLocked => _webHostWorkspaceLocked;

  /// Runtime API base with the existing app contract: must end with /api/.
  static String get base => _selectedWorkspace.apiPathBase;
  static String get authBase => '${base}auth/';
  static String get balanceBase => '${base}balance/';
  static String get homeBase => '${base}home/';
  static String get onlineBase => '${base}online/';

  static Future<void> initWorkspace() async {
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

  static Future<void> selectWorkspace(String slug) async {
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
    // horizon.evolution-portal.com => workspace slug "horizon".
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
