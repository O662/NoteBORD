import 'dart:math' as math_;
import 'dart:ui' show Brightness, PathMetric;

import 'package:flutter/painting.dart';

import '../board/ids.dart';
import '../board/model.dart';
import '../math/evaluate.dart';
import '../math/linear.dart' show latexToLinear;
import '../math/math_pictures.dart' show mathFontFallback;
import '../theme/colors.dart';
import '../theme/tokens.g.dart';
import 'graph_card.dart' show graphColors, nextGraphColor;

// The math tools on the page (MathKit.png, MathKit.dc.html): a number line
// with points and intervals, the unit circle stepping through the special
// angles, and a polar grid with curves. Drawn in the design's units, scaled
// by the item's `unit`; their buttons are pressed by the canvas
// (mathToolHitAt).

/// The 16 special angles: degrees, radians, and exact cos, sin and tan.
const specialAngles = <(int, String, String, String, String)>[
  (0, '0', '1', '0', '0'),
  (30, 'π/6', '√3/2', '1/2', '√3/3'),
  (45, 'π/4', '√2/2', '√2/2', '1'),
  (60, 'π/3', '1/2', '√3/2', '√3'),
  (90, 'π/2', '0', '1', 'undefined'),
  (120, '2π/3', '−1/2', '√3/2', '−√3'),
  (135, '3π/4', '−√2/2', '√2/2', '−1'),
  (150, '5π/6', '−√3/2', '1/2', '−√3/3'),
  (180, 'π', '−1', '0', '0'),
  (210, '7π/6', '−√3/2', '−1/2', '√3/3'),
  (225, '5π/4', '−√2/2', '−√2/2', '1'),
  (240, '4π/3', '−1/2', '−√3/2', '√3'),
  (270, '3π/2', '0', '−1', 'undefined'),
  (300, '5π/3', '1/2', '−√3/2', '−√3'),
  (315, '7π/4', '√2/2', '−√2/2', '−1'),
  (330, '11π/6', '√3/2', '−1/2', '−√3/3'),
];

/// Each tool's width in the design.
const numberLineWidth = 790.0, unitCircleWidth = 400.0, polarWidth = 370.0;

/// A new tool of [kind] ('numberline', 'unitcircle' or 'polar') at [at]
/// (its top-left).
MathToolItem newMathTool(String kind, Offset at, {required int z, required DateTime now}) {
  final MathToolData data = switch (kind) {
    'numberline' => const NumberLineData(),
    'unitcircle' => const UnitCircleData(),
    _ => PolarData(curves: [
        GraphLine(r'r=1+\cos\theta', graphColors[0]),
        GraphLine(r'r=2\cos 3\theta', graphColors[1], hidden: true),
      ]),
  };
  final w = switch (data) {
    NumberLineData _ => numberLineWidth,
    UnitCircleData _ => unitCircleWidth,
    PolarData _ => polarWidth,
  };
  return fitMathTool(MathToolItem(id: newId('it', now: now), x: at.dx, y: at.dy, z: z, createdAt: now, w: w, h: 100, data: data));
}

/// What a tool is called in "Added … to the page".
String mathToolName(MathToolData data) => switch (data) {
      NumberLineData _ => 'a number line',
      UnitCircleData _ => 'the unit circle',
      PolarData _ => 'a polar grid',
    };

/// [t] as tall as what it shows needs (its header can wrap).
MathToolItem fitMathTool(MathToolItem t) {
  final h = _layoutFor(t.data, t.w / t.unit).height * t.unit;
  if ((h - t.h).abs() < 0.05) return t;
  return MathToolItem(
    id: t.id,
    x: t.x,
    y: t.y,
    rotation: t.rotation,
    z: t.z,
    createdAt: t.createdAt,
    author: t.author,
    remember: t.remember,
    extra: t.extra,
    w: t.w,
    h: h,
    data: t.data,
    unit: t.unit,
  );
}

// Reading the numbers.

final _values = <String, double?>{};
final _polar = <String, PolarFunction?>{};

/// The number a point or an interval's end is (∞ for `\infty`).
double? numberValue(String latex) => _values.putIfAbsent(latex, () => constantOf(latex));

PolarFunction? polarCurve(String expr) => _polar.putIfAbsent(expr, () => polarOf(expr));

