import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_env.dart';
import '../../data/models/workspace_ops.dart';
import '../../data/models/workspace_transaction_cleanup.dart';
import '../../services/workspace_ops_service.dart';
import '../../state/page_refresh_provider.dart';
import '../../state/session_provider.dart';
import '../../state/transaction_history_provider.dart';

class WorkspaceTransactionCleanupPage extends ConsumerStatefulWidget {
  const WorkspaceTransactionCleanupPage({super.key});

  @override
  ConsumerState<WorkspaceTransactionCleanupPage> createState() =>
      _WorkspaceTransactionCleanupPageState();
}

class _WorkspaceTransactionCleanupPageState
    extends ConsumerState<WorkspaceTransactionCleanupPage> {
  final _formKey = GlobalKey<FormState>();
  final _transactionCtl = TextEditingController();

  bool _loadingWorkspaces = false;
  bool _dryRunLoading = false;
  bool _confirmLoading = false;
  String? _workspaceError;
  String? _error;
  String? _selectedWorkspaceSlug;
  List<WorkspaceOption> _workspaces = const [];
  WorkspaceTransactionCleanupResponse? _candidateResult;
  WorkspaceTransactionCleanupResponse? _dryRunResult;
  WorkspaceTransactionCleanupResponse? _finalResult;

  bool get _busy => _loadingWorkspaces || _dryRunLoading || _confirmLoading;
  WorkspaceOption? get _selectedWorkspace {
    for (final workspace in _workspaces) {
      if (workspace.slug == _selectedWorkspaceSlug) return workspace;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadWorkspaces());
  }

  @override
  void dispose() {
    _transactionCtl.dispose();
    super.dispose();
  }

  void _clearResults() {
    if (_dryRunResult == null && _finalResult == null && _error == null) return;
    setState(() {
      _dryRunResult = null;
      _finalResult = null;
      _candidateResult = null;
      _error = null;
    });
  }

  String _friendlyError(Object e) {
    final text = e.toString().replaceFirst('Exception: ', '').trim();
    if (text.contains('401')) return 'Unauthorized. Please login again.';
    if (text.contains('403')) {
      return 'This cleanup action is only available to main workspace superusers.';
    }
    return text.isEmpty ? 'Request failed.' : text;
  }

  Future<void> _loadWorkspaces() async {
    if (!mounted) return;
    setState(() {
      _loadingWorkspaces = true;
      _workspaceError = null;
    });
    try {
      final response = await WorkspaceOpsService.instance.getWorkspaces();
      if (!mounted) return;
      final active = response.workspaces
          .where((workspace) => workspace.active)
          .toList(growable: false);
      setState(() {
        _workspaces = active.isEmpty ? response.workspaces : active;
        _selectedWorkspaceSlug =
            _workspaces.isEmpty ? null : _workspaces.first.slug;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _workspaceError = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loadingWorkspaces = false);
    }
  }

  Future<void> _runDryRun() async {
    if (!_formKey.currentState!.validate()) return;
    final slug = _selectedWorkspaceSlug;
    if (slug == null || slug.isEmpty) return;
    final localTransactionId = int.tryParse(_transactionCtl.text.trim()) ?? 0;

    setState(() {
      _dryRunLoading = true;
      _dryRunResult = null;
      _finalResult = null;
      _error = null;
      if (localTransactionId == 0) _candidateResult = null;
    });

    try {
      final result = await WorkspaceOpsService.instance.cleanupTransaction(
        workspaceSlug: slug,
        localTransactionId: localTransactionId,
        dryRun: true,
      );
      if (!mounted) return;
      setState(() {
        if (result.isCandidateList) {
          _candidateResult = result;
          _dryRunResult = null;
        } else {
          _dryRunResult = result;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _dryRunLoading = false);
    }
  }

  void _dryRunCandidate(WorkspaceCleanupCandidate candidate) {
    final id = candidate.localTransactionId;
    if (id == null || id < 1) return;
    setState(() {
      _transactionCtl.text = '$id';
      _dryRunResult = null;
      _finalResult = null;
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _runDryRun());
  }

  Future<void> _confirmDelete() async {
    final dryRun = _dryRunResult;
    final workspace = _selectedWorkspace;
    if (dryRun == null || !dryRun.canConfirmDelete || workspace == null) return;
    if (!_formKey.currentState!.validate()) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm orphan cleanup'),
        content: Text(
          'Delete transaction ${_transactionCtl.text.trim()} from ${workspace.name}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _confirmLoading = true;
      _finalResult = null;
      _error = null;
    });

    try {
      final result = await WorkspaceOpsService.instance.cleanupTransaction(
        workspaceSlug: workspace.slug,
        localTransactionId: int.parse(_transactionCtl.text.trim()),
        dryRun: false,
      );
      if (!mounted) return;
      setState(() => _finalResult = result);
      if (result.isSuccess) {
        ref.read(pageRefreshPulseProvider.notifier).state++;
        await ref.read(transactionHistoryProvider.notifier).refresh();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _confirmLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final onMainWorkspace =
        AppEnv.selectedWorkspace.slug == AppEnv.defaultWorkspace.slug;
    if (!session.isSuperuser || !onMainWorkspace) {
      return const SafeArea(
        child: Center(
          child: Text(
            'Workspace Transaction Cleanup is available for main workspace superusers only.',
          ),
        ),
      );
    }

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
        children: [
          _Header(
            loading: _loadingWorkspaces,
            onRefresh: _loadingWorkspaces ? null : _loadWorkspaces,
          ),
          const SizedBox(height: 10),
          _CleanupFormCard(
            formKey: _formKey,
            workspaces: _workspaces,
            selectedWorkspaceSlug: _selectedWorkspaceSlug,
            transactionCtl: _transactionCtl,
            busy: _busy,
            loadingWorkspaces: _loadingWorkspaces,
            workspaceError: _workspaceError,
            onWorkspaceChanged: (value) {
              setState(() => _selectedWorkspaceSlug = value);
              _clearResults();
            },
            onChanged: _clearResults,
            onRetryWorkspaces: _loadWorkspaces,
            onRunDryRun: _runDryRun,
            dryRunLoading: _dryRunLoading,
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            _NoticeCard(
              icon: Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
              title: 'Request failed',
              message: _error!,
            ),
          ],
          if (_candidateResult != null) ...[
            const SizedBox(height: 10),
            _CandidatesCard(
              response: _candidateResult!,
              selectedResponse: _dryRunResult,
              finalResponse: _finalResult,
              checking: _dryRunLoading,
              deleting: _confirmLoading,
              onDryRunCandidate: _busy ? null : _dryRunCandidate,
              onConfirmDelete:
                  (_dryRunResult?.canConfirmDelete ?? false) && !_busy
                      ? _confirmDelete
                      : null,
            ),
          ],
          if (_candidateResult == null && _dryRunResult != null) ...[
            const SizedBox(height: 10),
            _CleanupResultCard(
              title: 'Dry run result',
              response: _dryRunResult!,
              dryRun: true,
            ),
          ],
          if (_candidateResult == null &&
              (_dryRunResult?.canConfirmDelete ?? false)) ...[
            const SizedBox(height: 10),
            _ConfirmStrip(
              loading: _confirmLoading,
              onConfirm: _busy ? null : _confirmDelete,
            ),
          ],
          if (_candidateResult == null && _finalResult != null) ...[
            const SizedBox(height: 10),
            _CleanupResultCard(
              title: 'Final result',
              response: _finalResult!,
              dryRun: false,
            ),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final bool loading;
  final VoidCallback? onRefresh;

  const _Header({required this.loading, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Workspace Transaction Cleanup',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        IconButton(
          tooltip: 'Refresh workspaces',
          onPressed: onRefresh,
          icon: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
        ),
      ],
    );
  }
}

class _CleanupFormCard extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final List<WorkspaceOption> workspaces;
  final String? selectedWorkspaceSlug;
  final TextEditingController transactionCtl;
  final bool busy;
  final bool loadingWorkspaces;
  final String? workspaceError;
  final ValueChanged<String?> onWorkspaceChanged;
  final VoidCallback onChanged;
  final VoidCallback onRetryWorkspaces;
  final VoidCallback onRunDryRun;
  final bool dryRunLoading;

  const _CleanupFormCard({
    required this.formKey,
    required this.workspaces,
    required this.selectedWorkspaceSlug,
    required this.transactionCtl,
    required this.busy,
    required this.loadingWorkspaces,
    required this.workspaceError,
    required this.onWorkspaceChanged,
    required this.onChanged,
    required this.onRetryWorkspaces,
    required this.onRunDryRun,
    required this.dryRunLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cleanup request',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 720;
                  final workspaceField = _WorkspaceDropdown(
                    workspaces: workspaces,
                    selectedWorkspaceSlug: selectedWorkspaceSlug,
                    enabled: !busy && !loadingWorkspaces,
                    loading: loadingWorkspaces,
                    error: workspaceError,
                    onChanged: onWorkspaceChanged,
                    onRetry: onRetryWorkspaces,
                  );
                  final transactionField = TextFormField(
                    controller: transactionCtl,
                    enabled: !busy,
                    onChanged: (_) => onChanged(),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Transaction ID',
                      helperText: 'Leave empty to load candidates',
                      prefixIcon: Icon(Icons.receipt_long_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final text = (v ?? '').trim();
                      if (text.isEmpty) return null;
                      final id = int.tryParse(text);
                      if (id == null || id < 1) return 'Enter a valid ID';
                      return null;
                    },
                  );
                  final runButton = SizedBox(
                    height: 56,
                    child: FilledButton.icon(
                      onPressed:
                          busy || workspaces.isEmpty ? null : onRunDryRun,
                      icon: dryRunLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.manage_search_outlined),
                      label: const Text('Run'),
                    ),
                  );

                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        workspaceField,
                        const SizedBox(height: 12),
                        transactionField,
                        const SizedBox(height: 12),
                        runButton,
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: workspaceField),
                      const SizedBox(width: 12),
                      Expanded(flex: 2, child: transactionField),
                      const SizedBox(width: 12),
                      runButton,
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceDropdown extends StatelessWidget {
  final List<WorkspaceOption> workspaces;
  final String? selectedWorkspaceSlug;
  final bool enabled;
  final bool loading;
  final String? error;
  final ValueChanged<String?> onChanged;
  final VoidCallback onRetry;

  const _WorkspaceDropdown({
    required this.workspaces,
    required this.selectedWorkspaceSlug,
    required this.enabled,
    required this.loading,
    required this.error,
    required this.onChanged,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (error != null && workspaces.isEmpty) {
      return OutlinedButton.icon(
        onPressed: loading ? null : onRetry,
        icon: const Icon(Icons.refresh),
        label: Text(error!),
      );
    }

    final selected = workspaces.any((w) => w.slug == selectedWorkspaceSlug)
        ? selectedWorkspaceSlug
        : null;

    return DropdownButtonFormField<String>(
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Workspace',
        prefixIcon: const Icon(Icons.hub_outlined),
        border: const OutlineInputBorder(),
        suffixIcon: loading
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
      ),
      items: workspaces
          .map(
            (workspace) => DropdownMenuItem<String>(
              value: workspace.slug,
              child: Text(
                [
                  workspace.name,
                  if (workspace.domain?.isNotEmpty ?? false) workspace.domain!,
                ].join('  |  '),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: enabled ? onChanged : null,
      validator: (value) {
        if (value == null || value.isEmpty) return 'Choose a workspace';
        return null;
      },
    );
  }
}

class _CandidatesCard extends StatefulWidget {
  final WorkspaceTransactionCleanupResponse response;
  final WorkspaceTransactionCleanupResponse? selectedResponse;
  final WorkspaceTransactionCleanupResponse? finalResponse;
  final bool checking;
  final bool deleting;
  final ValueChanged<WorkspaceCleanupCandidate>? onDryRunCandidate;
  final VoidCallback? onConfirmDelete;

  const _CandidatesCard({
    required this.response,
    required this.selectedResponse,
    required this.finalResponse,
    required this.checking,
    required this.deleting,
    required this.onDryRunCandidate,
    required this.onConfirmDelete,
  });

  @override
  State<_CandidatesCard> createState() => _CandidatesCardState();
}

class _CandidatesCardState extends State<_CandidatesCard> {
  final _horizontalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final transactions = widget.response.transactions;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.format_list_bulleted_outlined,
                    color: scheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Cleanup candidates',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${widget.response.count == 0 ? transactions.length : widget.response.count} rows',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            if (widget.response.message?.isNotEmpty ?? false) ...[
              const SizedBox(height: 6),
              Text(
                widget.response.message!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            if (transactions.isEmpty)
              const Text('No cleanup candidates returned.')
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final gridWidth = _CandidateGrid.widthFor(
                    constraints.maxWidth,
                  );
                  return Scrollbar(
                    controller: _horizontalController,
                    thumbVisibility: true,
                    interactive: true,
                    child: SingleChildScrollView(
                      controller: _horizontalController,
                      scrollDirection: Axis.horizontal,
                      child: _CandidateGrid(
                        width: gridWidth,
                        transactions: transactions,
                        selectedResponse: widget.selectedResponse,
                        finalResponse: widget.finalResponse,
                        checking: widget.checking,
                        deleting: widget.deleting,
                        onDryRunCandidate: widget.onDryRunCandidate,
                        onConfirmDelete: widget.onConfirmDelete,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _CandidateWidths {
  final double action;
  final double local;
  final double status;
  final double client;
  final double order;
  final double main;
  final double created;
  final double modified;
  final double content;
  final double total;

  const _CandidateWidths({
    required this.action,
    required this.local,
    required this.status,
    required this.client,
    required this.order,
    required this.main,
    required this.created,
    required this.modified,
    required this.content,
    required this.total,
  });

  factory _CandidateWidths.forTotal(double total) {
    final extra =
        (total - _CandidateGrid.minTotalWidth).clamp(0, double.infinity);
    final content = total - (_CandidateGrid.rowHorizontalPadding * 2);
    return _CandidateWidths(
      action: _CandidateGrid.actionWidth,
      local: _CandidateGrid.localWidth,
      status: _CandidateGrid.statusWidth,
      client: _CandidateGrid.clientWidth,
      order: _CandidateGrid.orderWidth + (extra * 0.46),
      main: _CandidateGrid.mainWidth,
      created: _CandidateGrid.dateWidth + (extra * 0.27),
      modified: _CandidateGrid.dateWidth + (extra * 0.27),
      content: content,
      total: total,
    );
  }
}

class _CandidateGrid extends StatelessWidget {
  static const double actionWidth = 92;
  static const double localWidth = 70;
  static const double statusWidth = 70;
  static const double clientWidth = 75;
  static const double orderWidth = 210;
  static const double mainWidth = 70;
  static const double dateWidth = 145;
  static const double gap = 10;
  static const double rowHorizontalPadding = 6;
  static const double minContentWidth = actionWidth +
      localWidth +
      statusWidth +
      clientWidth +
      orderWidth +
      mainWidth +
      dateWidth +
      dateWidth +
      (gap * 7);
  static const double minTotalWidth =
      minContentWidth + (rowHorizontalPadding * 2);

  final double width;
  final List<WorkspaceCleanupCandidate> transactions;
  final WorkspaceTransactionCleanupResponse? selectedResponse;
  final WorkspaceTransactionCleanupResponse? finalResponse;
  final bool checking;
  final bool deleting;
  final ValueChanged<WorkspaceCleanupCandidate>? onDryRunCandidate;
  final VoidCallback? onConfirmDelete;

  const _CandidateGrid({
    required this.width,
    required this.transactions,
    required this.selectedResponse,
    required this.finalResponse,
    required this.checking,
    required this.deleting,
    required this.onDryRunCandidate,
    required this.onConfirmDelete,
  });

  static double widthFor(double availableWidth) {
    if (availableWidth.isFinite && availableWidth > minTotalWidth) {
      return availableWidth;
    }
    return minTotalWidth;
  }

  @override
  Widget build(BuildContext context) {
    final widths = _CandidateWidths.forTotal(width);
    return SizedBox(
      width: widths.total,
      child: Column(
        children: [
          _CandidateHeaderRow(widths: widths),
          const Divider(height: 1),
          for (final tx in transactions)
            _CandidateDataRow(
              widths: widths,
              tx: tx,
              selectedResponse: selectedResponse,
              finalResponse: finalResponse,
              checking: checking,
              deleting: deleting,
              onDryRunCandidate: onDryRunCandidate,
              onConfirmDelete: onConfirmDelete,
            ),
        ],
      ),
    );
  }

  static bool matches(
    WorkspaceCleanupCandidate tx,
    WorkspaceTransactionCleanupResponse? response,
  ) {
    final txId = tx.localTransactionId;
    final responseId = response?.localTransactionId;
    return txId != null && responseId != null && txId == responseId;
  }
}

class _CandidateHeaderRow extends StatelessWidget {
  final _CandidateWidths widths;

  const _CandidateHeaderRow({required this.widths});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _CandidateGrid.rowHorizontalPadding,
        vertical: 8,
      ),
      child: Row(
        children: [
          _TableHead('Action', width: widths.action),
          const SizedBox(width: _CandidateGrid.gap),
          _TableHead('Local ID', width: widths.local),
          const SizedBox(width: _CandidateGrid.gap),
          _TableHead('Status', width: widths.status),
          const SizedBox(width: _CandidateGrid.gap),
          _TableHead('Client #', width: widths.client),
          const SizedBox(width: _CandidateGrid.gap),
          _TableHead('Order UUID', width: widths.order),
          const SizedBox(width: _CandidateGrid.gap),
          _TableHead('Main Tx', width: widths.main),
          const SizedBox(width: _CandidateGrid.gap),
          _TableHead('Created', width: widths.created),
          const SizedBox(width: _CandidateGrid.gap),
          _TableHead('Modified', width: widths.modified),
        ],
      ),
    );
  }
}

class _CandidateDataRow extends StatelessWidget {
  final _CandidateWidths widths;
  final WorkspaceCleanupCandidate tx;
  final WorkspaceTransactionCleanupResponse? selectedResponse;
  final WorkspaceTransactionCleanupResponse? finalResponse;
  final bool checking;
  final bool deleting;
  final ValueChanged<WorkspaceCleanupCandidate>? onDryRunCandidate;
  final VoidCallback? onConfirmDelete;

  const _CandidateDataRow({
    required this.widths,
    required this.tx,
    required this.selectedResponse,
    required this.finalResponse,
    required this.checking,
    required this.deleting,
    required this.onDryRunCandidate,
    required this.onConfirmDelete,
  });

  @override
  Widget build(BuildContext context) {
    final selected = _CandidateGrid.matches(tx, selectedResponse);
    final done = _CandidateGrid.matches(tx, finalResponse);
    final statusFailed = (tx.status ?? '').toLowerCase() == 'failed';
    final message = done
        ? finalResponse?.message
        : (selected ? selectedResponse?.message : null);

    return Container(
      decoration: BoxDecoration(
        color: (selected || done)
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.05)
            : null,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: _CandidateGrid.rowHorizontalPadding,
        vertical: 6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _RowAction(
                tx: tx,
                selected: selected,
                done: done,
                checking: checking,
                deleting: deleting,
                canDelete:
                    selected && (selectedResponse?.canConfirmDelete ?? false),
                onCheck: onDryRunCandidate,
                onDelete: onConfirmDelete,
              ),
              const SizedBox(width: _CandidateGrid.gap),
              _CandidateCell(tx.localTransactionId?.toString() ?? '-',
                  width: widths.local),
              const SizedBox(width: _CandidateGrid.gap),
              _CandidateCell(
                tx.status ?? '-',
                width: widths.status,
                color:
                    statusFailed ? Theme.of(context).colorScheme.error : null,
              ),
              const SizedBox(width: _CandidateGrid.gap),
              _CandidateCell(tx.clientNumber ?? '-', width: widths.client),
              const SizedBox(width: _CandidateGrid.gap),
              _CandidateCell(tx.orderUuid ?? '-', width: widths.order),
              const SizedBox(width: _CandidateGrid.gap),
              _CandidateCell(tx.mainTransactionId?.toString() ?? '-',
                  width: widths.main),
              const SizedBox(width: _CandidateGrid.gap),
              _CandidateCell(tx.created ?? '-', width: widths.created),
              const SizedBox(width: _CandidateGrid.gap),
              _CandidateCell(tx.modified ?? '-', width: widths.modified),
            ],
          ),
          if ((tx.note?.trim().isNotEmpty ?? false) ||
              (message?.trim().isNotEmpty ?? false)) ...[
            const SizedBox(height: 5),
            _CandidateNote(
              width: widths.content,
              note: tx.note,
              message: message,
              failed: statusFailed,
            ),
          ],
        ],
      ),
    );
  }
}

class _TableHead extends StatelessWidget {
  final String label;
  final double width;

  const _TableHead(this.label, {required this.width});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _RowAction extends StatelessWidget {
  final WorkspaceCleanupCandidate tx;
  final bool selected;
  final bool done;
  final bool checking;
  final bool deleting;
  final bool canDelete;
  final ValueChanged<WorkspaceCleanupCandidate>? onCheck;
  final VoidCallback? onDelete;

  const _RowAction({
    required this.tx,
    required this.selected,
    required this.done,
    required this.checking,
    required this.deleting,
    required this.canDelete,
    required this.onCheck,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (done) {
      return const SizedBox(
        width: _CandidateGrid.actionWidth,
        child: Text('Done', style: TextStyle(fontSize: 12)),
      );
    }
    if (canDelete) {
      return SizedBox(
        width: _CandidateGrid.actionWidth,
        height: 30,
        child: FilledButton(
          style: FilledButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
            textStyle:
                const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
          onPressed: deleting ? null : onDelete,
          child: deleting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Delete'),
        ),
      );
    }

    return SizedBox(
      width: _CandidateGrid.actionWidth,
      height: 30,
      child: TextButton(
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
        onPressed: checking || tx.localTransactionId == null || onCheck == null
            ? null
            : () => onCheck!(tx),
        child: checking && selected
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(selected ? 'Checked' : 'Check'),
      ),
    );
  }
}

class _CandidateCell extends StatelessWidget {
  final String value;
  final double width;
  final Color? color;

  const _CandidateCell(this.value, {this.width = 120, this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: SelectableText(
        value,
        maxLines: 2,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: color == null ? FontWeight.w400 : FontWeight.w700,
        ),
      ),
    );
  }
}

class _CandidateNote extends StatelessWidget {
  final double width;
  final String? note;
  final String? message;
  final bool failed;

  const _CandidateNote({
    required this.width,
    required this.note,
    required this.message,
    required this.failed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = failed ? scheme.error : scheme.onSurfaceVariant;
    final pairs = _notePairs(note);

    return Container(
      width: width,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: failed
            ? scheme.errorContainer.withValues(alpha: 0.22)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: failed
              ? scheme.error.withValues(alpha: 0.35)
              : Theme.of(context).dividerColor,
        ),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          if (message?.trim().isNotEmpty ?? false)
            _NotePair(label: 'Message', value: message!.trim(), color: color),
          if (pairs.isEmpty && (note?.trim().isNotEmpty ?? false))
            _NotePair(label: 'Note', value: note!.trim(), color: color),
          for (final pair in pairs)
            _NotePair(label: pair.label, value: pair.value, color: color),
        ],
      ),
    );
  }

  List<_NoteKv> _notePairs(String? raw) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) return const [];
    final matches =
        RegExp(r"'([^']+)'\s*:\s*(?:'([^']*)'|([^,}]+))").allMatches(text);
    final out = <_NoteKv>[];
    for (final match in matches) {
      final label = match.group(1)?.trim();
      final value = (match.group(2) ?? match.group(3))?.trim();
      if (label == null || label.isEmpty || value == null || value.isEmpty) {
        continue;
      }
      out.add(_NoteKv(label, value));
    }
    return out;
  }
}

class _NotePair extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _NotePair({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 11, color: color),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }
}

class _NoteKv {
  final String label;
  final String value;

  const _NoteKv(this.label, this.value);
}

class _ConfirmStrip extends StatelessWidget {
  final bool loading;
  final VoidCallback? onConfirm;

  const _ConfirmStrip({required this.loading, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(Icons.warning_amber_outlined, color: scheme.error),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Dry run found an orphan child transaction eligible for deletion.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: onConfirm,
            icon: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.delete_outline),
            label: const Text('Delete orphan'),
          ),
        ],
      ),
    );
  }
}

