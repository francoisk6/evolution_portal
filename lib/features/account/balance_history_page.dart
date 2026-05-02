import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:evolution_portal/app/app_scroll_behavior.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:evolution_portal/services/balance_service.dart';
import 'package:evolution_portal/state/balance_history_provider.dart';
import 'package:evolution_portal/state/current_balance_provider.dart';
import 'package:evolution_portal/state/currency_provider.dart';
import 'package:evolution_portal/state/notification_provider.dart';
import 'package:evolution_portal/state/page_refresh_provider.dart';
import 'package:evolution_portal/utils/money_format.dart';
import 'package:evolution_portal/utils/note_pretty.dart';
import 'package:evolution_portal/utils/notify.dart';
import 'package:evolution_portal/widgets/page_action_bar.dart'
    show PageActions, PageAction, pageActions;

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

        return EvolutionPopupScrollScope(
          child: FractionallySizedBox(
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

class BalanceHistoryPage extends ConsumerStatefulWidget {
  const BalanceHistoryPage({super.key});

  @override
  ConsumerState<BalanceHistoryPage> createState() => _BalanceHistoryPageState();
}

class _BalanceHistoryPageState extends ConsumerState<BalanceHistoryPage> {
  static const _fg = Color(0xFF444444);
  static const _fgSoft = Color(0xFF666666);

  final _df = DateFormat('yyyy-MM-dd');
  final _vCardsCtl = ScrollController();
  final _vGridCtl = ScrollController();
  final _hGridCtl = ScrollController();

  double? _maxDueBalanceLbp;
  double? _maxDueBalanceUsd;

  @override
  void initState() {
    super.initState();
    _vCardsCtl.addListener(() => _onScroll(_vCardsCtl));
    _vGridCtl.addListener(() => _onScroll(_vGridCtl));
    Future.microtask(() async {
      await _loadDueBalanceInfo();
      await ref.read(balanceHistoryProvider.notifier).fetch(reset: true);
    });
  }

  @override
  void dispose() {
    _vCardsCtl.dispose();
    _vGridCtl.dispose();
    _hGridCtl.dispose();
    super.dispose();
  }

  double? _parseNullableNum(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final s = value.toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null') return null;
    return double.tryParse(s.replaceAll(',', ''));
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    return const <String, dynamic>{};
  }

  Future<void> _loadDueBalanceInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('user_json');
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final me = decoded['data'] is Map<String, dynamic>
          ? decoded['data'] as Map<String, dynamic>
          : decoded;
      final profile = _asMap(me['profile']);
      final lbp = _parseNullableNum(
        profile['max_due_balance_lbp'] ?? me['max_due_balance_lbp'],
      );
      final usd = _parseNullableNum(
        profile['max_due_balance_usd'] ?? me['max_due_balance_usd'],
      );
      if (!mounted) return;
      setState(() {
        _maxDueBalanceLbp = lbp;
        _maxDueBalanceUsd = usd;
      });
    } catch (_) {
      // ignore malformed cached profile payloads
    }
  }

  void _onScroll(ScrollController ctl) {
    if (!ctl.hasClients) return;
    final pos = ctl.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels >= pos.maxScrollExtent * 0.7) {
      ref.read(balanceHistoryProvider.notifier).fetch();
    }
  }

  Future<void> _openFilters() async {
    final currentPageActions = List<PageAction>.from(pageActions.value);
    pageActions.value = const <PageAction>[];

    final current = ref.read(balanceHistoryProvider).filters;
    final backendAvailable = ref.read(balanceHistoryProvider).filterData?.available;
    final currencies = ref.read(currencyProvider).all;
    final fromCtl = TextEditingController(
      text: current.from == null ? '' : _df.format(current.from!),
    );
    final toCtl = TextEditingController(
      text: current.to == null ? '' : _df.format(current.to!),
    );
    int? selectedCurrencyId = current.currencyId;
    int? selectedUserId = current.userId;
    bool distinctUsers = current.distinctUsers;
    int statusIdx = current.status == null ? 0 : (current.status! ? 1 : 2);

    final userOptions = (() {
      final backendUsers =
          backendAvailable?.users ?? const <BalanceFilterUserOption>[];
      final out = <_ComboBoxOption<int>>[];
      final seen = <int>{};
      for (final entry in backendUsers) {
        final id = entry.id;
        if (!seen.add(id)) continue;
        final label = entry.label.trim();
        out.add(_ComboBoxOption<int>(
          value: id,
          label: label.isEmpty ? '#$id' : label,
        ));
      }
      return out;
    })();

    final currencyOptions = (() {
      final backendCurrencies =
          backendAvailable?.currencies ?? const <BalanceFilterCurrencyOption>[];
      if (backendCurrencies.isNotEmpty) {
        final out = <_ComboBoxOption<int>>[];
        final seen = <int>{};
        for (final entry in backendCurrencies) {
          final id = entry.id;
          if (id == null || !seen.add(id)) continue;
          final label = entry.label.trim().isNotEmpty
              ? entry.label.trim()
              : entry.code.trim().toUpperCase();
          out.add(_ComboBoxOption<int>(value: id, label: label));
        }
        if (out.isNotEmpty) return out;
      }

      return currencies
          .map(
            (c) => _ComboBoxOption<int>(value: c.id, label: c.code),
          )
          .toList();
    })();

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setModalState) {
              void clearFilters() {
                setModalState(() {
                  fromCtl.clear();
                  toCtl.clear();
                  selectedCurrencyId = null;
                  selectedUserId = null;
                  distinctUsers = false;
                  statusIdx = 0;
                });
              }

              void applyFilters() {
                DateTime? parse(String s) =>
                    s.trim().isEmpty ? null : DateTime.tryParse(s.trim());
                final f = BalanceFilters(
                  from: parse(fromCtl.text),
                  to: parse(toCtl.text),
                  status: statusIdx == 0 ? null : (statusIdx == 1),
                  currencyId: selectedCurrencyId,
                  userId: selectedUserId,
                  distinctUsers: distinctUsers,
                );
                ref.read(balanceHistoryProvider.notifier).setFilters(f);
                ref.read(balanceHistoryProvider.notifier).fetch(reset: true);
                Navigator.pop(ctx);
              }

              Widget buildOverlayActions() {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FloatingActionButton.small(
                      heroTag: 'balance_filter_cancel',
                      tooltip: 'Cancel',
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      onPressed: () => Navigator.pop(ctx),
                      child: const Icon(Icons.close),
                    ),
                    const SizedBox(height: 10),
                    FloatingActionButton.small(
                      heroTag: 'balance_filter_clear',
                      tooltip: 'Clear',
                      backgroundColor: Colors.white,
                      foregroundColor: Theme.of(ctx).colorScheme.primary,
                      onPressed: clearFilters,
                      child: const Icon(Icons.backspace_outlined),
                    ),
                    const SizedBox(height: 10),
                    FloatingActionButton.small(
                      heroTag: 'balance_filter_apply',
                      tooltip: 'Apply',
                      onPressed: applyFilters,
                      child: const Icon(Icons.check),
                    ),
                  ],
                );
              }

              return EvolutionPopupScrollScope(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(ctx).viewInsets.bottom,
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
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
                                            'Filter Balance History',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller: fromCtl,
                                              decoration: InputDecoration(
                                                labelText:
                                                    'From (YYYY-MM-DD)',
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
                                              onTap: () async {
                                                final now = DateTime.now();
                                                final d = await showDatePicker(
                                                  context: ctx,
                                                  firstDate:
                                                      DateTime(now.year - 5),
                                                  lastDate:
                                                      DateTime(now.year + 1),
                                                  initialDate: current.from ??
                                                      now,
                                                );
                                                if (d != null) {
                                                  setModalState(() {
                                                    fromCtl.text = _df.format(d);
                                                  });
                                                }
                                              },
                                              readOnly: true,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: TextField(
                                              controller: toCtl,
                                              decoration: InputDecoration(
                                                labelText: 'To (YYYY-MM-DD)',
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
                                              onTap: () async {
                                                final now = DateTime.now();
                                                final d = await showDatePicker(
                                                  context: ctx,
                                                  firstDate:
                                                      DateTime(now.year - 5),
                                                  lastDate:
                                                      DateTime(now.year + 1),
                                                  initialDate: current.to ??
                                                      now,
                                                );
                                                if (d != null) {
                                                  setModalState(() {
                                                    toCtl.text = _df.format(d);
                                                  });
                                                }
                                              },
                                              readOnly: true,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (userOptions.isNotEmpty ||
                                          selectedUserId != null) ...[
                                        const SizedBox(height: 12),
                                        _SearchableDropdownField<int>(
                                          label: 'User',
                                          hintText: 'All users',
                                          allLabel: 'All users',
                                          value: selectedUserId,
                                          options: userOptions,
                                          onChanged: (v) {
                                            setModalState(
                                              () => selectedUserId = v,
                                            );
                                          },
                                        ),
                                      ],
                                      const SizedBox(height: 12),
                                      _SearchableDropdownField<int>(
                                        label: 'Currency',
                                        hintText: 'All currencies',
                                        allLabel: 'All currencies',
                                        value: selectedCurrencyId,
                                        options: currencyOptions,
                                        onChanged: (v) {
                                          setModalState(
                                            () => selectedCurrencyId = v,
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 12),
                                      DropdownButtonFormField<int>(
                                        initialValue: statusIdx,
                                        items: const [
                                          DropdownMenuItem<int>(
                                            value: 0,
                                            child: Text('All'),
                                          ),
                                          DropdownMenuItem<int>(
                                            value: 1,
                                            child: Text('PAID'),
                                          ),
                                          DropdownMenuItem<int>(
                                            value: 2,
                                            child: Text('DUE'),
                                          ),
                                        ],
                                        onChanged: (v) {
                                          setModalState(() => statusIdx = v ?? 0);
                                        },
                                        decoration: const InputDecoration(
                                          labelText: 'Status',
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      SwitchListTile.adaptive(
                                        contentPadding: EdgeInsets.zero,
                                        title: const Text('Distinct users'),
                                        subtitle: const Text(
                                          'Group results by user only once',
                                        ),
                                        value: distinctUsers,
                                        onChanged: (v) {
                                          setModalState(() => distinctUsers = v);
                                        },
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

  Future<void> _onAddBalance() async {
    final lbpCtl = TextEditingController();
    final usdCtl = TextEditingController();
    bool submitting = false;
    String? dialogError;

    final hasDueInfo = _maxDueBalanceLbp != null || _maxDueBalanceUsd != null;
    final maxDueLbpText = _maxDueBalanceLbp == null
        ? null
        : 'LBP ${MoneyFormat.format(_maxDueBalanceLbp!, currencyCode: 'LBP')}';
    final maxDueUsdText = _maxDueBalanceUsd == null
        ? null
        : 'USD ${MoneyFormat.format(_maxDueBalanceUsd!, currencyCode: 'USD')}';

    num parseAmount(String value) => num.tryParse(value.trim()) ?? 0;

    Future<void> submit(BuildContext dialogContext,
        void Function(void Function()) setModalState) async {
      final lbpAmount = lbpCtl.text.trim();
      final usdAmount = usdCtl.text.trim();
      if (parseAmount(lbpAmount) <= 0 && parseAmount(usdAmount) <= 0) {
        setModalState(() => dialogError = 'Enter LBP and/or USD amount.');
        return;
      }

      setModalState(() {
        submitting = true;
        dialogError = null;
      });

      try {
        final result = await BalanceService.instance.addRequest(
          lbpAmount: lbpAmount.isEmpty ? null : lbpAmount,
          usdAmount: usdAmount.isEmpty ? null : usdAmount,
        );

        if (dialogContext.mounted) {
          Navigator.of(dialogContext).pop();
        }

        if (!mounted) return;

        final message = result.message.trim().isEmpty
            ? 'Balance request submitted.'
            : result.message.trim();
        showSuccess(context, message);

        await ref
            .read(currentBalanceProvider.notifier)
            .refreshBalances(force: true);
        await ref.read(balanceHistoryProvider.notifier).fetch(reset: true);
        await ref
            .read(notificationCenterProvider.notifier)
            .refreshAll(resetList: true);
      } catch (e) {
        if (!mounted) return;
        setModalState(() {
          submitting = false;
          dialogError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final width = MediaQuery.of(dialogContext).size.width;
        final dialogWidth = width < 520 ? width - 24 : 420.0;
        return StatefulBuilder(
          builder: (dialogContext, setModalState) {
            return AlertDialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
              contentPadding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
              titlePadding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
              title: const Text('Add Balance'),
              content: SizedBox(
                width: dialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Submit LBP and/or USD amount. The backend may auto-add part of the request and keep the rest pending for admin approval.',
                      style: TextStyle(fontSize: 12.5, height: 1.35),
                    ),
                    if (hasDueInfo) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: .05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.blue.withValues(alpha: .16),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Max due balance',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (maxDueLbpText != null)
                                  _buildDueInfoChip(maxDueLbpText),
                                if (maxDueUsdText != null)
                                  _buildDueInfoChip(maxDueUsdText),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    TextField(
                      controller: lbpCtl,
                      enabled: !submitting,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'LBP amount',
                        hintText: '500000',
                        prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: usdCtl,
                      enabled: !submitting,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'USD amount',
                        hintText: '25',
                        prefixIcon: Icon(Icons.attach_money),
                      ),
                    ),
                    if (dialogError != null &&
                        dialogError!.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        dialogError!,
                        style:
                            const TextStyle(color: Colors.red, fontSize: 12.5),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: submitting
                      ? null
                      : () => submit(dialogContext, setModalState),
                  icon: submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(submitting ? 'Submitting...' : 'Submit'),
                ),
              ],
            );
          },
        );
      },
    );

    lbpCtl.dispose();
    usdCtl.dispose();
  }

  Widget _buildDueInfoChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.blue.withValues(alpha: .16)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Future<void> _showNoteDialog(BalanceEntry entry) async {
    if (!_hasBalanceNote(entry.note) || !mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final mq = MediaQuery.of(ctx);
        final maxDialogWidth = mq.size.width < 600
            ? (mq.size.width - 24).clamp(280.0, 520.0)
            : 760.0;

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxDialogWidth,
              maxHeight: mq.size.height * .82,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Balance #${entry.id} Note',
                          style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: _fg,
                              ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SingleChildScrollView(
                      child: buildPrettyNoteWidget(
                        entry.note,
                        baseStyle: const TextStyle(fontSize: 12, height: 1.25),
                        keyStyle: const TextStyle(
                          fontSize: 12,
                          height: 1.25,
                          fontWeight: FontWeight.w900,
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close),
                      label: const Text('Close'),
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

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(pageRefreshPulseProvider, (prev, next) {
      if (prev == next) return;
      final route = ModalRoute.of(context);
      if (route == null || route.isCurrent != true) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(balanceHistoryProvider.notifier).fetch(reset: true);
      });
    });

    final state = ref.watch(balanceHistoryProvider);
    final mq = MediaQuery.of(context);
    final w = mq.size.width;
    final isCompact = w < 980;
    final isPortrait = mq.orientation == Orientation.portrait;
    final useGrid = !isCompact || !isPortrait;

    return PageActions(
      actions: [
        PageAction(
            label: 'Add Balance',
            icon: Icons.add,
            onTap: () => _onAddBalance()),
        PageAction(
          label: 'Filter',
          icon: Icons.filter_list,
          onTap: _openFilters,
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isCompact && isPortrait) ...[
              _BalanceFiltersSummary(
                filters: state.filters,
                filterData: state.filterData,
                currencies: ref.watch(currencyProvider).all,
                fg: _fg,
                fgSoft: _fgSoft,
              ),
              const SizedBox(height: 12),
            ],
            if (state.loading && state.items.isNotEmpty) ...[
              const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: ScrollConfiguration(
                behavior: const EvolutionScrollBehavior(showScrollbars: false),
                child: useGrid
                    ? _BalanceGrid(
                        state: state,
                        fg: _fg,
                        fgSoft: _fgSoft,
                        vCtl: _vGridCtl,
                        hCtl: _hGridCtl,
                        onRefresh: () => ref
                            .read(balanceHistoryProvider.notifier)
                            .fetch(reset: true),
                        onLoadMore: () =>
                            ref.read(balanceHistoryProvider.notifier).fetch(),
                        onOpenNote: _showNoteDialog,
                      )
                    : _BalanceCardsList(
                        state: state,
                        fg: _fg,
                        fgSoft: _fgSoft,
                        vCtl: _vCardsCtl,
                        onRefresh: () => ref
                            .read(balanceHistoryProvider.notifier)
                            .fetch(reset: true),
                        onLoadMore: () =>
                            ref.read(balanceHistoryProvider.notifier).fetch(),
                        onOpenNote: _showNoteDialog,
                      ),
              ),
            ),
            if (isCompact && isPortrait && state.items.isNotEmpty) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${state.items.length} rows',
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

class _BalanceFiltersSummary extends StatelessWidget {
  final BalanceFilters filters;
  final BalanceFilterData? filterData;
  final List<Currency> currencies;
  final Color fg;
  final Color fgSoft;

  const _BalanceFiltersSummary({
    required this.filters,
    required this.filterData,
    required this.currencies,
    required this.fg,
    required this.fgSoft,
  });

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd');
    final chips = <String>[];
    if (filters.from != null) chips.add('From: ${df.format(filters.from!)}');
    if (filters.to != null) chips.add('To: ${df.format(filters.to!)}');
    if (filters.currencyId != null) {
      String? label;
      final backendCurrencies = filterData?.available?.currencies ??
          const <BalanceFilterCurrencyOption>[];
      for (final entry in backendCurrencies) {
        if (entry.id == filters.currencyId) {
          label = entry.label.trim().isNotEmpty
              ? entry.label.trim()
              : entry.code.trim().toUpperCase();
          break;
        }
      }
      if (label == null) {
        for (final currency in currencies) {
          if (currency.id == filters.currencyId) {
            label = currency.code;
            break;
          }
        }
      }
      chips.add('Currency: ${label ?? filters.currencyId}');
    }
    if (filters.userId != null) {
      String? userLabel;
      final users =
          filterData?.available?.users ?? const <BalanceFilterUserOption>[];
      for (final entry in users) {
        if (entry.id == filters.userId) {
          userLabel = entry.label.trim().isNotEmpty
              ? entry.label.trim()
              : entry.username;
          break;
        }
      }
      chips.add('User: ${userLabel ?? filters.userId}');
    }
    if (filters.status != null) {
      chips.add(filters.status == true ? 'Status: PAID' : 'Status: DUE');
    }
    if (filters.distinctUsers) {
      chips.add('Distinct users');
    }

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
          'Showing all balance history entries',
          style: TextStyle(
            color: fgSoft,
            fontWeight: FontWeight.w600,
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
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Active filters:',
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w800,
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
                  color: fg,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceCardsList extends StatelessWidget {
  final BalanceHistoryState state;
  final Color fg;
  final Color fgSoft;
  final ScrollController vCtl;
  final Future<void> Function() onRefresh;
  final VoidCallback onLoadMore;
  final Future<void> Function(BalanceEntry entry) onOpenNote;

  const _BalanceCardsList({
    required this.state,
    required this.fg,
    required this.fgSoft,
    required this.vCtl,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onOpenNote,
  });

  @override
  Widget build(BuildContext context) {
    if (state.loading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.items.isEmpty) {
      return const Center(child: Text('No balance entries.'));
    }

    final showLoadMore = state.hasMore && !state.loading;

    return Scrollbar(
      controller: vCtl,
      thumbVisibility: true,
      trackVisibility: true,
      child: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView.separated(
          controller: vCtl,
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: state.items.length + (showLoadMore ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (index >= state.items.length) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
                child: Center(
                  child: OutlinedButton.icon(
                    onPressed: onLoadMore,
                    icon: const Icon(Icons.expand_more),
                    label: const Text('Load more'),
                  ),
                ),
              );
            }

            final e = state.items[index];
            return _BalanceCard(
              entry: e,
              fg: fg,
              fgSoft: fgSoft,
              onOpenNote: onOpenNote,
            );
          },
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final BalanceEntry entry;
  final Color fg;
  final Color fgSoft;
  final Future<void> Function(BalanceEntry entry) onOpenNote;

  const _BalanceCard({
    required this.entry,
    required this.fg,
    required this.fgSoft,
    required this.onOpenNote,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = _balanceStatusColor(entry.status);
    final hasNote = _hasBalanceNote(entry.note);
    final w = MediaQuery.of(context).size.width;
    final wide = w >= 720;
    final username = entry.username?.trim() ?? '';

    final title = [
      if (wide) '#${entry.id}',
      wide
          ? '${entry.currencyCode.trim().toUpperCase()} ${MoneyFormat.format(entry.amount, currencyCode: entry.currencyCode)}'
          : (username.isNotEmpty
              ? username
              : '${entry.currencyCode.trim().toUpperCase()} ${MoneyFormat.format(entry.amount, currencyCode: entry.currencyCode)}'),
    ].where((e) => e.trim().isNotEmpty).join(' - ');

    final subtitle = [
      DateFormat('yyyy-MM-dd HH:mm').format(entry.date.toLocal()),
      if (wide && username.isNotEmpty) username,
    ].join(' · ');

    return Card(
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
            _BalanceStatusRail(
              status: entry.status,
              color: statusColor,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
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
                              const SizedBox(height: 6),
                              Text(
                                subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: fgSoft),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        _BalanceAmountPill(entry: entry),
                      ],
                    ),
                    if (hasNote) ...[
                      const SizedBox(height: 8),
                      _BalanceNotePreview(
                        note: entry.note,
                        fg: fg,
                        fgSoft: fgSoft,
                        onTap: () => onOpenNote(entry),
                      ),
                    ],
                    if (entry.balance != null || entry.balanceDue != null) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (entry.balance != null)
                            _BalanceMetaChip(
                              label: 'Balance',
                              value: _moneyOrDash(
                                entry.balance,
                                entry.currencyCode,
                              ),
                              textColor: const Color(0xFF1E7E34),
                              borderColor: const Color(0xFF1E7E34),
                            ),
                          if (entry.balanceDue != null)
                            _BalanceMetaChip(
                              label: 'Balance Due',
                              value: _moneyOrDash(
                                entry.balanceDue,
                                entry.currencyCode,
                              ),
                              textColor: const Color(0xFFE67E22),
                              borderColor: const Color(0xFFE67E22),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceAmountPill extends StatelessWidget {
  final BalanceEntry entry;

  const _BalanceAmountPill({required this.entry});

  @override
  Widget build(BuildContext context) {
    final cur = entry.currencyCode.trim().toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Amount',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFFD32F2F),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            MoneyFormat.format(entry.amount, currencyCode: entry.currencyCode),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1E7E34),
            ),
          ),
          if (cur.isNotEmpty)
            Text(
              cur,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E7E34),
              ),
            ),
        ],
      ),
    );
  }
}

class _BalanceNotePreview extends StatelessWidget {
  final dynamic note;
  final Color fg;
  final Color fgSoft;
  final VoidCallback onTap;

  const _BalanceNotePreview({
    required this.note,
    required this.fg,
    required this.fgSoft,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final preview = _balanceNotePreviewText(note);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        decoration: BoxDecoration(
          color: Colors.blueGrey.withValues(alpha: .05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blueGrey.withValues(alpha: .16)),
        ),
        child: Text(
          preview,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: fg,
            fontWeight: FontWeight.w600,
            height: 1.24,
          ),
        ),
      ),
    );
  }
}

class _BalanceMetaChip extends StatelessWidget {
  final String label;
  final String value;
  final Color textColor;
  final Color borderColor;

  const _BalanceMetaChip({
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
            fontSize: 11.5,
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

class _BalanceStatusRail extends StatelessWidget {
  final bool? status;
  final Color color;

  const _BalanceStatusRail({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    final label = _balanceStatusLabel(status);
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

class _BalanceGridCol {
  final String key;
  final String label;
  final double width;
  final TextAlign align;
  final String Function(BalanceEntry entry) cell;
  final TextStyle? Function(BalanceEntry entry)? cellStyle;

  const _BalanceGridCol({
    required this.key,
    required this.label,
    required this.width,
    required this.align,
    required this.cell,
    this.cellStyle,
  });
}

class _BalanceGrid extends StatelessWidget {
  final BalanceHistoryState state;
  final Color fg;
  final Color fgSoft;
  final ScrollController vCtl;
  final ScrollController hCtl;
  final Future<void> Function() onRefresh;
  final VoidCallback onLoadMore;
  final Future<void> Function(BalanceEntry entry) onOpenNote;

  const _BalanceGrid({
    required this.state,
    required this.fg,
    required this.fgSoft,
    required this.vCtl,
    required this.hCtl,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onOpenNote,
  });

  @override
  Widget build(BuildContext context) {
    if (state.loading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.items.isEmpty) {
      return const Center(child: Text('No balance entries.'));
    }

    final hasUser =
        state.items.any((e) => (e.username?.trim().isNotEmpty ?? false));
    final showLoadMore = state.hasMore && !state.loading;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = <_BalanceGridCol>[
          _BalanceGridCol(
            key: 'status_rail',
            label: 'Status',
            width: 28,
            align: TextAlign.center,
            cell: (e) => _balanceStatusLabel(e.status),
          ),
          _BalanceGridCol(
            key: 'id',
            label: 'Id',
            width: 56,
            align: TextAlign.left,
            cell: (e) => '#${e.id}',
          ),
          _BalanceGridCol(
            key: 'date',
            label: 'Date',
            width: 112,
            align: TextAlign.center,
            cell: (e) =>
                DateFormat('yyyy-MM-dd\nHH:mm:ss').format(e.date.toLocal()),
          ),
          if (hasUser)
            _BalanceGridCol(
              key: 'user',
              label: 'User',
              width: 130,
              align: TextAlign.left,
              cell: (e) => e.username ?? '',
            ),
          _BalanceGridCol(
            key: 'currency',
            label: 'Currency',
            width: 78,
            align: TextAlign.center,
            cell: (e) => e.currencyCode.trim().toUpperCase(),
          ),
          _BalanceGridCol(
            key: 'amount',
            label: 'Amount',
            width: 140,
            align: TextAlign.right,
            cell: (e) =>
                MoneyFormat.format(e.amount, currencyCode: e.currencyCode),
            cellStyle: (_) => const TextStyle(
              fontWeight: FontWeight.w900,
              color: Color(0xFF1E7E34),
            ),
          ),
          _BalanceGridCol(
            key: 'balance',
            label: 'Balance',
            width: 140,
            align: TextAlign.right,
            cell: (e) => _moneyOrDash(e.balance, e.currencyCode),
            cellStyle: (e) => TextStyle(
              fontWeight: FontWeight.w800,
              color: e.balance == null ? fgSoft : const Color(0xFF1E7E34),
            ),
          ),
          _BalanceGridCol(
            key: 'balance_due',
            label: 'Balance Due',
            width: 140,
            align: TextAlign.right,
            cell: (e) => _moneyOrDash(e.balanceDue, e.currencyCode),
            cellStyle: (e) => TextStyle(
              fontWeight: FontWeight.w800,
              color: e.balanceDue == null ? fgSoft : const Color(0xFFE67E22),
            ),
          ),
          _BalanceGridCol(
            key: 'note',
            label: 'Note',
            width: 240,
            align: TextAlign.left,
            cell: (e) => _balanceNotePreviewText(e.note),
            cellStyle: (e) => TextStyle(
              fontSize: 12,
              color: _hasBalanceNote(e.note) ? fg : fgSoft,
              fontWeight:
                  _hasBalanceNote(e.note) ? FontWeight.w700 : FontWeight.w600,
              height: 1.18,
            ),
          ),
          _BalanceGridCol(
            key: 'status',
            label: 'Status',
            width: 110,
            align: TextAlign.center,
            cell: (e) => _balanceStatusLabel(e.status),
            cellStyle: (e) => TextStyle(
              fontWeight: FontWeight.w800,
              color: _balanceStatusColor(e.status),
            ),
          ),
        ];

        final baseTableW =
            cols.fold<double>(0, (sum, col) => sum + col.width) + 2;

        final extraWidth = constraints.maxWidth > baseTableW
            ? constraints.maxWidth - baseTableW
            : 0.0;

        final effectiveCols = extraWidth > 0
            ? [
                ...cols.take(cols.length - 1),
                _BalanceGridCol(
                  key: cols.last.key,
                  label: cols.last.label,
                  width: cols.last.width + extraWidth,
                  align: cols.last.align,
                  cell: cols.last.cell,
                  cellStyle: cols.last.cellStyle,
                ),
              ]
            : cols;

        final tableW =
            effectiveCols.fold<double>(0, (sum, col) => sum + col.width) + 2;

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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
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

        Widget row(BalanceEntry e, int index) {
          final border = Colors.red.withValues(alpha: .16);
          final statusColor = _balanceStatusColor(e.status);
          final zebra =
              index.isEven ? Colors.white : Colors.grey.withValues(alpha: .028);

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
                          c.cell(e),
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

                  final style = c.cellStyle?.call(e) ??
                      TextStyle(
                        fontSize: 12,
                        color: fg,
                        fontWeight: FontWeight.w600,
                        height: 1.18,
                      );

                  if (c.key == 'note') {
                    final hasNote = _hasBalanceNote(e.note);
                    return SizedBox(
                      width: c.width,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 6,
                        ),
                        child: hasNote
                            ? InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => onOpenNote(e),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  child: Text(
                                    c.cell(e),
                                    textAlign: c.align,
                                    style: style,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                            : Text(
                                c.cell(e),
                                textAlign: c.align,
                                style: style,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                    );
                  }

                  return SizedBox(
                    width: c.width,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      child: Text(
                        c.cell(e),
                        textAlign: c.align,
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
          controller: hCtl,
          thumbVisibility: true,
          trackVisibility: true,
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: hCtl,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableW,
              height: constraints.maxHeight,
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
                        controller: vCtl,
                        thumbVisibility: true,
                        trackVisibility: true,
                        notificationPredicate: (notification) =>
                            notification.metrics.axis == Axis.vertical,
                        child: RefreshIndicator(
                          onRefresh: onRefresh,
                          child: ListView.builder(
                            controller: vCtl,
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount:
                                state.items.length + (showLoadMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index >= state.items.length) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                  child: Center(
                                    child: OutlinedButton.icon(
                                      onPressed: onLoadMore,
                                      icon: const Icon(Icons.expand_more),
                                      label: const Text('Load more'),
                                    ),
                                  ),
                                );
                              }
                              return row(state.items[index], index);
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
    );
  }
}

bool _hasBalanceNote(dynamic note) {
  final text = prettyNote(note).trim();
  return text.isNotEmpty && text != '-';
}

String _balanceNotePreviewText(dynamic note) {
  final text = prettyNote(note)
      .replaceAll('\r', ' ')
      .replaceAll('\n', '  •  ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return text.isEmpty ? '—' : text;
}

String _moneyOrDash(num? value, String currencyCode) {
  if (value == null) return '—';
  return MoneyFormat.format(value, currencyCode: currencyCode);
}

String _balanceStatusLabel(bool? status) {
  if (status == true) return 'PAID';
  if (status == false) return 'DUE';
  return '—';
}

Color _balanceStatusColor(bool? status) {
  if (status == true) return const Color(0xFF1E7E34);
  if (status == false) return const Color(0xFFE67E22);
  return const Color(0xFF7F8C8D);
}
