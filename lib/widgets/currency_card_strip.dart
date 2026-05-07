import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_service.dart';
import '../state/current_balance_provider.dart';
import '../state/currency_provider.dart';
import '../utils/money_format.dart';

// Keep the legacy currencyProvider (used by older pages / filters) in sync with the
// server/session active currency maintained by CurrentBalanceNotifier.
//
// This prevents cases where the currency chips show USD (server active) while pages
// that rely on currencyProvider still default to LBP until the user taps a chip.
void _syncLegacyCurrencyProvider(WidgetRef ref, String? activeCode) {
  final code = (activeCode ?? '').trim().toUpperCase();
  if (code.isEmpty) return;

  final cs = ref.read(currencyProvider);
  final idx = cs.all.indexWhere((c) => c.code.toUpperCase() == code);
  if (idx < 0) return;
  final desiredId = cs.all[idx].id;
  if (cs.selectedId == desiredId) return;

  // Riverpod: avoid mutating provider during build.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final cs2 = ref.read(currencyProvider);
    final idx2 = cs2.all.indexWhere((c) => c.code.toUpperCase() == code);
    if (idx2 < 0) return;
    final desiredId2 = cs2.all[idx2].id;
    if (cs2.selectedId == desiredId2) return;
    ref.read(currencyProvider.notifier).select(desiredId2);
  });
}

void _maybeShowServerSnack(BuildContext context) {
  final env = ApiService.instance.lastEnvelope;
  if (env == null) return;
  final ok = env.ok;
  final msg = env.message?.trim();
  final err = env.humanError?.trim();
  if (ok && msg != null && msg.isNotEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.green.shade700,
        content: Text(msg),
      ),
    );
  } else if (!ok && err != null && err.isNotEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red.shade700,
        content: Text(err),
      ),
    );
  }
}

class CurrencyCardStrip extends ConsumerWidget {
  const CurrencyCardStrip({
    super.key,
    this.showBack = true,
    this.onBack,
    this.showNext = false,
    this.nextEnabled = true,
    this.nextLoading = false,
    this.onNext,
  });

  /// Whether to show the Back arrow.
  /// Home page should pass false.
  final bool showBack;

  /// Back handler. If null, Back will appear disabled.
  final VoidCallback? onBack;

  /// Whether to show the Next arrow.
  final bool showNext;

  /// Enable/disable Next.
  final bool nextEnabled;

  /// Show a small spinner inside Next.
  final bool nextLoading;

  /// Next handler. If null, Next will appear disabled.
  final Future<void> Function()? onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(currentBalanceProvider);
    final notifier = ref.read(currentBalanceProvider.notifier);

    final backChip = _BackChip(
      enabled: showBack && onBack != null,
      onTap: onBack,
    );

    final nextChip = _NextChip(
      enabled: showNext && nextEnabled && !nextLoading && onNext != null,
      loading: showNext && nextLoading,
      onTap: onNext,
    );

