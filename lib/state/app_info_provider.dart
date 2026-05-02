import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Raw platform package metadata.
final packageInfoProvider = FutureProvider<PackageInfo>((ref) async {
  return PackageInfo.fromPlatform();
});

/// Installed app version as reported by the platform.
///
/// Format: "<version> (<buildNumber>)" e.g. "2.0.1 (45)".
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await ref.watch(packageInfoProvider.future);
  final version = info.version.trim();
  final build = info.buildNumber.trim();
  if (build.isEmpty) return version;
  if (version.isEmpty) return build;
  return '$version ($build)';
});
