import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/models/pricing_group.dart';
import '../../../services/pricing_group_service.dart';
import 'pricing_group_widgets.dart';

/// One dealer's own filter on one group.
///
/// By default the dealer gets everything in the group. Rows marked **Only**
/// limit the dealer to them; rows marked **Except** are skipped. The most
/// specific row wins: a brand row beats its product row, a product row beats
/// its category row. Only what the group covers is listed.

const pricingRuleOnly = 'only';
const pricingRuleExcept = 'except';

String _ruleKey(PricingItemKind kind, int id) => '${kind.apiName}:$id';

class _RowInfo {
  final String label;
  final String subtitle;
  final int? categoryId;
  final int? productId;
  final bool editable;

  const _RowInfo(this.label, this.subtitle, this.categoryId, this.productId, this.editable);
}

/// The dealer's Only / Except rows while editing.
class PricingRuleBook extends ChangeNotifier {
  final Map<String, String> _states = {};
  final Map<String, String> _original = {};
  final Map<String, _RowInfo> _info = {};

  void load(List<PricingLinkEntry> entries) {
    _states.clear();
    _original.clear();
    for (final e in entries) {
      final key = _ruleKey(e.kind, e.id);
      _states[key] = e.state;
      _original[key] = e.state;
      _info[key] = _RowInfo(e.label, e.subtitle, e.categoryId, e.productId, e.editable);
    }
    notifyListeners();
  }

  String? stateOf(PricingItemKind kind, int? id) => id == null ? null : _states[_ruleKey(kind, id)];

  String labelOf(PricingItemKind kind, int id) =>
      _info[_ruleKey(kind, id)]?.label ?? '${kind.apiName} #$id';

  bool get hasOnly => _states.values.contains(pricingRuleOnly);

  void remember(PricingItemKind kind, int id, String label, String subtitle,
      {int? categoryId, int? productId}) {
    final key = _ruleKey(kind, id);
    final known = _info[key];
    _info[key] = _RowInfo(
      label.isNotEmpty ? label : (known?.label ?? ''),
      subtitle.isNotEmpty ? subtitle : (known?.subtitle ?? ''),
      categoryId ?? known?.categoryId,
      productId ?? known?.productId,
      known?.editable ?? true,
    );
  }

  void set(PricingItemKind kind, Iterable<int> ids, String? state) {
    for (final id in ids) {
      final key = _ruleKey(kind, id);
      if (state == null) {
        _states.remove(key);
      } else {
        _states[key] = state;
      }
    }
    notifyListeners();
  }

  bool isChanged(PricingItemKind kind, int id) {
    final key = _ruleKey(kind, id);
    return _states[key] != _original[key];
  }

  bool get isDirty {
    if (_states.length != _original.length) return true;
    for (final e in _states.entries) {
      if (_original[e.key] != e.value) return true;
    }
    return false;
  }

  int count(PricingItemKind kind) => _states.keys.where((k) => k.startsWith('${kind.apiName}:')).length;

  int changedCount(PricingItemKind kind) => _rowsOf(kind, changedOnly: true).length;

  List<_RuleRow> _rowsOf(PricingItemKind kind, {bool changedOnly = false}) {
    final keys = <String>{..._states.keys, if (changedOnly) ..._original.keys}
        .where((k) => k.startsWith('${kind.apiName}:'));
    final out = <_RuleRow>[];
    for (final key in keys) {
      final id = int.tryParse(key.split(':').last);
      if (id == null) continue;
      if (changedOnly && !isChanged(kind, id)) continue;
      final info = _info[key];
      out.add(_RuleRow(
        kind: kind,
        ids: [id],
        label: info?.label ?? '${kind.apiName} #$id',
        subtitle: info?.subtitle ?? '',
        categoryId: info?.categoryId,
        productId: info?.productId,
        editable: info?.editable ?? true,
      ));
    }
    out.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return out;
  }

  /// The complete list the API expects: [{kind, id, state}].
  List<Map<String, dynamic>> toJson() => [
        for (final e in _states.entries)
          {'kind': e.key.split(':').first, 'id': int.parse(e.key.split(':').last), 'state': e.value},
      ];
}

class _RuleRow {
  final PricingItemKind kind;
  final List<int> ids; // a workspace admin's product row can stand for several products
  final String label;
  final String subtitle;
  final int? categoryId;
  final int? productId;
  final bool editable;

