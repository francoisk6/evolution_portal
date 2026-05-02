import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_service.dart';

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
  bool _loadedWhileAuthenticated = false;

  ProductsWithoutGroupsNotifier() : super(const AsyncValue.loading()) {
    // Auto-load as soon as the provider is first read.
    refresh(force: true);
  }

  Future<void> refresh({bool force = true}) async {
    if (!force && _loadedWhileAuthenticated && state is AsyncData) return;

    state = const AsyncValue.loading();

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
      state = AsyncValue.error(e, st);
    }
  }
}

final productsWithoutGroupsProvider = StateNotifierProvider<
    ProductsWithoutGroupsNotifier, AsyncValue<List<ProductWithoutGroup>>>(
  (ref) => ProductsWithoutGroupsNotifier(),
);
