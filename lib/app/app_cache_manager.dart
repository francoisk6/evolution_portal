import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Centralized cache configuration for remote images.
///
/// This caches files on disk (and leverages Flutter's in-memory image cache).
/// After the first download, subsequent loads are typically near-instant.
class AppCacheManager {
  static final CacheManager images = CacheManager(
    Config(
      'evolutionImagesCache',
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 750,
    ),
  );
}
