import '../data/models/notification_models.dart';
import 'api_service.dart';

class NotificationActionResult {
  final bool ok;
  final int unreadCount;
  final int notificationId;
  final String message;

  const NotificationActionResult({
    required this.ok,
    required this.unreadCount,
    required this.notificationId,
    required this.message,
  });
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  Future<NotificationListResponse> getNotifications({
    int limit = 20,
    int offset = 0,
    bool unreadOnly = false,
    DateTime? since,
  }) async {
    final map = await ApiService.instance.getNotifications(
      limit: limit,
      offset: offset,
      unreadOnly: unreadOnly,
      since: since,
    );
    return NotificationListResponse.fromJson(map);
  }

  Future<int> getUnreadCount() async {
    final map = await ApiService.instance.getNotificationUnreadCount();
    return _asInt(map['unread']);
  }

  Future<NotificationPollResponse> poll() async {
    final map = await ApiService.instance.pollNotifications();
    return NotificationPollResponse.fromJson(map);
  }

  Future<int> markRead(List<int> ids) async {
    final map = await ApiService.instance.markNotificationsRead(ids);
    if (map.containsKey('unread_count')) {
      return _asInt(map['unread_count']);
    }
    return ids.length;
  }

  Future<int> markAllRead() async {
    final map = await ApiService.instance.markAllNotificationsRead();
    if (map.containsKey('unread_count')) {
      return _asInt(map['unread_count']);
    }
    return 0;
  }

  Future<int> markOneRead(int id) async {
    final map = await ApiService.instance.markSingleNotificationRead(id);
    return _asInt(map['unread_count']);
  }

  Future<int> deleteOne(int id) async {
    final map = await ApiService.instance.deleteNotification(id);
    return _asInt(map['unread_count']);
  }

  Future<NotificationActionResult> runAction(
    NotificationItem item,
    NotificationAction action,
  ) async {
    final map = await ApiService.instance.runNotificationAction(
      action.url,
      method: action.method,
    );
    return NotificationActionResult(
      ok: _asBool(map['ok'], fallback: true),
      unreadCount: _asInt(map['unread_count']),
      notificationId: _asInt(map['id'], fallback: item.id),
      message: (map['message']?.toString().trim() ?? ''),
    );
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    return int.tryParse('${value ?? fallback}') ?? fallback;
  }

  bool _asBool(dynamic value, {bool fallback = false}) {
    if (value is bool) return value;
    final s = value?.toString().trim().toLowerCase() ?? '';
    if (s.isEmpty) return fallback;
    return s == 'true' || s == '1' || s == 'yes' || s == 'y';
  }
}
