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

  Offset get u => Offset(math.cos(angle), math.sin(angle));
  Offset get v => Offset(-math.sin(angle), math.cos(angle));

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
  return pts.sublist(0, best + 1);
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

// Flick back for an arrow.

/// Which ends of a stroke end in a flick, and the part of the stroke to keep
/// (`from`..`to`, inclusive, as indexes into the input points).
class Flicks {
  const Flicks({required this.start, required this.end, required this.from, required this.to});

  final bool start;
  final bool end;
  final int from;
  final int to;
}

/// Finds a short hook back at either end of a line. The hook must be short
/// (at most 45 screen px and 30% of the line), quick, fold back along the
/// line (within 60°), and follow a smooth stretch, so zig-zags, check marks
/// and long strokes back along the line stay ink.
Flicks? detectFlicks(List<Offset> pts, {List<int>? times, double unit = 1}) {
  if (pts.length < 4) return null;
  final end = _flickAtEnd(pts, times, unit, maxAngle: 60);
  final rev = pts.reversed.toList();
  final revTimes = times?.reversed.map((t) => times.last - t).toList();
  final startHit = _flickAtEnd(rev, revTimes, unit, maxAngle: 50);
  final to = end ?? pts.length - 1;
  final from = startHit == null ? 0 : pts.length - 1 - startHit;
  if (end == null && startHit == null) return null;
  // Both hooks can't eat the whole line.
  if (to - from < 2 || pathLength(pts.sublist(from, to + 1)) < 30 * unit) return null;
  return Flicks(start: startHit != null, end: end != null, from: from, to: to);
}

/// Index of the tip where a flick at the end of [pts] starts, or null.
int? _flickAtEnd(List<Offset> pts, List<int>? times, double unit, {required double maxAngle}) {
  final arc = arcLengths(pts);
  final total = arc.last;
  final e = pts.last;
  final maxFlick = math.min(45 * unit, 0.3 * total);

  // The sharpest turn within flick reach of the end is the tip.
  int? tip;
  var bestTurn = 0.0;
  for (var i = pts.length - 2; i > 0; i--) {
    if (total - arc[i] > maxFlick) break;
    final before = _atArc(pts, arc, arc[i] - 4 * unit);
    final after = _atArc(pts, arc, math.min(total, arc[i] + 4 * unit));
    final t = angleBetween(pts[i] - before, after - pts[i]);
    if (t > bestTurn) {
      bestTurn = t;
      tip = i;
    }
  }
  if (tip == null || bestTurn < 180 - maxAngle) return null;

  final t = pts[tip];
  final flickLen = (e - t).distance;
  if (flickLen < 6 * unit || flickLen > maxFlick) return null;
  if (total - arc[tip] > 1.35 * flickLen) return null; // the hook must be fairly straight
  final mainLen = arc[tip];
  if (mainLen < 40 * unit || flickLen > 0.3 * mainLen) return null;
  if (times != null && times.length == pts.length && times.last - times[tip] > 350) return null;

  // Direction of the line arriving at the tip, and how far the hook folds back.
  final inDir = t - _atArc(pts, arc, arc[tip] - 16 * unit);
  if (angleBetween(e - t, -inDir) > maxAngle) return null;

  // The line before the hook must be smooth: no zig-zag right before it.
  final from = arc[tip] - math.min(40 * unit, 0.5 * mainLen);
  for (var i = tip - 1; i > 0 && arc[i] > from; i--) {
    final b = _atArc(pts, arc, arc[i] - 6 * unit);
    final a = _atArc(pts, arc, math.min(arc[tip], arc[i] + 6 * unit));
    if (angleBetween(pts[i] - b, a - pts[i]) > 60) return null;
  }
  return tip;
}

