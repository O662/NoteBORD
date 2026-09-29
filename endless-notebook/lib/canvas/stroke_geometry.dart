import 'dart:math' as math;
import 'dart:ui';

import '../board/model.dart';
import 'pens.dart';

/// Turns pen samples into a filled outline whose width follows pressure.
///
/// Samples are smoothed with quadratic curves through their midpoints, then
/// offset left and right by the local radius and joined with round caps.
/// Sharp turns split the outline into pieces with their own caps; every piece
/// winds the same way, so the non-zero fill unions them without seams, and a
/// translucent marker never darkens where it overlaps itself.
Path strokeOutline({
  required List<Offset> points,
  required List<double> pressures,
  required double width,
  required PenType penType,
  required bool usePressure,
}) {
  final path = Path();
  if (points.isEmpty) return path;

  // Radius per input point, with pressure lightly smoothed to hide jitter.
  final pts = <Offset>[];
  final radii = <double>[];
  double? smoothed;
  for (var i = 0; i < points.length; i++) {
    final raw = usePressure ? pressures[i] : 0.5;
    smoothed = smoothed == null ? raw : smoothed + (raw - smoothed) * 0.35;
    final r = math.max(0.3, width * pressureFactor(penType, smoothed) / 2);
    // Drop samples that barely moved; keep the thicker radius.
    if (pts.isNotEmpty && (points[i] - pts.last).distance < 0.35) {
      radii[radii.length - 1] = math.max(radii.last, r);
      continue;
    }
    pts.add(points[i]);
    radii.add(r);
  }

  if (pts.length == 1) {
    return path..addOval(Rect.fromCircle(center: pts.first, radius: radii.first));
  }

  final (centers, rs) = _resample(pts, radii);

  // Split at sharp turns (> ~75°).
  var start = 0;
  for (var k = 1; k < centers.length - 1; k++) {
    final a = centers[k] - centers[k - 1];
    final b = centers[k + 1] - centers[k];
    if (a.distance == 0 || b.distance == 0) continue;
    final cos = (a.dx * b.dx + a.dy * b.dy) / (a.distance * b.distance);
    if (cos < 0.26) {
      _addPiece(path, centers, rs, start, k);
      start = k;
    }
  }
  _addPiece(path, centers, rs, start, centers.length - 1);
  return path;
}

/// Quadratic midpoint smoothing, sampled about every 1.5 px.
(List<Offset>, List<double>) _resample(List<Offset> p, List<double> r) {
  final c = <Offset>[p.first];
  final rr = <double>[r.first];
  if (p.length == 2) {
    c.add(p.last);
    rr.add(r.last);
    return (c, rr);
  }
  for (var i = 1; i < p.length - 1; i++) {
    final a = i == 1 ? p[0] : Offset.lerp(p[i - 1], p[i], 0.5)!;
    final ra = i == 1 ? r[0] : (r[i - 1] + r[i]) / 2;
    final b = p[i];
    final rb = r[i];
    final e = i == p.length - 2 ? p[i + 1] : Offset.lerp(p[i], p[i + 1], 0.5)!;
    final re = i == p.length - 2 ? r[i + 1] : (r[i] + r[i + 1]) / 2;
    final len = (b - a).distance + (e - b).distance;
    final steps = math.max(1, (len / 1.5).ceil());
    for (var s = 1; s <= steps; s++) {
      final t = s / steps;
      final u = 1 - t;
      c.add(a * (u * u) + b * (2 * u * t) + e * (t * t));
      rr.add(ra * u * u + rb * 2 * u * t + re * t * t);
    }
  }
  return (c, rr);
}

void _addPiece(Path path, List<Offset> c, List<double> r, int from, int to) {
  if (to <= from) return;
  final n = to - from + 1;
  final tangents = List<Offset>.filled(n, const Offset(1, 0));
  var last = const Offset(1, 0);
  for (var k = 0; k < n; k++) {
    final i = from + k;
    final d = (i == to ? c[i] : c[i + 1]) - (i == from ? c[i] : c[i - 1]);
    final len = d.distance;
    if (len > 1e-6) last = d / len;
    tangents[k] = last;
  }
  Offset normal(int k) => Offset(-tangents[k].dy, tangents[k].dx);

  path.moveTo(c[from].dx + normal(0).dx * r[from], c[from].dy + normal(0).dy * r[from]);
  for (var k = 1; k < n; k++) {
    final i = from + k;
    final nn = normal(k);
    path.lineTo(c[i].dx + nn.dx * r[i], c[i].dy + nn.dy * r[i]);
  }
  _cap(path, c[to], normal(n - 1), tangents[n - 1], r[to]);
  for (var k = n - 1; k >= 0; k--) {
    final i = from + k;
    final nn = normal(k);
    path.lineTo(c[i].dx - nn.dx * r[i], c[i].dy - nn.dy * r[i]);
  }
  _cap(path, c[from], -normal(0), -tangents[0], r[from]);
  path.close();
}

/// Half circle from `center + n·r` round the `t` side to `center − n·r`.
void _cap(Path path, Offset center, Offset n, Offset t, double r) {
  final segments = (r * 1.5).clamp(4, 12).round();
  for (var j = 1; j < segments; j++) {
    final a = math.pi * j / segments;
    final cos = math.cos(a), sin = math.sin(a);
    path.lineTo(
      center.dx + n.dx * r * cos + t.dx * r * sin,
      center.dy + n.dy * r * cos + t.dy * r * sin,
    );
  }
}

/// Outline of a stored stroke in page space.
Path outlineFor(StrokeItem s) => strokeOutline(
      points: s.pagePoints.toList(),
      pressures: [for (final p in s.points) p.pressure],
      width: s.width,
      penType: s.tool == InkTool.marker ? PenType.ballpoint : s.penType,
      usePressure: s.usePressure && s.tool == InkTool.pen,
    );

final _outlines = Expando<Path>('outline');

/// Cached outline; strokes are immutable so it's built once.
Path cachedOutline(StrokeItem s) => _outlines[s] ??= outlineFor(s);

/// Whether the eraser moving from [a] to [b] with radius [r] touches [s].
bool strokeHit(StrokeItem s, Offset a, Offset b, double r) {
  if (!s.bounds.inflate(r).overlaps(Rect.fromPoints(a, b).inflate(0.01))) return false;
  final reach = r + s.maxWidth / 2;
  Offset? prev;
  for (final p in s.pagePoints) {
    if (prev == null) {
      if (segmentDistance(a, b, p, p) <= reach) return true;
    } else if (segmentDistance(a, b, prev, p) <= reach) {
      return true;
    }
    prev = p;
  }
  return false;
}

double _pointSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 == 0) return (p - a).distance;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;

/// Shortest distance between segments a1–a2 and b1–b2.
double segmentDistance(Offset a1, Offset a2, Offset b1, Offset b2) {
  final d1 = a2 - a1, d2 = b2 - b1;
  final denom = _cross(d1, d2);
  if (denom != 0) {
    final t = _cross(b1 - a1, d2) / denom;
    final u = _cross(b1 - a1, d1) / denom;
    if (t >= 0 && t <= 1 && u >= 0 && u <= 1) return 0;
  }
  return [
    _pointSegment(a1, b1, b2),
    _pointSegment(a2, b1, b2),
    _pointSegment(b1, a1, a2),
    _pointSegment(b2, a1, a2),
  ].reduce(math.min);
}
