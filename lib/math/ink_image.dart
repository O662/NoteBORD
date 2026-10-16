import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

// Handwriting drawn as the math model sees it. The model (CoMER) learned
// from CROHME's pictures: white strokes on black, 3 px wide, writing about
// 30 px tall. Ported line for line from tool/math_model/render.py, where
// those numbers were tuned on real pen strokes.

/// A picture of handwriting for the math model: [width] × [height] pixels,
/// row by row, 1 where there's ink and 0 elsewhere.
class InkImage {
  const InkImage(this.width, this.height, this.pixels);

  final int width;
  final int height;
  final Float32List pixels;

  bool inkAt(int x, int y) => pixels[y * width + x] > 0;
}

/// How tall the writing is: the median height of the strokes that aren't
/// flat (minus signs, fraction bars and dots don't count).
double writingSize(List<List<Offset>> strokes) {
  final heights = <double>[];
  for (final s in strokes) {
    final b = _bounds(s);
    if (b.h >= 0.5 * b.w && b.h > 0) heights.add(b.h);
  }
  if (heights.isEmpty) {
    for (final s in strokes) {
      final b = _bounds(s);
      heights.add(math.max(b.h, b.w));
    }
  }
  heights.sort();
  final m = heights.isEmpty ? 1.0 : heights[heights.length ~/ 2];
  return math.max(m, 1e-3);
}

/// The strokes ([strokes], in page coordinates) as the model's picture, or
/// null when there's no ink.
InkImage? renderInk(List<List<Offset>> strokes, {double symbolPx = 30, double linePx = 3, int margin = 4}) {
  final ink = [for (final s in strokes) if (s.isNotEmpty) s];
  if (ink.isEmpty) return null;
  final size = writingSize(ink);
  var k = symbolPx / size;
  var x0 = double.infinity, y0 = double.infinity, x1 = -double.infinity, y1 = -double.infinity;
  for (final s in ink) {
    for (final p in s) {
      x0 = math.min(x0, p.dx);
      y0 = math.min(y0, p.dy);
      x1 = math.max(x1, p.dx);
      y1 = math.max(y1, p.dy);
    }
  }
  final w = (x1 - x0) * k, h = (y1 - y0) * k;
  // The model's limits: at most 256 high and 1024 wide.
  final fit = math.min(
    1.0,
    math.min((256 - 2 * margin - linePx) / math.max(h, 1e-6), (1024 - 2 * margin - linePx) / math.max(w, 1e-6)),
  );
  k *= fit;
  final r = linePx / 2;
  final off = margin + r;
  final width = math.max(16, ((x1 - x0) * k + 2 * off).ceil());
  final height = math.max(16, ((y1 - y0) * k + 2 * off).ceil());
  final pixels = Float32List(width * height);
  for (final s in ink) {
    final pts = [for (final p in s) Offset((p.dx - x0) * k + off, (p.dy - y0) * k + off)];
    if (pts.length == 1) pts.add(pts.first);
    for (var i = 0; i + 1 < pts.length; i++) {
      _segment(pixels, width, height, pts[i], pts[i + 1], r);
    }
  }
  return InkImage(width, height, pixels);
}

/// Pixels whose centre is within [r] of the segment from [a] to [b] become 1.
void _segment(Float32List img, int width, int height, Offset a, Offset b, double r) {
  final xLo = math.max(0, (math.min(a.dx, b.dx) - r).floor());
  final xHi = math.min(width - 1, (math.max(a.dx, b.dx) + r).ceil());
  final yLo = math.max(0, (math.min(a.dy, b.dy) - r).floor());
  final yHi = math.min(height - 1, (math.max(a.dy, b.dy) + r).ceil());
  final dx = b.dx - a.dx, dy = b.dy - a.dy;
  final ll = dx * dx + dy * dy;
  final rr = r * r;
  for (var y = yLo; y <= yHi; y++) {
    final py = y + 0.5;
    for (var x = xLo; x <= xHi; x++) {
      final px = x + 0.5;
      final t = ll == 0 ? 0.0 : (((px - a.dx) * dx + (py - a.dy) * dy) / ll).clamp(0.0, 1.0);
      final qx = a.dx + t * dx - px, qy = a.dy + t * dy - py;
      if (qx * qx + qy * qy <= rr) img[y * width + x] = 1;
    }
  }
}

({double w, double h}) _bounds(List<Offset> s) {
  var x0 = double.infinity, y0 = double.infinity, x1 = -double.infinity, y1 = -double.infinity;
  for (final p in s) {
    x0 = math.min(x0, p.dx);
    y0 = math.min(y0, p.dy);
    x1 = math.max(x1, p.dx);
    y1 = math.max(y1, p.dy);
  }
  return (w: x1 - x0, h: y1 - y0);
}
