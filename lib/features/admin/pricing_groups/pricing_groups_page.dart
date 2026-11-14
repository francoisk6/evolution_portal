import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/pricing_group.dart';
import '../../../services/pricing_group_service.dart';
import '../../../state/session_provider.dart';
import 'dealer_pricing_groups_page.dart';
import 'pricing_group_widgets.dart';

/// Admin › Pricing groups: list + editor.
class PricingGroupsPage extends ConsumerStatefulWidget {
  const PricingGroupsPage({super.key});

  @override
  ConsumerState<PricingGroupsPage> createState() => _PricingGroupsPageState();
}

class _PricingGroupsPageState extends ConsumerState<PricingGroupsPage> {
  final _searchCtl = TextEditingController();
  PricingGroupListResponse? _data;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await PricingGroupService.instance.list(search: _searchCtl.text);
      if (!mounted) return;
      setState(() => _data = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyPricingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEditor({int? groupId}) async {
    final data = _data;
    final changed = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        builder: (_) => PricingGroupEditorPage(
          groupId: groupId,
          canEdit: data?.canEdit ?? false,
          canUseCategories: data?.canUseCategories ?? false,
        ),
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (!session.isAdmin) {
      return const SafeArea(child: Center(child: Text('Pricing groups are for admin users only.')));
    }
    final groups = _data?.groups ?? const <PricingGroup>[];

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
                    child: Text('Pricing groups',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh),
                  ),
                  if (_data?.canEdit ?? false)
                    FilledButton.icon(
                      onPressed: () => _openEditor(),
                      icon: const Icon(Icons.add),
                      label: const Text('New group'),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'A group holds categories, products and brands with one dealer % and one selling %. '
                'Turn it on for a dealer and those percentages are applied to the dealer\'s brands.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchCtl,
                onSubmitted: (_) => _load(),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search groups',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _load),
                ),
              ),
              const SizedBox(height: 12),
              if (_loading && _data == null) const LinearProgressIndicator(),
              if (_error != null)
                Card(
                  color: const Color(0xFFFEF2F2),
                  child: ListTile(
                    leading: const Icon(Icons.error_outline, color: Color(0xFFB91C1C)),
                    title: Text(_error!),
                    trailing: TextButton(onPressed: _load, child: const Text('Retry')),
                  ),
                ),
              if (_data != null && groups.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text('No pricing groups yet.',
                        style: TextStyle(color: Colors.grey.shade600)),
                  ),
                ),
              for (final g in groups) _GroupCard(group: g, onTap: () => _openEditor(groupId: g.id)),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final PricingGroup group;
  final VoidCallback onTap;

  const _GroupCard({required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = group.counts;
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.name,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        PricingInfoChip('Dealer ${group.profitPercentage ?? 'keep'}',
                            color: const Color(0xFF1E7E34)),
                        PricingInfoChip('Selling ${group.sellingProfitPercentage ?? 'keep'}',
                            color: const Color(0xFF1E7E34)),
                        PricingInfoChip(
                            '${c.categories} cat · ${c.products} prod · ${c.brands} brand',
                            icon: Icons.category_outlined),
                        PricingInfoChip('${c.membersActive} active / ${c.membersTotal} members',
                            icon: Icons.people_outline,
                            color: const Color(0xFF2563EB)),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── editor ─────────────────────────

class PricingGroupEditorPage extends StatefulWidget {
  final int? groupId;
  final bool canEdit;
  final bool canUseCategories;

  const PricingGroupEditorPage({
    super.key,
    required this.groupId,
    required this.canEdit,
    required this.canUseCategories,
  });

  @override
  State<PricingGroupEditorPage> createState() => _PricingGroupEditorPageState();
}

class _PricingGroupEditorPageState extends State<PricingGroupEditorPage> {
  final _nameCtl = TextEditingController();
  final _dealerCtl = TextEditingController();
  final _sellingCtl = TextEditingController();
  final _noteCtl = TextEditingController();

  int? _groupId;
  PricingGroupDetail? _detail;
  final Map<PricingItemKind, List<PricingGroupItem>> _items = {
    for (final k in PricingItemKind.values) k: <PricingGroupItem>[],
  };
  bool _loading = false;
  bool _busy = false;
  bool _dirty = false;
  bool _changedSomething = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _groupId = widget.groupId;
    if (_groupId != null) WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _dealerCtl.dispose();
    _sellingCtl.dispose();
    _noteCtl.dispose();
    super.dispose();
  }

  List<PricingItemKind> get _kinds => [
        if (widget.canUseCategories) PricingItemKind.category,
        PricingItemKind.product,
        PricingItemKind.brand,
      ];

  Future<void> _load() async {
    final id = _groupId;
    if (id == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await PricingGroupService.instance.detail(id);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _nameCtl.text = d.group.name;
        _dealerCtl.text = d.group.profitPercentage ?? '';
        _sellingCtl.text = d.group.sellingProfitPercentage ?? '';
        _noteCtl.text = d.group.note;
        final items = d.group.items ?? const PricingGroupItems();
        for (final k in PricingItemKind.values) {
          _items[k] = List<PricingGroupItem>.from(items.of(k));
        }
        _dirty = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyPricingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  String? _validate() {
    if (_nameCtl.text.trim().isEmpty) return 'Enter a group name.';
    for (final ctl in [_dealerCtl, _sellingCtl]) {
      final s = ctl.text.trim();
      if (s.isEmpty) continue;
      final v = double.tryParse(s);
      if (v == null || v <= 0) return 'Percentages are multipliers like 1.05 (or blank to keep).';
    }
    return null;
  }

  Future<PricingSaveResult> _send({required bool dryRun}) {
    return PricingGroupService.instance.save(
      id: _groupId,
      name: _nameCtl.text,
      profitPercentage: _dealerCtl.text,
      sellingProfitPercentage: _sellingCtl.text,
      note: _noteCtl.text,
      categoryIds: pricingIdsOf(_items[PricingItemKind.category]!, PricingItemKind.category),
      productIds: pricingIdsOf(_items[PricingItemKind.product]!, PricingItemKind.product),
      brandIds: pricingIdsOf(_items[PricingItemKind.brand]!, PricingItemKind.brand),
      includeCategories: widget.canUseCategories,
      dryRun: dryRun,
    );
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      showPricingSnack(context, problem, error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final preview = await _send(dryRun: true);
      if (!mounted) return;
      final ok = await confirmPricingPreview(
        context,
        title: _groupId == null ? 'Create "${_nameCtl.text.trim()}"?' : 'Save and apply?',
        preview: preview,
        confirmLabel: _groupId == null ? 'Create' : 'Save & apply',
      );
      if (!ok || !mounted) return;
      final result = await _send(dryRun: false);
      if (!mounted) return;
      _changedSomething = true;
      final newId = result.raw['group'] is Map ? (result.raw['group'] as Map)['id'] : null;
      if (_groupId == null && newId is num) _groupId = newId.toInt();
      showPricingSnack(context, result.message);
      await _load();
    } catch (e) {
      if (mounted) await showPricingError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addItems(PricingItemKind kind) async {
    final picked = await pickPricingItems(
      context,
      kind: kind,
      alreadySelectedKeys: _items[kind]!.map((e) => e.key).toSet(),
    );
    if (picked == null || picked.isEmpty) return;
    setState(() {
      _items[kind]!.addAll(picked);
      _dirty = true;
    });
  }

  Future<void> _reapply() async {
    final id = _groupId;
    if (id == null) return;
    setState(() => _busy = true);
    try {
      final msg = await PricingGroupService.instance.reapply(id);
      if (!mounted) return;
      _changedSomething = true;
      showPricingSnack(context, msg);
      await _load();
    } catch (e) {
      if (mounted) await showPricingError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final id = _groupId;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${_nameCtl.text}"?'),
        content: const Text(
            'Members keep their current prices; their rows simply stop following this group.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB91C1C)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final msg = await PricingGroupService.instance.delete(id);
      if (!mounted) return;
      showPricingSnack(context, msg);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) await showPricingError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openHistory() async {
    final id = _groupId;
    if (id == null) return;
    var undone = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: .75,
        child: _HistorySheet(groupId: id, onUndone: () => undone = true),
      ),
    );
    if (!mounted) return;
    if (undone) _changedSomething = true;
    await _load();
  }

  Future<void> _openMember(PricingGroupMember m) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DealerPricingGroupsPage(userId: m.userId, username: m.username),
      ),
    );
    if (changed == true) {
      _changedSomething = true;
      await _load();
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your edits are not saved yet.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
        ],
      ),
    );
    return leave == true;
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    final editable = widget.canEdit && !_busy;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) {
          Navigator.of(context).pop(_changedSomething);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_groupId == null ? 'New pricing group' : (d?.group.name ?? 'Pricing group')),
          actions: [
            if (_groupId != null) ...[
              IconButton(
                tooltip: 'History / undo',
                onPressed: _busy ? null : _openHistory,
                icon: const Icon(Icons.history),
              ),
              if (widget.canEdit)
                IconButton(
                  tooltip: 'Delete group',
                  onPressed: _busy ? null : _delete,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ],
        ),
        bottomNavigationBar: widget.canEdit
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: FilledButton.icon(
                    onPressed: editable ? _save : null,
                    icon: _busy
                        ? const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check),
                    label: Text(_groupId == null ? 'Preview & create' : 'Preview & save'),
                  ),
                ),
              )
            : null,
        body: _loading && d == null
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
                    if (d != null) _statusCard(d),
                    TextField(
                      controller: _nameCtl,
                      enabled: editable,
                      onChanged: (_) => _markDirty(),
                      decoration: const InputDecoration(
                        labelText: 'Group name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _pctField('Dealer %', _dealerCtl, editable)),
                        const SizedBox(width: 12),
                        Expanded(child: _pctField('Selling %', _sellingCtl, editable)),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 6, 4, 12),
                      child: Text(
                        'Multipliers: 1.05 = +5%. Leave one blank to keep that value on rows that already exist '
                        '(new rows then use the standard percentage).',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ),
                    TextField(
                      controller: _noteCtl,
                      enabled: editable,
                      onChanged: (_) => _markDirty(),
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Note (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('What the group covers',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 8),
                      child: Text(
                        'Parent wins: a product inside a listed category, or a brand inside a listed product, '
                        'is removed automatically on save.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ),
                    for (final kind in _kinds)
                      PricingItemSection(
                        title: kind.title,
                        items: _items[kind]!,
                        onAdd: editable ? () => _addItems(kind) : null,
                        onRemove: editable
                            ? (item) => setState(() {
                                  _items[kind]!.remove(item);
                                  _dirty = true;
                                })
                            : null,
                      ),
                    if ((d?.group.items?.hiddenItemCount ?? 0) > 0)
                      Text(
                        '${d!.group.items!.hiddenItemCount} item(s) added by a superuser are not shown to you; '
                        'they are kept when you save.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    if (d != null) ...[
                      const SizedBox(height: 16),
                      _membersCard(d),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _pctField(String label, TextEditingController ctl, bool enabled) {
    return TextField(
      controller: ctl,
      enabled: enabled,
      onChanged: (_) => _markDirty(),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        hintText: 'blank = keep',
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _statusCard(PricingGroupDetail d) {
    final ok = d.inSync;
    final color = ok ? const Color(0xFF1E7E34) : const Color(0xFFB45309);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 14),
      color: color.withValues(alpha: .06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: .3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(ok ? Icons.check_circle_outline : Icons.sync_problem, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                ok
                    ? 'In sync · ${d.impact.brandsInScope} brand(s) · ${d.impact.activeUsers} active member(s)'
                    : '${d.impact.changes} row(s) differ from the group (e.g. edited by hand or new brands).',
                style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w700),
              ),
            ),
            if (!ok && widget.canEdit)
              TextButton(onPressed: _busy ? null : _reapply, child: const Text('Re-apply')),
          ],
        ),
      ),
    );
  }

  Widget _membersCard(PricingGroupDetail d) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Members (${d.members.length})',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Text(
                'Turn the group on or off per dealer from Admin › Dealer pricing groups.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
            if (d.members.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('No members yet.', style: TextStyle(color: Colors.grey.shade500)),
              ),
            for (final m in d.members)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(m.active ? Icons.toggle_on : Icons.toggle_off_outlined,
                    color: m.active ? const Color(0xFF1E7E34) : Colors.grey),
                title: Text(m.username, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text([
                  if (m.fullName.isNotEmpty) m.fullName,
                  m.active ? 'on' : 'off',
                  if (m.exclusionCount > 0) '${m.exclusionCount} exclusion(s)',
                  if (!m.isActiveUser) 'inactive user',
                ].join(' · ')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openMember(m),
              ),
          ],
        ),
      ),
    );
  }
}

