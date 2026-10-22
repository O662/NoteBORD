import 'dart:math' as math_;
import 'dart:ui' show Brightness, PathMetric;

import 'package:flutter/painting.dart';

import '../board/model.dart';
import '../math/evaluate.dart';
import '../math/linear.dart' show latexToLinear;
import '../math/math_pictures.dart' show MathSource, mathFontFallback, mathReferenceSize;
import '../theme/colors.dart';
import '../theme/tokens.g.dart';

// A graph on the page (Graph.png, Graph.dc.html): a header with 2D · x y /
// 3D · x y z, zoom (and turning, in 3D); the functions, each with a dot
// that shows or hides it; "write or type an equation…"; the point being
// traced; and the plot. Everything is drawn in the design's units, scaled
// by the item's `unit`, so the card looks the same on the page, in
// thumbnails and in exports. Its buttons are pressed by the canvas
// (graphHitAt).

/// The colors new functions get, in turn (stored like ink).
final graphColors = <Color>[inkDefaults[1], inkDefaults[2], extraInkDefaults[0], extraInkDefaults[2], coverColors[4], coverColors[5]];

/// The next color for a graph that already uses [used].
Color nextGraphColor(Iterable<Color> used) {
  final taken = {for (final c in used) c.toARGB32()};
  return graphColors.firstWhere((c) => !taken.contains(c.toARGB32()), orElse: () => graphColors[taken.length % graphColors.length]);
}

final _parsed = <String, GraphFunction?>{};
final _surfaces = <String, SurfaceFunction?>{};
final _points = <String, List<double>?>{};

/// [expr] as a function of x (remembered), or null if it can't be graphed.
GraphFunction? graphFunction(String expr) => _parsed.putIfAbsent(expr, () => graphable(expr));

/// [expr] as a surface over x and y (remembered).
SurfaceFunction? graphSurface(String expr) => _surfaces.putIfAbsent(expr, () => surfaceOf(expr));

/// [expr] as a point in 3D (remembered).
List<double>? graphPoint(String expr) => _points.putIfAbsent(expr, () => point3dOf(expr));

/// Whether [expr] can go on a 3D graph: a surface or a point.
bool graphable3d(String expr) => graphSurface(expr) != null || graphPoint(expr) != null;

// Layout, in the design's units.

const _header = 60.0, _list = 270.0, _pad = 14.0;
const _rowH = 44.0, _chipPad = 8.0, _inkRow = 24.0;
const _addH = 54.0, _traceH = 54.0;
const _hintH = 38.0, _angleH = 21.0;

/// What a press on a graph lands on.
enum GraphPart { mode2d, mode3d, turnLeft, turnRight, zoomOut, zoomIn, toggle, edit, add, wireframe, surface, plot }

/// A part, and which function or surface for [GraphPart.toggle] and
/// [GraphPart.edit].
class GraphHit {
  const GraphHit(this.part, [this.index = -1]);

  final GraphPart part;
  final int index;

  @override
  bool operator ==(Object other) => other is GraphHit && other.part == part && other.index == index;

  @override
  int get hashCode => Object.hash(part, index);

  @override
  String toString() => 'GraphHit($part, $index)';
}

class _Row {
  _Row(this.index, this.chip, this.dot, this.math, this.ink);

  final int index;
  final Rect chip, dot, math;
  final Rect? ink;
}

