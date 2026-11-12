# Hold to straighten

Draw a line (or a circle, rectangle or triangle) and keep the pen still at the end. After 150 ms a dashed preview and a filling ring appear, and at 500 ms the stroke snaps to the shape. With a line, keep the pen down and move it: the far end follows, so you can change the angle and length. It snaps to 0°, 45° and 90° when it's close, and the angle is shown next to it. Undo brings back the ink as you drew it.

This is a copy for reading. The code lives in the Endless app (Flutter/Dart). Whole files are copied as they are. From the big canvas file (`lib/canvas/ink_canvas.dart`) only the parts this feature uses are copied, with their line numbers, so some of them start or end partway through a method.

## Recognising the shape

### `lib/canvas/gestures.dart`, lines 1–387

Shared geometry, then fitting a line, circle, oval, rectangle or triangle to a stroke, and snapping a line to 0°, 45° or 90°.

```dart
import 'dart:math' as math;
import 'dart:ui';

import '../board/model.dart';
import 'stroke_geometry.dart';

// Pen gesture recognizers (docs/SPEC.md Phase 3): hold to straighten, flick
// back for an arrow, and scribble to erase. They are pure functions over
// page-space points. `unit` is page px per screen px (1 / zoom), so every
// threshold follows the hand on the glass rather than the zoom level.

// Shared geometry.

double pathLength(List<Offset> pts) {
  var len = 0.0;
  for (var i = 1; i < pts.length; i++) {
    len += (pts[i] - pts[i - 1]).distance;
  }
  return len;
}

/// Cumulative arc length at each point.
List<double> arcLengths(List<Offset> pts) {
  final out = List<double>.filled(pts.length, 0);
  for (var i = 1; i < pts.length; i++) {
    out[i] = out[i - 1] + (pts[i] - pts[i - 1]).distance;
  }
  return out;
}

/// Points spaced [spacing] apart along the path (the ends are kept).
List<Offset> resample(List<Offset> pts, double spacing, {bool closed = false}) {
  if (pts.length < 2) return [...pts];
  final path = closed ? [...pts, pts.first] : pts;
  final out = <Offset>[path.first];
  var carry = 0.0;
  for (var i = 1; i < path.length; i++) {
    var a = path[i - 1];
    final b = path[i];
    var seg = (b - a).distance;
    while (carry + seg >= spacing) {
      final t = (spacing - carry) / seg;
      a = Offset.lerp(a, b, t)!;
      out.add(a);
      seg = (b - a).distance;
      carry = 0;
    }
    carry += seg;
  }
  if (!closed && (out.last - path.last).distance > spacing * 0.25) out.add(path.last);
  if (closed && out.length > 1 && (out.last - out.first).distance < spacing * 0.5) out.removeLast();
  return out;
}

/// Angle in degrees (0–180) between two directions.
double angleBetween(Offset a, Offset b) {
  final la = a.distance, lb = b.distance;
  if (la == 0 || lb == 0) return 0;
  final cos = ((a.dx * b.dx + a.dy * b.dy) / (la * lb)).clamp(-1.0, 1.0);
  return math.acos(cos) * 180 / math.pi;
}

double _pointLine(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len = ab.distance;
  if (len == 0) return (p - a).distance;
  return ((p - a).dx * ab.dy - (p - a).dy * ab.dx).abs() / len;
}

/// Principal axes of a point cloud: (center, angle of the major axis in radians).
(Offset, double) principalAxis(List<Offset> pts) {
  var cx = 0.0, cy = 0.0;
  for (final p in pts) {
    cx += p.dx;
    cy += p.dy;
  }
  cx /= pts.length;
  cy /= pts.length;
  var sxx = 0.0, syy = 0.0, sxy = 0.0;
  for (final p in pts) {
    final dx = p.dx - cx, dy = p.dy - cy;
    sxx += dx * dx;
    syy += dy * dy;
    sxy += dx * dy;
  }
  return (Offset(cx, cy), 0.5 * math.atan2(2 * sxy, sxx - syy));
}

/// A box aligned to [angle]: points are measured along `u` (the angle) and `v`.
class OrientedBox {
  OrientedBox(this.center, this.angle, this.halfU, this.halfV);

  /// Tightest box at [angle] around [pts].
  factory OrientedBox.around(List<Offset> pts, double angle) {
    final u = Offset(math.cos(angle), math.sin(angle));
    final v = Offset(-u.dy, u.dx);
    var minU = double.infinity, maxU = -double.infinity, minV = double.infinity, maxV = -double.infinity;
    for (final p in pts) {
      final pu = p.dx * u.dx + p.dy * u.dy, pv = p.dx * v.dx + p.dy * v.dy;
      minU = math.min(minU, pu);
      maxU = math.max(maxU, pu);
      minV = math.min(minV, pv);
      maxV = math.max(maxV, pv);
    }
    final cu = (minU + maxU) / 2, cv = (minV + maxV) / 2;
    return OrientedBox(u * cu + v * cv, angle, (maxU - minU) / 2, (maxV - minV) / 2);
  }

  final Offset center;
  final double angle;
  final double halfU;
  final double halfV;

  // Worked out once: [contains] asks for them for every point of every
  // stroke under a scribble.
  late final Offset u = Offset(math.cos(angle), math.sin(angle));
  late final Offset v = Offset(-u.dy, u.dx);

  double get diagonal => 2 * math.sqrt(halfU * halfU + halfV * halfV);

  OrientedBox inflate(double by) => OrientedBox(center, angle, halfU + by, halfV + by);

  bool contains(Offset p) {
    final d = p - center;
    return (d.dx * u.dx + d.dy * u.dy).abs() <= halfU && (d.dx * v.dx + d.dy * v.dy).abs() <= halfV;
  }

  List<Offset> get corners => [
        center - u * halfU - v * halfV,
        center + u * halfU - v * halfV,
        center + u * halfU + v * halfV,
        center - u * halfU + v * halfV,
      ];
}

// Hold to straighten.

enum ShapeKind { line, circle, ellipse, rect, triangle }

/// A recognized shape, ready to replace the freehand stroke.
class ShapeFit {
  const ShapeFit(this.kind, this.points, {this.angle});

  final ShapeKind kind;

  /// The shape as a polyline in page space (closed shapes end where they start).
  final List<Offset> points;

  /// For a line: its angle to the horizontal in whole degrees (0–90).
  final int? angle;
}

/// How far from horizontal a line from [a] to [b] is, in degrees (0–90).
double lineAngle(Offset a, Offset b) {
  var deg = math.atan2(-(b.dy - a.dy), b.dx - a.dx) * 180 / math.pi;
  deg = deg % 180;
  if (deg < 0) deg += 180;
  return deg > 90 ? 180 - deg : deg;
}

/// Rotates the end of a line onto 0°, 45° or 90° when it is within [snapDeg].
Offset snapLineEnd(Offset a, Offset b, {double snapDeg = 3}) {
  final d = b - a;
  final len = d.distance;
  if (len == 0) return b;
  final deg = math.atan2(d.dy, d.dx) * 180 / math.pi;
  final nearest = (deg / 45).round() * 45.0;
  if ((deg - nearest).abs() > snapDeg) return b;
  final r = nearest * math.pi / 180;
  return a + Offset(math.cos(r), math.sin(r)) * len;
}

List<Offset> _polyline(List<Offset> corners, double spacing, {bool closed = false}) {
  final out = <Offset>[];
  final n = closed ? corners.length : corners.length - 1;
  for (var i = 0; i < n; i++) {
    final a = corners[i], b = corners[(i + 1) % corners.length];
    final steps = math.max(1, ((b - a).distance / spacing).ceil());
    for (var s = 0; s < steps; s++) {
      out.add(Offset.lerp(a, b, s / steps)!);
    }
  }
  out.add(closed ? corners.first : corners.last);
  return out;
}

/// The points of a straight line from [a] to [b].
List<Offset> linePoints(Offset a, Offset b, {double spacing = 6}) => _polyline([a, b], spacing);

/// Ink points for a straightened shape: the stroke's typical pressure all
/// the way along, spread over the time it took to draw.
List<InkPoint> shapeInk(List<Offset> shape, List<double> pressures, int durationMs) {
  final sorted = [...pressures]..sort();
  final p = sorted.isEmpty ? 0.5 : sorted[sorted.length ~/ 2];
  final n = shape.length;
  return [
    for (var i = 0; i < n; i++) InkPoint(shape[i].dx, shape[i].dy, p, n < 2 ? 0 : (durationMs * i / (n - 1)).round()),
  ];
}

List<Offset> _ellipsePoints(Offset c, double rx, double ry, double angle, double spacing) {
  final perimeter = math.pi * (3 * (rx + ry) - math.sqrt((3 * rx + ry) * (rx + 3 * ry)));
  final n = math.max(24, (perimeter / spacing).ceil());
  final u = Offset(math.cos(angle), math.sin(angle)), v = Offset(-u.dy, u.dx);
  return [
    for (var i = 0; i <= n; i++)
      c + u * (rx * math.cos(i / n * 2 * math.pi)) + v * (ry * math.sin(i / n * 2 * math.pi)),
  ];
}

/// Snaps an angle (radians) to the nearest multiple of 90° when within [deg].
double _snapAxis(double angle, double deg) {
  final quarter = math.pi / 2;
  final nearest = (angle / quarter).round() * quarter;
  return (angle - nearest).abs() <= deg * math.pi / 180 ? nearest : angle;
}

/// Recognizes a line, circle, ellipse, rectangle or triangle in a freehand
/// stroke, or returns null when it is none of them.
ShapeFit? fitShape(List<Offset> raw, {double unit = 1}) {
  if (raw.length < 2) return null;
  final pts = resample(raw, 2 * unit);
  final length = pathLength(pts);
  if (length < 24 * unit || pts.length < 3) return null;
  final first = pts.first, last = pts.last;
  final chord = (last - first).distance;

  // A line: nearly as long as its path and never far from its chord.
  var maxDev = 0.0;
  for (final p in pts) {
    maxDev = math.max(maxDev, _pointLine(p, first, last));
  }
  if (chord / length > 0.88 && maxDev < math.max(0.1 * chord, 6 * unit)) {
    final end = snapLineEnd(first, last);
    return ShapeFit(ShapeKind.line, linePoints(first, end), angle: lineAngle(first, end).round());
  }

  // Everything else must close on itself.
  final bounds = _bounds(pts);
  final diag = math.sqrt(bounds.width * bounds.width + bounds.height * bounds.height);
  final loop = _closeLoop(pts, diag);
  if (loop == null) return null;

  final perimeter = pathLength([...loop, loop.first]);
  const n = 72;
  final ring = resample(loop, perimeter / n, closed: true);
  final corners = _corners(ring);

  if (corners.length == 3) {
    final tri = [for (final i in corners) ring[i]];
    if (_polygonArea(tri).abs() > 0.08 * diag * diag) {
      return ShapeFit(ShapeKind.triangle, _polyline(tri, 6, closed: true));
    }
  }
  if (corners.length == 4) {
    final quad = [for (final i in corners) ring[i]];
    return ShapeFit(ShapeKind.rect, _polyline(_fitRect(quad), 6, closed: true));
  }
  return _fitEllipse(ring);
}

Rect _bounds(List<Offset> pts) {
  var r = Rect.fromLTRB(pts.first.dx, pts.first.dy, pts.first.dx, pts.first.dy);
  for (final p in pts) {
    r = r.expandToInclude(Rect.fromLTRB(p.dx, p.dy, p.dx, p.dy));
  }
  return r;
}

/// Trims an overshoot past the starting point and returns the loop, or null
/// when the ends are too far apart for a closed shape.
List<Offset>? _closeLoop(List<Offset> pts, double diag) {
  // The point in the last third that comes closest to the start.
  var best = pts.length - 1;
  var bestD = (pts.last - pts.first).distance;
  for (var i = (pts.length * 2 / 3).floor(); i < pts.length; i++) {
    final d = (pts[i] - pts.first).distance;
    if (d < bestD) {
      bestD = d;
      best = i;
    }
  }
  if (bestD > 0.3 * diag) return null;
  final loop = pts.sublist(0, best + 1);
  // What comes after it must be an overshoot, not a letter's stem.
  if (best < pts.length - 2 && !_overshoot(loop, pts.sublist(best))) return null;
  return loop;
}

/// Whether [tail], drawn after [loop] closed, is an overshoot: it goes on
/// round the same way, about as far from the middle. The stem of an a, d,
/// g or q turns back down the side the loop just came up, or reaches out
/// of it, so a written "a" doesn't become a circle.
bool _overshoot(List<Offset> loop, List<Offset> tail) {
  var c = Offset.zero;
  for (final p in loop) {
    c += p;
  }
  c /= loop.length.toDouble();
  final radius = loop.map((p) => (p - c).distance).reduce(math.max);
  if (tail.any((p) => (p - c).distance > 1.2 * radius)) return false;
  double sweep(List<Offset> pts) {
    var s = 0.0;
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1] - c, b = pts[i] - c;
      s += math.atan2(a.dx * b.dy - a.dy * b.dx, a.dx * b.dx + a.dy * b.dy);
    }
    return s;
  }

  final round = sweep(loop), more = sweep(tail);
  // A small hook at the end is fine; turning back by more than ~20° isn't.
  return more.abs() <= 0.35 || more.sign == round.sign;
}

/// Indexes of sharp corners on a closed, evenly sampled ring.
List<int> _corners(List<Offset> ring) {
  final n = ring.length;
  const k = 3;
  if (n < 4 * k) return const [];
  final turn = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    turn[i] = angleBetween(ring[i] - ring[(i - k + n) % n], ring[(i + k) % n] - ring[i]);
  }
  final out = <int>[];
  for (var i = 0; i < n; i++) {
    if (turn[i] < 55) continue;
    // A peak: higher than its neighbors (the first of a plateau wins).
    var isPeak = true;
    for (var j = 1; j <= k && isPeak; j++) {
      isPeak = turn[(i - j + n) % n] < turn[i] && turn[(i + j) % n] <= turn[i];
    }
    if (isPeak) out.add(i);
  }
  return out;
}

double _polygonArea(List<Offset> pts) {
  var a = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final p = pts[i], q = pts[(i + 1) % pts.length];
    a += p.dx * q.dy - q.dx * p.dy;
  }
  return a / 2;
}

/// The rectangle closest to a hand-drawn quadrilateral, squared up to the
/// page when it is within a few degrees of level.
List<Offset> _fitRect(List<Offset> quad) {
  // Average edge direction, modulo 90° (edges weighted by length).
  var sx = 0.0, sy = 0.0;
  for (var i = 0; i < 4; i++) {
    final e = quad[(i + 1) % 4] - quad[i];
    final a = math.atan2(e.dy, e.dx) * 4;
    sx += math.cos(a) * e.distance;
    sy += math.sin(a) * e.distance;
  }
  final angle = _snapAxis(math.atan2(sy, sx) / 4, 6);
  final u = Offset(math.cos(angle), math.sin(angle)), v = Offset(-u.dy, u.dx);
  final us = [for (final p in quad) p.dx * u.dx + p.dy * u.dy]..sort();
  final vs = [for (final p in quad) p.dx * v.dx + p.dy * v.dy]..sort();
  final u0 = (us[0] + us[1]) / 2, u1 = (us[2] + us[3]) / 2;
  final v0 = (vs[0] + vs[1]) / 2, v1 = (vs[2] + vs[3]) / 2;
  Offset at(double pu, double pv) => u * pu + v * pv;
  return [at(u0, v0), at(u1, v0), at(u1, v1), at(u0, v1)];
}

ShapeFit? _fitEllipse(List<Offset> ring) {
  final (_, rawAngle) = principalAxis(ring);
  final angle = _snapAxis(rawAngle, 8);
  final box = OrientedBox.around(ring, angle);
  final a = box.halfU, b = box.halfV;
  if (a < 4 || b < 4) return null;
  var err = 0.0;
  for (final p in ring) {
    final d = p - box.center;
    final pu = (d.dx * box.u.dx + d.dy * box.u.dy) / a, pv = (d.dx * box.v.dx + d.dy * box.v.dy) / b;
    err += (math.sqrt(pu * pu + pv * pv) - 1).abs();
  }
  if (err / ring.length > 0.13) return null;
  final ratio = math.min(a, b) / math.max(a, b);
  if (ratio > 0.82) {
    final r = (a + b) / 2;
    return ShapeFit(ShapeKind.circle, _ellipsePoints(box.center, r, r, -math.pi / 2, 6));
  }
  return ShapeFit(ShapeKind.ellipse, _ellipsePoints(box.center, a, b, angle, 6));
}
```

