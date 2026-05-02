import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/notification_models.dart';
import '../services/notification_service.dart';

class NotificationCenterState {
  final int unreadCount;
  final List<NotificationItem> items;
  final bool loadingCount;
  final bool loadingList;
  final bool loadingMore;
  final bool hasLoadedList;
  final bool hasMore;
  final int totalCount;
  final int limit;
  final int offset;
  final Map<String, bool> actionLoading;
  final String? error;

  const NotificationCenterState({
    this.unreadCount = 0,
    this.items = const <NotificationItem>[],
    this.loadingCount = false,
    this.loadingList = false,
    this.loadingMore = false,
    this.hasLoadedList = false,
    this.hasMore = true,
    this.totalCount = 0,
    this.limit = 20,
    this.offset = 0,
    this.actionLoading = const <String, bool>{},
    this.error,
  });

  NotificationCenterState copyWith({
    int? unreadCount,
    List<NotificationItem>? items,
    bool? loadingCount,
    bool? loadingList,
    bool? loadingMore,
    bool? hasLoadedList,
    bool? hasMore,
    int? totalCount,
    int? limit,
    int? offset,
    Map<String, bool>? actionLoading,
    String? error,
    bool clearError = false,
  }) {
    return NotificationCenterState(
      unreadCount: unreadCount ?? this.unreadCount,
      items: items ?? this.items,
      loadingCount: loadingCount ?? this.loadingCount,
      loadingList: loadingList ?? this.loadingList,
      loadingMore: loadingMore ?? this.loadingMore,
      hasLoadedList: hasLoadedList ?? this.hasLoadedList,
      hasMore: hasMore ?? this.hasMore,
      totalCount: totalCount ?? this.totalCount,
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
      actionLoading: actionLoading ?? this.actionLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class NotificationCenterNotifier extends StateNotifier<NotificationCenterState> {
  NotificationCenterNotifier() : super(const NotificationCenterState());

  Future<void> refreshUnreadCount() async {
    if (state.loadingCount) return;
    state = state.copyWith(loadingCount: true, clearError: true);
    try {
      final unread = await NotificationService.instance.getUnreadCount();
      state = state.copyWith(unreadCount: unread, loadingCount: false);
    } catch (e) {
      state = state.copyWith(
        loadingCount: false,
        error: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> loadFirstPage({
    int limit = 20,
    bool unreadOnly = false,
    DateTime? since,
  }) async {
    if (state.loadingList) return;
    state = state.copyWith(
      loadingList: true,
      loadingMore: false,
      clearError: true,
      limit: limit,
      offset: 0,
    );

    try {
      final response = await NotificationService.instance.getNotifications(
        limit: limit,
        offset: 0,
        unreadOnly: unreadOnly,
        since: since,
      );
      final hasMore = response.results.length + response.offset < response.count;
      state = state.copyWith(
        items: response.results,
        totalCount: response.count,
        limit: response.limit,
        offset: response.offset + response.results.length,
        hasLoadedList: true,
        hasMore: hasMore,
        loadingList: false,
      );
    } catch (e) {
      state = state.copyWith(
        loadingList: false,
        hasLoadedList: true,
        error: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> loadMore() async {
    if (state.loadingList || state.loadingMore || !state.hasMore) return;
    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      final response = await NotificationService.instance.getNotifications(
        limit: state.limit,
        offset: state.offset,
      );
      final merged = <NotificationItem>[...state.items, ...response.results];
      final hasMore = response.offset + response.results.length < response.count;
      state = state.copyWith(
        items: merged,
        totalCount: response.count,
        offset: response.offset + response.results.length,
        hasMore: hasMore,
        loadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(
        loadingMore: false,
        error: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> refreshAll({bool resetList = false}) async {
    await refreshUnreadCount();
    if (resetList || state.hasLoadedList) {
      await loadFirstPage(limit: state.limit);
    }
  }

  Future<void> pollLatestUnread() async {
    try {
      final response = await NotificationService.instance.poll();
      state = state.copyWith(unreadCount: response.count);
    } catch (_) {
      // Silent by design during background polling.
    }
  }

  Future<void> markSelectedRead(List<int> ids) async {
    if (ids.isEmpty) return;
    await NotificationService.instance.markRead(ids);
    _markLocalRead(ids);
    await refreshUnreadCount();
  }

  Future<void> markAllRead() async {
    final unreadCount = await NotificationService.instance.markAllRead();
    state = state.copyWith(
      unreadCount: unreadCount,
      items: state.items
          .map((item) => item.isRead ? item : item.copyWith(isRead: true))
          .toList(),
    );
  }

  Future<void> markOneRead(int id) async {
    final unreadCount = await NotificationService.instance.markOneRead(id);
    state = state.copyWith(
      unreadCount: unreadCount,
      items: state.items
          .map((item) => item.id == id ? item.copyWith(isRead: true) : item)
          .toList(),
    );
  }

  Future<void> deleteOne(int id) async {
    final unreadCount = await NotificationService.instance.deleteOne(id);
    final newItems = state.items.where((item) => item.id != id).toList();
    final newTotal = state.totalCount > 0 ? state.totalCount - 1 : 0;
    state = state.copyWith(
      unreadCount: unreadCount,
      items: newItems,
      totalCount: newTotal,
      hasMore: newItems.length < newTotal,
    );
  }

  bool isActionLoading(int notificationId, String actionKey) {
    return state.actionLoading[_actionToken(notificationId, actionKey)] ?? false;
  }

  Future<String> runAction(NotificationItem item, NotificationAction action) async {
    final token = _actionToken(item.id, action.key);
    if (state.actionLoading[token] == true) {
      return '';
    }

    final loading = Map<String, bool>.from(state.actionLoading);
    loading[token] = true;
    state = state.copyWith(actionLoading: loading, clearError: true);

    try {
      final result = await NotificationService.instance.runAction(item, action);
      final updatedLoading = Map<String, bool>.from(state.actionLoading)
        ..remove(token);
      final newItems = state.items.where((n) => n.id != item.id).toList();
      final newTotal = state.totalCount > 0 ? state.totalCount - 1 : 0;

      state = state.copyWith(
        actionLoading: updatedLoading,
        unreadCount: result.unreadCount,
        items: newItems,
        totalCount: newTotal,
        hasMore: newItems.length < newTotal,
      );
      return result.message;
    } catch (e) {
      final updatedLoading = Map<String, bool>.from(state.actionLoading)
        ..remove(token);
      state = state.copyWith(
        actionLoading: updatedLoading,
        error: e.toString().replaceFirst('Exception: ', ''),
      );
      rethrow;
    }
  }

  void _markLocalRead(List<int> ids) {
    final idSet = ids.toSet();
    state = state.copyWith(
      items: state.items
          .map((item) => idSet.contains(item.id)
              ? item.copyWith(isRead: true)
              : item)
          .toList(),
    );
  }

  String _actionToken(int notificationId, String actionKey) {
    return '$notificationId:$actionKey';
  }
}

final notificationCenterProvider = StateNotifierProvider<
    NotificationCenterNotifier, NotificationCenterState>(
  (ref) => NotificationCenterNotifier(),
);
