import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/models/pricing_group.dart';
import '../../../services/pricing_group_service.dart';
import 'pricing_group_widgets.dart';

/// One dealer x every group, item by item (read-only): which group prices
/// what for this dealer, and what is left to be priced by hand.

const _itemW = 260.0;
const _typeW = 78.0;
const _groupW = 96.0;
const _pctW = 130.0;

const _green = Color(0xFF1E7E34);
const _blue = Color(0xFF2563EB);
const _amber = Color(0xFFB45309);

PricingItemKind? _childKindOf(PricingItemKind k) => switch (k) {
      PricingItemKind.category => PricingItemKind.product,
      PricingItemKind.product => PricingItemKind.brand,
      PricingItemKind.brand => null,
    };

class PricingOverviewGrid extends StatefulWidget {
  final int userId;

  const PricingOverviewGrid({super.key, required this.userId});

  @override
  State<PricingOverviewGrid> createState() => _PricingOverviewGridState();
}

class _PricingOverviewGridState extends State<PricingOverviewGrid> {
  static const _pageSize = 50;

  final _searchCtl = TextEditingController();
  Timer? _debounce;
  String _type = 'all';
  bool _unpricedOnly = false;
  bool _canUseCategories = false;

  List<PricingOverviewGroup> _groups = const [];
  final List<PricingOverviewRow> _rows = [];
  int _total = 0;
  bool _loading = false;
  String? _error;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    _rows.clear();
    _total = 0;
    await _loadMore();
  }

  Future<void> _loadMore() async {
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await PricingGroupService.instance.overview(
        widget.userId,
        type: _type,
        search: _searchCtl.text,
        unpricedOnly: _unpricedOnly,
        limit: _pageSize,
        offset: _rows.length,
      );
      if (!mounted || token != _token) return;
      setState(() {
        _groups = page.groups;
        _canUseCategories = page.canUseCategories;
        _rows.addAll(page.rows);
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

  double get _tableWidth => _itemW + _typeW + _groupW * _groups.length + _pctW;

  @override
  Widget build(BuildContext context) {
    final grey = Colors.grey.shade600;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 140,
              child: DropdownButtonFormField<String>(
                initialValue: _type,
                isDense: true,
                decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder(), isDense: true),
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('All types')),
                  if (_canUseCategories) const DropdownMenuItem(value: 'category', child: Text('Categories')),
                  const DropdownMenuItem(value: 'product', child: Text('Products')),
                  const DropdownMenuItem(value: 'brand', child: Text('Brands')),
                ],
                onChanged: (v) {
                  if (v == null || v == _type) return;
                  setState(() => _type = v);
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
                  hintText: 'Search items',
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
          children: [
            ChoiceChip(
              label: const Text('All'),
              selected: !_unpricedOnly,
              onSelected: (_) {
                if (!_unpricedOnly) return;
                setState(() => _unpricedOnly = false);
                _reload();
              },
            ),
            ChoiceChip(
              label: const Text('Not in any group'),
              selected: _unpricedOnly,
              onSelected: (_) {
                if (_unpricedOnly) return;
                setState(() => _unpricedOnly = true);
                _reload();
              },
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
          child: Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _legend(const Icon(Icons.check_circle, size: 15, color: _green), 'priced by this group'),
              _legend(const Text('2/5', style: TextStyle(fontSize: 12, color: _blue, fontWeight: FontWeight.w800)),
                  'some of its brands'),
              _legend(Icon(Icons.radio_button_unchecked, size: 14, color: grey),
                  'in the group, not for this dealer (off / Except / outside Only)'),
            ],
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
        if (_loading && _rows.isEmpty) const LinearProgressIndicator(minHeight: 2),
        if (!_loading && _rows.isEmpty && _error == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(_unpricedOnly ? 'Every item here is priced by a group.' : 'No item matches.',
                  style: TextStyle(color: grey)),
            ),
          ),
        if (_rows.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(10),
              color: Colors.white,
            ),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _tableWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(groups: _groups),
                    for (final r in _rows)
                      _OverviewRowTile(
                        key: ValueKey('${r.kind.apiName}:${r.item.key}'),
                        row: r,
                        groups: _groups,
                        userId: widget.userId,
                        unpricedOnly: _unpricedOnly,
                        depth: 0,
                      ),
                  ],
                ),
              ),
            ),
          ),
        if (_rows.length < _total)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: OutlinedButton.icon(
                onPressed: _loading ? null : _loadMore,
                icon: _loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.expand_more),
                label: Text('Show more (${_rows.length} of $_total)'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _legend(Widget mark, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
        mark,
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700)),
      ]);
}

class _Header extends StatelessWidget {
  final List<PricingOverviewGroup> groups;

  const _Header({required this.groups});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 12, fontWeight: FontWeight.w800);
    return Container(
      color: Colors.grey.shade100,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const SizedBox(
              width: _itemW, child: Padding(padding: EdgeInsets.only(left: 10), child: Text('Item', style: style))),
          const SizedBox(width: _typeW, child: Text('Type', style: style)),
          for (final g in groups)
            SizedBox(
              width: _groupW,
              child: Tooltip(
                message:
                    g.active ? 'On for this dealer' : (g.linked ? 'Off for this dealer' : 'Not linked to this dealer'),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.circle, size: 8, color: g.active ? _green : Colors.grey.shade400),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(g.name,
                          overflow: TextOverflow.ellipsis,
                          style: style.copyWith(color: g.active ? null : Colors.grey.shade600)),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(width: _pctW, child: Text('Dealer / Selling %', style: style)),
        ],
      ),
    );
  }
}

