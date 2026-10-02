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
}) =>
    strokeShape(points: points, pressures: pressures, width: width, penType: penType, usePressure: usePressure).toPath();

/// A filled ink outline: closed polygons that all wind the same way (fill
/// them non-zero), or a single [dot]. Drawn on screen as a [Path] and
/// written to exported PDFs as vectors.
class InkShape {
  const InkShape(this.polygons, {this.dot});

  final List<List<Offset>> polygons;

  /// A stroke of one sample: a round dot.
  final Rect? dot;

  Path toPath() {
    final path = Path();
    if (dot != null) path.addOval(dot!);
    for (final poly in polygons) {
      if (poly.isEmpty) continue;
      path.moveTo(poly.first.dx, poly.first.dy);
      for (final p in poly.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      path.close();
    }
    return path;
  }
}

/// The outline of a stroke as polygons; see [strokeOutline].
InkShape strokeShape({
  required List<Offset> points,
  required List<double> pressures,
  required double width,
  required PenType penType,
  required bool usePressure,
}) {
  final pieces = <List<Offset>>[];
  if (points.isEmpty) return const InkShape([]);

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
    return InkShape(const [], dot: Rect.fromCircle(center: pts.first, radius: radii.first));
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
      _addPiece(pieces, centers, rs, start, k);
      start = k;
    }
  }
  _addPiece(pieces, centers, rs, start, centers.length - 1);
  return InkShape(pieces);
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

void _addPiece(List<List<Offset>> out, List<Offset> c, List<double> r, int from, int to) {
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

  final poly = <Offset>[Offset(c[from].dx + normal(0).dx * r[from], c[from].dy + normal(0).dy * r[from])];
  for (var k = 1; k < n; k++) {
    final i = from + k;
    final nn = normal(k);
    poly.add(Offset(c[i].dx + nn.dx * r[i], c[i].dy + nn.dy * r[i]));
  }
  _cap(poly, c[to], normal(n - 1), tangents[n - 1], r[to]);
  for (var k = n - 1; k >= 0; k--) {
    final i = from + k;
    final nn = normal(k);
    poly.add(Offset(c[i].dx - nn.dx * r[i], c[i].dy - nn.dy * r[i]));
  }
  _cap(poly, c[from], -normal(0), -tangents[0], r[from]);
  out.add(poly);
}

/// Half circle from `center + n·r` round the `t` side to `center − n·r`.
void _cap(List<Offset> poly, Offset center, Offset n, Offset t, double r) {
  final segments = (r * 1.5).clamp(4, 12).round();
  for (var j = 1; j < segments; j++) {
    final a = math.pi * j / segments;
    final cos = math.cos(a), sin = math.sin(a);
    poly.add(Offset(
      center.dx + n.dx * r * cos + t.dx * r * sin,
      center.dy + n.dy * r * cos + t.dy * r * sin,
    ));
  }
}

/// Outline of a stored stroke in page space.
Path outlineFor(StrokeItem s) => inkShapeFor(s).toPath();

/// Outline of a stored stroke in page space, as polygons.
InkShape inkShapeFor(StrokeItem s) => strokeShape(
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

// Arrowheads (Arrows.dc.html): sides about 30° off the line, as long as
// arrowHeadLength(width), pointing along the last stretch of the line so
// curves keep their curve.

const _headHalfAngle = 30 * math.pi / 180;

/// Fill paths for a stroke's arrowheads in page space (empty without arrows).
List<Path> arrowHeadPaths(StrokeItem s) => [for (final h in arrowHeadShapes(s)) h.toPath()];

/// A stroke's arrowheads in page space, as polygons.
List<InkShape> arrowHeadShapes(StrokeItem s) {
  final heads = s.arrow;
  if (heads == null) return const [];
  final pts = s.pagePoints.toList();
  if (pts.length < 2) return const [];
  final len = arrowHeadLength(s.width);
  final out = <InkShape>[];
  if (heads.end) out.addAll(_head(s, pts.last, _pointBack(pts.reversed, len * 0.8), len, heads.style));
  if (heads.start) out.addAll(_head(s, pts.first, _pointBack(pts, len * 0.8), len, heads.style));
  return out;
}

/// The point [dist] along the path from its first point (or its last one).
Offset _pointBack(Iterable<Offset> fromTip, double dist) {
  Offset? prev;
  var run = 0.0;
  for (final p in fromTip) {
    if (prev != null) {
      final seg = (p - prev).distance;
      if (run + seg >= dist && seg > 0) return Offset.lerp(prev, p, (dist - run) / seg)!;
      run += seg;
    }
    prev = p;
  }
  return prev!;
}

List<InkShape> _head(StrokeItem s, Offset tip, Offset from, double len, ArrowStyle style) {
  final d = tip - from;
  if (d.distance == 0) return const [];
  final back = -d / d.distance;
  Offset rot(Offset v, double a) => Offset(v.dx * math.cos(a) - v.dy * math.sin(a), v.dx * math.sin(a) + v.dy * math.cos(a));
  final b1 = tip + rot(back, _headHalfAngle) * len;
  final b2 = tip + rot(back, -_headHalfAngle) * len;
  List<Offset> dense(Offset a, Offset b) =>
      [for (var i = 0; i <= 8; i++) Offset.lerp(a, b, i / 8)!];
  InkShape outline(List<Offset> pts, List<double> pressures, {bool pressure = false}) => strokeShape(
        points: pts,
        pressures: pressures,
        width: s.width,
        penType: s.tool == InkTool.marker ? PenType.ballpoint : s.penType,
        usePressure: pressure,
      );

  switch (style) {
    case ArrowStyle.open:
      final pts = [...dense(b1, tip), ...dense(tip, b2).skip(1)];
      return [outline(pts, List.filled(pts.length, 0.5))];
    case ArrowStyle.filled:
      final tri = InkShape([
        [tip, b1, b2],
      ]);
      final edge = [...dense(b1, tip), ...dense(tip, b2).skip(1), ...dense(b2, b1).skip(1)];
      return [tri, outline(edge, List.filled(edge.length, 0.5))];
    case ArrowStyle.ink:
      // Like a quick hand-drawn chevron: slightly bowed sides that taper
      // from the tip, in the stroke's own pen.
      Offset bow(Offset a, Offset b) {
        final m = Offset.lerp(a, b, 0.5)!;
        final n = Offset(-(b - a).dy, (b - a).dx) / (b - a).distance;
        final side = (n.dx * (tip - m).dx + n.dy * (tip - m).dy) > 0 ? -1.0 : 1.0;
        return m + n * (side * len * 0.08);
      }
      List<Offset> quad(Offset a, Offset c, Offset b) => [
            for (var i = 0; i <= 10; i++)
              a * math.pow(1 - i / 10, 2).toDouble() + c * (2 * (1 - i / 10) * (i / 10)) + b * math.pow(i / 10, 2).toDouble(),
          ];
      final pts = [...quad(b1, bow(b1, tip), tip), ...quad(tip, bow(tip, b2), b2).skip(1)];
      final n = pts.length;
      final pressures = [for (var i = 0; i < n; i++) 0.3 + 0.45 * (1 - ((i - n / 2).abs() / (n / 2)))];
      return [outline(pts, pressures, pressure: true)];
  }
}

final _heads = Expando<List<Path>>('arrowHeads');

/// Cached arrowhead paths; strokes are immutable so they're built once.
List<Path> cachedArrowHeads(StrokeItem s) => _heads[s] ??= arrowHeadPaths(s);