class _Layout {
  _Layout(GraphItem g) : size = Size(g.w / g.unit, g.h / g.unit) {
    final w = size.width, h = size.height;
    // The header, right to left: zoom in, zoom out, the turn buttons in 3D,
    // then the 2D / 3D switch.
    var right = w - 12;
    zoomIn = Rect.fromLTWH(right - 44, 8, 44, 44);
    right = zoomIn.left - 10;
    zoomOut = Rect.fromLTWH(right - 44, 8, 44, 44);
    right = zoomOut.left - 10;
    if (g.is3d) {
      turnRight = Rect.fromLTWH(right - 44, 8, 44, 44);
      turnLeft = Rect.fromLTWH(turnRight!.left - 10 - 44, 8, 44, 44);
      right = turnLeft!.left - 10;
    }
    final w2 = _textWidth('2D · x y', 14, g.is3d ? FontWeight.w500 : FontWeight.w700) + 28;
    final w3 = _textWidth('3D · x y z', 14, g.is3d ? FontWeight.w700 : FontWeight.w500) + 28;
    seg = Rect.fromLTWH(right - (w2 + w3 + 8), 8, w2 + w3 + 8, 44);
    mode2d = Rect.fromLTWH(seg.left + 3, seg.top + 3, w2, 38);
    mode3d = Rect.fromLTWH(mode2d.right + 2, seg.top + 3, w3, 38);

    body = Rect.fromLTRB(_list, _header, w, h);
    plot = Rect.fromLTRB(_list + 15, _header + 20, math_.max(_list + 60, w - 45), math_.max(_header + 60, h - 40));

    // The list: what's graphed, then where to add more.
    final bottom = h - _pad;
    if (g.is3d) {
      footer = Rect.fromLTRB(_pad, bottom - _angleH - 8 - _hintH, _list - _pad, bottom);
    } else {
      trace = Rect.fromLTRB(_pad, bottom - _traceH, _list - _pad, bottom);
    }
    final limit = (g.is3d ? footer! : trace!).top - 8 - (4 + _addH);
    var top = _header + _pad;
    final lines = g.is3d ? g.surfaces : g.functions;
    for (final (i, line) in lines.indexed) {
      final double height;
      if (g.is3d) {
        height = 10 + 30 + (i == 0 ? 8 + 24 : 0) + 10;
      } else {
        height = _chipPad * 2 + _rowH + (line.ink.isNotEmpty ? 4 + _inkRow : 0);
      }
      if (top + height > limit) break;
      final chip = Rect.fromLTWH(_pad, top, _list - 2 * _pad, height);
      if (g.is3d) {
        final row = Rect.fromLTWH(chip.left + 12, chip.top + 10, chip.width - 24, 30);
        rows.add(_Row(i, chip, Rect.fromLTWH(row.left - 12, row.top - 7, 44, 44), Rect.fromLTRB(row.left + 22, row.top, row.right, row.bottom), null));
        if (i == 0) {
          final ww = _textWidth('Wireframe', 12, FontWeight.w600) + 20;
          final sw = _textWidth('Surface', 12, FontWeight.w600) + 20;
          wireframe = Rect.fromLTWH(row.left, row.bottom + 8, ww, 24);
          surface = Rect.fromLTWH(wireframe!.right + 6, row.bottom + 8, sw, 24);
        }
      } else {
        final dot = Rect.fromLTWH(chip.left + 10, chip.top + _chipPad, 44, 44);
        rows.add(_Row(
          i,
          chip,
          dot,
          Rect.fromLTRB(dot.right + 8, dot.top, chip.right - 8, dot.bottom),
          line.ink.isEmpty ? null : Rect.fromLTRB(dot.right + 8, dot.bottom + 4, chip.right - 8, dot.bottom + 4 + _inkRow),
        ));
      }
      top = chip.bottom + 8;
    }
    add = Rect.fromLTWH(_pad, top + 4, _list - 2 * _pad, _addH);
  }

  final Size size;
  late final Rect zoomIn, zoomOut, seg, mode2d, mode3d, body, plot, add;
  Rect? turnLeft, turnRight, trace, footer, wireframe, surface;
  final rows = <_Row>[];
}

final _layouts = Expando<_Layout>('graphLayout');

_Layout _layoutOf(GraphItem g) => _layouts[g] ??= _Layout(g);

/// Where the plot is, relative to the card's top-left.
Rect graphPlotRect(GraphItem g) {
  final r = _layoutOf(g).plot;
  return Rect.fromLTRB(r.left * g.unit, r.top * g.unit, r.right * g.unit, r.bottom * g.unit);
}

/// The smallest a graph can be stretched to (its list, header and some plot).
Size graphMinSize(GraphItem g) => Size((_list + 220) * g.unit, (_header + 300) * g.unit);

/// What's under [local] (relative to the card's top-left, unrotated).
GraphHit? graphHitAt(GraphItem g, Offset local) {
  final l = _layoutOf(g);
  final p = local / g.unit;
  if (!(Offset.zero & l.size).contains(p)) return null;
  if (l.mode2d.contains(p)) return const GraphHit(GraphPart.mode2d);
  if (l.mode3d.contains(p)) return const GraphHit(GraphPart.mode3d);
  if (l.zoomOut.contains(p)) return const GraphHit(GraphPart.zoomOut);
  if (l.zoomIn.contains(p)) return const GraphHit(GraphPart.zoomIn);
  if (l.turnLeft?.contains(p) ?? false) return const GraphHit(GraphPart.turnLeft);
  if (l.turnRight?.contains(p) ?? false) return const GraphHit(GraphPart.turnRight);
  if (l.wireframe?.contains(p) ?? false) return const GraphHit(GraphPart.wireframe);
  if (l.surface?.contains(p) ?? false) return const GraphHit(GraphPart.surface);
  for (final r in l.rows) {
    if (r.dot.contains(p)) return GraphHit(GraphPart.toggle, r.index);
    if (r.chip.contains(p)) return GraphHit(GraphPart.edit, r.index);
  }
  if (l.add.contains(p)) return const GraphHit(GraphPart.add);
  if (l.body.contains(p)) return const GraphHit(GraphPart.plot);
  return null;
}

// Changing the view (no undo steps: it's where you're looking).

/// [g] zoomed in by [factor] (out, below 1), about [local] or the middle.
GraphItem graphZoomed(GraphItem g, double factor, {Offset? local}) {
  if (g.is3d) return g.copyWith(view3d: g.view3d.copyWith(zoom: (g.view3d.zoom * factor).clamp(0.3, 5.0)));
  final v = g.view;
  final plot = graphPlotRect(g);
  final at = local == null
      ? v.center
      : Offset(
          v.left + (local.dx - plot.left) / plot.width * v.width,
          v.top + (plot.bottom - local.dy) / plot.height * v.height,
        );
  final k = 1 / factor.clamp(0.05, 20.0);
  final next = Rect.fromLTRB(at.dx + (v.left - at.dx) * k, at.dy + (v.top - at.dy) * k, at.dx + (v.right - at.dx) * k, at.dy + (v.bottom - at.dy) * k);
  if (next.width < 1e-3 || next.width > 1e6 || next.height < 1e-3 || next.height > 1e6) return g;
  return g.copyWith(view: next);
}