## Timing the hold, the snap, and moving the line's end

### `lib/canvas/ink_canvas.dart`, lines 116–123

How still, and for how long.

```dart
/// The pen counts as held still while it stays within this many screen px.
const holdSlop = 4.0;

/// Held still this long, the ring and a dashed preview of the shape appear…
const holdPreview = Duration(milliseconds: 150);

/// …and this long, the stroke snaps to the shape.
const holdSnap = Duration(milliseconds: 500);
```

### `lib/canvas/ink_canvas.dart`, lines 241–248

```dart
  // Hold to straighten.
  Timer? _holdTimer;
  Offset _holdAnchor = Offset.zero;
  late final AnimationController _hold = AnimationController(vsync: this, duration: holdSnap)
    ..addListener(_overlay.ping)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _snap();
    });
```

### `lib/canvas/ink_canvas.dart`, lines 1296–1367

After the snap, a line's end follows the pen (that's how angle and length are adjusted). Moving the pen restarts the hold timer.

```dart
  /// Where ink lands for a pen at [screen]: on the ruler's edge if the
  /// stroke started there.
  Offset _inkPoint(Offset screen) {
    final edge = _rulerEdge;
    if (edge == null) return _vp.toPage(screen);
    final gap = active.width * _vp.scale / 2 + 1;
    return _vp.toPage(edge.snap(screen, gap));
  }

  void _inkSample(PointerEvent e) {
    final snapped = _overlay.snapped;
    if (snapped != null) {
      // After the snap, a line's end follows the pen; other shapes stay put.
      if (snapped.kind == ShapeKind.line) {
        final start = snapped.points.first;
        final end = snapLineEnd(start, _vp.toPage(e.localPosition));
        final fit = ShapeFit(ShapeKind.line, linePoints(start, end), angle: lineAngle(start, end).round());
        _overlay.snapped = fit;
        active.shape = fit.points;
      }
      return;
    }
    active.add(_inkPoint(e.localPosition), e.localPosition, _pressure(e), (e.timeStamp - _strokeStart).inMilliseconds);
    _samples++;
    if (_rulerEdge != null) {
      // The chip shows how long the line along the ruler is.
      pane.ruler.measure = (active.points.last - active.points.first).distance;
      return;
    }
    if ((e.localPosition - _holdAnchor).distance > holdSlop) {
      _holdAnchor = e.localPosition;
      _restartHold();
    }
    if (_samples % 3 == 0) _checkScribble();
  }

  /// The pen moved: start timing a new hold.
  void _restartHold() {
    _holdTimer?.cancel();
    if (_hold.value > 0 || _overlay.holdFit != null) {
      _hold.reset();
      _overlay.holdFit = null;
      active.opacity = 1;
      _status(null);
    }
    // Math is kept as it's written: no straightening into shapes.
    if (!ref.read(settingsProvider).snap || _rulerEdge != null || pane.math.on) return;
    _holdTimer = Timer(holdPreview, _holdBegan);
  }

  void _holdBegan() {
    if (_drag != _Drag.ink || _scribbleIds.isNotEmpty) return;
    final fit = fitShape(active.points, unit: _unit);
    if (fit == null) return;
    _overlay.holdFit = fit;
    active.opacity = 0.45;
    _status('Hold to straighten…');
    _hold.forward(from: holdPreview.inMilliseconds / holdSnap.inMilliseconds);
  }

  void _snap() {
    final fit = _overlay.holdFit;
    if (_drag != _Drag.ink || fit == null) return;
    _overlay
      ..snapped = fit
      ..holdFit = null;
    active
      ..shape = fit.points
      ..opacity = 1;
    _status(null);
    if (ref.read(settingsProvider).pref<bool>('haptics')) HapticFeedback.selectionClick();
  }
```