/// A number as the number line labels it: `\sqrt{2}` is √2, `-2.5` −2.5.
String numberLabel(String latex) {
  final s = latexToLinear(latex).trim().replaceAll(' / ', '/');
  return s.startsWith('− ') ? '−${s.substring(2)}' : s;
}

/// An interval as its chip names it: [1, π).
String intervalLabel(NumberSpan s) =>
    '${s.openFrom ? '(' : '['}${numberLabel(s.from)}, ${numberLabel(s.to)}${s.openTo ? ')' : ']'}';

/// What's typed for the number line: a number (`√2`) or an interval
/// (`[1, π)`, `(−∞, 2]`), from the keyboard's text and its LaTeX for each
/// part. Null when it's neither.
({String? point, NumberSpan? span})? readNumberLine(String text, String Function(String) toLatex, Color color) {
  final t = text.trim();
  final m = RegExp(r'^([\[(])(.+),(.+)([\])])$').firstMatch(t);
  if (m != null) {
    final from = toLatex(m.group(2)!.trim()), to = toLatex(m.group(3)!.trim());
    final a = numberValue(from), b = numberValue(to);
    if (a == null || b == null || a >= b || a == double.infinity || b == double.negativeInfinity) return null;
    return (
      point: null,
      span: NumberSpan(from, to, color, openFrom: m.group(1) == '(' || a.isInfinite, openTo: m.group(4) == ')' || b.isInfinite),
    );
  }
  final latex = toLatex(t);
  final v = numberValue(latex);
  if (v == null || v.isInfinite) return null;
  return (point: latex, span: null);
}

/// The next color for a number line's point or interval.
Color nextNumberColor(NumberLineData d) => nextGraphColor([for (final p in d.points) p.color, for (final s in d.spans) s.color]);

// Pressing.

enum MathToolPart {
  /// The unit circle's − and +.
  previous,
  next,

  /// An interval's chip (shows or hides it), or a polar curve's.
  chip,

  /// "+ point" or the polar grid's +.
  add,

  /// A point on the number line, or a polar curve on the plot: edit it.
  item,

  /// An interval on the line (edit it), or one of its ends (open / close).
  span,
  spanFrom,
  spanTo,
}

class MathToolHit {
  const MathToolHit(this.part, [this.index = -1]);

  final MathToolPart part;
  final int index;

  @override
  bool operator ==(Object other) => other is MathToolHit && other.part == part && other.index == index;

  @override
  int get hashCode => Object.hash(part, index);

  @override
  String toString() => 'MathToolHit($part, $index)';
}

/// What's under [local] (relative to the tool's top-left, unrotated).
MathToolHit? mathToolHitAt(MathToolItem t, Offset local) {
  final l = _layoutOf(t);
  final p = local / t.unit;
  for (final (i, chip) in l.chips.indexed) {
    if (chip.contains(p)) return MathToolHit(MathToolPart.chip, i);
  }
  if (l.add?.contains(p) ?? false) return const MathToolHit(MathToolPart.add);
  if (l.previous?.contains(p) ?? false) return const MathToolHit(MathToolPart.previous);
  if (l.next?.contains(p) ?? false) return const MathToolHit(MathToolPart.next);
  switch (t.data) {
    case NumberLineData d:
      final line = _NumberLine(d, l.plot);
      // Ends and points first (they sit on the bar), nearest wins.
      MathToolHit? best;
      var bestD = 16.0;
      void consider(Offset at, MathToolHit hit) {
        final dist = (at - p).distance;
        if (dist < bestD) {
          bestD = dist;
          best = hit;
        }
      }
      for (final (i, s) in d.spans.indexed) {
        if (s.hidden) continue;
        final (a, b) = line.ends(s);
        if (numberValue(s.from)?.isFinite ?? false) consider(Offset(a, line.y), MathToolHit(MathToolPart.spanFrom, i));
        if (numberValue(s.to)?.isFinite ?? false) consider(Offset(b, line.y), MathToolHit(MathToolPart.spanTo, i));
      }
      for (final (i, pt) in d.points.indexed) {
        final x = line.xOf(numberValue(pt.value));
        if (x == null) continue;
        consider(Offset(x, line.y), MathToolHit(MathToolPart.item, i));
        // Its label, above.
        consider(Offset(x, line.y - 26), MathToolHit(MathToolPart.item, i));
      }
      if (best != null) return best;
      for (final (i, s) in d.spans.indexed) {
        if (s.hidden) continue;
        final (a, b) = line.ends(s);
        if (Rect.fromLTRB(a, line.y - 14, b, line.y + 14).contains(p)) return MathToolHit(MathToolPart.span, i);
      }
    case PolarData d:
      final grid = _PolarGrid(d, l.plot);
      for (final (i, curve) in d.curves.indexed) {
        if (curve.hidden) continue;
        final path = grid.path(curve);
        if (path == null) continue;
        for (final m in path.computeMetrics()) {
          for (var s = 0.0; s <= m.length; s += 4) {
            final at = m.getTangentForOffset(s)?.position;
            if (at != null && (at - p).distance <= 10) return MathToolHit(MathToolPart.item, i);
          }
        }
      }
    case UnitCircleData _:
      break;
  }
  return null;
}

