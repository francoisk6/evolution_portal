import 'package:flutter/material.dart';

/// One backend catalog-update job, exposed under Admin ▸ Update Catalog.
///
/// [key] is the URL segment: POST `api/online/catalog-updates/<key>/run/`.
/// [timeout] mirrors the `--max-time` the backend jobs were tuned against.
class CatalogTarget {
  final String key;
  final String label;
  final IconData icon;
  final Duration timeout;

  const CatalogTarget({
    required this.key,
    required this.label,
    required this.icon,
    required this.timeout,
  });
}

const List<CatalogTarget> kCatalogTargets = <CatalogTarget>[
  CatalogTarget(
    key: 'g2g',
    label: 'G2G',
    icon: Icons.sync_alt_outlined,
    timeout: Duration(seconds: 120),
  ),
  CatalogTarget(
    key: 'online_cards',
    label: 'FV / Online Cards',
    icon: Icons.credit_card_outlined,
    timeout: Duration(seconds: 180),
  ),
  CatalogTarget(
    key: 'cyberia_bot',
    label: 'Cyberia Bot',
    icon: Icons.smart_toy_outlined,
    timeout: Duration(seconds: 30),
  ),
  CatalogTarget(
    key: 'idm_bot',
    label: 'IDM Bot',
    icon: Icons.smart_toy_outlined,
    timeout: Duration(seconds: 30),
  ),
  CatalogTarget(
    key: 'sodetel_bot',
    label: 'Sodetel Bot',
    icon: Icons.smart_toy_outlined,
    timeout: Duration(seconds: 30),
  ),
  CatalogTarget(
    key: 'mobi',
    label: 'Mobi',
    icon: Icons.sim_card_outlined,
    timeout: Duration(seconds: 120),
  ),
  CatalogTarget(
    key: 'cablevision',
    label: 'Cablevision Data',
    icon: Icons.router_outlined,
    timeout: Duration(seconds: 300),
  ),
  CatalogTarget(
    key: 'daniel_rajab',
    label: 'Telecom DR',
    icon: Icons.cell_tower_outlined,
    timeout: Duration(seconds: 120),
  ),
  CatalogTarget(
    key: 'wakel',
    label: 'Wakel Topup',
    icon: Icons.account_balance_wallet_outlined,
    timeout: Duration(seconds: 120),
  ),
];

/// Result of a single catalog-update run.
///
/// The backend response shape isn't fixed across jobs, so the human-readable
/// text falls back through the usual envelope keys before defaulting.
class CatalogUpdateResult {
  final String message;
  final Map<String, dynamic> raw;

  const CatalogUpdateResult({required this.message, required this.raw});

  factory CatalogUpdateResult.fromJson(Map<String, dynamic> json) {
    String? pick(String key) {
      final v = json[key];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    final message = pick('message') ??
        pick('detail') ??
        pick('status') ??
        pick('result') ??
        'Completed';
    return CatalogUpdateResult(message: message, raw: json);
  }
}

enum CatalogRunStatus { idle, running, success, failure }

class CatalogRunState {
  final CatalogRunStatus status;
  final String? message;
  final Duration? elapsed;

  const CatalogRunState({
    this.status = CatalogRunStatus.idle,
    this.message,
    this.elapsed,
  });

  bool get isRunning => status == CatalogRunStatus.running;
}

/// Emitted once per finished run so the shell can surface a snackbar even when
/// the drawer was closed while the job was still in flight.
class CatalogRunEvent {
  final CatalogTarget target;
  final bool ok;
  final String message;
  final Duration elapsed;

  const CatalogRunEvent({
    required this.target,
    required this.ok,
    required this.message,
    required this.elapsed,
  });
}
