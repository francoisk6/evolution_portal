import 'package:flutter/material.dart';

import '../app/app_env.dart';
import 'brand_wordmark.dart';

/// Header brand mark for the active workspace.
///
/// Resolution order:
///   1. `assets/logos/<slug>.png` — per-workspace artwork, if supplied
///   2. `assets/logo.png` — the original Evolution mark, for Main only
///   3. [BrandWordmark] — styled text of the workspace name
///
/// The text fallback exists because falling back to Evolution's logo would put
/// the wrong brand in a tenant's app. A tenant with no artwork gets its own
/// name instead.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.height = 28});

  final double height;

  @override
  Widget build(BuildContext context) {
    final slug = AppEnv.selectedWorkspace.slug.toLowerCase();
    // In a standalone build the baked workspace IS the tenant, so guard on
    // the lock too: without this a locked DMP build would resolve 'main' and
    // render Evolution's logo inside a tenant app.
    final isMain =
        !AppEnv.isBuildLocked && slug == AppEnv.mainSlug.toLowerCase();

    // Main keeps the existing asset untouched, so the current brand is
    // pixel-identical to before.
    if (isMain) {
      return Image.asset(
        'assets/logo.png',
        height: height,
        errorBuilder: (_, __, ___) => BrandWordmark(fontSize: height * 0.78),
      );
    }

    return Image.asset(
      'assets/logos/$slug.png',
      height: height,
      // Thrown when the tenant has no artwork yet; show its name instead.
      errorBuilder: (_, __, ___) => BrandWordmark(fontSize: height * 0.78),
    );
  }
}
