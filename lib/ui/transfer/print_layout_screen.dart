import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../board/model.dart';
import '../../canvas/clusters.dart';
import '../../canvas/page_runtime.dart';
import '../../canvas/pane.dart';
import '../../state/notebook.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart' show FontFamilies, Radii, TypeScale;
import '../../transfer/files.dart';
import '../../transfer/pdf_export.dart';
import '../../transfer/print_layout.dart';
import '../../transfer/transfer.dart';
import '../calendar/calendar_widgets.dart' show Segmented;
import '../canvas/page_bar.dart' show pageTitle;
import '../canvas/version_history.dart' show paintDashedRRect, paintTag;
import '../common.dart';
import '../dialogs.dart';
import '../icons.dart';
import '../shell.dart' show LayoutWidth;

// Print layout (design/screens/PrintLayout.png, Update 04 §7), from ⋯ →
// Print…: the page zoomed out with page-shaped boxes over it. What's inside
// a box prints on that sheet, in the boxes' order. Drag a box to move it,
// its corner to resize it (it keeps the paper's shape), × removes the one
// picked. A bigger box prints smaller. What no box covers is outlined in
// clay with NOT ON A PAGE, and Add pages for them covers it. The layout is
// saved with the notebook, so printing again reuses it.

/// Opens Print layout for the page [pane] shows.
Future<void> showPrintLayout(BuildContext context, Pane pane) => Navigator.of(context).push(PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => PrintLayoutScreen(pane: pane),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      transitionDuration: const Duration(milliseconds: 180),
    ));

class PrintLayoutScreen extends ConsumerStatefulWidget {
  const PrintLayoutScreen({super.key, required this.pane});

  final Pane pane;

  @override
  ConsumerState<PrintLayoutScreen> createState() => _PrintLayoutState();
}

class _PrintLayoutState extends ConsumerState<PrintLayoutScreen> {
  late PrintLayout _layout;
  late final String _pageId;
  int? _picked;
  bool _busy = false;
  String? _status;

  /// The board view: screen = page × [_scale] + [_offset]. Null until it's
  /// first fitted to the space it has.
  double? _scale;
  Offset _offset = Offset.zero;
  Size _boardSize = Size.zero;
  double _startScale = 1;
  Offset _startFocal = Offset.zero, _startOffset = Offset.zero;

  NotebookNotifier get _nb => ref.read(notebookProvider(widget.pane.notebookId).notifier);
  PageRuntime get _page {
    final nb = ref.read(notebookProvider(widget.pane.notebookId));
    return nb.pages[nb.indexOf(_pageId)];
  }

  @override
  void initState() {
    super.initState();
    final nb = ref.read(notebookProvider(widget.pane.notebookId));
    _pageId = nb.pageAt(widget.pane.page).id;
    final saved = PrintLayout.fromJson(_nb.printLayoutJson(_pageId));
    _layout = saved ??
        PrintLayout.auto(_page.page, paper: paperForLocale(WidgetsBinding.instance.platformDispatcher.locale));
    if (_layout.boxes.isNotEmpty) _picked = 0;
    // The first layout is kept too, so printing again reuses it.
    if (saved == null) WidgetsBinding.instance.addPostFrameCallback((_) => _nb.setPrintLayout(_pageId, _layout.toJson()));
  }

  void _set(PrintLayout l, {int? pick, bool keepPick = true}) {
    setState(() {
      _layout = l;
      if (!keepPick || pick != null) _picked = pick;
      if (_picked != null && _picked! >= l.boxes.length) _picked = l.boxes.isEmpty ? null : l.boxes.length - 1;
      _status = null;
    });
    _nb.setPrintLayout(_pageId, l.toJson());
  }

  void _setBox(int i, PrintBox b) => _set(_layout.copyWith(boxes: [..._layout.boxes]..[i] = b));

