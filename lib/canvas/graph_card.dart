import 'dart:math' as math_;
import 'dart:ui' show Brightness;

import 'package:flutter/painting.dart';

import '../board/model.dart';
import '../math/evaluate.dart';
import '../math/math_pictures.dart' show MathSource, mathReferenceSize;
import '../theme/colors.dart';
import '../theme/tokens.g.dart';

// A graph on the page (Graph.png, drawn smaller): "Graph" over its
// functions, each with its color and typeset, beside the plot.

const _header = 44.0, _list = 168.0, _pad = 12.0;

final _parsed = <String, GraphFunction?>{};

/// [expr] as a function of x (remembered), or null if it can't be graphed.
GraphFunction? graphFunction(String expr) => _parsed.putIfAbsent(expr, () => graphable(expr));

/// Where the plot is, relative to the card's top-left.
Rect graphPlotRect(GraphItem g) {
  final u = g.unit;
  return Rect.fromLTRB((_list + _pad) * u, (_header + _pad) * u, g.w - _pad * u, g.h - _pad * u);
}

void paintGraphCard(Canvas canvas, GraphItem g, Brightness brightness, EndlessColors c, MathSource? math) {
  final u = g.unit;
  final card = RRect.fromRectAndRadius(Offset.zero & Size(g.w, g.h), Radius.circular(18 * u));
  canvas
    ..drawRRect(card, Paint()..color = c.surface)
    ..drawRRect(
      card.deflate(0.5 * u),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = u
        ..color = c.line,
    );

  // The header: an axes icon and "Graph".
  final icon = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6 * u
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = c.text;
  final o = Offset(18 * u, 13 * u);
  canvas.drawPath(
    Path()
      ..moveTo(o.dx, o.dy)
      ..lineTo(o.dx, o.dy + 18 * u)
      ..lineTo(o.dx + 18 * u, o.dy + 18 * u)
      ..moveTo(o.dx + 3 * u, o.dy + 13 * u)
      ..lineTo(o.dx + 8 * u, o.dy + 7 * u)
      ..lineTo(o.dx + 12 * u, o.dy + 10 * u)
      ..lineTo(o.dx + 18 * u, o.dy + 3 * u),
    icon,
  );
  _text(canvas, 'Graph', Offset(46 * u, _header * u / 2), 16 * u, c.text, weight: FontWeight.w600, middle: true);
  canvas.drawLine(Offset(0, _header * u), Offset(g.w, _header * u), Paint()
    ..color = c.line
    ..strokeWidth = u);
  canvas.drawLine(Offset(_list * u, _header * u), Offset(_list * u, g.h), Paint()
    ..color = c.line
    ..strokeWidth = u);

  // The functions, each on a chip with its color.
  var top = (_header + 12) * u;
  for (final line in g.functions) {
    final typeset = math?.picture(line.expr);
    // The math at 18 px, shrunk only if it's too wide for the chip.
    final room = (_list - 20 - 42) * u;
    final k = typeset == null ? 0.0 : math_.min(18 * u / mathReferenceSize, room / typeset.size.width);
    final tall = typeset == null ? 0.0 : typeset.size.height * k;
    final chip = Rect.fromLTWH(10 * u, top, (_list - 20) * u, math_.max(46 * u, tall + 16 * u));
    if (chip.bottom > g.h - 8 * u) break;
    canvas.drawRRect(RRect.fromRectAndRadius(chip, Radius.circular(12 * u)), Paint()..color = c.surfaceSunk);
    final ink = displayInk(line.color, brightness);
    canvas.drawCircle(Offset(chip.left + 18 * u, chip.center.dy), 7 * u, Paint()..color = ink);
    if (typeset != null) {
      canvas
        ..save()
        ..translate(chip.left + 34 * u, chip.center.dy - tall / 2)
        ..scale(k)
        ..saveLayer(Offset.zero & typeset.size, Paint()..colorFilter = ColorFilter.mode(c.text, BlendMode.srcIn))
        ..drawPicture(typeset.picture)
        ..restore()
        ..restore();
    }
    top = chip.bottom + 8 * u;
  }

  _plot(canvas, g, graphPlotRect(g), brightness, c);
}