/// [g] with its plot dragged by [delta] (page px, unrotated): the 2D
/// window moves with it, a 3D view turns and tilts.
GraphItem graphDragged(GraphItem g, Offset delta) {
  if (g.is3d) {
    final d = delta / g.unit;
    return g.copyWith(
      view3d: g.view3d.copyWith(turn: _wrapDegrees(g.view3d.turn - d.dx * 0.5), tilt: (g.view3d.tilt + d.dy * 0.4).clamp(-10.0, 89.0)),
    );
  }
  final plot = graphPlotRect(g);
  final v = g.view;
  final dx = delta.dx / plot.width * v.width, dy = delta.dy / plot.height * v.height;
  return g.copyWith(view: v.translate(-dx, dy));
}

/// [g] turned by [degrees] about its z axis (the turn buttons: 20°).
GraphItem graphTurned(GraphItem g, double degrees) => g.copyWith(view3d: g.view3d.copyWith(turn: _wrapDegrees(g.view3d.turn + degrees)));

double _wrapDegrees(double d) {
  var a = d % 360;
  if (a > 180) a -= 360;
  return a;
}

/// Where the shown functions cross in the window: (x, y, the two
/// functions' indexes), left to right.
List<(double, double, int, int)> graphCrossings(GraphItem g) {
  final key = '${[for (final f in g.functions) '${f.expr}${f.hidden}'].join('|')}@${g.view}';
  return _crossings[key] ??= () {
    if (_crossings.length > 64) _crossings.clear();
    final out = <(double, double, int, int)>[];
    final v = g.view;
    final shown = [
      for (final (i, f) in g.functions.indexed)
        if (!f.hidden)
          if (graphFunction(f.expr) case final fn?) (i, fn),
    ];
    for (var a = 0; a < shown.length; a++) {
      for (var b = a + 1; b < shown.length; b++) {
        for (final x in crossingsOf(shown[a].$2, shown[b].$2, v.left, v.right, maxJump: v.height * 1.5)) {
          final y = shown[a].$2(x);
          if (y.isFinite && y >= v.top && y <= v.bottom) out.add((x, y, shown[a].$1, shown[b].$1));
        }
      }
    }
    out.sort((p, q) => p.$1.compareTo(q.$1));
    return out;
  }();
}

final _crossings = <String, List<(double, double, int, int)>>{};

/// The grid's step: 1, 2 or 5 times a power of ten, about ten lines across.
double graphStep(Rect view) => _niceStep(view.width);

/// [g] tracing the shown curve nearest [local] at its x: snapped to a
/// tenth of the grid step, or to where curves cross when that's nearer.
/// Null when there's nothing to trace there.
GraphItem? graphTracedAt(GraphItem g, Offset local) {
  if (g.is3d) return null;
  final plot = graphPlotRect(g);
  final v = g.view;
  double sx(double x) => plot.left + (x - v.left) / v.width * plot.width;
  double sy(double y) => plot.bottom - (y - v.top) / v.height * plot.height;
  final x = v.left + (local.dx - plot.left) / plot.width * v.width;
  // The nearest curve at that x.
  int? line;
  var best = double.infinity;
  for (final (i, f) in g.functions.indexed) {
    if (f.hidden) continue;
    final y = graphFunction(f.expr)?.call(x);
    if (y == null || !y.isFinite) continue;
    final d = (sy(y) - local.dy).abs();
    if (d < best) {
      best = d;
      line = i;
    }
  }
  final nearest = line;
  if (nearest == null) return null;
  final step = graphStep(v) / 10;
  final snapped = double.parse(((x / step).round() * step).toStringAsFixed(10));
  final ys = graphFunction(g.functions[nearest].expr)!(snapped);
  var reach = ys.isFinite ? (Offset(sx(snapped), sy(ys)) - local).distance : double.infinity;
  // A crossing wins when it's nearer than that tenth (and within 12 px):
  // Graph.png's (2, 2) is only 3.5 px from where the curves cross at 1.93.
  GraphTrace? crossing;
  for (final (cx, cy, a, b) in graphCrossings(g)) {
    final d = (Offset(sx(cx), sy(cy)) - local).distance;
    if (d <= 12 * g.unit && d < reach) {
      reach = d;
      crossing = GraphTrace(a == nearest || b == nearest ? nearest : a, cx);
    }
  }
  return g.copyWith(trace: () => crossing ?? GraphTrace(nearest, snapped));
}

