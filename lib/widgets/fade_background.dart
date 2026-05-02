import 'package:flutter/material.dart';

class FadeBackground extends StatelessWidget {
  const FadeBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Your real JPEG — if it breaks, fall back to a soft gradient.
        Image.asset(
          'assets/backgrounds/tech_bg_3.jpg',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFF5F6F8), Color(0xFFE9ECEF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        ),
        // Very light transparency (keeps your V2 look)
        ColoredBox(color: Colors.white.withValues(alpha: 0.82)),
      ],
    );
  }
}