/// The unit circle stepped on by [by] special angles.
MathToolItem unitCircleStepped(MathToolItem t, int by) {
  final d = t.data as UnitCircleData;
  return t.copyWith(data: UnitCircleData(step: (d.step + by) % 16, rest: d.rest));
}

// Layout, in the design's units.

class _ToolLayout {
  _ToolLayout(this.height, this.plot, {this.chips = const [], this.add, this.previous, this.next});

  final double height;

  /// Where the line, circle or grid is drawn.
  final Rect plot;
  final List<Rect> chips;
  final Rect? add, previous, next;
}

const _padX = 16.0, _padY = 12.0, _gap = 6.0, _chipH = 36.0;

final _layouts = Expando<_ToolLayout>('mathToolLayout');

_ToolLayout _layoutOf(MathToolItem t) => _layouts[t] ??= _layoutFor(t.data, t.w / t.unit);

/// Lays out [labels] as chips after the title, wrapping onto more rows.
(List<Rect>, Rect?, double) _chipRows(String title, List<double> widths, double? addWidth, double width) {
  final chips = <Rect>[];
  var x = _padX + _textWidth(title, 14, FontWeight.w700) + 8;
  var y = _padY;
  final right = width - _padX;
  // Chips sit at the right of the title row, as in the design: measure the
  // row and push it right.
  final all = [...widths, ?addWidth];
  final rows = <List<(int, double)>>[[]];
  var used = x;
  for (final (i, w) in all.indexed) {
    if (used + w > right && rows.last.isNotEmpty) {
      rows.add([]);
      used = _padX;
    }
    rows.last.add((i, w));
    used += w + 8;
  }
  Rect? add;
  for (final row in rows) {
    final rowWidth = row.fold(0.0, (s, e) => s + e.$2) + 8 * (row.length - 1);
    x = right - rowWidth;
    for (final (i, w) in row) {
      final r = Rect.fromLTWH(x, y, w, _chipH);
      if (addWidth != null && i == all.length - 1) {
        add = r;
      } else {
        chips.add(r);
      }
      x += w + 8;
    }
    y += _chipH + _gap;
  }
  return (chips, add, y - _gap);
}

_ToolLayout _layoutFor(MathToolData data, double width) {
  switch (data) {
    case NumberLineData d:
      final (chips, add, bottom) = _chipRows(
        'Number line',
        [for (final s in d.spans) _textWidth('interval ${intervalLabel(s)}', 15, FontWeight.w400, family: FontFamilies.serif) + 26],
        _textWidth('+ point', 13, FontWeight.w600) + 26,
        width,
      );
      final plot = Rect.fromLTWH(_padX, bottom + _gap, width - 2 * _padX, 92);
      return _ToolLayout(plot.bottom + _padY + 2, plot, chips: chips, add: add);
    case UnitCircleData _:
      // − θ = 90° = π/2 +, at the right; the angle as wide as the widest,
      // so the buttons stay put as it steps.
      final next = Rect.fromLTWH(width - _padX - 44, _padY, 44, 40);
      final previous = Rect.fromLTWH(next.left - 8 - _angleWidth - 8 - 44, _padY, 44, 40);
      return _ToolLayout(424, Rect.fromLTWH(_padX, _padY + 40 + _gap, width - 2 * _padX, 300), previous: previous, next: next);
    case PolarData d:
      final (chips, add, bottom) = _chipRows(
        'Polar grid',
        [for (final c in d.curves) _textWidth(_curveLabel(c.expr), 14, FontWeight.w400, family: FontFamilies.serif, italic: true) + 23],
        36,
        width,
      );
      final side = width - 2 * _padX;
      final plot = Rect.fromLTWH(_padX, bottom + _gap, side, side);
      return _ToolLayout(plot.bottom + _padY + 2, plot, chips: chips, add: add);
  }
}

