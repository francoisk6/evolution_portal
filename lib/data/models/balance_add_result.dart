class BalanceSummary {
  final String currency;
  final String balance;
  final String balanceDue;

  const BalanceSummary({
    required this.currency,
    required this.balance,
    required this.balanceDue,
  });

  factory BalanceSummary.fromJson(Map<String, dynamic> json) => BalanceSummary(
        currency: (json['currency'] ?? '').toString(),
        balance: json['balance']?.toString() ?? '0',
        balanceDue: json['balance_due']?.toString() ?? '0',
      );
}

class AddBalanceResult {
  final String message;
  final List<BalanceSummary> newBalances;

  const AddBalanceResult({
    required this.message,
    required this.newBalances,
  });

  factory AddBalanceResult.fromJson(Map<String, dynamic> json) => AddBalanceResult(
        message: (json['message'] ?? '').toString(),
        newBalances: (json['new_balances'] as List? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(BalanceSummary.fromJson)
            .toList(),
      );
}
