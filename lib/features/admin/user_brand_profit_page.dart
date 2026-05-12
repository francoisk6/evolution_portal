import 'dart:convert' show utf8;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../app/app_scroll_behavior.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/user_brand_profit.dart';
import '../../services/user_brand_profit_service.dart';
import '../../state/session_provider.dart';
import '../../utils/file_download.dart';
import '../../utils/money_format.dart';
import '../../widgets/page_action_bar.dart' show PageAction, PageActions;

class _ComboBoxOption<T> {
  final T value;
  final String label;

  const _ComboBoxOption({required this.value, required this.label});
}

class _DropdownSelectionResult<T> {
  final T? value;
  final bool cleared;

  const _DropdownSelectionResult.select(this.value) : cleared = false;
  const _DropdownSelectionResult.clear()
      : value = null,
        cleared = true;
}

class _SearchableDropdownField<T> extends StatelessWidget {
  final String label;
  final String? hintText;
  final T? value;
  final List<_ComboBoxOption<T>> options;
  final ValueChanged<T?> onChanged;
  final String allLabel;

  const _SearchableDropdownField({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.hintText,
    this.allLabel = 'All',
  });

  String? _selectedLabel() {
    for (final option in options) {
      if (option.value == value) return option.label;
    }
    return null;
  }

