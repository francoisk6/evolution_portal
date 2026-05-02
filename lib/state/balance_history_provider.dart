import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/balance_service.dart';

Map<String, dynamic> _asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.cast<String, dynamic>();
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _asMapList(dynamic v) {
  final raw = (v as List?) ?? const <dynamic>[];
  return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
}

String? _asCleanString(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

int? _asIntOrNull(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  return int.tryParse(s);
}

bool? _asBoolOrNull(dynamic v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().trim().toLowerCase();
  if (s.isEmpty) return null;
  if (s == 'true' || s == '1' || s == 'yes' || s == 'y') return true;
  if (s == 'false' || s == '0' || s == 'no' || s == 'n') return false;
  return null;
}

class BalanceEntry {
  final int id;
  final DateTime date;
  final String currencyCode;
  final double amount;
  final bool? status;
  final String? username;
  final double? balance;
  final double? balanceDue;
  final dynamic note;

  BalanceEntry({
    required this.id,
    required this.date,
    required this.currencyCode,
    required this.amount,
    this.status,
    this.username,
    this.balance,
    this.balanceDue,
    this.note,
  });

  static DateTime _parseDate(dynamic v) {
    if (v == null) return DateTime.now();
    final s = v.toString();
    try {
      return DateTime.parse(s);
    } catch (_) {
      return DateTime.now();
    }
  }

  static double? _parseNullableNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = v.toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null') return null;
    return double.tryParse(s);
  }

  factory BalanceEntry.fromJson(Map<String, dynamic> m) {
    final id =
        int.tryParse('${m['id'] ?? m['pk'] ?? m['balance_id'] ?? 0}') ?? 0;
    final date = _parseDate(
      m['created'] ?? m['created_at'] ?? m['date'] ?? m['datetime'],
    );

    final currency = (m['currency'] is Map)
        ? (m['currency']['code'] ?? m['currency']['name'] ?? '').toString()
        : (m['currency_code'] ?? m['currency'] ?? '').toString();

    final amount = double.tryParse(
          '${m['amount'] ?? m['value'] ?? m['change'] ?? m['delta'] ?? 0}',
        ) ??
        0.0;

    final stRaw = m['status'] ?? m['approved'] ?? m['is_approved'] ?? m['ok'];
    bool? st;
    if (stRaw is bool) {
      st = stRaw;
    } else if (stRaw is String) {
      final s = stRaw.toLowerCase().trim();
      if (s == 'true' || s == '1') {
        st = true;
      } else if (s == 'false' || s == '0') {
        st = false;
      }
    } else if (stRaw is num) {
      st = stRaw != 0;
    }

    final user = (m['user'] is Map)
        ? (m['user']['username'] ?? m['user']['name'] ?? '').toString()
        : (m['username'] ?? m['user_name'] ?? '').toString();

    final balance = _parseNullableNum(
      m['balance'] ?? m['current_balance'] ?? m['running_balance'],
    );

    final balanceDue = _parseNullableNum(
      m['balance_due'] ?? m['due_balance'] ?? m['due'] ?? m['running_due'],
    );

    final note = m.containsKey('note')
        ? m['note']
        : (m.containsKey('notes') ? m['notes'] : m['remark']);

    return BalanceEntry(
      id: id,
      date: date,
      currencyCode: currency,
      amount: amount,
      status: st,
      username: user.isEmpty ? null : user,
      balance: balance,
      balanceDue: balanceDue,
      note: note,
    );
  }
}

class BalanceFilterUserOption {
  final int id;
  final String username;
  final String label;

  const BalanceFilterUserOption({
    required this.id,
    required this.username,
    required this.label,
  });

  factory BalanceFilterUserOption.fromJson(Map<String, dynamic> m) {
    final username = _asCleanString(m['username']) ??
        _asCleanString(m['name']) ??
        _asCleanString(m['label']) ??
        '';
    return BalanceFilterUserOption(
      id: _asIntOrNull(m['id']) ?? 0,
      username: username,
      label: _asCleanString(m['label']) ?? username,
    );
  }
}

