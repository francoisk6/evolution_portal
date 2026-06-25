import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/batch_refill_models.dart';
import '../../../services/batch_refill_service.dart';

// ─── BRANDS (session cache) ───────────────────────────────────────────────────

final batchBrandsProvider =
    AsyncNotifierProvider<BatchBrandsNotifier, List<BatchBrand>>(
  BatchBrandsNotifier.new,
);

class BatchBrandsNotifier extends AsyncNotifier<List<BatchBrand>> {
  @override
  Future<List<BatchBrand>> build() =>
      BatchRefillService.instance.getBrands();
}

// ─── BALANCES (session cache) ─────────────────────────────────────────────────

final batchBalancesProvider =
    AsyncNotifierProvider<BatchBalancesNotifier, List<BatchBalance>>(
  BatchBalancesNotifier.new,
);

class BatchBalancesNotifier extends AsyncNotifier<List<BatchBalance>> {
  @override
  Future<List<BatchBalance>> build() =>
      BatchRefillService.instance.getBalances();
}

// ─── SHEETS ───────────────────────────────────────────────────────────────────

final batchSheetsProvider =
    AsyncNotifierProvider<BatchSheetsNotifier, List<BatchSheet>>(
  BatchSheetsNotifier.new,
);

class BatchSheetsNotifier extends AsyncNotifier<List<BatchSheet>> {
  @override
  Future<List<BatchSheet>> build() =>
      BatchRefillService.instance.getSheets();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(BatchRefillService.instance.getSheets);
  }

  Future<BatchSheet> createSheet(String name) async {
    final sheet = await BatchRefillService.instance.createSheet(name);
    state = AsyncData([...state.value ?? [], sheet]);
    return sheet;
  }

  Future<BatchSheet> importSheet({
    required List<int> csvBytes,
    required String filename,
    String? name,
  }) async {
    final result = await BatchRefillService.instance.importSheet(
      csvBytes: csvBytes,
      filename: filename,
      name: name,
    );
    state = AsyncData([...state.value ?? [], result.sheet]);
    return result.sheet;
  }

  Future<void> deleteSheet(int id) async {
    await BatchRefillService.instance.deleteSheet(id);
    state = AsyncData((state.value ?? []).where((s) => s.id != id).toList());
  }
}

// ─── RECORDS (per sheet) ──────────────────────────────────────────────────────

final batchRecordsProvider = AsyncNotifierProvider.family<
    BatchRecordsNotifier, List<BatchRecord>, int>(
  BatchRecordsNotifier.new,
);

class BatchRecordsNotifier
    extends FamilyAsyncNotifier<List<BatchRecord>, int> {
  @override
  Future<List<BatchRecord>> build(int arg) =>
      BatchRefillService.instance.getRecords(arg);

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => BatchRefillService.instance.getRecords(arg),
    );
  }

  Future<BatchRecord> addRecord(Map<String, dynamic> data) async {
    final record =
        await BatchRefillService.instance.createRecord(arg, data);
    state = AsyncData([...state.value ?? [], record]);
    return record;
  }

  Future<void> updateRecord(int recordId, Map<String, dynamic> data) async {
    final updated =
        await BatchRefillService.instance.updateRecord(recordId, data);
    final current = state.value ?? [];
    state = AsyncData(
      current.map((r) => r.id == recordId ? updated : r).toList(),
    );
  }

  Future<void> deleteRecord(int recordId) async {
    await BatchRefillService.instance.deleteRecord(recordId);
    state = AsyncData(
      (state.value ?? []).where((r) => r.id != recordId).toList(),
    );
  }

  Future<void> bulkDelete(List<int> ids) async {
    await BatchRefillService.instance.bulkDeleteRecords(ids);
    final idSet = ids.toSet();
    state = AsyncData(
      (state.value ?? []).where((r) => !idSet.contains(r.id)).toList(),
    );
  }

  Future<BatchCheckResult> checkSheet() async {
    final result = await BatchRefillService.instance.checkSheet(arg);
    final current = state.value ?? [];
    if (result.records.isNotEmpty) {
      final updatedMap = {for (final r in result.records) r.id: r};
      state = AsyncData(
        current.map((r) => updatedMap[r.id] ?? r).toList(),
      );
    } else {
      final resultMap = {for (final r in result.results) r.recordId: r};
      state = AsyncData(
        current.map((r) {
          final res = resultMap[r.id];
          if (res == null) return r;
          final newStatus = res.note == 'Ready' ? 'Refill' : r.clientActive;
          return r.copyWith(clientActive: newStatus, note: res.note);
        }).toList(),
      );
    }
    return result;
  }

  Future<BatchRefillResult> refillSheet(String pin) async {
    final result =
        await BatchRefillService.instance.refillSheet(arg, pin);
    final current = state.value ?? [];
    if (result.records.isNotEmpty) {
      final updatedMap = {for (final r in result.records) r.id: r};
      state = AsyncData(
        current.map((r) => updatedMap[r.id] ?? r).toList(),
      );
    } else {
      final resultMap = {for (final r in result.results) r.recordId: r};
      state = AsyncData(
        current.map((r) {
          final res = resultMap[r.id];
          if (res == null) return r;
          return r.copyWith(clientActive: res.status, note: res.note);
        }).toList(),
      );
    }
    return result;
  }
}
