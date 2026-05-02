import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/workspace_ops.dart';
import '../../services/workspace_ops_service.dart';
import '../../state/session_provider.dart';

class WorkspaceOpsPage extends ConsumerStatefulWidget {
  const WorkspaceOpsPage({super.key});

  @override
  ConsumerState<WorkspaceOpsPage> createState() => _WorkspaceOpsPageState();
}

class _WorkspaceOpsPageState extends ConsumerState<WorkspaceOpsPage> {
  final _limitCtl = TextEditingController(text: '200');
  final _sampleLimitCtl = TextEditingController(text: '20');

  bool _verifyRemote = false;
  bool _loadingStatus = false;
  bool _loadingAudit = false;
  String? _statusError;
  String? _auditError;
  WorkspaceStatusResponse? _status;
  WorkspaceAuditSummaryResponse? _audit;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshAll());
  }

  @override
  void dispose() {
    _limitCtl.dispose();
    _sampleLimitCtl.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadStatus(), _loadAudit()]);
  }

  Future<void> _loadStatus() async {
    if (!mounted) return;
    setState(() {
      _loadingStatus = true;
      _statusError = null;
    });
    try {
      final data = await WorkspaceOpsService.instance.getStatus();
      if (!mounted) return;
      setState(() => _status = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusError = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loadingStatus = false);
    }
  }

  Future<void> _loadAudit() async {
    final limit = int.tryParse(_limitCtl.text.trim()) ?? 200;
    final sampleLimit = int.tryParse(_sampleLimitCtl.text.trim()) ?? 20;
    if (!mounted) return;
    setState(() {
      _loadingAudit = true;
      _auditError = null;
    });
    try {
      final data = await WorkspaceOpsService.instance.getAuditSummary(
        verifyRemote: _verifyRemote,
        limit: limit,
        sampleLimit: sampleLimit,
      );
      if (!mounted) return;
      setState(() => _audit = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _auditError = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loadingAudit = false);
    }
  }

  String _friendlyError(Object e) {
    final text = e.toString().replaceFirst('Exception: ', '').trim();
    if (text.contains('401')) return 'Unauthorized. Please login again.';
    if (text.contains('403')) return 'You do not have permission to access Workspace Ops.';
    return text.isEmpty ? 'Request failed.' : text;
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (!session.isAdmin) {
      return const _PageFrame(
        child: Center(child: Text('Workspace Ops is available for admin/staff users only.')),
      );
    }

    return _PageFrame(
      child: RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Workspace Ops',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: (_loadingStatus || _loadingAudit) ? null : _refreshAll,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _StatusBlock(
              loading: _loadingStatus,
              error: _statusError,
              status: _status,
              onRetry: _loadStatus,
            ),
            const SizedBox(height: 12),
            _AuditControls(
              verifyRemote: _verifyRemote,
              limitCtl: _limitCtl,
              sampleLimitCtl: _sampleLimitCtl,
              loading: _loadingAudit,
              onVerifyChanged: (v) => setState(() => _verifyRemote = v),
              onRun: _loadAudit,
            ),
            const SizedBox(height: 12),
            _AuditBlock(
              loading: _loadingAudit,
              error: _auditError,
              audit: _audit,
              onRetry: _loadAudit,
            ),
          ],
        ),
      ),
    );
  }
}

class _PageFrame extends StatelessWidget {
  final Widget child;
  const _PageFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return SafeArea(child: child);
  }
}

class _StatusBlock extends StatelessWidget {
  final bool loading;
  final String? error;
  final WorkspaceStatusResponse? status;
  final VoidCallback onRetry;

  const _StatusBlock({required this.loading, required this.error, required this.status, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    if (loading && status == null) return const _LoadingCard(title: 'Workspace Status');
    if (error != null && status == null) return _ErrorCard(title: 'Workspace Status', message: error!, onRetry: onRetry);
    final s = status;
    if (s == null) return const _EmptyCard(title: 'Workspace Status', message: 'No workspace status loaded.');

    return Column(
      children: [
        if (loading) const LinearProgressIndicator(minHeight: 2),
        _KeyValueCard(title: 'Workspace', data: s.workspace, keys: const [
          'mode', 'slug', 'name', 'is_main', 'is_child', 'enable_internal_sync', 'enable_catalog_sync', 'enable_admin',
        ]),
        _KeyValueCard(title: 'Mapping', data: s.mapping, keys: const [
          'main_internal_api_url', 'main_dealer_user_id_env', 'workspace_row_found_in_current_db', 'workspace_row_id', 'workspace_active', 'workspace_main_dealer_user_id_db',
        ]),
        _KeyValueCard(title: 'Reserved Users', data: s.reservedUsers, keys: const [
          'super_admin_exists', 'super_admin_id', 'super_admin_is_superuser', 'super_admin_is_staff', 'admin_exists', 'admin_id', 'admin_is_superuser', 'admin_is_staff',
        ]),
        _KeyValueCard(title: 'Counts', data: s.counts, keys: const [
          'users', 'balances', 'transactions', 'active_brands', 'mirrored_transactions', 'pending_transactions', 'failed_transactions', 'pending_mirrored_transactions', 'failed_mirrored_transactions',
        ]),
        _KeyValueCard(title: 'Recent', data: s.recent, keys: const [
          'latest_transaction_id', 'latest_pending_transaction_id', 'latest_failed_transaction_id', 'latest_mirrored_transaction_id',
        ]),
        if (error != null) _InlineWarning(message: error!),
      ],
    );
  }
}

class _AuditControls extends StatelessWidget {
  final bool verifyRemote;
  final TextEditingController limitCtl;
  final TextEditingController sampleLimitCtl;
  final bool loading;
  final ValueChanged<bool> onVerifyChanged;
  final VoidCallback onRun;

