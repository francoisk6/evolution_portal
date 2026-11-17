import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/pricing_group.dart';
import '../../../services/pricing_group_service.dart';
import '../../../state/session_provider.dart';
import 'pricing_group_widgets.dart';
import 'pricing_overview_grid.dart';
import 'pricing_rule_grid.dart';

/// Admin › Dealer pricing groups: pick a dealer.
class DealerPricingListPage extends ConsumerStatefulWidget {
  const DealerPricingListPage({super.key});

  @override
  ConsumerState<DealerPricingListPage> createState() => _DealerPricingListPageState();
}

class _DealerPricingListPageState extends ConsumerState<DealerPricingListPage> {
  final _searchCtl = TextEditingController();
  List<PricingDealer>? _dealers;
  bool _loading = false;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await PricingGroupService.instance.dealers(search: _searchCtl.text);
      if (!mounted) return;
      setState(() => _dealers = d);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyPricingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(PricingDealer d) async {
    final changed = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(builder: (_) => DealerPricingGroupsPage(userId: d.id, username: d.username)),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (!session.isAdmin) {
      return const SafeArea(child: Center(child: Text('Pricing groups are for admin users only.')));
    }
    final dealers = _dealers ?? const <PricingDealer>[];
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: PricingPageBody(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Dealer pricing groups',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('Pick a dealer to turn groups on or off and choose Only / Except items.',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
              const SizedBox(height: 12),
              TextField(
                controller: _searchCtl,
                onChanged: (_) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 350), _load);
                },
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search dealer by username or name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (_loading && _dealers == null) const LinearProgressIndicator(),
              if (_error != null)
                Card(
                  color: const Color(0xFFFEF2F2),
                  child: ListTile(
                    title: Text(_error!),
                    trailing: TextButton(onPressed: _load, child: const Text('Retry')),
                  ),
                ),
              if (_dealers != null && dealers.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: Text('No dealers found.', style: TextStyle(color: Colors.grey.shade600))),
                ),
              for (final d in dealers)
                Card(
                  elevation: 0,
                  color: Colors.white,
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: ListTile(
                    onTap: () => _open(d),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(d.username,
                              overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                        if (!d.isActiveUser) ...[
                          const SizedBox(width: 6),
                          const PricingInfoChip('inactive', color: Color(0xFF6B7280)),
                        ],
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: d.activeGroups.isEmpty
                          ? Text(d.fullName.isEmpty ? 'No active group' : '${d.fullName} · no active group')
                          : Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                for (final g in d.activeGroups) PricingInfoChip(g, color: const Color(0xFF2563EB)),
                              ],
                            ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One dealer: every group with an on/off switch and the dealer's Only / Except items.
class DealerPricingGroupsPage extends StatefulWidget {
  final int userId;
  final String username;

  const DealerPricingGroupsPage({super.key, required this.userId, required this.username});

  @override
  State<DealerPricingGroupsPage> createState() => _DealerPricingGroupsPageState();
}

class _DealerPricingGroupsPageState extends State<DealerPricingGroupsPage> {
  PricingUserDetail? _detail;
  bool _loading = false;
  final Set<int> _busyGroups = {};
  bool _changed = false;
  String? _error;
  int _version = 0; // rebuilds the overview after a change

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await PricingGroupService.instance.dealer(widget.userId);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _version++;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyPricingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(PricingUserLink link, bool on) async {
    final gid = link.group.id;
    setState(() => _busyGroups.add(gid));
    try {
      final res = await runPricingSave(
        context,
        send: ({required bool dryRun, String? onOverlap}) => PricingGroupService.instance.saveLink(
          userId: widget.userId,
          groupId: gid,
          active: on,
          onOverlap: onOverlap,
          dryRun: dryRun,
        ),
        title: on
            ? 'Turn on "${link.group.name}" for ${widget.username}?'
            : 'Turn off "${link.group.name}" for ${widget.username}?',
        confirmLabel: on ? 'Turn on' : 'Turn off',
        groupName: link.group.name,
      );
      if (res == null || !mounted) return;
      _changed = true;
      showPricingSnack(context, res.message);
      await _load();
    } catch (e) {
      if (mounted) await showPricingError(context, e);
    } finally {
      if (mounted) setState(() => _busyGroups.remove(gid));
    }
  }

  Future<void> _editRule(PricingUserLink link) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _LinkRulePage(
          userId: widget.userId,
          username: widget.username,
          link: link,
          canUseCategories: _detail?.canUseCategories ?? false,
        ),
      ),
    );
    if (changed == true) {
      _changed = true;
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.username),
            actions: [
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
            bottom: const TabBar(tabs: [Tab(text: 'Groups'), Tab(text: 'Overview')]),
          ),
          body: TabBarView(
            // The overview table scrolls sideways; swiping must not switch tabs.
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _loading && d == null
                  ? const Center(child: CircularProgressIndicator())
                  : PricingPageBody(
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (_error != null)
                            Card(
                              color: const Color(0xFFFEF2F2),
                              child: ListTile(
                                title: Text(_error!),
                                trailing: TextButton(onPressed: _load, child: const Text('Retry')),
                              ),
                            ),
                          if (d != null) ...[
                            Text(
                              [
                                if (d.user.fullName.isNotEmpty) d.user.fullName,
                                if (!d.user.isActiveUser) 'inactive user (groups still apply)',
                              ].join(' · '),
                              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Turn on the groups this dealer should follow. Two groups that are on may not give the '
                              'same item - when they would, you choose which group keeps it.',
                              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                            ),
                            const SizedBox(height: 12),
                            if (d.groups.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 32),
                                child: Center(
                                  child: Text('No pricing groups exist yet.',
                                      style: TextStyle(color: Colors.grey.shade600)),
                                ),
                              ),
                            for (final link in d.groups) _linkCard(link),
                          ],
                        ],
                      ),
                    ),
              PricingPageBody(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Every item and the group that prices it for ${widget.username}. '
                      'Tap a category or product to open what is inside.',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 12),
                    PricingOverviewGrid(key: ValueKey(_version), userId: widget.userId),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _linkCard(PricingUserLink link) {
    final busy = _busyGroups.contains(link.group.id);
    final on = link.active;
    final accent = on ? const Color(0xFF1E7E34) : Colors.grey.shade500;
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: on ? accent.withValues(alpha: .5) : Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(link.group.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900)),
                ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else
                  Switch(value: on, onChanged: (v) => _toggle(link, v)),
              ],
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                PricingInfoChip(link.group.percentLabel, color: const Color(0xFF1E7E34)),
                PricingInfoChip('${link.scopeCount} brand(s)', icon: Icons.sell_outlined),
                if (on) PricingInfoChip('${link.managedRows} managed', color: const Color(0xFF2563EB)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    link.ruleLabel,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ),
                TextButton.icon(
                  onPressed: busy ? null : () => _editRule(link),
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Only / Except'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The dealer's Only / Except items on one group, as a grid.
class _LinkRulePage extends StatefulWidget {
  final int userId;
  final String username;
  final PricingUserLink link;
  final bool canUseCategories;

  const _LinkRulePage({
    required this.userId,
    required this.username,
    required this.link,
    required this.canUseCategories,
  });

  @override
  State<_LinkRulePage> createState() => _LinkRulePageState();
}

class _LinkRulePageState extends State<_LinkRulePage> {
  final _book = PricingRuleBook();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _book.load(widget.link.entries);
    _book.addListener(_onBook);
  }

  @override
  void dispose() {
    _book.removeListener(_onBook);
    _book.dispose();
    super.dispose();
  }

  void _onBook() {
    if (mounted) setState(() {});
  }

  List<PricingItemKind> get _kinds => [
        if (widget.canUseCategories) PricingItemKind.category,
        PricingItemKind.product,
        PricingItemKind.brand,
      ];

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final res = await runPricingSave(
        context,
        send: ({required bool dryRun, String? onOverlap}) => PricingGroupService.instance.saveLink(
          userId: widget.userId,
          groupId: widget.link.group.id,
          items: _book.toJson(),
          onOverlap: onOverlap,
          dryRun: dryRun,
        ),
        title: 'Save Only / Except for ${widget.username}?',
        confirmLabel: 'Save',
        groupName: widget.link.group.name,
      );
      if (res == null || !mounted) return;
      showPricingSnack(context, res.message);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) await showPricingError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dirty = _book.isDirty;
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Discard changes?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
            ],
          ),
        );
        if (leave == true && context.mounted) Navigator.of(context).pop(false);
      },
      child: Scaffold(
        appBar: AppBar(title: Text('${widget.username} · ${widget.link.group.name}')),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              onPressed: _busy || !dirty ? null : _save,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: const Text('Preview & save'),
            ),
          ),
        ),
        body: PricingPageBody(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  PricingInfoChip(widget.link.active ? 'On' : 'Off',
                      color: widget.link.active ? const Color(0xFF1E7E34) : const Color(0xFF6B7280)),
                  PricingInfoChip('Gets ${widget.link.scopeCount} brand(s) now', icon: Icons.sell_outlined),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Items not marked keep following the group. The most specific row wins: '
                'brand › product › category. Tap a row to open what is inside it.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
              PricingRuleGrid(
                book: _book,
                groupId: widget.link.group.id,
                kinds: _kinds,
                editable: !_busy,
              ),
              if (widget.link.hiddenEntryCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${widget.link.hiddenEntryCount} item(s) set by a superuser are not shown; they are kept.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
