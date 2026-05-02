import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app/app_env.dart';
import '../data/models/version_info.dart';
import '../utils/version_compare.dart';
import 'app_info_provider.dart';
import 'version_provider.dart';

class ForceUpdateInfo {
  final String currentVersion;
  final String requiredVersion;
  final String? storeUrl;
  final String message;
  final String sourceLabel;
  final bool isWeb;

  const ForceUpdateInfo({
    required this.currentVersion,
    required this.requiredVersion,
    required this.storeUrl,
    required this.message,
    required this.sourceLabel,
    required this.isWeb,
  });

  String get actionLabel => isWeb ? 'Reload now' : 'Update now';
  String get title => isWeb ? 'Reload required' : 'Update required';
}

final forceUpdateProvider = FutureProvider<ForceUpdateInfo?>((ref) async {
  final packageInfo = await ref.watch(packageInfoProvider.future);

  VersionInfo versionInfo;
  try {
    versionInfo = await ref.watch(versionInfoProvider.future);
  } catch (_) {
    // Fail open: never lock the app because the version endpoint failed.
    return null;
  }

  final installed = ParsedAppVersion.parse(
    _composeInstalledVersion(packageInfo),
  );
  final required = ParsedAppVersion.parse(
    kIsWeb ? versionInfo.webVersion : versionInfo.guiVersion,
  );

  if (!installed.isValid || !required.isValid) return null;

  final needsUpdate = compareParsedVersions(installed, required) < 0;
  if (!needsUpdate) return null;

  final defaultMessage = kIsWeb
      ? 'A newer web version is available. Please reload this page to continue.'
      : 'A newer version is required to continue using the app.';

  return ForceUpdateInfo(
    currentVersion: installed.display,
    requiredVersion: required.display,
    storeUrl: _resolveStoreUrl(versionInfo, packageInfo),
    message: (versionInfo.updateMessage ?? '').trim().isNotEmpty
        ? versionInfo.updateMessage!.trim()
        : defaultMessage,
    sourceLabel: kIsWeb ? 'Web Version' : 'GUI Version',
    isWeb: kIsWeb,
  );
});

String _composeInstalledVersion(PackageInfo info) {
  final version = info.version.trim();
  final build = info.buildNumber.trim();
  if (build.isEmpty) return version;
  if (version.isEmpty) return build;
  return '$version ($build)';
}

String? _resolveStoreUrl(VersionInfo info, PackageInfo packageInfo) {
  final backendPlatformUrl = switch (defaultTargetPlatform) {
    TargetPlatform.iOS => info.iosStoreUrl,
    TargetPlatform.android => info.androidStoreUrl,
    _ => null,
  };

  final backendAny = info.storeUrl;
  final envPlatformUrl = switch (defaultTargetPlatform) {
    TargetPlatform.iOS => AppEnv.iosStoreUrl,
    TargetPlatform.android => AppEnv.androidStoreUrl,
    _ => null,
  };

  final fallbacks = <String?>[
    backendPlatformUrl,
    backendAny,
    envPlatformUrl,
    AppEnv.storeUrl,
  ];
  for (final candidate in fallbacks) {
    if ((candidate ?? '').trim().isNotEmpty) return candidate!.trim();
  }

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    final packageName = packageInfo.packageName.trim();
    if (packageName.isNotEmpty) {
      return 'https://play.google.com/store/apps/details?id=$packageName';
    }
  }

  return null;
}
