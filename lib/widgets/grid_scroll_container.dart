import 'package:flutter/material.dart';

class GridScrollContainer extends StatelessWidget {
  final Widget child;
  final ScrollController? controller;
  final bool showScrollbar;

  const GridScrollContainer({
    super.key,
    required this.child,
    this.controller,
    this.showScrollbar = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scrollView = SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.all(12),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: child,
          ),
        );

        if (!showScrollbar) return scrollView;

        return Scrollbar(
          controller: controller,
          thumbVisibility: true,
          trackVisibility: true,
          interactive: true,
          child: scrollView,
        );
      },
    );
  }
}
