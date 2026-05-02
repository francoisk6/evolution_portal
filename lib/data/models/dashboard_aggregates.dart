import 'package:flutter/foundation.dart';

double _asDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  final s = v.toString().replaceAll(',', '').trim();
  if (s.isEmpty) return 0;
  return double.tryParse(s) ?? 0;
}

int _asInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  final s = v.toString().replaceAll(',', '').trim();
  if (s.isEmpty) return 0;
  return int.tryParse(s) ?? 0;
}

bool _asBool(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  final s = v.toString().trim().toLowerCase();
  return s == 'true' || s == '1' || s == 'yes' || s == 'y';
}

DateTime? _tryDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

String? _tryString(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  return s.trim().isEmpty ? null : s;
}

List<int>? _tryIntList(dynamic v) {
  if (v == null) return null;
  if (v is List) {
    final out = <int>[];
    for (final x in v) {
      final i = _asInt(x);
      if (i != 0) out.add(i);
    }
    return out.isEmpty ? null : out;
  }
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  final parts = s.split(',');
  final out = <int>[];
  for (final p in parts) {
    final i = int.tryParse(p.trim());
    if (i != null && i != 0) out.add(i);
  }
  return out.isEmpty ? null : out;
}

@immutable
class DashboardTotals {
  final String currency;
  final double dealer;
  final double customer;
  final double dealerProfit;
  final double cost;
  final double adminProfit;
  final int count;

  const DashboardTotals({
    this.currency = '',
    this.dealer = 0,
    this.customer = 0,
    this.dealerProfit = 0,
    this.cost = 0,
    this.adminProfit = 0,
    this.count = 0,
  });

  factory DashboardTotals.fromJson(Map<String, dynamic> json) {
    return DashboardTotals(
      currency:     (json['currency'] ?? '').toString(),
      dealer:       _asDouble(json['dealer']),
      customer:     _asDouble(json['customer']),
      dealerProfit: _asDouble(json['dealer_profit']),
      cost:         _asDouble(json['cost']),
      adminProfit:  _asDouble(json['admin_profit']),
      count:        _asInt(json['count']),
    );
  }

  double metricValue(String metricLabel) {
    switch (metricLabel) {
      case 'Dealer':    return dealer;
      case 'Customer':  return customer;
      case 'D Profit':  return dealerProfit;
      case 'A Profit':  return adminProfit;
      case 'Cost':      return cost;
      case 'Count':     return count.toDouble();
      default:          return 0;
    }
  }
}

class DashboardResponse {
  final DashboardMeta meta;
  final DashboardData data;

  const DashboardResponse({required this.meta, required this.data});

  factory DashboardResponse.fromJson(Map<String, dynamic> json) {
    final meta = DashboardMeta.fromJson(
      (json['meta'] is Map) ? (json['meta'] as Map).cast<String, dynamic>() : const {},
    );
    final data = DashboardData.fromJson(
      (json['data'] is Map) ? (json['data'] as Map).cast<String, dynamic>() : const {},
    );
    return DashboardResponse(meta: meta, data: data);
  }
}

class DashboardMeta {
  /// Keep the raw meta so the UI can display/debug without tight coupling.
  final Map<String, dynamic> raw;

  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? currency;
  final String? status;
  final int? top;
  final bool isSuperuser;
  final int? userId;
  final List<int>? userIds;

  const DashboardMeta({
    required this.raw,
    this.dateFrom,
    this.dateTo,
    this.currency,
    this.status,
    this.top,
    this.isSuperuser = false,
    this.userId,
    this.userIds,
  });

  factory DashboardMeta.fromJson(Map<String, dynamic> meta) {
    // Support multiple possible server meta shapes.
    final filters = (meta['filters'] is Map)
        ? (meta['filters'] as Map).cast<String, dynamic>()
        : meta;
    final scope = (meta['scope'] is Map)
        ? (meta['scope'] as Map).cast<String, dynamic>()
        : meta;

    final df = _tryDate(filters['date_from'] ?? filters['from']);
    final dt = _tryDate(filters['date_to'] ?? filters['to']);
    final currency = _tryString(filters['currency']);
    final status = _tryString(filters['status']);
    final top = meta['top'] != null
        ? _asInt(meta['top'])
        : (filters['top'] != null ? _asInt(filters['top']) : null);

    final isSuperuser = _asBool(scope['is_superuser'] ?? meta['is_superuser']);
    final userId = (scope['user_id'] ?? meta['user_id']) != null
        ? _asInt(scope['user_id'] ?? meta['user_id'])
        : null;
    final userIds = _tryIntList(scope['user_ids'] ?? meta['user_ids']);

    return DashboardMeta(
      raw: meta,
      dateFrom: df,
      dateTo: dt,
      currency: currency,
      status: status,
      top: top,
      isSuperuser: isSuperuser,
      userId: (userId == 0) ? null : userId,
      userIds: userIds,
    );
  }
}

