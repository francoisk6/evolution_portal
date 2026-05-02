import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the *current page's* action widgets (shown above the bottom bar).
/// Pages set this when they build / become visible.
final pageActionsProvider = StateProvider<List<Widget>>((ref) => const []);