  /// Fits everything (the ink and the boxes) into the board.
  void _fit(Size size) {
    Rect? all = _page.contentBounds;
    for (final b in _layout.boxes) {
      final r = b.rect(_layout.paper);
      all = all == null ? r : all.expandToInclude(r);
    }
    all ??= const Rect.fromLTWH(0, 0, 800, 600);
    final area = (Offset.zero & size).deflate(40);
    final s = math.min(area.width / all.width, area.height / all.height).clamp(0.05, 2.0);
    _scale = s;
    _offset = area.center - all.center * s;
  }

  void _zoom(double by) => setState(() {
        final c = _boardSize.center(Offset.zero);
        final s0 = _scale!, s1 = (s0 * by).clamp(0.05, 2.0);
        _offset = c - (c - _offset) * (s1 / s0);
        _scale = s1;
      });

  Rect _toScreen(Rect r) => Rect.fromLTWH(r.left * _scale! + _offset.dx, r.top * _scale! + _offset.dy, r.width * _scale!, r.height * _scale!);

  Future<void> _print({required bool save}) async {
    setState(() {
      _busy = true;
      _status = 'Getting the pages ready…';
    });
    try {
      final file = await ref
          .read(transfersProvider)
          .printLayoutPdf(widget.pane.notebookId, current: ref.read(notebookProvider(widget.pane.notebookId)).indexOf(_pageId), layout: _layout);
      final files = ref.read(fileTransferProvider);
      if (save) {
        final ok = await files.save(file.name, file.bytes, file.mime);
        if (mounted) setState(() => _status = ok ? 'Saved ${file.name}' : null);
      } else {
        await files.print(file.name, file.bytes);
        if (mounted) setState(() => _status = null);
      }
    } on ExportProblem catch (e) {
      if (mounted) setState(() => _status = e.message);
    } on Object catch (e, st) {
      debugPrint('Print failed: $e\n$st');
      if (mounted) setState(() => _status = 'Couldn’t print: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final nb = ref.watch(notebookProvider(widget.pane.notebookId));
    final page = _page;
    final missing = _layout.notCovered(page.page);
    final narrow = context.narrow;

    final top = Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: c.surface, border: Border(bottom: BorderSide(color: c.lineSoft))),
      child: Row(spacing: 12, children: [
        ChromeButton(label: 'Back', icon: EIcons.back, iconSize: 22, onPressed: () => Navigator.of(context).pop()),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
            Semantics(
              header: true,
              child: Text('Print layout', style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 24, height: 1.1, color: c.text)),
            ),
            Text('${nb.notebook.title} › ${pageTitle(page.page)}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.textMuted)),
          ]),
        ),
        if (!narrow)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: c.side, borderRadius: BorderRadius.circular(999)),
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
              EIcon(EIcons.move, size: 16, color: c.textMuted),
              Text('Drag a page to move it · drag its corner to resize · pinch to zoom the board',
                  style: TextStyle(fontSize: 13, color: c.text)),
            ]),
          ),
        ChromeButton(label: 'Zoom out', icon: EIcons.minus, onPressed: _scale == null ? null : () => _zoom(1 / 1.25)),
        SizedBox(
          width: 48,
          child: Text('${((_scale ?? 0) * 100).round()}%',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
        ),
        ChromeButton(label: 'Zoom in', icon: EIcons.plus, onPressed: _scale == null ? null : () => _zoom(1.25)),
      ]),
    );

    final board = LayoutBuilder(builder: (context, box) {
      final size = box.biggest;
      if (_scale == null || size != _boardSize) {
        if (_scale == null) _fit(size);
        _boardSize = size;
      }
      final paper = _layout.paper;
      return ClipRect(
        child: Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _picked = null),
              onScaleStart: (d) {
                _startScale = _scale!;
                _startFocal = d.localFocalPoint;
                _startOffset = _offset;
              },
              onScaleUpdate: (d) => setState(() {
                final s = (_startScale * d.scale).clamp(0.05, 2.0);
                // Keep the page point under the fingers under them.
                final pagePoint = (_startFocal - _startOffset) / _startScale;
                _scale = s;
                _offset = d.localFocalPoint - pagePoint * s;
              }),
              child: CustomPaint(
                painter: _BoardPainter(page, _scale!, _offset, Theme.of(context).brightness, c, missing,
                    dots: true),
              ),
            ),
          ),
          for (final (i, b) in _layout.boxes.indexed)
            _BoxView(
              key: ValueKey('box$i'),
              rect: _toScreen(b.rect(paper)),
              number: i + 1,
              label: '${paper.label} · ${b.landscape ? 'Landscape' : 'Portrait'} · ${(b.scale(paper) * 100).round()}%',
              selected: _picked == i,
              onTap: () => setState(() => _picked = i),
              onMove: (d) {
                _picked = i;
                _setBox(i, _layout.boxes[i].moved(d / _scale!));
              },
              onResize: (d) => _setBox(i, _layout.boxes[i].sized(_layout.boxes[i].width + d.dx / _scale!, paper)),
              onRemove: () {
                final boxes = [..._layout.boxes]..removeAt(i);
                _set(_layout.copyWith(boxes: boxes), pick: boxes.isEmpty ? null : math.max(0, i - 1));
              },
            ),
          Positioned(
            left: 14,
            bottom: 14,
            child: Wrap(spacing: 10, runSpacing: 10, children: [
              SecondaryButton(
                label: 'Add a page',
                icon: EIcons.plus,
                height: 48,
                filled: true,
                onPressed: () {
                  // In the middle of what's shown, at real size.
                  final center = (_boardSize.center(Offset.zero) - _offset) / _scale!;
                  final w = paper.size.width;
                  final h = paper.size.height;
                  final boxes = [..._layout.boxes, PrintBox(center.dx - w / 2, center.dy - h / 2, w)];
                  _set(_layout.copyWith(boxes: boxes), pick: boxes.length - 1);
                },
              ),
              SecondaryButton(
                label: 'Lay out pages for me',
                icon: EIcons.layout,
                height: 48,
                filled: true,
                onPressed: () {
                  final l = PrintLayout.auto(page.page, paper: paper, keep: _layout);
                  _set(l, pick: l.boxes.isEmpty ? null : 0);
                  setState(() => _fit(_boardSize));
                },
              ),
            ]),
          ),
        ]),
      );
    });

    final panel = _Panel(
      layout: _layout,
      page: page,
      picked: _picked,
      missing: missing,
      busy: _busy,
      status: _status,
      onCover: () => _set(_layout.addingFor(page.page), pick: _layout.boxes.length),
      onPaper: (p) => _set(_layout.copyWith(paper: p)),
      onTurn: (landscape) {
        final i = _picked;
        if (i == null || _layout.boxes[i].landscape == landscape) return;
        _setBox(i, _layout.boxes[i].turned(_layout.paper));
      },
      onPick: (i) => setState(() => _picked = i),
      onOptions: (l) => _set(l),
      onSave: () => _print(save: true),
      onPrint: () => _print(save: false),
    );

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          top,
          Expanded(
            child: narrow
                ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: board),
                    SizedBox(height: 460, child: panel),
                  ])
                : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: board),
                    SizedBox(width: 340, child: panel),
                  ]),
          ),
        ]),
      ),
    );
  }
}

