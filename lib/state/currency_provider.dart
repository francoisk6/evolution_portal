import 'package:flutter_riverpod/flutter_riverpod.dart';

class Currency {
  final int id;
  final String code;
  final String symbol;
  final double available;
  const Currency(
      {required this.id,
      required this.code,
      required this.symbol,
      required this.available});
}

class CurrencyState {
  final List<Currency> all;
  final int selectedId;
  const CurrencyState(this.all, this.selectedId);
  Currency get selected => all.isEmpty
      ? const Currency(id: 0, code: 'N/A', symbol: '', available: 0)
      : all.firstWhere((c) => c.id == selectedId, orElse: () => all.first);
}

class CurrencyNotifier extends StateNotifier<CurrencyState> {
  CurrencyNotifier()
      : super(const CurrencyState([
          Currency(id: 4, code: 'USD', symbol: '\$', available: 0.0),
          Currency(id: 2, code: 'LBP', symbol: '£', available: 0.0),
        ], 2));

  void select(int id) => state = CurrencyState(state.all, id);
  void setBalances(List<Currency> list, int selectedId) =>
      state = CurrencyState(list, list.isEmpty ? selectedId : selectedId);
}

final currencyProvider = StateNotifierProvider<CurrencyNotifier, CurrencyState>(
    (ref) => CurrencyNotifier());