class _CleanupResultCard extends StatelessWidget {
  final String title;
  final WorkspaceTransactionCleanupResponse response;
  final bool dryRun;

  const _CleanupResultCard({
    required this.title,
    required this.response,
    required this.dryRun,
  });

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(context, response, dryRun);
    return _NoticeCard(
      icon: style.icon,
      color: style.color,
      title: title,
      message: style.message,
      rows: [
        _InfoRow('Result', response.result),
        if (response.localTransactionId != null)
          _InfoRow('Transaction ID', '${response.localTransactionId}'),
        if (response.orderUuid != null)
          _InfoRow('Order UUID', response.orderUuid!),
        if (response.mainTransactionId != null)
          _InfoRow('Main transaction ID', '${response.mainTransactionId}'),
        if (response.mainStatus != null)
          _InfoRow('Main status', response.mainStatus!),
        if (response.status != null) _InfoRow('Status', response.status!),
        if (!response.ok) _InfoRow('OK', 'false'),
      ],
    );
  }

  _ResultStyle _styleFor(
    BuildContext context,
    WorkspaceTransactionCleanupResponse response,
    bool dryRun,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final backendMessage = response.message;

    switch (response.result) {
      case 'would_delete_orphan_child_transaction':
        return _ResultStyle(
          icon: Icons.warning_amber_outlined,
          color: scheme.error,
          message: backendMessage ??
              'Main has no matching transaction. The child transaction can be deleted after confirmation.',
        );
      case 'would_reconcile':
        return _ResultStyle(
          icon: Icons.sync_outlined,
          color: scheme.primary,
          message: backendMessage ??
              'Main transaction exists. The child would be reconciled instead of deleted.',
        );
      case 'reconciled':
        return _ResultStyle(
          icon: Icons.check_circle_outline,
          color: Colors.green.shade700,
          message: backendMessage ??
              'Main transaction exists. The child transaction was synced instead of deleted.',
        );
      case 'not_deletable_status':
        return _ResultStyle(
          icon: Icons.block_outlined,
          color: scheme.error,
          message: backendMessage ??
              'This child transaction status is not deletable.',
        );
      case 'skipped':
        return _ResultStyle(
          icon: Icons.info_outline,
          color: scheme.secondary,
          message: backendMessage ?? 'Workspace metadata is missing.',
        );
      case 'not_found_in_child':
        return _ResultStyle(
          icon: Icons.search_off_outlined,
          color: scheme.secondary,
          message: backendMessage ?? 'Child transaction was not found.',
        );
      case 'deleted_orphan_child_transaction':
        return _ResultStyle(
          icon: Icons.check_circle_outline,
          color: Colors.green.shade700,
          message:
              backendMessage ?? 'The orphan child transaction was deleted.',
        );
      default:
        return _ResultStyle(
          icon: response.ok ? Icons.info_outline : Icons.error_outline,
          color: response.ok ? scheme.primary : scheme.error,
          message: backendMessage ??
              (response.ok
                  ? 'Cleanup request completed.'
                  : 'Cleanup request failed.'),
        );
    }
  }
}

class _NoticeCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final List<Widget> rows;

  const _NoticeCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    this.rows = const [],
  });

  @override
  Widget build(BuildContext context) {
    final tinted = color.withValues(alpha: 0.08);
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: tinted,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(message),
            if (rows.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: rows,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 360),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ResultStyle {
  final IconData icon;
  final Color color;
  final String message;

  const _ResultStyle({
    required this.icon,
    required this.color,
    required this.message,
  });
}
