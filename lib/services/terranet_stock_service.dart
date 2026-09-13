import '../data/models/terranet_stock.dart';
import 'api_service.dart';

class TerranetStockService {
  TerranetStockService._();
  static final TerranetStockService instance = TerranetStockService._();

  /// How long to wait between polls while a reading is in flight.
  static const Duration pollInterval = Duration(seconds: 5);

  /// A reading takes roughly 40 seconds (the worker drives a real browser
  /// through four pages of the portal's stock list). Stop waiting well after
  /// that rather than spinning forever.
  static const Duration pollTimeout = Duration(seconds: 90);

  /// Last completed reading. Never blocks; safe to call on screen open.
  Future<TerranetStockReading> fetch() async {
    final m = await ApiService.instance.getTerranetStock();
    return TerranetStockReading.fromJson(m);
  }

  /// Queue a reading without waiting for it.
  ///
  /// Explicit user action only — see [ApiService.refreshTerranetStock].
  Future<TerranetRefreshQueued> queueRefresh() async {
    final m = await ApiService.instance.refreshTerranetStock();
    return TerranetRefreshQueued.fromJson(m);
  }

  /// Queue a reading, then poll until the worker finishes.
  ///
  /// [onPoll] receives every intermediate reading so the caller can keep the
  /// screen live while waiting. [cancelled] is checked before each poll so a
  /// disposed screen stops the loop.
  ///
  /// On timeout this returns `completed: false` with the last reading seen —
  /// surfacing a stale reading beats spinning forever.
  Future<TerranetRefreshOutcome> refreshAndWait({
    void Function(TerranetStockReading reading)? onPoll,
    bool Function()? cancelled,
  }) async {
    final queued = await queueRefresh();

    final deadline = DateTime.now().add(pollTimeout);
    var reading = await fetch();
    onPoll?.call(reading);

    while (reading.refreshing && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(pollInterval);
      if (cancelled?.call() ?? false) {
        return TerranetRefreshOutcome(
          reading: reading,
          queued: queued.queued,
          completed: false,
        );
      }
      reading = await fetch();
      onPoll?.call(reading);
    }

    return TerranetRefreshOutcome(
      reading: reading,
      queued: queued.queued,
      completed: !reading.refreshing,
    );
  }
}
