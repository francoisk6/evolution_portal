import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/app_scroll_behavior.dart';
import '../../data/models/dashboard_aggregates.dart';
import '../../state/currency_provider.dart';
import '../../state/dashboard_provider.dart';
import '../../state/session_provider.dart';
import '../../utils/money_format.dart';
import '../../widgets/page_action_bar.dart' show PageActions, PageAction;

enum DashboardMetric {
  dealer,
  adminProfit, // "A Profit" – priority 1 default when available
  dealerProfit, // "D Profit" – priority 2 default when available
  customer,
  count,
  cost,
}

class MyDashboardPage extends ConsumerStatefulWidget {
  const MyDashboardPage({super.key});

  @override
  ConsumerState<MyDashboardPage> createState() => _MyDashboardPageState();
}

class _MyDashboardPageState extends ConsumerState<MyDashboardPage> {
  final _df = DateFormat('yyyy-MM-dd');
  DashboardMetric _metric = DashboardMetric.dealerProfit;
  bool _metricInitialized = false;
  final _blockKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(dashboardProvider.notifier).fetch());
  }

  void _scrollToBlock(String title) {
    final ctx = _blockKeys[title]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      alignment: 0.05,
    );
  }

  GlobalKey _keyFor(String title) =>
      _blockKeys.putIfAbsent(title, GlobalKey.new);

  Future<void> _openFilters() async {
    final st = ref.read(dashboardProvider);
    final current = st.filters;

    final fromCtl = TextEditingController(
      text: current.from == null ? '' : _df.format(current.from!),
    );
    final toCtl = TextEditingController(
      text: current.to == null ? '' : _df.format(current.to!),
    );
    final topCtl = TextEditingController(text: '${current.top}');
    final userIdCtl = TextEditingController(
      text: current.userId == null ? '' : '${current.userId}',
    );
    final userIdsCtl = TextEditingController(text: current.userIds ?? '');

    String? currency =
        (current.currency?.trim().isEmpty ?? true) ? null : current.currency;
    String? status =
        (current.status?.trim().isEmpty ?? true) ? null : current.status;

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
                      now.subtract(const Duration(days: 30)))
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
                  fromCtl.text = _df.format(d);
                } else {
                  toCtl.text = _df.format(d);
                }
              });
            }

            final appCurrencies = ref.read(currencyProvider).all;
            final currencyItems = <DropdownMenuItem<String?>>[
              DropdownMenuItem<String?>(
                value: null,
                child: Text(
                  'Default (current: ${ref.read(currencyProvider).selected.code})',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const DropdownMenuItem<String?>(
                value: kDashboardCurrencyAll,
                child: Text(
                  'All currencies (no filter)',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              ...appCurrencies.map(
                (c) => DropdownMenuItem<String?>(
                  value: c.code,
                  child: Text(c.code, style: const TextStyle(fontSize: 12)),
                ),
              ),
            ];

            void clearFilters() {
              setModalState(() {
                fromCtl.clear();
                toCtl.clear();
                currency = kDashboardCurrencyAll;
                status = null;
                topCtl.text = '10';
                userIdCtl.clear();
                userIdsCtl.clear();
              });
            }

            void applyFilters() {
              int? parseIntOrNull(String s) {
                final t = s.trim();
                if (t.isEmpty) return null;
                return int.tryParse(t);
              }

              final top = int.tryParse(topCtl.text.trim()) ?? 10;
              final userId = parseIntOrNull(userIdCtl.text);
              final userIds = userIdsCtl.text.trim().isEmpty
                  ? null
                  : userIdsCtl.text.trim();
              ref.read(dashboardProvider.notifier).setFilters(
                DashboardFilters(
                  from: parseYmd(fromCtl.text),
                  to: parseYmd(toCtl.text),
                  currency: currency,
                  status: status,
                  top: top,
                  userId: userId,
                  userIds: userIds,
                ),
              );
              Navigator.of(ctx).pop();
              ref.read(dashboardProvider.notifier).fetch();
            }

            Widget buildOverlayActions() {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'dash_filter_cancel',
                    tooltip: 'Cancel',
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    onPressed: () => Navigator.pop(ctx),
                    child: const Icon(Icons.close),
                  ),
                  const SizedBox(height: 10),
                  FloatingActionButton.small(
                    heroTag: 'dash_filter_clear',
                    tooltip: 'Clear',
                    backgroundColor: Colors.white,
                    foregroundColor: Theme.of(ctx).colorScheme.primary,
                    onPressed: clearFilters,
                    child: const Icon(Icons.backspace_outlined),
                  ),
                  const SizedBox(height: 10),
                  FloatingActionButton.small(
                    heroTag: 'dash_filter_apply',
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
                        maxHeight: MediaQuery.of(ctx).size.height * 0.92,
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
                              const Icon(Icons.dashboard_customize),
                              const SizedBox(width: 8),
                              Text(
                                'Dashboard Filters',
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
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: fromCtl,
                                  readOnly: true,
                                  style: const TextStyle(fontSize: 12),
                                  decoration: InputDecoration(
                                    labelText: 'From (YYYY-MM-DD)',
                                    labelStyle: const TextStyle(fontSize: 12),
                                    isDense: true,
                                    suffixIcon: fromCtl.text.isEmpty
                                        ? null
                                        : IconButton(
                                            tooltip: 'Clear',
                                            icon: const Icon(Icons.clear),
                                            onPressed: () {
                                              setModalState(
                                                  () => fromCtl.clear());
                                            },
                                          ),
                                  ),
                                  onTap: () => pickDate(isFrom: true),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: toCtl,
                                  readOnly: true,
                                  style: const TextStyle(fontSize: 12),
                                  decoration: InputDecoration(
                                    labelText: 'To (YYYY-MM-DD)',
                                    labelStyle: const TextStyle(fontSize: 12),
                                    isDense: true,
                                    suffixIcon: toCtl.text.isEmpty
                                        ? null
                                        : IconButton(
                                            tooltip: 'Clear',
                                            icon: const Icon(Icons.clear),
                                            onPressed: () {
                                              setModalState(
                                                  () => toCtl.clear());
                                            },
                                          ),
                                  ),
                                  onTap: () => pickDate(isFrom: false),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String?>(
                            initialValue: currency,
                            decoration: const InputDecoration(
                              labelText: 'Currency',
                              labelStyle: TextStyle(fontSize: 12),
                              isDense: true,
                            ),
                            items: currencyItems,
                            onChanged: (v) => currency = v,
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String?>(
                            initialValue: status,
                            decoration: const InputDecoration(
                              labelText: 'Status',
                              labelStyle: TextStyle(fontSize: 12),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem<String?>(
                                value: null,
                                child: Text(
                                  'All statuses',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              DropdownMenuItem<String?>(
                                value: 'Done',
                                child: Text(
                                  'Done',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              DropdownMenuItem<String?>(
                                value: 'wait',
                                child: Text(
                                  'wait',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                            onChanged: (v) => status = v,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: topCtl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 12),
                            decoration: const InputDecoration(
                              labelText: 'Top X (1..50)',
                              labelStyle: TextStyle(fontSize: 12),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (st.meta?.isSuperuser ?? false) ...[
                            Text(
                              'Superuser filters',
                              style: Theme.of(ctx)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: userIdCtl,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(fontSize: 12),
                              decoration: const InputDecoration(
                                labelText: 'User ID (single)',
                                labelStyle: TextStyle(fontSize: 12),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: userIdsCtl,
                              style: const TextStyle(fontSize: 12),
                              decoration: const InputDecoration(
                                labelText: 'User IDs (comma-separated)',
                                labelStyle: TextStyle(fontSize: 12),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tip: fill either User ID or User IDs.',
                              style: Theme.of(ctx)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: Colors.grey.shade700),
                            ),
                            const SizedBox(height: 12),
                          ],
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
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<DashboardState>(dashboardProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dashboard load failed: ${next.error}')),
        );
      }
    });

    ref.listen<CurrencyState>(currencyProvider, (prev, next) {
      if (prev?.selectedId != next.selectedId) {
        ref.read(dashboardProvider.notifier).refresh();
      }
    });

    final st = ref.watch(dashboardProvider);
    final hideDealerPrice = ref.watch(sessionProvider).hideDealerPrice;
    final appCurrency = ref.watch(currencyProvider).selected.code;

    final data = st.data;

    // ── availability flags ──────────────────────────────────────────────────
    bool _anyNonZero(Iterable<DashboardItem> items,
            double Function(DashboardAmounts) pick) =>
        items.any((it) => pick(it.amounts) != 0);

    final allItems = data == null
        ? <DashboardItem>[]
        : [
            ...data.topUsers,
            ...data.topGroupHeads,
            ...data.topGroupDetails,
            ...data.topGroupSubdetails,
            ...data.topBrands,
          ];

    final hasAdminProfit = _anyNonZero(allItems, (a) => a.adminProfit);
    final hasDealerProfit = _anyNonZero(allItems, (a) => a.dealerProfit);

    // ── auto-select metric once data first arrives ──────────────────────────
    if (data != null && !_metricInitialized) {
      _metricInitialized = true;
      final autoMetric = hasAdminProfit
          ? DashboardMetric.adminProfit
          : hasDealerProfit
              ? DashboardMetric.dealerProfit
              : DashboardMetric.customer;
      if (_metric != autoMetric) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _metric = autoMetric);
        });
      }
    }

    // ── effective metric (respect hideDealerPrice) ─────────────────────────
    final metric = hideDealerPrice && _metric == DashboardMetric.dealer
        ? DashboardMetric.customer
        : _metric;

    double metricValueFor(DashboardItem it) {
      switch (metric) {
        case DashboardMetric.dealer:
          return it.amounts.dealer;
        case DashboardMetric.customer:
          return it.amounts.customer;
        case DashboardMetric.adminProfit:
          return it.amounts.adminProfit;
        case DashboardMetric.dealerProfit:
          return it.amounts.dealerProfit;
        case DashboardMetric.cost:
          return it.amounts.cost;
        case DashboardMetric.count:
          return it.count.toDouble();
      }
    }

    String metricLabelFor() {
      switch (metric) {
        case DashboardMetric.dealer:
          return 'Dealer';
        case DashboardMetric.customer:
          return 'Customer';
        case DashboardMetric.adminProfit:
          return 'A Profit';
        case DashboardMetric.dealerProfit:
          return 'D Profit';
        case DashboardMetric.cost:
          return 'Cost';
        case DashboardMetric.count:
          return 'Count';
      }
    }

    String fmtValueFor(num v, {required String currencyCode}) {
      if (metric == DashboardMetric.count) return v.toStringAsFixed(0);
      return MoneyFormat.format(v, currencyCode: currencyCode);
    }

    final currencyCode = (st.filters.currency == null ||
            (st.filters.currency?.trim().isEmpty ?? true))
        ? appCurrency
        : (st.filters.currency == kDashboardCurrencyAll
            ? appCurrency
            : st.filters.currency!.trim().toUpperCase());

    List<_DashboardBlock> blocksForAllUsers() {
      if (data == null) return const [];
      return [
        _DashboardBlock(title: 'Top Sectors', items: data.topGroupHeads),
        _DashboardBlock(title: 'Top Categories', items: data.topGroupDetails),
        _DashboardBlock(title: 'Top Tabs', items: data.topGroupSubdetails),
        _DashboardBlock(title: 'Top Brands', items: data.topBrands),
      ].where((b) => b.items.isNotEmpty).toList(growable: false);
    }

    List<_DashboardBlock> blocksForSuperuser() {
      if (data == null) return const [];
      return [
        _DashboardBlock(title: 'Top Users', items: data.topUsers),
        _DashboardBlock(title: 'Top Admin Sectors', items: data.topSectors),
      ].where((b) => b.items.isNotEmpty).toList(growable: false);
    }

    final superBlocks = blocksForSuperuser();
    final userBlocks = blocksForAllUsers();
    final visibleBlocks = <_DashboardBlock>[...superBlocks, ...userBlocks];

    final body = RefreshIndicator(
      onRefresh: () => ref.read(dashboardProvider.notifier).refresh(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: st.loading && data == null
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 80),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _FiltersChipsRow(
                          filters: st.filters,
                          appCurrency: appCurrency,
                        ),
                        const SizedBox(height: 10),
                        _MetricPicker(
                          isSuperuser: (st.meta?.isSuperuser ?? false),
                          hideDealerPrice: hideDealerPrice,
                          hasAdminProfit: hasAdminProfit,
                          hasDealerProfit: hasDealerProfit,
                          value: metric,
                          onChanged: (m) => setState(() => _metric = m),
                        ),
                        if (visibleBlocks.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _SelectedPerformanceCard(
                            blocks: visibleBlocks,
                            serverTotals: data?.totals,
                            metricLabel: metricLabelFor(),
                            metricValue: metricValueFor,
                            currencyCode: currencyCode,
                            fmtValue: (v) =>
                                fmtValueFor(v, currencyCode: currencyCode),
                            onBlockTap: _scrollToBlock,
                          ),
                        ],
                        const SizedBox(height: 12),
                        if (superBlocks.isNotEmpty) ...[
                          Text(
                            'Admin performance',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 8),
                          ...superBlocks.map(
                            (b) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _DashboardBlockCard(
                                key: _keyFor(b.title),
                                title: b.title,
                                items: b.items,
                                metricLabel: metricLabelFor(),
                                metricValue: metricValueFor,
                                currencyCode: currencyCode,
                                fmtValue: (v) => fmtValueFor(
                                  v,
                                  currencyCode: currencyCode,
                                ),
                                showCost: metric == DashboardMetric.cost,
                                hideDealerPrice: hideDealerPrice,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                        if (userBlocks.isNotEmpty) ...[
                          Text(
                            'Catalog performance',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 8),
                          ...userBlocks.map(
                            (b) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _DashboardBlockCard(
                                key: _keyFor(b.title),
                                title: b.title,
                                items: b.items,
                                metricLabel: metricLabelFor(),
                                metricValue: metricValueFor,
                                currencyCode: currencyCode,
                                fmtValue: (v) => fmtValueFor(
                                  v,
                                  currencyCode: currencyCode,
                                ),
                                showCost: false,
                                hideDealerPrice: hideDealerPrice,
                              ),
                            ),
                          ),
                        ],
                        if ((data?.hasAnyData ?? false) == false)
                          Padding(
                            padding: const EdgeInsets.only(top: 28),
                            child: Center(
                              child: Text(
                                'No dashboard data for the current filters.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: Colors.grey.shade700),
                              ),
                            ),
                          ),
                        if (st.loading && data != null)
                          const Padding(
                            padding: EdgeInsets.only(top: 8, bottom: 16),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        const SizedBox(height: 24),
                      ],
                    ),
            ),
          );
        },
      ),
    );

    return PageActions(
      actions: [
        PageAction(
          label: 'Filter',
          icon: Icons.filter_list,
          onTap: _openFilters,
        ),
        PageAction(
          label: 'Refresh',
          icon: Icons.refresh,
          onTap: () => ref.read(dashboardProvider.notifier).refresh(),
        ),
      ],
      child: body,
    );
  }
}

class _DashboardBlock {
  final String title;
  final List<DashboardItem> items;
  const _DashboardBlock({required this.title, required this.items});
}

class _FiltersChipsRow extends ConsumerWidget {
  final DashboardFilters filters;
  final String appCurrency;

  const _FiltersChipsRow({required this.filters, required this.appCurrency});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String currencyText;
    if (filters.currency == null ||
        (filters.currency?.trim().isEmpty ?? true)) {
      currencyText = 'Currency: $appCurrency (default)';
    } else if (filters.currency == kDashboardCurrencyAll) {
      currencyText = 'Currency: ALL';
    } else {
      currencyText = 'Currency: ${filters.currency!.trim().toUpperCase()}';
    }

    String dateText() {
      if (filters.from == null && filters.to == null) {
        return 'Date: last 30 days (default)';
      }
      final f = filters.from == null
          ? '…'
          : DateFormat('yyyy-MM-dd').format(filters.from!);
      final t = filters.to == null
          ? '…'
          : DateFormat('yyyy-MM-dd').format(filters.to!);
      return 'Date: $f → $t';
    }

    final chips = <String>[
      dateText(),
      currencyText,
      'Status: ${(filters.status == null || filters.status!.trim().isEmpty) ? 'ALL' : filters.status}',
      'Top: ${filters.top}',
      if (filters.userId != null) 'User: ${filters.userId}',
      if (filters.userIds != null && filters.userIds!.trim().isNotEmpty)
        'Users: ${filters.userIds}',
    ];

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tune, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Current selection',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: chips
                  .map(
                    (t) => Chip(
                      label: Text(
                        t,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricPicker extends StatelessWidget {
  final bool isSuperuser;
  final bool hideDealerPrice;
  final bool hasAdminProfit;
  final bool hasDealerProfit;
  final DashboardMetric value;
  final ValueChanged<DashboardMetric> onChanged;

  const _MetricPicker({
    required this.isSuperuser,
    required this.hideDealerPrice,
    required this.hasAdminProfit,
    required this.hasDealerProfit,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final items = <DashboardMetric, String>{
      if (!hideDealerPrice) DashboardMetric.dealer: 'Dealer',
      DashboardMetric.customer: 'Customer',
      if (hasAdminProfit) DashboardMetric.adminProfit: 'A Profit',
      if (hasDealerProfit) DashboardMetric.dealerProfit: 'D Profit',
      DashboardMetric.count: 'Count',
      if (isSuperuser) DashboardMetric.cost: 'Cost',
    };

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.entries
          .map(
            (e) => ChoiceChip(
              label: Text(e.value, style: const TextStyle(fontSize: 12)),
              selected: value == e.key,
              onSelected: (_) => onChanged(e.key),
              visualDensity: VisualDensity.compact,
            ),
          )
          .toList(growable: false),
    );
  }
}

class _SelectedPerformanceCard extends StatelessWidget {
  final List<_DashboardBlock> blocks;
  final DashboardTotals? serverTotals;
  final String metricLabel;
  final double Function(DashboardItem) metricValue;
  final String currencyCode;
  final String Function(num) fmtValue;
  final void Function(String blockTitle)? onBlockTap;

  const _SelectedPerformanceCard({
    required this.blocks,
    required this.serverTotals,
    required this.metricLabel,
    required this.metricValue,
    required this.currencyCode,
    required this.fmtValue,
    this.onBlockTap,
  });

  List<Color> _palette(BuildContext context) {
    return [
      Theme.of(context).colorScheme.primary,
      Colors.teal.shade600,
      Colors.orange.shade700,
      Colors.purple.shade600,
      Colors.indigo.shade500,
      Colors.red.shade400,
      Colors.green.shade600,
      Colors.brown.shade500,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final entries = <_PerformanceEntry>[];

    for (final block in blocks) {
      if (block.items.isEmpty) continue;

      DashboardItem? bestItem;
      var bestValue = double.negativeInfinity;
      for (final item in block.items) {
        final value = metricValue(item);
        if (bestItem == null || value > bestValue) {
          bestItem = item;
          bestValue = value;
        }
      }

      if (bestItem != null) {
        entries.add(
          _PerformanceEntry(
            blockTitle: block.title,
            itemLabel: bestItem.label,
            value: bestValue.isFinite ? bestValue : 0,
            rowCount: block.items.length,
          ),
        );
      }
    }

    if (entries.isEmpty) return const SizedBox.shrink();

    final bestEntry = entries.reduce((a, b) => a.value >= b.value ? a : b);

    // Use server-provided totals (accurate, with currency conversion for ALL currencies)
    final grandTotal = serverTotals?.metricValue(metricLabel) ?? 0.0;
    final grandTotalCurrency = serverTotals?.currency ?? currencyCode;
    // If server total is in a different currency than the current filter (ALL→LBP),
    // format using that currency instead of the filter currency.
    final fmtGrandTotal = metricLabel == 'Count'
        ? grandTotal.toStringAsFixed(0)
        : (grandTotalCurrency != currencyCode
            ? MoneyFormat.format(grandTotal, currencyCode: grandTotalCurrency)
            : fmtValue(grandTotal));

    final palette = _palette(context);
    entries.sort((a, b) => b.value.compareTo(a.value));

    final chartData = List<_ChartDatum>.generate(
      entries.length,
      (index) => _ChartDatum(
        label: entries[index].blockTitle,
        subtitle: entries[index].itemLabel,
        value: entries[index].value,
        color: palette[index % palette.length],
      ),
    );

    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.bar_chart, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Performance of selected metric',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                Text(
                  metricLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Colors.grey.shade700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Readable chart view for the current top lists. The vertical bars compare the visible best result in each list, and the donut shows the share distribution.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade700,
                    height: 1.2,
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _DashboardKpiTile(
                  label: 'Selected metric',
                  value: metricLabel,
                  icon: Icons.check_circle_outline,
                ),
                _DashboardKpiTile(
                  label: 'Best Sector',
                  value: metricLabel == 'Count'
                      ? bestEntry.value.toStringAsFixed(0)
                      : fmtValue(bestEntry.value),
                  helper: bestEntry.itemLabel,
                  icon: Icons.emoji_events_outlined,
                ),
                _DashboardKpiTile(
                  label: 'Total result',
                  value: fmtGrandTotal,
                  helper: grandTotalCurrency != currencyCode
                      ? 'Converted to $grandTotalCurrency'
                      : null,
                  icon: Icons.calculate_outlined,
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final twoCols = constraints.maxWidth >= 760;
                final panelWidth = twoCols
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth;

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: panelWidth,
                      child: _ChartPanel(
                        title: 'Vertical comparison',
                        subtitle: 'Best visible result from each top list',
                        child: SizedBox(
                          height: 230,
                          child: _VerticalBarChart(
                            data: chartData,
                            valueFormatter: (v) => metricLabel == 'Count'
                                ? v.toStringAsFixed(0)
                                : fmtValue(v),
                            onBarTap: onBlockTap,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: panelWidth,
                      child: _ChartPanel(
                        title: 'Share distribution',
                        subtitle: 'Select a list — top items + Others = grand total',
                        child: _TabbedDonutSection(
                          blocks: blocks,
                          serverTotals: serverTotals,
                          metricLabel: metricLabel,
                          metricValue: metricValue,
                          fmtValue: fmtValue,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Text(
              'Legend',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            ...chartData.map(
              (datum) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      margin: const EdgeInsets.only(top: 3),
                      decoration: BoxDecoration(
                        color: datum.color,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            datum.label,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            datum.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      metricLabel == 'Count'
                          ? datum.value.toStringAsFixed(0)
                          : fmtValue(datum.value),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
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
}

class _PerformanceEntry {
  final String blockTitle;
  final String itemLabel;
  final double value;
  final int rowCount;

  const _PerformanceEntry({
    required this.blockTitle,
    required this.itemLabel,
    required this.value,
    required this.rowCount,
  });
}

class _ChartDatum {
  final String label;
  final String subtitle;
  final double value;
  final Color color;

  const _ChartDatum({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.color,
  });
}

class _DashboardKpiTile extends StatelessWidget {
  final String label;
  final String value;
  final String? helper;
  final IconData icon;

  const _DashboardKpiTile({
    required this.label,
    required this.value,
    required this.icon,
    this.helper,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (helper != null && helper!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    helper!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _ChartPanel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _VerticalBarChart extends StatelessWidget {
  final List<_ChartDatum> data;
  final String Function(double) valueFormatter;
  final void Function(String blockTitle)? onBarTap;

  const _VerticalBarChart({
    required this.data,
    required this.valueFormatter,
    this.onBarTap,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Center(child: Text('No chart data'));
    }

    final maxValue = data.fold<double>(0, (p, e) => math.max(p, e.value));
    final denom = maxValue <= 0 ? 1.0 : maxValue;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: data
          .map(
            (datum) => Expanded(
              child: GestureDetector(
                onTap: onBarTap != null ? () => onBarTap!(datum.label) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        valueFormatter(datum.value),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            heightFactor:
                                (datum.value <= 0 ? 0.0 : (datum.value / denom))
                                    .clamp(0.0, 1.0)
                                    .toDouble(),
                            widthFactor: 1,
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 8),
                              decoration: BoxDecoration(
                                color: datum.color,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        datum.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (datum.subtitle.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          datum.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _DonutChartSection extends StatefulWidget {
  final List<_ChartDatum> data;
  final double totalValue;
  final String centerLabel;
  final String centerValue;
  final String Function(double) valueFormatter;

  const _DonutChartSection({
    required this.data,
    required this.totalValue,
    required this.centerLabel,
    required this.centerValue,
    required this.valueFormatter,
  });

  @override
  State<_DonutChartSection> createState() => _DonutChartSectionState();
}

class _DonutChartSectionState extends State<_DonutChartSection> {
  int? _hoveredIndex;
  Offset? _hoverPos;
  double _paintSide = 0;

  int? _hitTest(Offset pos) {
    if (_paintSide <= 0 || widget.totalValue <= 0) return null;
    final cx = _paintSide / 2;
    final cy = _paintSide / 2;
    final dx = pos.dx - cx;
    final dy = pos.dy - cy;
    final dist = math.sqrt(dx * dx + dy * dy);
    final strokeWidth = math.max(14.0, _paintSide * 0.14);
    final radius = _paintSide / 2 - strokeWidth / 2;
    if (dist < radius - strokeWidth / 2 || dist > radius + strokeWidth / 2) {
      return null;
    }
    // Angle from 12-o'clock clockwise, range [0, 2π)
    final angle =
        (math.atan2(dy, dx) + math.pi / 2 + 2 * math.pi) % (2 * math.pi);
    double start = 0;
    for (int i = 0; i < widget.data.length; i++) {
      final v = widget.data[i].value;
      if (v <= 0) continue;
      final sweep = (v / widget.totalValue) * 2 * math.pi;
      if (angle >= start && angle < start + sweep) return i;
      start += sweep;
    }
    return null;
  }

  void _onHover(Offset pos) {
    final idx = _hitTest(pos);
    setState(() {
      _hoveredIndex = idx;
      _hoverPos = idx != null ? pos : null;
    });
  }

  void _onExit() => setState(() {
        _hoveredIndex = null;
        _hoverPos = null;
      });

  Widget _buildTooltip(int index, Offset pos) {
    if (index >= widget.data.length) return const SizedBox.shrink();
    final datum = widget.data[index];
    final share = widget.totalValue <= 0
        ? 0.0
        : (datum.value <= 0 ? 0.0 : datum.value) / widget.totalValue * 100;
    final left =
        pos.dx + 8 > _paintSide - 130 ? pos.dx - 138.0 : pos.dx + 8.0;
    final top = pos.dy - 24 < 0 ? pos.dy + 8.0 : pos.dy - 24.0;
    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 160),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                datum.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${share.toStringAsFixed(1)}%  •  ${widget.valueFormatter(datum.value)}',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final totalValue = widget.totalValue;

    return Row(
      children: [
        Expanded(
          flex: 4,
          child: LayoutBuilder(
            builder: (context, constraints) {
              _paintSide = constraints.maxWidth;
              return SizedBox.square(
                dimension: _paintSide,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    MouseRegion(
                      onHover: (e) => _onHover(e.localPosition),
                      onExit: (_) => _onExit(),
                      child: GestureDetector(
                        onTapDown: (e) => _onHover(e.localPosition),
                        onTapUp: (_) => _onExit(),
                        child: CustomPaint(
                          size: Size(_paintSide, _paintSide),
                          painter: _DonutChartPainter(
                            data: data,
                            totalValue: totalValue,
                            baseColor: Colors.grey.shade200,
                            hoveredIndex: _hoveredIndex,
                          ),
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.centerLabel,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.centerValue,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    if (_hoveredIndex != null && _hoverPos != null)
                      _buildTooltip(_hoveredIndex!, _hoverPos!),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 5,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: data.map(
                (datum) {
                  final share = totalValue <= 0
                      ? 0.0
                      : ((datum.value <= 0 ? 0 : datum.value) / totalValue) *
                          100;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.only(top: 3),
                          decoration: BoxDecoration(
                            color: datum.color,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                datum.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                '${share.toStringAsFixed(1)}% • ${widget.valueFormatter(datum.value)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ).toList(growable: false),
            ),
          ),
        ),
      ],
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final List<_ChartDatum> data;
  final double totalValue;
  final Color baseColor;
  final int? hoveredIndex;

  const _DonutChartPainter({
    required this.data,
    required this.totalValue,
    required this.baseColor,
    this.hoveredIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = math.max(14.0, size.shortestSide * 0.14);
    final rect = Offset.zero & size;
    final radius = (math.min(size.width, size.height) / 2) - strokeWidth / 2;
    final arcRect = Rect.fromCircle(center: rect.center, radius: radius);

    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      math.pi * 2,
      false,
      Paint()
        ..color = baseColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt,
    );

    if (data.isEmpty || totalValue <= 0) return;

    // Precompute angles
    final startAngles = <double>[];
    final sweeps = <double>[];
    var angle = -math.pi / 2;
    for (final datum in data) {
      startAngles.add(angle);
      final v = datum.value <= 0 ? 0.0 : datum.value;
      final sweep = v > 0 ? (v / totalValue) * math.pi * 2 : 0.0;
      sweeps.add(sweep);
      angle += sweep;
    }

    // First pass: non-hovered segments (dimmed when something is hovered)
    for (int i = 0; i < data.length; i++) {
      if (sweeps[i] <= 0 || i == hoveredIndex) continue;
      canvas.drawArc(
        arcRect,
        startAngles[i],
        sweeps[i],
        false,
        Paint()
          ..color = hoveredIndex != null
              ? data[i].color.withValues(alpha: 0.45)
              : data[i].color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.butt,
      );
    }

    // Second pass: hovered segment on top, slightly wider
    if (hoveredIndex != null &&
        hoveredIndex! < data.length &&
        sweeps[hoveredIndex!] > 0) {
      final hw = strokeWidth * 1.28;
      final hr = (math.min(size.width, size.height) / 2) - hw / 2;
      canvas.drawArc(
        Rect.fromCircle(center: rect.center, radius: hr),
        startAngles[hoveredIndex!],
        sweeps[hoveredIndex!],
        false,
        Paint()
          ..color = data[hoveredIndex!].color
          ..style = PaintingStyle.stroke
          ..strokeWidth = hw
          ..strokeCap = StrokeCap.butt,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.totalValue != totalValue ||
        oldDelegate.baseColor != baseColor ||
        oldDelegate.hoveredIndex != hoveredIndex;
  }
}

class _TabbedDonutSection extends StatefulWidget {
  final List<_DashboardBlock> blocks;
  final DashboardTotals? serverTotals;
  final String metricLabel;
  final double Function(DashboardItem) metricValue;
  final String Function(num) fmtValue;

  const _TabbedDonutSection({
    required this.blocks,
    required this.serverTotals,
    required this.metricLabel,
    required this.metricValue,
    required this.fmtValue,
  });

  @override
  State<_TabbedDonutSection> createState() => _TabbedDonutSectionState();
}

class _TabbedDonutSectionState extends State<_TabbedDonutSection> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final blocks = widget.blocks;
    if (blocks.isEmpty) return const SizedBox.shrink();

    final tab = _tab.clamp(0, blocks.length - 1);
    final block = blocks[tab];
    final grandTotal = widget.serverTotals?.metricValue(widget.metricLabel) ?? 0.0;

    final palette = [
      Theme.of(context).colorScheme.primary,
      Colors.teal.shade600,
      Colors.orange.shade700,
      Colors.purple.shade600,
      Colors.indigo.shade500,
      Colors.red.shade400,
      Colors.green.shade600,
      Colors.brown.shade500,
    ];

    final sortedItems = [...block.items]..sort(
        (a, b) => widget.metricValue(b).compareTo(widget.metricValue(a)),
      );
    final chartData = <_ChartDatum>[];
    double blockSum = 0;
    for (int i = 0; i < sortedItems.length; i++) {
      final v = math.max(0.0, widget.metricValue(sortedItems[i]));
      blockSum += v;
      chartData.add(_ChartDatum(
        label: sortedItems[i].label,
        subtitle: '',
        value: v,
        color: palette[i % palette.length],
      ));
    }

    final others = grandTotal - blockSum;
    if (others > 1) {
      chartData.add(_ChartDatum(
        label: 'Others',
        subtitle: '',
        value: others,
        color: Colors.grey.shade400,
      ));
    }

    final effectiveTotal = grandTotal > 0 ? grandTotal : blockSum;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(blocks.length, (i) {
              return Padding(
                padding: EdgeInsets.only(right: i < blocks.length - 1 ? 6 : 0),
                child: ChoiceChip(
                  label: Text(
                    blocks[i].title,
                    style: const TextStyle(fontSize: 11),
                  ),
                  selected: i == tab,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _tab = i),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: _DonutChartSection(
            data: chartData,
            totalValue: effectiveTotal,
            centerLabel: widget.metricLabel,
            centerValue: widget.metricLabel == 'Count'
                ? effectiveTotal.toStringAsFixed(0)
                : widget.fmtValue(effectiveTotal),
            valueFormatter: widget.fmtValue,
          ),
        ),
      ],
    );
  }
}

class _DashboardBlockCard extends StatelessWidget {
  final String title;
  final List<DashboardItem> items;
  final String metricLabel;
  final double Function(DashboardItem) metricValue;
  final String currencyCode;
  final String Function(num) fmtValue;
  final bool showCost;
  final bool hideDealerPrice;

  const _DashboardBlockCard({
    super.key,
    required this.title,
    required this.items,
    required this.metricLabel,
    required this.metricValue,
    required this.currencyCode,
    required this.fmtValue,
    required this.showCost,
    required this.hideDealerPrice,
  });

  @override
  Widget build(BuildContext context) {
    final sortedItems = [...items]..sort(
        (a, b) => metricValue(b).compareTo(metricValue(a)),
      );
    final maxV = sortedItems.isEmpty
        ? 0.0
        : sortedItems
            .map(metricValue)
            .fold<double>(0, (p, v) => math.max(p, v));
    final denom = (maxV <= 0) ? 1.0 : maxV;
    final barColor = Theme.of(context).colorScheme.primary;

    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  '$metricLabel chart',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey.shade700),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Horizontal bar chart for the current top results.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade700,
                  ),
            ),
            const SizedBox(height: 12),
            ...List.generate(sortedItems.length, (index) {
              final it = sortedItems[index];
              final v = metricValue(it);
              final pct =
                  (v <= 0 ? 0.0 : (v / denom)).clamp(0.0, 1.0).toDouble();
              final primary =
                  (metricLabel == 'Count') ? it.count.toString() : fmtValue(v);
              final dealerProfit = it.amounts.dealerProfit;
              final adminProfit = it.amounts.adminProfit;
              final cost = it.amounts.cost;

              return Padding(
                padding: EdgeInsets.only(
                    bottom: index == sortedItems.length - 1 ? 0 : 14),
                child: _HorizontalBarChartRow(
                  label: it.label,
                  value: primary,
                  percent: pct,
                  color: barColor,
                  meta: [
                    'Count: ${it.count}',
                    if (adminProfit != 0)
                      'A Profit: ${MoneyFormat.format(adminProfit, currencyCode: currencyCode)}',
                    if (!hideDealerPrice && dealerProfit != 0)
                      'D Profit: ${MoneyFormat.format(dealerProfit, currencyCode: currencyCode)}',
                    if (showCost && cost != 0)
                      'Cost: ${MoneyFormat.format(cost, currencyCode: currencyCode)}',
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _HorizontalBarChartRow extends StatelessWidget {
  final String label;
  final String value;
  final double percent;
  final Color color;
  final List<String> meta;

  const _HorizontalBarChartRow({
    required this.label,
    required this.value,
    required this.percent,
    required this.color,
    required this.meta,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 560;

        final chart = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 14,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: percent,
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: meta
                  .map(
                    (text) => Text(
                      text,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              chart,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: chart),
            const SizedBox(width: 12),
            SizedBox(
              width: 90,
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
