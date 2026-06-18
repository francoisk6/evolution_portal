import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scroll_behavior.dart';
import '../../data/models/prepaid_stock.dart';
import '../../services/prepaid_stock_service.dart';
import '../../state/session_provider.dart';
import '../../widgets/page_action_bar.dart' show PageAction, PageActions;

class _ComboBoxOption<T> {
  final T value;
  final String label;

  const _ComboBoxOption({required this.value, required this.label});
}

class _PrepaidGridCol {
  final String key;
  final String label;
  final double width;
  final TextAlign align;
  final String Function(PrepaidStockRow row) cell;

  const _PrepaidGridCol({
    required this.key,
    required this.label,
    required this.width,
    required this.align,
    required this.cell,
  });
}

class _MultiSelectionResult<T> {
  final List<T> values;
  final bool cleared;

  _MultiSelectionResult.submit(this.values) : cleared = false;
  _MultiSelectionResult.clear()
      : values = <T>[],
        cleared = true;
}

class _SearchableMultiSelectField<T> extends StatelessWidget {
  final String label;
  final String? hintText;
  final List<T> values;
  final List<_ComboBoxOption<T>> options;
  final ValueChanged<List<T>> onChanged;
  final String allLabel;

  const _SearchableMultiSelectField({
    required this.label,
    required this.values,
    required this.options,
    required this.onChanged,
    this.hintText,
    this.allLabel = 'All',
  });

  String _selectedLabel() {
    if (values.isEmpty) return hintText ?? allLabel;
    final selected =
        options.where((option) => values.contains(option.value)).toList();
    if (selected.isEmpty) return '${values.length} selected';
    if (selected.length == 1) return selected.first.label;
    if (selected.length <= 3) return selected.map((e) => e.label).join(', ');
    return '${selected.length} selected';
  }

