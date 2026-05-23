import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../routing/route_names.dart';
import '../../services/api_service.dart';

class MaintenanceGate extends StatelessWidget {
  const MaintenanceGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ApiService.maintenanceMode,
      builder: (context, active, _) {
        if (!active) return const SizedBox.shrink();
        return const _MaintenanceOverlay();
      },
    );
  }
}

class _MaintenanceOverlay extends StatefulWidget {
  const _MaintenanceOverlay();

  @override
  State<_MaintenanceOverlay> createState() => _MaintenanceOverlayState();
}

class _MaintenanceOverlayState extends State<_MaintenanceOverlay> {
  static const int _retryAfterSeconds = 60;

  Timer? _timer;
  int _remaining = _retryAfterSeconds;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    _remaining = _retryAfterSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _remaining--);
      if (_remaining <= 0) {
        t.cancel();
        _ping();
      }
    });
  }

  Future<void> _ping() async {
    if (_retrying || !mounted) return;
    setState(() => _retrying = true);
    try {
      await ApiService.instance.getVersionInfo();
      if (mounted) ApiService.maintenanceMode.value = false;
    } catch (_) {
      if (!mounted) return;
      setState(() => _retrying = false);
      _startCountdown();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFE4E6E8)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const _LabelChip(label: 'EV'),
                        const SizedBox(width: 8),
                        const _LabelChip(
                          label: 'Scheduled Maintenance',
                          leading: _SpinIcon(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "We're doing a quick tune-up",
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'نحن نقوم بصيانة سريعة للنظام',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Color(0xFF1E88E5),
                        fontWeight: FontWeight.w600,
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Our servers are undergoing maintenance to keep things fast, '
                      'secure, and reliable. Most services are temporarily unavailable.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    _CountdownBox(remaining: _remaining, retrying: _retrying),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        FilledButton(
                          onPressed: _retrying
                              ? null
                              : () {
                                  _timer?.cancel();
                                  ApiService.maintenanceMode.value = false;
                                  context.go(R.home);
                                },
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1A1A1A),
                          ),
                          child: const Text('Try Home'),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton(
                          onPressed: _retrying
                              ? null
                              : () {
                                  _timer?.cancel();
                                  setState(() {
                                    _retrying = false;
                                    _remaining = _retryAfterSeconds;
                                  });
                                  _ping();
                                },
                          child: const Text('Reload Page'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text.rich(
                      TextSpan(
                        text: 'Need help? Contact us at ',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                        children: [
                          TextSpan(
                            text: 'evolutionportale@gmail.com',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          const TextSpan(text: '.'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CountdownBox extends StatelessWidget {
  final int remaining;
  final bool retrying;

  const _CountdownBox({required this.remaining, required this.retrying});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE4E6E8)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const _PulseDot(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Estimated downtime:',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  retrying
                      ? 'Checking availability…'
                      : "We'll try again automatically in ${remaining}s.",
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LabelChip extends StatelessWidget {
  final String label;
  final Widget? leading;

  const _LabelChip({required this.label, this.leading});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDDE1E4)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _SpinIcon extends StatefulWidget {
  const _SpinIcon();

  @override
  State<_SpinIcon> createState() => _SpinIconState();
}

class _SpinIconState extends State<_SpinIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _ctrl,
      child: Icon(Icons.autorenew, size: 13, color: Colors.grey.shade700),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.2, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Colors.green,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