class BalanceFilterCurrencyOption {
  final int? id;
  final String code;
  final String label;

  const BalanceFilterCurrencyOption({
    required this.id,
    required this.code,
    required this.label,
  });

  factory BalanceFilterCurrencyOption.fromJson(Map<String, dynamic> m) {
    final code = (_asCleanString(m['code']) ??
            _asCleanString(m['name']) ??
            _asCleanString(m['currency']) ??
            _asCleanString(m['label']) ??
            '')
        .toUpperCase();
    return BalanceFilterCurrencyOption(
      id: _asIntOrNull(m['id']),
      code: code,
      label: _asCleanString(m['label']) ?? code,
    );
  }
}

class BalanceFilterSelected {
  final int? userId;
  final int? currencyId;
  final String? currencyCode;
  final bool? status;
  final bool? distinctUsers;

  const BalanceFilterSelected({
    this.userId,
    this.currencyId,
    this.currencyCode,
    this.status,
    this.distinctUsers,
  });

  factory BalanceFilterSelected.fromJson(Map<String, dynamic> m) {
    return BalanceFilterSelected(
      userId: _asIntOrNull(m['user_id'] ?? m['user']),
      currencyId: _asIntOrNull(m['currency_id']),
      currencyCode: _asCleanString(m['currency'])?.toUpperCase(),
      status: _asBoolOrNull(m['status']),
      distinctUsers: _asBoolOrNull(
        m['distinct_users'] ?? m['distinctUsers'],
      ),
    );
  }
}

class BalanceFilterAvailable {
  final List<BalanceFilterUserOption> users;
  final List<BalanceFilterCurrencyOption> currencies;

  const BalanceFilterAvailable({
    required this.users,
    required this.currencies,
  });

  bool get hasAnyOptions => users.isNotEmpty || currencies.isNotEmpty;

  factory BalanceFilterAvailable.fromJson(Map<String, dynamic> m) {
    return BalanceFilterAvailable(
      users: _asMapList(m['users'])
          .map(BalanceFilterUserOption.fromJson)
          .where((e) => e.id > 0)
          .toList(),
      currencies: _asMapList(m['currencies'])
          .map(BalanceFilterCurrencyOption.fromJson)
          .where((e) => e.code.trim().isNotEmpty || e.id != null)
          .toList(),
    );
  }
}

class BalanceFilterData {
  final BalanceFilterSelected? selected;
  final BalanceFilterAvailable? available;

  const BalanceFilterData({required this.selected, required this.available});

  factory BalanceFilterData.fromJson(Map<String, dynamic> m) {
    final selectedMap = _asMap(m['selected']);
    final availableMap = _asMap(m['available']);
    return BalanceFilterData(
      selected: selectedMap.isEmpty
          ? null
          : BalanceFilterSelected.fromJson(selectedMap),
      available: availableMap.isEmpty
          ? null
          : BalanceFilterAvailable.fromJson(availableMap),
    );
  }
}

class _Unset {
  const _Unset();
}

const _balanceUnset = _Unset();

class BalanceFilters {
  final DateTime? from;
  final DateTime? to;
  final bool? status; // null=All
  final int? currencyId;
  final int? userId;
  final bool distinctUsers;

  const BalanceFilters({
    this.from,
    this.to,
    this.status,
    this.currencyId,
    this.userId,
    this.distinctUsers = false,
  });

  BalanceFilters copyWith({
    Object? from = _balanceUnset,
    Object? to = _balanceUnset,
    Object? status = _balanceUnset,
    Object? currencyId = _balanceUnset,
    Object? userId = _balanceUnset,
    Object? distinctUsers = _balanceUnset,
  }) {
    return BalanceFilters(
      from: from is _Unset ? this.from : from as DateTime?,
      to: to is _Unset ? this.to : to as DateTime?,
      status: status is _Unset ? this.status : status as bool?,
      currencyId: currencyId is _Unset ? this.currencyId : currencyId as int?,
      userId: userId is _Unset ? this.userId : userId as int?,
      distinctUsers: distinctUsers is _Unset
          ? this.distinctUsers
          : distinctUsers as bool,
    );
  }

