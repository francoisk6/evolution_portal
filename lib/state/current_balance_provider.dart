import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/current_balance.dart';
import '../services/api_service.dart';

/// Persistent + self-throttled current-balance store
final currentBalanceProvider =
    AsyncNotifierProvider<CurrentBalanceNotifier, CurrentBalance?>(
  CurrentBalanceNotifier.new,
);

class CurrentBalanceNotifier extends AsyncNotifier<CurrentBalance?> {
  DateTime? _lastFetchAt;
  final Duration _minFetchGap = const Duration(seconds: 8);

  // Keep the last good value so UI can remain stable during refresh.
  CurrentBalance? _lastGood;

  // Track session currency explicitly, because /auth/change-currency/
  // returns {data: {current_currency}} while /balance/current-balance/
  // returns {default_currency}. We want the UI to reflect what the
  // session is using *right now* even if default hasn't changed yet.
  String? _activeCurrency;
  String? get activeCurrency =>
      _activeCurrency ?? state.value?.defaultCurrency?.toUpperCase();

  @override
  Future<CurrentBalance?> build() async => _fetch(force: true);

  Future<CurrentBalance?> _fetch({bool force = false}) async {
    final now = DateTime.now();
    if (!force && _lastFetchAt != null) {
      if (now.difference(_lastFetchAt!) < _minFetchGap) {
        // Never return null while throttled if we have a last good value.
        return _lastGood ?? state.valueOrNull;
      }
    }

    // If user is logged out (or we just wiped state), don't hit the API.
    final authed = await ApiService.instance.isAuthenticated();
    if (!authed) {
      _lastFetchAt = now;
      _activeCurrency = null;
      state = const AsyncData(null);
      return null;
    }

    final map = await ApiService.instance.getCurrentBalance();
    final cb = CurrentBalance.fromJson(map);
    _lastFetchAt = now;

    // Remember the last successful value.
    _lastGood = cb;

    // If activeCurrency not set yet, initialize from API; else keep override.
    final apiDefault = cb.defaultCurrency?.toUpperCase();
    _activeCurrency ??= apiDefault;

    // If override currency not present in items anymore, fall back to API default.
    final currencies = cb.items.map((e) => e.currency.toUpperCase()).toSet();
    if (_activeCurrency != null && !currencies.contains(_activeCurrency)) {
      _activeCurrency = apiDefault;
    }

    state = AsyncData(cb);
    return cb;
  }

  Future<void> refreshBalances({bool force = false}) async {
    // If we are not authenticated, keep UI clean and avoid 401 requests.
    final authed = await ApiService.instance.isAuthenticated();
    if (!authed) {
      _lastFetchAt = null;
      _activeCurrency = null;
      _lastGood = null;
      state = const AsyncData(null);
      return;
    }

    // Keep previously loaded balances visible during refresh (no blank chips).
    // Only show a loading state when we truly have nothing to render yet.
    final preserve = _lastGood ?? state.valueOrNull;
    if (preserve == null) {
      state = const AsyncLoading();
    } else {
      state = AsyncData(preserve);
    }
    try {
      await _fetch(force: force);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> changeCurrency(String currencyCode) async {
    final c = await ApiService.instance.changeCurrency(currencyCode);
    // Prefer the server's reply; if null, use the one we sent.
    _activeCurrency = (c ?? currencyCode).toUpperCase();
    await refreshBalances(force: true);
  }

  void reset() {
    _lastFetchAt = null;
    _activeCurrency = null;
    _lastGood = null;
    state = const AsyncData(null);
  }
}
