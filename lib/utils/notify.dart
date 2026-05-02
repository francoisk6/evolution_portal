import 'package:flutter/material.dart';
import '../services/api_service.dart';

String _clean(Object e) => e.toString().replaceFirst('Exception: ', '').trim();

void showSuccess(BuildContext context, String msg) {
  if (msg.trim().isEmpty) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: Colors.green.shade700,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

void showError(BuildContext context, String msg) {
  if (msg.trim().isEmpty) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Use after a successful API call.
/// If the server sent a top-level "message", shows it in green.
/// If it sent an "error", shows it in red.
/// If neither exists, shows nothing.
void showServerNoticeFromLast(BuildContext context) {
  final env = ApiService.instance.lastEnvelope;
  final ok = env?.ok ?? false;
  final msg = env?.message?.toString().trim();
  final err = env?.humanError?.toString().trim();

  if (ok && msg != null && msg.isNotEmpty) {
    showSuccess(context, msg);
  } else if (!ok && err != null && err.isNotEmpty) {
    showError(context, err);
  }
}

/// Use inside catch blocks to show clean errors (red).
void showCaughtError(BuildContext context, Object e) {
  showError(context, _clean(e));
}