void _plot(Canvas canvas, GraphItem g, Rect plot, Brightness brightness, EndlessColors c) {
  final u = g.unit;
  final v = g.view;
  if (plot.isEmpty || v.width <= 0 || v.height <= 0) return;
  Offset at(double x, double y) =>
      Offset(plot.left + (x - v.left) / v.width * plot.width, plot.bottom - (y - v.top) / v.height * plot.height);

  canvas
    ..save()
    ..clipRect(plot);
  final grid = Paint()
    ..color = c.lineSoft
    ..strokeWidth = u;
  final stepX = _niceStep(v.width), stepY = _niceStep(v.height);
  for (var x = (v.left / stepX).ceil() * stepX; x <= v.right; x += stepX) {
    canvas.drawLine(at(x, v.top), at(x, v.bottom), grid);
  }
  for (var y = (v.top / stepY).ceil() * stepY; y <= v.bottom; y += stepY) {
    canvas.drawLine(at(v.left, y), at(v.right, y), grid);
  }
  final axis = Paint()
    ..color = c.textMuted
    ..strokeWidth = 1.2 * u;
  if (v.top <= 0 && v.bottom >= 0) canvas.drawLine(at(v.left, 0), at(v.right, 0), axis);
  if (v.left <= 0 && v.right >= 0) canvas.drawLine(at(0, v.top), at(0, v.bottom), axis);

  // Every other grid line is labelled, beside the axes (or the plot's edge).
  final labelY = (v.top <= 0 && v.bottom >= 0) ? at(0, 0).dy : plot.bottom - 14 * u;
  final labelX = (v.left <= 0 && v.right >= 0) ? at(0, 0).dx : plot.left + 4 * u;
  for (var x = (v.left / (2 * stepX)).ceil() * 2 * stepX; x <= v.right; x += 2 * stepX) {
    if (x.abs() < stepX / 2) continue;
    _text(canvas, _label(x), at(x, 0).translate(0, 0).copyWith(dy: labelY + 4 * u), 10 * u, c.textMuted, center: true);
  }
  for (var y = (v.top / (2 * stepY)).ceil() * 2 * stepY; y <= v.bottom; y += 2 * stepY) {
    final at0 = at(0, y).dy;
    if (y.abs() < stepY / 2 || at0 < plot.top + 8 * u || at0 > plot.bottom - 8 * u) continue;
    _text(canvas, _label(y), Offset(labelX + 5 * u, at(0, y).dy), 10 * u, c.textMuted, middle: true);
  }

  // The curves: broken where they leave the plot far or stop being defined.
  for (final line in g.functions) {
    final f = graphFunction(line.expr);
    if (f == null) continue;
    final path = Path();
    var pen = false;
    final n = math_.max(60, (plot.width / u / 2).round());
    double? lastY;
    for (var k = 0; k <= n; k++) {
      final x = v.left + v.width * k / n;
      final y = f(x);
      final ok = y.isFinite && y > v.top - v.height * 4 && y < v.bottom + v.height * 4;
      // A jump across the whole window is an asymptote, not a line.
      final jump = lastY != null && (y - lastY).abs() > v.height * 1.5;
      if (!ok || jump) {
        pen = false;
        lastY = ok ? y : null;
        if (!ok) continue;
      }
      final p = at(x, y);
      if (pen) {
        path.lineTo(p.dx, p.dy);
      } else {
        path.moveTo(p.dx, p.dy);
        pen = true;
      }
      lastY = y;
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6 * u
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = displayInk(line.color, brightness),
    );
  }
  canvas.restore();
}

extension on Offset {
  Offset copyWith({double? dx, double? dy}) => Offset(dx ?? this.dx, dy ?? this.dy);
}

/// 1, 2 or 5 times a power of ten: about ten grid lines across [span].
double _niceStep(double span) {
  final raw = span / 10;
  final p = math_.pow(10, (math_.log(raw) / math_.ln10).floor()).toDouble();
  for (final m in const [1, 2, 5, 10]) {
    if (m * p >= raw) return m * p;
  }
  return 10 * p;
}

String _label(double v) {
  final r = (v * 1000).round() / 1000;
  return r == r.roundToDouble() ? '${r.round()}'.replaceFirst('-', '−') : '$r'.replaceFirst('-', '−');
}

void _text(
  Canvas canvas,
  String s,
  Offset at,
  double size,
  Color color, {
  FontWeight weight = FontWeight.w400,
  bool center = false,
  bool middle = false,
}) {
  final p = TextPainter(
    text: TextSpan(text: s, style: TextStyle(fontFamily: FontFamilies.ui, fontSize: size, fontWeight: weight, color: color)),
    textDirection: TextDirection.ltr,
  )..layout();
  p.paint(canvas, Offset(center ? at.dx - p.width / 2 : at.dx, middle ? at.dy - p.height / 2 : at.dy));
  p.dispose();
}
