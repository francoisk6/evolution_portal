import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

bool _isMobilePlatform() {
  if (kIsWeb) return false;

  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return true;
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.fuchsia:
      return false;
  }
}

ThemeData buildV2LightTheme() {
  const bg = Colors.white;
  const surface = Colors.white;

  final isMobile = _isMobilePlatform();
  final scrollbarThickness = isMobile ? 1.0 : 6.0;

  final scheme = const ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF1E88E5),
    onPrimary: Colors.white,
    secondary: Color(0xFF43A047),
    onSecondary: Colors.white,
    surface: surface,
    onSurface: Color(0xFF3C3E40),
    error: Colors.red,
    onError: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    appBarTheme: const AppBarTheme(
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Color(0xFF333333),
      ),
    ),
    cardTheme: CardThemeData(
      color: surface.withValues(alpha: 0.9),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFFE4E6E8),
      thickness: 1,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      elevation: 12,
      showUnselectedLabels: true,
      type: BottomNavigationBarType.fixed,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbVisibility: const WidgetStatePropertyAll(true),
      trackVisibility: const WidgetStatePropertyAll(true),
      interactive: true,
      radius: Radius.circular(isMobile ? 3 : 10),
      thickness: WidgetStatePropertyAll<double>(scrollbarThickness),
      minThumbLength: isMobile ? 18 : 44,
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (isMobile) {
          if (states.contains(WidgetState.dragged)) {
            return const Color(0xFFB8B8B8).withValues(alpha: 0.32);
          }
          if (states.contains(WidgetState.hovered)) {
            return const Color(0xFFBDBDBD).withValues(alpha: 0.22);
          }
          return const Color(0xFFC6C6C6).withValues(alpha: 0.12);
        }

        if (states.contains(WidgetState.dragged)) {
          return const Color(0xFFB0B0B0).withValues(alpha: 0.95);
        }
        if (states.contains(WidgetState.hovered)) {
          return const Color(0xFFB8B8B8).withValues(alpha: 0.88);
        }
        return const Color(0xFFC2C2C2).withValues(alpha: 0.80);
      }),
      trackColor: WidgetStatePropertyAll(
        isMobile
            ? const Color(0xFFEAEAEA).withValues(alpha: 0.03)
            : const Color(0xFFE6E6E6).withValues(alpha: 0.70),
      ),
      trackBorderColor: WidgetStatePropertyAll(
        isMobile
            ? const Color(0xFFE0E0E0).withValues(alpha: 0.03)
            : const Color(0xFFDADADA).withValues(alpha: 0.65),
      ),
      crossAxisMargin: isMobile ? 0 : 2,
      mainAxisMargin: isMobile ? 0 : 2,
    ),
  );
}
