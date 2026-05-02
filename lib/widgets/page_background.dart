import 'package:flutter/material.dart';

/// Shared page background:
/// - 15px vertical ribbon: #40B2D6
/// - then gradient to #D0EEEE
/// - then gradient to white
///
/// Wraps content without enforcing padding or layout.
class PageBackground extends StatelessWidget {
  const PageBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth <= 0) ? 1.0 : c.maxWidth;

        // As requested: 15px ribbon (#40B2D6) then fade to #D0EEEE then to white.
        const ribbonPx = 0.0;
        const fadeToPalePx = 0.0; // ribbon → #D0EEEE

        final ribbonStop = (ribbonPx / w).clamp(0.0, 1.0);
        final paleStop = ((ribbonPx + fadeToPalePx) / w).clamp(ribbonStop, 1.0);

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const [
                Color(0xFF40B2D6),
                Color(0xFF40B2D6),
                Color.fromARGB(255, 227, 248, 248),
                Color.fromARGB(255, 246, 248, 248),
              ],
              stops: [0.0, ribbonStop, paleStop, 1.0],
            ),
          ),
          child: child,
        );
      },
    );
  }
}