### `lib/canvas/ink_canvas.dart`, lines 1259–1289

Clearing it all when the pen lifts.

```dart
  void _resetInput() {
    _inkingIn?.inking = false;
    _inkingIn = null;
    if (_drag == _Drag.rulerEnd) pane.ruler.releaseEnd();
    _drawPointer = null;
    _drawAt = null;
    _drag = _Drag.none;
    _lastErase = null;
    _fingerDrawing = false;
    _rulerEdge = null;
    _inkTarget = null;
    _stretching = null;
    _connector = null;
    _pad = null;
    _pulled = null;
    _stackOnto = null;
    _stackArmed = false;
    _stackTimer?.cancel();
    _stackTimer = null;
    if (_touch != _Touch.graph) _graphId = null;
    if (_selection.live == null) _moving = const {};
    _scribbleIds = const {};
    _holdTimer?.cancel();
    _hold.reset();
    _overlay
      ..holdFit = null
      ..snapped = null
      ..scribble = const {}
      ..scribbleInk = const []
      ..lasso = []
      ..marquee = null;
```

### `lib/canvas/ink_canvas.dart`, lines 1413–1479

Pen up: the drawn ink is kept, then swapped for the shape, so Undo gives the ink back.

```dart
  void _finishInk() {
    if (!active.isActive) {
      diag('stroke with no points: dropped');
      return;
    }
    _clearGraphed();
    final settings = ref.read(settingsProvider);
    final notifier = _notebook;
    final page = _page;
    final snapped = _overlay.snapped;
    final scribble = _scribbleIds;
    _status(null);

    // A star drawn next to something marks it to remember (before a
    // scribble: a star's tips look like back-and-forths).
    if (snapped == null && _rememberStar(active.toItem(z: page.nextZ), settings)) {
      diag('stroke ${active.points.length} pts -> remember star (not kept)');
      active.clear();
      return;
    }

    if (scribble.isNotEmpty) {
      // The scribble itself is never kept.
      diag('stroke ${active.points.length} pts -> scribble erased ${scribble.length} strokes (not kept)');
      if (_targetNote case final note?) {
        final left = note.withoutInk(scribble);
        notifier.replaceItems(page.id, [if (left is ChecklistItem) left.pruned else left]);
      } else {
        notifier.removeItems(page.id, scribble);
      }
      _toast('Erased ${_strokes(scribble.length)}');
    } else {
      // Two steps: the ink as drawn, then what the gesture makes of it (a
      // shape or an arrow, joined to what its ends are on). Undo gives the
      // ink back.
      final raw = active.toItem(z: page.nextZ);
      StrokeItem? shaped;
      String? message;
      if (snapped != null) {
        shaped = raw.copyWith(pagePoints: active.snappedInk(), shape: () => snapped.kind.name);
        message = '${_shapeName(snapped.kind)} straightened';
      } else {
        shaped = _arrowFrom(raw, settings);
        if (shaped != null) message = 'Made an arrow';
      }
      if (shaped != null && shaped.isConnector) {
        final note = _targetNote;
        // An arrow that leaves the sticky note it started on joins it from
        // the page; one drawn on the note stays on the note.
        if (note == null || !shaped.pagePoints.every((note as BoxItem).contains)) {
          _inkTarget = null;
          shaped = attachEnds(shaped, page.items, slop: _attachReach * _unit);
        }
      }
      diag('stroke ${active.points.length} pts ${active.times.isEmpty ? 0 : active.times.last}ms -> kept${shaped == null ? "" : snapped != null ? " as ${snapped.kind.name}" : " as arrow"}${_targetNote != null ? " on a note" : ""}');
      _putStroke(raw);
      _wroteMath(raw);
      if (shaped != null) {
        _swapStroke(shaped);
        _toast(message!);
        if (snapped?.kind == ShapeKind.line && !shaped.isAttached) _overlay.glow = snapped;
      }
    }
    active.clear();
  }

  /// [raw] with the flick at either end turned into an arrowhead, or null.
```

