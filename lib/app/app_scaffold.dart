import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:evolution_portal/widgets/top_bar.dart';
import 'package:evolution_portal/widgets/left_menu_drawer.dart';
//import 'package:evolution_portal/widgets/fade_background.dart';
import 'package:evolution_portal/widgets/currency_card_strip.dart';
import 'package:evolution_portal/widgets/page_background.dart';
import 'package:evolution_portal/widgets/page_nav.dart';
import 'package:evolution_portal/widgets/page_action_bar.dart'
    show pageActions, PageAction; // listen only
import 'package:evolution_portal/widgets/bottom_nav.dart';
import 'app_scroll_behavior.dart';
import '../state/current_balance_provider.dart';
import '../state/session_provider.dart';
import '../state/page_refresh_provider.dart';
import '../state/nav_history_provider.dart';
import '../routing/route_names.dart';

class AppScaffold extends ConsumerStatefulWidget {
  final Widget body;
  final String location;
  const AppScaffold({super.key, required this.body, required this.location});

  @override
  ConsumerState<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends ConsumerState<AppScaffold> {
  bool _showScrollToTop = false;
  ScrollableState? _activeScrollable;
  ScrollableState? _lastPageScrollable;
  ScrollPosition? _boundScrollPosition;

  bool _navNextBusy = false;

  GoRouter? _router;
  bool _routerBound = false;
  String? _lastRouterLocation;

  final GlobalKey _scrollRootKey = GlobalKey();

  static const double _scrollToTopThreshold = 120;
  static const double _arrowScrollStep = 72;
  static const double _horizontalArrowScrollStep = 96;
  static const double _pageScrollFactor = 0.9;

  bool _computeScrollToTopVisibility({ScrollPosition? position}) {
    final hasActivePopup =
        EvolutionScrollRegistry.activePopupContext.value != null;
    if (hasActivePopup) return false;

    final pos = position ?? _boundScrollPosition;
    if (pos == null) return false;

    try {
      return pos.hasContentDimensions &&
          pos.maxScrollExtent > 0 &&
          pos.pixels > _scrollToTopThreshold;
    } catch (_) {
      return false;
    }
  }

  void _updateScrollToTopVisibility({ScrollPosition? position}) {
    if (!mounted) return;
    final shouldShow = _computeScrollToTopVisibility(position: position);
    if (shouldShow != _showScrollToTop) {
      setState(() => _showScrollToTop = shouldShow);
    }
  }

  void _handleBoundScrollPositionChanged() {
    _updateScrollToTopVisibility();
  }

  bool _isScrollableUsable(ScrollableState? scrollable) {
    if (scrollable == null) return false;
    try {
      final _ = scrollable.position;
      return true;
    } catch (_) {
      return false;
    }
  }

  void _bindActiveScrollable(ScrollableState? scrollable, {
    bool updateVisibility = true,
  }) {
    _activeScrollable = scrollable;

    final hasActivePopup =
        EvolutionScrollRegistry.activePopupContext.value != null;
    if (!hasActivePopup && scrollable != null && _isScrollableUsable(scrollable)) {
      _lastPageScrollable = scrollable;
    }

    ScrollPosition? nextPosition;
    try {
      nextPosition = scrollable?.position;
    } catch (_) {
      nextPosition = null;
    }

    if (!identical(_boundScrollPosition, nextPosition)) {
      try {
        _boundScrollPosition?.removeListener(_handleBoundScrollPositionChanged);
      } catch (_) {}
      _boundScrollPosition = nextPosition;
      try {
        _boundScrollPosition?.addListener(_handleBoundScrollPositionChanged);
      } catch (_) {}
    }

    if (updateVisibility) {
      _updateScrollToTopVisibility(position: nextPosition);
    }
  }

  void _restorePageScrollableAfterPopup() {
    if (!mounted) return;

    final cached = _lastPageScrollable;
    if (_isScrollableUsable(cached)) {
      _bindActiveScrollable(cached, updateVisibility: false);
      _updateScrollToTopVisibility(position: cached!.position);
      return;
    }

    final vertical = _resolveScrollable(preferredAxis: Axis.vertical);
    if (vertical != null) {
      _bindActiveScrollable(vertical, updateVisibility: false);
      _updateScrollToTopVisibility(position: vertical.position);
      return;
    }

    _primeDefaultScrollable();
    _updateScrollToTopVisibility();
  }

  void _handlePopupContextChanged() {
    final hasActivePopup =
        EvolutionScrollRegistry.activePopupContext.value != null;

    if (hasActivePopup) {
      _updateScrollToTopVisibility();
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _restorePageScrollableAfterPopup();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _restorePageScrollableAfterPopup();
      });
    });
  }

  bool _onScrollNotification(ScrollNotification n) {
    // Ignore non-vertical scrollables (e.g., horizontal action bars) for the FAB.
    if (n.metrics.axis == Axis.vertical) {
      final ctx = n.context;
      if (ctx != null) {
        _bindActiveScrollable(Scrollable.maybeOf(ctx), updateVisibility: false);
      }

      final hasScroll = n.metrics.maxScrollExtent > 0;
      final shouldShow =
          EvolutionScrollRegistry.activePopupContext.value == null &&
          hasScroll &&
          n.metrics.pixels > _scrollToTopThreshold;

      if (shouldShow != _showScrollToTop && mounted) {
        setState(() => _showScrollToTop = shouldShow);
      }
    } else {
      final ctx = n.context;
      if (ctx != null) {
        _bindActiveScrollable(Scrollable.maybeOf(ctx), updateVisibility: false);
      }
    }

    return false;
  }

  void _scrollToTop() {
    final s = _resolveScrollable(preferredAxis: Axis.vertical);
    if (s == null) return;
    _animateTo(
      s,
      s.position.minScrollExtent,
      durationMs: 260,
    );
  }

  Widget _buildFabStack(BuildContext context, String location) {
    final bottom =
        kBottomNavigationBarHeight + 16 + MediaQuery.of(context).padding.bottom;

    return Positioned(
      right: 16,
      bottom: bottom,
      child: ValueListenableBuilder<List<PageAction>>(
        valueListenable: pageActions,
        builder: (context, actions, _) {
          final List<Widget> children = <Widget>[];

          // Render page actions as floating mini FABs (primary action appears closest to the bottom).
          for (int i = actions.length - 1; i >= 0; i--) {
            final a = actions[i];
            children.add(
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FloatingActionButton.small(
                  heroTag: 'page_fab_${location.hashCode}_$i',
                  onPressed: a.onTap,
                  tooltip: a.label,
                  child: Icon(a.icon),
                ),
              ),
            );
          }

          // Scroll-to-top icon (only appears once there is vertical scroll).
          children.add(
            AnimatedOpacity(
              opacity: _showScrollToTop ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: IgnorePointer(
                ignoring: !_showScrollToTop,
                child: FloatingActionButton.small(
                  heroTag: 'scrolltop_fab_${location.hashCode}',
                  onPressed: _scrollToTop,
                  child: const Icon(Icons.keyboard_arrow_up),
                ),
              ),
            ),
          );

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: children,
          );
        },
      ),
    );
  }

  String _routeInfoToLocation(dynamic routeInfo, {required String fallback}) {
    // Flutter/go_router versions differ: prefer RouteInformation.uri, fallback to location.
    try {
      final uri = routeInfo.uri;
      if (uri != null) return uri.toString();
    } catch (_) {}
    try {
      final loc = routeInfo.location;
      if (loc != null) return loc.toString();
    } catch (_) {}
    return fallback;
  }

  String _routerLocation() {
    final r = _router;
    if (r == null) return widget.location;
    return _routeInfoToLocation(
      r.routeInformationProvider.value,
      fallback: widget.location,
    );
  }

  void _handleRouteInfoChanged() {
    if (!mounted) return;
    final r = _router;
    if (r == null) return;
    final loc = _routeInfoToLocation(
      r.routeInformationProvider.value,
      fallback: widget.location,
    );
    if (loc == _lastRouterLocation) return;
    final old = _lastRouterLocation;
    _lastRouterLocation = loc;
    _onLocationChanged(old, loc);
  }

  void _onLocationChanged(String? oldLoc, String newLoc) {
    if (!mounted) return;

    final oldUri =
        (oldLoc == null || oldLoc.trim().isEmpty) ? null : Uri.tryParse(oldLoc);
    final newUri = Uri.tryParse(newLoc);

    final pathChanged = (oldUri != null && newUri != null)
        ? (oldUri.path != newUri.path)
        : true;

    // Manual refresh == same path, but `ts` changed
    final isManualRefresh = (oldUri != null && newUri != null)
        ? (oldUri.path == newUri.path &&
            newUri.queryParameters.containsKey('ts') &&
            newUri.queryParameters['ts'] != oldUri.queryParameters['ts'])
        : false;

    // Clear actions only when navigating to a different page
    if (pathChanged) {
      pageActions.value = const <PageAction>[];

      // Clear per-page navigation config to avoid stale next/back targets
      // while the new page mounts.
      pageNav.value = null;

      // New page: reset scroll-to-top state.
      _lastPageScrollable = null;
      _bindActiveScrollable(null);
      EvolutionScrollRegistry.activeScrollable.value = null;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _primeDefaultScrollable();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _updateScrollToTopVisibility();
        });
      });
    }

    // Track navigation history (ignore manual refresh)
    if (!isManualRefresh) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(navHistoryProvider.notifier).pushLocation(newLoc);
      });
    }

    // Always refresh balances when route changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!ref.read(sessionProvider).loggedIn) return;
      ref.read(currentBalanceProvider.notifier).refreshBalances(force: true);
    });

    // Manual refresh: notify the active page to reload its own data
    if (isManualRefresh) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(pageRefreshPulseProvider.notifier).state++;
      });
    }
  }

  EditableText? _focusedEditableText() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return null;
    final ctx = focus.context;
    if (ctx == null) return null;
    final widget = ctx.widget;
    if (widget is EditableText) return widget;
    return ctx.findAncestorWidgetOfExactType<EditableText>();
  }

  bool _isTextEditingActive() {
    final editable = _focusedEditableText();
    if (editable == null) return false;
    return !editable.readOnly;
  }

  ScrollableState? _scrollableFromFocusedContext({Axis? preferredAxis}) {
    final focus = FocusManager.instance.primaryFocus;
    final ctx = focus?.context;
    if (ctx == null) return null;

    ScrollableState? exact = Scrollable.maybeOf(ctx);
    if (exact != null) {
      try {
        final matches =
            preferredAxis == null || _axisOf(exact) == preferredAxis;
        if (matches && exact.position.hasContentDimensions) {
          return exact;
        }
      } catch (_) {}
    }

    Element? element = ctx is Element ? ctx : null;
    ScrollableState? found;

    while (element != null && found == null) {
      element.visitAncestorElements((ancestor) {
        final scrollable = Scrollable.maybeOf(ancestor);
        if (scrollable == null) return true;
        try {
          final matches =
              preferredAxis == null || _axisOf(scrollable) == preferredAxis;
          if (matches && scrollable.position.hasContentDimensions) {
            found = scrollable;
            return false;
          }
        } catch (_) {}
        return true;
      });
      break;
    }

    return found;
  }

  Axis _axisOf(ScrollableState scrollable) {
    return axisDirectionToAxis(scrollable.position.axisDirection);
  }

  void _syncActiveScrollableFromRegistry() {
    final registered = EvolutionScrollRegistry.activeScrollable.value;
    if (registered != null) {
      _bindActiveScrollable(registered);
    }
  }

  ScrollableState? _findFirstScrollable(BuildContext root, {Axis? axis}) {
    final rootElement = root is Element ? root : null;
    if (rootElement == null) return null;

    ScrollableState? found;
    final visited = <ScrollableState>{};

    void visit(Element element) {
      if (found != null) return;

      final scrollable = Scrollable.maybeOf(element);
      if (scrollable != null && !visited.contains(scrollable)) {
        visited.add(scrollable);
        if (axis == null || _axisOf(scrollable) == axis) {
          found = scrollable;
          return;
        }
      }

      element.visitChildElements(visit);
    }

    rootElement.visitChildElements(visit);
    return found;
  }


  ScrollableState? _scrollableFromPopupContext({Axis? preferredAxis}) {
    final popupContext = EvolutionScrollRegistry.activePopupContext.value;
    if (popupContext == null) return null;

    final popupScrollable = EvolutionScrollRegistry.findFirstDescendantScrollable(
      popupContext,
      axis: preferredAxis,
    );
    if (popupScrollable != null) {
      _bindActiveScrollable(popupScrollable);
      return popupScrollable;
    }

    return null;
  }

  ScrollableState? _resolveScrollable({Axis? preferredAxis}) {
    final hasActivePopup =
        EvolutionScrollRegistry.activePopupContext.value != null;
    final popupScrollable =
        _scrollableFromPopupContext(preferredAxis: preferredAxis);
    if (popupScrollable != null) {
      return popupScrollable;
    }
    if (hasActivePopup) {
      return null;
    }

    final focused = _scrollableFromFocusedContext(preferredAxis: preferredAxis);
    if (focused != null) {
      _bindActiveScrollable(focused);
      return focused;
    }

    _syncActiveScrollableFromRegistry();

    final current = _activeScrollable;
    if (current != null) {
      try {
        final matches =
            preferredAxis == null || _axisOf(current) == preferredAxis;
        if (matches && current.position.hasContentDimensions) {
          return current;
        }
      } catch (_) {
        _bindActiveScrollable(null);
      }
    }

    final rootContext = _scrollRootKey.currentContext;
    if (rootContext == null) return null;

    final exact = _findFirstScrollable(rootContext, axis: preferredAxis);
    if (exact != null) {
      _bindActiveScrollable(exact);
      return exact;
    }

    final any = _findFirstScrollable(rootContext);
    if (any != null) {
      _bindActiveScrollable(any);
      return any;
    }

    return null;
  }

  void _primeDefaultScrollable() {
    final vertical = _resolveScrollable(preferredAxis: Axis.vertical);
    if (vertical != null) {
      _bindActiveScrollable(vertical);
      return;
    }
    _bindActiveScrollable(_resolveScrollable());
  }

  bool _animateTo(
    ScrollableState scrollable,
    double offset, {
    int durationMs = 140,
  }) {
    try {
      final position = scrollable.position;
      final target = offset.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((target - position.pixels).abs() < 0.5) {
        return false;
      }
      position.animateTo(
        target,
        duration: Duration(milliseconds: durationMs),
        curve: Curves.easeOutCubic,
      );
      _bindActiveScrollable(scrollable, updateVisibility: false);
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _scrollBy(Axis axis, double delta) {
    final scrollable = _resolveScrollable(preferredAxis: axis);
    if (scrollable == null) return false;
    final position = scrollable.position;
    return _animateTo(scrollable, position.pixels + delta);
  }

  bool _scrollToEdge(Axis axis, {required bool end}) {
    final scrollable = _resolveScrollable(preferredAxis: axis);
    if (scrollable == null) return false;
    final position = scrollable.position;
    final target = end ? position.maxScrollExtent : position.minScrollExtent;
    return _animateTo(scrollable, target, durationMs: 220);
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (_isTextEditingActive()) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final verticalPageDelta = ((_resolveScrollable(preferredAxis: Axis.vertical)
                    ?.position
                    .viewportDimension ??
                0) *
            _pageScrollFactor)
        .clamp(240.0, 1000.0);

    final handled = switch (key) {
      LogicalKeyboardKey.arrowUp => _scrollBy(Axis.vertical, -_arrowScrollStep),
      LogicalKeyboardKey.arrowDown =>
        _scrollBy(Axis.vertical, _arrowScrollStep),
      LogicalKeyboardKey.arrowLeft =>
        _scrollBy(Axis.horizontal, -_horizontalArrowScrollStep),
      LogicalKeyboardKey.arrowRight =>
        _scrollBy(Axis.horizontal, _horizontalArrowScrollStep),
      LogicalKeyboardKey.pageUp => _scrollBy(Axis.vertical, -verticalPageDelta),
      LogicalKeyboardKey.pageDown =>
        _scrollBy(Axis.vertical, verticalPageDelta),
      LogicalKeyboardKey.home => _scrollToEdge(Axis.vertical, end: false) ||
          _scrollToEdge(Axis.horizontal, end: false),
      LogicalKeyboardKey.end => _scrollToEdge(Axis.vertical, end: true) ||
          _scrollToEdge(Axis.horizontal, end: true),
      _ => false,
    };

    return handled ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  bool _handleHardwareKeyEvent(KeyEvent event) {
    return _handleKeyEvent(event) == KeyEventResult.handled;
  }

  @override
  void initState() {
    super.initState();

    EvolutionScrollRegistry.activeScrollable.addListener(
      _syncActiveScrollableFromRegistry,
    );
    EvolutionScrollRegistry.activePopupContext.addListener(
      _handlePopupContextChanged,
    );
    HardwareKeyboard.instance.addHandler(_handleHardwareKeyEvent);

    // Seed navigation history for back-arrow fallback.
    // Riverpod forbids modifying providers during build/initState; defer to end of frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final r = GoRouter.of(context);
      final loc = _routeInfoToLocation(
        r.routeInformationProvider.value,
        fallback: widget.location,
      );
      _lastRouterLocation ??= loc;
      ref.read(navHistoryProvider.notifier).setInitial(loc);
      _primeDefaultScrollable();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _updateScrollToTopVisibility();
      });
    });

    // Always start with no stale global state from a previous AppScaffold.
    pageActions.value = const <PageAction>[];
    pageNav.value = null;
    EvolutionScrollRegistry.activeScrollable.value = null;
    EvolutionScrollRegistry.activePopupContext.value = null;
    // Initial page load → refresh balances (force)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!ref.read(sessionProvider).loggedIn) return;
      ref.read(currentBalanceProvider.notifier).refreshBalances(force: true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routerBound) return;
    _router = GoRouter.of(context);
    _routerBound = true;
    _lastRouterLocation ??= _routerLocation();
    _router!.routeInformationProvider.addListener(_handleRouteInfoChanged);
  }

  @override
  void dispose() {
    try {
      _router?.routeInformationProvider.removeListener(_handleRouteInfoChanged);
    } catch (_) {}
    EvolutionScrollRegistry.activeScrollable.removeListener(
      _syncActiveScrollableFromRegistry,
    );
    EvolutionScrollRegistry.activePopupContext.removeListener(
      _handlePopupContextChanged,
    );
    try {
      _boundScrollPosition?.removeListener(_handleBoundScrollPositionChanged);
    } catch (_) {}
    HardwareKeyboard.instance.removeHandler(_handleHardwareKeyEvent);
    // Clear global ValueNotifiers so stale state from this session never
    // leaks into the next AppScaffold instance (e.g. after re-login).
    pageNav.value = null;
    EvolutionScrollRegistry.activeScrollable.value = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AppScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.location == widget.location) return;
    if (_lastRouterLocation == widget.location) return;
    _lastRouterLocation = widget.location;
    _onLocationChanged(oldWidget.location, widget.location);
  }

  @override
  Widget build(BuildContext context) {
    final router = _router ?? GoRouter.of(context);

    return ValueListenableBuilder<RouteInformation>(
      valueListenable: router.routeInformationProvider,
      builder: (context, info, _) {
        final loc = _routeInfoToLocation(info, fallback: widget.location);
        // widget.location comes from ShellRoute state — always reflects the
        // current logical route, even during the first build after a redirect.
        // routeInformationProvider.value.uri is stale on that first build
        // (still holds the pre-redirect path, e.g. /auth/login), so we must
        // NOT derive isHome from it.
        final isHome =
            (Uri.tryParse(widget.location)?.path ?? widget.location) == R.home;

        Widget buildNavStrip() {
          return ValueListenableBuilder<PageNavConfig?>(
            valueListenable: pageNav,
            builder: (context, cfg, _) {
              if (isHome) {
                return const CurrencyCardStrip(
                    showBack: false, showNext: false);
              }

              final showBack = cfg?.showBack ?? true;
              final showNext = cfg?.showNext ?? false;
              final nextEnabled = (cfg?.nextEnabled ?? true) && !_navNextBusy;

              final backTo =
                  (cfg?.backTo == null || cfg!.backTo!.trim().isEmpty)
                      ? R.home
                      : cfg.backTo!;

              final onBack = cfg?.onBack ?? () => context.go(backTo);

              Future<void> onNext() async {
                if (_navNextBusy) return;

                // Submit-style next (async) should show spinner.
                if (cfg?.onNext != null) {
                  setState(() => _navNextBusy = true);
                  try {
                    await cfg!.onNext!();
                  } finally {
                    if (mounted) setState(() => _navNextBusy = false);
                  }
                  return;
                }

                final nt = cfg?.nextTo;
                if (nt != null && nt.trim().isNotEmpty) {
                  context.go(nt);
                }
              }

              return CurrencyCardStrip(
                showBack: showBack,
                onBack: showBack ? onBack : null,
                showNext: showNext,
                nextEnabled: nextEnabled,
                nextLoading: _navNextBusy,
                onNext: showNext ? onNext : null,
              );
            },
          );
        }

        return Stack(
          children: [
            // Shared background (ribbon + gradients)
            const PageBackground(child: SizedBox.expand()),

            //const FadeBackground(), // keep disabled if you want
            Scaffold(
                backgroundColor: Colors.transparent,
                drawer: const LeftMenuDrawer(),
                appBar: const PreferredSize(
                  preferredSize: Size.fromHeight(kToolbarHeight),
                  child: TopBar(),
                ),
                body: Column(
                  children: [
                    buildNavStrip(),
                    const SizedBox(height: 6),
                    Expanded(
                      child: KeyedSubtree(
                        key: _scrollRootKey,
                        child: NotificationListener<ScrollNotification>(
                          onNotification: _onScrollNotification,
                          child: widget.body,
                        ),
                      ),
                    ),
                  ],
                ),
                bottomNavigationBar: BottomNav(location: loc),
              ),

            // Scroll-to-top icon (only appears once there is vertical scroll).
            _buildFabStack(context, loc),
          ],
        );
      },
    );
  }
}