/// The board under the boxes: dots, the page's ink, and what no box covers
/// outlined in clay with NOT ON A PAGE.
class _BoardPainter extends CustomPainter {
  _BoardPainter(this.page, this.scale, this.offset, this.brightness, this.colors, this.missing, {this.dots = false});

  final PageRuntime page;
  final double scale;
  final Offset offset;
  final Brightness brightness;
  final EndlessColors colors;
  final List<Item> missing;
  final bool dots;

  @override
  void paint(Canvas canvas, Size size) {
    if (dots) {
      final p = Paint()..color = colors.dot;
      const step = 18.0;
      for (var x = step / 2; x < size.width; x += step) {
        for (var y = step / 2; y < size.height; y += step) {
          canvas.drawCircle(Offset(x, y), 1, p);
        }
      }
    }
    final boxes = [
      for (final r in clustersOf(missing, gap: 40))
        Rect.fromLTWH(r.left * scale + offset.dx, r.top * scale + offset.dy, r.width * scale, r.height * scale).inflate(10),
    ];
    for (final b in boxes) {
      canvas.drawRRect(RRect.fromRectAndRadius(b, const Radius.circular(10)), Paint()..color = colors.clayTint.withValues(alpha: 0.7));
    }
    canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..scale(scale)
      ..drawPicture(page.fullPicture(brightness, colors))
      ..restore();
    for (final b in boxes) {
      paintDashedRRect(canvas, RRect.fromRectAndRadius(b, const Radius.circular(10)), colors.clay);
      paintTag(canvas, 'NOT ON A PAGE', Offset(b.left + 112, b.top), colors.clay, colors.onAccent);
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) =>
      old.scale != scale || old.offset != offset || old.missing != missing || old.brightness != brightness;
}

/// A page box: its numbered tab, a dashed or (picked) solid outline, the
/// corner handle that resizes it and × to remove it.
class _BoxView extends StatelessWidget {
  const _BoxView({
    super.key,
    required this.rect,
    required this.number,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.onMove,
    required this.onResize,
    required this.onRemove,
  });

