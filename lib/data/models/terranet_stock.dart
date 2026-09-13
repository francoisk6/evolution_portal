// Models for the TerraNet stock endpoints (superuser only):
//   GET  /api/online/terranet/stock/          → last completed reading, never blocks
//   POST /api/online/terranet/stock/refresh/  → queues a new reading (202 + job_id)
//
// The counts live on the provider's portal, not in our database, so a reading
// is taken asynchronously: queue a refresh, then poll the GET until
// `pendingJobs` drops to zero.
//
// A card moves in one direction: virgin → reserved → redeemed.
//   usable     virgin — the ONLY figure that is free to sell or spend
//   recovered  code revealed, not yet redeemed — spoken for, never sellable
//   available  usable + recovered ("not yet consumed", NOT "sellable")
//   used       redeemed; gone from the stock list
//   total      available + used

class TerranetStockTotals {
  final int total;
  final int available;
  final int usable;
  final int recovered;
  final int used;

  const TerranetStockTotals({
    required this.total,
    required this.available,
    required this.usable,
    required this.recovered,
    required this.used,
  });

  factory TerranetStockTotals.fromJson(Map<String, dynamic> json) {
    int n(String key) => (json[key] as num?)?.toInt() ?? 0;
    return TerranetStockTotals(
      total: n('total'),
      available: n('available'),
      usable: n('usable'),
      recovered: n('recovered'),
      used: n('used'),
    );
  }

  /// The two identities the backend asserts:
  ///   available == usable + recovered
  ///   total     == available + used
  /// A payload that breaks either one is suspect and must not be rendered
  /// as fact.
  bool get consistent =>
      available == usable + recovered && total == available + used;
}

class TerranetStockType {
  final String type;
  final int available;
  final int usable;
  final int recovered;

  const TerranetStockType({
    required this.type,
    required this.available,
    required this.usable,
    required this.recovered,
  });

  factory TerranetStockType.fromJson(Map<String, dynamic> json) {
    int n(String key) => (json[key] as num?)?.toInt() ?? 0;
    return TerranetStockType(
      type: json['type']?.toString() ?? '-',
      available: n('available'),
      usable: n('usable'),
      recovered: n('recovered'),
    );
  }

  /// The portal reports stock, but none of it can be sold — the case the
  /// handover warns about (e.g. D11: 5 available, 0 usable).
  bool get availableButNotSellable => available > 0 && usable == 0;
}

class TerranetStockReading {
  final bool success;
  final DateTime? asOf;
  final int? ageSeconds;
  final bool stale;
  final int pendingJobs;

  /// True => the sweep couldn't read every row, so every count is an
  /// undercount. Show the reading as incomplete rather than as fact.
  final bool partial;

  /// Null before the first reading — an empty state, never a table of zeros.
  final TerranetStockTotals? totals;

  /// All card types are always present, including those at zero.
  final List<TerranetStockType> types;

  final String message;

  const TerranetStockReading({
    required this.success,
    required this.asOf,
    required this.ageSeconds,
    required this.stale,
    required this.pendingJobs,
    required this.partial,
    required this.totals,
    required this.types,
    required this.message,
  });

  factory TerranetStockReading.fromJson(Map<String, dynamic> json) {
    final totalsRaw = json['totals'];
    final typesRaw = json['types'];

    final types = (typesRaw is List)
        ? typesRaw
            .whereType<Map>()
            .map((e) => TerranetStockType.fromJson(e.cast<String, dynamic>()))
            .toList()
        : const <TerranetStockType>[];

    return TerranetStockReading(
      success: json['success'] == true,
      asOf: DateTime.tryParse(json['as_of']?.toString() ?? '')?.toLocal(),
      ageSeconds: (json['age_seconds'] as num?)?.toInt(),
      stale: json['stale'] == true,
      pendingJobs: (json['pending_jobs'] as num?)?.toInt() ?? 0,
      partial: json['partial'] == true,
      totals: totalsRaw is Map
          ? TerranetStockTotals.fromJson(totalsRaw.cast<String, dynamic>())
          : null,
      types: types,
      message: json['message']?.toString() ?? '',
    );
  }

  /// No reading has been taken yet (or the last one produced nothing).
  bool get hasReading => totals != null;

  /// A refresh is in flight on the backend.
  bool get refreshing => pendingJobs > 0;

  bool get consistent => totals?.consistent ?? true;

  /// Age of the reading — from `age_seconds` when present, otherwise derived
  /// from `as_of`.
  Duration? get age {
    final seconds = ageSeconds;
    if (seconds != null) return Duration(seconds: seconds);
    final stamp = asOf;
    if (stamp == null) return null;
    return DateTime.now().difference(stamp);
  }
}

/// Result of POST .../stock/refresh/.
class TerranetRefreshQueued {
  /// False when a reading was already running — that job is reused rather than
  /// stacking another.
  final bool queued;
  final String? jobId;
  final String message;

  const TerranetRefreshQueued({
    required this.queued,
    required this.jobId,
    required this.message,
  });

  factory TerranetRefreshQueued.fromJson(Map<String, dynamic> json) {
    final id = json['job_id'];
    return TerranetRefreshQueued(
      // 202 carries a job_id; 200 carries queued:false.
      queued: json['queued'] != false,
      jobId: id?.toString(),
      message: json['message']?.toString() ?? '',
    );
  }
}

/// Outcome of "queue a refresh, then wait for it".
class TerranetRefreshOutcome {
  final TerranetStockReading reading;
  final bool queued;

  /// False => we stopped waiting before the worker finished. [reading] is then
  /// the last one we saw, which may still be the previous (stale) reading.
  final bool completed;

  const TerranetRefreshOutcome({
    required this.reading,
    required this.queued,
    required this.completed,
  });
}
