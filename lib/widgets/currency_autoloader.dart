import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/balance_service.dart';
import '../state/currency_provider.dart';

class CurrencyAutoLoader extends ConsumerStatefulWidget {
  const CurrencyAutoLoader({super.key});
  @override
  ConsumerState<CurrencyAutoLoader> createState() => _CurrencyAutoLoaderState();
}

class _CurrencyAutoLoaderState extends ConsumerState<CurrencyAutoLoader> {
  bool _ran = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ran) return;
    _ran = true;
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await BalanceService.instance.current();
      final balances = (data['balances'] ??
              data['currencies'] ??
              data['data'] ??
              []) as List? ??
          [];
      (data['default_currency'] ?? data['current_currency'])?.toString();
      final List<Currency> cs = [];
      for (final item in balances) {
        if (item is Map<String, dynamic>) {
          final id =
              (item['id'] ?? item['currency_id'] ?? item['pk'] ?? 0) as int;
          final code = (item['code'] ?? item['currency'] ?? '').toString();
          final symbol = (item['symbol'] ??
                  (code == 'USD'
                      ? '\$'
                      : code == 'LBP'
                          ? '£'
                          : code))
              .toString();
          final available = double.tryParse((item['available'] ??
                      item['balance'] ??
                      item['amount'] ??
                      '0')
                  .toString()) ??
              0.0;
          cs.add(Currency(
              id: id, code: code, symbol: symbol, available: available));
        }
      }
      int selectedId = 1;
      final curr = data['default_currency'] ?? data['selected_currency'];
      if (curr is int) selectedId = curr;
      if (curr is String) {
        final idx = cs.indexWhere((c) => c.code == curr);
        if (idx >= 0) selectedId = cs[idx].id;
      }
      if (cs.isNotEmpty) {
        ref.read(currencyProvider.notifier).setBalances(cs, selectedId);
      }
    } catch (_) {
      // keep defaults
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