    Widget wrap(List<Widget> children) {
      // Keep currency chips centered while pinning back/next to the edges.
      // Reserve equal slots so the center stays visually centered.
      const navSlotW = 44.0;
      final showNav = showBack || showNext;

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (showNav)
              SizedBox(
                width: navSlotW,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: showBack ? backChip : const SizedBox.shrink(),
                ),
              ),
            Expanded(
              child: Align(
                alignment: Alignment.center,
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: children,
                ),
              ),
            ),
            if (showNav)
              SizedBox(
                width: navSlotW,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: showNext ? nextChip : const SizedBox.shrink(),
                ),
              ),
          ],
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: async.when(
        loading: () => wrap(
          List.generate(2, (_) => const _SkeletonChip()),
        ),
        error: (e, _) => wrap([
          _ErrorChip(
            message: e.toString().replaceFirst('Exception: ', ''),
            onRetry: () async {
              try {
                await notifier.refreshBalances(force: true);
              } catch (_) {}
            },
          ),
        ]),
        data: (cb) {
          final items = cb?.items ?? const [];
          final active = notifier.activeCurrency?.toUpperCase();

          // Auto-sync legacy provider to whatever the session is using right now.
          _syncLegacyCurrencyProvider(ref, active);

          if (items.isEmpty) {
            return wrap(const [
              _PlainText('No balances yet'),
            ]);
          }

          return wrap(
            items.map((it) {
              final code = it.currency.toUpperCase();
              final isActive = code == active;
              return _CurrencyChip(
                currency: code,
                amount: it.balance,
                active: isActive,
                onTap: isActive
                    ? null
                    : () async {
                        try {
                          await notifier.changeCurrency(it.currency);

                          // Keep the legacy currencyProvider (used by filters + online pages)
                          // in sync with the server-selected currency.
                          final cs = ref.read(currencyProvider);
                          final idx = cs.all.indexWhere(
                            (c) => c.code.toUpperCase() == code,
                          );
                          if (idx >= 0) {
                            ref.read(currencyProvider.notifier).select(cs.all[idx].id);
                          }
                          if (!context.mounted) return;
                          _maybeShowServerSnack(context);
                        } catch (e) {
                          if (!context.mounted) return;
                          final msg = e.toString().replaceFirst('Exception: ', '');
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              behavior: SnackBarBehavior.floating,
                              backgroundColor: Colors.red.shade700,
                              content: Text(msg),
                            ),
                          );
                        }
                      },
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _BackChip extends StatelessWidget {
  final bool enabled;
  final VoidCallback? onTap;

  const _BackChip({
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFDC3545);
    final bg = enabled ? red.withValues(alpha: .10) : red.withValues(alpha: .06);
    final bd = enabled ? red.withValues(alpha: .35) : red.withValues(alpha: .22);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: bd),
        ),
        child: const Icon(
          Icons.arrow_back,
          size: 16,
          color: red,
        ),
      ),
    );
  }
}

class _NextChip extends StatelessWidget {
  final bool enabled;
  final bool loading;
  final Future<void> Function()? onTap;

  const _NextChip({
    required this.enabled,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF28A745);
    // UX: when Next is disabled, show a neutral grey arrow (not green).
    const disabled = Color(0xFF9AA0A6);

    final Color iconColor = enabled ? green : disabled;
    final Color bg = enabled
        ? green.withValues(alpha: .10)
        : disabled.withValues(alpha: .10);
    final Color bd = enabled
        ? green.withValues(alpha: .35)
        : disabled.withValues(alpha: .30);

    return InkWell(
      onTap: enabled
          ? () async {
              final fn = onTap;
              if (fn == null) return;
              await fn();
            }
          : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: bd),
        ),
        child: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: green,
                ),
              )
            : Icon(
                Icons.arrow_forward,
                size: 16,
                color: iconColor,
              ),
      ),
    );
  }
}

class _PlainText extends StatelessWidget {
  final String text;
  const _PlainText(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12, // slightly smaller
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .7),
        ),
      ),
    );
  }
}

class _SkeletonChip extends StatelessWidget {
  const _SkeletonChip();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: const SizedBox(width: 86, height: 14),
    );
  }
}

class _ErrorChip extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorChip({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: .25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, size: 16, color: Colors.red),
        const SizedBox(width: 6),
        Text(
          message,
          style: const TextStyle(fontSize: 12, color: Colors.red),
        ),
        const SizedBox(width: 10),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text(
            'Retry',
            style: TextStyle(fontSize: 12),
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ]),
    );
  }
}

class _CurrencyChip extends StatelessWidget {
  final String currency;
  final num amount;
  final bool active;
  final VoidCallback? onTap;

  const _CurrencyChip({
    required this.currency,
    required this.amount,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = active
        ? cs.primary.withValues(alpha: .15)
        : cs.surface.withValues(alpha: .7);
    final fg = active ? cs.primary : cs.onSurface.withValues(alpha: .9);
    final bd = active ? cs.primary.withValues(alpha: .35) : Colors.black12;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: bd),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(
            currency,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            MoneyFormat.format(amount, currencyCode: currency),
            style: TextStyle(fontSize: 12, color: fg),
          ),
        ]),
      ),
    );
  }
}
