import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_service.dart';
import 'session_provider.dart';

class ProductWithoutGroup {
  /// Backend returns an arbitrary string identifier (often lowercased).
  final String id;

  /// Display label requested by user.
  final String alt;

  /// Kept for search/filtering (not displayed on cards).
  final String name;
  final String sectorName;

  ProductWithoutGroup({
    required this.id,
    required this.alt,
    required this.name,
    required this.sectorName,
  });

  factory ProductWithoutGroup.fromMap(Map<String, dynamic> m) {
    return ProductWithoutGroup(
      id: (m['id'] ?? '').toString(),
      alt: (m['alt'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      sectorName: (m['sector_name'] ?? '').toString(),
    );
  }
}

class ProductsWithoutGroupsNotifier
    extends StateNotifier<AsyncValue<List<ProductWithoutGroup>>> {
  final Ref _ref;
  bool _loadedWhileAuthenticated = false;

  ProductsWithoutGroupsNotifier(this._ref) : super(const AsyncValue.loading()) {
    var prevLoggedIn = _ref.read(sessionProvider).loggedIn;
    _ref.listen<SessionState>(sessionProvider, (_, next) {
      final wasLoggedIn = prevLoggedIn;
      prevLoggedIn = next.loggedIn;
      if (wasLoggedIn && !next.loggedIn) {
        _loadedWhileAuthenticated = false;
        state = const AsyncValue.data(<ProductWithoutGroup>[]);
      }
    });
    refresh(force: true);
  }

  Future<void> refresh({bool force = true}) async {
    if (!force && _loadedWhileAuthenticated && state is AsyncData) return;

    // Keep existing data visible during refresh to avoid skeleton flash.
    final hadData = state is AsyncData;
    if (!hadData) state = const AsyncValue.loading();

    final authed = await ApiService.instance.isAuthenticated();
    if (!authed) {
      _loadedWhileAuthenticated = false;
      state = const AsyncValue.data(<ProductWithoutGroup>[]);
      return;
    }

    try {
      final raw = await ApiService.instance.getProductsWithoutGroups();
      final list = raw
          .whereType<Map<String, dynamic>>()
          .map(ProductWithoutGroup.fromMap)
          .toList(growable: false);
      _loadedWhileAuthenticated = true;
      state = AsyncValue.data(list);
    } catch (e, st) {
      _loadedWhileAuthenticated = false;
      if (!hadData) state = AsyncValue.error(e, st);
    }
  }
}

final productsWithoutGroupsProvider = StateNotifierProvider<
    ProductsWithoutGroupsNotifier, AsyncValue<List<ProductWithoutGroup>>>(
  (ref) => ProductsWithoutGroupsNotifier(ref),
);
