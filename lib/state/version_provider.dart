import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/version_info.dart';
import '../services/api_service.dart';

/// Loads backend API / GUI / WEB versions from GET /api/version/
final versionInfoProvider = FutureProvider<VersionInfo>((ref) async {
  return ApiService.instance.getVersionInfo();
});
