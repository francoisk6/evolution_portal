class WorkspaceTransactionCleanupResponse {
  final bool ok;
  final String result;
  final String? message;
  final int? localTransactionId;
  final String? orderUuid;
  final int? mainTransactionId;
  final String? mainStatus;
  final String? status;
  final int count;
  final List<WorkspaceCleanupCandidate> transactions;
  final Map<String, dynamic> raw;

  const WorkspaceTransactionCleanupResponse({
    required this.ok,
    required this.result,
    required this.raw,
    this.count = 0,
    this.transactions = const [],
    this.message,
    this.localTransactionId,
    this.orderUuid,
    this.mainTransactionId,
    this.mainStatus,
    this.status,
  });

  bool get canConfirmDelete =>
      ok && result == 'would_delete_orphan_child_transaction';
  bool get isCandidateList => ok && result == 'cleanup_candidates';

  bool get isSuccess =>
      ok &&
      (result == 'deleted_orphan_child_transaction' || result == 'reconciled');

  factory WorkspaceTransactionCleanupResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    final payload = json['data'] is Map
        ? (json['data'] as Map).cast<String, dynamic>()
        : json;

    return WorkspaceTransactionCleanupResponse(
      ok: _asBool(payload['ok'] ?? json['ok']),
      result: (payload['result'] ?? json['result'] ?? '').toString(),
      message: (payload['message'] ??
              json['message'] ??
              payload['error'] ??
              json['error'])
          ?.toString(),
      localTransactionId: _asInt(
        payload['local_transaction_id'] ?? json['local_transaction_id'],
      ),
      orderUuid: (payload['order_uuid'] ?? json['order_uuid'])?.toString(),
      mainTransactionId: _asInt(
        payload['main_transaction_id'] ?? json['main_transaction_id'],
      ),
      mainStatus: (payload['main_status'] ?? json['main_status'])?.toString(),
      status: (payload['status'] ?? json['status'])?.toString(),
      count: _asInt(payload['count'] ?? json['count']) ?? 0,
      transactions: _listOfMaps(payload['transactions'] ?? json['transactions'])
          .map(WorkspaceCleanupCandidate.fromJson)
          .toList(growable: false),
      raw: payload,
    );
  }

  static bool _asBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v?.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes' || s == 'ok';
  }

  static int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  static List<Map<String, dynamic>> _listOfMaps(dynamic v) {
    if (v is! List) return const <Map<String, dynamic>>[];
    return v
        .map((item) => item is Map<String, dynamic>
            ? item
            : (item is Map
                ? item.cast<String, dynamic>()
                : const <String, dynamic>{}))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}

class WorkspaceCleanupCandidate {
  final int? localTransactionId;
  final String? status;
  final String? clientNumber;
  final String? orderUuid;
  final int? mainTransactionId;
  final String? note;
  final String? created;
  final String? modified;
  final Map<String, dynamic> raw;

  const WorkspaceCleanupCandidate({
    required this.raw,
    this.localTransactionId,
    this.status,
    this.clientNumber,
    this.orderUuid,
    this.mainTransactionId,
    this.note,
    this.created,
    this.modified,
  });

  factory WorkspaceCleanupCandidate.fromJson(Map<String, dynamic> json) {
    return WorkspaceCleanupCandidate(
      raw: json,
      localTransactionId: WorkspaceTransactionCleanupResponse._asInt(
          json['local_transaction_id']),
      status: json['status']?.toString(),
      clientNumber: json['clientnumber']?.toString(),
      orderUuid: json['order_uuid']?.toString(),
      mainTransactionId: WorkspaceTransactionCleanupResponse._asInt(
          json['main_transaction_id']),
      note: json['note']?.toString(),
      created: json['created']?.toString(),
      modified: json['modified']?.toString(),
    );
  }
}