Offset _atArc(List<Offset> pts, List<double> arc, double s) {
  if (s <= 0) return pts.first;
  if (s >= arc.last) return pts.last;
  var lo = 0, hi = arc.length - 1;
  while (hi - lo > 1) {
    final mid = (lo + hi) >> 1;
    if (arc[mid] < s) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  final span = arc[hi] - arc[lo];
  return span == 0 ? pts[lo] : Offset.lerp(pts[lo], pts[hi], (s - arc[lo]) / span)!;
}

// Scribble to erase.

enum ScribbleLevel { light, normal, firm }

String scribbleLevelLabel(ScribbleLevel l) => switch (l) {
      ScribbleLevel.light => 'Light',
      ScribbleLevel.normal => 'Normal',
      ScribbleLevel.firm => 'Firm',
    };

/// Help text under the sensitivity choice (Scribble.dc.html).
String scribbleLevelHelp(ScribbleLevel l) => switch (l) {
      ScribbleLevel.light => 'Two quick back-and-forth strokes are enough.',
      ScribbleLevel.normal => 'Three or more back-and-forth strokes. Shading stays safe.',
      ScribbleLevel.firm => 'Needs a dense scribble. Best if you shade or hatch a lot.',
    };

/// Sharp reversals along a stroke (each back-and-forth adds one).
int countCusps(List<Offset> raw, {double unit = 1}) {
  final pts = resample(raw, 2 * unit);
  const k = 3;
  if (pts.length < 2 * k + 1) return 0;
  var count = 0;
  var lastAt = -100;
  for (var i = k; i < pts.length - k; i++) {
    final turn = angleBetween(pts[i] - pts[i - k], pts[i + k] - pts[i]);
    if (turn > 110 && i - lastAt > 2 * k) {
      count++;
      lastAt = i;
    }
  }
  return count;
}

/// Whether a stroke is shaped like a scribble at this sensitivity. It only
/// erases when there is ink under it (see [scribbleTargets]).
bool looksLikeScribble(List<Offset> pts, ScribbleLevel level, {double unit = 1}) {
  if (pts.length < 6) return false;
  final (minCusps, minDensity) = switch (level) {
    ScribbleLevel.light => (3, 1.8),
    ScribbleLevel.normal => (5, 1.8),
    ScribbleLevel.firm => (7, 3.0),
  };
  if (countCusps(pts, unit: unit) < minCusps) return false;
  final (_, angle) = principalAxis(pts);
  final box = OrientedBox.around(pts, angle);
  return box.diagonal > 0 && pathLength(pts) / box.diagonal >= minDensity;
}

/// The strokes a scribble covers: each one must be touched by the scribble
/// and lie mostly (half its points or more) inside the scribbled area, so a
/// long line the scribble only clips is left alone.
List<StrokeItem> scribbleTargets(List<Offset> scribble, Iterable<StrokeItem> candidates, {double unit = 1}) {
  if (scribble.length < 2) return const [];
  final (_, angle) = principalAxis(scribble);
  final core = OrientedBox.around(scribble, angle);
  final zone = core.inflate(math.max(6 * unit, 0.25 * math.min(core.halfU, core.halfV) * 2));
  final out = <StrokeItem>[];
  for (final s in candidates) {
    final pts = s.pagePoints.toList();
    var inside = 0;
    for (final p in pts) {
      if (zone.contains(p)) inside++;
    }
    if (inside * 2 < pts.length) continue;
    var touched = false;
    for (var i = 1; i < scribble.length && !touched; i++) {
      touched = strokeHit(s, scribble[i - 1], scribble[i], 2 * unit);
    }
    if (touched) out.add(s);
  }
  return out;
}

// Lasso.

/// Even-odd point in polygon.
bool insidePolygon(Offset p, List<Offset> poly) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) && p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}

/// Items at least half inside [poly] (strokes by their points, others by
/// their corners and center).
List<Item> itemsInPolygon(List<Offset> poly, Iterable<Item> items) {
  if (poly.length < 3) return const [];
  final out = <Item>[];
  for (final item in items) {
    final pts = switch (item) {
      StrokeItem s => s.pagePoints.toList(),
      _ => [item.bounds.topLeft, item.bounds.topRight, item.bounds.bottomLeft, item.bounds.bottomRight, item.bounds.center],
    };
    var inside = 0;
    for (final p in pts) {
      if (insidePolygon(p, poly)) inside++;
    }
    if (pts.isNotEmpty && inside * 2 >= pts.length) out.add(item);
  }
  return out;
}