/// The traced point (x, y) and whether it's where two curves cross, or
/// null when nothing is traced (or that function is hidden or undefined there).
({double x, double y, bool crossing})? graphTracePoint(GraphItem g) {
  final t = g.trace;
  if (t == null || g.is3d || t.line < 0 || t.line >= g.functions.length || g.functions[t.line].hidden) return null;
  final y = graphFunction(g.functions[t.line].expr)?.call(t.x);
  if (y == null || !y.isFinite) return null;
  final crossing = graphCrossings(g).any((c) => (c.$1 - t.x).abs() < 1e-9 && (c.$3 == t.line || c.$4 == t.line));
  return (x: t.x, y: y, crossing: crossing);
}

/// A number as the trace shows it: whole numbers as they are, others to two
/// places; minus signs as −.
String graphNumber(double v) {
  final r = (v * 100).round() / 100;
  final s = r == r.roundToDouble() ? '${r.round()}' : r.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
  return s == '-0' ? '0' : s.replaceFirst('-', '−');
}

// Painting.

void paintGraphCard(Canvas canvas, GraphItem g, Brightness brightness, EndlessColors c, MathSource? math) {
  final l = _layoutOf(g);
  final size = l.size;
  final card = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(18));
  canvas
    ..save()
    ..scale(g.unit);
  // 0 18px 36px -22px shadow
  if (size.shortestSide > 60) {
    canvas.drawRRect(
      card.deflate(22).shift(const Offset(0, 18)),
      Paint()
        ..color = c.shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
  }
  canvas
    ..drawRRect(card, Paint()..color = c.surface)
    ..drawRRect(card.deflate(0.5), _stroke(c.line, 1))
    ..save()
    ..clipRRect(card);

  _paintHeader(canvas, g, l, c);
  final soft = _stroke(c.lineSoft, 1);
  canvas
    ..drawLine(Offset(0, _header - 0.5), Offset(size.width, _header - 0.5), soft)
    ..drawLine(Offset(_list - 0.5, _header), Offset(_list - 0.5, size.height), soft);

  if (g.is3d) {
    _paintSurfaceList(canvas, g, l, brightness, c, math);
    canvas
      ..save()
      ..clipRect(l.body);
    _plot3d(canvas, g, l, brightness, c);
    canvas.restore();
  } else {
    _paintFunctionList(canvas, g, l, brightness, c, math);
    canvas
      ..save()
      ..clipRect(l.body);
    _plot2d(canvas, g, l, brightness, c);
    canvas.restore();
  }
  canvas
    ..restore()
    ..restore();
}

void _paintHeader(Canvas canvas, GraphItem g, _Layout l, EndlessColors c) {
  // The graph icon (20 px, centered in the 60 px header).
  canvas
    ..save()
    ..translate(16, 20)
    ..scale(20 / 24)
    ..drawPath(
      Path()
        ..moveTo(4, 3)
        ..lineTo(4, 20)
        ..lineTo(21, 20)
        ..moveTo(6, 17)
        ..cubicTo(9, 8, 12, 6, 14, 11)
        ..cubicTo(15, 13.5, 17, 15, 20, 7),
      _stroke(c.accentDeep, 1.9),
    )
    ..restore();
  _text(canvas, 'Graph', Offset(46, _header / 2), 16, c.text, weight: FontWeight.w700, middle: true);

  // 2D · x y | 3D · x y z
  canvas.drawRRect(RRect.fromRectAndRadius(l.seg, const Radius.circular(10)), Paint()..color = c.side);
  for (final (on, rect, label) in [(!g.is3d, l.mode2d, '2D · x y'), (g.is3d, l.mode3d, '3D · x y z')]) {
    if (on) {
      final r = RRect.fromRectAndRadius(rect, const Radius.circular(8));
      canvas
        ..drawRRect(
          r.shift(const Offset(0, 1)),
          Paint()
            ..color = c.shadow.withValues(alpha: c.shadow.a * 0.33)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1),
        )
        ..drawRRect(r, Paint()..color = c.surface);
    }
    _text(canvas, label, rect.center, 14, c.text, weight: on ? FontWeight.w700 : FontWeight.w500, center: true, middle: true);
  }

  if (l.turnLeft case final left?) _turnIcon(canvas, left, c, mirror: false);
  if (l.turnRight case final right?) _turnIcon(canvas, right, c, mirror: true);
  final icon = _stroke(c.text, 2 * 18 / 24);
  for (final (rect, plus) in [(l.zoomOut, false), (l.zoomIn, true)]) {
    final m = rect.center;
    const k = 7 * 18 / 24;
    canvas.drawLine(m.translate(-k, 0), m.translate(k, 0), icon);
    if (plus) canvas.drawLine(m.translate(0, -k), m.translate(0, k), icon);
  }
}

/// Rotate left (↺) or, mirrored, right (↻): a bordered 44 px button.
void _turnIcon(Canvas canvas, Rect rect, EndlessColors c, {required bool mirror}) {
  canvas.drawRRect(RRect.fromRectAndRadius(rect.deflate(0.5), const Radius.circular(10)), _stroke(c.lineStrong, 1));
  canvas
    ..save()
    ..translate(rect.center.dx, rect.center.dy)
    ..scale(mirror ? -18 / 24 : 18 / 24, 18 / 24)
    ..translate(-12, -12)
    ..drawPath(
      Path()
        ..moveTo(3, 12)
        ..arcToPoint(const Offset(6, 5.3), radius: const Radius.circular(9), largeArc: true, clockwise: false)
        ..lineTo(3, 8)
        ..moveTo(3, 3)
        ..lineTo(3, 8)
        ..lineTo(8, 8),
      _stroke(c.text, 2),
    )
    ..restore();
}