/// One row; tapping a category / product opens its children below it.
class _OverviewRowTile extends StatefulWidget {
  final PricingOverviewRow row;
  final List<PricingOverviewGroup> groups;
  final int userId;
  final bool unpricedOnly;
  final int depth;

  const _OverviewRowTile({
    super.key,
    required this.row,
    required this.groups,
    required this.userId,
    required this.unpricedOnly,
    required this.depth,
  });

  @override
  State<_OverviewRowTile> createState() => _OverviewRowTileState();
}

class _OverviewRowTileState extends State<_OverviewRowTile> {
  static const _pageSize = 50;

  bool _open = false;
  final List<PricingOverviewRow> _children = [];
  int _total = 0;
  bool _loading = false;
  bool _loaded = false;
  String? _error;

  void _toggle() {
    setState(() => _open = !_open);
    if (_open && !_loaded) _loadMore();
  }

  Future<void> _loadMore() async {
    final kind = _childKindOf(widget.row.kind);
    if (kind == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final item = widget.row.item;
      final page = await PricingGroupService.instance.overview(
        widget.userId,
        type: kind.apiName,
        unpricedOnly: widget.unpricedOnly,
        limit: _pageSize,
        offset: _children.length,
        categoryId: widget.row.kind == PricingItemKind.category ? item.id : null,
        productIds: widget.row.kind == PricingItemKind.product
            ? (item.productIds.isNotEmpty ? item.productIds : [if (item.id != null) item.id!])
            : null,
      );
      if (!mounted) return;
      setState(() {
        _children.addAll(page.rows);
        _total = page.total;
        _loaded = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyPricingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _cell(PricingOverviewCell? c) {
    if (c == null) return const SizedBox.shrink();
    return switch (c.state) {
      'full' => const Tooltip(
          message: 'Priced by this group',
          child: Icon(Icons.check_circle, size: 18, color: _green),
        ),
      'partial' => Tooltip(
          message: '${c.count} of ${c.total} brand(s) priced by this group',
          child: Text('${c.count}/${c.total}',
              style: const TextStyle(fontSize: 12.5, color: _blue, fontWeight: FontWeight.w800)),
        ),
      _ => Tooltip(
          message: '${c.count} brand(s) in this group, not priced by it for this dealer',
          child: Icon(Icons.radio_button_unchecked, size: 16, color: Colors.grey.shade500),
        ),
    };
  }

  Widget _pct(PricingOverviewRow r) {
    final grey = Colors.grey.shade600;
    if (r.kind != PricingItemKind.brand) {
      if (r.unpricedCount == 0) return Text('—', style: TextStyle(color: grey));
      return Text('${r.unpricedCount} not in a group', style: const TextStyle(fontSize: 11.5, color: _amber));
    }
    if (!r.hasRow) return Text('no access', style: TextStyle(fontSize: 12, color: grey));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${r.profitPercentage ?? '-'} / ${r.sellingProfitPercentage ?? '-'}',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              decoration: r.deactivated ? TextDecoration.lineThrough : null,
            )),
        Text(
          r.deactivated ? 'deactivated' : (r.managedBy != null ? 'by ${r.managedBy}' : 'by hand'),
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: r.managedBy != null ? _green : _amber),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final grey = Colors.grey.shade600;
    final hasChildren = _childKindOf(r.kind) != null;
    final indent = 10.0 + widget.depth * 16;

    final item = Padding(
      padding: EdgeInsets.only(left: indent, right: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasChildren)
            Icon(_open ? Icons.expand_more : Icons.chevron_right, size: 18)
          else
            const SizedBox(width: 18),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.item.label,
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                if (r.item.subtitle.isNotEmpty)
                  Text(r.item.subtitle, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: grey)),
              ],
            ),
          ),
        ],
      ),
    );

    final line = InkWell(
      onTap: hasChildren ? _toggle : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade200))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: _itemW, child: item),
            SizedBox(
              width: _typeW,
              child: Text(r.kind.apiName, style: TextStyle(fontSize: 11.5, color: grey)),
            ),
            for (final g in widget.groups) SizedBox(width: _groupW, child: Center(child: _cell(r.cells[g.id]))),
            SizedBox(width: _pctW, child: _pct(r)),
          ],
        ),
      ),
    );

    if (!_open) return line;
    final childKind = _childKindOf(r.kind)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        line,
        if (_loading && _children.isEmpty) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: EdgeInsets.only(left: indent + 22, top: 4, bottom: 4),
            child: Row(children: [
              Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 12.5)),
              TextButton(onPressed: _loadMore, child: const Text('Retry')),
            ]),
          ),
        if (_loaded && _children.isEmpty && _error == null)
          Padding(
            padding: EdgeInsets.only(left: indent + 22, top: 6, bottom: 6),
            child: Text('No ${childKind.title.toLowerCase()} here.', style: TextStyle(fontSize: 12, color: grey)),
          ),
        for (final c in _children)
          _OverviewRowTile(
            key: ValueKey('${c.kind.apiName}:${c.item.key}'),
            row: c,
            groups: widget.groups,
            userId: widget.userId,
            unpricedOnly: widget.unpricedOnly,
            depth: widget.depth + 1,
          ),
        if (_children.length < _total)
          Padding(
            padding: EdgeInsets.only(left: indent + 18),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _loading ? null : _loadMore,
                icon: const Icon(Icons.expand_more, size: 18),
                label: Text('Show more (${_children.length} of $_total)'),
              ),
            ),
          ),
      ],
    );
  }
}