  BalanceFilters applyBackendSelected(BalanceFilterSelected selected) {
    return BalanceFilters(
      from: from,
      to: to,
      status: status,
      currencyId: selected.currencyId ?? currencyId,
      userId: selected.userId ?? userId,
      distinctUsers: selected.distinctUsers ?? distinctUsers,
    );
  }
}

class BalanceHistoryState {
  final List<BalanceEntry> items;
  final int page;
  final bool loading;
  final bool hasMore;
  final BalanceFilters filters;
  final BalanceFilterData? filterData;

  const BalanceHistoryState({
    this.items = const [],
    this.page = 1,
    this.loading = false,
    this.hasMore = true,
    this.filters = const BalanceFilters(),
    this.filterData,
  });

  BalanceHistoryState copyWith({
    List<BalanceEntry>? items,
    int? page,
    bool? loading,
    bool? hasMore,
    BalanceFilters? filters,
    Object? filterData = _balanceUnset,
  }) {
    return BalanceHistoryState(
      items: items ?? this.items,
      page: page ?? this.page,
      loading: loading ?? this.loading,
      hasMore: hasMore ?? this.hasMore,
      filters: filters ?? this.filters,
      filterData: filterData is _Unset
          ? this.filterData
          : filterData as BalanceFilterData?,
    );
  }
}

class BalanceHistoryNotifier extends StateNotifier<BalanceHistoryState> {
  BalanceHistoryNotifier() : super(const BalanceHistoryState());

  Future<void> refresh() => fetch(reset: true);

  void setFilters(BalanceFilters f) {
    state = state.copyWith(filters: f, page: 1, items: [], hasMore: true);
  }

  Future<void> fetch({bool reset = false}) async {
    if (state.loading) return;

    final nextPage = reset ? 1 : state.page;
    state = state.copyWith(loading: true);

    try {
      final data = await BalanceService.instance.history(
        page: nextPage,
        dateFrom: state.filters.from,
        dateTo: state.filters.to,
        status: state.filters.status,
        currencyId: state.filters.currencyId,
        distinctUsers: state.filters.distinctUsers,
        userId: state.filters.userId,
        includeFilters: reset,
      );

      final List<dynamic> rawList =
          (data['results'] as List?) ?? const <dynamic>[];
      final entries = rawList
          .whereType<Map<String, dynamic>>()
          .map(BalanceEntry.fromJson)
          .toList();

      final newList = reset ? entries : [...state.items, ...entries];

      final count = (data['count'] as int?) ?? newList.length;
      final currentPage = (data['page'] as int?) ?? nextPage;
      final pageSize =
          (data['page_size'] as int?) ?? (entries.isEmpty ? 0 : entries.length);
      int? totalPages;
      if (pageSize > 0) {
        totalPages = ((count + pageSize - 1) ~/ pageSize);
      }

      final hasMore =
          (totalPages != null) ? currentPage < totalPages : entries.isNotEmpty;

      final nextFilterData = reset
          ? (() {
              final filtersMap = _asMap(data['filters']);
              return filtersMap.isEmpty
                  ? null
                  : BalanceFilterData.fromJson(filtersMap);
            })()
          : state.filterData;

      var nextFilters = state.filters;
      final selected = nextFilterData?.selected;
      if (reset && selected != null) {
        nextFilters = nextFilters.applyBackendSelected(selected);
      }

      state = state.copyWith(
        items: newList,
        page: nextPage + 1,
        hasMore: hasMore,
        loading: false,
        filterData: nextFilterData,
        filters: nextFilters,
      );
    } catch (_) {
      state = state.copyWith(loading: false);
    }
  }
}

final balanceHistoryProvider =
    StateNotifierProvider<BalanceHistoryNotifier, BalanceHistoryState>(
  (ref) => BalanceHistoryNotifier(),
);