class DashboardData {
  // superuser-only blocks
  final List<DashboardItem> topUsers;
  final List<DashboardItem> topSectors;
  final List<DashboardItem> topGroupCategories;

  // all users blocks
  final List<DashboardItem> topGroupHeads;
  final List<DashboardItem> topGroupDetails;
  final List<DashboardItem> topGroupSubdetails;
  final List<DashboardItem> topBrands;

  // UI aliases (optional)
  final Map<String, dynamic> ui;

  // Pre-computed grand totals (with currency conversion when ALL currencies)
  final DashboardTotals? totals;

  const DashboardData({
    this.topUsers = const [],
    this.topSectors = const [],
    this.topGroupCategories = const [],
    this.topGroupHeads = const [],
    this.topGroupDetails = const [],
    this.topGroupSubdetails = const [],
    this.topBrands = const [],
    this.ui = const {},
    this.totals,
  });

  factory DashboardData.fromJson(Map<String, dynamic> data) {
    List<DashboardItem> parseList(dynamic v) {
      if (v is! List) return const [];
      return v
          .whereType<Map>()
          .map((m) => DashboardItem.fromJson(m.cast<String, dynamic>()))
          .toList(growable: false);
    }

    return DashboardData(
      topUsers: parseList(data['top_users']),
      topSectors: parseList(data['top_sectors']),
      topGroupCategories: parseList(data['top_group_categories']),
      topGroupHeads: parseList(data['top_group_heads']),
      topGroupDetails: parseList(data['top_group_details']),
      topGroupSubdetails: parseList(data['top_group_subdetails']),
      topBrands: parseList(data['top_brands']),
      ui: (data['ui'] is Map) ? (data['ui'] as Map).cast<String, dynamic>() : const {},
      totals: (data['totals'] is Map)
          ? DashboardTotals.fromJson((data['totals'] as Map).cast<String, dynamic>())
          : null,
    );
  }

  bool get hasAnyData =>
      topUsers.isNotEmpty ||
      topSectors.isNotEmpty ||
      topGroupCategories.isNotEmpty ||
      topGroupHeads.isNotEmpty ||
      topGroupDetails.isNotEmpty ||
      topGroupSubdetails.isNotEmpty ||
      topBrands.isNotEmpty;
}

class DashboardItem {
  final int id;
  final String label;
  final int count;
  final DashboardAmounts amounts;

  const DashboardItem({
    required this.id,
    required this.label,
    required this.count,
    required this.amounts,
  });

  factory DashboardItem.fromJson(Map<String, dynamic> json) {
    return DashboardItem(
      id: _asInt(json['id']),
      label: (json['label'] ?? '').toString(),
      count: _asInt(json['count']),
      amounts: DashboardAmounts.fromJson(
        (json['amounts'] is Map)
            ? (json['amounts'] as Map).cast<String, dynamic>()
            : const {},
      ),
    );
  }

  @override
  String toString() => 'DashboardItem(id: $id, label: $label, count: $count)';
}

@immutable
class DashboardAmounts {
  final double dealer;
  final double customer;
  final double dealerProfit;
  final double cost;
  final double adminProfit;

  const DashboardAmounts({
    this.dealer = 0,
    this.customer = 0,
    this.dealerProfit = 0,
    this.cost = 0,
    this.adminProfit = 0,
  });

  factory DashboardAmounts.fromJson(Map<String, dynamic> json) {
    return DashboardAmounts(
      dealer: _asDouble(json['dealer']),
      customer: _asDouble(json['customer']),
      dealerProfit: _asDouble(json['dealer_profit']),
      cost: _asDouble(json['cost']),
      adminProfit: _asDouble(json['admin_profit']),
    );
  }

  bool get hasCostFields => cost != 0 || adminProfit != 0;
}
