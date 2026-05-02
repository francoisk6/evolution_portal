class NotificationAction {
  final String key;
  final String label;
  final String method;
  final String url;
  final String style;
  final String confirm;

  const NotificationAction({
    required this.key,
    required this.label,
    required this.method,
    required this.url,
    required this.style,
    required this.confirm,
  });

  factory NotificationAction.fromJson(Map<String, dynamic> json) {
    final maps = _candidateMaps(json);
    return NotificationAction(
      key: _pickString(
        json,
        const ['key', 'name', 'code', 'action'],
        maps: maps,
      ),
      label: _pickString(
        json,
        const ['label', 'title', 'text', 'name'],
        maps: maps,
        fallback: 'Action',
      ),
      method: _pickString(
        json,
        const ['method', 'http_method'],
        maps: maps,
        fallback: 'POST',
      ).toUpperCase(),
      url: _pickString(
        json,
        const ['url', 'href', 'link', 'action_url'],
        maps: maps,
      ),
      style: _pickString(
        json,
        const ['style', 'variant', 'color'],
        maps: maps,
      ),
      confirm: _pickString(
        json,
        const ['confirm', 'confirm_text', 'confirmation'],
        maps: maps,
      ),
    );
  }
}

class NotificationItem {
  final int id;
  final String verb;
  final String level;
  final String description;
  final String url;
  final bool isRead;
  final DateTime? createdAt;
  final String targetType;
  final String targetId;
  final List<NotificationAction> actions;

  const NotificationItem({
    required this.id,
    required this.verb,
    required this.level,
    required this.description,
    required this.url,
    required this.isRead,
    required this.createdAt,
    required this.targetType,
    required this.targetId,
    required this.actions,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    final maps = _candidateMaps(json);

    final idValue = _pickDynamic(
      json,
      const ['id', 'pk', 'notification_id'],
      maps: maps,
    );

    final verb = _pickString(
      json,
      const [
        'verb',
        'title',
        'subject',
        'name',
        'heading',
        'label',
        'notification_title',
      ],
      maps: maps,
    );

    final description = _pickString(
      json,
      const [
        'description',
        'message',
        'body',
        'content',
        'text',
        'details',
        'note',
        'notification_message',
        'desc',
      ],
      maps: maps,
    );

    final level = _pickString(
      json,
      const ['level', 'type', 'status', 'severity'],
      maps: maps,
      fallback: 'info',
    );

    final url = _pickString(
      json,
      const ['url', 'link', 'href', 'target_url', 'action_url'],
      maps: maps,
    );

    final isRead = _asBool(
      _pickDynamic(
        json,
        const ['is_read', 'read', 'is_seen', 'seen'],
        maps: maps,
      ),
    );

    final createdAt = _parseDateTime(
      _pickDynamic(
        json,
        const [
          'created_at',
          'createdAt',
          'timestamp',
          'created',
          'date',
          'datetime',
          'sent_at',
        ],
        maps: maps,
      ),
    );

    return NotificationItem(
      id: idValue is int ? idValue : int.tryParse('${idValue ?? 0}') ?? 0,
      verb: verb,
      level: level,
      description: description,
      url: url,
      isRead: isRead,
      createdAt: createdAt,
      targetType: _pickString(
        json,
        const ['target_type', 'targetType'],
        maps: maps,
      ),
      targetId: _pickString(
        json,
        const ['target_id', 'targetId'],
        maps: maps,
      ),
      actions: _parseActions(_pickList(json, const ['actions']) ?? const <dynamic>[]),
    );
  }

  NotificationItem copyWith({
    int? id,
    String? verb,
    String? level,
    String? description,
    String? url,
    bool? isRead,
    DateTime? createdAt,
    String? targetType,
    String? targetId,
    List<NotificationAction>? actions,
  }) {
    return NotificationItem(
      id: id ?? this.id,
      verb: verb ?? this.verb,
      level: level ?? this.level,
      description: description ?? this.description,
      url: url ?? this.url,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      targetType: targetType ?? this.targetType,
      targetId: targetId ?? this.targetId,
      actions: actions ?? this.actions,
    );
  }
}

class NotificationListResponse {
  final List<NotificationItem> results;
  final int count;
  final int limit;
  final int offset;

  const NotificationListResponse({
    required this.results,
    required this.count,
    required this.limit,
    required this.offset,
  });

  factory NotificationListResponse.fromJson(Map<String, dynamic> json) {
    final dataMap = _asMap(json['data']);
    final rawResults = _pickList(json, const ['results', 'items', 'notifications']) ??
        _pickList(dataMap, const ['results', 'items', 'notifications']) ??
        const <dynamic>[];

    final items = rawResults
        .map((e) => _asMap(e))
        .whereType<Map<String, dynamic>>()
        .map(NotificationItem.fromJson)
        .toList();

    return NotificationListResponse(
      results: items,
      count: _asInt(
        json['count'] ?? dataMap?['count'] ?? items.length,
        fallback: items.length,
      ),
      limit: _asInt(json['limit'] ?? dataMap?['limit'] ?? 20, fallback: 20),
      offset: _asInt(json['offset'] ?? dataMap?['offset'] ?? 0, fallback: 0),
    );
  }
}

class NotificationPollItem {
  final int id;
  final String verb;
  final String description;
  final String url;
  final String level;
  final String timestamp;
  final String targetType;
  final String targetId;
  final List<NotificationAction> actions;

