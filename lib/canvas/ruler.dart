import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/colors.dart';

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

/// The on-screen ruler (Tools.dc.html): 620 × 72, lives in screen space so
/// it stays put while the page pans. Two fingers move and rotate it; the pen
/// snaps to whichever long edge it starts near.
class Ruler extends ChangeNotifier {
  static const length = 620.0;
  static const thickness = 72.0;

  /// The pen snaps when it starts this close (screen px) outside an edge.
  static const reach = 28.0;

  bool _visible = false;
  Offset _center = Offset.zero;
  double _rawAngle = 0;

  bool get visible => _visible;
  Offset get center => _center;

  /// Rotation in radians, settling on multiples of 45° within 2°.
  double get angle {
    const step = math.pi / 4;
    final nearest = (_rawAngle / step).round() * step;
    return (_rawAngle - nearest).abs() < 2 * math.pi / 180 ? nearest : _rawAngle;
  }

  /// The angle label: degrees from level, 0–90.
  int get degrees {
    var d = (-angle * 180 / math.pi) % 180;
    if (d < 0) d += 180;
    return (d > 90 ? 180 - d : d).round();
  }

  Offset get _u => Offset(math.cos(angle), math.sin(angle));
  Offset get _v => Offset(-math.sin(angle), math.cos(angle));

  /// Shows the ruler level, across the lower middle of a [view]-sized canvas.
  void show(Size view) {
    _visible = true;
    _center = Offset(view.width / 2, view.height * 0.62);
    _rawAngle = 0;
    notifyListeners();
  }

  void hide() {
    if (!_visible) return;
    _visible = false;
    notifyListeners();
  }

  void moveBy(Offset delta) {
    _center += delta;
    notifyListeners();
  }

  /// Rotates by [radians] about [focal] (screen).
  void rotateAbout(Offset focal, double radians) {
    final d = _center - focal;
    final c = math.cos(radians), s = math.sin(radians);
    _center = focal + Offset(c * d.dx - s * d.dy, s * d.dx + c * d.dy);
    _rawAngle += radians;
    notifyListeners();
  }

  (double, double) _local(Offset p) {
    final d = p - _center;
    return (d.dx * _u.dx + d.dy * _u.dy, d.dx * _v.dx + d.dy * _v.dy);
  }

  bool contains(Offset p) {
    if (!_visible) return false;
    final (pu, pv) = _local(p);
    return pu.abs() <= length / 2 && pv.abs() <= thickness / 2;
  }

  /// The edge the pen snaps to when it lands at [p], or null.
  RulerEdge? edgeNear(Offset p) {
    if (!_visible) return null;
    final (pu, pv) = _local(p);
    if (pu.abs() > length / 2 + reach || pv.abs() > thickness / 2 + reach) return null;
    final top = pv < 0;
    final normal = top ? -_v : _v;
    return RulerEdge(_center + normal * (thickness / 2), _u, normal);
  }
}

/// Draws the ruler: a translucent strip with ticks every 10 px (every 50 px
/// longer) and its angle in a dark chip.
class RulerPainter extends CustomPainter {
  RulerPainter(this.ruler, this.colors) : super(repaint: ruler);

  final Ruler ruler;
  final EndlessColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (!ruler.visible) return;
    canvas
      ..save()
      ..translate(ruler.center.dx, ruler.center.dy)
      ..rotate(ruler.angle);
    final rect = Rect.fromCenter(center: Offset.zero, width: Ruler.length, height: Ruler.thickness);
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
    final tick = Paint()..color = colors.text;
    for (var x = 0.0; x <= Ruler.length; x += 10) {
      final major = x % 50 == 0;
      canvas.drawRect(
        Rect.fromLTWH(rect.left + x, rect.top, major ? 1.5 : 1, major ? 22 : 12),
        tick,
      );
    }
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = colors.text.withValues(alpha: 0.35),
    );

    final label = TextPainter(
      text: TextSpan(
        text: '${ruler.degrees}°',
        style: TextStyle(fontFamily: 'Figtree', fontSize: 14, fontWeight: FontWeight.w600, color: colors.onInverse),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final chip = Rect.fromCenter(
      center: const Offset(0, 8),
      width: label.width + 20,
      height: label.height + 8,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(chip, const Radius.circular(999)), Paint()..color = colors.inverse);
    label.paint(canvas, chip.topLeft + const Offset(10, 4));
    canvas.restore();
  }

  @override
  bool shouldRepaint(RulerPainter old) => old.ruler != ruler || old.colors != colors;
}