### `lib/canvas/ink_canvas.dart`, lines 1521–1527

```dart
  static String _shapeName(ShapeKind k) => switch (k) {
        ShapeKind.line => 'Line',
        ShapeKind.circle => 'Circle',
        ShapeKind.ellipse => 'Oval',
        ShapeKind.rect => 'Rectangle',
        ShapeKind.triangle => 'Triangle',
      };
```

### `lib/canvas/ink_canvas.dart`, lines 491–494

```dart
  /// A straightened line's marks go when its "Undo" message does.
  void _statusChanged() {
    if (pane.status.value == null) _overlay.glow = null;
  }
```

## The stroke being drawn

### `lib/canvas/ink_canvas.dart`, lines 2981–3079

Holds the shape shown in place of the ink after the snap.

```dart
class ActiveStroke extends ChangeNotifier {
  final points = <Offset>[];
  final pressures = <double>[];
  final times = <int>[];
  InkTool tool = InkTool.pen;
  PenType penType = PenType.ballpoint;
  Color color = const Color(0xFF000000);
  double width = 2;
  bool usePressure = true;
  Offset? lastScreen;
  DateTime? _startedAt;
  Path? _path;
  List<Offset>? _shape;
  double _opacity = 1;

  /// After hold to straighten: the shape shown (and kept) instead of the ink.
  List<Offset>? get shape => _shape;
  set shape(List<Offset>? v) {
    _shape = v;
    _path = null;
    notifyListeners();
  }

  /// Faded while a scribble is about to erase.
  double get opacity => _opacity;
  set opacity(double v) {
    if (v == _opacity) return;
    _opacity = v;
    notifyListeners();
  }

  bool get isActive => points.isNotEmpty;

  void begin({
    required InkTool tool,
    required PenType penType,
    required Color color,
    required double width,
    required bool usePressure,
  }) {
    this.tool = tool;
    this.penType = penType;
    this.color = color;
    this.width = width;
    this.usePressure = usePressure;
    _startedAt = DateTime.now().toUtc();
    points.clear();
    pressures.clear();
    times.clear();
    _path = null;
    _shape = null;
    _opacity = 1;
  }

  void add(Offset page, Offset screen, double pressure, int tMs) {
    points.add(page);
    pressures.add(pressure);
    times.add(tMs);
    lastScreen = screen;
    _path = null;
    notifyListeners();
  }

  Path get path => _path ??= strokeOutline(
        points: _shape ?? points,
        pressures: _shape == null ? pressures : List.filled(_shape!.length, 0.5),
        width: width,
        penType: tool == InkTool.marker ? PenType.ballpoint : penType,
        usePressure: usePressure && tool == InkTool.pen && _shape == null,
      );

  /// The snapped [shape] as ink points.
  List<InkPoint> snappedInk() => shapeInk(_shape ?? points, pressures, times.isEmpty ? 0 : times.last);

  StrokeItem toItem({required int z}) => StrokeItem.fromPagePoints(
        id: newId('it'),
        z: z,
        createdAt: _startedAt ?? DateTime.now().toUtc(),
        tool: tool,
        penType: penType,
        color: color,
        width: width,
        usePressure: usePressure,
        pagePoints: [
          for (var i = 0; i < points.length; i++) InkPoint(points[i].dx, points[i].dy, pressures[i], times[i]),
        ],
      );

  void clear() {
    points.clear();
    pressures.clear();
    times.clear();
    lastScreen = null;
    _path = null;
    _shape = null;
    _opacity = 1;
    notifyListeners();
  }
}
```