/// The widest "θ = 330° = 11π/6" (at least MathKit.dc.html's 110).
final double _angleWidth = math_.max(110, [
  for (final (deg, rad, _, _, _) in specialAngles) _textWidth('θ = $deg° = $rad', 18, FontWeight.w400, family: FontFamilies.serif),
].reduce(math_.max));

String _curveLabel(String expr) => latexToLinear(expr);

// Painting.

void paintMathTool(Canvas canvas, MathToolItem t, Brightness brightness, EndlessColors c) {
  final l = _layoutOf(t);
  final size = Size(t.w / t.unit, t.h / t.unit);
  final card = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16));
  canvas
    ..save()
    ..scale(t.unit);
  // 0 12px 24px -18px shadow
  if (size.shortestSide > 40) {
    canvas.drawRRect(
      card.deflate(18).shift(const Offset(0, 12)),
      Paint()
        ..color = c.shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
  }
  canvas
    ..drawRRect(card, Paint()..color = c.surface)
    ..drawRRect(card.deflate(0.5), _stroke(c.line, 1))
    ..save()
    ..clipRRect(card);
  switch (t.data) {
    case NumberLineData d:
      _text(canvas, 'Number line', const Offset(_padX, _padY + _chipH / 2), 14, c.text, weight: FontWeight.w700, middle: true);
      _paintNumberLine(canvas, d, l, brightness, c);
    case UnitCircleData d:
      _text(canvas, 'Unit circle', const Offset(_padX, _padY + 20), 14, c.text, weight: FontWeight.w700, middle: true);
      _paintUnitCircle(canvas, d, l, c, size.width);
    case PolarData d:
      _text(canvas, 'Polar grid', const Offset(_padX, _padY + _chipH / 2), 14, c.text, weight: FontWeight.w700, middle: true);
      _paintPolar(canvas, d, l, brightness, c);
  }
  canvas
    ..restore()
    ..restore();
}

/// Where the number line's numbers go across [plot].
class _NumberLine {
  _NumberLine(NumberLineData d, this.plot) {
    var lo = -5.0, hi = 5.0;
    for (final v in [
      for (final p in d.points) numberValue(p.value),
      for (final s in d.spans) ...[numberValue(s.from), numberValue(s.to)],
    ]) {
      if (v == null || v.isInfinite) continue;
      lo = math_.min(lo, (v - 0.5).floorToDouble());
      hi = math_.max(hi, (v + 0.5).ceilToDouble());
    }
    min = lo;
    max = hi;
    step = _niceStep(hi - lo);
  }

  final Rect plot;
  late final double min, max, step;

  /// The line's height in the plot.
  double get y => plot.top + 43;

  /// The first and last tick: 25 in from the arrowheads.
  double get left => plot.left + 39;

  double get right => plot.right - 39;

  double x(double v) => left + (v - min) / (max - min) * (right - left);

  double? xOf(double? v) => v == null || v.isInfinite ? null : x(v);

  /// An interval's ends on screen; an infinite end runs to the arrow.
  (double, double) ends(NumberSpan s) {
    final a = numberValue(s.from), b = numberValue(s.to);
    return (
      a == null || a.isInfinite ? plot.left + 14 : x(a),
      b == null || b.isInfinite ? plot.right - 14 : x(b),
    );
  }
}

