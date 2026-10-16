import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../board/model.dart';
import '../../spelling/my_handwriting.dart';
import '../../state/settings.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../dialogs.dart';

/// "Teach Endless your handwriting": each letter written once in a box on
/// guide lines, so spelling fixes can be written in the user's own letters.
/// True when a sample was saved.
Future<bool> showTeachHandwriting(BuildContext context) async =>
    await showEndlessDialog<bool>(context, dismissible: false, builder: (context) => const _Teach()) ?? false;

/// Boxes per row of the pad.
const _columns = 13;
const _cellHeight = 112.0;
const _cellGap = 6.0;

/// Where box [i] is on a pad [width] wide.
Rect _cell(int i, double width) {
  final w = (width - (_columns - 1) * _cellGap) / _columns;
  return Rect.fromLTWH((i % _columns) * (w + _cellGap), (i ~/ _columns) * (_cellHeight + _cellGap), w, _cellHeight);
}

double _padHeight(int boxes) {
  final rows = (boxes / _columns).ceil();
  return rows * _cellHeight + (rows - 1) * _cellGap;
}

class _Stroke {
  _Stroke(this.points, this.box);

  /// On the pad.
  final List<InkPoint> points;

  /// The box it was written in.
  final int box;
}

class _Teach extends ConsumerStatefulWidget {
  const _Teach();

  @override
  ConsumerState<_Teach> createState() => _TeachState();
}

class _TeachState extends ConsumerState<_Teach> {
  var _step = 0;
  final _strokes = [for (final _ in sampleSteps) <_Stroke>[]];
  List<InkPoint>? _live;
  int? _pointer;
  Duration? _start;
  bool _stylus = false;
  double _padWidth = 1;

  String get _letters => sampleSteps[_step].letters;

  Set<int> _filled(int step) => {for (final s in _strokes[step]) s.box};

  List<String> get _missing => [
        for (final (i, ch) in _letters.characters.indexed)
          if (!_filled(_step).contains(i)) ch,
      ];

  void _down(PointerDownEvent e) {
    if (_pointer != null) return;
    final stylus = e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus;
    if (stylus) _stylus = true;
    // Once the pen is in use, a resting palm doesn't write.
    if (_stylus && e.kind == PointerDeviceKind.touch) return;
    _pointer = e.pointer;
    _start = e.timeStamp;
    setState(() => _live = [_point(e)]);
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer || _live == null) return;
    setState(() => _live!.add(_point(e)));
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    final pts = _live;
    _live = null;
    if (pts != null && pts.isNotEmpty) {
      final xs = pts.map((p) => p.x), ys = pts.map((p) => p.y);
      final mid = Offset((xs.reduce(math.min) + xs.reduce(math.max)) / 2, (ys.reduce(math.min) + ys.reduce(math.max)) / 2);
      _strokes[_step].add(_Stroke(pts, _boxAt(mid)));
    }
    setState(() {});
  }

  InkPoint _point(PointerEvent e) {
    final range = e.pressureMax - e.pressureMin;
    final stylus = e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus;
    final pressure = stylus && range > 0 ? ((e.pressure - e.pressureMin) / range).clamp(0.0, 1.0) : 0.5;
    return InkPoint(e.localPosition.dx, e.localPosition.dy, pressure, (e.timeStamp - _start!).inMilliseconds);
  }

  /// The box a stroke centered at [at] belongs to: the one it's in, or the
  /// nearest.
  int _boxAt(Offset at) {
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < _letters.characters.length; i++) {
      final r = _cell(i, _padWidth);
      if (r.contains(at)) return i;
      final d = (r.center - at).distanceSquared;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  /// The sample as written so far.
  MyHandwriting _hand() {
    final glyphs = <String, HandGlyph>{};
    for (final (step, s) in sampleSteps.indexed) {
      for (final (i, ch) in s.letters.characters.indexed) {
        final g = HandGlyph.fromBox([
          for (final st in _strokes[step])
            if (st.box == i) st.points,
        ], _cell(i, _padWidth));
        if (g != null) glyphs[ch] = g;
      }
    }
    return MyHandwriting(glyphs: glyphs, createdAt: DateTime.now().toUtc());
  }

  Future<void> _save() async {
    await ref.read(myHandwritingProvider.notifier).save(_hand());
    ref.read(settingsProvider.notifier).apply((s) => s.copyWith(fixInHandwriting: true));
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final step = sampleSteps[_step];
    final last = _step == sampleSteps.length - 1;
    final missing = _missing;
    final ready = !step.required || missing.isEmpty;
    final mine = _strokes[_step];
    final status = step.required && missing.isNotEmpty
        ? (missing.length == _letters.length
            ? 'Write each small letter in its box, sitting on the solid line, the way you usually write it.'
            : missing.length == 1
                ? '1 letter to go: ${missing.single}'
                : '${missing.length} letters to go: ${missing.take(8).join(', ')}${missing.length > 8 ? '…' : ''}')
        : step.required
            ? 'All the small letters are there.'
            : 'Capitals and marks you leave out are made from your small letters, or drawn simply.';
    return DialogFrame(
      title: 'Teach Endless your handwriting',
      width: 1100,
      onClose: () => Navigator.of(context).pop(false),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
        Row(children: [
          Expanded(
            child: Text(
              'Step ${_step + 1} of ${sampleSteps.length} · ${step.title}',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text),
            ),
          ),
          Text(
            'Kept on this tablet only, never in notebooks or exports.',
            style: TextStyle(fontSize: 13, color: c.textMuted),
          ),
        ]),
        LayoutBuilder(builder: (context, box) {
          _padWidth = box.maxWidth;
          return Semantics(
            label: 'Handwriting sample: write each letter in its box',
            child: SizedBox(
              height: _padHeight(_letters.length),
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _down,
                onPointerMove: _move,
                onPointerUp: _up,
                onPointerCancel: _up,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _PadPainter(
                    letters: _letters,
                    strokes: mine,
                    live: _live,
                    filled: _filled(_step),
                    colors: c,
                  ),
                ),
              ),
            ),
          );
        }),
        if (last) _Preview(hand: _hand()),
        Row(spacing: 10, children: [
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(status, style: TextStyle(fontSize: 14, height: 1.35, color: c.textMuted)),
            ),
          ),
          SecondaryButton(
            label: 'Undo',
            height: 46,
            onPressed: mine.isEmpty ? null : () => setState(mine.removeLast),
          ),
          SecondaryButton(label: 'Clear', height: 46, onPressed: mine.isEmpty ? null : () => setState(mine.clear)),
          if (_step > 0) SecondaryButton(label: 'Back', height: 46, onPressed: () => setState(() => _step--)),
          PrimaryButton(
            label: last ? 'Save my handwriting' : 'Next',
            height: 46,
            onPressed: !ready ? null : (last ? _save : () => setState(() => _step++)),
          ),
        ]),
      ]),
    );
  }
}