void _paintFunctionList(Canvas canvas, GraphItem g, _Layout l, Brightness brightness, EndlessColors c, MathSource? math) {
  for (final r in l.rows) {
    final line = g.functions[r.index];
    canvas.drawRRect(RRect.fromRectAndRadius(r.chip, const Radius.circular(12)), Paint()..color = c.bg);
    final ink = displayInk(line.color, brightness);
    // The dot: filled when the function is shown.
    final dot = r.dot.center;
    if (!line.hidden) canvas.drawCircle(dot, 10, Paint()..color = ink);
    canvas.drawCircle(dot, 8.5, _stroke(ink, 3));
    _paintMath(canvas, math, line.expr, r.math, 22, c.text);
    if (r.ink case final inkRow?) {
      final label = _text(canvas, 'from your handwriting', Offset(inkRow.left, inkRow.center.dy), 12, c.textMuted, middle: true);
      _paintInk(canvas, line.ink, Rect.fromLTRB(inkRow.left + label + 8, inkRow.top + 2, inkRow.right, inkRow.bottom - 2), ink);
    }
  }
  _dashed(canvas, RRect.fromRectAndRadius(l.add, const Radius.circular(12)), _stroke(c.lineStrong, 1.5));
  _text(
    canvas,
    'write or type an equation…',
    Offset(l.add.left + 12, l.add.center.dy),
    22,
    c.textMuted,
    family: FontFamilies.handwritingSample,
    middle: true,
  );

  // TRACE: the point being traced.
  final box = l.trace!;
  canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(12)), Paint()..color = c.accentTint);
  final t = graphTracePoint(g);
  _text(canvas, t != null && t.crossing ? 'CROSSING' : 'TRACE', Offset(box.left + 12, box.top + 9), 12, c.accentDeep, weight: FontWeight.w700);
  if (t != null) {
    _text(canvas, 'x = ${graphNumber(t.x)},  y = ${graphNumber(t.y)}', Offset(box.left + 12, box.top + 25), 18, c.accentDeep,
        family: FontFamilies.serif);
  } else {
    _text(canvas, g.functions.isEmpty ? 'Add an equation to graph it' : 'Tap a curve to trace it', Offset(box.left + 12, box.top + 29), 13,
        c.accentDeep);
  }
}

void _paintSurfaceList(Canvas canvas, GraphItem g, _Layout l, Brightness brightness, EndlessColors c, MathSource? math) {
  for (final r in l.rows) {
    final s = g.surfaces[r.index];
    canvas.drawRRect(RRect.fromRectAndRadius(r.chip, const Radius.circular(12)), Paint()..color = c.bg);
    final ink = displayInk(s.color, brightness);
    final square = RRect.fromRectAndRadius(Rect.fromCenter(center: r.dot.center, width: 14, height: 14), const Radius.circular(4));
    if (s.hidden) {
      canvas.drawRRect(square.deflate(1), _stroke(ink, 2));
    } else {
      canvas.drawRRect(square, Paint()..color = ink);
    }
    _paintMath(canvas, math, s.expr, r.math, 21, c.text);
  }
  for (final (rect, on, label) in [
    if (l.wireframe != null) (l.wireframe!, !g.view3d.surface, 'Wireframe'),
    if (l.surface != null) (l.surface!, g.view3d.surface, 'Surface'),
  ]) {
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(999)), Paint()..color = on ? c.inverse : c.side);
    _text(canvas, label, rect.center, 12, on ? c.onInverse : c.text, weight: FontWeight.w600, center: true, middle: true);
  }
  _dashed(canvas, RRect.fromRectAndRadius(l.add, const Radius.circular(12)), _stroke(c.lineStrong, 1.5));
  _text(canvas, 'add a surface or 3D point…', Offset(l.add.left + 12, l.add.center.dy), 22, c.textMuted,
      family: FontFamilies.handwritingSample, middle: true);
  final f = l.footer!;
  final hint = TextPainter(
    text: TextSpan(
      text: 'Two fingers rotate the view. Pinch to zoom.',
      style: TextStyle(fontFamily: FontFamilies.ui, fontSize: 13, height: 1.45, color: c.textMuted),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: f.width);
  hint.paint(canvas, f.topLeft);
  hint.dispose();
  _text(canvas, 'View angle: ${g.view3d.turn.round()}°', Offset(f.left, f.bottom - _angleH), 16, c.text, family: FontFamilies.serif);
}