void _paintNumberLine(Canvas canvas, NumberLineData d, _ToolLayout l, Brightness brightness, EndlessColors c) {
  for (final (i, s) in d.spans.indexed) {
    final r = RRect.fromRectAndRadius(l.chips[i], const Radius.circular(999));
    if (!s.hidden) canvas.drawRRect(r, Paint()..color = c.greenTint);
    canvas.drawRRect(r.deflate(0.5), _stroke(s.hidden ? c.lineStrong : displayInk(s.color, brightness).withValues(alpha: 0.6), 1));
    _text(canvas, 'interval ${intervalLabel(s)}', l.chips[i].center, 15, c.text, family: FontFamilies.serif, center: true, middle: true);
  }
  if (l.add case final add?) {
    _dashed(canvas, RRect.fromRectAndRadius(add.deflate(0.5), const Radius.circular(999)), _stroke(c.lineDashed, 1));
    _text(canvas, '+ point', add.center, 13, c.text, weight: FontWeight.w600, center: true, middle: true);
  }

  final line = _NumberLine(d, l.plot);
  final y = line.y;
  final p = l.plot;
  for (final s in d.spans) {
    if (s.hidden) continue;
    final (a, b) = line.ends(s);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(a, y - 5, b, y + 5), const Radius.circular(5)),
      Paint()..color = displayInk(s.color, brightness).withValues(alpha: 0.3),
    );
  }
  final ink = _stroke(c.text, 2);
  canvas
    ..drawLine(Offset(p.left + 14, y), Offset(p.right - 14, y), ink)
    ..drawPath(
      Path()
        ..moveTo(p.right - 22, y - 7)
        ..lineTo(p.right - 13, y)
        ..lineTo(p.right - 22, y + 7)
        ..moveTo(p.left + 22, y - 7)
        ..lineTo(p.left + 13, y)
        ..lineTo(p.left + 22, y + 7),
      ink,
    );
  for (var v = (line.min / line.step).ceil() * line.step; v <= line.max + 1e-9; v += line.step) {
    final x = line.x(v);
    canvas.drawLine(Offset(x, y - 8), Offset(x, y + 8), Paint()
      ..color = c.text
      ..strokeWidth = v.abs() < 1e-9 ? 3 : 1.5);
    _text(canvas, _label(v), Offset(x, p.top + 72 - 6), 15, c.textMuted, family: FontFamilies.serif, center: true, middle: true);
  }
  void mark(double x, Color color, bool filled, String label) {
    canvas
      ..drawCircle(Offset(x, y), 7, Paint()..color = filled ? color : c.surface)
      ..drawCircle(Offset(x, y), 7, _stroke(color, 3));
    _text(canvas, label, Offset(x, p.top + 22 - 7), 16, color, family: FontFamilies.serif, italic: true, center: true, middle: true);
  }

  for (final s in d.spans) {
    if (s.hidden) continue;
    final color = displayInk(s.color, brightness);
    final (a, b) = line.ends(s);
    if (numberValue(s.from)?.isFinite ?? false) mark(a, color, !s.openFrom, numberLabel(s.from));
    if (numberValue(s.to)?.isFinite ?? false) mark(b, color, !s.openTo, numberLabel(s.to));
  }
  for (final pt in d.points) {
    final x = line.xOf(numberValue(pt.value));
    if (x != null) mark(x, displayInk(pt.color, brightness), true, numberLabel(pt.value));
  }
}