## What's drawn on screen

### `lib/canvas/gesture_overlay.dart`, lines 14–36

```dart
class GestureOverlayState extends ChangeNotifier {
  ShapeFit? _holdFit;
  ShapeFit? _snapped;
  ShapeFit? _glow;
  Set<String> _scribble = const {};
  List<StrokeItem> _scribbleInk = const [];
  List<Offset> _lasso = [];
  Rect? _marquee;
  Item? _ghost;
  Path? _graphed;

  /// While the pen is held: the shape it will snap to (dashed).
  ShapeFit? get holdFit => _holdFit;
  set holdFit(ShapeFit? v) => _set(() => _holdFit = v);

  /// After the snap, while the pen is still down.
  ShapeFit? get snapped => _snapped;
  set snapped(ShapeFit? v) => _set(() => _snapped = v);

  /// A straightened line's ends and angle, shown with its "Undo" toast.
  ShapeFit? get glow => _glow;
  set glow(ShapeFit? v) => _set(() => _glow = v);

```

### `lib/canvas/gesture_overlay.dart`, lines 236–259

The dashed preview and the ring filling up.

```dart
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
```

### `lib/canvas/gesture_overlay.dart`, lines 307–347

The line's end circles, a dashed level line, and the angle.

```dart
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

  /// Graph.dc.html's "Graphed" pill: 12 px bold on the accent tint, its
```