  final Rect rect;
  final int number;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<Offset> onMove;
  final ValueChanged<Offset> onResize;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final line = selected ? c.accent : c.accentDeep.withValues(alpha: 0.7);
    return Positioned.fromRect(
      rect: rect.inflate(22),
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fromRect(
          rect: Rect.fromLTWH(22, 22, rect.width, rect.height),
          child: Semantics(
            button: true,
            selected: selected,
            label: 'Page $number: $label. Drag to move it',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              onPanDown: (_) => onTap(),
              onPanUpdate: (d) => onMove(d.delta),
              child: Container(
                color: selected ? c.accent.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.15),
                // The picked one: a solid line with a soft ring outside it.
                child: CustomPaint(
                  painter: _OutlinePainter(line, dashed: !selected, width: selected ? 3 : 2, ring: selected ? c.accent.withValues(alpha: 0.15) : null),
                ),
              ),
            ),
          ),
        ),
        // The tab: "1 A4 · Portrait · 100%".
        Positioned(
          left: 22,
          top: 0,
          child: IgnorePointer(
            child: Container(
              height: 22,
              padding: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(color: line, borderRadius: BorderRadius.circular(5)),
              child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                Container(
                  width: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(5)),
                  child: Text('$number', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c.onAccent)),
                ),
                Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.onAccent)),
              ]),
            ),
          ),
        ),
        if (selected) ...[
          Positioned(
            right: 0,
            top: 0,
            child: Semantics(
              button: true,
              label: 'Remove page $number',
              excludeSemantics: true,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(color: c.inverse, shape: BoxShape.circle, border: Border.all(color: c.surface, width: 2)),
                    child: Center(child: EIcon(EIcons.close, size: 14, color: c.onInverse)),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Semantics(
              label: 'Resize page $number',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) => onResize(d.delta),
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(7), border: Border.all(color: c.surface, width: 2)),
                    child: Center(child: EIcon(EIcons.resizeCorner, size: 14, color: c.onAccent)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

class _OutlinePainter extends CustomPainter {
  _OutlinePainter(this.color, {required this.dashed, required this.width, this.ring});

  final Color color;
  final bool dashed;
  final double width;
  final Color? ring;

  @override
  void paint(Canvas canvas, Size size) {
    if (ring != null) {
      canvas.drawRRect(
          RRect.fromRectAndRadius((Offset.zero & size).inflate(2), const Radius.circular(4)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..color = ring!);
    }
    final r = RRect.fromRectAndRadius((Offset.zero & size).deflate(width / 2), const Radius.circular(2));
    if (dashed) {
      paintDashedRRect(canvas, r, color, width: width);
    } else {
      canvas.drawRRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..color = color);
    }
  }

  @override
  bool shouldRepaint(_OutlinePainter old) => old.color != color || old.dashed != dashed || old.width != width || old.ring != ring;
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.layout,
    required this.page,
    required this.picked,
    required this.missing,
    required this.busy,
    required this.status,
    required this.onCover,
    required this.onPaper,
    required this.onTurn,
    required this.onPick,
    required this.onOptions,
    required this.onSave,
    required this.onPrint,
  });

  final PrintLayout layout;
  final PageRuntime page;
  final int? picked;
  final List<Item> missing;
  final bool busy;
  final String? status;
  final VoidCallback onCover;
  final ValueChanged<PaperSize> onPaper;
  final ValueChanged<bool> onTurn;
  final ValueChanged<int> onPick;
  final ValueChanged<PrintLayout> onOptions;
  final VoidCallback onSave;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final paper = layout.paper;
    final n = layout.boxes.length;
    final parts = clustersOf(missing, gap: 40).length;
    final box = picked == null ? null : layout.boxes[picked!];
    final contents = layout.contents(page.page);
    Widget label(String text) => Text(text.toUpperCase(), style: TypeScale.sectionLabel.copyWith(fontWeight: FontWeight.w700, color: c.textMuted));

    Widget turnCard(bool landscape) {
      final on = box?.landscape == landscape;
      return Expanded(
        child: Semantics(
          inMutuallyExclusiveGroup: true,
          checked: on,
          button: true,
          label: landscape ? 'Landscape' : 'Portrait',
          excludeSemantics: true,
          child: Material(
            color: on ? c.accentWash : c.surface,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: on ? c.accent : c.line, width: on ? 2 : 1),
              borderRadius: BorderRadius.circular(Radii.button),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.button),
              onTap: box == null ? null : () => onTurn(landscape),
              child: SizedBox(
                height: 50,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 10, children: [
                  Container(
                    width: landscape ? 22 : 16,
                    height: landscape ? 16 : 22,
                    decoration: BoxDecoration(border: Border.all(color: c.text, width: 1.5), borderRadius: BorderRadius.circular(2)),
                  ),
                  Text(landscape ? 'Landscape' : 'Portrait', style: TextStyle(fontSize: 15, color: c.text)),
                ]),
              ),
            ),
          ),
        ),
      );
    }

    Widget toggle(String text, bool on, PrintLayout Function(bool) set) => Semantics(
          label: text,
          toggled: on,
          excludeSemantics: true,
          child: Row(children: [
            Expanded(child: Text(text, style: TextStyle(fontSize: 15, color: c.text))),
            Switch(
              value: on,
              activeThumbColor: c.surface,
              activeTrackColor: c.accent,
              inactiveThumbColor: c.surface,
              inactiveTrackColor: c.switchOff,
              trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
              onChanged: (v) => onOptions(set(v)),
            ),
          ]),
        );

    return Container(
      decoration: BoxDecoration(color: c.surface, border: Border(left: BorderSide(color: c.lineSoft))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(18, 16, 18, 16), children: [
            if (parts > 0)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.clayTint,
                  border: Border.all(color: c.clayLine),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
                  Text(parts == 1 ? '1 part of the board isn’t on a page' : '$parts parts of the board aren’t on a page',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.clayDeep)),
                  Text('Anything outside the page boxes won’t print. Move a page over it, or add one.',
                      style: TextStyle(fontSize: 13, color: c.text)),
                  PrimaryButton(label: 'Add pages for them', height: 44, color: c.clay, onPressed: onCover),
                ]),
              )
            else
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.greenTint,
                  border: Border.all(color: c.greenLine),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(spacing: 10, children: [
                  EIcon(EIcons.checkBold, size: 18, color: c.greenDeep),
                  Expanded(
                    child: Text('Everything on the board is on a page',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.greenDeep)),
                  ),
                ]),
              ),
            const SizedBox(height: 20),
            label('Paper'),
            const SizedBox(height: 8),
            Segmented<PaperSize>(
              values: PaperSize.values,
              labels: const ['A4', 'US Letter'],
              value: paper,
              label: 'Paper',
              height: 44,
              onChanged: onPaper,
            ),
            const SizedBox(height: 20),
            label(picked == null ? 'Pick a page' : 'Page ${picked! + 1}'),
            const SizedBox(height: 8),
            Row(spacing: 8, children: [turnCard(false), turnCard(true)]),
            if (box != null) ...[
              const SizedBox(height: 8),
              Text(
                'Bigger box = smaller writing on paper. This page prints your ink at ${(box.scale(paper) * 100).round()}% of its real size.',
                style: TextStyle(fontSize: 13, color: c.textMuted),
              ),
            ],
            const SizedBox(height: 20),
            label('${n == 1 ? '1 page' : '$n pages'} · in this order'),
            const SizedBox(height: 8),
            for (final (i, b) in layout.boxes.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Semantics(
                  button: true,
                  selected: picked == i,
                  label: 'Page ${i + 1}',
                  excludeSemantics: true,
                  child: Material(
                    color: picked == i ? c.accentWash : c.surface,
                    shape: RoundedRectangleBorder(
                      side: BorderSide(color: picked == i ? c.accent : c.lineSoft, width: picked == i ? 2 : 1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => onPick(i),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(spacing: 12, children: [
                          SizedBox(
                            width: 64,
                            height: 64,
                            child: Center(
                              child: Container(
                                width: b.landscape ? 64 : 46,
                                height: (b.landscape ? 64 : 46) * b.aspect(paper),
                                decoration: BoxDecoration(color: c.bg, border: Border.all(color: c.lineSoft)),
                                child: CustomPaint(painter: _ThumbPainter(page, b.rect(paper), Theme.of(context).brightness, c)),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                              Text('Page ${i + 1}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
                              Text(
                                contents[i].isEmpty
                                    ? 'Empty: move it over your notes'
                                    : changeSummary(contents[i], const [])!.replaceFirst('+', ''),
                                style: TextStyle(fontSize: 12, color: c.textMuted),
                              ),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            label('On every page'),
            toggle('Notebook title and date', layout.header, (v) => layout.copyWith(header: v)),
            toggle('Page numbers', layout.numbers, (v) => layout.copyWith(numbers: v)),
            toggle('Dot grid background', layout.background, (v) => layout.copyWith(background: v)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.lineSoft))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
            if (status != null)
              Semantics(liveRegion: true, child: Text(status!, style: TextStyle(fontSize: 13, color: c.textMuted))),
            Row(spacing: 10, children: [
              Expanded(child: SecondaryButton(label: 'Save as PDF', height: 48, onPressed: busy || n == 0 ? null : onSave)),
              Expanded(
                child: PrimaryButton(
                  label: n == 1 ? 'Print 1 page' : 'Print $n pages',
                  icon: EIcons.print,
                  height: 48,
                  padding: 12,
                  onPressed: busy || n == 0 ? null : onPrint,
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// What a box prints, fitted into its thumbnail.
class _ThumbPainter extends CustomPainter {
  _ThumbPainter(this.page, this.area, this.brightness, this.colors);

  final PageRuntime page;
  final Rect area;
  final Brightness brightness;
  final EndlessColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / area.width;
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..scale(k)
      ..translate(-area.left, -area.top)
      ..drawPicture(page.fullPicture(brightness, colors))
      ..restore();
  }

  @override
  bool shouldRepaint(_ThumbPainter old) => old.area != area || old.page != page;
}
