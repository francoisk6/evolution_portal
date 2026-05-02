import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../routing/route_names.dart';
import '../state/current_balance_provider.dart';
import '../state/page_refresh_provider.dart';

class BottomNav extends ConsumerWidget {
  final String location;
  const BottomNav({super.key, required this.location});

  // Adjust this to gain space. Typical good values: 56, 60, 64.
  static const double _navHeight = 48;

  /// Returns tab index for core tabs; null for "other" pages.
  int? _indexFor(String loc) {
    if (loc.startsWith(R.home)) return 0;
    if (loc.startsWith(R.transactions)) return 1;
    if (loc.startsWith(R.accountBalanceHistory)) return 2;
    return null; // not a core tab → show no highlight
  }

  void _go(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go(R.home);
        break;
      case 1:
        context.go(R.transactions);
        break;
      case 2:
        context.go(R.accountBalanceHistory);
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = _indexFor(location);
    final selectedIndex = idx ?? 0;

    final nav = NavigationBar(
      height: _navHeight, // KEY: reduce whitespace without shrinking icons
      selectedIndex: selectedIndex,

      // Icons only (keep labels for accessibility + tooltips)
      labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,

      onDestinationSelected: (i) {
        // Refresh item (last)
        if (i == 3) {
          ref
              .read(currentBalanceProvider.notifier)
              .refreshBalances(force: true);
          ref.read(pageRefreshPulseProvider.notifier).state++;
          return;
        }
        if (i == idx) return; // already there
        _go(context, i);
      },

      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Home',
          tooltip: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long),
          label: 'T-History',
          tooltip: 'Transaction History',
        ),
        NavigationDestination(
          icon: Icon(Icons.balance),
          selectedIcon: Icon(Icons.balance),
          label: 'B-History',
          tooltip: 'Balance History',
        ),
        NavigationDestination(
          icon: Icon(Icons.refresh_outlined),
          selectedIcon: Icon(Icons.refresh),
          label: 'Refresh',
          tooltip: 'Refresh',
        ),
      ],
    );

    // Optional: further reduce vertical “touch target” padding.
    // Keeps icons the same size, but makes the bar feel tighter.
    final compactTheme = Theme(
      data: Theme.of(context).copyWith(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: const VisualDensity(vertical: -2),
      ),
      child: nav,
    );

    // When not on a core tab, hide the visual selection.
    if (idx == null) {
      return NavigationBarTheme(
        data: const NavigationBarThemeData(
          indicatorColor: Colors.transparent,
          labelTextStyle: WidgetStatePropertyAll(TextStyle()),
          iconTheme: WidgetStatePropertyAll(IconThemeData()),
        ),
        child: compactTheme,
      );
    }

    return compactTheme;
  }
}