void _plot2d(Canvas canvas, GraphItem g, _Layout l, Brightness brightness, EndlessColors c) {
  final v = g.view;
  final plot = l.plot;
  if (plot.isEmpty || v.width <= 0 || v.height <= 0) return;
  double sx(double x) => plot.left + (x - v.left) / v.width * plot.width;
  double sy(double y) => plot.bottom - (y - v.top) / v.height * plot.height;

  // The grid: the same step both ways, while that isn't too many lines.
  final step = _niceStep(v.width);
  final stepY = v.height / step <= 20 ? step : _niceStep(v.height);
  final grid = Path();
  for (var x = (v.left / step).ceil() * step; x <= v.right + 1e-9; x += step) {
    grid
      ..moveTo(sx(x), plot.top)
      ..lineTo(sx(x), plot.bottom);
  }
  for (var y = (v.top / stepY).ceil() * stepY; y <= v.bottom + 1e-9; y += stepY) {
    grid
      ..moveTo(plot.left, sy(y))
      ..lineTo(plot.right, sy(y));
  }
  canvas.drawPath(grid, _stroke(c.lineSoft, 1));
  final xAxis = v.top <= 0 && v.bottom >= 0, yAxis = v.left <= 0 && v.right >= 0;
  final axes = _stroke(c.textFaint, 1.6);
  final y0 = xAxis ? sy(0) : plot.bottom, x0 = yAxis ? sx(0) : plot.left;
  if (xAxis) canvas.drawLine(Offset(plot.left, y0), Offset(plot.right, y0), axes);
  if (yAxis) canvas.drawLine(Offset(x0, plot.top), Offset(x0, plot.bottom), axes);

  // Every other line is labelled: x under its axis, y left of it.
  for (var x = (v.left / (2 * step)).ceil() * 2 * step; x <= v.right + 1e-9; x += 2 * step) {
    if (x.abs() < step / 2 || sx(x) > plot.right - 6) continue;
    _text(canvas, _label(x), Offset(sx(x), y0 + 12.5), 11, c.textMuted, center: true, middle: true);
  }
  for (var y = (v.top / (2 * stepY)).ceil() * 2 * stepY; y <= v.bottom + 1e-9; y += 2 * stepY) {
    if (y.abs() < stepY / 2 || sy(y) < plot.top + 6 || sy(y) > plot.bottom - 6) continue;
    _text(canvas, _label(y), Offset(x0 - 12, sy(y) + 0.5), 11, c.textMuted, center: true, middle: true);
  }
  _text(canvas, 'x', Offset(plot.right, y0 - 22), 18, c.textMuted, family: FontFamilies.serif, italic: true);
  _text(canvas, 'y', Offset(x0 + 10, plot.top - 20), 18, c.textMuted, family: FontFamilies.serif, italic: true);

  // The curves: broken where they leave the window or jump (asymptotes).
  final reach = v.height * 0.042;
  final n = math_.max(200, (plot.width / 2).round());
  for (final line in g.functions) {
    if (line.hidden) continue;
    final f = graphFunction(line.expr);
    if (f == null) continue;
    final path = Path();
    var pen = false;
    double? lastY;
    for (var k = 0; k <= n; k++) {
      final x = v.left + v.width * k / n;
      final y = f(x);
      final ok = y.isFinite && y >= v.top - reach && y <= v.bottom + reach;
      final jump = lastY != null && y.isFinite && (y - lastY).abs() > v.height * 1.5;
      lastY = y.isFinite ? y : null;
      if (!ok || jump) {
        pen = false;
        if (!ok) continue;
      }
      if (pen) {
        path.lineTo(sx(x), sy(y));
      } else {
        path.moveTo(sx(x), sy(y));
        pen = true;
      }
    }
    canvas.drawPath(path, _stroke(displayInk(line.color, brightness), 3));
  }

  // Where curves cross.
  for (final (x, y, _, _) in graphCrossings(g)) {
    final p = Offset(sx(x), sy(y));
    canvas
      ..drawCircle(p, 4.5, Paint()..color = c.surface)
      ..drawCircle(p, 4.5, _stroke(c.textMuted, 2));
  }

  // The traced point, labelled with where it is.
  if (graphTracePoint(g) case final t?) {
    final p = Offset(sx(t.x), sy(t.y));
    canvas
      ..drawCircle(p, 7, Paint()..color = c.surface)
      ..drawCircle(p, 7, _stroke(displayInk(g.functions[g.trace!.line].color, brightness), 3));
    final label = '(${graphNumber(t.x)}, ${graphNumber(t.y)})';
    final w = _textWidth(label, 16, FontWeight.w400, family: FontFamilies.serif);
    final left = p.dx + 12 + w > plot.right ? p.dx - 12 - w : p.dx + 12;
    _text(canvas, label, Offset(left, p.dy + 8), 16, c.accentDeep, family: FontFamilies.serif);
  }
}

// 3D: an orthographic view, turned about z and tilted toward you.

const _span3d = 3.0, _zClip = 4.0;

class _View3d {
  _View3d(GraphItem g, Rect body)
      : center = body.center,
        s = 58 * g.view3d.zoom * math_.min(body.width / 588, body.height / 600),
        ca = math_.cos(g.view3d.turn * math_.pi / 180),
        sa = math_.sin(g.view3d.turn * math_.pi / 180),
        ce = math_.cos(g.view3d.tilt * math_.pi / 180),
        se = math_.sin(g.view3d.tilt * math_.pi / 180);

