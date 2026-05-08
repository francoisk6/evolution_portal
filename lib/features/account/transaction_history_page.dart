import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../app/app_scroll_behavior.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/transaction_history.dart';
import '../../services/api_service.dart';
import '../../services/transaction_service.dart';
import '../../state/transaction_history_provider.dart';
import '../../state/session_provider.dart';
import '../../state/page_refresh_provider.dart';
import '../../utils/money_format.dart';
import '../../utils/note_actions.dart';
import '../../utils/note_pretty.dart';
import '../../utils/file_download.dart';
import '../../widgets/page_action_bar.dart'
    show PageActions, PageAction, pageActions;

class TransactionHistoryPage extends ConsumerStatefulWidget {
  const TransactionHistoryPage({super.key});

  @override
  ConsumerState<TransactionHistoryPage> createState() =>
      _TransactionHistoryPageState();
}

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
  final double? menuHeight;

  const _SearchableDropdownField({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.hintText,
    this.allLabel = 'All',
    this.menuHeight,
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

        return EvolutionPopupScrollScope(
          child: FractionallySizedBox(
            heightFactor: 0.72,
            child: StatefulBuilder(
              builder: (context, setState) {
                final query = searchCtl.text.trim().toLowerCase();
                final filtered = query.isEmpty
                    ? options
                    : options.where((option) {
                        final label = option.label.toLowerCase();
                        return label.contains(query);
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
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
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
                                  const Icon(Icons.backspace_outlined,
                                      size: 18),
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
                                : ListView.separated(
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
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: selected
                                                          ? FontWeight.w700
                                                          : FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                                if (selected)
                                                  Icon(
                                                    Icons.check,
                                                    size: 18,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary,
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
                      ],
                    ),
                  ),
                );
              },
            ),
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
    final hasValue = selectedLabel != null && selectedLabel.trim().isNotEmpty;
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openPicker(context),
        child: InputDecorator(
          decoration: InputDecoration(
            isDense: true,
            labelText: label,
            labelStyle: const TextStyle(fontSize: 11.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 9,
            ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 54,
              minHeight: 32,
            ),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (value != null)
                  IconButton(
                    tooltip: 'Clear',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => onChanged(null),
                  ),
                const Icon(Icons.arrow_drop_down, size: 20),
                const SizedBox(width: 4),
              ],
            ),
          ),
          child: Text(
            hasValue ? selectedLabel : (hintText ?? allLabel),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: hasValue ? theme.colorScheme.onSurface : theme.hintColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _TransactionHistoryPageState
    extends ConsumerState<TransactionHistoryPage> {
  static const _fg = Color(0xFF444444);
  static const _fgSoft = Color(0xFF666666);

  bool _summaryExpanded = true;
  bool _isExporting = false;

  // Separate controllers for cards vs grid to avoid "attached to multiple scroll views"
  // when resizing the web window.
  final _vCardsCtl = ScrollController();
  final _vGridCtl = ScrollController();

  final _hSummaryCtl = ScrollController();

  // Single horizontal controller for the grid (header + body share one viewport).
  final _hGridCtl = ScrollController();

  @override
  void initState() {
    super.initState();

    _vCardsCtl.addListener(() => _onScroll(_vCardsCtl));
    _vGridCtl.addListener(() => _onScroll(_vGridCtl));

    Future.microtask(
        () => ref.read(transactionHistoryProvider.notifier).refresh());
  }

  @override
  void dispose() {
    _vCardsCtl.dispose();
    _vGridCtl.dispose();
    _hSummaryCtl.dispose();
    _hGridCtl.dispose();
    super.dispose();
  }

  void _onScroll(ScrollController ctl) {
    if (!ctl.hasClients) return;
    final pos = ctl.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels >= pos.maxScrollExtent * 0.7) {
      ref.read(transactionHistoryProvider.notifier).fetchMore();
    }
  }

  String? _fmtYmd(DateTime? value) {
    if (value == null) return null;
    return DateFormat('yyyy-MM-dd').format(value);
  }

  Future<void> _exportToExcel() async {
    if (_isExporting) return;

    final cancelToken = DownloadCancelToken();
    bool dialogOpen = true;

    setState(() => _isExporting = true);

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return WillPopScope(
            onWillPop: () async => false,
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text('Exporting to Excel'),
              content: const Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Please wait while the Excel file is being generated.',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton.icon(
                  onPressed: () {
                    dialogOpen = false;
                    cancelToken.cancel();
                    Navigator.of(dialogContext).pop();
                  },
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel'),
                ),
              ],
            ),
          );
        },
      ).then((_) {
        dialogOpen = false;
      }),
    );

    try {
      final filters = ref.read(transactionHistoryProvider).filters;
      final file = await TransactionService.instance.exportExcel(
        dateFrom: _fmtYmd(filters.from),
        dateTo: _fmtYmd(filters.to),
        currency: filters.currency,
        status: filters.status,
        q: filters.q,
        userId: filters.userId,
        sectorId: filters.sectorId,
        productId: filters.productId,
        brandId: filters.brandId,
        brandNotNull: filters.brandNotNull,
        cancelToken: cancelToken,
      );

      final saved = await saveDownloadedFile(
        bytes: file.bytes,
        filename: file.filename,
        mimeType: file.contentType,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? 'Excel export started: ${file.filename}'
                : 'Excel file ready: ${file.filename}',
          ),
        ),
      );
    } on DownloadCancelledException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Excel export cancelled.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to export Excel: $e')),
      );
    } finally {
      if (mounted && dialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _openFilters() async {
    final currentPageActions = List<PageAction>.from(pageActions.value);
    pageActions.value = const <PageAction>[];

    final state = ref.read(transactionHistoryProvider);
    final current = state.filters;
    final available = state.availableFilters;
    final df = DateFormat('yyyy-MM-dd');

    final fromCtl = TextEditingController(
        text: current.from == null ? '' : df.format(current.from!));
    final toCtl = TextEditingController(
        text: current.to == null ? '' : df.format(current.to!));
    final qCtl = TextEditingController(text: current.q ?? '');

    String? currency =
        (current.currency?.trim().isEmpty ?? true) ? null : current.currency;
    String? status =
        (current.status?.trim().isEmpty ?? true) ? null : current.status;
    int? userId = current.userId;
    int? sectorId = current.sectorId;
    int? productId = current.productId;
    int? brandId = current.brandId;
    bool brandNotNull = current.brandNotNull == true;

    final currencySet = <String>{};
    if (currency != null && currency.trim().isNotEmpty) {
      currencySet.add(currency.trim().toUpperCase());
    }
    currencySet.addAll(
      state.summary?.totals.keys
              .map((e) => e.trim().toUpperCase())
              .where((e) => e.isNotEmpty) ??
          const <String>[],
    );
    currencySet.addAll(
      state.items
          .map((e) => e.currency.trim().toUpperCase())
          .where((e) => e.isNotEmpty),
    );
    if (currencySet.isEmpty) {
      currencySet.addAll(const ['LBP', 'USD']);
    }
    final currencyOptions = currencySet.toList()..sort();

    final statusSet = <String>{};
    if (status != null && status.trim().isNotEmpty) {
      statusSet.add(status.trim());
    }
    statusSet.addAll(
      state.items.map((e) => e.status.trim()).where((e) => e.isNotEmpty),
    );
    if (statusSet.isEmpty) {
      statusSet.addAll(const ['Done', 'Under process', 'Failed']);
    }
    final statusOptions = statusSet.toList()..sort();

    bool productMatchesSector(int? selectedProductId, int? selectedSectorId) {
      if (selectedProductId == null || selectedSectorId == null) return true;
      TransactionFilterProductOption? product;
      for (final entry
          in available?.products ?? const <TransactionFilterProductOption>[]) {
        if (entry.id == selectedProductId) {
          product = entry;
          break;
        }
      }
      if (product == null || product.sectorId == null) return true;
      return product.sectorId == selectedSectorId;
    }

    bool brandMatchesSelection(
      int? selectedBrandId,
      int? selectedSectorId,
      int? selectedProductId,
    ) {
      if (selectedBrandId == null) return true;
      TransactionFilterBrandOption? brand;
      for (final entry
          in available?.brands ?? const <TransactionFilterBrandOption>[]) {
        if (entry.id == selectedBrandId) {
          brand = entry;
          break;
        }
      }
      if (brand == null) return true;
      if (selectedSectorId != null &&
          brand.sectorId != null &&
          brand.sectorId != selectedSectorId) {
        return false;
      }
      if (selectedProductId != null &&
          brand.productId != null &&
          brand.productId != selectedProductId) {
        return false;
      }
      return true;
    }

    List<TransactionFilterProductOption> filteredProducts(
        int? selectedSectorId) {
      final all =
          available?.products ?? const <TransactionFilterProductOption>[];
      if (selectedSectorId == null) return all;
      return all
          .where((e) => e.sectorId == null || e.sectorId == selectedSectorId)
          .toList();
    }

    List<TransactionFilterBrandOption> filteredBrands(
      int? selectedSectorId,
      int? selectedProductId,
    ) {
      final all = available?.brands ?? const <TransactionFilterBrandOption>[];
      return all.where((e) {
        final sectorOk = selectedSectorId == null ||
            e.sectorId == null ||
            e.sectorId == selectedSectorId;
        final productOk = selectedProductId == null ||
            e.productId == null ||
            e.productId == selectedProductId;
        return sectorOk && productOk;
      }).toList();
    }

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) {
          DateTime? parseYmd(String s) {
            final t = s.trim();
            if (t.isEmpty) return null;
            return DateTime.tryParse(t);
          }

          return StatefulBuilder(
            builder: (ctx, setModalState) {
              Future<void> pickDate({required bool isFrom}) async {
                final now = DateTime.now();
                final initial = isFrom
                    ? (parseYmd(fromCtl.text) ??
                        current.from ??
                        now.subtract(const Duration(days: 1)))
                    : (parseYmd(toCtl.text) ?? current.to ?? now);
                final d = await showDatePicker(
                  context: ctx,
                  firstDate: DateTime(now.year - 5),
                  lastDate: DateTime(now.year + 1),
                  initialDate: initial,
                );
                if (d == null) return;
                setModalState(() {
                  if (isFrom) {
                    fromCtl.text = df.format(d);
                  } else {
                    toCtl.text = df.format(d);
                  }
                });
              }

              void clearFilters() {
                setModalState(() {
                  fromCtl.clear();
                  toCtl.clear();
                  qCtl.clear();
                  currency = null;
                  status = null;
                  userId = null;
                  sectorId = null;
                  productId = null;
                  brandId = null;
                  brandNotNull = false;
                });
              }

              void applyFilters() {
                final next = TransactionFilters(
                  from: parseYmd(fromCtl.text),
                  to: parseYmd(toCtl.text),
                  currency: currency,
                  status: status,
                  q: qCtl.text.trim().isEmpty ? null : qCtl.text.trim(),
                  limit: current.limit,
                  userId: userId,
                  sectorId: sectorId,
                  productId: productId,
                  brandId: brandId,
                  brandNotNull: brandNotNull ? true : null,
                );
                ref.read(transactionHistoryProvider.notifier).setFilters(next);
                ref.read(transactionHistoryProvider.notifier).refresh();
                Navigator.pop(ctx);
              }

              Widget buildOverlayActions() {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FloatingActionButton.small(
                      heroTag: 'tx_filter_cancel',
                      tooltip: 'Cancel',
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      onPressed: () => Navigator.pop(ctx),
                      child: const Icon(Icons.close),
                    ),
                    const SizedBox(height: 10),
                    FloatingActionButton.small(
                      heroTag: 'tx_filter_clear',
                      tooltip: 'Clear',
                      backgroundColor: Colors.white,
                      foregroundColor: Theme.of(ctx).colorScheme.primary,
                      onPressed: clearFilters,
                      child: const Icon(Icons.backspace_outlined),
                    ),
                    const SizedBox(height: 10),
                    FloatingActionButton.small(
                      heroTag: 'tx_filter_apply',
                      tooltip: 'Apply',
                      onPressed: applyFilters,
                      child: const Icon(Icons.check),
                    ),
                  ],
                );
              }

              final productOptions = filteredProducts(sectorId);
              final brandOptions = filteredBrands(sectorId, productId);
              final showUserFilter =
                  (available?.users.isNotEmpty ?? false) || userId != null;
              final showSectorFilter = (available?.sectors.isNotEmpty ?? false);
              final showProductFilter = productOptions.isNotEmpty;
              final showBrandFilter = brandOptions.isNotEmpty;

              return EvolutionPopupScrollScope(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(ctx).viewInsets.bottom,
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(ctx).size.height * 0.88,
                        ),
                        child: Focus(
                          autofocus: true,
                          child: Stack(
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  right: 72,
                                  bottom: 12,
                                ),
                                child: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.filter_list),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Filter Transactions',
                                            style: Theme.of(ctx)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller: fromCtl,
                                              readOnly: true,
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                              ),
                                              decoration: InputDecoration(
                                                labelText: 'From (YYYY-MM-DD)',
                                                labelStyle: const TextStyle(
                                                  fontSize: 11.5,
                                                ),
                                                isDense: true,
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 10,
                                                ),
                                                suffixIcon: fromCtl.text.isEmpty
                                                    ? null
                                                    : IconButton(
                                                        tooltip: 'Clear',
                                                        icon: const Icon(
                                                          Icons.clear,
                                                        ),
                                                        onPressed: () {
                                                          setModalState(
                                                            () =>
                                                                fromCtl.clear(),
                                                          );
                                                        },
                                                      ),
                                              ),
                                              onTap: () =>
                                                  pickDate(isFrom: true),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: TextField(
                                              controller: toCtl,
                                              readOnly: true,
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                              ),
                                              decoration: InputDecoration(
                                                labelText: 'To (YYYY-MM-DD)',
                                                labelStyle: const TextStyle(
                                                  fontSize: 11.5,
                                                ),
                                                isDense: true,
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 10,
                                                ),
                                                suffixIcon: toCtl.text.isEmpty
                                                    ? null
                                                    : IconButton(
                                                        tooltip: 'Clear',
                                                        icon: const Icon(
                                                          Icons.clear,
                                                        ),
                                                        onPressed: () {
                                                          setModalState(
                                                            () => toCtl.clear(),
                                                          );
                                                        },
                                                      ),
                                              ),
                                              onTap: () =>
                                                  pickDate(isFrom: false),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: qCtl,
                                        style: const TextStyle(fontSize: 11.5),
                                        decoration: InputDecoration(
                                          labelText: 'Search',
                                          labelStyle:
                                              const TextStyle(fontSize: 11.5),
                                          isDense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 10,
                                          ),
                                          prefixIcon: const Icon(Icons.search,
                                              size: 18),
                                          suffixIcon: qCtl.text.isEmpty
                                              ? null
                                              : IconButton(
                                                  tooltip: 'Clear',
                                                  icon: const Icon(Icons.clear),
                                                  onPressed: () {
                                                    setModalState(
                                                      () => qCtl.clear(),
                                                    );
                                                  },
                                                ),
                                        ),
                                        onChanged: (_) => setModalState(() {}),
                                      ),
                                      if (showUserFilter) ...[
                                        const SizedBox(height: 8),
                                        _SearchableDropdownField<int>(
                                          label: 'User',
                                          hintText: 'All users',
                                          allLabel: 'All users',
                                          value: userId,
                                          options: available!.users
                                              .map(
                                                (e) => _ComboBoxOption<int>(
                                                  value: e.id,
                                                  label: e.label,
                                                ),
                                              )
                                              .toList(),
                                          onChanged: (v) =>
                                              setModalState(() => userId = v),
                                        ),
                                      ],
                                      const SizedBox(height: 8),
                                      _SearchableDropdownField<String>(
                                        label: 'Currency',
                                        hintText: 'All currencies',
                                        allLabel: 'All currencies',
                                        value: currency,
                                        options: currencyOptions
                                            .map(
                                              (e) => _ComboBoxOption<String>(
                                                value: e,
                                                label: e,
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (v) =>
                                            setModalState(() => currency = v),
                                      ),
                                      const SizedBox(height: 8),
                                      _SearchableDropdownField<String>(
                                        label: 'Status',
                                        hintText: 'All statuses',
                                        allLabel: 'All statuses',
                                        value: status,
                                        options: statusOptions
                                            .map(
                                              (e) => _ComboBoxOption<String>(
                                                value: e,
                                                label: e,
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (v) =>
                                            setModalState(() => status = v),
                                      ),
                                      if (showSectorFilter ||
                                          sectorId != null) ...[
                                        const SizedBox(height: 8),
                                        _SearchableDropdownField<int>(
                                          label: 'Sector',
                                          hintText: 'All sectors',
                                          allLabel: 'All sectors',
                                          value: sectorId,
                                          options: available!.sectors
                                              .map(
                                                (e) => _ComboBoxOption<int>(
                                                  value: e.id,
                                                  label: e.label,
                                                ),
                                              )
                                              .toList(),
                                          onChanged: (v) {
                                            setModalState(() {
                                              sectorId = v;
                                              if (!productMatchesSector(
                                                productId,
                                                sectorId,
                                              )) {
                                                productId = null;
                                              }
                                              if (!brandMatchesSelection(
                                                brandId,
                                                sectorId,
                                                productId,
                                              )) {
                                                brandId = null;
                                              }
                                            });
                                          },
                                        ),
                                      ],
                                      if (showProductFilter ||
                                          productId != null) ...[
                                        const SizedBox(height: 8),
                                        _SearchableDropdownField<int>(
                                          label: 'Product',
                                          hintText: 'All products',
                                          allLabel: 'All products',
                                          value: productId,
                                          options: productOptions
                                              .map(
                                                (e) => _ComboBoxOption<int>(
                                                  value: e.id,
                                                  label: e.label,
                                                ),
                                              )
                                              .toList(),
                                          onChanged: (v) {
                                            setModalState(() {
                                              productId = v;
                                              if (!brandMatchesSelection(
                                                brandId,
                                                sectorId,
                                                productId,
                                              )) {
                                                brandId = null;
                                              }
                                            });
                                          },
                                        ),
                                      ],
                                      if (showBrandFilter ||
                                          brandId != null) ...[
                                        const SizedBox(height: 8),
                                        _SearchableDropdownField<int>(
                                          label: 'Brand',
                                          hintText: 'All brands',
                                          allLabel: 'All brands',
                                          value: brandId,
                                          options: brandOptions
                                              .map(
                                                (e) => _ComboBoxOption<int>(
                                                  value: e.id,
                                                  label: e.label,
                                                ),
                                              )
                                              .toList(),
                                          onChanged: (v) => setModalState(
                                            () => brandId = v,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 8),
                                      CheckboxListTile(
                                        value: brandNotNull,
                                        contentPadding: EdgeInsets.zero,
                                        dense: true,
                                        controlAffinity:
                                            ListTileControlAffinity.leading,
                                        title: const Text(
                                          'Brand is not null',
                                          style: TextStyle(fontSize: 11.5),
                                        ),
                                        visualDensity: const VisualDensity(
                                          horizontal: -4,
                                          vertical: -4,
                                        ),
                                        onChanged: (v) => setModalState(
                                          () => brandNotNull = v == true,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: buildOverlayActions(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      if (mounted) {
        pageActions.value = currentPageActions;
      }
    }
  }

  Future<void> _openDetail(TransactionListItem item) async {
    try {
      final detail = await TransactionService.instance.detail(item.id);
      if (!mounted) return;

      // ─────────────────────────────────────────────────────────────
      // Online Purchase Order Check (before opening note)
      // Call when:
      //   - note is empty OR
      //   - note cannot be parsed into a JSON Map OR
      //   - note.status != "done"
      // Order number is the client number/pin.
      // ─────────────────────────────────────────────────────────────

      String normalizeOrderNumber(String s) {
        final t = s.trim();
        if (t.isEmpty) return '';
        return t.startsWith('#') ? t : '#$t';
      }

      bool isNoteEmpty(dynamic note) {
        if (note == null) return true;
        if (note is String) {
          final s = note.trim();
          if (s.isEmpty) return true;
          if (s == '-' || s.toLowerCase() == 'null') return true;
          if (s == '{}' || s == '[]') return true;
          return false;
        }
        if (note is Map) return note.isEmpty;
        if (note is List) return note.isEmpty;
        return false;
      }

      dynamic tryDecodeJsonish(String s) {
        final t = s.trim();
        if (t.isEmpty) return null;
        try {
          return jsonDecode(t);
        } catch (_) {
          // Best-effort python-ish repr.
          if ((t.startsWith('{') && t.endsWith('}')) ||
              (t.startsWith('[') && t.endsWith(']'))) {
            var x = t;
            x = x.replaceAll("'", '"');
            x = x.replaceAll(RegExp(r'\bNone\b'), 'null');
            x = x.replaceAll(RegExp(r'\bTrue\b'), 'true');
            x = x.replaceAll(RegExp(r'\bFalse\b'), 'false');
            try {
              return jsonDecode(x);
            } catch (_) {
              return null;
            }
          }
          return null;
        }
      }

      Map<String, dynamic>? tryParseNoteMap(dynamic note) {
        if (note is Map<String, dynamic>) return note;
        if (note is Map) return note.cast<String, dynamic>();
        if (note is String) {
          final decoded = tryDecodeJsonish(note);
          if (decoded is Map<String, dynamic>) return decoded;
          if (decoded is Map) return decoded.cast<String, dynamic>();
        }
        return null;
      }

      bool isDoneStatus(dynamic v) {
        if (v == null) return false;
        final s = v.toString().trim().toLowerCase();
        return s == 'done';
      }

      String? pickString(Map<String, dynamic> m, List<String> keys) {
        for (final k in keys) {
          if (!m.containsKey(k)) continue;
          final v = m[k];
          if (v == null) continue;
          final s = v.toString().trim();
          if (s.isNotEmpty) return s;
        }
        return null;
      }

      dynamic noteForUi = detail.note;
      final noteMap = tryParseNoteMap(noteForUi);
      final noteStatus = noteMap == null ? null : noteMap['status'];
      final shouldCheckOrder = isNoteEmpty(noteForUi) ||
          noteMap == null ||
          !isDoneStatus(noteStatus);

      if (shouldCheckOrder) {
        final orderNumber = normalizeOrderNumber(
            (detail.client.number.trim().isNotEmpty)
                ? detail.client.number
                : item.client.number);

        final sectorName = (detail.context.sectorLabel.trim().isNotEmpty)
            ? detail.context.sectorLabel.trim()
            : (item.context.sectorLabel.trim().isNotEmpty)
                ? item.context.sectorLabel.trim()
                : 'FlashVision';

        try {
          final resp =
              await TransactionService.instance.onlinePurchaseOrderCheck(
            orderNumber: orderNumber,
            sectorName: sectorName,
            transactionId: detail.id,
          );

          final merged = <String, dynamic>{};
          if (noteMap != null) {
            merged.addAll(noteMap);
          } else {
            // Preserve whatever was there.
            final raw = (noteForUi == null) ? '' : noteForUi.toString();
            if (raw.trim().isNotEmpty) merged['note_raw'] = raw;
          }

          merged['order_checked_at'] = DateTime.now().toIso8601String();
          merged['order_check'] = resp;

          final data = resp['data'];
          if (data is Map) {
            final dataMap = data.cast<String, dynamic>();
            final providerStatus = pickString(
                dataMap, const ['status', 'order_status', 'state', 'result']);
            if (providerStatus != null && providerStatus.trim().isNotEmpty) {
              final prev = merged['status'];
              if (prev != null && prev.toString() != providerStatus) {
                merged['previous_status'] = prev;
              }
              merged['status'] = providerStatus;
            }
          }

          noteForUi = merged;
        } catch (e) {
          // Non-fatal: show the note dialog anyway.
          final merged = <String, dynamic>{};
          if (noteMap != null) {
            merged.addAll(noteMap);
          } else {
            final raw = (noteForUi == null) ? '' : noteForUi.toString();
            if (raw.trim().isNotEmpty) merged['note_raw'] = raw;
          }
          merged['order_checked_at'] = DateTime.now().toIso8601String();
          merged['order_check'] = {'success': false, 'message': e.toString()};
          noteForUi = merged;
        }
      }

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) {
          bool dataNotEmpty(dynamic v) {
            if (v == null) return false;
            if (v is String) {
              final s = v.trim();
              if (s.isEmpty) return false;
              if (s == '-' || s.toLowerCase() == 'null') return false;
              if (s == '{}' || s == '[]') return false;
              return true;
            }
            if (v is Map) return v.isNotEmpty;
            if (v is List) return v.isNotEmpty;
            return true;
          }

          bool isSuccessTrue(dynamic v) {
            if (v == null) return false;
            if (v is bool) return v;
            if (v is num) return v != 0;
            if (v is String) {
              final s = v.trim().toLowerCase();
              return s == 'yes' || s == 'true' || s == '1' || s == 'ok';
            }
            return false;
          }

          dynamic pickNoteForDisplay(dynamic note) {
            // If we have an order-check response with non-empty data,
            // show ONLY the provider `data` block in the Note section.
            //
            // If `order_check.data` is empty AND `order_check.success` is true,
            // we hide the whole Order Check block (to avoid clutter).
            if (note is Map) {
              final oc = note['order_check'];
              if (oc is Map) {
                final data = oc['data'];
                final success = oc['success'];

                if (isSuccessTrue(success) && !dataNotEmpty(data)) {
                  final cleaned =
                      Map<String, dynamic>.from(note.cast<String, dynamic>());
                  cleaned.remove('order_check');
                  cleaned.remove('order_checked_at');
                  cleaned.remove('order_checked');
                  return cleaned;
                }

                if (dataNotEmpty(data)) return data;
              }

              // Fallback: if note itself contains a non-empty `data` key.
              final data = note['data'];
              if (dataNotEmpty(data)) return data;
            }
            return note;
          }

          final noteForDisplay = pickNoteForDisplay(noteForUi);
          final noteText = prettyNote(noteForDisplay);

          TextStyle labelStyle() => const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _fgSoft,
              );

          Widget kv(String k, String v) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 120, child: Text(k, style: labelStyle())),
                  Expanded(
                    child: Text(
                      v,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _fg,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          final content = SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Transaction #${detail.id}',
                        style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                            color: _fg,
                            fontSize: 16,
                            fontWeight: FontWeight.w900),
                      ),
                    ),
                    Text(
                      detail.currency,
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          color: _fg,
                          fontSize: 13,
                          fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                kv('Date', detail.ts.toLocal().toString()),
                kv('Status', detail.status),
                kv('Client', '${detail.client.name} (${detail.client.number})'),
                kv('Brand', detail.context.brandLabel),
                const Divider(height: 24),
                Text(
                  'Note',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      color: _fg, fontSize: 13, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: buildPrettyNoteWidget(
                    noteForDisplay,
                    baseStyle: const TextStyle(fontSize: 12, height: 1.25),
                    keyStyle: const TextStyle(
                      fontSize: 12,
                      height: 1.25,
                      fontWeight: FontWeight.w900,
                      color: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          );

          final mq = MediaQuery.of(ctx);
          final maxDialogWidth = mq.size.width < 600
              ? (mq.size.width - 24).clamp(280.0, 520.0)
              : 760.0;

          Widget actionsBar(BoxConstraints constraints) {
            final compact = constraints.maxWidth < 360;

            Widget actionBtn({
              required VoidCallback? onPressed,
              required IconData icon,
              required String label,
            }) {
              if (compact) {
                return IconButton(
                  tooltip: label,
                  onPressed: onPressed,
                  icon: Icon(icon),
                );
              }

              return TextButton.icon(
                onPressed: onPressed,
                icon: Icon(icon),
                label: Text(label, style: const TextStyle(fontSize: 12)),
              );
            }

            return Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: compact ? 2 : 4,
              runSpacing: 4,
              children: [
                if (noteText.isNotEmpty)
                  actionBtn(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: noteText));
                      if (!ctx.mounted) return;
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Copied')),
                      );
                    },
                    icon: Icons.copy,
                    label: 'Copy',
                  ),
                if (noteText.isNotEmpty)
                  actionBtn(
                    onPressed: () async {
                      final ok = await shareText(
                        noteText,
                        title: 'Transaction #${detail.id}',
                      );
                      if (!ctx.mounted) return;
                      if (!ok) {
                        await Clipboard.setData(ClipboardData(text: noteText));
                        if (!ctx.mounted) return;
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('Copied (share not available)'),
                          ),
                        );
                      }
                    },
                    icon: Icons.share,
                    label: 'Share',
                  ),
                if (noteText.isNotEmpty)
                  actionBtn(
                    onPressed: () async {
                      final ok = await printText(
                        'Transaction #${detail.id}',
                        noteText,
                      );
                      if (!ctx.mounted) return;
                      if (!ok) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('Print is not available here'),
                          ),
                        );
                      }
                    },
                    icon: Icons.print,
                    label: 'Print',
                  ),
                actionBtn(
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: Icons.close,
                  label: 'Close',
                ),
              ],
            );
          }

          return Dialog(
            insetPadding: EdgeInsets.symmetric(
              horizontal: mq.size.width < 600 ? 12 : 28,
              vertical: mq.size.height < 700 ? 12 : 24,
            ),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: mq.size.width < 600 ? 280 : 520,
                maxWidth: maxDialogWidth,
                maxHeight: mq.size.height * 0.90,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(child: content),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, constraints) =>
                          actionsBar(constraints),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to load detail: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Global Refresh button (bottom nav) emits a pulse; reload transactions when
    // this page is active so both current-balance + /api/account/transactions
    // are refreshed together.
    ref.listen<int>(pageRefreshPulseProvider, (prev, next) {
      if (prev == null) return;
      if (next == prev) return;
      ref.read(transactionHistoryProvider.notifier).refresh();
    });
    ref.listen<TransactionHistoryState>(transactionHistoryProvider,
        (prev, next) {
      final msg = next.errorMessage;
      if (msg == null || msg.isEmpty) return;
      if (msg == prev?.errorMessage) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    });

    final st = ref.watch(transactionHistoryProvider);
    final hideDealerPrice = ref.watch(sessionProvider).hideDealerPrice;
    Future<void> onRefresh() =>
        ref.read(transactionHistoryProvider.notifier).refresh();

    final mq = MediaQuery.of(context);
    final w = mq.size.width;
    final isCompact = w < 980;
    final isPortrait = mq.orientation == Orientation.portrait;
    final useGrid = !isCompact || !isPortrait;
    return PageActions(
      actions: [
        PageAction(
          label: _isExporting ? 'Exporting...' : 'Export Excel',
          icon: Icons.file_download_outlined,
          onTap: _isExporting ? () {} : _exportToExcel,
        ),
        PageAction(
            label: 'Filter', icon: Icons.filter_list, onTap: _openFilters),
      ],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isCompact && isPortrait && st.summary != null) ...[
              _CollapsibleSummaryHeader(
                summary: st.summary!,
                fg: _fg,
                fgSoft: _fgSoft,
                hCtl: _hSummaryCtl,
                hideDealerPrice: hideDealerPrice,
                expanded: _summaryExpanded,
                onToggle: () =>
                    setState(() => _summaryExpanded = !_summaryExpanded),
              ),
              const SizedBox(height: 12),
            ],
            if (st.isRefreshing && st.items.isNotEmpty) ...[
              const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: ScrollConfiguration(
                behavior: const EvolutionScrollBehavior(showScrollbars: false),
                child: useGrid
                    ? _TxGrid(
                        st: st,
                        fg: _fg,
                        fgSoft: _fgSoft,
                        vCtl: _vGridCtl,
                        hCtl: _hGridCtl,
                        summary: isCompact && !isPortrait ? null : st.summary,
                        summaryExpanded: _summaryExpanded,
                        hideDealerPrice: hideDealerPrice,
                        onToggleSummary: (isCompact && !isPortrait) ||
                                st.summary == null
                            ? null
                            : () => setState(
                                  () => _summaryExpanded = !_summaryExpanded,
                                ),
                        onRefresh: onRefresh,
                        onTapRow: _openDetail,
                      )
                    : _TxCardsList(
                        st: st,
                        fg: _fg,
                        fgSoft: _fgSoft,
                        vCtl: _vCardsCtl,
                        hideDealerPrice: hideDealerPrice,
                        onRefresh: onRefresh,
                        onTapRow: _openDetail,
                      ),
              ),
            ),
            if (isCompact && isPortrait && st.meta != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${st.items.length} rows',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: _fgSoft),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CollapsibleSummaryHeader extends StatelessWidget {
  final TransactionSummary summary;
  final Color fg;
  final Color fgSoft;
  final ScrollController hCtl;
  final bool hideDealerPrice;
  final bool expanded;
  final VoidCallback onToggle;

  const _CollapsibleSummaryHeader({
    required this.summary,
    required this.fg,
    required this.fgSoft,
    required this.hCtl,
    required this.hideDealerPrice,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    // Same palette as the global "Next" chip navigation.
    const green = Color(0xFF28A745);
    const darkGreen = Color(0xFF1E7E34);

    final bg = green.withValues(alpha: .10); // light green
    final bd = green.withValues(alpha: .35);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bd),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                // When collapsed, keep the header very short to gain space.
                padding: expanded
                    ? const EdgeInsets.fromLTRB(8, 10, 8, 6)
                    : const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Center(
                  child: Container(
                    width: 46,
                    height: 5,
                    decoration: BoxDecoration(
                      color: green.withValues(alpha: .35),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState:
                expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
              child: _SummaryTable(
                summary: summary,
                fg: fg,
                fgSoft: fgSoft,
                hCtl: hCtl,
                hideDealerPrice: hideDealerPrice,
                headerColor: darkGreen,
              ),
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _SummaryTable extends StatelessWidget {
  final TransactionSummary summary;
  final Color fg;
  final Color fgSoft;
  final ScrollController hCtl;
  final bool hideDealerPrice;
  final Color headerColor;

  const _SummaryTable({
    required this.summary,
    required this.fg,
    required this.fgSoft,
    required this.hCtl,
    required this.hideDealerPrice,
    required this.headerColor,
  });

  double _asNum(String? raw) => MoneyFormat.tryParse(raw ?? '0') ?? 0;

  bool _nonZero(String? raw) => _asNum(raw).abs() > 0.00001;

  String _fmt(String? raw, String cur) =>
      MoneyFormat.format(_asNum(raw), currencyCode: cur);

  List<MapEntry<String, TransactionTotals>> _sortedEntries() {
    final entries = summary.totals.entries.toList();
    entries.sort((a, b) {
      const preferred = {'LBP': 0, 'USD': 1};
      final pa = preferred[a.key.toUpperCase()] ?? 99;
      final pb = preferred[b.key.toUpperCase()] ?? 99;
      if (pa != pb) return pa.compareTo(pb);
      return a.key.compareTo(b.key);
    });
    return entries;
  }

  String _costOrigValue(TransactionTotals t, String cur) {
    final raw = t.costPriceOriginalByBrandCurrency;
    final parsed = _asNum(raw);
    if (parsed.abs() > 0.00001) return raw;

    final legacy = _asNum(t.costPriceOriginal);
    if (legacy.abs() > 0.00001) return t.costPriceOriginal;

    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final entries = _sortedEntries();

    if (entries.isEmpty) return const SizedBox.shrink();

    // Hide any metric that is missing/zero for ALL currencies.
    final showCost =
        !hideDealerPrice && entries.any((e) => _nonZero(e.value.costPrice));
    final showCostOrig = !hideDealerPrice &&
        entries.any((e) =>
            _nonZero(e.value.costPriceOriginalByBrandCurrency) ||
            _nonZero(e.value.costPriceOriginal));
    final showAProfit =
        !hideDealerPrice && entries.any((e) => _nonZero(e.value.aProfit));
    final showDProfit =
        !hideDealerPrice && entries.any((e) => _nonZero(e.value.dProfit));
    final showCount = entries.any((e) => (e.value.count) != 0);

    final metrics = <_SumMetric>[
      if (showCost)
        _SumMetric(label: 'Cost', value: (t, cur) => _fmt(t.costPrice, cur)),
      if (showCostOrig)
        _SumMetric(
          label: 'Cost (Orig)',
          value: (t, cur) => _fmt(_costOrigValue(t, cur), cur),
        ),
      if (!hideDealerPrice)
        _SumMetric(
            label: 'Dealer', value: (t, cur) => _fmt(t.dealerPrice, cur)),
      _SumMetric(
          label: 'Customer', value: (t, cur) => _fmt(t.customerPrice, cur)),
      if (showDProfit)
        _SumMetric(label: 'D Profit', value: (t, cur) => _fmt(t.dProfit, cur)),
      if (showAProfit)
        _SumMetric(label: 'A Profit', value: (t, cur) => _fmt(t.aProfit, cur)),
      if (showCount) _SumMetric(label: 'Count', value: (t, _) => '${t.count}'),
    ];

    // NOTE: Per your requirement, do not show balances in the header totals.

    const curW = 56.0;
    const cellW = 140.0;

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row: metric labels (aligns columns across currencies)
        Row(
          children: [
            const SizedBox(width: curW),
            ...metrics.map(
              (m) => SizedBox(
                width: cellW,
                child: Text(
                  m.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: headerColor, // dark green
                  ),
                  textAlign: TextAlign.end,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ...entries.map((e) {
          final cur = e.key;
          final t = e.value;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: curW,
                  child: Text(
                    cur,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: headerColor, // dark green
                    ),
                  ),
                ),
                ...metrics.map(
                  (m) => SizedBox(
                    width: cellW,
                    child: Text(
                      m.value(t, cur),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: fgSoft, // dark grey
                      ),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );

    // Desktop/web usability: allow mouse wheel to scroll the header horizontally
    // and show a horizontal scrollbar when overflow exists.
    return Listener(
      onPointerSignal: (signal) {
        if (signal is PointerScrollEvent) {
          if (!hCtl.hasClients) return;
          final max = hCtl.position.maxScrollExtent;
          if (max <= 0) return;

          final d = signal.scrollDelta;
          // Prefer trackpad horizontal; fallback to vertical wheel.
          final delta = (d.dx.abs() > d.dy.abs()) ? d.dx : d.dy;
          if (delta == 0) return;
          final next = (hCtl.offset + delta).clamp(0.0, max);
          if ((next - hCtl.offset).abs() > 0.1) {
            hCtl.jumpTo(next);
          }
        }
      },
      child: SingleChildScrollView(
        controller: hCtl,
        scrollDirection: Axis.horizontal,
        child: content,
      ),
    );
  }
}

class _SumMetric {
  final String label;
  final String Function(TransactionTotals t, String cur) value;
  const _SumMetric({required this.label, required this.value});
}

// ------------------------------
// Desktop / web grid view
// ------------------------------

class _TxGrid extends StatelessWidget {
  final TransactionHistoryState st;
  final Color fg;
  final Color fgSoft;
  final ScrollController vCtl;
  final ScrollController hCtl;
  final TransactionSummary? summary;
  final bool summaryExpanded;
  final bool hideDealerPrice;
  final VoidCallback? onToggleSummary;
  final Future<void> Function(TransactionListItem item) onTapRow;
  final Future<void> Function() onRefresh;

  const _TxGrid({
    required this.st,
    required this.fg,
    required this.fgSoft,
    required this.vCtl,
    required this.hCtl,
    required this.summary,
    required this.summaryExpanded,
    required this.hideDealerPrice,
    required this.onToggleSummary,
    required this.onTapRow,
    required this.onRefresh,
  });

  double _asNum(String? raw) => MoneyFormat.tryParse(raw ?? '0') ?? 0;
  bool _nonZero(String? raw) => _asNum(raw).abs() > 0.00001;

  String _fmtMoney(String? raw, String cur) =>
      MoneyFormat.format(_asNum(raw), currencyCode: cur);

  String _fmtMoneyNum(num v, String cur) =>
      MoneyFormat.format(v, currencyCode: cur);

  List<MapEntry<String, TransactionTotals>> _sortedSummaryEntries() {
    final entries = summary?.totals.entries.toList() ??
        <MapEntry<String, TransactionTotals>>[];

    entries.sort((a, b) {
      const preferred = {'LBP': 0, 'USD': 1};
      final pa = preferred[a.key.toUpperCase()] ?? 99;
      final pb = preferred[b.key.toUpperCase()] ?? 99;
      if (pa != pb) return pa.compareTo(pb);
      return a.key.compareTo(b.key);
    });

    return entries;
  }

  String _summaryMoneyValue(String? raw, String cur) {
    final value = _asNum(raw);
    if (value.abs() <= 0.00001) return '—';
    return MoneyFormat.format(value, currencyCode: cur);
  }

  String _summaryCostOrigRaw(TransactionTotals t) {
    final parsed = _asNum(t.costPriceOriginalByBrandCurrency);
    if (parsed.abs() > 0.00001) return t.costPriceOriginalByBrandCurrency;

    final legacy = _asNum(t.costPriceOriginal);
    if (legacy.abs() > 0.00001) return t.costPriceOriginal;

    return t.costPriceOriginalByBrandCurrency;
  }

  List<String> _summaryLinesForColumn(String key) {
    final entries = _sortedSummaryEntries();
    if (entries.isEmpty) return const <String>[];

    switch (key) {
      case 'currency':
        return entries.map((e) => e.key.toUpperCase()).toList();
      case 'cost':
        return entries
            .map((e) =>
                _summaryMoneyValue(e.value.costPrice, e.key.toUpperCase()))
            .toList();
      case 'cost_orig':
        return entries
            .map((e) => _summaryMoneyValue(
                  _summaryCostOrigRaw(e.value),
                  e.key.toUpperCase(),
                ))
            .toList();
      case 'dealer':
        if (hideDealerPrice) return const <String>[];
        return entries
            .map((e) =>
                _summaryMoneyValue(e.value.dealerPrice, e.key.toUpperCase()))
            .toList();
      case 'customer':
        return entries
            .map((e) =>
                _summaryMoneyValue(e.value.customerPrice, e.key.toUpperCase()))
            .toList();
      case 'd_profit':
        if (hideDealerPrice) return const <String>[];
        return entries
            .map(
                (e) => _summaryMoneyValue(e.value.dProfit, e.key.toUpperCase()))
            .toList();
      case 'a_profit':
        return entries
            .map(
                (e) => _summaryMoneyValue(e.value.aProfit, e.key.toUpperCase()))
            .toList();
      default:
        return const <String>[];
    }
  }

  Widget _buildSummaryHeaderCell(_TxGridCol col) {
    final lines = _summaryLinesForColumn(col.key);

    if (col.key == 'status') {
      return SizedBox(width: col.width, child: const SizedBox.shrink());
    }

    if (lines.isEmpty) {
      return SizedBox(
        width: col.width,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 3, vertical: 6),
          child: SizedBox(height: 18),
        ),
      );
    }

    final isCurrency = col.key == 'currency';

    return SizedBox(
      width: col.width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
        child: Text(
          lines.join('\n'),
          textAlign: isCurrency ? TextAlign.center : col.align,
          softWrap: true,
          style: TextStyle(
            color:
                isCurrency ? const Color(0xFF1E7E34) : const Color(0xFF28A745),
            fontWeight: FontWeight.w800,
            fontSize: isCurrency ? 9.4 : 9.0,
            height: 1.25,
          ),
        ),
      ),
    );
  }

  /// If backend doesn't provide per-row D Profit (or returns 0), derive it as:
  /// customer - dealer.
  num _dProfitNum(TransactionListItem e) {
    final raw = _asNum(e.amounts.dProfit);
    if (raw.abs() > 0.00001) return raw;
    final dealer = _asNum(e.amounts.dealer);
    final customer = _asNum(e.amounts.customer);
    return customer - dealer;
  }

  @override
  Widget build(BuildContext context) {
    final hasCost =
        !hideDealerPrice && st.items.any((e) => _nonZero(e.amounts.cost));
    final hasAProfit =
        !hideDealerPrice && st.items.any((e) => _nonZero(e.amounts.aProfit));
    final hasCostOrig = !hideDealerPrice &&
        st.items.any((e) => _nonZero(e.amounts.costOriginal));
    final hasBalance = st.items.any((e) => (e.balance?.isNotEmpty ?? false));
    final hasUser =
        st.items.any((e) => (e.username?.trim().isNotEmpty ?? false));
    final hasSector = st.items.any(
      (e) => e.context.sectorLabel.trim().isNotEmpty,
    );

    final baseCols = <_TxGridCol>[
      _TxGridCol(
        key: 'status',
        label: 'Status',
        width: 20,
        align: TextAlign.center,
        cell: (e) => e.status,
      ),
      _TxGridCol(
        key: 'id',
        label: 'Id',
        width: 50,
        align: TextAlign.left,
        cell: (e) => '#${e.id}',
      ),
      if (hasUser)
        _TxGridCol(
          key: 'user',
          label: 'User',
          width: 80,
          align: TextAlign.left,
          cell: (e) => e.username ?? '',
        ),
      _TxGridCol(
        key: 'date',
        label: 'Date',
        width: 88,
        align: TextAlign.center,
        cell: (e) {
          final dt = e.ts.toLocal();
          return DateFormat('yyyy-MM-dd\nHH:mm:ss').format(dt);
        },
      ),
      _TxGridCol(
        key: 'client_name',
        label: 'Client\nName',
        width: 92,
        align: TextAlign.left,
        cell: (e) => e.client.name,
      ),
      _TxGridCol(
        key: 'client_number',
        label: 'Client\nNumber/Pin',
        width: 108,
        align: TextAlign.center,
        isLink: true,
        cell: (e) => e.client.number,
      ),
      _TxGridCol(
        key: 'brand',
        label: 'Brand',
        width: 132,
        align: TextAlign.left,
        cell: (e) => e.context.brandLabel,
      ),
      if (hasSector)
        _TxGridCol(
          key: 'sector',
          label: 'Sector',
          width: 80,
          align: TextAlign.left,
          cell: (e) => e.context.sectorLabel,
        ),
      if (hasCost)
        _TxGridCol(
          key: 'cost',
          label: 'Cost Price',
          width: 75,
          align: TextAlign.right,
          cell: (e) => _fmtMoney(e.amounts.cost, e.currency),
        ),
      if (hasCostOrig)
        _TxGridCol(
          key: 'cost_orig',
          label: 'Cost Price\n(Original)',
          width: 75,
          align: TextAlign.right,
          cell: (e) {
            final cur = e.context.brandCurrency.trim().isNotEmpty
                ? e.context.brandCurrency
                : (e.amounts.costOriginalCurrency.trim().isNotEmpty
                    ? e.amounts.costOriginalCurrency
                    : e.currency);
            return _fmtMoney(e.amounts.costOriginal, cur);
          },
        ),
      if (!hideDealerPrice)
        _TxGridCol(
          key: 'dealer',
          label: 'Dealer Price',
          width: 75,
          align: TextAlign.right,
          cell: (e) => _fmtMoney(e.amounts.dealer, e.currency),
        ),
      _TxGridCol(
        key: 'customer',
        label: 'Customer\nPrice',
        width: 75,
        align: TextAlign.right,
        cell: (e) => _fmtMoney(e.amounts.customer, e.currency),
      ),
      if (!hideDealerPrice)
        _TxGridCol(
          key: 'd_profit',
          label: 'D Profit',
          width: 65,
          align: TextAlign.right,
          cell: (e) => _fmtMoneyNum(_dProfitNum(e), e.currency),
        ),
      if (hasAProfit)
        _TxGridCol(
          key: 'a_profit',
          label: 'A Profit',
          width: 65,
          align: TextAlign.right,
          cell: (e) => _fmtMoney(e.amounts.aProfit, e.currency),
        ),
      _TxGridCol(
        key: 'currency',
        label: 'Currency',
        width: 60,
        align: TextAlign.center,
        cell: (e) => e.currency,
      ),
      if (hasBalance)
        _TxGridCol(
          key: 'balance',
          label: 'Balance',
          width: 118,
          align: TextAlign.right,
          cell: (e) {
            final b = e.balance;
            if (b == null || b.isEmpty) return '';
            // LBP first, then USD, then alpha.
            final entries = b.entries.toList()
              ..sort((a, b) {
                const pref = {'LBP': 0, 'USD': 1};
                final pa = pref[a.key.toUpperCase()] ?? 99;
                final pb = pref[b.key.toUpperCase()] ?? 99;
                if (pa != pb) return pa.compareTo(pb);
                return a.key.compareTo(b.key);
              });
            return entries.map((e) {
              final cur = e.key.toUpperCase();
              final v = MoneyFormat.tryParse(e.value) ?? 0;
              return '${MoneyFormat.format(v, currencyCode: cur)} $cur';
            }).join('\n');
          },
        ),
    ];

    return SelectionArea(
      child: LayoutBuilder(
      builder: (context, constraints) {
        const headerRed = Color(0xFFD32F2F);
        const headerBg = Color(0xFFFFF2F2);
        final border = Colors.red.withValues(alpha: .25);

        const minBrandW = 124.0;

        final fixedW = baseCols.fold<double>(
          0,
          (s, c) => s + (c.key == 'brand' ? 0 : c.width),
        );

        final brandW =
            (constraints.maxWidth - fixedW - 2).clamp(minBrandW, 100000.0);

        final cols = baseCols.map((c) {
          if (c.key != 'brand') return c;
          return _TxGridCol(
            key: c.key,
            label: c.label,
            width: brandW,
            align: c.align,
            cell: c.cell,
            isLink: c.isLink,
          );
        }).toList();

        // tableW becomes ~constraints.maxWidth when there's room; otherwise it stays wider and scrolls.
        final tableW = fixedW + brandW + 2;

        Widget headerRowFixed() {
          final hasSummary = summary != null && summary!.totals.isNotEmpty;
          const summaryGreen = Color(0xFF28A745);
          const summaryBg = Color(0xFFF5FBF5);

          Widget labelsRow() {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: cols.map((c) {
                if (c.key == 'status') {
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
                    child: Text(
                      c.label,
                      textAlign: c.align,
                      style: const TextStyle(
                        color: headerRed,
                        fontWeight: FontWeight.w900,
                        fontSize: 10.0,
                        height: 1.2,
                      ),
                      softWrap: true,
                    ),
                  ),
                );
              }).toList(),
            );
          }

          return Container(
            width: tableW,
            decoration: BoxDecoration(
              color: headerBg,
              border: Border(
                bottom: BorderSide(color: border),
                top: BorderSide(color: border),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                labelsRow(),
                if (hasSummary)
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: summaryBg,
                      border: Border(
                        top: BorderSide(
                          color: summaryGreen.withValues(alpha: .25),
                        ),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: cols.map(_buildSummaryHeaderCell).toList(),
                    ),
                  ),
              ],
            ),
          );
        }

        Widget buildRow(BuildContext context, TransactionListItem e, int idx) {
          final zebra = idx.isOdd ? const Color(0xFFF2F2F2) : Colors.white;

          // Render Status as an overlay so its background fills the full row height
          // without using CrossAxisAlignment.stretch (which breaks in ListView due to
          // unbounded height constraints).
          final statusCol = cols.firstWhere((x) => x.key == 'status');
          final otherCols = cols.where((x) => x.key != 'status').toList();

          Widget buildCell(_TxGridCol col) {
            final raw = col.cell(e).trim();
            final isLink = col.isLink && raw.isNotEmpty;

            Widget text = Text(
              raw,
              textAlign: col.align,
              softWrap: true,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isLink ? Colors.blue : fgSoft,
                fontWeight: col.key == 'id' ? FontWeight.w900 : FontWeight.w600,
                fontSize: 10.0,
                height: 1.25,
              ),
            );

            if (isLink) {
              text = InkWell(
                onTap: () async {
                  // Client number should open the transaction popup (same as row tap)
                  // rather than copying the value.
                  if (col.key == 'client_number') {
                    await onTapRow(e);
                    return;
                  }

                  await Clipboard.setData(ClipboardData(text: raw));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied')),
                  );
                },
                child: text,
              );
            }

            return SizedBox(
              width: col.width,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
                child: text,
              ),
            );
          }

          Widget buildStatus() {
            final raw = statusCol.cell(e).trim();
            final label = raw.trim().isEmpty ? '—' : raw.trim().toUpperCase();

            final s = raw.trim().toLowerCase();
            Color statusColor;
            if (s == 'active' ||
                s == 'done' ||
                s == 'accept' ||
                s == 'accepted') {
              statusColor = Colors.green;
            } else if (s.contains('fail') || s.contains('error')) {
              statusColor = Colors.red;
            } else if (s.contains('not') && s.contains('paid')) {
              statusColor = Colors.orange;
            } else {
              statusColor = Colors.orange;
            }

            return Container(
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: .10),
                border: Border(
                  right: BorderSide(
                    color: statusColor.withValues(alpha: .35),
                  ),
                ),
              ),
              child: Center(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 8.0,
                      height: 1.0,
                      letterSpacing: .25,
                    ),
                  ),
                ),
              ),
            );
          }

          return SizedBox(
            width: tableW,
            child: Container(
              decoration: BoxDecoration(
                color: zebra,
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade300),
                  left: BorderSide(color: Colors.grey.shade200),
                  right: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: ClipRect(
                child: Stack(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: statusCol.width),
                        ...otherCols.map(buildCell),
                      ],
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: statusCol.width,
                      child: buildStatus(),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        Widget footer() {
          if (st.isInitialLoading || st.isLoadingMore) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          if (st.items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(child: Text(st.errorMessage ?? 'No transactions')),
            );
          }
          if (!st.hasMore) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: Text('End of list')),
            );
          }
          return const SizedBox(height: 4);
        }

        return Scrollbar(
          controller: vCtl,
          thumbVisibility: true,
          trackVisibility: true,
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.vertical,
          child: Listener(
            onPointerSignal: (signal) {
              if (signal is PointerScrollEvent) {
                // Horizontal scrolling: trackpad horizontal (dx) or SHIFT + wheel (dy).
                // IMPORTANT: do NOT steal normal vertical wheel scrolling from the rows ListView.
                final pressed = HardwareKeyboard.instance.logicalKeysPressed;
                final shiftDown =
                    pressed.contains(LogicalKeyboardKey.shiftLeft) ||
                        pressed.contains(LogicalKeyboardKey.shiftRight);
                final dx = signal.scrollDelta.dx;
                final dy = signal.scrollDelta.dy;
                final wantH = dx.abs() > 0.01 || (shiftDown && dy.abs() > 0.01);
                if (!wantH) return;

                // pointerSignalResolver expects a callback that accepts the resolved PointerSignalEvent.
                // (Older Flutter versions do not accept a zero-arg callback.)
                GestureBinding.instance.pointerSignalResolver.register(signal,
                    (event) {
                  if (!hCtl.hasClients) return;
                  final max = hCtl.position.maxScrollExtent;
                  if (max <= 0) return;

                  final delta = dx.abs() > 0.01 ? dx : dy;
                  final next = (hCtl.offset + delta).clamp(0.0, max);
                  if ((next - hCtl.offset).abs() > 0.1) {
                    hCtl.jumpTo(next);
                  }
                });
              }
            },
            child: SingleChildScrollView(
              controller: hCtl,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableW,
                height: constraints.maxHeight,
                child: Column(
                  children: [
                    headerRowFixed(),
                    Expanded(
                      child: SizedBox(
                        width: tableW,
                        child: RefreshIndicator(
                          onRefresh: onRefresh,
                          child: ListView.builder(
                            controller: vCtl,
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: st.items.length + 1,
                            itemBuilder: (context, i) {
                              if (i < st.items.length) {
                                return buildRow(context, st.items[i], i);
                              }
                              return footer();
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
    );
  }
}

class _TxGridCol {
  final String key;
  final String label;
  final double width;
  final TextAlign align;
  final String Function(TransactionListItem e) cell;
  final bool isLink;

  const _TxGridCol({
    required this.key,
    required this.label,
    required this.width,
    required this.align,
    required this.cell,
    this.isLink = false,
  });
}

class _TxCardsList extends StatelessWidget {
  final TransactionHistoryState st;
  final Color fg;
  final Color fgSoft;
  final ScrollController vCtl;
  final bool hideDealerPrice;
  final Future<void> Function(TransactionListItem item) onTapRow;
  final Future<void> Function() onRefresh;

  const _TxCardsList({
    required this.st,
    required this.fg,
    required this.fgSoft,
    required this.vCtl,
    required this.hideDealerPrice,
    required this.onTapRow,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    // Show balance whenever the API provides it.
    final showBalance = st.items.any((e) => (e.balance?.isNotEmpty ?? false));

    // +1 for footer
    final itemCount = st.items.length + 1;

    return Scrollbar(
      controller: vCtl,
      thumbVisibility: true,
      trackVisibility: true,
      child: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView.separated(
          controller: vCtl,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
          itemCount: itemCount,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            if (i < st.items.length) {
              final e = st.items[i];
              return _TransactionCard(
                key: ValueKey('tx_${e.id}'),
                item: e,
                fg: fg,
                fgSoft: fgSoft,
                showBalance: showBalance,
                hideDealerPrice: hideDealerPrice,
                onTap: () => onTapRow(e),
              );
            }

            // Footer
            if (st.isInitialLoading || st.isLoadingMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            if (st.items.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child:
                    Center(child: Text(st.errorMessage ?? 'No transactions')),
              );
            }
            if (!st.hasMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Center(child: Text('End of list')),
              );
            }
            // Has more but not currently loading: keep footer minimal.
            return const SizedBox(height: 4);
          },
        ),
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  final TransactionListItem item;
  final Color fg;
  final Color fgSoft;
  final bool showBalance;
  final bool hideDealerPrice;
  final VoidCallback onTap;

  const _TransactionCard({
    super.key,
    required this.item,
    required this.fg,
    required this.fgSoft,
    required this.showBalance,
    required this.hideDealerPrice,
    required this.onTap,
  });

  Color _statusColor(BuildContext context) {
    final s = item.status.trim().toLowerCase();
    if (s == 'active' || s == 'done' || s == 'accept' || s == 'accepted') {
      return Colors.green;
    }
    if (s.contains('fail') || s.contains('error')) return Colors.red;
    if (s.contains('not') && s.contains('paid')) return Colors.orange;
    return Colors.orange; // default non-done
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(context);

    final dt = item.ts.toLocal();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(dt);

    final clientLine = [
      item.client.name.trim(),
      item.client.number.trim(),
    ].where((e) => e.isNotEmpty).join(' - ');

    final w = MediaQuery.of(context).size.width;
    final wide = w >= 720;

    final title = [
      if (wide) '#${item.id}',
      item.context.brandLabel,
    ].where((e) => e.trim().isNotEmpty).join(' - ');

    final leftInfo = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: fg,
          ),
        ),
        if ((item.username?.trim().isNotEmpty ?? false)) ...[
          const SizedBox(height: 6),
          Text(
            item.username!.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 6),
        if (clientLine.isNotEmpty)
          Text(
            clientLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: fg),
          ),
        const SizedBox(height: 6),
        Text(dateStr, style: TextStyle(color: fgSoft)),
      ],
    );

    final rightInfo = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        _TxPricesCard(
          currency: item.currency,
          amounts: item.amounts,
          hideDealerPrice: hideDealerPrice,
          brandCurrency: item.context.brandCurrency,
        ),
      ],
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade300),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatusRail(
                status: item.status,
                color: statusColor,
                fg: fg,
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(wide ? 10 : 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: leftInfo),
                            const SizedBox(width: 12),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 360),
                              child: rightInfo,
                            ),
                          ],
                        )
                      else ...[
                        leftInfo,
                        const SizedBox(height: 10),
                        _TxPricesCard(
                          currency: item.currency,
                          amounts: item.amounts,
                          // Mobile: show balance inside the Prices card (dealer block)
                          // when the API provides it.
                          balance: showBalance ? item.balance : null,
                          hideDealerPrice: hideDealerPrice,
                          brandCurrency: item.context.brandCurrency,
                        ),
                      ],
                      // Desktop/tablet wide layout: keep balance as a separate line below.
                      if (wide && showBalance && item.balance != null) ...[
                        const SizedBox(height: 10),
                        _TxBalanceLine(
                          balance: item.balance!,
                          fg: fgSoft,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusRail extends StatelessWidget {
  final String status;
  final Color color;
  final Color fg;

  const _StatusRail({
    required this.status,
    required this.color,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    final label = status.trim().isEmpty ? '—' : status.trim().toUpperCase();
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
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: .4,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

class _TxBalanceLine extends StatelessWidget {
  final Map<String, String> balance;
  final Color fg;

  const _TxBalanceLine({required this.balance, required this.fg});

  @override
  Widget build(BuildContext context) {
    final parts =
        balance.entries.where((e) => e.key.trim().isNotEmpty).map((e) {
      final cur = e.key.trim().toUpperCase();
      final v = MoneyFormat.tryParse(e.value) ?? 0;
      return '$cur ${MoneyFormat.format(v, currencyCode: cur)}';
    }).toList();

    return Text(
      parts.isEmpty ? '' : 'Balance: ${parts.join('  |  ')}',
      style: TextStyle(color: fg, fontWeight: FontWeight.w700),
    );
  }
}

/// Mimics the Purchase page "Prices" card:
/// - Customer cost always visible (emphasized)
/// - Eye toggles showing the rest (dealer/cost/profits/etc.)

class _TxPricesCard extends StatefulWidget {
  final String currency;
  final TxAmounts amounts;
  final Map<String, String>? balance;
  final bool hideDealerPrice;
  final String brandCurrency;

  const _TxPricesCard({
    required this.currency,
    required this.amounts,
    this.balance,
    this.hideDealerPrice = false,
    this.brandCurrency = '',
  });

  @override
  State<_TxPricesCard> createState() => _TxPricesCardState();
}

class _TxPricesCardState extends State<_TxPricesCard> {
  bool _showMore = false;

  @override
  void initState() {
    super.initState();
    _showMore = !widget.hideDealerPrice;
  }

  @override
  void didUpdateWidget(covariant _TxPricesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hideDealerPrice != widget.hideDealerPrice) {
      _showMore = !widget.hideDealerPrice;
    }
  }

  bool _nonZero(String? raw) {
    final v = MoneyFormat.tryParse(raw ?? '0') ?? 0;
    return v.abs() > 0.00001;
  }

  String _fmt(String? raw, String cur) {
    final v = MoneyFormat.tryParse(raw ?? '0') ?? 0;
    return MoneyFormat.format(v, currencyCode: cur);
  }

  String _fmtNum(num v, String cur) => MoneyFormat.format(v, currencyCode: cur);

  num _dProfitNum(TxAmounts a) {
    final raw = MoneyFormat.tryParse(a.dProfit) ?? 0;
    if (raw.abs() > 0.00001) return raw;
    final dealer = MoneyFormat.tryParse(a.dealer) ?? 0;
    final customer = MoneyFormat.tryParse(a.customer) ?? 0;
    return customer - dealer;
  }

  @override
  Widget build(BuildContext context) {
    final cur = widget.currency.trim().toUpperCase();
    final a = widget.amounts;

    String? balanceRawForCur() {
      final b = widget.balance;
      if (b == null || b.isEmpty) return null;
      final want = cur.toUpperCase();
      // Fast path
      final direct = b[want] ?? b[want.toLowerCase()];
      if (direct != null && direct.toString().trim().isNotEmpty) {
        return direct.toString();
      }
      // Case-insensitive fallback
      for (final e in b.entries) {
        if (e.key.toString().trim().toUpperCase() == want) {
          final v = e.value.toString();
          if (v.trim().isNotEmpty) return v;
        }
      }
      return null;
    }

    final dProfit = _dProfitNum(a);
    final costOrigCur = widget.brandCurrency.trim().isNotEmpty
        ? widget.brandCurrency.trim().toUpperCase()
        : (a.costOriginalCurrency.trim().isNotEmpty
            ? a.costOriginalCurrency.trim().toUpperCase()
            : cur);

    final hasCost = !widget.hideDealerPrice && _nonZero(a.cost);
    final hasDealer = !widget.hideDealerPrice && _nonZero(a.dealer);
    final hasDProfit = !widget.hideDealerPrice && dProfit.abs() > 0.00001;
    final hasAProfit = !widget.hideDealerPrice && _nonZero(a.aProfit);
    final hasCostOrig = !widget.hideDealerPrice && _nonZero(a.costOriginal);

    final balRaw = balanceRawForCur();
    final hasBalance = (balRaw != null && balRaw.trim().isNotEmpty);

    final hasAnyExtra = hasCost ||
        hasDealer ||
        hasDProfit ||
        hasAProfit ||
        hasCostOrig ||
        hasBalance;

    Widget row(
      String label,
      String value, {
      bool emphasize = false,
      String? currencyOverride,
    }) {
      final curText = (currencyOverride ?? cur).trim().toUpperCase();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: emphasize ? 11.2 : 10.4,
                  fontWeight: FontWeight.w800,
                  color: Colors.red.shade700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${value.isEmpty ? '—' : value} $curText',
              style: TextStyle(
                fontSize: emphasize ? 14.4 : 11.2,
                fontWeight: emphasize ? FontWeight.w900 : FontWeight.w800,
                color: Colors.green.shade800,
              ),
            ),
          ],
        ),
      );
    }

    final groupAHas = hasCost || hasCostOrig || hasAProfit;
    // Dealer block (mobile wants balance here when provided)
    final groupBHas = hasDealer || hasDProfit || hasBalance;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Prices',
                    style: TextStyle(
                      fontSize: 11.2,
                      fontWeight: FontWeight.w900,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ),
                if (hasAnyExtra)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      _showMore ? Icons.visibility : Icons.visibility_off,
                      size: 14.4,
                      color: Colors.grey.shade700,
                    ),
                    onPressed: () => setState(() => _showMore = !_showMore),
                  ),
              ],
            ),
            const SizedBox(height: 6),

            // Extras (hidden by default), grouped
            if (_showMore) ...[
              if (groupAHas) ...[
                if (hasCost) row('Cost', _fmt(a.cost, cur)),
                if (hasCostOrig)
                  row(
                    'Cost (Orig)',
                    _fmt(a.costOriginal, costOrigCur),
                    currencyOverride: costOrigCur,
                  ),
                if (hasAProfit) row('A Profit', _fmt(a.aProfit, cur)),
                const Divider(height: 12),
              ],
              if (groupBHas) ...[
                if (hasDealer) row('Dealer', _fmt(a.dealer, cur)),
                if (hasDProfit) row('D Profit', _fmtNum(dProfit, cur)),
                if (hasBalance) row('Balance', _fmt(balRaw, cur)),
                const Divider(height: 12),
              ],
            ],

            // Always visible
            row('Customer', _fmt(a.customer, cur), emphasize: true),
          ],
        ),
      ),
    );
  }
}