class _HistorySheet extends StatefulWidget {
  final int groupId;
  final VoidCallback onUndone;

  const _HistorySheet({required this.groupId, required this.onUndone});

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  List<PricingGroupLog>? _logs;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final logs = await PricingGroupService.instance.logs(widget.groupId);
      if (mounted) setState(() => _logs = logs);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyPricingError(e));
    }
  }

  Future<void> _undo(PricingGroupLog log) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Undo this change?'),
        content: const Text(
            'Rows go back to their previous percentages and the group / membership settings are '
            'restored. Rows edited since then are left as they are.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Undo')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final msg = await PricingGroupService.instance.undo(log.id);
      if (!mounted) return;
      widget.onUndone();
      showPricingSnack(context, msg);
      await _load();
    } catch (e) {
      if (mounted) await showPricingError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _when(DateTime? t) {
    if (t == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final logs = _logs;
    return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('History',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              Text('Only the most recent change can be undone.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              if (_error != null) Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C))),
              if (logs == null && _error == null)
                const Expanded(child: Center(child: CircularProgressIndicator())),
              if (logs != null)
                Expanded(
                  child: logs.isEmpty
                      ? Center(
                          child: Text('No changes yet.',
                              style: TextStyle(color: Colors.grey.shade600)))
                      : ListView.separated(
                          itemCount: logs.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final log = logs[i];
                            final s = log.summary;
                            return ListTile(
                              dense: true,
                              title: Text('${log.triggerLabel} · ${_when(log.createdAt)}',
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text([
                                if (log.actor != null) 'by ${log.actor}',
                                '+${s.created} created, ${s.updated} updated'
                                    '${s.released > 0 ? ', ${s.released} released' : ''}',
                                if (log.undoneAt != null) 'undone ${_when(log.undoneAt)}',
                              ].join(' · ')),
                              trailing: log.canUndo && log.undoneAt == null
                                  ? OutlinedButton(
                                      onPressed: _busy ? null : () => _undo(log),
                                      child: const Text('Undo'),
                                    )
                                  : null,
                            );
                          },
                        ),
                ),
            ],
          ),
        ),
    );
  }
}