  final Offset center;
  final double s, ca, sa, ce, se;

  Offset at(double x, double y, double z) {
    final px = x * ca - y * sa, py = x * sa + y * ca;
    return Offset(center.dx + px * s, center.dy - (z * ce - py * se) * s);
  }

  /// How near the viewer: drawn far to near.
  double near(double x, double y, double z) => (x * sa + y * ca) * ce + z * se;
}

void _plot3d(Canvas canvas, GraphItem g, _Layout l, Brightness brightness, EndlessColors c) {
  final view = _View3d(g, l.body);
  final shown = [for (final s in g.surfaces) if (!s.hidden) s];
  if (g.view3d.surface) {
    _surfaces3d(canvas, shown, view, brightness, c);
  } else {
    for (final s in shown) {
      final f = graphSurface(s.expr);
      if (f == null) continue;
      final ink = displayInk(s.color, brightness);
      final along = Path(), across = Path();
      for (var k = -_span3d; k <= _span3d + 1e-9; k += 0.5) {
        _polyline(along, [for (var j = -_span3d; j <= _span3d + 1e-9; j += 0.25) (j, k, f(j, k))], view);
        _polyline(across, [for (var j = -_span3d; j <= _span3d + 1e-9; j += 0.25) (k, j, f(k, j))], view);
      }
      canvas
        ..drawPath(across, _stroke(ink.withValues(alpha: 0.5), 1.2))
        ..drawPath(along, _stroke(ink.withValues(alpha: 0.85), 1.4));
    }
  }
  final axes = _stroke(c.text.withValues(alpha: 0.85), 2);
  for (final (a, b) in [
    ((-3.8, 0.0, 0.0), (3.8, 0.0, 0.0)),
    ((0.0, -3.8, 0.0), (0.0, 3.8, 0.0)),
    ((0.0, 0.0, -2.6), (0.0, 0.0, 3.2)),
  ]) {
    canvas.drawLine(view.at(a.$1, a.$2, a.$3), view.at(b.$1, b.$2, b.$3), axes);
  }
  for (final (name, p) in [('x', view.at(4.2, 0, 0)), ('y', view.at(0, 4.2, 0)), ('z', view.at(0, 0, 3.5).translate(-6, 0))]) {
    _text(canvas, name, p.translate(0, -16), 20, c.text, family: FontFamilies.serif, italic: true);
  }
  for (final s in shown) {
    final p = graphPoint(s.expr);
    if (p == null) continue;
    final at = view.at(p[0], p[1], p[2]);
    canvas
      ..drawCircle(at, 6, Paint()..color = displayInk(s.color, brightness))
      ..drawCircle(at, 6, _stroke(c.surface, 1.5));
    _text(canvas, '(${p.map(graphNumber).join(', ')})', at.translate(10, -22), 15, c.text, family: FontFamilies.serif);
  }
}

/// Adds the points to [path], lifting the pen where z is undefined or far
/// off the box.
void _polyline(Path path, List<(double, double, double)> pts, _View3d view) {
  var pen = false;
  for (final (x, y, z) in pts) {
    if (!z.isFinite || z.abs() > _zClip) {
      pen = false;
      continue;
    }
    final p = view.at(x, y, z);
    if (pen) {
      path.lineTo(p.dx, p.dy);
    } else {
      path.moveTo(p.dx, p.dy);
      pen = true;
    }
  }
}

/// Shaded surfaces: small quads drawn far to near, lit from above you.
void _surfaces3d(Canvas canvas, List<GraphLine> shown, _View3d view, Brightness brightness, EndlessColors c) {
  const step = 0.25;
  final n = (2 * _span3d / step).round();
  final quads = <(double, Path, Color)>[];
  for (final s in shown) {
    final f = graphSurface(s.expr);
    if (f == null) continue;
    final ink = displayInk(s.color, brightness);
    double z(int i, int j) => f(-_span3d + i * step, -_span3d + j * step);
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        final x0 = -_span3d + i * step, y0 = -_span3d + j * step;
        final zs = [z(i, j), z(i + 1, j), z(i + 1, j + 1), z(i, j + 1)];
        if (zs.any((v) => !v.isFinite || v.abs() > _zClip)) continue;
        final corners = [(x0, y0, zs[0]), (x0 + step, y0, zs[1]), (x0 + step, y0 + step, zs[2]), (x0, y0 + step, zs[3])];
        // The normal, from the diagonals.
        final ax = step, ay = step, az = zs[2] - zs[0];
        final bx = -step, by = step, bz = zs[3] - zs[1];
        var nx = ay * bz - az * by, ny = az * bx - ax * bz, nz = ax * by - ay * bx;
        final len = math_.sqrt(nx * nx + ny * ny + nz * nz);
        nx /= len;
        ny /= len;
        nz /= len;
        final light = (nx * -0.35 + ny * 0.45 + nz * 0.82).abs();
        final shade = Color.lerp(c.surface, ink, 0.3 + 0.6 * light)!;
        final path = Path()..addPolygon([for (final p in corners) view.at(p.$1, p.$2, p.$3)], true);
        final mid = view.near(x0 + step / 2, y0 + step / 2, (zs[0] + zs[2]) / 2);
        quads.add((mid, path, shade));
      }
    }
  }
  quads.sort((a, b) => a.$1.compareTo(b.$1));
  final edge = _stroke(c.surface.withValues(alpha: 0.35), 0.6);
  for (final (_, path, color) in quads) {
    canvas
      ..drawPath(path, Paint()..color = color)
      ..drawPath(path, edge);
  }
}

