import 'package:flutter/material.dart';

/// Per-page navigation configuration for the top-level back/next controls.
///
/// Defaults (unless overridden by a page):
/// - back is shown on all non-home pages and routes to /home
/// - next is hidden
///
/// Home page always shows no back/next.
@immutable
class PageNavConfig {
  /// Whether to show the Back control.
  final bool showBack;

  /// Target location for Back (used when [onBack] is null).
  /// If null, falls back to '/home'.
  final String? backTo;

  /// Optional custom back handler.
  final VoidCallback? onBack;

  /// Whether to show the Next control.
  final bool showNext;

  /// Target location for Next (used when [onNext] is null).
  final String? nextTo;

  /// Optional custom next handler (supports async; used for "submit then go" flows).
  final Future<void> Function()? onNext;

  /// Enable/disable the Next control (useful when selection is required).
  final bool nextEnabled;

  const PageNavConfig({
    this.showBack = true,
    this.backTo,
    this.onBack,
    this.showNext = false,
    this.nextTo,
    this.onNext,
    this.nextEnabled = true,
  });
}

/// Global notifier consumed by AppScaffold.
///
/// Pages publish their configuration via the [PageNav] widget.
final ValueNotifier<PageNavConfig?> pageNav = ValueNotifier<PageNavConfig?>(null);

/// Wrap a page body with this to publish a [PageNavConfig] while the page is mounted.
class PageNav extends StatefulWidget {
  final PageNavConfig config;
  final Widget child;

  const PageNav({super.key, required this.config, required this.child});

  @override
  State<PageNav> createState() => _PageNavState();
}

class _PageNavState extends State<PageNav> {
  PageNavConfig? _published;

  @override
  void initState() {
    super.initState();
    _publish(widget.config);
  }

  @override
  void didUpdateWidget(covariant PageNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) {
      _publish(widget.config);
    }
  }

  void _publish(PageNavConfig cfg) {
    _published = cfg;
    // Defer to end of frame to avoid "set during build" edge cases.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      pageNav.value = cfg;
    });
  }

  @override
  void dispose() {
    // Only clear if we are still the current publisher.
    if (pageNav.value == _published) {
      pageNav.value = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
