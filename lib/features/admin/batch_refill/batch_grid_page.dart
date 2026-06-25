import 'dart:async';
import 'dart:convert';
import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/batch_refill_models.dart';
import '../../../routing/route_names.dart';
import '../../../services/batch_refill_service.dart';
import '../../../state/page_refresh_provider.dart';
import '../../../utils/file_download.dart';
import '../../../utils/notify.dart';
import 'batch_record_edit_sheet.dart';
import 'batch_refill_providers.dart';

// ─── Column layout ────────────────────────────────────────────────────────────

class _Col {
  final String label;
  final double width;
  const _Col(this.label, this.width);
}

const _kCols = [
  _Col('#', 40),
  _Col('Cust.Name', 140),
  _Col('Cust.No', 88),
  _Col('Product', 120),
  _Col('Brand Code', 75),
  _Col('Brand', 155),
  _Col('DSL ID', 78),
  _Col('D. Price', 92),
  _Col('Cust. Price', 92),
  _Col('Currency', 62),
  _Col('Active', 95),
  _Col('Notes', 185),
  _Col('RF-Date', 148),
];

const double _kRowH = 36;

double get _kTotalWidth => _kCols.fold(0.0, (s, c) => s + c.width);

const _kStatuses = ['Inactive', 'Info', 'Refill', 'Refilled'];

// ─── Helpers ──────────────────────────────────────────────────────────────────

Color _statusFg(String s) {
  switch (s) {
    case 'Refilled':
      return Colors.green.shade700;
    case 'Refill':
      return Colors.orange.shade800;
    case 'Info':
      return Colors.blue.shade700;
    default:
      return Colors.grey.shade700;
  }
}

Color _statusBg(String s) {
  switch (s) {
    case 'Refilled':
      return Colors.green.shade50;
    case 'Refill':
      return Colors.orange.shade50;
    case 'Info':
      return Colors.blue.shade50;
    default:
      return Colors.grey.shade100;
  }
}

String _fmtPrice(String v) {
  if (v.isEmpty || v == '0') return '';
  final d = double.tryParse(v);
  return d == null ? v : d.toStringAsFixed(2);
}

String _fmtDate(String? v) {
  if (v == null || v.isEmpty) return '';
  return v.length > 16 ? v.substring(0, 16) : v;
}

// ─── Page ─────────────────────────────────────────────────────────────────────

class BatchGridPage extends ConsumerStatefulWidget {
  final int sheetId;
  final String sheetName;

  const BatchGridPage({
    required this.sheetId,
    required this.sheetName,
    super.key,
  });

  @override
  ConsumerState<BatchGridPage> createState() => _BatchGridPageState();
}

class _BatchGridPageState extends ConsumerState<BatchGridPage> {
  final _hScroll = ScrollController();
  final _vScroll = ScrollController();
  final _selected = <int>{};
  bool _selectMode = false;
  bool _checking = false;
  bool _submitting = false;
  bool _exporting = false;

  @override
  void dispose() {
    _hScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  // ─── Actions ─────────────────────────────────────────────────────────────

  Future<void> _openAddRecord() async {
    final brands = ref.read(batchBrandsProvider).value ?? [];
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => BatchRecordEditSheet(
        sheetId: widget.sheetId,
        record: null,
        brands: brands,
      ),
    );
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final n = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Records'),
        content: Text('Delete $n selected record${n == 1 ? '' : 's'}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(
                foregroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref
          .read(batchRecordsProvider(widget.sheetId).notifier)
          .bulkDelete(_selected.toList());
      setState(() {
        _selected.clear();
        _selectMode = false;
      });
      if (!mounted) return;
      showSuccess(context, '$n record${n == 1 ? '' : 's'} deleted.');
    } catch (e) {
      if (!mounted) return;
      showCaughtError(context, e);
    }
  }

