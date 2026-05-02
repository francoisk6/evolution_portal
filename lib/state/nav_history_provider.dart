import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Minimal navigation history to support a "Back" affordance even when
/// pages are navigated via `context.go()` (no back stack).
///
/// We store normalized locations (query param `ts` removed) so manual refresh
/// does not pollute history.
class NavHistoryState {
  final String current;
  final String? previous;

  const NavHistoryState({required this.current, required this.previous});

  NavHistoryState copyWith({String? current, String? previous}) =>
      NavHistoryState(
        current: current ?? this.current,
        previous: previous,
      );
}

class NavHistoryNotifier extends StateNotifier<NavHistoryState> {
  NavHistoryNotifier() : super(const NavHistoryState(current: '/home', previous: null));

  static String normalize(String location) {
    final uri = Uri.tryParse(location);
    if (uri == null) return location;

    // Remove manual refresh marker
    final qp = Map<String, String>.from(uri.queryParameters);
    qp.remove('ts');

    return uri.replace(queryParameters: qp.isEmpty ? null : qp).toString();
  }

  void setInitial(String location) {
    final norm = normalize(location);
    state = NavHistoryState(current: norm, previous: null);
  }

  void pushLocation(String location) {
    final norm = normalize(location);
    if (norm == state.current) return;
    state = NavHistoryState(current: norm, previous: state.current);
  }
}

final navHistoryProvider =
    StateNotifierProvider<NavHistoryNotifier, NavHistoryState>(
  (ref) => NavHistoryNotifier(),
);
