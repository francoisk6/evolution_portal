import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A single page action (label + icon + tap handler).
class PageAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const PageAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });
}

/// Global, simple bus for page actions.
/// AppScaffold (or wherever you render your action bar) should listen to this.
final ValueNotifier<List<PageAction>> pageActions =
    ValueNotifier<List<PageAction>>(<PageAction>[]);

/// Wrap your page content with this when the page wants to expose actions.
/// The actions are set on init, updated on prop change, and cleared on dispose.
class PageActions extends StatefulWidget {
  final List<PageAction> actions;
  final Widget child;

  const PageActions({
    super.key,
    required this.actions,
    required this.child,
  });

  @override
  State<PageActions> createState() => _PageActionsState();
}

class _PageActionsState extends State<PageActions> {
  @override
  void initState() {
    super.initState();
    // Set actions for this page.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      pageActions.value = List<PageAction>.from(widget.actions);
    });
  }

  @override
  void didUpdateWidget(covariant PageActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.actions, widget.actions)) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        pageActions.value = List<PageAction>.from(widget.actions);
      });
    }
  }

  @override
  void dispose() {
    // Clear actions when leaving the page.
    pageActions.value = const <PageAction>[];
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
