import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/models/pricing_group.dart';
import '../../../services/pricing_group_service.dart';
import 'pricing_group_widgets.dart';

/// Per-item percentages of a pricing group.
///
/// Pick a type (category / product / brand), search, and set a dealer % and a
/// selling % on any row. The most specific row wins: a brand row beats its
/// product row, a product row beats its category row. A blank % is taken from
/// the row above it (shown greyed out as a hint).

// ───────────────────────── local state ─────────────────────────

/// One item's settings while editing.
class PricingItemDraft {
  final bool excluded;
  final String pp;
  final String spp;

  const PricingItemDraft({this.excluded = false, this.pp = '', this.spp = ''});

  PricingItemDraft copyWith({bool? excluded, String? pp, String? spp}) => PricingItemDraft(
        excluded: excluded ?? this.excluded,
        pp: pp ?? this.pp,
        spp: spp ?? this.spp,
      );

  @override
  bool operator ==(Object other) =>
      other is PricingItemDraft && other.excluded == excluded && other.pp == pp && other.spp == spp;

  @override
  int get hashCode => Object.hash(excluded, pp, spp);
}

String pricingDraftKey(PricingItemKind kind, int id) => '${kind.apiName}:$id';

/// Every item of the group being edited, plus labels for showing where an
/// inherited % comes from.
class PricingDraftBook extends ChangeNotifier {
  final Map<String, PricingItemDraft> _items = {};
  final Map<String, PricingItemDraft> _original = {};
  final Map<String, String> _labels = {};
  final Map<String, PricingGroupEntry> _entries = {};

  void load(List<PricingGroupEntry> entries) {
    _items.clear();
    _original.clear();
    _entries.clear();
    for (final e in entries) {
      final key = pricingDraftKey(e.kind, e.id);
      final d = PricingItemDraft(
        excluded: e.excluded,
        pp: e.profitPercentage ?? '',
        spp: e.sellingProfitPercentage ?? '',
      );
      _items[key] = d;
      _original[key] = d;
      _labels[key] = e.label;
      _entries[key] = e;
    }
    notifyListeners();
  }

  PricingItemDraft? get(PricingItemKind kind, int? id) =>
      id == null ? null : _items[pricingDraftKey(kind, id)];

  String labelOf(PricingItemKind kind, int id) =>
      _labels[pricingDraftKey(kind, id)] ?? '${kind.apiName} #$id';

  void rememberLabel(PricingItemKind kind, int id, String label) {
    if (label.isNotEmpty) _labels[pricingDraftKey(kind, id)] = label;
  }

  bool isEditable(PricingItemKind kind, int id) =>
      _entries[pricingDraftKey(kind, id)]?.editable ?? true;

  void set(PricingItemKind kind, Iterable<int> ids, PricingItemDraft? draft) {
    for (final id in ids) {
      final key = pricingDraftKey(kind, id);
      if (draft == null) {
        _items.remove(key);
      } else {
        _items[key] = draft;
      }
    }
    notifyListeners();
  }

  /// Changes one % of rows, adding the rows to the group if needed.
  void setPercent(PricingItemKind kind, Iterable<int> ids, {String? pp, String? spp}) {
    for (final id in ids) {
      final key = pricingDraftKey(kind, id);
      final cur = _items[key] ?? const PricingItemDraft();
      _items[key] = cur.copyWith(excluded: false, pp: pp ?? cur.pp, spp: spp ?? cur.spp);
    }
    notifyListeners();
  }

  bool isChanged(PricingItemKind kind, int id) {
    final key = pricingDraftKey(kind, id);
    return _items[key] != _original[key];
  }

  bool get isDirty {
    if (_items.length != _original.length) return true;
    for (final e in _items.entries) {
      if (_original[e.key] != e.value) return true;
    }
    return false;
  }

