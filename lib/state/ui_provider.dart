import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PageAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const PageAction(
      {required this.label, required this.icon, required this.onTap});
}

final pageActionsProvider = StateProvider<List<PageAction>>((_) => const []);
