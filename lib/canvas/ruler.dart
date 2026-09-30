import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/colors.dart';
import 'canvas_view.dart';

/// What the ruler measures in. Lengths are page lengths: an inch is 160
/// page px (Android's dp), so at 100% the ruler matches a real one.
enum RulerUnit { cm, mm, inch }

extension RulerUnitText on RulerUnit {
  String get label => switch (this) {
        RulerUnit.cm => 'cm',
        RulerUnit.mm => 'mm',
        RulerUnit.inch => 'in',
      };

  /// Page px per centimeter or inch (mm ticks use the centimeter).
  double get pxPerMajor => this == RulerUnit.inch ? 160 : 160 / 2.54;

  /// [px] page px as "4.2 cm", "42 mm" or "1.65 in".
  String format(double px) => switch (this) {
        RulerUnit.cm => '${(px / pxPerMajor).toStringAsFixed(1)} cm',
        RulerUnit.mm => '${(px / pxPerMajor * 10).round()} mm',
        RulerUnit.inch => '${(px / pxPerMajor).toStringAsFixed(2)} in',
      };
}

/// Degrees with up to three decimals and no trailing zeros ("22.5°").
String formatDegrees(double deg) {
  var s = deg.toStringAsFixed(3);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  if (s == '-0') s = '0';
  return '${s.replaceFirst('-', '−')}°';
}

/// One long edge of the ruler: a line through [origin] along [dir], with
/// [normal] pointing away from the ruler.
class RulerEdge {
  const RulerEdge(this.origin, this.dir, this.normal);

  final Offset origin;
  final Offset dir;
  final Offset normal;

  /// [p] moved onto the edge, [gap] px outside it.
  Offset snap(Offset p, double gap) {
    final d = p - origin;
    return origin + dir * (d.dx * dir.dx + d.dy * dir.dy) + normal * gap;
  }
}

/// The on-screen ruler (Tools.dc.html): 72 px tall, 620 long to start. It
/// lives in screen space so it stays put while the page pans. Fingers move,
/// turn and (pinching along it) lengthen it; the pen snaps to whichever
/// long edge it starts near; tapping the angle chip sets an exact angle.
class Ruler extends ChangeNotifier {
  static const thickness = 72.0;
  static const minLength = 240.0;
  static const maxLength = 2400.0;

  /// The pen snaps when it starts this close (screen px) outside an edge.
  static const reach = 28.0;

  bool _visible = false;
  Offset _center = Offset.zero;
  double _length = 620;
  double _fingerAngle = 0;
  double _angle = 0;
  double? _measure;

  bool get visible => _visible;
  Offset get center => _center;
  double get length => _length;

  /// Rotation in radians (screen convention: positive turns clockwise).
  double get angle => _angle;

  /// The angle shown: degrees counter-clockwise from level, −180 to 180.
  double get degrees {
    var d = -_angle * 180 / math.pi;
    d = (d + 180) % 360 - 180;
    return d <= -180 ? d + 360 : d;
  }

  /// Length (page px) of the line being drawn along the ruler, or null.
  double? get measure => _measure;
  set measure(double? v) {
    if (v == _measure) return;
    _measure = v;
    notifyListeners();
  }

  Offset get _u => Offset(math.cos(_angle), math.sin(_angle));
  Offset get _v => Offset(-math.sin(_angle), math.cos(_angle));

  /// Shows the ruler level, across the lower middle of a [view]-sized canvas.
  void show(Size view) {
    _visible = true;
    _center = Offset(view.width / 2, view.height * 0.62);
    _fingerAngle = _angle = 0;
    _measure = null;
    notifyListeners();
  }

  void hide() {
    if (!_visible) return;
    _visible = false;
    notifyListeners();
  }

  void moveBy(Offset delta) {
    _center += delta;
    _measure = null;
    notifyListeners();
  }

  /// Turns by [radians] about [focal] (screen), as fingers do: the angle
  /// settles on whole degrees, and on multiples of 45° within 2°.
  void rotateAbout(Offset focal, double radians) {
    _fingerAngle += radians;
    var deg = _fingerAngle * 180 / math.pi;
    final nearest = (deg / 45).round() * 45.0;
    deg = (deg - nearest).abs() < 2 ? nearest : deg.roundToDouble();
    _turnTo(deg * math.pi / 180, focal);
  }

  /// Sets the angle exactly: [deg] counter-clockwise from level.
  void setDegrees(double deg) {
    final a = -deg * math.pi / 180;
    _turnTo(a, _center);
    _fingerAngle = a;
  }

  void _turnTo(double a, Offset focal) {
    final delta = a - _angle;
    final d = _center - focal;
    final c = math.cos(delta), s = math.sin(delta);
    _center = focal + Offset(c * d.dx - s * d.dy, s * d.dx + c * d.dy);
    _angle = a;
    _measure = null;
    notifyListeners();
  }

  /// Lengthens (or shortens) it by [factor], about its center.
  void resizeBy(double factor) {
    _length = (_length * factor).clamp(minLength, maxLength);
    _measure = null;
    notifyListeners();
  }

  (double, double) _local(Offset p) {
    final d = p - _center;
    return (d.dx * _u.dx + d.dy * _u.dy, d.dx * _v.dx + d.dy * _v.dy);
  }