  /// Rows of one kind that have their own settings (or were changed).
  List<PricingGroupEntry> rowsOf(PricingItemKind kind, {bool changedOnly = false}) {
    final keys = <String>{
      ..._items.keys,
      if (changedOnly) ..._original.keys,
    }.where((k) => k.startsWith('${kind.apiName}:'));
    final out = <PricingGroupEntry>[];
    for (final key in keys) {
      final id = int.tryParse(key.split(':').last);
      if (id == null) continue;
      if (changedOnly && !isChanged(kind, id)) continue;
      final known = _entries[key];
      out.add(PricingGroupEntry(
        kind: kind,
        id: id,
        label: _labels[key] ?? known?.label ?? '${kind.apiName} #$id',
        subtitle: known?.subtitle ?? '',
        categoryId: known?.categoryId ?? _parents[key]?.$1,
        productId: known?.productId ?? _parents[key]?.$2,
        editable: known?.editable ?? true,
      ));
    }
    out.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return out;
  }

  /// Parents of rows first seen in the catalog (not in the saved group).
  final Map<String, (int?, int?)> _parents = {};

  void rememberRow(PricingItemKind kind, int id, String label, String subtitle,
      {int? categoryId, int? productId}) {
    rememberLabel(kind, id, label);
    _parents[pricingDraftKey(kind, id)] = (categoryId, productId);
    final key = pricingDraftKey(kind, id);
    if (!_entries.containsKey(key)) {
      _entries[key] = PricingGroupEntry(
        kind: kind,
        id: id,
        label: label,
        subtitle: subtitle,
        categoryId: categoryId,
        productId: productId,
      );
    }
  }

  int count(PricingItemKind kind, {bool? excluded}) => _items.entries
      .where((e) =>
          e.key.startsWith('${kind.apiName}:') && (excluded == null || e.value.excluded == excluded))
      .length;

  int changedCount(PricingItemKind kind) => rowsOf(kind, changedOnly: true).length;

  /// First problem, or null when everything can be sent.
  String? validate() {
    for (final e in _items.entries) {
      if (e.value.excluded) continue;
      for (final v in [e.value.pp, e.value.spp]) {
        final s = v.trim();
        if (s.isEmpty) continue;
        final n = double.tryParse(s);
        if (n == null || n <= 0) {
          return '"${_labels[e.key] ?? e.key}": percentages are multipliers like 1.05.';
        }
      }
    }
    return null;
  }

  List<Map<String, dynamic>> toJson() => [
        for (final e in _items.entries)
          {
            'kind': e.key.split(':').first,
            'id': int.parse(e.key.split(':').last),
            'excluded': e.value.excluded,
            'profit_percentage': e.value.excluded || e.value.pp.trim().isEmpty ? null : e.value.pp.trim(),
            'selling_profit_percentage':
                e.value.excluded || e.value.spp.trim().isEmpty ? null : e.value.spp.trim(),
          },
      ];
}

// ───────────────────────── resolution (mirrors the server) ─────────────────────────

enum _RowState { inGroup, excluded, covered, none }

class _Resolved {
  final _RowState state;
  final PricingItemDraft? own;
  final String? coveredBy;
  final String? inheritedPp;
  final String? inheritedSpp;
  final String? ppFrom;
  final String? sppFrom;
  final bool canExclude;

  const _Resolved({
    required this.state,
    this.own,
    this.coveredBy,
    this.inheritedPp,
    this.inheritedSpp,
    this.ppFrom,
    this.sppFrom,
    this.canExclude = false,
  });
}

class _GridRow {
  final PricingItemKind kind;
  final List<int> ids; // a workspace admin's product row can stand for several products
  final String label;
  final String subtitle;
  final int? categoryId;
  final int? productId;
  final bool editable;

  const _GridRow({
    required this.kind,
    required this.ids,
    required this.label,
    required this.subtitle,
    this.categoryId,
    this.productId,
    this.editable = true,
  });

  String get key => '${kind.apiName}:${ids.join(',')}';
}

