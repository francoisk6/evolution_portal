import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_env.dart';
import '../../state/app_info_provider.dart';
import '../../state/force_update_provider.dart';
import '../../state/version_provider.dart';
import '../../utils/page_reload.dart';

class ForceUpdateGate extends ConsumerStatefulWidget {
  const ForceUpdateGate({super.key});

  @override
  ConsumerState<ForceUpdateGate> createState() => _ForceUpdateGateState();
}

class _ForceUpdateGateState extends ConsumerState<ForceUpdateGate>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPeriodicChecks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshVersionCheck(delay: const Duration(milliseconds: 800)));
    }
  }

  void _startPeriodicChecks() {
    _timer?.cancel();
    _timer = Timer.periodic(
      AppEnv.forceUpdateCheckInterval,
      (_) => unawaited(_refreshVersionCheck()),
    );
  }

  Future<void> _refreshVersionCheck({Duration? delay}) async {
    if (!mounted || _checking) return;
    _checking = true;
    try {
      if (delay != null) {
        await Future<void>.delayed(delay);
        if (!mounted) return;
      }
      ref.invalidate(packageInfoProvider);
      ref.invalidate(appVersionProvider);
      ref.invalidate(versionInfoProvider);
      ref.invalidate(forceUpdateProvider);
      await ref.read(forceUpdateProvider.future);
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(forceUpdateProvider);

    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (info) {
        if (info == null) return const SizedBox.shrink();
        return _ForceUpdateOverlay(info: info);
      },
    );
  }
}

class _ForceUpdateOverlay extends StatefulWidget {
  final ForceUpdateInfo info;

  const _ForceUpdateOverlay({required this.info});

  @override
  State<_ForceUpdateOverlay> createState() => _ForceUpdateOverlayState();
}

class _ForceUpdateOverlayState extends State<_ForceUpdateOverlay> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    widget.info.isWeb ? Icons.refresh : Icons.system_update_alt,
                    size: 44,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.info.title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.info.message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  _kv(context, 'Current version', widget.info.currentVersion),
                  _kv(context, 'Required version', widget.info.requiredVersion),
                  _kv(context, 'Required by', widget.info.sourceLabel),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _busy ? null : _handleAction,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(widget.info.isWeb ? Icons.refresh : Icons.open_in_new),
                    label: Text(_buttonLabel),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _buttonLabel {
    if (widget.info.isWeb) return widget.info.actionLabel;
    if ((widget.info.storeUrl ?? '').trim().isEmpty) {
      return 'Store URL not configured';
    }
    return widget.info.actionLabel;
  }

  Widget _kv(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleAction() async {
    if (_busy) return;

    setState(() => _busy = true);
    try {
      if (widget.info.isWeb) {
        await reloadCurrentPage();
        return;
      }

      final raw = widget.info.storeUrl?.trim() ?? '';
      if (raw.isEmpty) return;

      final uri = Uri.tryParse(raw);
      if (uri == null) return;

      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
