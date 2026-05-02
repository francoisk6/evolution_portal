import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/transaction_history.dart';
import '../services/transaction_service.dart';

class _Unset {
  const _Unset();
}

const _txUnset = _Unset();

class TransactionFilters {
  final DateTime? from;
  final DateTime? to;
  final String? currency;
  final String? status;
  final String? q;
  final int limit;
  final int? userId;
  final int? sectorId;
  final int? productId;
  final int? brandId;
  final bool? brandNotNull;

  const TransactionFilters({
    this.from,
    this.to,
    this.currency,
    this.status,
    this.q,
    this.limit = 50,
    this.userId,
    this.sectorId,
    this.productId,
    this.brandId,
    this.brandNotNull,
  });

  TransactionFilters copyWith({
    Object? from = _txUnset,
    Object? to = _txUnset,
    Object? currency = _txUnset,
    Object? status = _txUnset,
    Object? q = _txUnset,
    int? limit,
    Object? userId = _txUnset,
    Object? sectorId = _txUnset,
    Object? productId = _txUnset,
    Object? brandId = _txUnset,
    Object? brandNotNull = _txUnset,
  }) {
    return TransactionFilters(
      from: from is _Unset ? this.from : from as DateTime?,
      to: to is _Unset ? this.to : to as DateTime?,
      currency: currency is _Unset ? this.currency : currency as String?,
      status: status is _Unset ? this.status : status as String?,
      q: q is _Unset ? this.q : q as String?,
      limit: limit ?? this.limit,
      userId: userId is _Unset ? this.userId : userId as int?,
      sectorId: sectorId is _Unset ? this.sectorId : sectorId as int?,
      productId: productId is _Unset ? this.productId : productId as int?,
      brandId: brandId is _Unset ? this.brandId : brandId as int?,
      brandNotNull: brandNotNull is _Unset
          ? this.brandNotNull
          : brandNotNull as bool?,
    );
  }

  TransactionFilters applyBackendSelected(TransactionFilterSelected selected) {
    return TransactionFilters(
      from: from,
      to: to,
      limit: limit,
      currency: selected.currency,
      status: selected.status,
      q: selected.q,
      userId: selected.userId,
      sectorId: selected.sectorId,
      productId: selected.productId,
      brandId: selected.brandId,
      brandNotNull: selected.brandNotNull,
    );
  }
}

class TransactionHistoryState {
  final TransactionMeta? meta;
  final TransactionSummary? summary;
  final TransactionFilterData? filterData;
  final List<TransactionListItem> items;
  final bool isInitialLoading;
  final bool isRefreshing;
  final bool isLoadingMore;
  final bool hasMore;
  final String? cursor;
  final TransactionFilters filters;
  final String? errorMessage;

  const TransactionHistoryState({
    this.meta,
    this.summary,
    this.filterData,
    this.items = const [],
    this.isInitialLoading = false,
    this.isRefreshing = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.cursor,
    this.filters = const TransactionFilters(),
    this.errorMessage,
  });

  bool get loading => isInitialLoading || isRefreshing || isLoadingMore;

  TransactionFilterAvailable? get availableFilters => filterData?.available;

  TransactionHistoryState copyWith({
    Object? meta = _txUnset,
    Object? summary = _txUnset,
    Object? filterData = _txUnset,
    List<TransactionListItem>? items,
    bool? isInitialLoading,
    bool? isRefreshing,
    bool? isLoadingMore,
    bool? hasMore,
    Object? cursor = _txUnset,
    TransactionFilters? filters,
    Object? errorMessage = _txUnset,
  }) {
    return TransactionHistoryState(
      meta: meta is _Unset ? this.meta : meta as TransactionMeta?,
      summary: summary is _Unset ? this.summary : summary as TransactionSummary?,
      filterData: filterData is _Unset
          ? this.filterData
          : filterData as TransactionFilterData?,
      items: items ?? this.items,
      isInitialLoading: isInitialLoading ?? this.isInitialLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      cursor: cursor is _Unset ? this.cursor : cursor as String?,
      filters: filters ?? this.filters,
      errorMessage:
          errorMessage is _Unset ? this.errorMessage : errorMessage as String?,
    );
  }
}

class TransactionHistoryNotifier extends StateNotifier<TransactionHistoryState> {
  TransactionHistoryNotifier() : super(const TransactionHistoryState());

  void setFilters(TransactionFilters next) {
    final sanitized = _sanitizeFilters(next, state.availableFilters);
    state = state.copyWith(
      filters: sanitized,
      items: const [],
      hasMore: true,
      cursor: null,
      meta: null,
      summary: null,
      errorMessage: null,
    );
  }

  Future<void> refresh() async => fetch(reset: true);

