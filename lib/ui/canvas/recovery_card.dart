import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../board/model.dart';
import '../../canvas/canvas_view.dart';
import '../../canvas/clusters.dart';
import '../../canvas/live_items.dart' show clockText;
import '../../state/crash_report.dart';
import '../../state/journal.dart';
import '../../state/notebook.dart';
import '../../state/settings.dart' show boardStoreProvider;
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart' show FontFamilies, Radii;
import '../../transfer/files.dart';
import '../dialogs.dart';
import '../icons.dart';
import 'version_history.dart' show paintDashedRRect, paintTag;

// "We brought back your last strokes" (design/screens/Recovery.png, Update
// 04): after Endless closed unexpectedly, the strokes in the journal that
// hadn't reached their pages are back. The card says when it closed and
// how much came back, shows them (green dashed, BROUGHT BACK), and has Undo
// restore / Redo restore, an anonymous crash report (off; through the
// share sheet) and Keep writing.

class RecoveryCard extends ConsumerStatefulWidget {
  const RecoveryCard({super.key, required this.recovery, required this.showing, required this.onShowing});

  final Recovery recovery;

  /// The highlights are showing.
  final bool showing;
  final ValueChanged<bool> onShowing;

  @override
  ConsumerState<RecoveryCard> createState() => _RecoveryCardState();
}

class _RecoveryCardState extends ConsumerState<RecoveryCard> {
  bool _report = false;

  Recovery get r => widget.recovery;

  Future<void> _keepWriting() async {
    ref.read(recoveryProvider.notifier).dismiss(r.notebookId);
    if (!_report) return;
    final text = await crashReport(ref.read(boardStoreProvider), closedAt: r.closedAt, strokes: r.strokes);
    await ref
        .read(fileTransferProvider)
        .share('endless-crash-report.txt', Uint8List.fromList(utf8.encode(text)), 'text/plain');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final nb = ref.read(notebookProvider(r.notebookId).notifier);
    final strokes = r.strokes, lines = r.lines;
    Widget chip(String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: c.side, borderRadius: BorderRadius.circular(999)),
          child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.textMuted)),
        );
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'We brought back your last strokes',
      explicitChildNodes: true,
      child: Container(
        width: 580,
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(22),
          boxShadow: c.modalShadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: c.greenTint, borderRadius: BorderRadius.circular(14)),
              child: Center(child: EIcon(EIcons.restoreCheck, size: 26, color: c.greenDeep)),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
                Text('We brought back your last strokes',
                    style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 24, height: 1.15, color: c.text)),
                Text(
                  'Endless closed unexpectedly at ${clockText(r.closedAt.toLocal(), seconds: false)}. '
                  'Everything you wrote up to ${StrokeJournal.flushEvery.inSeconds} seconds before is back on this page.',
                  style: TextStyle(fontSize: 14, height: 1.4, color: c.textMuted),
                ),
                const SizedBox(height: 2),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  chip(strokes == 1 ? '1 stroke' : '$strokes strokes'),
                  if (lines > 0) chip(lines == 1 ? '1 line of writing' : '$lines lines of writing'),
                  chip('Lost: about ${StrokeJournal.flushEvery.inSeconds} seconds'),
                ]),
              ]),
            ),
          ]),
          Semantics(
            checked: _report,
            label: 'Send an anonymous crash report (no notes or handwriting)',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.key),
              onTap: () => setState(() => _report = !_report),
              child: Padding(
                padding: const EdgeInsets.only(left: 52),
                child: Row(children: [
                  Checkbox(value: _report, onChanged: (v) => setState(() => _report = v ?? false)),
                  Flexible(
                    child: Text('Send an anonymous crash report (no notes or handwriting)',
                        style: TextStyle(fontSize: 13, color: c.textMuted)),
                  ),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 64),
            child: Row(spacing: 8, children: [
              _SoftButton(
                label: widget.showing ? 'Hide highlights' : 'Show what came back',
                selected: widget.showing,
                onTap: () => widget.onShowing(!widget.showing),
              ),
              _TextAction(
                label: r.undone ? 'Redo restore' : 'Undo restore',
                color: c.danger,
                onTap: () => r.undone ? nb.redoRecovery(r) : nb.undoRecovery(r),
              ),
              const Spacer(),
              PrimaryButton(label: 'Keep writing', height: 44, onPressed: _keepWriting),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _SoftButton extends StatelessWidget {
  const _SoftButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      toggled: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? c.greenTint : c.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: selected ? c.greenLine : c.lineStrong),
          borderRadius: BorderRadius.circular(Radii.button),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.button),
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
          ),
        ),
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.color, required this.onTap});

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.key),
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
          ),
        ),
      );
}

/// The brought-back strokes on the page shown: green dashed boxes with
/// BROUGHT BACK, in page space (they follow pan and zoom).
class RecoveryPainter extends CustomPainter {
  RecoveryPainter(this.view, this.items, this.colors) : super(repaint: view);

  final CanvasView view;
  final List<Item> items;
  final EndlessColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    for (final r in clustersOf(items, gap: 40)) {
      final box = Rect.fromPoints(view.toScreen(r.topLeft), view.toScreen(r.bottomRight)).inflate(14);
      final rr = RRect.fromRectAndRadius(box, const Radius.circular(12));
      canvas.drawRRect(rr, Paint()..color = colors.greenTint.withValues(alpha: 0.55));
      paintDashedRRect(canvas, rr, colors.green);
      paintTag(canvas, 'BROUGHT BACK', Offset(box.center.dx + 50, box.top), colors.greenDeep, colors.onAccent);
    }
  }

  @override
  bool shouldRepaint(RecoveryPainter old) => old.items != items || old.colors != colors;
}