  const _RuleRow({
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

bool _isRow(PricingGroupItem i) => i.id != null || i.productIds.isNotEmpty;

_RuleRow _ruleRowFrom(PricingRuleBook book, PricingItemKind kind, PricingGroupItem item) {
  final ids = kind == PricingItemKind.product && item.productIds.isNotEmpty
      ? item.productIds
      : <int>[if (item.id != null) item.id!];
  for (final id in ids) {
    book.remember(kind, id, item.label, item.subtitle, categoryId: item.categoryId, productId: item.productId);
  }
  return _RuleRow(
    kind: kind,
    ids: ids,
    label: item.label,
    subtitle: item.subtitle,
    categoryId: item.categoryId,
    productId: item.productId,
  );
}

/// What one row resolves to (mirrors the server).
class _RuleResolved {
  final String? own;
  final String? inherited;
  final String? from;
  final bool included;

  const _RuleResolved({this.own, this.inherited, this.from, required this.included});
}

_RuleResolved _resolveRule(PricingRuleBook book, _RuleRow row) {
  final own = book.stateOf(row.kind, row.ids.first);
  final ancestors = <(PricingItemKind, int)>[
    if (row.kind == PricingItemKind.brand && row.productId != null) (PricingItemKind.product, row.productId!),
    if (row.kind != PricingItemKind.category && row.categoryId != null)
      (PricingItemKind.category, row.categoryId!),
  ];
  String? inherited, from;
  for (final (kind, id) in ancestors) {
    final st = book.stateOf(kind, id);
    if (st == null) continue;
    inherited = st;
    from = book.labelOf(kind, id);
    break;
  }
  final effective = own ?? inherited;
  return _RuleResolved(
    own: own,
    inherited: inherited,
    from: from,
    included: effective == null ? !book.hasOnly : effective == pricingRuleOnly,
  );
}

// ───────────────────────── grid ─────────────────────────

enum _Show { all, marked, changed }

class PricingRuleGrid extends StatefulWidget {
  final PricingRuleBook book;
  final int groupId;
  final List<PricingItemKind> kinds;
  final bool editable;

  const PricingRuleGrid({
    super.key,
    required this.book,
    required this.groupId,
    required this.kinds,
    required this.editable,
  });

  @override
  State<PricingRuleGrid> createState() => _PricingRuleGridState();
}

class _PricingRuleGridState extends State<PricingRuleGrid> {
  static const _pageSize = 50;

  final _searchCtl = TextEditingController();
  Timer? _debounce;
  late PricingItemKind _kind;
  _Show _show = _Show.all;

  final List<_RuleRow> _catalog = [];
  int _total = 0;
  bool _loading = false;
  String? _error;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _kind = widget.kinds.contains(PricingItemKind.product) ? PricingItemKind.product : widget.kinds.first;
    widget.book.addListener(_onBook);
    _reload();
  }

  @override
  void didUpdateWidget(covariant PricingRuleGrid old) {
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
        withinGroup: widget.groupId,
        limit: _pageSize,
        offset: _catalog.length,
      );
      if (!mounted || token != _token) return;
      setState(() {
        _catalog.addAll(page.items.where(_isRow).map((i) => _ruleRowFrom(widget.book, _kind, i)));
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

  List<_RuleRow> get _rows {
    if (_show == _Show.all) return _catalog;
    final q = _search.toLowerCase();
    return widget.book
        ._rowsOf(_kind, changedOnly: _show == _Show.changed)
        .where((r) => q.isEmpty || r.label.toLowerCase().contains(q) || r.subtitle.toLowerCase().contains(q))
        .toList();
  }

  int get _matchingCount => _show == _Show.all ? _total : _rows.length;

  Future<List<_RuleRow>?> _allMatching() async {
    if (_show != _Show.all) return _rows;
    if (_catalog.length >= _total) return List<_RuleRow>.from(_catalog);
    try {
      final page = await PricingGroupService.instance
          .options(kind: _kind, search: _search, withinGroup: widget.groupId, all: true);
      final rows = page.items.where(_isRow).map((i) => _ruleRowFrom(widget.book, _kind, i)).toList();
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

  Future<void> _bulk(String? state) async {
    final rows = await _allMatching();
    if (rows == null || !mounted) return;
    for (final r in rows.where((r) => r.editable)) {
      widget.book.set(r.kind, r.ids, state);
    }
    final what = switch (state) {
      pricingRuleOnly => 'Marked Only',
      pricingRuleExcept => 'Marked Except',
      _ => 'Cleared',
    };
    showPricingSnack(context, '$what: ${rows.length} ${_kind.title.toLowerCase()}. Save to apply.');
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final rows = _rows;
    final grey = Colors.grey.shade600;
    final marked = book.count(_kind);
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
                decoration: const InputDecoration(labelText: 'Show', border: OutlineInputBorder(), isDense: true),
                items: [for (final k in widget.kinds) DropdownMenuItem(value: k, child: Text(k.title))],
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
                  _Show.marked => 'Only / Except ($marked)',
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
                onSelected: (v) => _bulk(v == 'clear' ? null : v),
                itemBuilder: (_) => [
                  PopupMenuItem(value: pricingRuleOnly, child: Text('Only: all $_matchingCount')),
                  PopupMenuItem(value: pricingRuleExcept, child: Text('Except: all $_matchingCount')),
                  PopupMenuItem(value: 'clear', child: Text('Clear all $_matchingCount')),
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
            book.hasOnly
                ? 'This dealer gets ONLY the rows marked Only (and what is inside them), minus rows marked Except.'
                : 'This dealer gets everything in the group, minus rows marked Except. '
                    'Mark rows Only to limit the dealer to them.',
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
                  _Show.all => 'No ${_kind.title.toLowerCase()} in this group match.',
                  _Show.marked => 'No ${_kind.title.toLowerCase()} marked Only or Except.',
                  _Show.changed => 'Nothing changed here yet.',
                },
                style: TextStyle(color: grey),
              ),
            ),
          ),
        for (final r in rows)
          _ExpandableRule(key: ValueKey(r.key), row: r, book: book, groupId: widget.groupId, editable: widget.editable),
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

/// A row that opens its children (inside the group) when tapped.
class _ExpandableRule extends StatefulWidget {
  final _RuleRow row;
  final PricingRuleBook book;
  final int groupId;
  final bool editable;

  const _ExpandableRule({
    super.key,
    required this.row,
    required this.book,
    required this.groupId,
    required this.editable,
  });

  @override
  State<_ExpandableRule> createState() => _ExpandableRuleState();
}

class _ExpandableRuleState extends State<_ExpandableRule> {
  static const _pageSize = 50;

  bool _open = false;
  final List<_RuleRow> _children = [];
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
        withinGroup: widget.groupId,
        limit: _pageSize,
        offset: _children.length,
        categoryId: r.kind == PricingItemKind.category ? r.ids.first : null,
        productIds: r.kind == PricingItemKind.product ? r.ids : null,
      );
      if (!mounted) return;
      setState(() {
        _children.addAll(page.items.where(_isRow).map((i) => _ruleRowFrom(widget.book, kind, i)));
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RuleItemRow(
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
            decoration: BoxDecoration(border: Border(left: BorderSide(color: Colors.grey.shade300, width: 2))),
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
                    child: Text('No ${childKind.title.toLowerCase()} of this group inside.',
                        style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
                  ),
                for (final c in _children)
                  _ExpandableRule(
                    key: ValueKey(c.key),
                    row: c,
                    book: widget.book,
                    groupId: widget.groupId,
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

class _RuleItemRow extends StatelessWidget {
  final _RuleRow row;
  final PricingRuleBook book;
  final bool editable;
  final bool? expanded;
  final VoidCallback? onToggle;

  const _RuleItemRow({
    required this.row,
    required this.book,
    required this.editable,
    this.expanded,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final r = row;
    final res = _resolveRule(book, r);
    final changed = r.ids.any((id) => book.isChanged(r.kind, id));
    final grey = Colors.grey.shade600;
    const green = Color(0xFF1E7E34);
    const red = Color(0xFFB91C1C);
    const blue = Color(0xFF2563EB);

    final (chipText, chipColor) = switch ((res.own, res.inherited)) {
      (pricingRuleOnly, _) => ('Only', green),
      (pricingRuleExcept, _) => ('Except', red),
      (null, pricingRuleOnly) => ('Via ${res.from}', blue),
      (null, pricingRuleExcept) => ('Except via ${res.from}', red),
      _ => res.included ? ('In group', green) : ('Not included', grey),
    };

    final menu = <PopupMenuEntry<String>>[
      if (res.own != pricingRuleOnly)
        const PopupMenuItem(value: pricingRuleOnly, child: Text('Only (limit the dealer to it)')),
      if (res.own != pricingRuleExcept)
        const PopupMenuItem(value: pricingRuleExcept, child: Text('Except (skip it)')),
      if (res.own != null)
        PopupMenuItem(
          value: 'clear',
          child: Text(res.inherited != null ? 'Clear (follow ${res.from})' : 'Clear'),
        ),
    ];

    final stateChip = PopupMenuButton<String>(
      enabled: editable,
      tooltip: 'Change',
      onSelected: (v) => book.set(r.kind, r.ids, v == 'clear' ? null : v),
      itemBuilder: (_) => menu,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: chipColor.withValues(alpha: res.own != null ? .12 : .05),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: chipColor.withValues(alpha: .3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Text(chipText,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: chipColor, fontWeight: FontWeight.w700)),
          ),
          if (editable) Icon(Icons.arrow_drop_down, size: 16, color: chipColor),
        ]),
      ),
    );

    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(r.label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
              color: res.included ? null : grey,
              decoration: res.included ? null : TextDecoration.lineThrough,
            )),
        if (r.subtitle.isNotEmpty)
          Text(r.subtitle, style: TextStyle(fontSize: 12, color: grey), overflow: TextOverflow.ellipsis),
        if (r.ids.length > 1) Text('${r.ids.length} products', style: TextStyle(fontSize: 11.5, color: grey)),
      ],
    );
    final open = expanded;
    final title = open == null
        ? texts
        : InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tooltip(
                  message: open ? 'Hide' : 'Show its ${r.kind == PricingItemKind.category ? 'products' : 'brands'}',
                  child: Icon(open ? Icons.expand_more : Icons.chevron_right, size: 20),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: title),
          const SizedBox(width: 8),
          stateChip,
        ],
      ),
    );
  }
}
