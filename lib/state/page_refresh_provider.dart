import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Incremented when the user taps the global Refresh button.
/// Pages that need to reload their data should listen to this value.
final pageRefreshPulseProvider = StateProvider<int>((ref) => 0);