// Helpers.

Paint _stroke(Color color, double width) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..color = color;

/// A function in [box], centered on its middle: as Graph.dc.html writes it,
/// in italic serif on one line (`y = x² / 2`), as the keyboard types it.
/// What the keyboard can only write as LaTeX is typeset instead (shrunk to
/// fit, at [fontSize]).
void _paintMath(Canvas canvas, MathSource? math, String latex, Rect box, double fontSize, Color color) {
  final linear = latexToLinear(latex).trim();
  final typeset = linear.contains(r'\') ? math?.picture(latex) : null;
  if (typeset == null) {
    _text(canvas, linear, Offset(box.left, box.center.dy), fontSize, color,
        family: FontFamilies.serif, italic: true, middle: true, maxWidth: box.width);
    return;
  }
  final k = math_.min(fontSize / mathReferenceSize, math_.min(box.width / typeset.size.width, (box.height - 4) / typeset.size.height));
  final tall = typeset.size.height * k;
  canvas
    ..save()
    ..translate(box.left, box.center.dy - tall / 2)
    ..scale(k)
    ..saveLayer(Offset.zero & typeset.size, Paint()..colorFilter = ColorFilter.mode(color, BlendMode.srcIn))
    ..drawPicture(typeset.picture)
    ..restore()
    ..restore();
}

/// The handwriting a function came from, fitted into [box] from its left.
void _paintInk(Canvas canvas, List<List<Offset>> ink, Rect box, Color color) {
  if (ink.isEmpty || box.width <= 0 || box.height <= 0) return;
  var r = Rect.fromPoints(ink.first.first, ink.first.first);
  for (final s in ink) {
    for (final p in s) {
      r = r.expandToInclude(Rect.fromPoints(p, p));
    }
  }
  final k = math_.min(box.height / math_.max(r.height, 1), box.width / math_.max(r.width, 1));
  final path = Path();
  for (final s in ink) {
    for (final (i, p) in s.indexed) {
      final q = box.topLeft + (p - r.topLeft) * k + Offset(0, (box.height - r.height * k) / 2);
      if (i == 0) {
        path.moveTo(q.dx, q.dy);
      } else {
        path.lineTo(q.dx, q.dy);
      }
    }
  }
  canvas.drawPath(path, _stroke(color, 1.4));
}

void _dashed(Canvas canvas, RRect shape, Paint paint, {double dash = 6, double gap = 4}) {
  final out = Path();
  for (final PathMetric m in (Path()..addRRect(shape)).computeMetrics()) {
    for (var d = 0.0; d < m.length; d += dash + gap) {
      out.addPath(m.extractPath(d, math_.min(d + dash, m.length)), Offset.zero);
    }
  }
  canvas.drawPath(out, paint);
}

/// 1, 2 or 5 times a power of ten: about ten grid lines across [span].
double _niceStep(double span) {
  final raw = span / 10;
  final p = math_.pow(10, (math_.log(raw) / math_.ln10).floor()).toDouble();
  for (final m in const [1, 2, 5, 10]) {
    if (m * p >= raw - 1e-12) return m * p;
  }
  return 10 * p;
}

String _label(double v) {
  final r = (v * 1000).round() / 1000;
  return (r == r.roundToDouble() ? '${r.round()}' : '$r').replaceFirst('-', '−');
}

double _textWidth(String s, double size, FontWeight weight, {String family = FontFamilies.ui}) {
  final p = TextPainter(
    text: TextSpan(text: s, style: TextStyle(fontFamily: family, fontFamilyFallback: mathFontFallback, fontSize: size, fontWeight: weight)),
    textDirection: TextDirection.ltr,
  )..layout();
  final w = p.width;
  p.dispose();
  return w;
}

/// Draws [s] at [at] (its top-left, or its middle with [center] and
/// [middle]); returns its width.
double _text(
  Canvas canvas,
  String s,
  Offset at,
  double size,
  Color color, {
  FontWeight weight = FontWeight.w400,
  String family = FontFamilies.ui,
  bool italic = false,
  bool center = false,
  bool middle = false,
  double? maxWidth,
}) {
  final p = TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(
        fontFamily: family,
        fontFamilyFallback: mathFontFallback,
        fontSize: size,
        fontWeight: weight,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        color: color,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: maxWidth == null ? null : '…',
  )..layout(maxWidth: maxWidth ?? double.infinity);
  p.paint(canvas, Offset(center ? at.dx - p.width / 2 : at.dx, middle ? at.dy - p.height / 2 : at.dy));
  final w = p.width;
  p.dispose();
  return w;
}
