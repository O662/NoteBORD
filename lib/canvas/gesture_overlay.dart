import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../board/model.dart';
import '../theme/colors.dart';
import 'canvas_view.dart';
import 'gestures.dart';
import 'page_runtime.dart';
import 'selection.dart';

/// What the pen gestures are showing right now, drawn over the ink.
class GestureOverlayState extends ChangeNotifier {
  ShapeFit? _holdFit;
  ShapeFit? _snapped;
  ShapeFit? _glow;
  Set<String> _scribble = const {};
  List<Offset> _lasso = [];
  Rect? _marquee;

  /// While the pen is held: the shape it will snap to (dashed).
  ShapeFit? get holdFit => _holdFit;
  set holdFit(ShapeFit? v) => _set(() => _holdFit = v);

  /// After the snap, while the pen is still down.
  ShapeFit? get snapped => _snapped;
  set snapped(ShapeFit? v) => _set(() => _snapped = v);

  /// A straightened line's ends and angle, shown with its "Undo" toast.
  ShapeFit? get glow => _glow;
  set glow(ShapeFit? v) => _set(() => _glow = v);

  /// Strokes the scribble in progress would erase. A new set each time it
  /// changes (the ink layer caches on the instance).
  Set<String> get scribble => _scribble;
  set scribble(Set<String> v) => _set(() => _scribble = v);

  /// The lasso loop being drawn (page space). Add points, then [ping].
  List<Offset> get lasso => _lasso;
  set lasso(List<Offset> v) => _set(() => _lasso = v);

  /// The Select tool's drag box (page space).
  Rect? get marquee => _marquee;
  set marquee(Rect? v) => _set(() => _marquee = v);

  void _set(void Function() change) {
    change();
    notifyListeners();
  }

  void ping() => notifyListeners();
}

/// Dashes along [source]: [dash] on, [gap] off.
Path dashed(Path source, double dash, double gap) {
  final out = Path();
  for (final m in source.computeMetrics()) {
    for (var d = 0.0; d < m.length; d += dash + gap) {
      out.addPath(m.extractPath(d, math.min(d + dash, m.length)), Offset.zero);
    }
  }
  return out;
}

class GestureOverlayPainter extends CustomPainter {
  GestureOverlayPainter({
    required this.overlay,
    required this.vp,
    required this.page,
    required this.selection,
    required this.outline,
    required this.hold,
    required this.holdAt,
    required this.inkColor,
    required this.brightness,
    required this.colors,
  }) : super(repaint: Listenable.merge([overlay, vp, hold, selection]));

  final GestureOverlayState overlay;
  final CanvasView vp;
  final PageRuntime page;
  final Selection selection;

  /// The selection outline in page space (null when nothing is selected).
  final Path? Function() outline;

  /// Progress of the hold to straighten (0–1).
  final Animation<double> hold;

  /// Where the pen is, on screen.
  final Offset? Function() holdAt;
  final Color inkColor;
  final Brightness brightness;
  final EndlessColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final live = selection.live;

    // Selected items while they're dragged (the ink layer leaves them out).
    if (live != null) {
      canvas
        ..save()
        ..transform(vp.matrix.storage)
        ..transform(live.matrix.storage);
      for (final id in selection.ids) {
        if (page[id] case final item?) paintItem(canvas, item, brightness, colors);
      }
      canvas.restore();
    }

    // What a scribble is about to erase (Scribble.dc.html: faded red).
    if (overlay.scribble.isNotEmpty) {
      canvas
        ..save()
        ..transform(vp.matrix.storage);
      for (final id in overlay.scribble) {
        if (page[id] case final StrokeItem s) paintStroke(canvas, s, colors.scribbleMark, opacity: 0.45);
      }
      canvas.restore();
    }

    final fill = Paint()..color = colors.accent.withValues(alpha: 0.06);
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = colors.accent;

    // The selection's dashed outline, with resize and rotate handles.
    var path = selection.isEmpty ? null : outline();
    if (path != null) {
      if (live != null) path = path.transform(live.matrix.storage);
      final screen = path.transform(vp.matrix.storage);
      canvas
        ..drawPath(screen, fill)
        ..drawPath(dashed(screen, 7, 6), dash);
      if (live == null) _handles(canvas, screen.getBounds());
    }

