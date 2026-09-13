import 'dart:convert' show utf8;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/app_scroll_behavior.dart';
import '../../data/models/terranet_stock.dart';
import '../../services/terranet_stock_service.dart';
import '../../state/session_provider.dart';
import '../../utils/file_download.dart';
import '../../widgets/page_action_bar.dart'
    show PageAction, PageActions;

/// TerraNet card stock held on the dealer account.
///
/// The counts live on the provider's portal, so the reading is asynchronous:
/// GET on open (never blocks), then an explicit "Take reading" queues a sweep
/// and polls until the worker finishes.
///
/// The one thing to get right: `available` means *not yet consumed* — it
/// includes cards whose code has already been revealed and handed to a
/// customer. The sellable number is `usable`.
class TerranetStockPage extends ConsumerStatefulWidget {
  const TerranetStockPage({super.key});

  @override
  ConsumerState<TerranetStockPage> createState() => _TerranetStockPageState();
}

class _TerranetStockPageState extends ConsumerState<TerranetStockPage> {
  final _service = TerranetStockService.instance;
  final _pageCtl = ScrollController();
  final _typesCtl = ScrollController();

  TerranetStockReading? _reading;

  bool _loading = false; // plain GET in flight
  bool _taking = false; // refresh queued + polling
  bool _exporting = false;
  String? _error;
  String? _notice;

  Color get _fg => const Color(0xFF1F2937);
  Color get _fgSoft => const Color(0xFF6B7280);

  static const Color _sellable = Color(0xFF1E7E34);
  static const Color _held = Color(0xFFB26A00);
  static const Color _bad = Color(0xFFD32F2F);

  @override
  void initState() {
    super.initState();
    Future.microtask(_bootstrap);
  }

  @override
  void dispose() {
    _pageCtl.dispose();
    _typesCtl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (!ref.read(sessionProvider).isSuperuser) return;
    await _load();
  }

  String _cleanError(Object e) {
    final s = e.toString();
    if (s.startsWith('Exception: ')) return s.substring('Exception: '.length);
    return s;
  }

  // ───────────────── data loading ─────────────────

