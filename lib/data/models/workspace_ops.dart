class WorkspaceStatusResponse {
  final bool ok;
  final Map<String, dynamic> workspace;
  final Map<String, dynamic> mapping;
  final Map<String, dynamic> reservedUsers;
  final Map<String, dynamic> counts;
  final Map<String, dynamic> recent;

  const WorkspaceStatusResponse({
    required this.ok,
    required this.workspace,
    required this.mapping,
    required this.reservedUsers,
    required this.counts,
    required this.recent,
  });

  factory WorkspaceStatusResponse.fromJson(Map<String, dynamic> json) {
    return WorkspaceStatusResponse(
      ok: _asBool(json['ok']),
      workspace: _map(json['workspace']),
      mapping: _map(json['mapping']),
      reservedUsers: _map(json['reserved_users'] ?? json['reservedUsers']),
      counts: _map(json['counts']),
      recent: _map(json['recent']),
    );
  }
}

class WorkspaceAuditSummaryResponse {
  final bool ok;
  final Map<String, dynamic> workspace;
  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> missingWorkspaceMeta;
  final List<Map<String, dynamic>> missingMainTransactionId;
  final List<Map<String, dynamic>> remoteMissing;
  final List<Map<String, dynamic>> remoteLookupErrors;
  final List<Map<String, dynamic>> statusMismatch;
  final List<Map<String, dynamic>> okSynced;

  const WorkspaceAuditSummaryResponse({
    required this.ok,
    required this.workspace,
    required this.summary,
    required this.missingWorkspaceMeta,
    required this.missingMainTransactionId,
    required this.remoteMissing,
    required this.remoteLookupErrors,
    required this.statusMismatch,
    required this.okSynced,
  });

  factory WorkspaceAuditSummaryResponse.fromJson(Map<String, dynamic> json) {
    final samples = _map(json['samples']);
    List<Map<String, dynamic>> sampleList(String key) {
      final direct = json[key];
      final nested = samples[key];
      return _listOfMaps(direct ?? nested);
    }

    return WorkspaceAuditSummaryResponse(
      ok: _asBool(json['ok']),
      workspace: _map(json['workspace']),
      summary: _map(json['summary'] ?? json['counters'] ?? json['counts']),
      missingWorkspaceMeta: sampleList('missing_workspace_meta'),
      missingMainTransactionId: sampleList('missing_main_transaction_id'),
      remoteMissing: sampleList('remote_missing'),
      remoteLookupErrors: sampleList('remote_lookup_errors'),
      statusMismatch: sampleList('status_mismatch'),
      okSynced: sampleList('ok_synced'),
    );
  }
}

class WorkspaceListResponse {
  final bool ok;
  final int count;
  final List<WorkspaceOption> workspaces;

  const WorkspaceListResponse({
    required this.ok,
    required this.count,
    required this.workspaces,
  });

  factory WorkspaceListResponse.fromJson(Map<String, dynamic> json) {
    final workspaces = _listOfMaps(json['workspaces'])
        .map(WorkspaceOption.fromJson)
        .toList(growable: false);
    return WorkspaceListResponse(
      ok: _asBool(json['ok']),
      count: _asInt(json['count']) ?? workspaces.length,
      workspaces: workspaces,
    );
  }
}

class WorkspaceOption {
  final String slug;
  final String name;
  final String? domain;
  final bool active;
  final int? mainDealerUserId;
  final String? mainDealerUsername;

  const WorkspaceOption({
    required this.slug,
    required this.name,
    this.domain,
    required this.active,
    this.mainDealerUserId,
    this.mainDealerUsername,
  });

  factory WorkspaceOption.fromJson(Map<String, dynamic> json) {
    final slug = json['slug']?.toString() ?? '';
    return WorkspaceOption(
      slug: slug,
      name: json['name']?.toString() ?? slug,
      domain: json['domain']?.toString(),
      active: _asBool(json['active']),
      mainDealerUserId: _asInt(json['main_dealer_user_id']),
      mainDealerUsername: json['main_dealer_username']?.toString(),
    );
  }
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _listOfMaps(dynamic value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return value
      .map((item) => _map(item))
      .where((item) => item.isNotEmpty)
      .toList();
}

bool _asBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final s = value?.toString().trim().toLowerCase() ?? '';
  return s == 'true' || s == '1' || s == 'yes' || s == 'y';
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}