  Future<void> fetchMore() async {
    if (!state.hasMore || state.isLoadingMore || state.isInitialLoading) return;
    await fetch(reset: false);
  }

  static String _ymd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final da = d.day.toString().padLeft(2, '0');
    return '$y-$m-$da';
  }

  TransactionFilters _sanitizeFilters(
    TransactionFilters filters,
    TransactionFilterAvailable? available,
  ) {
    if (available == null) return filters;

    int? sectorId = filters.sectorId;
    int? productId = filters.productId;
    int? brandId = filters.brandId;

    bool productMatchesSector(int? selectedProductId, int? selectedSectorId) {
      if (selectedProductId == null || selectedSectorId == null) return true;
      TransactionFilterProductOption? product;
      for (final entry in available.products) {
        if (entry.id == selectedProductId) {
          product = entry;
          break;
        }
      }
      if (product == null || product.sectorId == null) return true;
      return product.sectorId == selectedSectorId;
    }

    bool brandMatches(
      int? selectedBrandId,
      int? selectedSectorId,
      int? selectedProductId,
    ) {
      if (selectedBrandId == null) return true;
      TransactionFilterBrandOption? brand;
      for (final entry in available.brands) {
        if (entry.id == selectedBrandId) {
          brand = entry;
          break;
        }
      }
      if (brand == null) return true;
      if (selectedSectorId != null &&
          brand.sectorId != null &&
          brand.sectorId != selectedSectorId) {
        return false;
      }
      if (selectedProductId != null &&
          brand.productId != null &&
          brand.productId != selectedProductId) {
        return false;
      }
      return true;
    }

    if (!productMatchesSector(productId, sectorId)) {
      productId = null;
    }
    if (!brandMatches(brandId, sectorId, productId)) {
      brandId = null;
    }

    return filters.copyWith(productId: productId, brandId: brandId);
  }

  List<TransactionListItem> _mergeItems(
    List<TransactionListItem> base,
    List<TransactionListItem> incoming,
  ) {
    final out = <TransactionListItem>[];
    final seen = <int>{};

    for (final item in [...base, ...incoming]) {
      if (seen.add(item.id)) {
        out.add(item);
      }
    }
    return out;
  }

  Future<void> fetch({required bool reset}) async {
    if (state.loading && !(reset && state.isRefreshing)) return;

    final initial = reset && state.items.isEmpty;
    state = state.copyWith(
      isInitialLoading: initial,
      isRefreshing: reset && !initial,
      isLoadingMore: !reset,
      errorMessage: null,
    );

    try {
      final now = DateTime.now();
      final df = state.filters.from ?? now.subtract(const Duration(days: 1));
      final dt = state.filters.to ?? now;

      final resp = await TransactionService.instance.list(
        dateFrom: _ymd(df),
        dateTo: _ymd(dt),
        limit: state.filters.limit,
        cursor: reset ? null : state.cursor,
        includeSummary: reset,
        includeFilters: reset,
        includeBalance: true,
        currency: (state.filters.currency?.trim().isEmpty ?? true)
            ? null
            : state.filters.currency,
        status: (state.filters.status?.trim().isEmpty ?? true)
            ? null
            : state.filters.status,
        q: (state.filters.q?.trim().isEmpty ?? true) ? null : state.filters.q,
        userId: state.filters.userId,
        sectorId: state.filters.sectorId,
        productId: state.filters.productId,
        brandId: state.filters.brandId,
        brandNotNull: state.filters.brandNotNull,
      );

      final nextFilterData = reset ? (resp.filters ?? state.filterData) : state.filterData;
      var nextFilters = state.filters;
      final selected = resp.filters?.selected;
      if (reset && selected != null) {
        nextFilters = nextFilters.applyBackendSelected(selected);
      }
      nextFilters = _sanitizeFilters(nextFilters, nextFilterData?.available);

      state = state.copyWith(
        meta: resp.meta,
        summary: reset ? (resp.summary ?? state.summary) : state.summary,
        filterData: nextFilterData,
        items: reset ? _mergeItems(const [], resp.items) : _mergeItems(state.items, resp.items),
        hasMore: resp.meta.hasMore,
        cursor: resp.meta.nextCursor,
        filters: nextFilters,
        isInitialLoading: false,
        isRefreshing: false,
        isLoadingMore: false,
        errorMessage: null,
      );
    } catch (e) {
      state = state.copyWith(
        isInitialLoading: false,
        isRefreshing: false,
        isLoadingMore: false,
        errorMessage: e.toString(),
      );
    }
  }
}

final transactionHistoryProvider =
    StateNotifierProvider<TransactionHistoryNotifier, TransactionHistoryState>(
        (ref) => TransactionHistoryNotifier());
