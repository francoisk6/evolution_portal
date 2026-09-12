import 'package:flutter/material.dart';

import '../app/app_env.dart';

/// Text stand-in for the former `assets/logo.png` header wordmark.
///
/// The logo was a fixed image, so every build showed "Evolution" regardless of
/// which workspace was in use. Rendering it as text lets the header carry the
/// active workspace name — a standalone DMP build shows "DMP" — with no
/// per-tenant image asset to produce and ship.
///
/// This is a fallback only: a workspace with artwork in assets/logos/ uses that
/// instead (see [BrandLogo]). It deliberately does not try to imitate the
/// Evolution logo - that artwork's weight and glow are not reproducible in
/// text, and the attempt read worse than an honest label.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.fontSize = 22});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    // The artwork was navy-on-light; that fill vanishes on a dark app bar, so
    // invert it there and keep the same halo.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? const Color(0xFFEAF6FF) : const Color(0xFF0B1B4D);

    return Text(
      AppEnv.brandName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontWeight: FontWeight.w900,
        fontSize: fontSize,
        letterSpacing: -0.2,
        height: 1.15,
        color: fill,
        // Painted back to front: broad haze, then a tight bright halo, then a
        // dark offset that reads as an extrude under the letterforms.
        shadows: const [
          Shadow(color: Color(0x8029B6F6), blurRadius: 24),
          Shadow(color: Color(0xCC4FC3F7), blurRadius: 11),
          Shadow(color: Color(0xFF5FD0FF), blurRadius: 4),
          Shadow(color: Color(0xFF061030), offset: Offset(1.2, 1.2)),
        ],
      ),
    );
  }
}