  Future<void> _openPicker(BuildContext context) async {
    final result = await showModalBottomSheet<_DropdownSelectionResult<T>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final searchCtl = TextEditingController();
        final scrollCtl = ScrollController();

        return FractionallySizedBox(
          heightFactor: 0.72,
          child: StatefulBuilder(
            builder: (context, setState) {
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
                      Text(
                        label,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
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
                                    setState(() {});
                                  },
                                ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => Navigator.pop(
                            context,
                            _DropdownSelectionResult<T>.clear(),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.backspace_outlined, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    allLabel,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (value == null)
                                  const Icon(Icons.check, size: 18),
                              ],
                            ),
                          ),
                        ),
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
                                      final selected = option.value == value;
                                      return Material(
                                        color: selected
                                            ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withValues(alpha: .08)
                                            : Colors.transparent,
                                        child: InkWell(
                                          onTap: () => Navigator.pop(
                                            context,
                                            _DropdownSelectionResult<T>.select(
                                              option.value,
                                            ),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                            child: Row(
                                              children: [
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
                                                if (selected)
                                                  const Icon(Icons.check, size: 18),
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
      onChanged(null);
      return;
    }
    onChanged(result.value);
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
          selectedLabel ?? hintText ?? allLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: selectedLabel == null
                ? Theme.of(context).hintColor
                : null,
            fontWeight: selectedLabel == null ? FontWeight.w400 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
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
    final selected = options.where((option) => values.contains(option.value)).toList();
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
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: .08),
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
                              icon: const Icon(Icons.backspace_outlined, size: 18),
                              label: Text(
                                allLabel,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => Navigator.pop(
                                context,
                                _MultiSelectionResult<T>.submit(selected.toList()),
                              ),
                              icon: const Icon(Icons.check, size: 18),
                              label: const Text(
                                'Apply',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
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
                                      final isSelected = selected.contains(option.value);
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
                                                        selected.remove(option.value);
                                                      } else {
                                                        selected.add(option.value);
                                                      }
                                                    });
                                                  },
                                                  visualDensity: VisualDensity.compact,
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    option.label,
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
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

class UserBrandProfitPage extends ConsumerStatefulWidget {
  const UserBrandProfitPage({super.key});

  @override
  ConsumerState<UserBrandProfitPage> createState() => _UserBrandProfitPageState();
}

class _UserBrandProfitPageState extends ConsumerState<UserBrandProfitPage> {
  final _service = UserBrandProfitService.instance;

  final _searchCtl = TextEditingController();
  final _profitCtl = TextEditingController();
  final _sellingProfitCtl = TextEditingController();

  final _pageCtl = ScrollController();
  final _vListCtl = ScrollController();
  final _hListCtl = ScrollController();

  UserBrandProfitFilterOptionsResponse? _filters;
  List<UserBrandProfitItem> _items = const <UserBrandProfitItem>[];
  bool _hasMore = false;
  bool _loadingMore = false;
  int _total = 0;

  bool _loadingFilters = false;
  bool _loadingList = false;
  bool _submittingBulk = false;
  bool _submittingStandard = false;
  bool _exportingCsv = false;
  String? _error;

  int? _groupId;
  List<int> _userIds = <int>[];
  int? _sectorId;
  int? _categoryId;
  int? _productId;
  String? _productPrefix;
  int? _productTypeId;
  int? _brandId;
  bool? _deactivated;
  bool _overrideExisting = false;

  int _page = 1;
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _vListCtl.addListener(() => _onScroll(_vListCtl));
    _pageCtl.addListener(() => _onScroll(_pageCtl));
    Future.microtask(_bootstrap);
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    _profitCtl.dispose();
    _sellingProfitCtl.dispose();
    _pageCtl.dispose();
    _vListCtl.dispose();
    _hListCtl.dispose();
    super.dispose();
  }

  Color get _fg => const Color(0xFF1F2937);
  Color get _fgSoft => const Color(0xFF6B7280);

  Future<void> _bootstrap() async {
    if (!ref.read(sessionProvider).isAdmin) return;
    await _loadFilters();
    await _loadList();
  }

  List<_ComboBoxOption<int>> _optionsFrom(List<UserBrandProfitOption> items) {
    return items
        .map((e) => _ComboBoxOption<int>(value: e.id, label: e.label))
        .toList();
  }

  // Product options encode id or prefix as a String key so the dropdown
  // can distinguish multiple prefix-group entries that all have id == 0.
  List<_ComboBoxOption<String>> _productOptions(List<UserBrandProfitOption> products) {
    return products.map((e) {
      if (e.productPrefix != null) {
        return _ComboBoxOption<String>(value: 'prefix:${e.productPrefix}', label: e.label);
      }
      return _ComboBoxOption<String>(value: 'id:${e.id}', label: e.label);
    }).toList();
  }

  String? _productFilterKey() {
    if (_productPrefix != null) return 'prefix:$_productPrefix';
    if (_productId != null) return 'id:$_productId';
    return null;
  }

  void _applyProductFilterKey(String? key) {
    if (key == null) {
      _productId = null;
      _productPrefix = null;
    } else if (key.startsWith('prefix:')) {
      _productPrefix = key.substring(7);
      _productId = null;
    } else if (key.startsWith('id:')) {
      _productId = int.tryParse(key.substring(3));
      _productPrefix = null;
    }
  }

  String _productFilterLabel(List<UserBrandProfitOption> products) {
    if (_productPrefix != null) return _productPrefix!;
    return _selectionLabel(products, _productId);
  }

  List<_ComboBoxOption<bool>> _deactivatedOptions() {
    return const <_ComboBoxOption<bool>>[
      _ComboBoxOption<bool>(value: false, label: 'Active only'),
      _ComboBoxOption<bool>(value: true, label: 'Deactivated only'),
    ];
  }

  bool _containsOption(List<UserBrandProfitOption> items, int? id) {
    if (id == null) return true;
    return items.any((e) => e.id == id);
  }

  List<int> _retainExistingOptionIds(
    List<UserBrandProfitOption> items,
    List<int> ids,
  ) {
    if (ids.isEmpty) return const <int>[];
    final allowed = items.map((e) => e.id).toSet();
    return ids.where(allowed.contains).toList();
  }

  List<String> _selectionLabels(List<UserBrandProfitOption> items, List<int> ids) {
    return ids.map((id) => _selectionLabel(items, id)).toList();
  }

  String _selectedUsersSummary(List<UserBrandProfitOption> items) {
    final labels = _selectionLabels(items, _userIds);
    if (labels.isEmpty) return 'All';
    if (labels.length <= 3) return labels.join(', ');
    return '${labels.take(3).join(', ')} +${labels.length - 3} more';
  }

  String _targetUsersLabel(List<UserBrandProfitOption> items) {
    final labels = _selectionLabels(items, _userIds);
    if (labels.isEmpty) return 'All active users';
    if (labels.length == 1) return 'User: ${labels.first}';
    if (labels.length <= 3) return 'Users: ${labels.join(', ')}';
    return 'Users: ${labels.take(2).join(', ')} +${labels.length - 2} more';
  }

  void _reconcileFilterSelections(UserBrandProfitFilterOptionsResponse next) {
    if (!_containsOption(next.groups, _groupId)) _groupId = null;
    _userIds = _retainExistingOptionIds(next.users, _userIds);
    if (!_containsOption(next.sectors, _sectorId)) _sectorId = null;
    if (!_containsOption(next.categories, _categoryId)) _categoryId = null;
    if (_productPrefix != null) {
      if (!next.products.any((e) => e.productPrefix == _productPrefix)) _productPrefix = null;
    } else if (!_containsOption(next.products, _productId)) {
      _productId = null;
    }
    if (!_containsOption(next.productTypes, _productTypeId)) _productTypeId = null;
    if (!_containsOption(next.brands, _brandId)) _brandId = null;
  }

  Future<void> _loadFilters() async {
    setState(() {
      _loadingFilters = true;
      _error = null;
    });

    try {
      final response = await _service.getFilters(
        groupId: _groupId,
        sectorId: _sectorId,
        categoryId: _categoryId,
        productId: _productId,
        productPrefix: _productPrefix,
        productTypeId: _productTypeId,
        brandId: _brandId,
      );
      if (!mounted) return;
      setState(() {
        _filters = response;
        _reconcileFilterSelections(response);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _cleanError(e));
    } finally {
      if (mounted) {
        setState(() => _loadingFilters = false);
      }
    }
  }

  void _onScroll(ScrollController ctl) {
    if (!ctl.hasClients) return;
    final pos = ctl.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels >= pos.maxScrollExtent * 0.7) _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loadingList || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final response = await _service.list(
        groupId: _groupId,
        userIds: _userIds,
        sectorId: _sectorId,
        categoryId: _categoryId,
        productId: _productId,
        productPrefix: _productPrefix,
        productTypeId: _productTypeId,
        brandId: _brandId,
        deactivated: _deactivated,
        search: _searchCtl.text.trim(),
        page: _page + 1,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _page++;
        _items = [..._items, ...response.items];
        _hasMore = response.hasNext;
        _total = response.total;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _cleanError(e));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _loadList({int? page}) async {
    setState(() {
      _loadingList = true;
      _error = null;
      if (page != null) _page = page;
    });

    try {
      final response = await _service.list(
        groupId: _groupId,
        userIds: _userIds,
        sectorId: _sectorId,
        categoryId: _categoryId,
        productId: _productId,
        productPrefix: _productPrefix,
        productTypeId: _productTypeId,
        brandId: _brandId,
        deactivated: _deactivated,
        search: _searchCtl.text.trim(),
        page: _page,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items = response.items;
        _hasMore = response.hasNext;
        _total = response.total;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _cleanError(e));
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  Future<void> _refreshAll() async {
    await _loadFilters();
    await _loadList(page: 1);
  }

  Future<void> _clearFilters() async {
    setState(() {
      _groupId = null;
      _userIds = <int>[];
      _sectorId = null;
      _categoryId = null;
      _productId = null;
      _productPrefix = null;
      _productTypeId = null;
      _brandId = null;
      _deactivated = null;
      _page = 1;
      _searchCtl.clear();
    });
    await _loadFilters();
    await _loadList(page: 1);
  }

  String _cleanError(Object e) {
    final s = e.toString();
    if (s.startsWith('Exception: ')) return s.substring('Exception: '.length);
    return s;
  }

  String _displayCostPrice(UserBrandProfitItem item) {
    final cost = MoneyFormat.tryParse(item.nativeCostPrice);
    if (cost == null || cost == 0) {
      return item.nativeCostPrice.isEmpty ? '-' : item.nativeCostPrice;
    }
    return MoneyFormat.format(cost, currencyCode: item.brand?.currency ?? '');
  }

  String _displayDealerPrice(UserBrandProfitItem item) {
    final cost = MoneyFormat.tryParse(item.nativeCostPrice);
    final profit = MoneyFormat.tryParse(item.profitPercentage);
    if (cost == null || profit == null || cost == 0) return '-';
    return MoneyFormat.format(cost * profit, currencyCode: item.brand?.currency ?? '');
  }

  String _displaySellingPrice(UserBrandProfitItem item) {
    final cost = MoneyFormat.tryParse(item.nativeCostPrice);
    final profit = MoneyFormat.tryParse(item.profitPercentage);
    final selling = MoneyFormat.tryParse(item.sellingProfitPercentage);
    if (cost == null || profit == null || selling == null || cost == 0) return '-';
    return MoneyFormat.format(
      cost * profit * selling,
      currencyCode: item.brand?.currency ?? '',
    );
  }

  static String _csvEscape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  Future<void> _exportCsv() async {
    setState(() => _exportingCsv = true);
    try {
      const batchSize = 200;
      final allItems = <UserBrandProfitItem>[];
      var page = 1;
      while (true) {
        final response = await _service.list(
          groupId: _groupId,
          userIds: _userIds,
          sectorId: _sectorId,
          categoryId: _categoryId,
          productId: _productId,
          productPrefix: _productPrefix,
          productTypeId: _productTypeId,
          brandId: _brandId,
          deactivated: _deactivated,
          search: _searchCtl.text.trim(),
          page: page,
          pageSize: batchSize,
        );
        allItems.addAll(response.items);
        if (!response.hasNext || response.items.isEmpty) break;
        page++;
      }
      final rows = <List<String>>[
        [
          'User', 'Brand', 'Code', 'Currency',
          'Sector', 'Category', 'Product', 'Product Type',
          'Native Cost', 'Profit %', 'Dealer Price', 'Selling %', 'Selling Price',
          'Status',
        ],
        for (final item in allItems) () {
          final cost = MoneyFormat.tryParse(item.nativeCostPrice);
          final profit = MoneyFormat.tryParse(item.profitPercentage);
          final selling = MoneyFormat.tryParse(item.sellingProfitPercentage);
          final dealerRaw = (cost != null && profit != null) ? cost * profit : null;
          final sellingRaw = (dealerRaw != null && selling != null) ? dealerRaw * selling : null;
          return [
            item.user?.label ?? '',
            item.brand?.label ?? '',
            item.brand?.code ?? '',
            item.brand?.currency ?? '',
            item.sector?.label ?? '',
            item.category?.label ?? '',
            item.product?.label ?? '',
            item.productType?.label ?? '',
            item.nativeCostPrice,
            item.profitPercentage,
            dealerRaw?.toStringAsFixed(4) ?? '',
            item.sellingProfitPercentage,
            sellingRaw?.toStringAsFixed(4) ?? '',
            item.deactivated ? 'Deactivated' : 'Active',
          ];
        }(),
      ];
      final csv = rows.map((r) => r.map(_csvEscape).join(',')).join('\r\n');
      await saveDownloadedFile(
        bytes: utf8.encode(csv),
        filename: 'user_brand_profit_export.csv',
        mimeType: 'text/csv',
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack(_cleanError(e));
    } finally {
      if (mounted) setState(() => _exportingCsv = false);
    }
  }

  String _selectionLabel(List<UserBrandProfitOption> items, int? id) {
    if (id == null) return 'All';
    for (final item in items) {
      if (item.id == id) return item.label;
    }
    return '#$id';
  }

  String _targetLabel() {
    if (_groupId != null) {
      return 'Group: ${_selectionLabel(_filters?.groups ?? const [], _groupId)}';
    }
    if (_userIds.isNotEmpty) {
      return _targetUsersLabel(_filters?.users ?? const []);
    }
    return 'All active users';
  }

  Future<void> _handleTargetGroupChanged(int? value) async {
    setState(() {
      _groupId = value;
      if (value != null) _userIds = <int>[];
      _page = 1;
    });
    await _loadFilters();
    await _loadList(page: 1);
  }

  Future<void> _handleTargetUsersChanged(List<int> values) async {
    setState(() {
      _userIds = values.toSet().toList()..sort();
      if (_userIds.isNotEmpty) _groupId = null;
      _page = 1;
    });
    await _loadList(page: 1);
  }

  Future<void> _handleSectorChanged(int? value) async {
    setState(() {
      _sectorId = value;
      _categoryId = null;
      _productId = null;
      _productTypeId = null;
      _brandId = null;
      _page = 1;
    });
    await _loadFilters();
    await _loadList(page: 1);
  }

  Future<void> _handleCategoryChanged(int? value) async {
    setState(() {
      _categoryId = value;
      _productId = null;
      _productTypeId = null;
      _brandId = null;
      _page = 1;
    });
    await _loadFilters();
    await _loadList(page: 1);
  }

  Future<void> _handleProductChanged(String? key) async {
    setState(() {
      _applyProductFilterKey(key);
      _productTypeId = null;
      _brandId = null;
      _page = 1;
    });
    await _loadFilters();
    await _loadList(page: 1);
  }

  Future<void> _handleProductTypeChanged(int? value) async {
    setState(() {
      _productTypeId = value;
      _brandId = null;
      _page = 1;
    });
    await _loadFilters();
    await _loadList(page: 1);
  }

  Future<void> _handleBrandChanged(int? value) async {
    setState(() {
      _brandId = value;
      _page = 1;
    });
    await _loadFilters();
    await _loadList(page: 1);
  }

  Future<void> _handleDeactivatedChanged(bool? value) async {
    setState(() {
      _deactivated = value;
      _page = 1;
    });
    await _loadList(page: 1);
  }

  Future<bool> _confirmDialog({
    required String title,
    required String message,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  )
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _submitStandardUpsert() async {
    final scope = _targetLabel();
    final brandScope = [
      if (_sectorId != null) 'sector',
      if (_categoryId != null) 'category',
      if (_productId != null || _productPrefix != null) 'product',
      if (_productTypeId != null) 'product type',
      if (_brandId != null) 'brand',
    ].join(', ');

    final message = _groupId == null && _userIds.isEmpty
        ? 'This will target ALL active users using standard percentages. Continue?'
        : 'Target: $scope\n\nApply standard percentages?';

    final confirmed = await _confirmDialog(
      title: 'Apply standard percentages',
      message: brandScope.isEmpty ? message : '$message\n\nBrand filters: $brandScope',
    );
    if (!confirmed) return;

    setState(() {
      _submittingStandard = true;
      _error = null;
    });

    try {
      final response = await _service.bulkUpsert(
        groupId: _groupId,
        userIds: _userIds,
        sectorId: _sectorId,
        categoryId: _categoryId,
        productId: _productId,
        productPrefix: _productPrefix,
        productTypeId: _productTypeId,
        brandId: _brandId,
        overrideExisting: _overrideExisting,
        useStandardPercentage: true,
      );
      if (!mounted) return;

      final summary = response.summary;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Standard percentages applied'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(response.message),
              const SizedBox(height: 12),
              Text('Target users: ${summary['target_user_count'] ?? 0}'),
              Text('Matched brands: ${summary['matched_brand_count'] ?? 0}'),
              Text('Created: ${summary['created_count'] ?? 0}'),
              Text('Updated: ${summary['updated_count'] ?? 0}'),
              Text('Skipped existing: ${summary['skipped_existing_count'] ?? 0}'),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      await _loadFilters();
      await _loadList(page: 1);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _cleanError(e));
      _showSnack(_cleanError(e));
    } finally {
      if (mounted) setState(() => _submittingStandard = false);
    }
  }

  Future<void> _submitBulkUpsert() async {
    final profit = _profitCtl.text.trim();
    final selling = _sellingProfitCtl.text.trim();

    if (profit.isEmpty || selling.isEmpty) {
      _showSnack('Profit percentage and selling profit percentage are required.');
      return;
    }

    final scope = _targetLabel();
    final brandScope = [
      if (_sectorId != null) 'sector',
      if (_categoryId != null) 'category',
      if (_productId != null || _productPrefix != null) 'product',
      if (_productTypeId != null) 'product type',
      if (_brandId != null) 'brand',
    ].join(', ');

    final message = _groupId == null && _userIds.isEmpty
        ? 'This will target ALL active users. Continue?'
        : 'Target: $scope\n\nContinue with bulk apply?';

    final confirmed = await _confirmDialog(
      title: 'Apply user-brand profit override',
      message: brandScope.isEmpty ? message : '$message\n\nBrand filters: $brandScope',
    );
    if (!confirmed) return;

    setState(() {
      _submittingBulk = true;
      _error = null;
    });

    try {
      final response = await _service.bulkUpsert(
        groupId: _groupId,
        userIds: _userIds,
        sectorId: _sectorId,
        categoryId: _categoryId,
        productId: _productId,
        productPrefix: _productPrefix,
        productTypeId: _productTypeId,
        brandId: _brandId,
        profitPercentage: profit,
        sellingProfitPercentage: selling,
        overrideExisting: _overrideExisting,
      );
      if (!mounted) return;

      final summary = response.summary;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Bulk apply completed'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(response.message),
              const SizedBox(height: 12),
              Text('Target users: ${summary['target_user_count'] ?? 0}'),
              Text('Matched brands: ${summary['matched_brand_count'] ?? 0}'),
              Text('Created: ${summary['created_count'] ?? 0}'),
              Text('Updated: ${summary['updated_count'] ?? 0}'),
              Text('Skipped existing: ${summary['skipped_existing_count'] ?? 0}'),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      await _loadFilters();
      await _loadList(page: 1);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _cleanError(e));
      _showSnack(_cleanError(e));
    } finally {
      if (mounted) setState(() => _submittingBulk = false);
    }
  }

  Future<void> _deleteItem(UserBrandProfitItem item) async {
    final confirmed = await _confirmDialog(
      title: 'Delete override',
      message:
          'Delete the override for ${item.user?.label ?? 'user'} / ${item.brand?.label ?? 'brand'}?',
      destructive: true,
    );
    if (!confirmed) return;

    try {
      await _service.delete(item.id);
      if (!mounted) return;
      _showSnack('Override deleted.');
      await _loadList(page: 1);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _cleanError(e));
      _showSnack(_cleanError(e));
    }
  }

  Future<void> _openEditDialog(UserBrandProfitItem item) async {
    final detail = await (() async {
      try {
        return await _service.detail(item.id);
      } catch (_) {
        return item;
      }
    })();

    if (!mounted) return;

    final profitCtl = TextEditingController(text: detail.profitPercentage);
    final sellingCtl = TextEditingController(text: detail.sellingProfitPercentage);
    final roundCtl = TextEditingController(text: detail.roundDealerPrice);
    final defaultSellingCtl = TextEditingController(text: detail.defaultSellingPrice);
    final nativeDealerCtl = TextEditingController(text: detail.nativeDealerPrice);
    final nativeCustomerCtl = TextEditingController(text: detail.nativeCustomerPrice);
    bool deactivated = detail.deactivated;
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              title: Text(
                '${detail.user?.label ?? 'User'} × ${detail.brand?.label ?? 'Brand'}',
              ),
              content: SizedBox(
                width: 540,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${detail.sector?.label ?? '-'} / ${detail.category?.label ?? '-'} / ${detail.product?.label ?? '-'} / ${detail.productType?.label ?? '-'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      _decimalField('Profit percentage', profitCtl),
                      const SizedBox(height: 10),
                      _decimalField('Selling profit percentage', sellingCtl),
                      const SizedBox(height: 10),
                      _decimalField('Round dealer price', roundCtl),
                      const SizedBox(height: 10),
                      _decimalField('Default selling price', defaultSellingCtl),
                      const SizedBox(height: 10),
                      _decimalField('Native dealer price', nativeDealerCtl),
                      const SizedBox(height: 10),
                      _decimalField('Native customer price', nativeCustomerCtl),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Deactivated'),
                        value: deactivated,
                        onChanged: saving
                            ? null
                            : (v) => setModalState(() => deactivated = v),
                      ),
                      if (detail.brandDefaults.isNotEmpty) ...[
                        const Divider(height: 24),
                        Text(
                          'Brand defaults',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        ...detail.brandDefaults.entries.map(
                          (entry) => Text('${entry.key}: ${entry.value}'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          setModalState(() => saving = true);
                          try {
                            await _service.update(
                              item.id,
                              <String, dynamic>{
                                'profit_percentage': profitCtl.text.trim(),
                                'selling_profit_percentage': sellingCtl.text.trim(),
                                'round_dealer_price': roundCtl.text.trim(),
                                'default_selling_price': defaultSellingCtl.text.trim(),
                                'native_dealer_price': nativeDealerCtl.text.trim(),
                                'native_customer_price': nativeCustomerCtl.text.trim(),
                                'deactivated': deactivated,
                              },
                            );
                            if (!mounted) return;
                            if (ctx.mounted) Navigator.pop(ctx);
                            _showSnack('Override updated.');
                            await _loadList(page: _page);
                          } catch (e) {
                            if (!mounted) return;
                            setState(() => _error = _cleanError(e));
                            _showSnack(_cleanError(e));
                            setModalState(() => saving = false);
                          }
                        },
                  child: Text(saving ? 'Saving…' : 'Save'),
                ),
              ],
            );
          },
        );
      },
    );

    profitCtl.dispose();
    sellingCtl.dispose();
    roundCtl.dispose();
    defaultSellingCtl.dispose();
    nativeDealerCtl.dispose();
    nativeCustomerCtl.dispose();
  }

  Widget _decimalField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 12),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9\.]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

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
                'User X Brand profit',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: _fg,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Manage user-brand profit overrides with the same admin flow used by the backend.',
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onPressed: _loadingFilters || _loadingList
                  ? null
                  : () {
                      _clearFilters();
                    },
              icon: const Icon(Icons.filter_alt_off, size: 18),
              label: const Text('Clear', style: TextStyle(fontSize: 12)),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onPressed: _exportingCsv ? null : _exportCsv,
              icon: _exportingCsv
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined, size: 18),
              label: Text(
                _exportingCsv ? 'Exporting…' : 'Export CSV',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onPressed: _loadingFilters || _loadingList
                  ? null
                  : () {
                      _refreshAll();
                    },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ],
    );
  }

  List<String> _activeFilterLabels() {
    final filters = _filters;
    if (filters == null) return const <String>[];

    final chips = <String>[];
    void add(String label, String value) {
      chips.add('$label: $value');
    }

    if (_groupId != null) add('Group', _selectionLabel(filters.groups, _groupId));
    if (_userIds.isNotEmpty) add('Users', _selectedUsersSummary(filters.users));
    if (_sectorId != null) add('Sector', _selectionLabel(filters.sectors, _sectorId));
    if (_categoryId != null) {
      add('Category', _selectionLabel(filters.categories, _categoryId));
    }
    if (_productId != null || _productPrefix != null) {
      add('Product', _productFilterLabel(filters.products));
    }
    if (_productTypeId != null) {
      add('Product type', _selectionLabel(filters.productTypes, _productTypeId));
    }
    if (_brandId != null) add('Brand', _selectionLabel(filters.brands, _brandId));
    if (_deactivated != null) add('Status', _deactivated! ? 'Deactivated' : 'Active');
    if (_searchCtl.text.trim().isNotEmpty) add('Search', _searchCtl.text.trim());
    return chips;
  }

  Widget _buildFiltersSummaryBar() {
    final chips = _activeFilterLabels();
    if (chips.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withValues(alpha: .20)),
        ),
        child: Text(
          'Showing all user-brand profit overrides',
          style: TextStyle(
            color: _fgSoft,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withValues(alpha: .18)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Text(
            'Active filters:',
            style: TextStyle(
              color: _fg,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          ...chips.map(
            (chip) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.blue.withValues(alpha: .18)),
              ),
              child: Text(
                chip,
                style: TextStyle(
                  color: _fg,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScopeAndFiltersCard(BuildContext context) {
    final filters = _filters;

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

            Widget box(Widget child) => SizedBox(width: fieldWidth, child: child);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Scope & filters',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: _fg,
                            ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: .06),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.red.withValues(alpha: .18)),
                      ),
                      child: Text(
                        'Target: ${_targetLabel()}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFD32F2F),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Group and users are mutually exclusive. Selecting one clears the other to keep the target explicit.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: _fgSoft,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    box(
                      _SearchableDropdownField<int>(
                        label: 'Group',
                        hintText: 'All groups',
                        value: _groupId,
                        options: _optionsFrom(filters?.groups ?? const []),
                        onChanged: (v) {
                          _handleTargetGroupChanged(v);
                        },
                      ),
                    ),
                    box(
                      _SearchableMultiSelectField<int>(
                        label: 'Users',
                        hintText: 'All users',
                        values: _userIds,
                        options: _optionsFrom(filters?.users ?? const []),
                        onChanged: (v) {
                          _handleTargetUsersChanged(v);
                        },
                      ),
                    ),
                    box(
                      _SearchableDropdownField<int>(
                        label: 'Sector',
                        hintText: 'All sectors',
                        value: _sectorId,
                        options: _optionsFrom(filters?.sectors ?? const []),
                        onChanged: (v) {
                          _handleSectorChanged(v);
                        },
                      ),
                    ),
                    box(
                      _SearchableDropdownField<int>(
                        label: 'Category',
                        hintText: 'All categories',
                        value: _categoryId,
                        options: _optionsFrom(filters?.categories ?? const []),
                        onChanged: (v) {
                          _handleCategoryChanged(v);
                        },
                      ),
                    ),
                    box(
                      _SearchableDropdownField<String>(
                        label: 'Product',
                        hintText: 'All products',
                        value: _productFilterKey(),
                        options: _productOptions(filters?.products ?? const []),
                        onChanged: (v) {
                          _handleProductChanged(v);
                        },
                      ),
                    ),
                    box(
                      _SearchableDropdownField<int>(
                        label: 'Product type',
                        hintText: 'All product types',
                        value: _productTypeId,
                        options: _optionsFrom(filters?.productTypes ?? const []),
                        onChanged: (v) {
                          _handleProductTypeChanged(v);
                        },
                      ),
                    ),
                    box(
                      _SearchableDropdownField<int>(
                        label: 'Brand',
                        hintText: 'All brands',
                        value: _brandId,
                        options: _optionsFrom(filters?.brands ?? const []),
                        onChanged: (v) {
                          _handleBrandChanged(v);
                        },
                      ),
                    ),
                    box(
                      _SearchableDropdownField<bool>(
                        label: 'Status',
                        hintText: 'All statuses',
                        value: _deactivated,
                        options: _deactivatedOptions(),
                        onChanged: (v) {
                          _handleDeactivatedChanged(v);
                        },
                      ),
                    ),
                    box(
                      TextField(
                        controller: _searchCtl,
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          labelText: 'Search',
                          hintText: 'Search existing rows',
                          isDense: true,
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: _searchCtl.text.trim().isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: () async {
                                    setState(() {
                                      _searchCtl.clear();
                                      _page = 1;
                                    });
                                    await _loadList(page: 1);
                                  },
                                  icon: const Icon(Icons.clear, size: 18),
                                ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onSubmitted: (_) {
                          _loadList(page: 1);
                        },
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildFiltersSummaryBar(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBulkApplyCard(BuildContext context) {
    return _sectionCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bulk apply',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: _fg,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Current scope: ${_targetLabel()}',
              style: TextStyle(
                fontSize: 11.5,
                color: _fgSoft,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final twoCols = width >= 700;
                final fieldWidth = twoCols ? (width - 10) / 2 : width;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(width: fieldWidth, child: _decimalField('Profit percentage', _profitCtl)),
                    SizedBox(
                      width: fieldWidth,
                      child: _decimalField('Selling profit percentage', _sellingProfitCtl),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              dense: true,
              visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Override existing rows',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                'When off, existing overrides are skipped.',
                style: TextStyle(fontSize: 11.5, color: _fgSoft),
              ),
              value: _overrideExisting,
              onChanged: _submittingBulk ? null : (v) => setState(() => _overrideExisting = v),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  ),
                  onPressed: _submittingBulk || _submittingStandard
                      ? null
                      : _submitStandardUpsert,
                  icon: const Icon(Icons.percent, size: 18),
                  label: Text(
                    _submittingStandard ? 'Applying…' : 'Use Standard %',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  ),
                  onPressed: _submittingBulk || _submittingStandard
                      ? null
                      : _submitBulkUpsert,
                  icon: const Icon(Icons.playlist_add_check_circle_outlined, size: 18),
                  label: Text(
                    _submittingBulk ? 'Applying…' : 'Apply bulk override',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListCard(BuildContext context) {
    final items = _items;

    return _sectionCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Existing overrides',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: _fg,
                        ),
                  ),
                ),
                Text(
                  'Total $_total',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: _fgSoft,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_loadingList)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (items.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: const Text(
                  'No overrides found for the current filters.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 920) {
                    return Column(
                      children: [
                        for (final item in items) _buildMobileItemCard(context, item),
                      ],
                    );
                  }
                  return _buildDesktopTable(context, items, constraints.maxWidth);
                },
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Showing ${_items.length} of $_total',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: _fgSoft,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_loadingMore)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileItemCard(BuildContext context, UserBrandProfitItem item) {
    final subtitle = [
      item.sector?.label,
      item.category?.label,
      item.product?.label,
      item.productType?.label,
    ].whereType<String>().where((e) => e.trim().isNotEmpty).join(' / ');

    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _UserBrandProfitStatusRail(
              label: item.deactivated ? 'OFF' : 'ON',
              color: _userBrandProfitStatusColor(item.deactivated),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.user?.label ?? 'User',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.brand?.label ?? 'Brand',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _fg,
                                  fontWeight: FontWeight.w700,
                                  height: 1.18,
                                ),
                              ),
                              if (subtitle.isNotEmpty) ...[
                                const SizedBox(height: 5),
                                Text(
                                  subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _fgSoft,
                                    fontSize: 11.2,
                                    height: 1.18,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        _UserBrandProfitValuePill(
                          label: 'Currency',
                          value: (item.brand?.currency ?? '').isNotEmpty
                              ? item.brand!.currency!
                              : '-',
                          color: const Color(0xFF2563EB),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _UserBrandProfitMetaChip(
                          label: 'Cost',
                          value: _displayCostPrice(item),
                          textColor: const Color(0xFFD32F2F),
                          borderColor: const Color(0xFFD32F2F),
                        ),
                        _UserBrandProfitMetaChip(
                          label: 'Profit %',
                          value: item.profitPercentage,
                          textColor: const Color(0xFF1E7E34),
                          borderColor: const Color(0xFF1E7E34),
                        ),
                        _UserBrandProfitMetaChip(
                          label: 'Dealer',
                          value: _displayDealerPrice(item),
                          textColor: const Color(0xFFD32F2F),
                          borderColor: const Color(0xFFD32F2F),
                        ),
                        _UserBrandProfitMetaChip(
                          label: 'Selling %',
                          value: item.sellingProfitPercentage,
                          textColor: const Color(0xFF1E7E34),
                          borderColor: const Color(0xFF1E7E34),
                        ),
                        _UserBrandProfitMetaChip(
                          label: 'Customer',
                          value: _displaySellingPrice(item),
                          textColor: const Color(0xFFD32F2F),
                          borderColor: const Color(0xFFD32F2F),
                        ),
                        _UserBrandProfitMetaChip(
                          label: 'Status',
                          value: item.deactivated ? 'Deactivated' : 'Active',
                          textColor: _userBrandProfitStatusColor(item.deactivated),
                          borderColor: _userBrandProfitStatusColor(item.deactivated),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                          ),
                          onPressed: () {
                            _openEditDialog(item);
                          },
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Edit', style: TextStyle(fontSize: 12)),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.error,
                            foregroundColor: Theme.of(context).colorScheme.onError,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                          ),
                          onPressed: () {
                            _deleteItem(item);
                          },
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Delete', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopTable(
    BuildContext context,
    List<UserBrandProfitItem> items,
    double maxWidth,
  ) {
    final cols = <_UserBrandProfitGridCol>[
      _UserBrandProfitGridCol(
        key: 'status_rail',
        label: 'Status',
        width: 30,
        align: TextAlign.center,
        cell: (e) => e.deactivated ? 'OFF' : 'ON',
      ),
      _UserBrandProfitGridCol(
        key: 'user',
        label: 'User',
        width: 150,
        align: TextAlign.left,
        cell: (e) => e.user?.label ?? '-',
      ),
      _UserBrandProfitGridCol(
        key: 'brand',
        label: 'Brand',
        width: 200,
        align: TextAlign.left,
        cell: (e) => [
          e.brand?.label ?? '-',
          if ((e.brand?.code ?? '').isNotEmpty) '(${e.brand!.code})',
        ].join(' '),
      ),
      _UserBrandProfitGridCol(
        key: 'path',
        label: 'Path',
        width: 250,
        align: TextAlign.left,
        cell: (e) => [
          e.sector?.label,
          e.category?.label,
          e.product?.label,
          e.productType?.label,
        ].whereType<String>().where((v) => v.trim().isNotEmpty).join(' / '),
      ),
      _UserBrandProfitGridCol(
        key: 'native_cost',
        label: 'Native Cost',
        width: 90,
        align: TextAlign.right,
        cell: (e) => _displayCostPrice(e),
        cellStyle: (_) => const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF374151),
          height: 1.15,
        ),
      ),
      _UserBrandProfitGridCol(
        key: 'profit',
        label: 'Profit %',
        width: 84,
        align: TextAlign.right,
        cell: (e) => e.profitPercentage,
        cellStyle: (_) => const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
          color: Color(0xFF1E7E34),
          height: 1.15,
        ),
      ),
      _UserBrandProfitGridCol(
        key: 'dealer_price',
        label: 'Dealer Price',
        width: 90,
        align: TextAlign.right,
        cell: (e) => _displayDealerPrice(e),
        cellStyle: (_) => const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF374151),
          height: 1.15,
        ),
      ),
      _UserBrandProfitGridCol(
        key: 'selling',
        label: 'Selling %',
        width: 84,
        align: TextAlign.right,
        cell: (e) => e.sellingProfitPercentage,
        cellStyle: (_) => const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
          color: Color(0xFF1E7E34),
          height: 1.15,
        ),
      ),
      _UserBrandProfitGridCol(
        key: 'selling_price',
        label: 'Selling Price',
        width: 90,
        align: TextAlign.right,
        cell: (e) => _displaySellingPrice(e),
        cellStyle: (_) => const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF374151),
          height: 1.15,
        ),
      ),
      _UserBrandProfitGridCol(
        key: 'currency',
        label: 'Currency',
        width: 72,
        align: TextAlign.center,
        cell: (e) => e.brand?.currency ?? '-',
        cellStyle: (_) => const TextStyle(
          fontSize: 11.3,
          fontWeight: FontWeight.w800,
          color: Color(0xFF2563EB),
          height: 1.15,
        ),
      ),
      _UserBrandProfitGridCol(
        key: 'status_text',
        label: 'Status',
        width: 96,
        align: TextAlign.center,
        cell: (e) => e.deactivated ? 'Deactivated' : 'Active',
        cellStyle: (e) => TextStyle(
          fontSize: 11.3,
          fontWeight: FontWeight.w800,
          color: _userBrandProfitStatusColor(e.deactivated),
          height: 1.15,
        ),
      ),
      _UserBrandProfitGridCol(
        key: 'actions',
        label: 'Actions',
        width: 110,
        align: TextAlign.center,
        cell: (_) => '',
      ),
    ];

    final baseTableW = cols.fold<double>(0, (sum, col) => sum + col.width) + 2;
    final extraWidth = maxWidth > baseTableW ? maxWidth - baseTableW : 0.0;
    final effectiveCols = extraWidth > 0
        ? [
            ...cols.take(cols.length - 2),
            _UserBrandProfitGridCol(
              key: cols[cols.length - 2].key,
              label: cols[cols.length - 2].label,
              width: cols[cols.length - 2].width + extraWidth,
              align: cols[cols.length - 2].align,
              cell: cols[cols.length - 2].cell,
              cellStyle: cols[cols.length - 2].cellStyle,
            ),
            cols.last,
          ]
        : cols;
    final tableW = effectiveCols.fold<double>(0, (sum, col) => sum + col.width) + 2;
    final tableH = math.min(math.max(items.length * 46.0 + 44.0, 220.0), 460.0);

    Widget headerRow() {
      const headerRed = Color(0xFFD32F2F);
      const headerBg = Color(0xFFFFF2F2);
      final border = Colors.red.withValues(alpha: .25);

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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: effectiveCols.map((c) {
            if (c.key == 'status_rail') {
              return SizedBox(
                width: c.width,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Center(
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: Text(
                        c.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: headerRed,
                          fontWeight: FontWeight.w900,
                          fontSize: 8.6,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }

            return SizedBox(
              width: c.width,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
                child: Text(
                  c.label,
                  textAlign: c.align,
                  style: const TextStyle(
                    color: headerRed,
                    fontWeight: FontWeight.w900,
                    fontSize: 10.2,
                    height: 1.15,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      );
    }

    Widget row(UserBrandProfitItem item, int index) {
      final border = Colors.red.withValues(alpha: .16);
      final statusColor = _userBrandProfitStatusColor(item.deactivated);
      final zebra = index.isEven ? Colors.white : Colors.grey.withValues(alpha: .028);

      return Container(
        width: tableW,
        decoration: BoxDecoration(
          color: zebra,
          border: Border(bottom: BorderSide(color: border)),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: effectiveCols.map((c) {
              if (c.key == 'status_rail') {
                return Container(
                  width: c.width,
                  color: statusColor.withValues(alpha: .10),
                  alignment: Alignment.center,
                  child: RotatedBox(
                    quarterTurns: -1,
                    child: Text(
                      c.cell(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .35,
                        color: statusColor,
                      ),
                    ),
                  ),
                );
              }

              if (c.key == 'actions') {
                return SizedBox(
                  width: c.width,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: 'Edit',
                          visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
                          iconSize: 18,
                          onPressed: () {
                            _openEditDialog(item);
                          },
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
                          iconSize: 18,
                          onPressed: () {
                            _deleteItem(item);
                          },
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final style = c.cellStyle?.call(item) ?? TextStyle(
                fontSize: 11.6,
                color: _fg,
                fontWeight: FontWeight.w600,
                height: 1.16,
              );

              return SizedBox(
                width: c.width,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Text(
                    c.cell(item),
                    textAlign: c.align,
                    softWrap: true,
                    style: style,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      );
    }

    return Scrollbar(
      controller: _hListCtl,
      thumbVisibility: true,
      trackVisibility: true,
      notificationPredicate: (notification) => notification.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        controller: _hListCtl,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: tableW,
          height: tableH,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withValues(alpha: .20)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                headerRow(),
                Expanded(
                  child: Scrollbar(
                    controller: _vListCtl,
                    thumbVisibility: true,
                    trackVisibility: true,
                    notificationPredicate: (notification) => notification.metrics.axis == Axis.vertical,
                    child: ListView.builder(
                      controller: _vListCtl,
                      itemCount: items.length,
                      itemBuilder: (context, index) => row(items[index], index),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final actions = <PageAction>[
      PageAction(label: 'Refresh', icon: Icons.refresh, onTap: () {
        _refreshAll();
      }),
      PageAction(label: 'Clear', icon: Icons.filter_alt_off, onTap: () {
        _clearFilters();
      }),
      PageAction(label: 'Export CSV', icon: Icons.download_outlined, onTap: () {
        _exportCsv();
      }),
    ];

    if (!session.isAdmin) {
      return _buildAccessDenied(context);
    }

    return MouseRegion(
      cursor: (_submittingBulk || _submittingStandard)
          ? SystemMouseCursors.wait
          : MouseCursor.defer,
      child: PageActions(
      actions: actions,
      child: ScrollConfiguration(
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
              if (_loadingFilters) ...[
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
              const SizedBox(height: 12),
              _buildScopeAndFiltersCard(context),
              const SizedBox(height: 12),
              _buildBulkApplyCard(context),
              const SizedBox(height: 12),
              _buildListCard(context),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }
}

Color _userBrandProfitStatusColor(bool deactivated) {
  return deactivated ? const Color(0xFFD32F2F) : const Color(0xFF1E7E34);
}

class _UserBrandProfitGridCol {
  final String key;
  final String label;
  final double width;
  final TextAlign align;
  final String Function(UserBrandProfitItem item) cell;
  final TextStyle? Function(UserBrandProfitItem item)? cellStyle;

  const _UserBrandProfitGridCol({
    required this.key,
    required this.label,
    required this.width,
    required this.align,
    required this.cell,
    this.cellStyle,
  });
}

class _UserBrandProfitStatusRail extends StatelessWidget {
  final String label;
  final Color color;

  const _UserBrandProfitStatusRail({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
        border: Border(
          right: BorderSide(color: color.withValues(alpha: .35)),
        ),
      ),
      child: Center(
        child: RotatedBox(
          quarterTurns: -1,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: .4,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _UserBrandProfitValuePill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _UserBrandProfitValuePill({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFFD32F2F),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _UserBrandProfitMetaChip extends StatelessWidget {
  final String label;
  final String value;
  final Color textColor;
  final Color borderColor;

  const _UserBrandProfitMetaChip({
    required this.label,
    required this.value,
    required this.textColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: borderColor.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor.withValues(alpha: .20)),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            color: textColor,
            fontSize: 11.3,
            fontWeight: FontWeight.w700,
          ),
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}
