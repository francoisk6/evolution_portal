import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class EvolutionScrollRegistry {
  static final ValueNotifier<ScrollableState?> activeScrollable =
      ValueNotifier<ScrollableState?>(null);

  static final ValueNotifier<BuildContext?> activePopupContext =
      ValueNotifier<BuildContext?>(null);

  static void activate(BuildContext context) {
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable != null) {
      activeScrollable.value = scrollable;
    }
  }

  static Axis _axisOf(ScrollableState scrollable) {
    return axisDirectionToAxis(scrollable.position.axisDirection);
  }

  static ScrollableState? findFirstDescendantScrollable(
    BuildContext context, {
    Axis? axis,
  }) {
    final exact = Scrollable.maybeOf(context);
    if (exact != null) {
      try {
        if (axis == null || _axisOf(exact) == axis) {
          return exact;
        }
      } catch (_) {}
    }

    final rootElement = context is Element ? context : null;
    if (rootElement == null) return null;

    ScrollableState? found;
    final visited = <ScrollableState>{};

    void visit(Element element) {
      if (found != null) return;

      final scrollable = Scrollable.maybeOf(element);
      if (scrollable != null && !visited.contains(scrollable)) {
        visited.add(scrollable);
        try {
          if (axis == null || _axisOf(scrollable) == axis) {
            found = scrollable;
            return;
          }
        } catch (_) {}
      }

      element.visitChildElements(visit);
    }

    rootElement.visitChildElements(visit);
    return found;
  }

  static void activateDescendant(
    BuildContext context, {
    Axis? axis,
  }) {
    final scrollable = findFirstDescendantScrollable(context, axis: axis);
    if (scrollable != null) {
      activeScrollable.value = scrollable;
    }
  }

  static void activatePopup(
    BuildContext context, {
    Axis? axis,
  }) {
    activePopupContext.value = context;
    activateDescendant(context, axis: axis);
  }

  static void deactivatePopup(BuildContext context) {
    if (identical(activePopupContext.value, context)) {
      activePopupContext.value = null;
    }
  }
}

class EvolutionPopupScrollScope extends StatefulWidget {
  final Widget child;
  final Axis? preferredAxis;
  final bool autofocus;

  const EvolutionPopupScrollScope({
    super.key,
    required this.child,
    this.preferredAxis = Axis.vertical,
    this.autofocus = true,
  });

  @override
  State<EvolutionPopupScrollScope> createState() =>
      _EvolutionPopupScrollScopeState();
}

class _EvolutionPopupScrollScopeState extends State<EvolutionPopupScrollScope> {
  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'EvolutionPopupScrollScope',
  );

  void _activate() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      EvolutionScrollRegistry.activatePopup(
        context,
        axis: widget.preferredAxis,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _activate();
  }

  @override
  void dispose() {
    EvolutionScrollRegistry.deactivatePopup(context);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (hasFocus) {
        if (hasFocus) _activate();
      },
      child: MouseRegion(
        onEnter: (_) => _activate(),
        child: Listener(
          onPointerDown: (_) => _activate(),
          onPointerSignal: (_) => _activate(),
          child: widget.child,
        ),
      ),
    );
  }
}

/// App-wide scroll behavior:
/// - Allows dragging/scrolling with mouse, trackpad, touch, and pen devices.
/// - Useful for Flutter Web/Desktop where default drag devices can be limited.
class EvolutionScrollBehavior extends MaterialScrollBehavior {
  /// Whether to wrap scrollables with a visible scrollbar.
  ///
  /// Defaults to `true` to keep scrollbars always visible across the app.
  /// Pages can opt out via a local [ScrollConfiguration] (e.g. Home page).
  final bool showScrollbars;

  const EvolutionScrollBehavior({this.showScrollbars = true});

  @override
  Set<PointerDeviceKind> get dragDevices => const <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.unknown,
      };

  Widget _wrapActivation(BuildContext context, Widget child) {
    return MouseRegion(
      onEnter: (_) => EvolutionScrollRegistry.activate(context),
      child: Listener(
        onPointerDown: (_) => EvolutionScrollRegistry.activate(context),
        onPointerSignal: (_) => EvolutionScrollRegistry.activate(context),
        child: child,
      ),
    );
  }

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final activatedChild = _wrapActivation(context, child);

    if (!showScrollbars) return activatedChild;

    return Scrollbar(
      controller: details.controller,
      thumbVisibility: true,
      trackVisibility: true,
      interactive: true,
      child: activatedChild,
    );
  }
}
