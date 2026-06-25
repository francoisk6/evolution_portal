import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/batch_refill_models.dart';
import '../../../utils/notify.dart';
import 'batch_refill_providers.dart';

const _kStatuses = ['Inactive', 'Info', 'Refill', 'Refilled'];

class BatchRecordEditSheet extends ConsumerStatefulWidget {
  final int sheetId;
  final BatchRecord? record;
  final List<BatchBrand> brands;

  const BatchRecordEditSheet({
    required this.sheetId,
    required this.record,
    required this.brands,
    super.key,
  });

  @override
  ConsumerState<BatchRecordEditSheet> createState() =>
      _BatchRecordEditSheetState();
}

class _BatchRecordEditSheetState
    extends ConsumerState<BatchRecordEditSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _numberCtrl;
  late final TextEditingController _dslCtrl;
  late final TextEditingController _codeCtrl;
  late final TextEditingController _dealerPriceCtrl;
  late final TextEditingController _custPriceCtrl;
  late final TextEditingController _noteCtrl;

  BatchBrand? _selectedBrand;
  String _status = 'Inactive';
  bool _saving = false;
  bool _deleting = false;

  bool get _isNew => widget.record == null;
  bool get _isRefilled => _status == 'Refilled';

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    _nameCtrl = TextEditingController(text: r?.clientname ?? '');
    _numberCtrl = TextEditingController(text: r?.clientnumber ?? '');
    _dslCtrl = TextEditingController(text: r?.clientDsl ?? '');
    _codeCtrl = TextEditingController(text: r?.code ?? '');
    _dealerPriceCtrl =
        TextEditingController(text: r?.dealerPrice ?? '');
    _custPriceCtrl =
        TextEditingController(text: r?.customerPrice ?? '');
    _noteCtrl = TextEditingController(text: r?.note ?? '');
    _status = r?.clientActive ?? 'Inactive';

    if (r?.brandId != null) {
      _selectedBrand = widget.brands
          .where((b) => b.id == r!.brandId)
          .cast<BatchBrand?>()
          .firstOrNull;
    }
    if (_selectedBrand == null && (r?.brandCode ?? '').isNotEmpty) {
      _selectedBrand = widget.brands
          .where((b) => b.code == r!.brandCode)
          .cast<BatchBrand?>()
          .firstOrNull;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _numberCtrl.dispose();
    _dslCtrl.dispose();
    _codeCtrl.dispose();
    _dealerPriceCtrl.dispose();
    _custPriceCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _applyBrand(BatchBrand brand) {
    setState(() => _selectedBrand = brand);
    _dealerPriceCtrl.text = brand.dealerPrice;
    _custPriceCtrl.text = brand.customerPrice;
  }

  Future<void> _pickBrand() async {
    final picked = await showModalBottomSheet<BatchBrand>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _BrandPickerSheet(brands: widget.brands),
    );
    if (picked != null) _applyBrand(picked);
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      showError(context, 'Customer name is required.');
      return;
    }
    setState(() => _saving = true);
    try {
      final data = <String, dynamic>{
        'clientname': name,
        'clientnumber': _numberCtrl.text.trim(),
        'client_dsl': _dslCtrl.text.trim(),
        'code': _codeCtrl.text.trim(),
        'client_active': _status,
        'note': _noteCtrl.text.trim(),
        if (_selectedBrand != null) 'brand_id': _selectedBrand!.id,
        'brand_code': _selectedBrand?.code ?? '',
        'brand_name': _selectedBrand?.name ?? '',
        'product_name': _selectedBrand?.product ?? '',
        'dealer_price': _dealerPriceCtrl.text.trim(),
        'customer_price': _custPriceCtrl.text.trim(),
      };

      final notifier =
          ref.read(batchRecordsProvider(widget.sheetId).notifier);
      if (_isNew) {
        await notifier.addRecord(data);
      } else {
        await notifier.updateRecord(widget.record!.id, data);
      }
      if (!mounted) return;
      Navigator.pop(context);
      showSuccess(context, _isNew ? 'Record added.' : 'Record saved.');
    } catch (e) {
      if (!mounted) return;
      showCaughtError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Record'),
        content: const Text('Delete this record? Cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            style:
                TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await ref
          .read(batchRecordsProvider(widget.sheetId).notifier)
          .deleteRecord(widget.record!.id);
      if (!mounted) return;
      Navigator.pop(context);
      showSuccess(context, 'Record deleted.');
    } catch (e) {
      if (!mounted) return;
      showCaughtError(context, e);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _saving || _deleting;
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title
            Text(
              _isNew ? 'Add Record' : 'Edit Record',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // ─── Customer info ────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _field(
                    label: 'Cust. Name *',
                    controller: _nameCtrl,
                    enabled: !busy && !_isRefilled,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _field(
                    label: 'Cust. No',
                    controller: _numberCtrl,
                    enabled: !busy && !_isRefilled,
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _field(
                    label: 'DSL ID',
                    controller: _dslCtrl,
                    enabled: !busy && !_isRefilled,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    label: 'Code',
                    controller: _codeCtrl,
                    enabled: !busy && !_isRefilled,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ─── Brand picker ─────────────────────────────────────────
            _BrandField(
              selected: _selectedBrand,
              enabled: !busy && !_isRefilled,
              onTap: _pickBrand,
            ),
            const SizedBox(height: 12),

            // ─── Prices ───────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _field(
                    label: 'Dealer Price',
                    controller: _dealerPriceCtrl,
                    enabled: !busy && !_isRefilled,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[\d.]'))
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    label: 'Cust. Price',
                    controller: _custPriceCtrl,
                    enabled: !busy && !_isRefilled,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[\d.]'))
                    ],
                  ),
                ),
                if (_selectedBrand != null) ...[
                  const SizedBox(width: 12),
                  Chip(
                    label: Text(_selectedBrand!.currency,
                        style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),

            // ─── Status ───────────────────────────────────────────────
            _StatusField(
              value: _status,
              enabled: !busy && !_isRefilled,
              onChanged: (v) => setState(() => _status = v),
            ),
            const SizedBox(height: 12),

            // ─── Note ─────────────────────────────────────────────────
            _field(
              label: 'Note',
              controller: _noteCtrl,
              enabled: !busy && _status == 'Inactive',
              maxLines: 2,
            ),
            const SizedBox(height: 20),

            // ─── Action buttons ───────────────────────────────────────
            Row(
              children: [
                if (!_isNew) ...[
                  OutlinedButton.icon(
                    onPressed: busy ? null : _delete,
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700),
                    icon: _deleting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2))
                        : const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Delete'),
                  ),
                  const SizedBox(width: 8),
                ],
                const Spacer(),
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: busy ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    bool enabled = true,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

// ─── Brand field (tap-to-pick) ────────────────────────────────────────────────

class _BrandField extends StatelessWidget {
  final BatchBrand? selected;
  final bool enabled;
  final VoidCallback onTap;

  const _BrandField({
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Brand',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.hintColor)),
        const SizedBox(height: 4),
        InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(
                  color: enabled
                      ? theme.colorScheme.outline
                      : theme.disabledColor),
              borderRadius: BorderRadius.circular(4),
              color: enabled ? null : theme.disabledColor.withValues(alpha: 0.05),
            ),
            child: Row(
              children: [
                Expanded(
                  child: selected == null
                      ? Text('Select brand…',
                          style: TextStyle(
                              color: theme.hintColor, fontSize: 13))
                      : Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            Text(
                              '${selected!.code} – ${selected!.alt ?? selected!.name}',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              selected!.product,
                              style: const TextStyle(fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                ),
                Icon(Icons.arrow_drop_down,
                    color: enabled
                        ? theme.colorScheme.onSurface
                        : theme.disabledColor),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Status field ─────────────────────────────────────────────────────────────

class _StatusField extends StatelessWidget {
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _StatusField({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Status',
        isDense: true,
        border: const OutlineInputBorder(),
        enabled: enabled,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          items: _kStatuses
              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
              .toList(),
          onChanged:
              enabled ? (v) => v != null ? onChanged(v) : null : null,
        ),
      ),
    );
  }
}

// ─── Brand picker bottom sheet ────────────────────────────────────────────────

class _BrandPickerSheet extends StatefulWidget {
  final List<BatchBrand> brands;
  const _BrandPickerSheet({required this.brands});

  @override
  State<_BrandPickerSheet> createState() => _BrandPickerSheetState();
}

class _BrandPickerSheetState extends State<_BrandPickerSheet> {
  final _searchCtrl = TextEditingController();
  List<BatchBrand> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.brands;
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = widget.brands;
      } else {
        _filtered = widget.brands.where((b) {
          return b.code.toLowerCase().contains(q) ||
              (b.alt ?? b.name).toLowerCase().contains(q) ||
              b.name.toLowerCase().contains(q) ||
              b.product.toLowerCase().contains(q);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.75,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
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
                          title: Text(
                            '${b.code} – ${b.alt ?? b.name}',
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            '${b.product}  •  ${b.currency}  •  D: ${b.dealerPrice}  C: ${b.customerPrice}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          onTap: () => Navigator.pop(context, b),
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
