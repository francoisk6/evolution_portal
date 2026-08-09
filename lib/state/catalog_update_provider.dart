import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/catalog_update.dart';
import '../services/catalog_update_service.dart';

class CatalogUpdateState {
  final Map<String, CatalogRunState> runs;
  final CatalogRunEvent? lastEvent;

  const CatalogUpdateState({
    this.runs = const <String, CatalogRunState>{},
    this.lastEvent,
  });

  CatalogRunState stateFor(String key) => runs[key] ?? const CatalogRunState();

  CatalogUpdateState copyWith({
    Map<String, CatalogRunState>? runs,
    CatalogRunEvent? lastEvent,
  }) {
    return CatalogUpdateState(
      runs: runs ?? this.runs,
      lastEvent: lastEvent ?? this.lastEvent,
    );
  }
}

/// Holds catalog-run state outside the drawer widget, so a job that takes
/// minutes keeps reporting even after the drawer is closed and rebuilt.
class CatalogUpdateController extends StateNotifier<CatalogUpdateState> {
  CatalogUpdateController() : super(const CatalogUpdateState());

  Future<void> run(CatalogTarget target) async {
    if (state.stateFor(target.key).isRunning) return;

    _set(target.key, const CatalogRunState(status: CatalogRunStatus.running));

    final sw = Stopwatch()..start();
    try {
      final result = await CatalogUpdateService.instance.run(target);
      sw.stop();
      _finish(target, ok: true, message: result.message, elapsed: sw.elapsed);
    } catch (e) {
      sw.stop();
      _finish(target,
          ok: false, message: _friendlyError(e), elapsed: sw.elapsed);
    }
  }

  void _set(String key, CatalogRunState value) {
    state = state.copyWith(
      runs: <String, CatalogRunState>{...state.runs, key: value},
    );
  }

  void _finish(
    CatalogTarget target, {
    required bool ok,
    required String message,
    required Duration elapsed,
  }) {
    if (!mounted) return;
    state = CatalogUpdateState(
      runs: <String, CatalogRunState>{
        ...state.runs,
        target.key: CatalogRunState(
          status: ok ? CatalogRunStatus.success : CatalogRunStatus.failure,
          message: message,
          elapsed: elapsed,
        ),
      },
      lastEvent: CatalogRunEvent(
        target: target,
        ok: ok,
        message: message,
        elapsed: elapsed,
      ),
    );
  }

  String _friendlyError(Object e) {
    final text = e.toString().replaceFirst('Exception: ', '').trim();
    if (text.contains('401')) return 'Unauthorized. Please login again.';
    if (text.contains('403')) {
      return 'You do not have permission to run catalog updates.';
    }
    return text.isEmpty ? 'Request failed.' : text;
  }
}

final catalogUpdateProvider =
    StateNotifierProvider<CatalogUpdateController, CatalogUpdateState>(
  (ref) => CatalogUpdateController(),
);
