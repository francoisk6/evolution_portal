import 'package:flutter/material.dart';

import '../../../data/models/pricing_group.dart';
import '../../../services/pricing_group_service.dart';

/// Shared pieces of the pricing-group screens.

String friendlyPricingError(Object e) {
  final text = e.toString().replaceFirst('Exception: ', '').trim();
  if (text.contains('HTTP 403')) return 'You do not have permission to manage pricing groups.';
  return text.isEmpty ? 'Request failed.' : text;
}

void showPricingSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? const Color(0xFFB91C1C) : null,
      duration: Duration(seconds: error ? 6 : 4),
    ));
}

Future<void> showPricingError(BuildContext context, Object e) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.error_outline, color: Color(0xFFB91C1C)),
      title: const Text('Not saved'),
      content: SingleChildScrollView(child: Text(friendlyPricingError(e))),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
      ],
    ),
  );
}

/// Shows what a change will do and asks to confirm. Returns true to apply.
Future<bool> confirmPricingPreview(
  BuildContext context, {
  required String title,
  required PricingSaveResult preview,
  String confirmLabel = 'Apply',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (preview.prunedCount > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${preview.prunedCount} item(s) will be dropped: they change nothing '
                    '(a broader item already decides them).',
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFF92400E)),
                  ),
                ),
              if (preview.moves.isNotEmpty) ...[
                PricingMovesPanel(moves: preview.moves),
                const SizedBox(height: 8),
              ],
              PricingSummaryPanel(summary: preview.summary),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(confirmLabel)),
      ],
    ),
  );
  return ok == true;
}

/// Preview → if a dealer would get the same brands from two groups, ask how
/// to resolve it → confirm → save. `send` is called with the chosen
/// `onOverlap` ('move' / 'keep', null = none). Returns the saved result, or
/// null when cancelled. Other errors are thrown to the caller.
Future<PricingSaveResult?> runPricingSave(
  BuildContext context, {
  required Future<PricingSaveResult> Function({required bool dryRun, String? onOverlap}) send,
  required String title,
  required String confirmLabel,
  required String groupName,
  bool allowKeep = true,
}) async {
  String? mode;
  PricingSaveResult preview;
  try {
    preview = await send(dryRun: true);
  } on PricingOverlapException catch (e) {
    if (!context.mounted) return null;
    mode = await askPricingOverlap(context,
        conflicts: e.conflicts, groupName: groupName, allowKeep: allowKeep);
    if (mode == null || !context.mounted) return null;
    preview = await send(dryRun: true, onOverlap: mode);
  }
  if (!context.mounted) return null;
  final ok = await confirmPricingPreview(context, title: title, preview: preview, confirmLabel: confirmLabel);
  if (!ok || !context.mounted) return null;
  return send(dryRun: false, onOverlap: mode);
}

/// "Already in another group": returns 'move', 'keep' or null (cancel).
/// allowKeep = false (editing a group): only "move" or cancel.
Future<String?> askPricingOverlap(
  BuildContext context, {
  required List<PricingConflict> conflicts,
  required String groupName,
  bool allowKeep = true,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _OverlapDialog(conflicts: conflicts, groupName: groupName, allowKeep: allowKeep),
  );
}

class _OverlapDialog extends StatefulWidget {
  final List<PricingConflict> conflicts;
  final String groupName;
  final bool allowKeep;

  const _OverlapDialog({required this.conflicts, required this.groupName, required this.allowKeep});

  @override
  State<_OverlapDialog> createState() => _OverlapDialogState();
}

class _OverlapDialogState extends State<_OverlapDialog> {
  static const _maxListed = 8;
  late String _mode;

  @override
  void initState() {
    super.initState();
    _mode = !widget.allowKeep || widget.conflicts.any((c) => c.suggested == 'move') ? 'move' : 'keep';
  }

  String get _others {
    final names = {for (final c in widget.conflicts) c.otherGroupName}.map((n) => '"$n"').toList();
    return names.join(', ');
  }

  Widget _option(String value, String title, String subtitle) {
    final selected = _mode == value;
    final color = Theme.of(context).colorScheme.primary;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(top: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: selected ? color : Colors.grey.shade300, width: selected ? 1.5 : 1),
      ),
      child: ListTile(
        dense: true,
        onTap: () => setState(() => _mode = value),
        leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            color: selected ? color : Colors.grey.shade500),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.conflicts;
    final more = list.length - _maxListed;
    final users = {for (final c in list) c.username};
    final who = users.length == 1 ? users.first : '${users.length} dealers';
    return AlertDialog(
      icon: const Icon(Icons.call_split, color: Color(0xFFB45309)),
      title: const Text('Already in another group'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('A dealer cannot get the same item from two groups. $who already gets these from $_others:',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              for (final c in list.take(_maxListed))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${users.length > 1 ? '${c.username} · ' : ''}"${c.otherGroupName}": '
                    '${c.brandCount} brand(s) - ${c.brandsLabel}',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800),
                  ),
                ),
              if (more > 0)
                Text('+$more more', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              if (widget.allowKeep) ...[
                _option('move', 'Move them to "${widget.groupName}"',
                    'They are excluded from $_others for $who.'),
                _option('keep', 'Keep them in $_others',
                    '"${widget.groupName}" skips them for $who.'),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Exclude them from $_others for ${users.length == 1 ? who : 'these dealers'} '
                    'and add them to "${widget.groupName}"?',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              const SizedBox(height: 8),
              Text('You will see a preview before anything is saved.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _mode),
          child: Text(widget.allowKeep ? 'Continue' : 'Exclude there & add here'),
        ),
      ],
    );
  }
}

/// What an overlap fix changes in the dealers' other groups.
class PricingMovesPanel extends StatelessWidget {
  final List<PricingMove> moves;

  const PricingMovesPanel({super.key, required this.moves});

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFB45309);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: amber.withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('Overlap fix', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          for (final m in moves)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                m.turnedOff
                    ? '• ${m.username} · "${m.groupName}": nothing would be left - it will be turned off '
                        'for ${m.username}.'
                    : '• ${m.username} · "${m.groupName}": ${m.brandCount} brand(s) excluded - ${m.brandsLabel}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

class PricingSummaryPanel extends StatelessWidget {
  final PricingApplySummary summary;
  final String? title;

  const PricingSummaryPanel({super.key, required this.summary, this.title});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.primary.withValues(alpha: .18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(title!, style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          for (final line in summary.lines())
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6, right: 8),
                    child: Icon(Icons.circle, size: 6),
                  ),
                  Expanded(child: Text(line, style: const TextStyle(fontSize: 13))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class PricingInfoChip extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color? color;

  const PricingInfoChip(this.text, {super.key, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.grey.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: .25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: c), const SizedBox(width: 4)],
          Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
        ],
      ),
    );
  }
}

/// Centers page content at a readable width.
class PricingPageBody extends StatelessWidget {
  final Widget child;

  const PricingPageBody({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: child,
      ),
    );
  }
}
