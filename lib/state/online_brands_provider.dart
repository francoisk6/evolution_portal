import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/online_brand_payload.dart';
import '../services/api_service.dart';

@immutable
class OnlineBrandsQuery {
  static const Object _unset = Object();

  final int groupDetailId;
  final String? productKey; // used by /api/online/product-details/brands/
  final String? searchMode; // e.g. "startswith"
  final String currency; // "LBP" | "USD"
  final int? gsd;

  const OnlineBrandsQuery({
    required this.groupDetailId,
    this.productKey,
    this.searchMode,
    required this.currency,
    this.gsd,
  });

  OnlineBrandsQuery copyWith({
    int? groupDetailId,
    Object? productKey = _unset,
    Object? searchMode = _unset,
    String? currency,
    Object? gsd = _unset,
  }) {
    return OnlineBrandsQuery(
      groupDetailId: groupDetailId ?? this.groupDetailId,
      productKey: identical(productKey, _unset)
          ? this.productKey
          : productKey as String?,
      searchMode: identical(searchMode, _unset)
          ? this.searchMode
          : searchMode as String?,
      currency: currency ?? this.currency,
      gsd: identical(gsd, _unset) ? this.gsd : gsd as int?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OnlineBrandsQuery &&
          runtimeType == other.runtimeType &&
          groupDetailId == other.groupDetailId &&
          productKey == other.productKey &&
          searchMode == other.searchMode &&
          currency == other.currency &&
          gsd == other.gsd;

  @override
  int get hashCode => Object.hash(groupDetailId, productKey, searchMode, currency, gsd);
}

final onlineBrandsPayloadProvider = FutureProvider.autoDispose
    .family<OnlineBrandsPayload, OnlineBrandsQuery>((ref, q) async {
  final key = (q.productKey ?? '').trim();
  if (key.isNotEmpty) {
    return ApiService.instance.getOnlineProductBrandsPayload(
      q: key,
      searchMode: q.searchMode,
      currency: q.currency,
      gsd: q.gsd,
    );
  }

  return ApiService.instance.getOnlineBrandsPayload(
    groupDetailId: q.groupDetailId,
    currency: q.currency,
    gsd: q.gsd,
  );
});