  bool contains(Offset p) {
    if (!_visible) return false;
    final (pu, pv) = _local(p);
    return pu.abs() <= _length / 2 && pv.abs() <= thickness / 2;
  }

  /// Whether [p] is on the angle chip (a 120 × 44 target around it).
  bool chipContains(Offset p) {
    if (!_visible) return false;
    final (pu, pv) = _local(p);
    return pu.abs() <= 60 && (pv - chipCenter.dy).abs() <= 22;
  }

  /// The chip's center in the ruler's own coordinates.
  static const chipCenter = Offset(0, 12);

  /// The edge the pen snaps to when it lands at [p], or null.
  RulerEdge? edgeNear(Offset p) {
    if (!_visible) return null;
    final (pu, pv) = _local(p);
    if (pu.abs() > _length / 2 + reach || pv.abs() > thickness / 2 + reach) return null;
    final top = pv < 0;
    final normal = top ? -_v : _v;
    return RulerEdge(_center + normal * (thickness / 2), _u, normal);
  }
}

/// Draws the ruler: a translucent strip with unit ticks along its top edge
/// (they follow the page's zoom), numbers under the whole units, and the
/// angle (and, while drawing along it, the line's length) in a dark chip.
class RulerPainter extends CustomPainter {
  RulerPainter(this.ruler, this.vp, this.unit, this.colors) : super(repaint: Listenable.merge([ruler, vp]));

  final Ruler ruler;
  final CanvasView vp;
  final RulerUnit unit;
  final EndlessColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (!ruler.visible) return;
    canvas
      ..save()
      ..translate(ruler.center.dx, ruler.center.dy)
      ..rotate(ruler.angle);
    final rect = Rect.fromCenter(center: Offset.zero, width: ruler.length, height: Ruler.thickness);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    // box-shadow: 0 12px 24px -14px shadow. Like CSS, only outside the
    // ruler: the face is see-through.
    canvas
      ..save()
      ..clipPath(Path.combine(
        PathOperation.difference,
        Path()..addRect(rect.inflate(60)),
        Path()..addRRect(rrect),
      ))
      ..drawRRect(
        rrect.shift(const Offset(0, 12)).deflate(14),
        Paint()
          ..color = colors.shadow
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      )
      ..restore();
    canvas.drawRRect(rrect, Paint()..color = colors.surface.withValues(alpha: 0.82));
    canvas
      ..save()
      ..clipRRect(rrect);
    _ticks(canvas, rect);
    canvas.restore();
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = colors.text.withValues(alpha: 0.35),
    );

    final measure = ruler.measure;
    final text = measure == null ? formatDegrees(ruler.degrees) : '${formatDegrees(ruler.degrees)} · ${unit.format(measure)}';
    final label = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontFamily: 'Figtree', fontSize: 14, fontWeight: FontWeight.w600, color: colors.onInverse),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final chip = Rect.fromCenter(center: Ruler.chipCenter, width: label.width + 20, height: label.height + 8);
    canvas.drawRRect(RRect.fromRectAndRadius(chip, const Radius.circular(999)), Paint()..color = colors.inverse);
    label.paint(canvas, chip.topLeft + const Offset(10, 4));
    canvas.restore();
  }

  /// Ticks from a zero 12 px in from the left end. Each level is drawn only
  /// while its ticks stay at least 5 px apart; numbers need 28 px.
  void _ticks(Canvas canvas, Rect rect) {
    // Tick levels as (fraction of the major unit, tick height).
    final levels = unit == RulerUnit.inch
        ? const [(16, 22.0), (8, 17.0), (4, 13.0), (2, 10.0), (1, 7.0)] // in sixteenths
        : const [(10, 22.0), (5, 17.0), (1, 12.0)]; // in millimeters
    final per = levels.first.$1; // finest ticks per major unit
    final major = unit.pxPerMajor * vp.scale;
    final fine = major / per;
    var finest = per; // zoomed far out: whole units only
    for (final (n, _) in levels.reversed) {
      if (fine * n >= 5) {
        finest = n;
        break;
      }
    }
    var labelEvery = 1;
    while (major * labelEvery < 28) {
      labelEvery *= 2;
    }
    final paint = Paint()..color = colors.text;
    final x0 = rect.left + 12;
    final count = ((rect.right - 4 - x0) / fine).floor();
    for (var k = 0; k <= count; k += finest) {
      final level = levels.firstWhere((l) => k % l.$1 == 0);
      final majorTick = k % per == 0;
      final x = x0 + k * fine;
      canvas.drawRect(Rect.fromLTWH(x, rect.top, majorTick ? 1.5 : 1, level.$2), paint);
      final n = k ~/ per;
      if (majorTick && n % labelEvery == 0) {
        final number = TextPainter(
          text: TextSpan(
            text: '${unit == RulerUnit.mm ? n * 10 : n}',
            style: TextStyle(fontFamily: 'Figtree', fontSize: 10, color: colors.textMuted),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        number.paint(canvas, Offset(x - number.width / 2, rect.top + 24));
      }
    }
  }

  @override
  bool shouldRepaint(RulerPainter old) =>
      old.ruler != ruler || old.colors != colors || old.unit != unit || old.vp != vp;
}
