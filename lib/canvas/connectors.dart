import 'dart:math' as math;
import 'dart:ui';

import '../board/model.dart';
import 'gestures.dart' show insidePolygon;

// Connectors: arrows and straight lines whose ends are attached to the edge
// of a shape, sticky note, frame, card or other box on the page
// (design/source/Arrows.dc.html, "snaps to shapes, moves with them").
// The stroke keeps the ids of what its ends are on (`startItemId`,
// `endItemId`), and when one of those moves, turns or is resized, the ink
// is bent like a rubber band so that end stays on the same spot of its
// edge while the rest of the line keeps its shape.

/// Whether a connector's end can be attached to [item]: any box but a
/// line or arrow shape (they have no inside).
bool canAttach(Item item) => item is BoxItem && !(item is ShapeItem && item.isLine);

/// Frames and pictures are written on: a line drawn on them is joined to
/// them only when its end is at their edge, never because it's inside.
bool _holdsWriting(BoxItem b) => b is FrameItem || b is ImageItem;

/// The outline of [item] as a polygon in its own coordinates (null for an
/// oval, which is handled as an ellipse).
List<Offset>? _outline(BoxItem item) {
  final w = item.w, h = item.h;
  if (item is ShapeItem && item.kind == ShapeType.ellipse) return null;
  if (item is ShapeItem && item.kind == ShapeType.triangle) return [Offset(w / 2, 0), Offset(w, h), Offset(0, h)];
  return [Offset.zero, Offset(w, 0), Offset(w, h), Offset(0, h)];
}

/// Whether [local] (relative to the item's top-left, before rotation) is
/// inside [item]'s outline.
bool insideOutline(BoxItem item, Offset local) {
  final poly = _outline(item);
  if (poly != null) {
    if (item is ShapeItem) return insidePolygon(local, poly);
    return local.dx >= 0 && local.dy >= 0 && local.dx <= item.w && local.dy <= item.h;
  }
  final rx = item.w / 2, ry = item.h / 2;
  if (rx <= 0 || ry <= 0) return false;
  final x = (local.dx - rx) / rx, y = (local.dy - ry) / ry;
  return x * x + y * y <= 1;
}

Offset _nearestOnSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 == 0) return a;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
  return a + ab * t;
}

/// The point of [item]'s outline nearest [local] (both in its own
/// coordinates). For an oval, the point straight out from its center.
Offset nearestOnOutline(BoxItem item, Offset local) {
  final poly = _outline(item);
  if (poly != null) {
    Offset? best;
    var bestD = double.infinity;
    for (var i = 0; i < poly.length; i++) {
      final q = _nearestOnSegment(local, poly[i], poly[(i + 1) % poly.length]);
      final d = (q - local).distance;
      if (d < bestD) {
        bestD = d;
        best = q;
      }
    }
    return best!;
  }
  final c = Offset(item.w / 2, item.h / 2);
  final rx = item.w / 2, ry = item.h / 2;
  final q = local - c;
  if (q.distance < 1e-9 || rx <= 0 || ry <= 0) return Offset(item.w, item.h / 2);
  final k = 1 / math.sqrt(math.pow(q.dx / rx, 2) + math.pow(q.dy / ry, 2));
  return c + q * k;
}

/// How far page point [page] is from [item]'s outline.
double distanceToOutline(BoxItem item, Offset page) {
  final local = item.toLocal(page);
  return (nearestOnOutline(item, local) - local).distance;
}

/// Bends [pts] like a rubber band: the first point moves by [start], the
/// last by [end], and the points between by a share of each that follows
/// how far along the line they are. A straight line stays straight.
List<InkPoint> rubberBand(List<InkPoint> pts, Offset start, Offset end) {
  if (pts.isEmpty || (start == Offset.zero && end == Offset.zero)) return pts;
  final along = <double>[0];
  for (var i = 1; i < pts.length; i++) {
    along.add(along.last + (Offset(pts[i].x, pts[i].y) - Offset(pts[i - 1].x, pts[i - 1].y)).distance);
  }
  final total = along.last;
  return [
    for (final (i, p) in pts.indexed)
      () {
        final t = total == 0 ? (pts.length == 1 ? 0.0 : i / (pts.length - 1)) : along[i] / total;
        final d = start * (1 - t) + end * t;
        return InkPoint(p.x + d.dx, p.y + d.dy, p.pressure, p.t);
      }(),
  ];
}

InkPoint _lerp(InkPoint a, InkPoint b, double t) => InkPoint(
      a.x + (b.x - a.x) * t,
      a.y + (b.y - a.y) * t,
      a.pressure + (b.pressure - a.pressure) * t,
      (a.t + (b.t - a.t) * t).round(),
    );