    // A lasso being drawn, or the Select tool's box.
    if (overlay.lasso.length > 1) {
      final loop = Path()..addPolygon([for (final p in overlay.lasso) vp.toScreen(p)], true);
      canvas
        ..drawPath(loop, fill)
        ..drawPath(dashed(loop, 7, 6), dash);
    }
    if (overlay.marquee case final m?) {
      final box = Path()..addRect(Rect.fromPoints(vp.toScreen(m.topLeft), vp.toScreen(m.bottomRight)));
      canvas
        ..drawPath(box, fill)
        ..drawPath(dashed(box, 7, 6), dash);
    }

    // Hold to straighten: the dashed shape and the ring filling up (Tools.dc.html).
    if (overlay.holdFit case final fit?) {
      final shape = Path()..addPolygon([for (final p in fit.points) vp.toScreen(p)], false);
      canvas.drawPath(
        dashed(shape, 6, 6),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = inkColor.withValues(alpha: 0.8),
      );
      if (holdAt() case final at?) {
        final ring = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round;
        canvas
          ..drawCircle(at, 20, ring..color = colors.line)
          ..drawArc(Rect.fromCircle(center: at, radius: 20), -math.pi / 2, 2 * math.pi * hold.value, false,
              ring..color = inkColor);
      }
    }

    final line = overlay.snapped ?? overlay.glow;
    if (line != null && line.kind == ShapeKind.line) _lineMarks(canvas, line);
  }

  void _handles(Canvas canvas, Rect box) {
    final fill = Paint()..color = colors.surface;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = colors.accent;
    for (final c in [box.topLeft, box.topRight, box.bottomRight, box.bottomLeft]) {
      canvas
        ..drawCircle(c, 6, fill)
        ..drawCircle(c, 6, ring);
    }
    // Rotate: a knob on a short stem below the selection.
    final knob = box.bottomCenter + const Offset(0, 30);
    canvas
      ..drawLine(box.bottomCenter, knob - const Offset(0, 11), ring..strokeWidth = 1.5)
      ..drawCircle(knob, 11, fill)
      ..drawCircle(knob, 11, ring..strokeWidth = 2);
    final arrow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = colors.accent;
    canvas.drawArc(Rect.fromCircle(center: knob, radius: 5), -math.pi * 0.9, math.pi * 1.5, false, arrow);
    final tip = knob + Offset(math.cos(math.pi * 0.6), math.sin(math.pi * 0.6)) * 5;
    canvas
      ..drawLine(tip, tip + const Offset(-3.5, -0.5), arrow)
      ..drawLine(tip, tip + const Offset(0.5, -3.5), arrow);
  }

  /// End circles, a dashed level line and the angle (Tools.dc.html, step 3).
  void _lineMarks(Canvas canvas, ShapeFit line) {
    final a = vp.toScreen(line.points.first), b = vp.toScreen(line.points.last);
    final ends = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = inkColor;
    for (final p in [a, b]) {
      canvas
        ..drawCircle(p, 6, Paint()..color = colors.surface)
        ..drawCircle(p, 6, ends);
    }
    final angle = line.angle ?? 0;
    if (angle == 0 || angle == 90) return;
    final right = b.dx >= a.dx;
    final muted = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = colors.textMuted;
    final level = Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(a.dx + (right ? 80 : -80), a.dy);
    canvas.drawPath(dashed(level, 4, 4), muted);
    final dir = math.atan2(b.dy - a.dy, b.dx - a.dx);
    final base = right ? 0.0 : math.pi;
    var sweep = dir - base;
    sweep = math.atan2(math.sin(sweep), math.cos(sweep));
    canvas.drawArc(Rect.fromCircle(center: a, radius: 60), base, sweep, false, muted);
    final mid = base + sweep / 2;
    final label = TextPainter(
      text: TextSpan(
        text: '$angle°',
        style: TextStyle(fontFamily: 'Figtree', fontSize: 13, fontWeight: FontWeight.w600, color: colors.inverseRaised),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final at = a + Offset(math.cos(mid), math.sin(mid)) * 76;
    label.paint(canvas, at - Offset(label.width / 2, label.height / 2));
  }

  @override
  bool shouldRepaint(GestureOverlayPainter old) => true;
}