  const _AuditControls({
    required this.verifyRemote,
    required this.limitCtl,
    required this.sampleLimitCtl,
    required this.loading,
    required this.onVerifyChanged,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 150,
              child: TextField(
                controller: limitCtl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Limit', isDense: true, border: OutlineInputBorder()),
              ),
            ),
            SizedBox(
              width: 150,
              child: TextField(
                controller: sampleLimitCtl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Sample limit', isDense: true, border: OutlineInputBorder()),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(value: verifyRemote, onChanged: loading ? null : onVerifyChanged),
                const Text('Verify remote'),
              ],
            ),
            FilledButton.icon(
              onPressed: loading ? null : onRun,
              icon: loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow),
              label: const Text('Load / Run Audit'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuditBlock extends StatelessWidget {
  final bool loading;
  final String? error;
  final WorkspaceAuditSummaryResponse? audit;
  final VoidCallback onRetry;

  const _AuditBlock({required this.loading, required this.error, required this.audit, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    if (loading && audit == null) return const _LoadingCard(title: 'Workspace Audit Summary');
    if (error != null && audit == null) return _ErrorCard(title: 'Workspace Audit Summary', message: error!, onRetry: onRetry);
    final a = audit;
    if (a == null) return const _EmptyCard(title: 'Workspace Audit Summary', message: 'No audit summary loaded.');

    return Column(
      children: [
        if (loading) const LinearProgressIndicator(minHeight: 2),
        _KeyValueCard(title: 'Audit Workspace', data: a.workspace),
        _KeyValueCard(title: 'Summary Counters', data: a.summary),
        _SampleSection(title: 'missing_workspace_meta', items: a.missingWorkspaceMeta),
        _SampleSection(title: 'missing_main_transaction_id', items: a.missingMainTransactionId),
        _SampleSection(title: 'remote_missing', items: a.remoteMissing),
        _SampleSection(title: 'remote_lookup_errors', items: a.remoteLookupErrors),
        _SampleSection(title: 'status_mismatch', items: a.statusMismatch),
        _SampleSection(title: 'ok_synced', items: a.okSynced),
        if (error != null) _InlineWarning(message: error!),
      ],
    );
  }
}

class _KeyValueCard extends StatelessWidget {
  final String title;
  final Map<String, dynamic> data;
  final List<String>? keys;

  const _KeyValueCard({required this.title, required this.data, this.keys});

  @override
  Widget build(BuildContext context) {
    final selectedKeys = keys ?? data.keys.toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        initiallyExpanded: title == 'Workspace' || title == 'Summary Counters',
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        children: [
          if (selectedKeys.isEmpty || data.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('No data.'))
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: selectedKeys.map((key) => _KeyValueRow(label: _label(key), value: data[key])).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  final String label;
  final dynamic value;

  const _KeyValueRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 210,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          ),
          Expanded(child: SelectableText(_value(value), style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}

class _SampleSection extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> items;

  const _SampleSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        title: Text('${_label(title)} (${items.length})', style: const TextStyle(fontWeight: FontWeight.w800)),
        children: [
          if (items.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('No sample rows.'))
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: items.asMap().entries.map((entry) {
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SelectableText(_prettyJson(entry.value), style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  final String title;
  const _LoadingCard({required this.title});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [const CircularProgressIndicator(), const SizedBox(width: 12), Text('Loading $title...')]),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onRetry;

  const _ErrorCard({required this.title, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(message),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
        ]),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String title;
  final String message;
  const _EmptyCard({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('$title: $message')));
  }
}

class _InlineWarning extends StatelessWidget {
  final String message;
  const _InlineWarning({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    );
  }
}

String _label(String key) {
  return key.replaceAll('_', ' ').split(' ').where((p) => p.isNotEmpty).map((p) {
    if (p.length == 1) return p.toUpperCase();
    return p[0].toUpperCase() + p.substring(1);
  }).join(' ');
}

String _value(dynamic value) {
  if (value == null) return '—';
  if (value is Map || value is List) return _prettyJson(value);
  return value.toString();
}

String _prettyJson(dynamic value) {
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } catch (_) {
    return value.toString();
  }
}