class _PadPainter extends CustomPainter {
  _PadPainter({required this.letters, required this.strokes, required this.live, required this.filled, required this.colors});

  final String letters;
  final List<_Stroke> strokes;
  final List<InkPoint>? live;
  final Set<int> filled;
  final EndlessColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final c = colors;
    for (final (i, ch) in letters.characters.indexed) {
      final r = _cell(i, size.width);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(Radii.small)),
        Paint()..color = c.surfaceSunk,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r.deflate(0.5), const Radius.circular(Radii.small)),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = filled.contains(i) ? c.lineStrong : c.line,
      );
      void guide(double at, Color color, {bool dashed = false}) {
        final y = r.top + r.height * at;
        final paint = Paint()
          ..color = color
          ..strokeWidth = 1;
        if (!dashed) {
          canvas.drawLine(Offset(r.left + 6, y), Offset(r.right - 6, y), paint);
          return;
        }
        for (var x = r.left + 6; x < r.right - 6; x += 7) {
          canvas.drawLine(Offset(x, y), Offset(math.min(x + 3.5, r.right - 6), y), paint);
        }
      }

      guide(SampleGuides.ascender, c.lineSoft, dashed: true);
      guide(SampleGuides.xLine, c.lineDashed, dashed: true);
      guide(SampleGuides.baseline, c.lineStrong);
      final label = TextPainter(
        text: TextSpan(
          text: ch,
          style: TextStyle(
            fontFamily: FontFamilies.ui,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: filled.contains(i) ? c.textFaint : c.textMuted,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, r.topLeft + const Offset(6, 4));
      label.dispose();
    }
    final ink = Paint()
      ..color = c.text
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final pts in [for (final s in strokes) s.points, ?live]) {
      if (pts.length == 1) {
        canvas.drawCircle(Offset(pts.first.x, pts.first.y), 1.6, Paint()..color = c.text);
        continue;
      }
      final path = Path()..moveTo(pts.first.x, pts.first.y);
      for (final p in pts.skip(1)) {
        path.lineTo(p.x, p.y);
      }
      canvas.drawPath(path, ink);
    }
  }

  @override
  bool shouldRepaint(_PadPainter old) => true;
}

/// "Spelling, fixed." written in the sample, to see how fixes will look.
class _Preview extends StatelessWidget {
  const _Preview({required this.hand});

  final MyHandwriting hand;

  static const text = 'Spelling, fixed.';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final line = hand.canWrite(text) ? layOutInHand(hand, text, seed: 7) : null;
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Row(spacing: 16, children: [
        Text('HOW A FIX WILL LOOK', style: TypeScale.sectionLabel.copyWith(color: c.textMuted)),
        Expanded(
          child: line == null
              ? Text('Write the small letters first.', style: TextStyle(fontSize: 14, color: c.textMuted))
              : Semantics(
                  label: 'Preview: $text in your handwriting',
                  child: CustomPaint(size: const Size(double.infinity, 76), painter: _LinePainter(line, c.text)),
                ),
        ),
      ]),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.line, this.color);

  final HandLine line;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // An x-height of 16 px, the baseline a little below the middle.
    const xh = 16.0;
    final base = size.height / 2 + xh * 0.6;
    final ink = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final s in line.strokes) {
      if (s.isEmpty) continue;
      final path = Path()..moveTo(s.first.x * xh, base + s.first.y * xh);
      for (final p in s.skip(1)) {
        path.lineTo(p.x * xh, base + p.y * xh);
      }
      if (s.length == 1) path.lineTo(s.first.x * xh + 0.1, base + s.first.y * xh);
      canvas.drawPath(path, ink);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.line != line || old.color != color;
}