  Future<void> _moveSelected() async {
    if (_selected.isEmpty) return;
    final sheets = (ref.read(batchSheetsProvider).value ?? [])
        .where((s) => s.id != widget.sheetId)
        .toList();
    if (sheets.isEmpty) {
      showError(context, 'No other sheets to move to.');
      return;
    }
    final dest = await showDialog<BatchSheet>(
      context: context,
      builder: (_) => _SheetPickerDialog(sheets: sheets),
    );
    if (dest == null || !mounted) return;
    try {
      await BatchRefillService.instance.moveRecords(
        ids: _selected.toList(),
        fromSheetId: widget.sheetId,
        toSheetId: dest.id,
      );
      await ref
          .read(batchRecordsProvider(widget.sheetId).notifier)
          .refresh();
      setState(() {
        _selected.clear();
        _selectMode = false;
      });
      if (!mounted) return;
      showSuccess(context, 'Moved to "${dest.name}".');
    } catch (e) {
      if (!mounted) return;
      showCaughtError(context, e);
    }
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      final r = await ref
          .read(batchRecordsProvider(widget.sheetId).notifier)
          .checkSheet();
      if (!mounted) return;
      showSuccess(context, '${r.valid} ready, ${r.invalid} error(s)');
    } on BatchSheetLockedException {
      if (!mounted) return;
      showError(context, 'Refill in progress — please wait.');
    } catch (e) {
      if (!mounted) return;
      showCaughtError(context, e);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _submit() async {
    final pin = await _showPinDialog();
    if (pin == null || !mounted) return;
    setState(() => _submitting = true);
    try {
      final r = await ref
          .read(batchRecordsProvider(widget.sheetId).notifier)
          .refillSheet(pin);
      if (!mounted) return;
      _showRefillResult(r);
    } on BatchSheetLockedException {
      if (!mounted) return;
      showError(context, 'Refill in progress — please wait.');
    } catch (e) {
      if (!mounted) return;
      showCaughtError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<String?> _showPinDialog() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter PIN'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          maxLength: 4,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
              hintText: '4-digit PIN', counterText: ''),
          onSubmitted: (v) {
            if (v.length == 4) Navigator.pop(ctx, v);
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.length == 4) Navigator.pop(ctx, v);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _showRefillResult(BatchRefillResult r) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Refill Complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _stat('Processed', r.processed),
            _stat('Success', r.success, color: Colors.green.shade700),
            _stat('Failed', r.failed,
                color: r.failed > 0 ? Colors.red.shade700 : null),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'))
        ],
      ),
    );
  }

  Widget _stat(String label, int v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(
              width: 100,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Text('$v',
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
        ]),
      );

  Future<void> _exportCsv(List<BatchRecord> records) async {
    setState(() => _exporting = true);
    try {
      final header = [
        'Cust.Name', 'Cust.No', 'Product', 'Brand Code', 'Brand',
        'DSL ID', 'Code', 'D.Price', 'Cust.Price', 'Currency',
        'Active', 'Notes', 'RF-Date',
      ];
      String q(String v) =>
          v.contains(',') || v.contains('"') || v.contains('\n')
              ? '"${v.replaceAll('"', '""')}"'
              : v;
      final rows = records.map((r) => [
            q(r.clientname), q(r.clientnumber), q(r.productName),
            q(r.brandCode), q(r.brandName), q(r.clientDsl), q(r.code),
            q(_fmtPrice(r.dealerPrice)), q(_fmtPrice(r.customerPrice)),
            q(r.currency), q(r.clientActive), q(r.note),
            q(r.refillDate ?? ''),
          ].join(','));
      final csv = [header.join(','), ...rows].join('\n');
      await saveDownloadedFile(
        bytes: utf8.encode(csv),
        filename: '${widget.sheetName}_batch_refill.csv',
        mimeType: 'text/csv',
      );
    } catch (e) {
      if (!mounted) return;
      showCaughtError(context, e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _saveRow(int recordId, Map<String, dynamic> data) =>
      ref
          .read(batchRecordsProvider(widget.sheetId).notifier)
          .updateRecord(recordId, data);

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(pageRefreshPulseProvider, (_, __) {
      ref.invalidate(batchBrandsProvider);
      ref.read(batchRecordsProvider(widget.sheetId).notifier).refresh();
    });

    final recordsAsync =
        ref.watch(batchRecordsProvider(widget.sheetId));
    final balancesAsync = ref.watch(batchBalancesProvider);
    ref.watch(batchBrandsProvider); // prefetch

    final records = recordsAsync.value ?? [];
    final busy = _checking || _submitting || _exporting;
    final hasInfo = records.any((r) => r.clientActive == 'Info');
    final hasRefill = records.any((r) => r.clientActive == 'Refill');
    final brands = ref.watch(batchBrandsProvider).value ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text('Batch Refill Grid: ${widget.sheetName}',
            overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add row',
            onPressed: busy ? null : _openAddRecord,
          ),
          if (_selectMode) ...[
            IconButton(
              icon: const Icon(Icons.drive_file_move_outline),
              tooltip: 'Move selected',
              onPressed: _selected.isEmpty ? null : _moveSelected,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete selected',
              onPressed: _selected.isEmpty ? null : _deleteSelected,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Exit selection',
              onPressed: () => setState(() {
                _selectMode = false;
                _selected.clear();
              }),
            ),
          ] else
            IconButton(
              icon: const Icon(Icons.checklist_outlined),
              tooltip: 'Select rows',
              onPressed: () => setState(() => _selectMode = true),
            ),
        ],
        bottom: busy
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                ),
              )
            : null,
      ),
      body: Column(
        children: [
          _BalanceBar(balancesAsync),
          const Divider(height: 1, thickness: 1),
          Expanded(
            child: recordsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(e.toString(),
                        style:
                            TextStyle(color: Colors.red.shade700)),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => ref
                          .read(batchRecordsProvider(widget.sheetId)
                              .notifier)
                          .refresh(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (records) =>
                  _buildGrid(records, brands),
            ),
          ),
          const Divider(height: 1, thickness: 1),
          _BottomBar(
            busy: busy,
            hasInfo: hasInfo,
            hasRefill: hasRefill,
            checking: _checking,
            submitting: _submitting,
            exporting: _exporting,
            onCancel: () => context.go(R.adminBatchRefill),
            onExport: () => _exportCsv(records),
            onSave: () async {
              ref.invalidate(batchBrandsProvider);
              await ref
                  .read(batchRecordsProvider(widget.sheetId).notifier)
                  .refresh();
            },
            onCheck: _check,
            onSubmit: _submit,
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(List<BatchRecord> records, List<BatchBrand> brands) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final gridW = max(_kTotalWidth, constraints.maxWidth);
        return Scrollbar(
          controller: _hScroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: gridW,
              height: constraints.maxHeight,
              child: Column(
                children: [
                  _Header(),
                  const Divider(height: 1, thickness: 1),
                  Expanded(
                    child: records.isEmpty
                        ? const Center(
                            child: Text('No records. Tap + to add.'))
                        : Scrollbar(
                            controller: _vScroll,
                            thumbVisibility: true,
                            child: ListView.builder(
                              controller: _vScroll,
                              itemCount: records.length,
                              itemBuilder: (_, i) => _EditableRow(
                                key: ValueKey(records[i].id),
                                record: records[i],
                                index: i,
                                isSelected:
                                    _selected.contains(records[i].id),
                                selectMode: _selectMode,
                                brands: brands,
                                onSave: _saveRow,
                                onToggleSelect: () => setState(() {
                                  final id = records[i].id;
                                  if (_selected.contains(id)) {
                                    _selected.remove(id);
                                  } else {
                                    _selected.add(id);
                                  }
                                }),
                                onEnterSelectMode: () => setState(() {
                                  _selectMode = true;
                                  _selected.add(records[i].id);
                                }),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Fixed header row ─────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final surface =
        Theme.of(context).colorScheme.surfaceContainerHighest;
    return Container(
      height: _kRowH,
      color: surface,
      child: Row(
        children: _kCols.map((col) {
          return SizedBox(
            width: col.width,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border(
                    right: BorderSide(color: Colors.grey.shade300)),
              ),
              alignment: col.label == '#'
                  ? Alignment.center
                  : Alignment.centerLeft,
              child: Text(
                col.label,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Editable row ─────────────────────────────────────────────────────────────

class _EditableRow extends StatefulWidget {
  final BatchRecord record;
  final int index;
  final bool isSelected;
  final bool selectMode;
  final List<BatchBrand> brands;
  final Future<void> Function(int id, Map<String, dynamic> data) onSave;
  final VoidCallback onToggleSelect;
  final VoidCallback onEnterSelectMode;

  const _EditableRow({
    required super.key,
    required this.record,
    required this.index,
    required this.isSelected,
    required this.selectMode,
    required this.brands,
    required this.onSave,
    required this.onToggleSelect,
    required this.onEnterSelectMode,
  });

  @override
  State<_EditableRow> createState() => _EditableRowState();
}

class _EditableRowState extends State<_EditableRow> {
  late TextEditingController _nameCtrl;
  late TextEditingController _numCtrl;
  late TextEditingController _dslCtrl;
  late TextEditingController _dPriceCtrl;
  late TextEditingController _cPriceCtrl;

  late FocusNode _nameFn;
  late FocusNode _numFn;
  late FocusNode _dslFn;
  late FocusNode _dPriceFn;
  late FocusNode _cPriceFn;

  BatchBrand? _brand;
  String _status = 'Inactive';
  bool _saving = false;
  bool _needsSaveAfter = false;

  bool get _isRefilled => _status == 'Refilled';

  bool get _anyFocused =>
      _nameFn.hasFocus ||
      _numFn.hasFocus ||
      _dslFn.hasFocus ||
      _dPriceFn.hasFocus ||
      _cPriceFn.hasFocus;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    _nameCtrl = TextEditingController(text: r.clientname);
    _numCtrl = TextEditingController(text: r.clientnumber);
    _dslCtrl = TextEditingController(text: r.clientDsl);
    _dPriceCtrl = TextEditingController(text: r.dealerPrice);
    _cPriceCtrl = TextEditingController(text: r.customerPrice);
    _status = r.clientActive;
    _brand = widget.brands
        .where((b) =>
            b.id == r.brandId ||
            (r.brandId == null && b.code == r.brandCode))
        .cast<BatchBrand?>()
        .firstOrNull;

    _nameFn = _fn();
    _numFn = _fn();
    _dslFn = _fn();
    _dPriceFn = _fn();
    _cPriceFn = _fn();
  }

  FocusNode _fn() {
    final n = FocusNode();
    n.addListener(() {
      if (!n.hasFocus) _scheduleCommit();
      if (mounted) setState(() {});
    });
    return n;
  }

  Timer? _commitTimer;

  void _scheduleCommit() {
    _commitTimer?.cancel();
    _commitTimer =
        Timer(const Duration(milliseconds: 80), () {
      if (mounted) _commit();
    });
  }

  @override
  void didUpdateWidget(_EditableRow old) {
    super.didUpdateWidget(old);
    final r = widget.record;
    final p = old.record;
    if (r.clientActive != p.clientActive && !_anyFocused) {
      _status = r.clientActive;
    }
  }

  @override
  void dispose() {
    _commitTimer?.cancel();
    for (final c in [
      _nameCtrl, _numCtrl, _dslCtrl, _dPriceCtrl, _cPriceCtrl
    ]) {
      c.dispose();
    }
    for (final f in [
      _nameFn, _numFn, _dslFn, _dPriceFn, _cPriceFn
    ]) {
      f.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _buildData() {
    final r = widget.record;
    return {
      'clientname': _nameCtrl.text.trim(),
      'clientnumber': _numCtrl.text.trim(),
      'client_dsl': _dslCtrl.text.trim(),
      'code': widget.record.code,
      'client_active': _status,
      'dealer_price': _dPriceCtrl.text.trim(),
      'customer_price': _cPriceCtrl.text.trim(),
      if (_brand != null) 'brand_id': _brand!.id,
      'brand_code': _brand?.code ?? r.brandCode,
      'brand_name': _brand?.name ?? r.brandName,
      'product_name': _brand?.product ?? r.productName,
    };
  }

  bool _hasChanged(Map<String, dynamic> d) {
    final r = widget.record;
    return d['clientname'] != r.clientname ||
        d['clientnumber'] != r.clientnumber ||
        d['client_dsl'] != r.clientDsl ||
        d['client_active'] != r.clientActive ||
        d['dealer_price'] != r.dealerPrice ||
        d['customer_price'] != r.customerPrice ||
        (d['brand_id'] as int?) != r.brandId;
  }

  Future<void> _commit() async {
    if (_saving) {
      _needsSaveAfter = true;
      return;
    }
    final data = _buildData();
    if (!_hasChanged(data)) return;

    if (mounted) setState(() => _saving = true);
    _needsSaveAfter = false;
    try {
      await widget.onSave(widget.record.id, data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        if (_needsSaveAfter) _commit();
      }
    }
  }

  Future<void> _changeStatus(String v) async {
    _commitTimer?.cancel();
    setState(() => _status = v);
    await _commit();
  }

  Future<void> _pickBrand() async {
    _commitTimer?.cancel();
    final picked = await showModalBottomSheet<BatchBrand>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BrandPickerSheet(brands: widget.brands),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _brand = picked;
      _dPriceCtrl.text = picked.dealerPrice;
      _cPriceCtrl.text = picked.customerPrice;
    });
    await _commit();
  }

  // ─── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.isSelected;
    final Color rowBg;
    if (isSelected) {
      rowBg = Colors.blue.shade50;
    } else if (_isRefilled) {
      rowBg = Colors.green.shade50;
    } else {
      rowBg = widget.index.isEven
          ? Colors.white
          : const Color(0xFFFAFAFA);
    }

    final r = widget.record;
    final productName = _brand?.product ?? r.productName;
    final brandCode = _brand?.code ?? r.brandCode;
    final currency = _brand?.currency ?? r.currency;

    return Column(
      children: [
        GestureDetector(
          onLongPress:
              widget.selectMode ? null : widget.onEnterSelectMode,
          child: Container(
            color: rowBg,
            child: Row(
              children: [
                // ─ # / checkbox ────────────────────────────────────────
                _numCell(widget.index, isSelected),

                // ─ Cust.Name ───────────────────────────────────────────
                _editCell(_nameCtrl, _kCols[1].width, _nameFn),

                // ─ Cust.No ─────────────────────────────────────────────
                _editCell(_numCtrl, _kCols[2].width, _numFn,
                    keyboardType: TextInputType.number),

                // ─ Product (read-only, from brand) ─────────────────────
                _readCell(productName, _kCols[3].width),

                // ─ Brand Code (read-only, from brand) ──────────────────
                _readCell(brandCode, _kCols[4].width),

                // ─ Brand (tap to pick) ─────────────────────────────────
                _brandCell(r),

                // ─ DSL ID ──────────────────────────────────────────────
                _editCell(_dslCtrl, _kCols[6].width, _dslFn),

                // ─ D.Price ─────────────────────────────────────────────
                _editCell(_dPriceCtrl, _kCols[7].width, _dPriceFn,
                    textAlign: TextAlign.right,
                    keyboardType:
                        const TextInputType.numberWithOptions(
                            decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[\d.]'))
                    ]),

                // ─ Cust.Price ──────────────────────────────────────────
                _editCell(_cPriceCtrl, _kCols[8].width, _cPriceFn,
                    textAlign: TextAlign.right,
                    keyboardType:
                        const TextInputType.numberWithOptions(
                            decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[\d.]'))
                    ]),

                // ─ Currency (read-only) ────────────────────────────────
                _readCell(currency, _kCols[9].width,
                    align: Alignment.center),

                // ─ Active / status dropdown ────────────────────────────
                _statusCell(),

                // ─ Notes (read-only) ───────────────────────────────────
                _readCell(r.note, _kCols[11].width),

                // ─ RF-Date (read-only) ─────────────────────────────────
                _readCell(_fmtDate(r.refillDate), _kCols[12].width),
              ],
            ),
          ),
        ),
        Divider(
            height: 1,
            thickness: 1,
            color: Colors.grey.shade200),
      ],
    );
  }

  // ─── Cell helpers ─────────────────────────────────────────────────────────

  Widget _numCell(int index, bool isSelected) {
    return SizedBox(
      width: _kCols[0].width,
      height: _kRowH,
      child: InkWell(
        onTap: widget.selectMode ? widget.onToggleSelect : null,
        child: Container(
          decoration: BoxDecoration(
            border:
                Border(right: BorderSide(color: Colors.grey.shade200)),
          ),
          alignment: Alignment.center,
          child: widget.selectMode
              ? Checkbox(
                  value: isSelected,
                  onChanged: (_) => widget.onToggleSelect(),
                  visualDensity: VisualDensity.compact,
                )
              : _saving
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Colors.grey.shade400),
                    )
                  : Text(
                      '${index + 1}',
                      style: TextStyle(
                          fontSize: 10, color: Colors.grey.shade600),
                    ),
        ),
      ),
    );
  }

  Widget _editCell(
    TextEditingController ctrl,
    double width,
    FocusNode fn, {
    bool readOnly = false,
    TextAlign textAlign = TextAlign.left,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final focused = fn.hasFocus;
    return SizedBox(
      width: width,
      height: _kRowH,
      child: Container(
        decoration: BoxDecoration(
          color: focused
              ? Colors.blue.shade50
              : readOnly
                  ? null
                  : Colors.white,
          border: Border(
            right: BorderSide(color: Colors.grey.shade200),
            bottom: focused
                ? BorderSide(color: Colors.blue.shade400, width: 2)
                : readOnly
                    ? BorderSide.none
                    : BorderSide(color: Colors.grey.shade300),
          ),
        ),
        child: readOnly
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Align(
                  alignment: textAlign == TextAlign.right
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Text(ctrl.text,
                      style: const TextStyle(fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1),
                ),
              )
            : TextField(
                controller: ctrl,
                focusNode: fn,
                textAlign: textAlign,
                keyboardType: keyboardType,
                inputFormatters: inputFormatters,
                style: const TextStyle(fontSize: 11),
                mouseCursor: SystemMouseCursors.text,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 6, vertical: 10),
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _commit(),
              ),
      ),
    );
  }

  Widget _readCell(String text, double width,
      {Alignment align = Alignment.centerLeft}) {
    return SizedBox(
      width: width,
      height: _kRowH,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border:
              Border(right: BorderSide(color: Colors.grey.shade200)),
        ),
        alignment: align,
        child: Text(text,
            style: const TextStyle(fontSize: 11),
            overflow: TextOverflow.ellipsis,
            maxLines: 1),
      ),
    );
  }

  Widget _brandCell(BatchRecord r) {
    final label = _brand?.alt ?? _brand?.name ?? r.brandName;
    return SizedBox(
      width: _kCols[5].width,
      height: _kRowH,
      child: InkWell(
        onTap: _pickBrand,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border(
                right: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1),
              ),
              Icon(Icons.arrow_drop_down,
                  size: 16, color: Colors.grey.shade500),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusCell() {
    return SizedBox(
      width: _kCols[10].width,
      height: _kRowH,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          border:
              Border(right: BorderSide(color: Colors.grey.shade200)),
        ),
        alignment: Alignment.center,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _status,
            isDense: true,
            style: TextStyle(fontSize: 11, color: _statusFg(_status), fontWeight: FontWeight.w600),
            selectedItemBuilder: (_) => _kStatuses
                .map((_) => Center(child: _StatusChip(status: _status)))
                .toList(),
            items: _kStatuses
                .map((s) => DropdownMenuItem(
                      value: s,
                      child: Text(s,
                          style: TextStyle(
                              fontSize: 11,
                              color: _statusFg(s))),
                    ))
                .toList(),
            onChanged: (v) => v != null ? _changeStatus(v) : null,
          ),
        ),
      ),
    );
  }
}

// ─── Status chip ──────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _statusBg(status),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
            color: _statusFg(status).withValues(alpha: 0.35)),
      ),
      child: Text(
        status,
        style: TextStyle(
            color: _statusFg(status),
            fontSize: 10,
            fontWeight: FontWeight.w600),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ─── Balance bar ──────────────────────────────────────────────────────────────

class _BalanceBar extends StatelessWidget {
  final AsyncValue<List<BatchBalance>> balancesAsync;
  const _BalanceBar(this.balancesAsync);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color:
          Theme.of(context).colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          const Text('Current Balance:',
              style: TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13)),
          const Spacer(),
          balancesAsync.when(
            loading: () => const SizedBox(
                width: 18,
                height: 18,
                child:
                    CircularProgressIndicator(strokeWidth: 2)),
            error: (_, __) => const SizedBox.shrink(),
            data: (bs) => Row(
              mainAxisSize: MainAxisSize.min,
              children: bs
                  .map((b) => Padding(
                        padding:
                            const EdgeInsets.only(left: 20),
                        child: Text(
                          '${_fmtPrice(b.balance)} ${b.currency}',
                          style: TextStyle(
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bottom action bar ────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final bool busy, hasInfo, hasRefill, checking, submitting, exporting;
  final VoidCallback onCancel, onExport, onSave, onCheck, onSubmit;

  const _BottomBar({
    required this.busy,
    required this.hasInfo,
    required this.hasRefill,
    required this.checking,
    required this.submitting,
    required this.exporting,
    required this.onCancel,
    required this.onExport,
    required this.onSave,
    required this.onCheck,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          OutlinedButton(
              onPressed: onCancel, child: const Text('Cancel')),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: busy ? null : onExport,
            icon: exporting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_outlined, size: 16),
            label: const Text('Export'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: busy ? null : onSave,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Save'),
          ),
          const Spacer(),
          if (hasInfo) ...[
            OutlinedButton.icon(
              onPressed: busy ? null : onCheck,
              icon: checking
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child:
                          CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.fact_check_outlined, size: 16),
              label: const Text('Check'),
            ),
            const SizedBox(width: 8),
          ],
          if (hasRefill)
            FilledButton.icon(
              onPressed: busy ? null : onSubmit,
              icon: submitting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_outlined, size: 16),
              label: const Text('Submit'),
            ),
        ],
      ),
    );
  }
}

// ─── Sheet picker dialog ──────────────────────────────────────────────────────

class _SheetPickerDialog extends StatefulWidget {
  final List<BatchSheet> sheets;
  const _SheetPickerDialog({required this.sheets});

  @override
  State<_SheetPickerDialog> createState() => _SheetPickerDialogState();
}

class _SheetPickerDialogState extends State<_SheetPickerDialog> {
  BatchSheet? _selected;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Move to Sheet'),
      content: InputDecorator(
        decoration: const InputDecoration(
            isDense: true, border: OutlineInputBorder()),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<BatchSheet>(
            value: _selected,
            hint: const Text('Select sheet'),
            isDense: true,
            items: widget.sheets
                .map((s) => DropdownMenuItem(
                    value: s, child: Text(s.name)))
                .toList(),
            onChanged: (v) => setState(() => _selected = v),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _selected == null
              ? null
              : () => Navigator.pop(context, _selected),
          child: const Text('Move'),
        ),
      ],
    );
  }
}

// ─── Brand picker sheet ───────────────────────────────────────────────────────

class _BrandPickerSheet extends StatefulWidget {
  final List<BatchBrand> brands;
  const _BrandPickerSheet({required this.brands});

  @override
  State<_BrandPickerSheet> createState() => _BrandPickerSheetState();
}

class _BrandPickerSheetState extends State<_BrandPickerSheet> {
  final _searchCtrl = TextEditingController();
  late List<BatchBrand> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.brands;
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _filter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? widget.brands
          : widget.brands
              .where((b) =>
                  b.code.toLowerCase().contains(q) ||
                  (b.alt ?? b.name).toLowerCase().contains(q) ||
                  b.name.toLowerCase().contains(q) ||
                  b.product.toLowerCase().contains(q))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.75,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16, 4, 16,
          MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Column(
          children: [
            Text('Select Brand',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Search by code, name, or product…',
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(child: Text('No brands found.'))
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) {
                        final b = _filtered[i];
                        return ListTile(
                          dense: true,
                          title: Text('${b.code} – ${b.alt ?? b.name}',
                              style:
                                  const TextStyle(fontSize: 13)),
                          subtitle: Text(
                            '${b.product}  •  ${b.currency}  •  D: ${b.dealerPrice}  C: ${b.customerPrice}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          onTap: () =>
                              Navigator.pop(context, b),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
