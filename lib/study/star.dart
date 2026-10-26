import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import '../board/model.dart';
import '../canvas/gestures.dart' show pathLength, resample;

// "Draw a star next to anything to mark it" (RememberMark.png): telling a
// drawn star from other ink, and finding what it's next to.

/// Whether [raw] (page points) was drawn as a five-pointed star: in one
/// stroke, as a pentagram (crossing itself) or as its outline. [unit] is
/// page px per screen px, so the size limits follow the hand.
///
/// A star has at least four sharp tips that all turn the same way (a
/// scribble's turns go back and forth), comes back to where it started,
/// and its tips go all the way round its middle.
bool looksLikeStar(List<Offset> raw, {double unit = 1}) {
  if (raw.length < 8) return false;
  final box = _bounds(raw);
  final diag = math.sqrt(box.width * box.width + box.height * box.height);
  if (diag < 22 * unit || box.width <= 0 || box.height <= 0) return false;
  final aspect = box.width / box.height;
  if (aspect < 0.55 || aspect > 1.8) return false;
  // It closes: the end comes back near the start.
  if ((raw.first - raw.last).distance > 0.3 * diag) return false;
  final pts = resample(raw, diag / 60);
  if (pts.length < 20) return false;
  if (pathLength(pts) < 2.4 * diag) return false;

  const k = 3;
  final tips = <int>[];
  var opposite = 0;
  var turning = 0.0;
  var lastTip = -100;
  for (var i = k; i < pts.length - k; i++) {
    final a = pts[i] - pts[i - k], b = pts[i + k] - pts[i];
    final turn = _signedTurn(a, b);
    if (turn.abs() > 100 && i - lastTip > 2 * k) {
      tips.add(i);
      lastTip = i;
    }
  }
  for (var i = 1; i < pts.length - 1; i++) {
    turning += _signedTurn(pts[i] - pts[i - 1], pts[i + 1] - pts[i]);
  }
  if (tips.length < 4 || tips.length > 6) return false;
  // Every tip turns the way the whole star goes round.
  final sign = turning.sign;
  for (final i in tips) {
    final t = _signedTurn(pts[i] - pts[i - k], pts[i + k] - pts[i]);
    if (t.sign != sign) opposite++;
  }
  if (opposite > 0) return false;
  // A pentagram turns about 720° (576° from tip to tip), its outline 360°
  // (216° from tip to tip: the tips turn one way, its inner corners back).
  if (turning.abs() < 180 || turning.abs() > 860) return false;

  // The tips (with where it started) go all the way round its middle.
  final points = [pts.first, for (final i in tips) pts[i]];
  final mid = Offset(box.center.dx, box.center.dy);
  final angles = [for (final p in points) math.atan2(p.dy - mid.dy, p.dx - mid.dx) * 180 / math.pi]..sort();
  var gap = 360 - (angles.last - angles.first);
  for (var i = 1; i < angles.length; i++) {
    gap = math.max(gap, angles[i] - angles[i - 1]);
  }
  if (gap > 135) return false;
  final reach = [for (final p in points) (p - mid).distance];
  final mean = reach.reduce((a, b) => a + b) / reach.length;
  return reach.every((r) => r > 0.55 * mean);
}

double _signedTurn(Offset a, Offset b) {
  if (a.distance == 0 || b.distance == 0) return 0;
  return math.atan2(a.dx * b.dy - a.dy * b.dx, a.dx * b.dx + a.dy * b.dy) * 180 / math.pi;
}

Rect _bounds(List<Offset> pts) {
  var r = Rect.fromPoints(pts.first, pts.first);
  for (final p in pts) {
    r = r.expandToInclude(Rect.fromPoints(p, p));
  }
  return r;
}

/// What [star] was drawn next to: the line of writing (and anything else)
/// on the nearer side of it, at its height. Empty when there's nothing
/// close enough. [unit] is page px per screen px.
List<Item> besideStar(StrokeItem star, Iterable<Item> items, {double unit = 1}) {
  final s = star.extent;
  final h = math.max(s.height, 16 * unit);
  final reach = math.max(2.5 * h, 60 * unit);

  double overlapY(Rect a, Rect b) => math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
  double gapX(Rect a, Rect b) => math.max(0, math.max(a.left - b.right, b.left - a.right));

  final candidates = <Item>[
    for (final i in items)
      if (i.id != star.id &&
          i is! FlashcardItem &&
          i is! UnknownItem &&
          !(i is StrokeItem && i.tool == InkTool.marker) &&
          // Not the paper it's drawn on.
          !(i is BoxItem && i.extent.contains(s.center)))
        i,
  ];
  bool level(Rect r, Rect band) {
    final o = overlapY(r, band);
    // Or a dot or comma that reaches it.
    return o > 0.3 * math.min(r.height, band.height) || (r.height < 0.5 * band.height && o > 0);
  }

  final band = Rect.fromLTRB(s.left, s.center.dy - h * 0.9, s.right, s.center.dy + h * 0.9);
  Item? nearest;
  var best = double.infinity;
  for (final i in candidates) {
    final r = i.extent;
    if (!level(r, band)) continue;
    final d = gapX(r, s);
    if (d <= reach && d < best) {
      best = d;
      nearest = i;
    }
  }
  if (nearest == null) return const [];
  final right = nearest.extent.center.dx > s.center.dx;
  final side = [
    for (final i in candidates)
      if (right ? i.extent.center.dx > s.center.dx : i.extent.center.dx < s.center.dx) i,
  ];

  final picked = <Item>{nearest};
  var run = nearest.extent;
  var grew = true;
  while (grew && picked.length < 400) {
    grew = false;
    // How far apart words on a line are: about the line's height.
    final lineH = math.max(run.height, h * 0.6);
    final step = math.max(1.4 * lineH, 40 * unit);
    for (final i in side) {
      if (picked.contains(i)) continue;
      final r = i.extent;
      // At the line's height, and touching it or a word's gap away (a
      // circle around the words counts; the lines above and below don't).
      if (level(r, run) && gapX(r, run) <= step) {
        // A long stroke that runs far above or below (a margin line) isn't part of it.
        if (r.height > 3 * math.max(run.height, h)) continue;
        picked.add(i);
        run = run.expandToInclude(r);
        grew = true;
      }
    }
  }
  return [for (final i in items) if (picked.contains(i)) i];
}