_Resolved _resolve(PricingDraftBook book, _GridRow row) {
  final own = book.get(row.kind, row.ids.first);
  final ancestors = <(PricingItemKind, int)>[
    if (row.kind == PricingItemKind.brand && row.productId != null)
      (PricingItemKind.product, row.productId!),
    if (row.kind != PricingItemKind.category && row.categoryId != null)
      (PricingItemKind.category, row.categoryId!),
  ];
  String? coveredBy;
  var covered = false;
  for (final (kind, id) in ancestors) {
    final d = book.get(kind, id);
    if (d == null) continue;
    covered = !d.excluded;
    if (covered) coveredBy = book.labelOf(kind, id);
    break;
  }
  String? pp, spp, ppFrom, sppFrom;
  for (final (kind, id) in ancestors) {
    final d = book.get(kind, id);
    if (d == null || d.excluded) continue;
    if (pp == null && d.pp.trim().isNotEmpty) {
      pp = d.pp.trim();
      ppFrom = book.labelOf(kind, id);
    }
    if (spp == null && d.spp.trim().isNotEmpty) {
      spp = d.spp.trim();
      sppFrom = book.labelOf(kind, id);
    }
  }
  final state = own != null
      ? (own.excluded ? _RowState.excluded : _RowState.inGroup)
      : (covered ? _RowState.covered : _RowState.none);
  return _Resolved(
    state: state,
    own: own,
    coveredBy: coveredBy,
    inheritedPp: pp,
    inheritedSpp: spp,
    ppFrom: ppFrom,
    sppFrom: sppFrom,
    canExclude: covered,
  );
}

bool _isRow(PricingGroupItem i) => i.id != null || i.productIds.isNotEmpty;

_GridRow _gridRowFrom(PricingDraftBook book, PricingItemKind kind, PricingGroupItem item) {
  final ids = kind == PricingItemKind.product && item.productIds.isNotEmpty
      ? item.productIds
      : <int>[if (item.id != null) item.id!];
  for (final id in ids) {
    book.rememberRow(kind, id, item.label, item.subtitle,
        categoryId: item.categoryId, productId: item.productId);
  }
  return _GridRow(
    kind: kind,
    ids: ids,
    label: item.label,
    subtitle: item.subtitle,
    categoryId: item.categoryId,
    productId: item.productId,
  );
}

// ───────────────────────── grid ─────────────────────────

enum _Show { all, inGroup, changed }

class PricingItemGrid extends StatefulWidget {
  final PricingDraftBook book;
  final List<PricingItemKind> kinds;
  final bool editable;

  const PricingItemGrid({
    super.key,
    required this.book,
    required this.kinds,
    required this.editable,
  });

  @override
  State<PricingItemGrid> createState() => _PricingItemGridState();
}

class _PricingItemGridState extends State<PricingItemGrid> {
  static const _pageSize = 50;

  final _searchCtl = TextEditingController();
  Timer? _debounce;
  late PricingItemKind _kind;
  _Show _show = _Show.all;

