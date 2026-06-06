import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../app/app_env.dart';
import '../data/models/batch_refill_models.dart';
import 'api_envelope.dart';

class BatchSheetLockedException implements Exception {
  const BatchSheetLockedException();
  @override
  String toString() => 'A refill is already in progress. Please wait.';
}

class BatchRefillService {
  BatchRefillService._();
  static final BatchRefillService instance = BatchRefillService._();

  String get _base => '${AppEnv.base}batch/';

  Future<Map<String, String>> _headers({bool json = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ?? '';
    return {
      'Accept': 'application/json',
      if (json) 'Content-Type': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Token $token',
    };
  }

  static String _bodyText(http.Response res) {
    if (res.bodyBytes.isEmpty) return res.body;
    try {
      return utf8.decode(res.bodyBytes);
    } catch (_) {
      return res.body;
    }
  }

  static Map<String, dynamic> _parseBody(http.Response res) {
    final text = _bodyText(res);
    if (text.trim().isEmpty) return {};
    try {
      final d = jsonDecode(text);
      if (d is Map<String, dynamic>) return d;
      return {'data': d};
    } catch (_) {
      return {};
    }
  }

  static void _assertOk(http.Response res, Map<String, dynamic> body) {
    if (res.statusCode == 423) throw const BatchSheetLockedException();
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    final env = ApiEnvelope(status: res.statusCode, body: body);
    throw Exception(
        env.humanError ?? 'Request failed (HTTP ${res.statusCode}).');
  }

  static List<T> _dataList<T>(
    Map<String, dynamic> body,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final data = body['data'];
    if (data is List) {
      return data
          .map((e) => fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  static T _dataItem<T>(
    Map<String, dynamic> body,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final data = body['data'];
    if (data is Map<String, dynamic>) return fromJson(data);
    return fromJson(body);
  }

  Future<Map<String, dynamic>> _get(String url) async {
    final h = await _headers(json: false);
    final res = await http.get(Uri.parse(url), headers: h);
    final body = _parseBody(res);
    _assertOk(res, body);
    return body;
  }

  Future<Map<String, dynamic>> _post(
    String url, [
    Map<String, dynamic>? data,
  ]) async {
    final h = await _headers();
    final res = await http.post(
      Uri.parse(url),
      headers: h,
      body: data != null ? jsonEncode(data) : null,
    );
    final body = _parseBody(res);
    _assertOk(res, body);
    return body;
  }

  Future<Map<String, dynamic>> _patch(
    String url,
    Map<String, dynamic> data,
  ) async {
    final h = await _headers();
    final res = await http.patch(
      Uri.parse(url),
      headers: h,
      body: jsonEncode(data),
    );
    final body = _parseBody(res);
    _assertOk(res, body);
    return body;
  }

  Future<void> _delete(String url, [Map<String, dynamic>? data]) async {
    final h = await _headers(json: data != null);
    final res = await http.delete(
      Uri.parse(url),
      headers: h,
      body: data != null ? jsonEncode(data) : null,
    );
    final body = _parseBody(res);
    _assertOk(res, body);
  }

  // ─── BRANDS ───────────────────────────────────────────────────────────────

  Future<List<BatchBrand>> getBrands() async {
    final body = await _get('${_base}brands/');
    return _dataList(body, BatchBrand.fromJson);
  }

  // ─── BALANCE ──────────────────────────────────────────────────────────────

  Future<List<BatchBalance>> getBalances() async {
    final body = await _get('${_base}balance/');
    return _dataList(body, BatchBalance.fromJson);
  }

  // ─── SHEETS ───────────────────────────────────────────────────────────────

  Future<List<BatchSheet>> getSheets() async {
    final body = await _get('${_base}sheets/');
    return _dataList(body, BatchSheet.fromJson);
  }

  Future<BatchSheet> createSheet(String name) async {
    final body = await _post('${_base}sheets/', {'name': name});
    return _dataItem(body, BatchSheet.fromJson);
  }

  Future<({BatchSheet sheet, List<BatchRecord> records})> importSheet({
    required List<int> csvBytes,
    required String filename,
    String? name,
  }) async {
    final h = await _headers(json: false);
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('${_base}sheets/import/'),
    );
    req.headers.addAll(h);
    req.files.add(
      http.MultipartFile.fromBytes(
        'csv_file',
        csvBytes,
        filename: filename,
      ),
    );
    if (name != null && name.isNotEmpty) req.fields['name'] = name;

    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    final body = _parseBody(res);
    _assertOk(res, body);

    final data = body['data'] as Map<String, dynamic>? ?? {};
    final sheet =
        BatchSheet.fromJson(data['sheet'] as Map<String, dynamic>? ?? {});
    final records = (data['records'] as List? ?? [])
        .map((e) => BatchRecord.fromJson(e as Map<String, dynamic>))
        .toList();
    return (sheet: sheet, records: records);
  }

  Future<void> deleteSheet(int id) async {
    await _delete('${_base}sheets/$id/');
  }

  // ─── RECORDS ──────────────────────────────────────────────────────────────

  Future<List<BatchRecord>> getRecords(int sheetId) async {
    final body = await _get('${_base}sheets/$sheetId/records/');
    return _dataList(body, BatchRecord.fromJson);
  }

  Future<BatchRecord> createRecord(
    int sheetId,
    Map<String, dynamic> data,
  ) async {
    final body = await _post('${_base}sheets/$sheetId/records/', data);
    return _dataItem(body, BatchRecord.fromJson);
  }

  Future<BatchRecord> updateRecord(
    int recordId,
    Map<String, dynamic> data,
  ) async {
    final body = await _patch('${_base}records/$recordId/', data);
    return _dataItem(body, BatchRecord.fromJson);
  }

  Future<void> deleteRecord(int recordId) async {
    await _delete('${_base}records/$recordId/');
  }

  Future<void> bulkDeleteRecords(List<int> ids) async {
    await _post('${_base}records/bulk-delete/', {'record_ids': ids});
  }

  Future<void> moveRecords({
    required List<int> ids,
    required int fromSheetId,
    required int toSheetId,
  }) async {
    await _post('${_base}records/move/', {
      'record_ids': ids,
      'from_sheet_id': fromSheetId,
      'to_sheet_id': toSheetId,
    });
  }

  // ─── CHECK & REFILL ───────────────────────────────────────────────────────

  Future<BatchCheckResult> checkSheet(int sheetId) async {
    final body = await _post('${_base}sheets/$sheetId/check/');
    final data = body['data'];
    if (data is Map<String, dynamic>) return BatchCheckResult.fromJson(data);
    return BatchCheckResult.fromJson(body);
  }

  Future<BatchRefillResult> refillSheet(int sheetId, String pin) async {
    final body =
        await _post('${_base}sheets/$sheetId/refill/', {'pin': pin});
    final data = body['data'];
    if (data is Map<String, dynamic>) return BatchRefillResult.fromJson(data);
    return BatchRefillResult.fromJson(body);
  }
}
