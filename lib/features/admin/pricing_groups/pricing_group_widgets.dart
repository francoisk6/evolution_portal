import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/models/pricing_group.dart';
import '../../../services/pricing_group_service.dart';

/// Shared pieces of the pricing-group screens.

String friendlyPricingError(Object e) {
  final text = e.toString().replaceFirst('Exception: ', '').trim();
  if (text.contains('HTTP 403')) return 'You do not have permission to manage pricing groups.';
  return text.isEmpty ? 'Request failed.' : text;
}

void showPricingSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? const Color(0xFFB91C1C) : null,
      duration: Duration(seconds: error ? 6 : 4),
    ));
}

Future<void> showPricingError(BuildContext context, Object e) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.error_outline, color: Color(0xFFB91C1C)),
      title: const Text('Not saved'),
      content: SingleChildScrollView(child: Text(friendlyPricingError(e))),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
      ],
    ),
  );
}

/// Shows what a change will do and asks to confirm. Returns true to apply.
Future<bool> confirmPricingPreview(
  BuildContext context, {
  required String title,
  required PricingSaveResult preview,
  String confirmLabel = 'Apply',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (preview.prunedCount > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${preview.prunedCount} item(s) are already covered by a parent and will be removed.',
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFF92400E)),
                  ),
                ),
              PricingSummaryPanel(summary: preview.summary),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(confirmLabel)),
      ],
    ),
  );
  return ok == true;
}

class PricingSummaryPanel extends StatelessWidget {
  final PricingApplySummary summary;
  final String? title;

  const PricingSummaryPanel({super.key, required this.summary, this.title});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.primary.withValues(alpha: .18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(title!, style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          for (final line in summary.lines())
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6, right: 8),
                    child: Icon(Icons.circle, size: 6),
                  ),
                  Expanded(child: Text(line, style: const TextStyle(fontSize: 13))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class PricingInfoChip extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color? color;

  const PricingInfoChip(this.text, {super.key, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.grey.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: .25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: c), const SizedBox(width: 4)],
          Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
        ],
      ),
    );
  }
}

/// A titled list of removable chips with an "Add" button.
class PricingItemSection extends StatelessWidget {
  final String title;
  final String? help;
  final List<PricingGroupItem> items;
  final VoidCallback? onAdd;
  final ValueChanged<PricingGroupItem>? onRemove;
  final String emptyText;

  const PricingItemSection({
    super.key,
    required this.title,
    required this.items,
    this.help,
    this.onAdd,
    this.onRemove,
    this.emptyText = 'None',
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('$title (${items.length})',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                ),
                if (onAdd != null)
                  TextButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                  ),
              ],
            ),
            if (help != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(help!, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ),
            if (items.isEmpty)
              Text(emptyText, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500))
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final item in items)
                    InputChip(
                      label: Text(
                        item.subtitle.isEmpty ? item.label : '${item.label} · ${item.subtitle}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      tooltip: item.productIds.length > 1
                          ? '${item.productIds.length} products share this name'
                          : null,
                      onDeleted: onRemove == null ? null : () => onRemove!(item),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet: server-side search, multi-select. Returns the picked items.
Future<List<PricingGroupItem>?> pickPricingItems(
  BuildContext context, {
  required PricingItemKind kind,
  required Set<String> alreadySelectedKeys,
  int? withinGroup,
  String? title,
}) {
  return showModalBottomSheet<List<PricingGroupItem>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.82,
      child: _PricingItemPicker(
        kind: kind,
        withinGroup: withinGroup,
        alreadySelectedKeys: alreadySelectedKeys,
        title: title ?? 'Add ${kind.title.toLowerCase()}',
      ),
    ),
  );
}

class _PricingItemPicker extends StatefulWidget {
  final PricingItemKind kind;
  final int? withinGroup;
  final Set<String> alreadySelectedKeys;
  final String title;

  const _PricingItemPicker({
    required this.kind,
    required this.withinGroup,
    required this.alreadySelectedKeys,
    required this.title,
  });

  @override
  State<_PricingItemPicker> createState() => _PricingItemPickerState();
}

class _PricingItemPickerState extends State<_PricingItemPicker> {
  final _searchCtl = TextEditingController();
  final Map<String, PricingGroupItem> _picked = {};
  List<PricingGroupItem> _options = const [];
  bool _loading = false;
  String? _error;
  Timer? _debounce;
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _load() async {
    final seq = ++_requestSeq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final options = await PricingGroupService.instance.options(
        kind: widget.kind,
        search: _searchCtl.text,
        withinGroup: widget.withinGroup,
      );
      if (!mounted || seq != _requestSeq) return;
      setState(() => _options = options);
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() => _error = friendlyPricingError(e));
    } finally {
      if (mounted && seq == _requestSeq) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, MediaQuery.of(context).viewInsets.bottom + 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(widget.title,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ),
                PricingInfoChip('${_picked.length} selected',
                    color: Theme.of(context).colorScheme.primary),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchCtl,
              autofocus: true,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search ${widget.kind.title.toLowerCase()}…',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C))),
              ),
            Expanded(
              child: _options.isEmpty && !_loading
                  ? Center(
                      child: Text(
                        _searchCtl.text.trim().isEmpty ? 'Nothing to pick.' : 'No match.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _options.length,
                      itemBuilder: (context, i) {
                        final o = _options[i];
                        final already = widget.alreadySelectedKeys.contains(o.key);
                        final picked = already || _picked.containsKey(o.key);
                        return CheckboxListTile(
                          dense: true,
                          value: picked,
                          onChanged: already
                              ? null
                              : (v) => setState(() {
                                    if (v == true) {
                                      _picked[o.key] = o;
                                    } else {
                                      _picked.remove(o.key);
                                    }
                                  }),
                          title: Text(o.label, style: const TextStyle(fontSize: 13.5)),
                          subtitle: Text(
                            [
                              if (o.subtitle.isNotEmpty) o.subtitle,
                              if (o.productIds.length > 1) '${o.productIds.length} products',
                              if (already) 'already added',
                            ].join(' · '),
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _picked.isEmpty
                        ? null
                        : () => Navigator.pop(context, _picked.values.toList()),
                    child: Text('Add ${_picked.isEmpty ? '' : _picked.length}'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Flattens picked items into the id lists the API expects.
List<int> pricingIdsOf(List<PricingGroupItem> items, PricingItemKind kind) {
  if (kind == PricingItemKind.product) {
    return {for (final i in items) ...(i.productIds.isNotEmpty ? i.productIds : [if (i.id != null) i.id!])}
        .toList();
  }
  return [for (final i in items) if (i.id != null) i.id!];
}

/// Centers page content at a readable width.
class PricingPageBody extends StatelessWidget {
  final Widget child;

  const PricingPageBody({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: child,
      ),
    );
  }
}