  final List<_GridRow> _catalog = [];
  int _total = 0;
  bool _loading = false;
  String? _error;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _kind = widget.kinds.contains(PricingItemKind.product)
        ? PricingItemKind.product
        : widget.kinds.first;
    widget.book.addListener(_onBook);
    _reload();
  }

  @override
  void didUpdateWidget(covariant PricingItemGrid old) {
    super.didUpdateWidget(old);
    if (old.book != widget.book) {
      old.book.removeListener(_onBook);
      widget.book.addListener(_onBook);
    }
  }

  @override
  void dispose() {
    widget.book.removeListener(_onBook);
    _debounce?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  void _onBook() {
    if (mounted) setState(() {});
  }

  String get _search => _searchCtl.text.trim();

  _GridRow _fromCatalog(PricingGroupItem item) => _gridRowFrom(widget.book, _kind, item);

  Future<void> _reload() async {
    _catalog.clear();
    _total = 0;
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_show != _Show.all) {
      setState(() {});
      return;
    }
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await PricingGroupService.instance.options(
        kind: _kind,
        search: _search,
        limit: _pageSize,
        offset: _catalog.length,
      );
      if (!mounted || token != _token) return;
      setState(() {
        _catalog.addAll(page.items.where(_isRow).map(_fromCatalog));
        _total = page.total;
      });
    } catch (e) {
      if (mounted && token == _token) setState(() => _error = friendlyPricingError(e));
    } finally {
      if (mounted && token == _token) setState(() => _loading = false);
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _reload);
    setState(() {});
  }

  bool _matches(PricingGroupEntry e) {
    final q = _search.toLowerCase();
    if (q.isEmpty) return true;
    return e.label.toLowerCase().contains(q) || e.subtitle.toLowerCase().contains(q);
  }

  List<_GridRow> get _rows {
    if (_show == _Show.all) return _catalog;
    return widget.book
        .rowsOf(_kind, changedOnly: _show == _Show.changed)
        .where(_matches)
        .map((e) => _GridRow(
              kind: e.kind,
              ids: [e.id],
              label: e.label,
              subtitle: e.subtitle,
              categoryId: e.categoryId,
              productId: e.productId,
              editable: e.editable,
            ))
        .toList();
  }

  // ── bulk ──

  Future<List<_GridRow>?> _allMatching() async {
    if (_show != _Show.all) return _rows;
    if (_catalog.length >= _total) return List<_GridRow>.from(_catalog);
    try {
      final page = await PricingGroupService.instance.options(kind: _kind, search: _search, all: true);
      final rows = page.items.where(_isRow).map(_fromCatalog).toList();
      if (page.total > rows.length && mounted) {
        showPricingSnack(context,
            'Only the first ${rows.length} of ${page.total} matches were changed - narrow the search for the rest.');
      }
      return rows;
    } catch (e) {
      if (mounted) await showPricingError(context, e);
      return null;
    }
  }

  int get _matchingCount => _show == _Show.all ? _total : _rows.length;

  Future<void> _bulkSetPercent() async {
    final count = _matchingCount;
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) => _BulkPercentDialog(count: count, kindTitle: _kind.title.toLowerCase()),
    );
    if (result == null || !mounted) return;
    final rows = await _allMatching();
    if (rows == null || !mounted) return;
    final (pp, spp) = result;
    for (final r in rows.where((r) => r.editable)) {
      widget.book.setPercent(r.kind, r.ids,
          pp: pp.isEmpty ? null : pp, spp: spp.isEmpty ? null : spp);
    }
    showPricingSnack(context, 'Set on ${rows.length} ${_kind.title.toLowerCase()}. Save to apply.');
  }

  Future<void> _bulkRemove() async {
    final count = _matchingCount;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove $count ${_kind.title.toLowerCase()} from the group?'),
        content: const Text('Their own percentages and exclusions are cleared. '
            'Rows inside a category or product that is still in the group keep following it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final rows = await _allMatching();
    if (rows == null || !mounted) return;
    for (final r in rows.where((r) => r.editable)) {
      widget.book.set(r.kind, r.ids, null);
    }
  }

  // ── build ──

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final rows = _rows;
    final grey = Colors.grey.shade600;
    final inGroup = book.count(_kind);
    final changed = book.changedCount(_kind);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<PricingItemKind>(
                initialValue: _kind,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'Show',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final k in widget.kinds) DropdownMenuItem(value: k, child: Text(k.title)),
                ],
                onChanged: (k) {
                  if (k == null || k == _kind) return;
                  setState(() => _kind = k);
                  _reload();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchCtl,
                onChanged: _onSearch,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search ${_kind.title.toLowerCase()}',
                  border: const OutlineInputBorder(),
                  suffixIcon: _searchCtl.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _searchCtl.clear();
                            _reload();
                          },
                        ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final s in _Show.values)
              ChoiceChip(
                label: Text(switch (s) {
                  _Show.all => 'All',
                  _Show.inGroup => 'In group ($inGroup)',
                  _Show.changed => 'Changed ($changed)',
                }),
                selected: _show == s,
                onSelected: (_) {
                  setState(() => _show = s);
                  if (s == _Show.all && _catalog.isEmpty) _reload();
                },
              ),
            if (widget.editable && _matchingCount > 0)
              PopupMenuButton<String>(
                tooltip: 'Change all matching rows',
                onSelected: (v) => v == 'pct' ? _bulkSetPercent() : _bulkRemove(),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'pct', child: Text('Set % for all $_matchingCount')),
                  PopupMenuItem(value: 'remove', child: Text('Remove all $_matchingCount from group')),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.playlist_add_check, size: 18),
                    const SizedBox(width: 4),
                    Text('All $_matchingCount…', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
          child: Text(
            'Type a % on any row to add it. Blank = taken from the row above it (shown in grey). '
            'The most specific row wins: brand › product › category.',
            style: TextStyle(fontSize: 12, color: grey),
          ),
        ),
        if (_error != null)
          Card(
            color: const Color(0xFFFEF2F2),
            child: ListTile(
              dense: true,
              title: Text(_error!),
              trailing: TextButton(onPressed: _reload, child: const Text('Retry')),
            ),
          ),
        if (_loading && rows.isEmpty) const LinearProgressIndicator(minHeight: 2),
        if (!_loading && rows.isEmpty && _error == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                switch (_show) {
                  _Show.all => 'No ${_kind.title.toLowerCase()} match.',
                  _Show.inGroup => 'No ${_kind.title.toLowerCase()} in the group yet.',
                  _Show.changed => 'Nothing changed here yet.',
                },
                style: TextStyle(color: grey),
              ),
            ),
          ),
        for (final r in rows)
          _ExpandableItem(
            key: ValueKey(r.key),
            row: r,
            book: book,
            editable: widget.editable,
          ),
        if (_show == _Show.all && _catalog.length < _total)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: OutlinedButton.icon(
                onPressed: _loading ? null : _loadMore,
                icon: _loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.expand_more),
                label: Text('Show more (${_catalog.length} of $_total)'),
              ),
            ),
          ),
      ],
    );
  }
}