void _paintUnitCircle(Canvas canvas, UnitCircleData d, _ToolLayout l, EndlessColors c, double width) {
  final (deg, rad, cos, sin, tan) = specialAngles[d.step % 16];
  for (final (rect, label) in [(l.previous!, '−'), (l.next!, '+')]) {
    canvas.drawRRect(RRect.fromRectAndRadius(rect.deflate(0.5), const Radius.circular(10)), _stroke(c.lineStrong, 1));
    _text(canvas, label, rect.center, 16, c.text, center: true, middle: true);
  }
  final mid = (l.previous!.right + l.next!.left) / 2;
  _richText(canvas, [('θ', true), (' = $deg° = $rad', false)], Offset(mid, _padY + 20), 18, c.text);

  final o = l.plot.topLeft;
  final center = o + const Offset(183, 150);
  const r = 120.0;
  canvas
    ..drawPath(
      Path()
        ..moveTo(o.dx + 18, center.dy)
        ..lineTo(o.dx + 348, center.dy)
        ..moveTo(center.dx, o.dy + 12)
        ..lineTo(center.dx, o.dy + 288),
      _stroke(c.lineDashed, 1.5),
    )
    ..drawCircle(center, r, _stroke(c.text, 2));
  for (final a in specialAngles) {
    final t = a.$1 * math_.pi / 180;
    canvas.drawCircle(center + Offset(math_.cos(t), -math_.sin(t)) * r, 3, Paint()..color = c.textFaint);
  }
  final t = deg * math_.pi / 180;
  final point = center + Offset(math_.cos(t), -math_.sin(t)) * r;
  if (deg != 0) {
    canvas.drawArc(Rect.fromCircle(center: center, radius: 34), 0, -t, false, _stroke(c.plum, 2));
  }
  canvas
    ..drawLine(center, point, _stroke(c.text, 2.5))
    ..drawLine(center, Offset(point.dx, center.dy), _stroke(c.accent, 4))
    ..drawLine(Offset(point.dx, center.dy), point, _stroke(c.clay, 4))
    ..drawCircle(point, 7, Paint()..color = c.surface)
    ..drawCircle(point, 7, _stroke(c.text, 3));
  final lx = (center.dx + math_.cos(t) * (r + 4)).clamp(o.dx + 60, o.dx + 306).toDouble();
  final ly = center.dy - math_.sin(t) * (r + 4) + (math_.sin(t) >= -1e-9 ? -14 : 24) - 6;
  _text(canvas, '($cos, $sin)', Offset(lx, ly), 15, c.text, family: FontFamilies.serif, center: true, middle: true);
  _text(canvas, 'x', o + const Offset(352, 146 - 14), 14, c.textMuted, family: FontFamilies.serif, italic: true);
  _text(canvas, 'y', o + const Offset(194, 44 - 14), 14, c.textMuted, family: FontFamilies.serif, italic: true);

  // cos θ, sin θ and tan θ, exact.
  final top = l.plot.bottom + _gap;
  final cellW = (width - 2 * _padX - 12) / 3;
  for (final (i, (name, value, bg, fg)) in [
    ('cos', cos, c.accentTint, c.accentDeep),
    ('sin', sin, c.clayTint, c.clayDeep),
    ('tan', tan, c.side, c.text),
  ].indexed) {
    final cell = Rect.fromLTWH(_padX + i * (cellW + 6), top, cellW, 46);
    canvas.drawRRect(RRect.fromRectAndRadius(cell, const Radius.circular(8)), Paint()..color = bg);
    final oneLine = _textWidth('$name θ = $value', 16, FontWeight.w400, family: FontFamilies.serif) <= cell.width - 12;
    if (oneLine) {
      _richText(canvas, [('$name ', false), ('θ', true), (' = $value', false)], cell.center, 16, fg);
    } else {
      _richText(canvas, [('$name ', false), ('θ', true), (' =', false)], cell.center.translate(0, -9.5), 16, fg);
      _text(canvas, value, cell.center.translate(0, 9.5), 16, fg, family: FontFamilies.serif, center: true, middle: true);
    }
  }
}

/// The polar grid's rings, rays and curves.
class _PolarGrid {
  _PolarGrid(PolarData d, this.plot) {
    var most = 2.0;
    for (final curve in d.curves) {
      if (curve.hidden) continue;
      final f = polarCurve(curve.expr);
      if (f == null) continue;
      for (var i = 0; i <= 360; i += 3) {
        final r = f(i * math_.pi / 180).abs();
        if (r.isFinite) most = math_.max(most, r);
      }
    }
    // Two units to the outer ring, as in the design, unless a curve is bigger.
    units = most <= 2 ? 2 : most.ceilToDouble();
  }

  final Rect plot;
  late final double units;

  Offset get center => plot.center;

  double get outer => plot.width / 2 * 140 / 169;

  double get scale => outer / units;

  Path? path(GraphLine curve) {
    final f = polarCurve(curve.expr);
    if (f == null) return null;
    final path = Path();
    var pen = false;
    for (var i = 0; i <= 720; i += 3) {
      final th = i * math_.pi / 360;
      final r = f(th);
      if (!r.isFinite || r.abs() > units * 1.6) {
        pen = false;
        continue;
      }
      final p = center + Offset(r * math_.cos(th), -r * math_.sin(th)) * scale;
      if (pen) {
        path.lineTo(p.dx, p.dy);
      } else {
        path.moveTo(p.dx, p.dy);
        pen = true;
      }
    }
    return path;
  }
}

