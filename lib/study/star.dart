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
  // It comes back towards the start (a quick star often stops a little
  // short).
  if ((raw.first - raw.last).distance > 0.6 * diag) return false;
  final pts = resample(raw, diag / 60);
  if (pts.length < 20) return false;
  if (pathLength(pts) < 2.2 * diag) return false;

  // How sharply the stroke turns at [i], over a short and a longer stretch
  // (a rounded tip turns over a longer one).
  double turnAt(int i) {
    var best = 0.0;
    for (final k in const [3, 6]) {
      if (i - k < 0 || i + k >= pts.length) continue;
      final t = _signedTurn(pts[i] - pts[i - k], pts[i + k] - pts[i]);
      if (t.abs() > best.abs()) best = t;
    }
    return best;
  }

  final tips = <int>[];
  var lastTip = -100;
  for (var i = 3; i < pts.length - 3; i++) {
    if (turnAt(i).abs() > 95 && i - lastTip > 8) {
      // The sharpest point of this tip.
      var at = i;
      for (var j = i + 1; j < math.min(pts.length - 3, i + 8); j++) {
        if (turnAt(j).abs() > turnAt(at).abs()) at = j;
      }
      tips.add(at);
      lastTip = at;
      i = at;
    }
  }
  var turning = 0.0;
  for (var i = 1; i < pts.length - 1; i++) {
    turning += _signedTurn(pts[i] - pts[i - 1], pts[i + 1] - pts[i]);
  }
  if (tips.length < 4 || tips.length > 7) return false;
  // Its tips turn the way the whole star goes round (a scribble's turns go
  // back and forth); one the other way is a wobble.
  final sign = turning.sign;
  final opposite = tips.where((i) => turnAt(i).sign != sign).length;
  if (opposite > 1 || tips.length - opposite < 4) return false;
  // A pentagram turns about 720° (576° from tip to tip), its outline 360°
  // (216° from tip to tip: the tips turn one way, its inner corners back).
  if (turning.abs() < 170 || turning.abs() > 860) return false;

  // The tips (with where it started) go all the way round its middle, at
  // four or five places (a triangle gone round twice has three).
  final points = [pts.first, for (final i in tips) if (turnAt(i).sign == sign) pts[i]];
  final places = <Offset>[];
  for (final p in points) {
    if (places.every((q) => (q - p).distance > 0.25 * diag)) places.add(p);
  }
  if (places.length < 4) return false;
  final mid = Offset(box.center.dx, box.center.dy);
  final angles = [for (final p in points) math.atan2(p.dy - mid.dy, p.dx - mid.dx) * 180 / math.pi]..sort();
  var gap = 360 - (angles.last - angles.first);
  for (var i = 1; i < angles.length; i++) {
    gap = math.max(gap, angles[i] - angles[i - 1]);
  }
  if (gap > 140) return false;
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