/// Where the segment from [inside] to [outside] crosses [item]'s outline.
InkPoint _crossing(BoxItem item, InkPoint inside, InkPoint outside) {
  var lo = 0.0, hi = 1.0;
  for (var i = 0; i < 24; i++) {
    final mid = (lo + hi) / 2;
    final m = _lerp(inside, outside, mid);
    if (insideOutline(item, item.toLocal(Offset(m.x, m.y)))) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return _lerp(inside, outside, (lo + hi) / 2);
}

/// [s] (a connector just drawn, or an end just dragged) with each end that
/// starts or ends on a box snapped to the box's edge and attached to it. An
/// end within [slop] of an outline moves onto it; an end inside a box is cut
/// back to where the line crosses its edge. A line that stays inside one
/// box is drawn on it, not joined to it. [ends] says which ends to try
/// (both by default); an end that finds nothing is detached.
StrokeItem attachEnds(
  StrokeItem s,
  List<Item> inZOrder, {
  required double slop,
  bool start = true,
  bool end = true,
}) {
  var pts = s.pageInk;
  String? startId = start ? null : s.startItemId;
  String? endId = end ? null : s.endItemId;

  for (final atStart in [true, false]) {
    if (atStart ? !start : !end) continue;
    if (pts.length < 2) break;
    final p = atStart ? pts.first : pts.last;
    final at = Offset(p.x, p.y);
    BoxItem? target;
    for (final item in inZOrder.reversed) {
      if (!canAttach(item)) continue;
      final box = item as BoxItem;
      final inside = insideOutline(box, box.toLocal(at));
      if (distanceToOutline(box, at) <= slop || (inside && !_holdsWriting(box))) {
        target = box;
        break;
      }
    }
    if (target == null) continue;

    final order = atStart ? [for (var i = 0; i < pts.length; i++) i] : [for (var i = pts.length - 1; i >= 0; i--) i];
    bool inTarget(int i) => insideOutline(target!, target.toLocal(Offset(pts[i].x, pts[i].y)));
    if (inTarget(order.first)) {
      // Walk out from the end to where the line leaves the box.
      final out = order.indexWhere((i) => !inTarget(i));
      if (out < 0) {
        // It never leaves: drawn on the box. Only an end right at the edge joins.
        if (distanceToOutline(target, at) > slop || _holdsWriting(target)) continue;
        pts = _moveEnd(pts, target, atStart);
      } else {
        final cross = _crossing(target, pts[order[out - 1]], pts[order[out]]);
        final kept = atStart ? [cross, ...pts.sublist(order[out])] : [...pts.sublist(0, order[out] + 1), cross];
        if (kept.length < 2) continue;
        pts = kept;
      }
    } else {
      pts = _moveEnd(pts, target, atStart);
    }
    if (atStart) {
      startId = target.id;
    } else {
      endId = target.id;
    }
  }
  return s.copyWith(pagePoints: pts, startItemId: () => startId, endItemId: () => endId);
}

/// [pts] with one end moved onto the nearest point of [box]'s outline.
List<InkPoint> _moveEnd(List<InkPoint> pts, BoxItem box, bool atStart) {
  final p = atStart ? pts.first : pts.last;
  final at = Offset(p.x, p.y);
  final onEdge = box.toPage(nearestOnOutline(box, box.toLocal(at)));
  final d = onEdge - at;
  return atStart ? rubberBand(pts, d, Offset.zero) : rubberBand(pts, Offset.zero, d);
}

/// Where page point [at] (on [box]'s edge) is, as a fraction of the box.
Offset _anchor(BoxItem box, Offset at) {
  final local = box.toLocal(at);
  return Offset(box.w == 0 ? 0.5 : local.dx / box.w, box.h == 0 ? 0.5 : local.dy / box.h);
}

/// [s] after the box [id] it's attached to went from [before] to [after]:
/// the attached ends go to the same spot on the box's edge. [was] is the
/// stroke as it was before this change (when it changed too, say because it
/// was moved along with the box); its ends say where they were on [before].
StrokeItem followBox(StrokeItem s, BoxItem before, BoxItem after, {StrokeItem? was}) {
  final old = (was ?? s).pageInk;
  final now = s.pageInk;
  if (old.isEmpty || now.isEmpty) return s;
  Offset shift(InkPoint oldEnd, InkPoint nowEnd) {
    final a = _anchor(before, Offset(oldEnd.x, oldEnd.y));
    return after.toPage(Offset(a.dx * after.w, a.dy * after.h)) - Offset(nowEnd.x, nowEnd.y);
  }

  final dStart = s.startItemId == before.id ? shift(old.first, now.first) : Offset.zero;
  final dEnd = s.endItemId == before.id ? shift(old.last, now.last) : Offset.zero;
  if (dStart.distance < 1e-6 && dEnd.distance < 1e-6) return s;
  return s.copyWith(pagePoints: rubberBand(now, dStart, dEnd));
}

/// Whether [s]'s attached end is still on [box]'s edge.
bool endOnEdge(StrokeItem s, BoxItem box, {required bool atStart, double tolerance = 1.5}) {
  final pts = s.pageInk;
  if (pts.isEmpty) return false;
  final p = atStart ? pts.first : pts.last;
  return distanceToOutline(box, Offset(p.x, p.y)) <= tolerance;
}
