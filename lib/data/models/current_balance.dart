class BalanceItem {
  final String currency;
  final num balance;
  final num? balanceDue;

  BalanceItem({required this.currency, required this.balance, this.balanceDue});

  factory BalanceItem.fromJson(Map<String, dynamic> j) => BalanceItem(
        currency: (j['currency'] ?? '').toString(),
        balance: j['balance'] is num
            ? j['balance'] as num
            : num.tryParse('${j['balance']}') ?? 0,
        balanceDue: j['balance_due'] is num
            ? j['balance_due'] as num
            : num.tryParse('${j['balance_due']}'),
      );
}

class CurrentBalance {
  final int? userId;
  final String? defaultCurrency;
  final List<BalanceItem> items;

  CurrentBalance({this.userId, this.defaultCurrency, required this.items});

  factory CurrentBalance.fromJson(Map<String, dynamic> j) => CurrentBalance(
        userId: j['user_id'] is int
            ? j['user_id'] as int
            : int.tryParse('${j['user_id']}'),
        defaultCurrency: j['default_currency']?.toString(),
        items: (j['items'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(BalanceItem.fromJson)
            .toList(),
      );
}