// ───────────────────────── drill-down ─────────────────────────

/// A row that opens its children when tapped: a category shows its products,
/// a product shows its brands. Children are rows like any other.
class _ExpandableItem extends StatefulWidget {
  final _GridRow row;
  final PricingDraftBook book;
  final bool editable;

  const _ExpandableItem({super.key, required this.row, required this.book, required this.editable});

  @override
  State<_ExpandableItem> createState() => _ExpandableItemState();
}

class _ExpandableItemState extends State<_ExpandableItem> {
  static const _pageSize = 50;

  bool _open = false;
  final List<_GridRow> _children = [];
  int _total = 0;
  bool _loading = false;
  bool _loaded = false;
  String? _error;

  PricingItemKind? get _childKind => switch (widget.row.kind) {
        PricingItemKind.category => PricingItemKind.product,
        PricingItemKind.product => PricingItemKind.brand,
        PricingItemKind.brand => null,
      };

  void _toggle() {
    setState(() => _open = !_open);
    if (_open && !_loaded) _loadMore();
  }

  Future<void> _loadMore() async {
    final kind = _childKind;
    if (kind == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = widget.row;
      final page = await PricingGroupService.instance.options(
        kind: kind,
        limit: _pageSize,
        offset: _children.length,
        categoryId: r.kind == PricingItemKind.category ? r.ids.first : null,
        productIds: r.kind == PricingItemKind.product ? r.ids : null,
      );
      if (!mounted) return;
      setState(() {
        _children.addAll(page.items.where(_isRow).map((i) => _gridRowFrom(widget.book, kind, i)));
        _total = page.total;
        _loaded = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyPricingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final childKind = _childKind;
    final grey = Colors.grey.shade600;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ItemRow(
          row: r,
          book: widget.book,
          editable: widget.editable && r.editable,
          expanded: childKind == null ? null : _open,
          onToggle: childKind == null ? null : _toggle,
        ),
        if (_open && childKind != null)
          Container(
            margin: const EdgeInsets.only(left: 14, bottom: 6),
            padding: const EdgeInsets.only(left: 10),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: Colors.grey.shade300, width: 2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_loading && _children.isEmpty) const LinearProgressIndicator(minHeight: 2),
                if (_error != null)
                  ListTile(
                    dense: true,
                    title: Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C))),
                    trailing: TextButton(onPressed: _loadMore, child: const Text('Retry')),
                  ),
                if (_loaded && _children.isEmpty && _error == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('No active ${childKind.title.toLowerCase()} inside.',
                        style: TextStyle(fontSize: 12.5, color: grey)),
                  ),
                for (final c in _children)
                  _ExpandableItem(
                    key: ValueKey(c.key),
                    row: c,
                    book: widget.book,
                    editable: widget.editable,
                  ),
                if (_children.length < _total)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _loading ? null : _loadMore,
                      icon: const Icon(Icons.expand_more, size: 18),
                      label: Text('Show more (${_children.length} of $_total)'),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ───────────────────────── one row ─────────────────────────

class _ItemRow extends StatefulWidget {
  final _GridRow row;
  final PricingDraftBook book;
  final bool editable;

  /// null = no children (brand); otherwise whether the children are shown.
  final bool? expanded;
  final VoidCallback? onToggle;

  const _ItemRow({
    required this.row,
    required this.book,
    required this.editable,
    this.expanded,
    this.onToggle,
  });

  @override
  State<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends State<_ItemRow> {
  late final TextEditingController _pp;
  late final TextEditingController _spp;

  @override
  void initState() {
    super.initState();
    final own = widget.book.get(widget.row.kind, widget.row.ids.first);
    _pp = TextEditingController(text: own?.excluded == true ? '' : own?.pp ?? '');
    _spp = TextEditingController(text: own?.excluded == true ? '' : own?.spp ?? '');
  }

  @override
  void dispose() {
    _pp.dispose();
    _spp.dispose();
    super.dispose();
  }

  void _syncControllers(PricingItemDraft? own) {
    final pp = own == null || own.excluded ? '' : own.pp;
    final spp = own == null || own.excluded ? '' : own.spp;
    if (_pp.text != pp) _pp.text = pp;
    if (_spp.text != spp) _spp.text = spp;
  }

  void _onPct({String? pp, String? spp}) {
    widget.book.setPercent(widget.row.kind, widget.row.ids, pp: pp, spp: spp);
  }

  void _setState(String action) {
    final r = widget.row;
    final own = widget.book.get(r.kind, r.ids.first);
    switch (action) {
      case 'add':
        widget.book.set(r.kind, r.ids, const PricingItemDraft());
      case 'include':
        widget.book.set(r.kind, r.ids, (own ?? const PricingItemDraft()).copyWith(excluded: false));
      case 'exclude':
        widget.book.set(r.kind, r.ids, const PricingItemDraft(excluded: true));
      case 'remove':
        widget.book.set(r.kind, r.ids, null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final res = _resolve(widget.book, r);
    _syncControllers(res.own);
    final changed = r.ids.any((id) => widget.book.isChanged(r.kind, id));
    final grey = Colors.grey.shade600;

    final (chipText, chipColor) = switch (res.state) {
      _RowState.inGroup => ('In group', const Color(0xFF1E7E34)),
      _RowState.excluded => ('Excluded', const Color(0xFFB91C1C)),
      _RowState.covered => ('Via ${res.coveredBy}', const Color(0xFF2563EB)),
      _RowState.none => ('Not in group', Colors.grey.shade600),
    };

    final menu = <PopupMenuEntry<String>>[
      if (res.state == _RowState.none) const PopupMenuItem(value: 'add', child: Text('Add to group')),
      if (res.state == _RowState.excluded) const PopupMenuItem(value: 'include', child: Text('Include again')),
      if (res.canExclude && res.state != _RowState.excluded)
        PopupMenuItem(value: 'exclude', child: Text('Exclude (skip it in ${res.coveredBy})')),
      if (res.own != null)
        PopupMenuItem(
          value: 'remove',
          child: Text(res.canExclude ? 'Clear (follow ${res.coveredBy})' : 'Remove from group'),
        ),
    ];

    final stateChip = PopupMenuButton<String>(
      enabled: widget.editable && menu.isNotEmpty,
      tooltip: 'Change',
      onSelected: _setState,
      itemBuilder: (_) => menu,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: chipColor.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: chipColor.withValues(alpha: .3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(chipText,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: chipColor, fontWeight: FontWeight.w700)),
          ),
          if (widget.editable && menu.isNotEmpty) Icon(Icons.arrow_drop_down, size: 16, color: chipColor),
        ]),
      ),
    );

    final excluded = res.state == _RowState.excluded;
    Widget pctField(String label, TextEditingController ctl, String? inherited, String? from, bool dealer) {
      return TextField(
        controller: ctl,
        enabled: widget.editable && !excluded,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (v) => dealer ? _onPct(pp: v) : _onPct(spp: v),
        style: const TextStyle(fontSize: 13.5),
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          hintText: excluded ? '—' : (inherited ?? 'keep'),
          helperText: !excluded && ctl.text.isEmpty && from != null ? 'from $from' : null,
          helperMaxLines: 1,
          border: const OutlineInputBorder(),
        ),
      );
    }

    final fields = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: pctField('Dealer %', _pp, res.inheritedPp, res.ppFrom, true)),
        const SizedBox(width: 8),
        Expanded(child: pctField('Selling %', _spp, res.inheritedSpp, res.sppFrom, false)),
      ],
    );

    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(r.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
        if (r.subtitle.isNotEmpty)
          Text(r.subtitle, style: TextStyle(fontSize: 12, color: grey), overflow: TextOverflow.ellipsis),
        if (r.ids.length > 1)
          Text('${r.ids.length} products', style: TextStyle(fontSize: 11.5, color: grey)),
      ],
    );
    final expanded = widget.expanded;
    final title = expanded == null
        ? texts
        : InkWell(
            onTap: widget.onToggle,
            borderRadius: BorderRadius.circular(6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tooltip(
                  message: expanded
                      ? 'Hide'
                      : 'Show its ${r.kind == PricingItemKind.category ? 'products' : 'brands'}',
                  child: Icon(expanded ? Icons.expand_more : Icons.chevron_right, size: 20),
                ),
                const SizedBox(width: 4),
                Expanded(child: texts),
              ],
            ),
          );

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: changed ? const Color(0xFFFFFBEB) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: changed ? const Color(0xFFF59E0B) : Colors.grey.shade300),
      ),
      child: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth >= 640) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: title),
              const SizedBox(width: 8),
              Padding(padding: const EdgeInsets.only(top: 6), child: stateChip),
              const SizedBox(width: 10),
              SizedBox(width: 280, child: fields),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: title),
                const SizedBox(width: 8),
                stateChip,
              ],
            ),
            const SizedBox(height: 8),
            fields,
          ],
        );
      }),
    );
  }
}