  /// Cheap read of whatever reading already exists.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final reading = await _service.fetch();
      if (!mounted) return;
      setState(() {
        _reading = reading;
        _notice = reading.refreshing
            ? 'A reading is already running on the server.'
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _cleanError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Queue a sweep of the portal, then poll until it finishes.
  ///
  /// Never wired to a timer: the sweep runs through the same single browser
  /// worker that places refills, so it delays real purchases by ~40s.
  Future<void> _takeReading() async {
    if (_taking) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Take a stock reading?'),
        content: const Text(
          'This drives the same browser worker that places refills and issues '
          'vouchers. Taken during trading, it puts a real purchase about 40 '
          'seconds behind it.\n\nThe reading itself takes roughly 40 seconds.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.sync),
            label: const Text('Take reading'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _taking = true;
      _error = null;
      _notice = null;
    });

    try {
      final outcome = await _service.refreshAndWait(
        onPoll: (reading) {
          if (!mounted) return;
          setState(() => _reading = reading);
        },
        cancelled: () => !mounted,
      );
      if (!mounted) return;
      setState(() {
        _reading = outcome.reading;
        if (!outcome.completed) {
          // Surface the stale reading rather than spinning forever.
          _notice = 'The reading did not finish in time. Showing the last '
              'completed reading — reload in a moment.';
        } else if (!outcome.queued) {
          _notice = 'A reading was already running; its result is shown.';
        } else {
          _notice = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _cleanError(e));
    } finally {
      if (mounted) setState(() => _taking = false);
    }
  }

  // ───────────────── export / copy ─────────────────

  /// Both exports carry the reading's provenance (when it was taken, whether
  /// it is stale or partial) alongside the numbers. Counts that travel without
  /// those flags are exactly how a dealer ends up acting on a stale or
  /// undercounted figure.
  List<List<String>> _exportRows(TerranetStockReading reading) {
    final totals = reading.totals!;
    final asOf = reading.asOf;
    final age = reading.age;

    return <List<String>>[
      const ['TerraNet stock reading'],
      ['Taken', asOf == null ? 'never' : _formatStamp(asOf)],
      ['Age', age == null ? '' : _formatAge(age)],
      ['Stale', reading.stale ? 'yes' : 'no'],
      ['Incomplete (partial)', reading.partial ? 'yes' : 'no'],
      if (reading.partial)
        const [
          'WARNING',
          'Incomplete reading — every count below is an undercount',
        ],
      const [
        'Note',
        'usable is the sellable figure; available also counts cards already '
            'handed to a customer',
      ],
      const <String>[],
      const ['Totals'],
      const ['total', 'available', 'usable', 'recovered', 'used'],
      [
        '${totals.total}',
        '${totals.available}',
        '${totals.usable}',
        '${totals.recovered}',
        '${totals.used}',
      ],
      const <String>[],
      const ['By card type'],
      const ['type', 'available', 'recovered', 'usable', 'note'],
      for (final row in reading.types)
        [
          row.type,
          '${row.available}',
          '${row.recovered}',
          '${row.usable}',
          row.availableButNotSellable ? 'NONE SELLABLE' : '',
        ],
    ];
  }

  static String _csvEscape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// Tabs and newlines would break the column alignment when pasted into a
  /// spreadsheet, so they collapse to spaces.
  static String _tsvEscape(String value) =>
      value.replaceAll(RegExp(r'[\t\r\n]+'), ' ');

  String _exportFilename(TerranetStockReading reading) {
    final stamp = reading.asOf ?? DateTime.now();
    return 'terranet_stock_${DateFormat('yyyyMMdd_HHmm').format(stamp)}.csv';
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// A reading is only exportable once it exists and passes its own identity
  /// checks — the screen withholds suspect counts, so the export does too.
  TerranetStockReading? get _exportable {
    final reading = _reading;
    if (reading == null || !reading.hasReading || !reading.consistent) {
      return null;
    }
    return reading;
  }

  String? _blockedExportReason() {
    final reading = _reading;
    if (reading == null || !reading.hasReading) {
      return 'Nothing to export yet — take a reading first.';
    }
    if (!reading.consistent) {
      return 'Counts withheld — the payload failed its own consistency checks.';
    }
    return null;
  }

  /// CSV rather than .xlsx: the file is built on the client (there is no
  /// TerraNet export endpoint), and Excel opens it directly.
  Future<void> _exportCsv() async {
    if (_exporting) return;
    final reading = _exportable;
    if (reading == null) {
      _showSnack(_blockedExportReason()!);
      return;
    }

    setState(() => _exporting = true);
    try {
      final csv = _exportRows(reading)
          .map((r) => r.map(_csvEscape).join(','))
          .join('\r\n');
      final filename = _exportFilename(reading);
      final saved = await saveDownloadedFile(
        bytes: utf8.encode(csv),
        filename: filename,
        mimeType: 'text/csv',
      );
      if (!mounted) return;
      _showSnack(saved ? 'Exported $filename' : 'Export failed.');
    } catch (e) {
      if (!mounted) return;
      _showSnack(_cleanError(e));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Tab-separated, so it pastes into Excel or Sheets as columns.
  Future<void> _copyReading() async {
    final reading = _exportable;
    if (reading == null) {
      _showSnack(_blockedExportReason()!);
      return;
    }

    final tsv = _exportRows(reading)
        .map((r) => r.map(_tsvEscape).join('\t'))
        .join('\n');
    await Clipboard.setData(ClipboardData(text: tsv));
    if (!mounted) return;
    _showSnack('Reading copied to the clipboard.');
  }

  // ───────────────── formatting ─────────────────

  String _formatStamp(DateTime value) =>
      DateFormat('yyyy-MM-dd HH:mm').format(value);

  String _formatAge(Duration age) {
    if (age.inSeconds < 60) return '${age.inSeconds}s ago';
    if (age.inMinutes < 60) return '${age.inMinutes}m ago';
    if (age.inHours < 24) return '${age.inHours}h ago';
    return '${age.inDays}d ago';
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
    final busy = _loading || _taking;
    final canExport = _exportable != null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TerraNet stock',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: _fg,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'TerraNet cards held on the dealer account, read from the '
                'provider portal. Usable is the sellable figure — available '
                'also counts cards already handed to a customer.',
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
            FilledButton.icon(
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onPressed: busy ? null : _takeReading,
              icon: const Icon(Icons.sync, size: 18),
              label: const Text('Take reading',
                  style: TextStyle(fontSize: 12)),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onPressed: busy ? null : _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reload', style: TextStyle(fontSize: 12)),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onPressed: canExport && !_exporting ? _exportCsv : null,
              icon: const Icon(Icons.download_outlined, size: 18),
              label: Text(
                _exporting ? 'Exporting…' : 'Export CSV',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onPressed: canExport ? _copyReading : null,
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              label: const Text('Copy', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _banner(
    BuildContext context, {
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Material(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: .25)),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: 12, color: _fg, height: 1.3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildStatusBanners(BuildContext context) {
    final reading = _reading;
    final inconsistent = reading != null && reading.hasReading && !reading.consistent;

    return [
      if (_loading || _taking) ...[
        const SizedBox(height: 12),
        const LinearProgressIndicator(minHeight: 2),
      ],
      if (_taking) ...[
        const SizedBox(height: 12),
        _banner(
          context,
          icon: Icons.hourglass_top,
          text: 'Reading the portal — this takes about 40 seconds.',
          color: Theme.of(context).colorScheme.primary,
        ),
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
      if (_notice != null) ...[
        const SizedBox(height: 12),
        _banner(
          context,
          icon: Icons.info_outline,
          text: _notice!,
          color: _held,
        ),
      ],
      if (inconsistent) ...[
        const SizedBox(height: 12),
        _banner(
          context,
          icon: Icons.report_gmailerrorred_outlined,
          text: 'The counts do not add up (available must equal usable + '
              'recovered, and total must equal available + used). Treat this '
              'payload as suspect — take a fresh reading before acting on it.',
          color: _bad,
        ),
      ],
      if (reading != null && reading.partial) ...[
        const SizedBox(height: 12),
        _banner(
          context,
          icon: Icons.warning_amber_outlined,
          text: 'Incomplete reading — the sweep could not read every row, so '
              'every count below is an undercount.',
          color: _held,
        ),
      ],
    ];
  }

  Widget _chip(String label, String value, Color color) {
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

  Widget _buildReadingMeta(TerranetStockReading reading) {
    final asOf = reading.asOf;
    final age = reading.age;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip(
          'Taken',
          asOf == null ? 'never' : _formatStamp(asOf),
          reading.stale ? _held : _sellable,
        ),
        if (age != null)
          _chip('Age', _formatAge(age), reading.stale ? _held : _fgSoft),
        if (reading.stale) _chip('State', 'stale', _held),
        if (reading.refreshing)
          _chip('Reading', 'in progress', Theme.of(context).colorScheme.primary),
      ],
    );
  }

  Widget _statTile({
    required String name,
    required int value,
    required String description,
    required Color color,
    bool emphasised = false,
  }) {
    return Container(
      width: 168,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: emphasised ? color.withValues(alpha: .06) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: emphasised
              ? color.withValues(alpha: .35)
              : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: emphasised ? color : _fgSoft,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              height: 1.05,
              color: emphasised ? color : _fg,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(fontSize: 11, color: _fgSoft, height: 1.2),
          ),
        ],
      ),
    );
  }

  Widget _buildTotals(TerranetStockTotals totals) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _statTile(
          name: 'usable',
          value: totals.usable,
          description: 'virgin — free to sell or spend',
          color: _sellable,
          emphasised: true,
        ),
        _statTile(
          name: 'recovered',
          value: totals.recovered,
          description: 'code revealed, not yet redeemed',
          color: _held,
          emphasised: true,
        ),
        _statTile(
          name: 'available',
          value: totals.available,
          description: 'not yet consumed = usable + recovered',
          color: _fgSoft,
        ),
        _statTile(
          name: 'used',
          value: totals.used,
          description: 'redeemed; gone from the stock list',
          color: _fgSoft,
        ),
        _statTile(
          name: 'total',
          value: totals.total,
          description: 'every card ever held',
          color: _fgSoft,
        ),
      ],
    );
  }

  Widget _numCell(int value, {required double width, Color? color}) {
    return SizedBox(
      width: width,
      child: Text(
        '$value',
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: color ?? _fg,
        ),
      ),
    );
  }

  Widget _buildTypesTable(List<TerranetStockType> types) {
    const wType = 96.0;
    const wNum = 92.0;

    Widget headerCell(String label, {required double width, bool right = true}) {
      return SizedBox(
        width: width,
        child: Text(
          label,
          textAlign: right ? TextAlign.right : TextAlign.left,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: .4,
            color: _fgSoft,
          ),
        ),
      );
    }

    return Scrollbar(
      controller: _typesCtl,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _typesCtl,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: wType + (wNum * 3) + 48,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    headerCell('TYPE', width: wType, right: false),
                    const Spacer(),
                    headerCell('AVAILABLE', width: wNum),
                    headerCell('RECOVERED', width: wNum),
                    headerCell('USABLE', width: wNum),
                  ],
                ),
              ),
              Divider(height: 1, color: Colors.grey.shade300),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: types.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: Colors.grey.shade200),
                itemBuilder: (context, index) {
                  final row = types[index];
                  final noneSellable = row.availableButNotSellable;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      children: [
                        SizedBox(
                          width: wType,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.type,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: _fg,
                                ),
                              ),
                              if (noneSellable) ...[
                                const SizedBox(height: 2),
                                const Text(
                                  'none sellable',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: _bad,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Spacer(),
                        _numCell(row.available, width: wNum, color: _fgSoft),
                        _numCell(row.recovered, width: wNum, color: _held),
                        _numCell(
                          row.usable,
                          width: wNum,
                          color: row.usable > 0 ? _sellable : _bad,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(TerranetStockReading? reading) {
    final message = (reading?.message.trim().isNotEmpty ?? false)
        ? reading!.message.trim()
        : 'No stock reading yet.';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Icon(Icons.inventory_2_outlined, size: 36, color: _fgSoft),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: _fgSoft, height: 1.3),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _loading || _taking ? null : _takeReading,
            icon: const Icon(Icons.sync, size: 18),
            label: const Text('Take reading', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final reading = _reading;

    if (reading == null) {
      return _sectionCard(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            height: 140,
            child: Center(
              child: _loading || _taking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      'No reading loaded.',
                      style: TextStyle(fontSize: 12, color: _fgSoft),
                    ),
            ),
          ),
        ),
      );
    }

    final totals = reading.totals;

    return _sectionCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildReadingMeta(reading),
            const SizedBox(height: 14),
            if (!reading.hasReading)
              _buildEmptyState(reading)
            else if (!reading.consistent)
              // Suspect payload: the identities the backend asserts are broken,
              // so the numbers are not rendered at all.
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'Counts withheld — the payload failed its own consistency '
                    'checks.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: _bad, height: 1.3),
                  ),
                ),
              )
            else ...[
              _buildTotals(totals!),
              const SizedBox(height: 18),
              Text(
                'By card type',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: _fg,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Both brands of a type draw from the same physical stock, so '
                'one usable figure governs the voucher brand and the '
                'direct-refill (_df) brand alike.',
                style: TextStyle(fontSize: 11.5, color: _fgSoft, height: 1.25),
              ),
              const SizedBox(height: 12),
              if (reading.types.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'The reading carried no card types.',
                      style: TextStyle(fontSize: 12, color: _fgSoft),
                    ),
                  ),
                )
              else
                _buildTypesTable(reading.types),
            ],
          ],
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
                  'TerraNet stock is available for superusers only.',
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
    if (!session.isSuperuser) {
      return _buildAccessDenied(context);
    }

    final actions = <PageAction>[
      PageAction(
        label: 'Take reading',
        icon: Icons.sync,
        onTap: _takeReading,
      ),
      PageAction(label: 'Reload', icon: Icons.refresh, onTap: _load),
      PageAction(
        label: _exporting ? 'Exporting…' : 'Export CSV',
        icon: Icons.download_outlined,
        onTap: _exportCsv,
      ),
      PageAction(
        label: 'Copy',
        icon: Icons.copy_all_outlined,
        onTap: _copyReading,
      ),
    ];

    return PageActions(
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
                ..._buildStatusBanners(context),
                const SizedBox(height: 12),
                _buildBody(context),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