void _paintPolar(Canvas canvas, PolarData d, _ToolLayout l, Brightness brightness, EndlessColors c) {
  for (final (i, curve) in d.curves.indexed) {
    final r = RRect.fromRectAndRadius(l.chips[i], const Radius.circular(999));
    final color = displayInk(curve.color, brightness);
    canvas
      ..drawRRect(r, Paint()..color = curve.hidden ? c.menuTile : c.surface)
      ..drawRRect(r.deflate(0.75), _stroke(color, 1.5));
    _text(canvas, _curveLabel(curve.expr), l.chips[i].center, 14, c.text, family: FontFamilies.serif, italic: true, center: true, middle: true);
  }
  if (l.add case final add?) {
    _dashed(canvas, RRect.fromRectAndRadius(add.deflate(0.5), const Radius.circular(999)), _stroke(c.lineDashed, 1));
    _text(canvas, '+', add.center, 18, c.text, weight: FontWeight.w600, center: true, middle: true);
  }
  final grid = _PolarGrid(d, l.plot);
  final o = grid.center;
  final ring = _stroke(c.cardLine, 1);
  for (var k = 1; k <= 4; k++) {
    canvas.drawCircle(o, grid.outer * k / 4, ring);
  }
  for (var deg = 0; deg < 360; deg += 30) {
    final t = deg * math_.pi / 180;
    final dir = Offset(math_.cos(t), -math_.sin(t));
    canvas.drawLine(o, o + dir * grid.outer, ring);
    _text(canvas, '$deg°', o + dir * (grid.outer + 16), 10, c.textFaint, center: true, middle: true);
  }
  for (final curve in d.curves) {
    if (curve.hidden) continue;
    final path = grid.path(curve);
    if (path != null) canvas.drawPath(path, _stroke(displayInk(curve.color, brightness), 3));
  }
}

// Helpers.

Paint _stroke(Color color, double width) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..color = color;

void _dashed(Canvas canvas, RRect shape, Paint paint, {double dash = 5, double gap = 4}) {
  final out = Path();
  for (final PathMetric m in (Path()..addRRect(shape)).computeMetrics()) {
    for (var d = 0.0; d < m.length; d += dash + gap) {
      out.addPath(m.extractPath(d, math_.min(d + dash, m.length)), Offset.zero);
    }
  }
  canvas.drawPath(out, paint);
}

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

TextStyle _style(double size, Color color, {FontWeight weight = FontWeight.w400, String family = FontFamilies.ui, bool italic = false}) =>
    TextStyle(
      fontFamily: family,
      fontFamilyFallback: mathFontFallback,
      fontSize: size,
      fontWeight: weight,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      color: color,
    );

double _textWidth(String s, double size, FontWeight weight, {String family = FontFamilies.ui, bool italic = false}) {
  final p = TextPainter(text: TextSpan(text: s, style: _style(size, const Color(0xFF000000), weight: weight, family: family, italic: italic)), textDirection: TextDirection.ltr)
    ..layout();
  final w = p.width;
  p.dispose();
  return w;
}

void _text(
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
}) {
  final p = TextPainter(text: TextSpan(text: s, style: _style(size, color, weight: weight, family: family, italic: italic)), textDirection: TextDirection.ltr)
    ..layout();
  p.paint(canvas, Offset(center ? at.dx - p.width / 2 : at.dx, middle ? at.dy - p.height / 2 : at.dy));
  p.dispose();
}

/// Serif runs, some italic, centered on [at].
void _richText(Canvas canvas, List<(String, bool)> runs, Offset at, double size, Color color) {
  final p = TextPainter(
    text: TextSpan(children: [
      for (final (s, italic) in runs) TextSpan(text: s, style: _style(size, color, family: FontFamilies.serif, italic: italic)),
    ]),
    textDirection: TextDirection.ltr,
  )..layout();
  p.paint(canvas, at - Offset(p.width / 2, p.height / 2));
  p.dispose();
}

/// What a tool says, for search and a PDF's text layer.
String mathToolText(MathToolData data) => switch (data) {
      NumberLineData d => [
          'Number line',
          for (final p in d.points) numberLabel(p.value),
          for (final s in d.spans) intervalLabel(s),
        ].join(' '),
      UnitCircleData d => () {
          final (deg, rad, cos, sin, tan) = specialAngles[d.step % 16];
          return 'Unit circle θ = $deg° = $rad cos θ = $cos sin θ = $sin tan θ = $tan';
        }(),
      PolarData d => ['Polar grid', for (final c in d.curves) latexToLinear(c.expr)].join(' '),
    };
