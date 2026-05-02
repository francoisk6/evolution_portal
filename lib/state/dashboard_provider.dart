import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/dashboard_aggregates.dart';
import '../services/dashboard_service.dart';
import 'currency_provider.dart';

/// Special filter value: request no currency filter (all currencies).
///
/// The dashboard default uses this value so the first load shows all currencies.
/// If [DashboardFilters.currency] is null/empty, the request uses the app-selected
/// currency instead.
const String kDashboardCurrencyAll = '__ALL__';

class DashboardFilters {
  final DateTime? from;
  final DateTime? to;
  final String? currency;
  final String? status;
  final int top;
  // Superuser-only filters
  final int? userId;
  final String? userIds; // comma-separated

  const DashboardFilters({
    this.from,
    this.to,
    this.currency = kDashboardCurrencyAll,
    this.status,
    this.top = 10,
    this.userId,
    this.userIds,
  });

  DashboardFilters copyWith({
    DateTime? from,
    DateTime? to,
    String? currency,
    String? status,
    int? top,
    int? userId,
    String? userIds,
    bool clearDateFrom = false,
    bool clearDateTo = false,
    bool clearCurrency = false,
    bool clearStatus = false,
    bool clearUser = false,
  }) {
    return DashboardFilters(
      from: clearDateFrom ? null : (from ?? this.from),
      to: clearDateTo ? null : (to ?? this.to),
      currency: clearCurrency ? null : (currency ?? this.currency),
      status: clearStatus ? null : (status ?? this.status),
      top: top ?? this.top,
      userId: clearUser ? null : (userId ?? this.userId),
      userIds: clearUser ? null : (userIds ?? this.userIds),
    );
  }
}

class DashboardState {
  final DashboardMeta? meta;
  final DashboardData? data;
  final bool loading;
  final String? error;
  final DashboardFilters filters;

  const DashboardState({
    this.meta,
    this.data,
    this.loading = false,
    this.error,
    this.filters = const DashboardFilters(),
  });

  DashboardState copyWith({
    DashboardMeta? meta,
    DashboardData? data,
    bool? loading,
    String? error,
    DashboardFilters? filters,
    bool clearError = false,
  }) {
    return DashboardState(
      meta: meta ?? this.meta,
      data: data ?? this.data,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      filters: filters ?? this.filters,
    );
  }
}

class DashboardNotifier extends StateNotifier<DashboardState> {
  final Ref ref;
  DashboardNotifier(this.ref) : super(const DashboardState());

  static String _ymd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final da = d.day.toString().padLeft(2, '0');
    return '$y-$m-$da';
  }

  void setFilters(DashboardFilters f) {
    state = state.copyWith(filters: f);
  }

  Future<void> refresh() async => fetch();

  Future<void> fetch() async {
    if (state.loading) return;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final now = DateTime.now();

      // Default to last 30 days if not provided.
      final df = state.filters.from ?? now.subtract(const Duration(days: 30));
      final dt = state.filters.to ?? now;

      // Dashboard default uses all currencies; null/empty keeps the app-selected currency mode.
      final selectedCode = ref.read(currencyProvider).selected.code;
      final rawCurrency = state.filters.currency;
      final String? currency;
      if (rawCurrency == null || rawCurrency.trim().isEmpty) {
        currency = selectedCode;
      } else if (rawCurrency.trim() == kDashboardCurrencyAll) {
        currency = null; // no filter
      } else {
        currency = rawCurrency.trim().toUpperCase();
      }

      final status = (state.filters.status?.trim().isEmpty ?? true)
          ? null
          : state.filters.status!.trim();

      final top = state.filters.top < 1
          ? 1
          : (state.filters.top > 50 ? 50 : state.filters.top);

      final resp = await DashboardService.instance.get(
        dateFrom: _ymd(df),
        dateTo: _ymd(dt),
        currency: currency,
        status: status,
        top: top,
        userId: state.filters.userId,
        userIds: (state.filters.userIds?.trim().isEmpty ?? true)
            ? null
            : state.filters.userIds!.trim(),
      );

      state = state.copyWith(
        meta: resp.meta,
        data: resp.data,
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: e.toString(),
      );
    }
  }
}

final dashboardProvider =
    StateNotifierProvider<DashboardNotifier, DashboardState>((ref) {
  return DashboardNotifier(ref);
});