class _BulkPercentDialog extends StatefulWidget {
  final int count;
  final String kindTitle;

  const _BulkPercentDialog({required this.count, required this.kindTitle});

  @override
  State<_BulkPercentDialog> createState() => _BulkPercentDialogState();
}

class _BulkPercentDialogState extends State<_BulkPercentDialog> {
  final _pp = TextEditingController();
  final _spp = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pp.dispose();
    _spp.dispose();
    super.dispose();
  }

  void _submit() {
    final pp = _pp.text.trim();
    final spp = _spp.text.trim();
    if (pp.isEmpty && spp.isEmpty) {
      setState(() => _error = 'Enter at least one percentage.');
      return;
    }
    for (final v in [pp, spp]) {
      if (v.isEmpty) continue;
      final n = double.tryParse(v);
      if (n == null || n <= 0) {
        setState(() => _error = 'Percentages are multipliers like 1.05.');
        return;
      }
    }
    Navigator.pop(context, (pp, spp));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Set % for ${widget.count} ${widget.kindTitle}'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _pp,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Dealer %', hintText: 'blank = keep', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _spp,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                      labelText: 'Selling %', hintText: 'blank = keep', border: OutlineInputBorder()),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Text('Rows not in the group yet are added. Multipliers: 1.05 = +5%.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 12.5)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Apply')),
      ],
    );
  }
}