  Future<void> _openPicker(BuildContext context) async {
    final result = await showModalBottomSheet<_MultiSelectionResult<T>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final searchCtl = TextEditingController();
        final scrollCtl = ScrollController();
        final selected = <T>{...values};

        return FractionallySizedBox(
          heightFactor: 0.78,
          child: StatefulBuilder(
            builder: (context, setModalState) {
              final query = searchCtl.text.trim().toLowerCase();
              final filtered = query.isEmpty
                  ? options
                  : options.where((option) {
                      return option.label.toLowerCase().contains(query);
                    }).toList();

              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    6,
                    12,
                    MediaQuery.of(context).viewInsets.bottom + 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: .08),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: .18),
                              ),
                            ),
                            child: Text(
                              '${selected.length} selected',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: searchCtl,
                        autofocus: true,
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'Type to search',
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: searchCtl.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    searchCtl.clear();
                                    setModalState(() {});
                                  },
                                ),
                        ),
                        onChanged: (_) => setModalState(() {}),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.pop(
                                context,
                                _MultiSelectionResult<T>.clear(),
                              ),
                              icon: const Icon(Icons.backspace_outlined,
                                  size: 18),
                              label: Text(
                                allLabel,
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => Navigator.pop(
                                context,
                                _MultiSelectionResult<T>.submit(
                                    selected.toList()),
                              ),
                              icon: const Icon(Icons.check, size: 18),
                              label: const Text(
                                'Apply',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: filtered.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No matching items',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                )
                              : Scrollbar(
                                  controller: scrollCtl,
                                  thumbVisibility: true,
                                  interactive: true,
                                  child: ListView.separated(
                                    controller: scrollCtl,
                                    itemCount: filtered.length,
                                    separatorBuilder: (_, __) => Divider(
                                      height: 1,
                                      color: Colors.grey.shade200,
                                    ),
                                    itemBuilder: (context, index) {
                                      final option = filtered[index];
                                      final isSelected =
                                          selected.contains(option.value);
                                      return Material(
                                        color: isSelected
                                            ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withValues(alpha: .08)
                                            : Colors.transparent,
                                        child: InkWell(
                                          onTap: () {
                                            setModalState(() {
                                              if (isSelected) {
                                                selected.remove(option.value);
                                              } else {
                                                selected.add(option.value);
                                              }
                                            });
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            child: Row(
                                              children: [
                                                Checkbox(
                                                  value: isSelected,
                                                  onChanged: (_) {
                                                    setModalState(() {
                                                      if (isSelected) {
                                                        selected
                                                            .remove(option.value);
                                                      } else {
                                                        selected
                                                            .add(option.value);
                                                      }
                                                    });
                                                  },
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    option.label,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );

    if (result == null) return;
    if (result.cleared) {
      onChanged(<T>[]);
      return;
    }
    onChanged(result.values);
  }

  @override
  Widget build(BuildContext context) {
    final selectedLabel = _selectedLabel();

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        _openPicker(context);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          suffixIcon: const Icon(Icons.arrow_drop_down),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          selectedLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: values.isEmpty ? Theme.of(context).hintColor : null,
            fontWeight: values.isEmpty ? FontWeight.w400 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class PrepaidStockPage extends ConsumerStatefulWidget {
  const PrepaidStockPage({super.key});

  @override
  ConsumerState<PrepaidStockPage> createState() => _PrepaidStockPageState();
}

class _PrepaidStockPageState extends ConsumerState<PrepaidStockPage> {
  final _service = PrepaidStockService.instance;

  final _searchCtl = TextEditingController();
  final _pageCtl = ScrollController(); // narrow (card) layout: whole-page scroll
  final _vGridCtl = ScrollController(); // wide grid: vertical row scroll
  final _hGridCtl = ScrollController(); // wide grid: horizontal scroll

  // The unfiltered universe (consumed=all) used to drive cascading filter
  // options. Each row carries full sector→category→product→brand context.
  List<PrepaidStockRow> _universe = const <PrepaidStockRow>[];

  PrepaidStockResponse? _result;

  bool _loadingUniverse = false;
  bool _loadingList = false;
  String? _error;

  List<int> _sectorIds = <int>[];
  List<int> _categoryIds = <int>[];
  List<int> _productIds = <int>[];
  List<int> _brandIds = <int>[];

  // 'false' (unconsumed only), 'true' (consumed only), 'all'.
  String _consumed = 'false';
  // 'quantity' (desc) or 'name' (asc).
  String _order = 'quantity';

  Color get _fg => const Color(0xFF1F2937);
  Color get _fgSoft => const Color(0xFF6B7280);

  @override
  void initState() {
    super.initState();
    Future.microtask(_bootstrap);
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    _pageCtl.dispose();
    _vGridCtl.dispose();
    _hGridCtl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (!ref.read(sessionProvider).isAdmin) return;
    await _loadUniverse();
    await _loadList();
  }

  String _cleanError(Object e) {
    final s = e.toString();
    if (s.startsWith('Exception: ')) return s.substring('Exception: '.length);
    return s;
  }

  // ───────────────── data loading ─────────────────

  Future<void> _loadUniverse() async {
    setState(() {
      _loadingUniverse = true;
      _error = null;
    });
    try {
      final response = await _service.stockByBrand(consumed: 'all');
      if (!mounted) return;
      setState(() {
        _universe = response.results;
        _reconcileSelections();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _cleanError(e));
    } finally {
      if (mounted) setState(() => _loadingUniverse = false);
    }
  }

  Future<void> _loadList() async {
    setState(() {
      _loadingList = true;
      _error = null;
    });
    try {
      final response = await _service.stockByBrand(
        sectorIds: _sectorIds,
        categoryIds: _categoryIds,
        productIds: _productIds,
        brandIds: _brandIds,
        search: _searchCtl.text.trim(),
        consumed: _consumed,
        order: _order,
      );
      if (!mounted) return;
      setState(() => _result = response);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _cleanError(e));
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  Future<void> _refreshAll() async {
    await _loadUniverse();
    await _loadList();
  }

  Future<void> _clearFilters() async {
    setState(() {
      _sectorIds = <int>[];
      _categoryIds = <int>[];
      _productIds = <int>[];
      _brandIds = <int>[];
      _consumed = 'false';
      _order = 'quantity';
      _searchCtl.clear();
    });
    await _loadList();
  }

  // ───────────────── cascading filter options ─────────────────

  // Rows of the universe that match the currently-selected parent filters,
  // up to (but excluding) [level]: 0=sector, 1=category, 2=product, 3=brand.
  Iterable<PrepaidStockRow> _rowsForLevel(int level) {
    return _universe.where((row) {
      if (level > 0 &&
          _sectorIds.isNotEmpty &&
          !_sectorIds.contains(row.sector?.id)) {
        return false;
      }
      if (level > 1 &&
          _categoryIds.isNotEmpty &&
          !_categoryIds.contains(row.category?.id)) {
        return false;
      }
      if (level > 2 &&
          _productIds.isNotEmpty &&
          !_productIds.contains(row.product?.id)) {
        return false;
      }
      return true;
    });
  }

  List<_ComboBoxOption<int>> _optionsFor(
    int level,
    PrepaidStockRef? Function(PrepaidStockRow row) pick,
  ) {
    final seen = <int>{};
    final options = <_ComboBoxOption<int>>[];
    for (final row in _rowsForLevel(level)) {
      final ref = pick(row);
      if (ref == null || seen.contains(ref.id)) continue;
      seen.add(ref.id);
      options.add(_ComboBoxOption<int>(value: ref.id, label: ref.label));
    }
    options.sort(
        (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return options;
  }

  List<int> _retainValid(List<int> ids, List<_ComboBoxOption<int>> options) {
    if (ids.isEmpty) return const <int>[];
    final allowed = options.map((e) => e.value).toSet();
    return ids.where(allowed.contains).toList();
  }

  // Drop selections that no longer exist in the universe / parent scope.
  void _reconcileSelections() {
    _sectorIds = _retainValid(_sectorIds, _optionsFor(0, (r) => r.sector));
    _categoryIds =
        _retainValid(_categoryIds, _optionsFor(1, (r) => r.category));
    _productIds = _retainValid(_productIds, _optionsFor(2, (r) => r.product));
    _brandIds = _retainValid(_brandIds, _optionsFor(3, (r) => r.brand));
  }

  Future<void> _handleSectorsChanged(List<int> values) async {
    setState(() {
      _sectorIds = values.toSet().toList()..sort();
      _categoryIds = <int>[];
      _productIds = <int>[];
      _brandIds = <int>[];
      _reconcileSelections();
    });
    await _loadList();
  }

  Future<void> _handleCategoriesChanged(List<int> values) async {
    setState(() {
      _categoryIds = values.toSet().toList()..sort();
      _productIds = <int>[];
      _brandIds = <int>[];
      _reconcileSelections();
    });
    await _loadList();
  }

  Future<void> _handleProductsChanged(List<int> values) async {
    setState(() {
      _productIds = values.toSet().toList()..sort();
      _brandIds = <int>[];
      _reconcileSelections();
    });
    await _loadList();
  }

  Future<void> _handleBrandsChanged(List<int> values) async {
    setState(() {
      _brandIds = values.toSet().toList()..sort();
      _reconcileSelections();
    });
    await _loadList();
  }

  // ───────────────── UI ─────────────────

  Widget _sectionCard({required Widget child}) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: child,
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Prepaid cards stock',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: _fg,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Available prepaid card stock grouped by brand, with cascading sector / category / product / brand filters.',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: _fgSoft,
                  height: 1.22,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onPressed: _loadingUniverse || _loadingList ? null : _clearFilters,
              icon: const Icon(Icons.filter_alt_off, size: 18),
              label: const Text('Clear', style: TextStyle(fontSize: 12)),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onPressed: _loadingUniverse || _loadingList ? null : _refreshAll,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryBar() {
    final result = _result;
    final brandCount = result?.brandCount ?? 0;
    final totalQuantity = result?.totalQuantity ?? 0;

    Widget chip(String label, String value, Color color) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: .18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$label: ',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _fgSoft,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip('Brands', '$brandCount', const Color(0xFF1565C0)),
        chip('Total quantity', '$totalQuantity', const Color(0xFF1E7E34)),
      ],
    );
  }

  Widget _buildFiltersCard(BuildContext context) {
    return _sectionCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = width >= 1180
                ? 4
                : width >= 820
                    ? 3
                    : width >= 540
                        ? 2
                        : 1;
            final fieldWidth = columns == 1
                ? width
                : (width - ((columns - 1) * 10)) / columns;

            Widget box(Widget child) =>
                SizedBox(width: fieldWidth, child: child);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filters',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: _fg,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sector → category → product → brand cascade. Selecting a parent narrows the choices below it.',
                  style: TextStyle(fontSize: 11.5, color: _fgSoft, height: 1.2),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    box(
                      _SearchableMultiSelectField<int>(
                        label: 'Sector',
                        hintText: 'All sectors',
                        values: _sectorIds,
                        options: _optionsFor(0, (r) => r.sector),
                        onChanged: _handleSectorsChanged,
                      ),
                    ),
                    box(
                      _SearchableMultiSelectField<int>(
                        label: 'Category',
                        hintText: 'All categories',
                        values: _categoryIds,
                        options: _optionsFor(1, (r) => r.category),
                        onChanged: _handleCategoriesChanged,
                      ),
                    ),
                    box(
                      _SearchableMultiSelectField<int>(
                        label: 'Product',
                        hintText: 'All products',
                        values: _productIds,
                        options: _optionsFor(2, (r) => r.product),
                        onChanged: _handleProductsChanged,
                      ),
                    ),
                    box(
                      _SearchableMultiSelectField<int>(
                        label: 'Brand',
                        hintText: 'All brands',
                        values: _brandIds,
                        options: _optionsFor(3, (r) => r.brand),
                        onChanged: _handleBrandsChanged,
                      ),
                    ),
                    box(
                      TextField(
                        controller: _searchCtl,
                        style: const TextStyle(fontSize: 12),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          labelText: 'Search',
                          hintText: 'Brand name / alt',
                          isDense: true,
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: _searchCtl.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _searchCtl.clear();
                                    _loadList();
                                  },
                                ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _loadList(),
                      ),
                    ),
                    box(
                      DropdownButtonFormField<String>(
                        initialValue: _consumed,
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          labelText: 'Consumed',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'false', child: Text('Available only')),
                          DropdownMenuItem(
                              value: 'true', child: Text('Consumed only')),
                          DropdownMenuItem(value: 'all', child: Text('All')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _consumed = v);
                          _loadList();
                        },
                      ),
                    ),
                    box(
                      DropdownButtonFormField<String>(
                        initialValue: _order,
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          labelText: 'Order',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'quantity',
                              child: Text('Quantity (high → low)')),
                          DropdownMenuItem(
                              value: 'name', child: Text('Name (A → Z)')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _order = v);
                          _loadList();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildListHeaderRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Stock by brand',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: _fg,
                ),
          ),
        ),
        if (_loadingList)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ],
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          'No prepaid stock matches the current filters.',
          style: TextStyle(fontSize: 12, color: _fgSoft),
        ),
      ),
    );
  }

  // Wide layout: a fixed-height card whose grid header stays put while the rows
  // scroll inside the grid (mirrors the Transaction History page).
  Widget _buildGridCard(BuildContext context) {
    final rows = _result?.results ?? const <PrepaidStockRow>[];

    return _sectionCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildListHeaderRow(context),
            const SizedBox(height: 12),
            _buildSummaryBar(),
            const SizedBox(height: 12),
            Expanded(
              child: (rows.isEmpty && !_loadingList)
                  ? _emptyState()
                  : _buildGrid(context, rows),
            ),
          ],
        ),
      ),
    );
  }

  // Narrow layout: stacked cards; the whole page scrolls.
  Widget _buildCardsCard(BuildContext context) {
    final rows = _result?.results ?? const <PrepaidStockRow>[];

    return _sectionCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildListHeaderRow(context),
            const SizedBox(height: 12),
            _buildSummaryBar(),
            const SizedBox(height: 12),
            if (rows.isEmpty && !_loadingList)
              _emptyState()
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: rows.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: Colors.grey.shade200),
                itemBuilder: (context, index) => _buildRow(rows[index]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(BuildContext context, List<PrepaidStockRow> rows) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;
        const headerRed = Color(0xFFD32F2F);
        const headerBg = Color(0xFFFFF2F2);
        final border = Colors.red.withValues(alpha: .25);

        final baseCols = <_PrepaidGridCol>[
      _PrepaidGridCol(
        key: 'brand',
        label: 'Brand',
        width: 140, // flexes below
        align: TextAlign.left,
        cell: (r) => r.brand?.label ?? '-',
      ),
      _PrepaidGridCol(
        key: 'product',
        label: 'Product',
        width: 130,
        align: TextAlign.left,
        cell: (r) => r.product?.label ?? '-',
      ),
      _PrepaidGridCol(
        key: 'category',
        label: 'Category',
        width: 120,
        align: TextAlign.left,
        cell: (r) => r.category?.label ?? '-',
      ),
      _PrepaidGridCol(
        key: 'sector',
        label: 'Sector',
        width: 110,
        align: TextAlign.left,
        cell: (r) => r.sector?.label ?? '-',
      ),
      _PrepaidGridCol(
        key: 'quantity',
        label: 'Quantity',
        width: 150,
        align: TextAlign.right,
        cell: (r) => '${r.quantity}',
      ),
    ];

    // Extra right padding on the last (Quantity) column so the right-aligned
    // values stay clear of the vertical scrollbar and the floating actions.
    const lastColRightPad = 56.0;

    const minBrandW = 140.0;
    final fixedW = baseCols.fold<double>(
      0,
      (s, c) => s + (c.key == 'brand' ? 0 : c.width),
    );
    final brandW = (maxWidth - fixedW - 2).clamp(minBrandW, 100000.0);
    final cols = baseCols.map((c) {
      if (c.key != 'brand') return c;
      return _PrepaidGridCol(
        key: c.key,
        label: c.label,
        width: brandW,
        align: c.align,
        cell: c.cell,
      );
    }).toList();
    final tableW = fixedW + brandW + 2;

    Widget headerRow() {
      return Container(
        width: tableW,
        decoration: BoxDecoration(
          color: headerBg,
          border: Border(
            top: BorderSide(color: border),
            bottom: BorderSide(color: border),
          ),
        ),
        child: Row(
          children: cols.map((c) {
            return SizedBox(
              width: c.width,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 8,
                  right: c.key == 'quantity' ? lastColRightPad : 8,
                  top: 8,
                  bottom: 8,
                ),
                child: Text(
                  c.label,
                  textAlign: c.align,
                  style: const TextStyle(
                    color: headerRed,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    height: 1.2,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      );
    }

    Widget dataRow(PrepaidStockRow r, int idx) {
      final zebra = idx.isOdd ? const Color(0xFFF2F2F2) : Colors.white;
      return Container(
        width: tableW,
        decoration: BoxDecoration(
          color: zebra,
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade300),
            left: BorderSide(color: Colors.grey.shade200),
            right: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: cols.map((c) {
            final raw = c.cell(r).trim();
            final isQty = c.key == 'quantity';
            final qtyColor = r.quantity <= 0
                ? const Color(0xFFD32F2F)
                : const Color(0xFF1E7E34);
            return SizedBox(
              width: c.width,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 8,
                  right: c.key == 'quantity' ? lastColRightPad : 8,
                  top: 9,
                  bottom: 9,
                ),
                child: Text(
                  raw,
                  textAlign: c.align,
                  softWrap: true,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isQty
                        ? qtyColor
                        : (c.key == 'brand' ? _fg : _fgSoft),
                    fontWeight: isQty || c.key == 'brand'
                        ? FontWeight.w900
                        : FontWeight.w600,
                    fontSize: 11,
                    height: 1.25,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      );
    }

        return ScrollConfiguration(
          behavior: const EvolutionScrollBehavior(showScrollbars: false),
          child: SingleChildScrollView(
            controller: _hGridCtl,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableW,
              height: maxHeight,
              child: Column(
                children: [
                  headerRow(), // stays fixed; only the rows below scroll
                  Expanded(
                    child: Scrollbar(
                      controller: _vGridCtl,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _vGridCtl,
                        itemCount: rows.length,
                        itemBuilder: (context, i) => dataRow(rows[i], i),
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

  Widget _buildRow(PrepaidStockRow row) {
    final outOfStock = row.quantity <= 0;
    final qtyColor =
        outOfStock ? const Color(0xFFD32F2F) : const Color(0xFF1E7E34);

    final context = <String>[
      if (row.sector != null) row.sector!.label,
      if (row.category != null) row.category!.label,
      if (row.product != null) row.product!.label,
    ].join(' • ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.brand?.label ?? '-',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _fg,
                  ),
                ),
                if (context.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    context,
                    style: TextStyle(fontSize: 11.5, color: _fgSoft),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: qtyColor.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: qtyColor.withValues(alpha: .20)),
            ),
            child: Text(
              '${row.quantity}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: qtyColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccessDenied(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 42,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text(
                  'Access denied',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'This page is available for admin users only.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Shared between layouts: optional progress bar + error banner.
  List<Widget> _buildStatusBanners(BuildContext context) {
    return [
      if (_loadingUniverse) ...[
        const SizedBox(height: 12),
        const LinearProgressIndicator(minHeight: 2),
      ],
      if (_error != null) ...[
        const SizedBox(height: 12),
        Material(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final actions = <PageAction>[
      PageAction(label: 'Refresh', icon: Icons.refresh, onTap: _refreshAll),
      PageAction(
          label: 'Clear', icon: Icons.filter_alt_off, onTap: _clearFilters),
    ];

    if (!session.isAdmin) {
      return _buildAccessDenied(context);
    }

    final useGrid = MediaQuery.of(context).size.width >= 720;

    return PageActions(
      actions: actions,
      child: useGrid ? _buildWideLayout(context) : _buildNarrowLayout(context),
    );
  }

  // Wide: header + filters stay fixed; the grid fills the rest of the viewport
  // and scrolls internally (its own header stays put) — like Transaction History.
  Widget _buildWideLayout(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          ..._buildStatusBanners(context),
          const SizedBox(height: 12),
          _buildFiltersCard(context),
          const SizedBox(height: 12),
          Expanded(child: _buildGridCard(context)),
        ],
      ),
    );
  }

  // Narrow: the whole page scrolls; results render as stacked cards (form).
  Widget _buildNarrowLayout(BuildContext context) {
    return ScrollConfiguration(
      behavior: const EvolutionScrollBehavior(showScrollbars: false),
      child: Scrollbar(
        controller: _pageCtl,
        thumbVisibility: true,
        trackVisibility: true,
        child: SingleChildScrollView(
          controller: _pageCtl,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              ..._buildStatusBanners(context),
              const SizedBox(height: 12),
              _buildFiltersCard(context),
              const SizedBox(height: 12),
              _buildCardsCard(context),
            ],
          ),
        ),
      ),
    );
  }
}
