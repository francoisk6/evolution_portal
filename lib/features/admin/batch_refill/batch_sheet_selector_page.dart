import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../routing/route_names.dart';
import '../../../utils/csv_file_picker.dart';
import '../../../utils/notify.dart';
import 'batch_refill_providers.dart';

class BatchSheetSelectorPage extends ConsumerStatefulWidget {
  const BatchSheetSelectorPage({super.key});

  @override
  ConsumerState<BatchSheetSelectorPage> createState() =>
      _BatchSheetSelectorPageState();
}

class _BatchSheetSelectorPageState
    extends ConsumerState<BatchSheetSelectorPage> {
  final _newNameCtrl = TextEditingController();
  String? _loadingAction;

  @override
  void dispose() {
    _newNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _createSheet() async {
    final name = _newNameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _loadingAction = 'Creating...');
    try {
      final sheet =
          await ref.read(batchSheetsProvider.notifier).createSheet(name);
      if (!mounted) return;
      _newNameCtrl.clear();
      context.go(
        '${R.adminBatchRefill}/${sheet.id}?name=${Uri.encodeComponent(sheet.name)}',
      );
    } catch (e) {
      if (!mounted) return;
      showCaughtError(context, e);
    } finally {
      if (mounted) setState(() => _loadingAction = null);
    }
  }

  Future<void> _importCsv() async {
    final picked = await pickCsvFile();
    if (picked == null) return;
    setState(() => _loadingAction = 'Importing...');
    try {
      final sheet =
          await ref.read(batchSheetsProvider.notifier).importSheet(
                csvBytes: picked.bytes,
                filename: picked.filename,
              );
      if (!mounted) return;
      context.go(
        '${R.adminBatchRefill}/${sheet.id}?name=${Uri.encodeComponent(sheet.name)}',
      );
    } catch (e) {
      if (!mounted) return;
      showCaughtError(context, e);
    } finally {
      if (mounted) setState(() => _loadingAction = null);
    }
  }

  Future<void> _deleteSheet(int id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Sheet'),
        content: Text('Delete "$name"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
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
    try {
      await ref.read(batchSheetsProvider.notifier).deleteSheet(id);
      if (!mounted) return;
      showSuccess(context, 'Sheet deleted.');
    } catch (e) {
      if (!mounted) return;
      showCaughtError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheetsAsync = ref.watch(batchSheetsProvider);
    final busy = _loadingAction != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Batch Refill Sheet (Online)'),
        bottom: busy
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              )
            : null,
      ),
      body: sheetsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(e.toString(),
                  style: TextStyle(color: Colors.red.shade700)),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () =>
                    ref.read(batchSheetsProvider.notifier).refresh(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (sheets) => _buildBody(context, sheets, busy),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<dynamic> sheets,
    bool busy,
  ) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Choose an option:',
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: theme.colorScheme.primary)),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // ─── Existing sheets ───────────────────────────────────────────
            Text('Select existing Sheet',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text('Name:', style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            if (sheets.isEmpty)
              Container(
                height: 52,
                decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text('----------',
                    style: TextStyle(color: theme.hintColor)),
              )
            else
              _SheetDropdown(
                sheets: sheets.cast(),
                onSelected: (sheet) {
                  context.go(
                    '${R.adminBatchRefill}/${sheet.id}?name=${Uri.encodeComponent(sheet.name)}',
                  );
                },
                onDelete: (sheet) =>
                    _deleteSheet(sheet.id, sheet.name),
              ),

            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 20),

            // ─── New sheet ─────────────────────────────────────────────────
            Text('Or create new empty Sheet',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text('Name:', style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newNameCtrl,
                    enabled: !busy,
                    decoration: const InputDecoration(
                      hintText: 'Sheet Name',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _createSheet(),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: busy ? null : _createSheet,
                  child: const Text('Create'),
                ),
              ],
            ),

            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 20),

            // ─── Import CSV ────────────────────────────────────────────────
            Text('Or import Sheet', style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            Row(
              children: [
                Text('Import CSV File:',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: busy ? null : _importCsv,
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('Choose File'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'FORMAT: Cust.Name | Cust.No | Product | Brand Code',
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontStyle: FontStyle.italic),
            ),

            const SizedBox(height: 32),
            Row(
              children: [
                OutlinedButton(
                  onPressed: () => context.pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sheet dropdown with delete ────────────────────────────────────────────────

class _SheetDropdown extends StatefulWidget {
  final List<dynamic> sheets;
  final void Function(dynamic sheet) onSelected;
  final void Function(dynamic sheet) onDelete;

  const _SheetDropdown({
    required this.sheets,
    required this.onSelected,
    required this.onDelete,
  });

  @override
  State<_SheetDropdown> createState() => _SheetDropdownState();
}

class _SheetDropdownState extends State<_SheetDropdown> {
  dynamic _selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: theme.dividerColor),
              borderRadius: BorderRadius.circular(6),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<dynamic>(
                value: _selected,
                hint: Text('----------',
                    style: TextStyle(color: theme.hintColor)),
                isExpanded: true,
                items: widget.sheets.map((s) {
                  return DropdownMenuItem<dynamic>(
                    value: s,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${s.name}  (${s.recordCount} records)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (s.locked)
                          Icon(Icons.lock_outline,
                              size: 14,
                              color: theme.colorScheme.error),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _selected = v),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton(
          onPressed: _selected == null
              ? null
              : () => widget.onSelected(_selected),
          child: const Text('Next'),
        ),
        if (_selected != null) ...[
          const SizedBox(width: 6),
          IconButton(
            icon: Icon(Icons.delete_outline,
                color: Colors.red.shade700, size: 20),
            tooltip: 'Delete sheet',
            onPressed: () => widget.onDelete(_selected),
          ),
        ],
      ],
    );
  }
}
