import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';

class HomeDetail {
  final int id;
  final String name;
  final String avatar;
  final String search;

  HomeDetail({
    required this.id,
    required this.name,
    required this.avatar,
    required this.search,
  });

  factory HomeDetail.fromMap(Map<String, dynamic> m) => HomeDetail(
        id: (m['id'] ?? 0) as int,
        name: (m['name'] ?? '') as String,
        avatar: (m['avatar'] ?? '') as String,
        search: (m['search'] ?? '') as String,
      );
}

class HomeSection {
  final int id;
  final String name;
  final List<HomeDetail> details;

  HomeSection({
    required this.id,
    required this.name,
    required this.details,
  });

  factory HomeSection.fromMap(Map<String, dynamic> m) => HomeSection(
        id: (m['id'] ?? 0) as int,
        name: (m['name'] ?? '') as String,
        details: (m['details'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(HomeDetail.fromMap)
            .toList(growable: false),
      );
}

class GroupsNotifier extends StateNotifier<AsyncValue<List<HomeSection>>> {
  bool _loadedWhileAuthenticated = false;

  GroupsNotifier() : super(const AsyncValue.loading()) {
    // Auto-load as soon as the provider is first read.
    refresh(force: true);
  }

  Future<void> refresh({bool force = true}) async {
    if (!force && _loadedWhileAuthenticated && state is AsyncData) return;

    state = const AsyncValue.loading();
    final authed = await ApiService.instance.isAuthenticated();
    if (!authed) {
      _loadedWhileAuthenticated = false;
      state = const AsyncValue.data(<HomeSection>[]);
      return;
    }

    try {
      final raw = await ApiService.instance.getGroupsWithProducts();
      final list = raw
          .whereType<Map<String, dynamic>>()
          .map(HomeSection.fromMap)
          .toList(growable: false);
      _loadedWhileAuthenticated = true;
      state = AsyncValue.data(list);
    } catch (e, st) {
      _loadedWhileAuthenticated = false;
      state = AsyncValue.error(e, st);
    }
  }
}

final groupsProvider =
    StateNotifierProvider<GroupsNotifier, AsyncValue<List<HomeSection>>>(
  (ref) => GroupsNotifier(),
);