  const NotificationPollItem({
    required this.id,
    required this.verb,
    required this.description,
    required this.url,
    required this.level,
    required this.timestamp,
    required this.targetType,
    required this.targetId,
    required this.actions,
  });

  factory NotificationPollItem.fromJson(Map<String, dynamic> json) {
    final maps = _candidateMaps(json);
    final idValue = _pickDynamic(
      json,
      const ['id', 'pk', 'notification_id'],
      maps: maps,
    );

    return NotificationPollItem(
      id: idValue is int ? idValue : int.tryParse('${idValue ?? 0}') ?? 0,
      verb: _pickString(
        json,
        const ['verb', 'title', 'subject', 'name', 'heading'],
        maps: maps,
      ),
      description: _pickString(
        json,
        const ['description', 'message', 'body', 'content', 'text', 'details'],
        maps: maps,
      ),
      url: _pickString(
        json,
        const ['url', 'link', 'href', 'target_url', 'action_url'],
        maps: maps,
      ),
      level: _pickString(
        json,
        const ['level', 'type', 'status', 'severity'],
        maps: maps,
        fallback: 'info',
      ),
      timestamp: _pickString(
        json,
        const ['timestamp', 'created_at', 'created', 'date', 'datetime'],
        maps: maps,
      ),
      targetType: _pickString(
        json,
        const ['target_type', 'targetType'],
        maps: maps,
      ),
      targetId: _pickString(
        json,
        const ['target_id', 'targetId'],
        maps: maps,
      ),
      actions: _parseActions(_pickList(json, const ['actions']) ?? const <dynamic>[]),
    );
  }
}

class NotificationPollResponse {
  final int count;
  final List<NotificationPollItem> items;

  const NotificationPollResponse({
    required this.count,
    required this.items,
  });

  factory NotificationPollResponse.fromJson(Map<String, dynamic> json) {
    final dataMap = _asMap(json['data']);
    final rawItems = _pickList(json, const ['items', 'results', 'notifications']) ??
        _pickList(dataMap, const ['items', 'results', 'notifications']) ??
        const <dynamic>[];

    final items = rawItems
        .map((e) => _asMap(e))
        .whereType<Map<String, dynamic>>()
        .map(NotificationPollItem.fromJson)
        .toList();

    return NotificationPollResponse(
      count: _asInt(
        json['count'] ?? dataMap?['count'] ?? items.length,
        fallback: items.length,
      ),
      items: items,
    );
  }
}

bool _asBool(dynamic value) {
  if (value is bool) return value;
  final s = value?.toString().trim().toLowerCase() ?? '';
  return s == 'true' || s == '1' || s == 'yes' || s == 'y';
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  return int.tryParse('${value ?? fallback}') ?? fallback;
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  final s = value.toString().trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    try {
      return value.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }
  return null;
}

List<dynamic>? _pickList(Map<String, dynamic>? json, List<String> keys) {
  if (json == null) return null;
  for (final key in keys) {
    final value = json[key];
    if (value is List) return value;
  }
  return null;
}

List<Map<String, dynamic>> _candidateMaps(Map<String, dynamic> json) {
  final maps = <Map<String, dynamic>>[];
  for (final value in json.values) {
    final map = _asMap(value);
    if (map != null) maps.add(map);
  }
  return maps;
}

List<NotificationAction> _parseActions(List<dynamic> raw) {
  return raw
      .map(_asMap)
      .whereType<Map<String, dynamic>>()
      .map(NotificationAction.fromJson)
      .where((action) => action.url.trim().isNotEmpty)
      .toList();
}

dynamic _pickDynamic(
  Map<String, dynamic> json,
  List<String> keys, {
  List<Map<String, dynamic>> maps = const <Map<String, dynamic>>[],
}) {
  for (final key in keys) {
    if (json.containsKey(key) && json[key] != null) {
      return json[key];
    }
  }
  for (final map in maps) {
    for (final key in keys) {
      if (map.containsKey(key) && map[key] != null) {
        return map[key];
      }
    }
  }
  return null;
}

String _pickString(
  Map<String, dynamic> json,
  List<String> keys, {
  List<Map<String, dynamic>> maps = const <Map<String, dynamic>>[],
  String fallback = '',
}) {
  final value = _pickDynamic(json, keys, maps: maps);
  final s = value?.toString().trim() ?? '';
  return s.isEmpty ? fallback : s;
}
