import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appStateScopeKey = GlobalKey<_AppStateScopeState>();

class AppStateScope extends StatefulWidget {
  final Widget child;
  const AppStateScope({super.key, required this.child});

  static void reset() => appStateScopeKey.currentState?.reset();

  @override
  State<AppStateScope> createState() => _AppStateScopeState();
}

class _AppStateScopeState extends State<AppStateScope> {
  int _epoch = 0;

  void reset() {
    setState(() => _epoch++);
  }

  @override
  Widget build(BuildContext context) {
    // Changing key forces a fresh ProviderContainer (wipes all provider state)
    return ProviderScope(
      key: ValueKey(_epoch),
      child: widget.child,
    );
  }
}
