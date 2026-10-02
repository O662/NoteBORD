import 'dart:convert';
import 'dart:math' as math;

import 'package:endless/board/codec.dart';
import 'package:endless/board/model.dart';
import 'package:endless/canvas/connectors.dart';
import 'package:endless/canvas/new_items.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

final _at = DateTime.utc(2026, 10, 1, 12);

ShapeItem _box(String id, Rect r, {ShapeType kind = ShapeType.rect, double rotation = 0}) => ShapeItem(
      id: id,
      x: r.left,
      y: r.top,
      rotation: rotation,
      z: 1,
      createdAt: _at,
      kind: kind,
      w: r.width,
      h: r.height,
      stroke: tokens.inkDefaults[0],
    );

List<Offset> _line(Offset a, Offset b, {int n = 40}) => [for (var i = 0; i <= n; i++) Offset.lerp(a, b, i / n)!];

/// A stroke along [pts] that ends in an arrowhead, like a flick makes.
StrokeItem _arrow(List<Offset> pts) =>
    strokeFrom(pts, width: 3.5).copyWith(arrow: () => const ArrowHeads(end: true));

void main() {
  final a = _box('it_a', const Rect.fromLTWH(100, 100, 120, 80)); // right edge at x = 220
  final b = _box('it_b', const Rect.fromLTWH(400, 200, 120, 80)); // left edge at x = 400

  group('attaching', () {
    test('an arrow from inside one box into another joins both, cut back to their edges', () {
      final s = attachEnds(_arrow(_line(const Offset(160, 140), const Offset(460, 240))), [a, b], slop: 16);
      expect(s.startItemId, 'it_a');
      expect(s.endItemId, 'it_b');
      final first = s.pagePoints.first, last = s.pagePoints.last;
      expect(distanceToOutline(a, first), lessThan(0.1));
      expect(distanceToOutline(b, last), lessThan(0.1));
      expect(first.dx, closeTo(220, 0.2)); // where the line leaves A's right edge
      expect(last.dx, closeTo(400, 0.2)); // where it meets B's left edge
      // Nothing is left inside either box.
      expect(s.pagePoints.where((p) => insideOutline(a, a.toLocal(p)) && distanceToOutline(a, p) > 0.1), isEmpty);
      expect(s.arrow, const ArrowHeads(end: true));
    });

    test('an end that stops just short of an edge moves onto it; one further off stays free', () {
      final near = attachEnds(_arrow(_line(const Offset(250, 140), const Offset(390, 240))), [a, b], slop: 16);
      expect(near.startItemId, isNull); // 30 px from A
      expect(near.endItemId, 'it_b');
      expect(near.pagePoints.last, const Offset(400, 240));
      expect(near.pagePoints.first, const Offset(250, 140)); // the other end stays put

      final far = attachEnds(_arrow(_line(const Offset(250, 140), const Offset(370, 240))), [a, b], slop: 16);
      expect(far.isAttached, isFalse);
      expect(far.pagePoints.last, const Offset(370, 240));
    });

    test('a line drawn on a frame or a picture is writing on it, not a connector', () {
      final frame = newFrame(const Offset(400, 100), z: 0, now: _at); // 120…680 × 100…892
      final onSheet = attachEnds(_arrow(_line(const Offset(200, 300), const Offset(500, 400))), [frame], slop: 16);
      expect(onSheet.isAttached, isFalse);
      expect(onSheet.points, hasLength(41));
      // From the sheet out to a box: the box end joins; the sheet end only if it's at its edge.
      final out = attachEnds(_arrow(_line(const Offset(600, 300), const Offset(760, 300))), [
        frame,
        _box('it_c', const Rect.fromLTWH(740, 260, 100, 80)),
      ], slop: 16);
      expect((out.startItemId, out.endItemId), (null, 'it_c'));
      final fromEdge = attachEnds(_arrow(_line(const Offset(672, 300), const Offset(760, 300))), [
        frame,
        _box('it_c', const Rect.fromLTWH(740, 260, 100, 80)),
      ], slop: 16);
      expect(fromEdge.startItemId, frame.id);
      expect(fromEdge.pagePoints.first.dx, closeTo(680, 0.01));
    });

    test('the topmost box wins, ovals and turned boxes are met on their real edge', () {
      final under = _box('it_under', const Rect.fromLTWH(380, 180, 200, 140));
      final s = attachEnds(_arrow(_line(const Offset(160, 140), const Offset(460, 240))), [a, under, b], slop: 16);
      expect(s.endItemId, 'it_b');

      final oval = _box('it_oval', const Rect.fromLTWH(400, 200, 160, 80), kind: ShapeType.ellipse);
      final o = attachEnds(_arrow(_line(const Offset(300, 120), const Offset(470, 230))), [oval], slop: 16);
      expect(o.endItemId, 'it_oval');
      expect(distanceToOutline(oval, o.pagePoints.last), lessThan(0.1));
      expect(insideOutline(oval, oval.toLocal(o.pagePoints.last + const Offset(-2, -2))), isFalse);

      final turned = _box('it_t', const Rect.fromLTWH(400, 200, 120, 80), rotation: 30);
      final t = attachEnds(_arrow(_line(const Offset(250, 240), const Offset(460, 240))), [turned], slop: 16);
      expect(t.endItemId, 'it_t');
      expect(distanceToOutline(turned, t.pagePoints.last), lessThan(0.1));
    });

    test('ends can be tried one at a time; an end that finds nothing lets go', () {
      final both = attachEnds(_arrow(_line(const Offset(160, 140), const Offset(460, 240))), [a, b], slop: 16);
      final moved = both.copyWith(pagePoints: [...both.pageInk.take(both.points.length - 1), const InkPoint(700, 600, 0.5, 0)]);
      final freed = attachEnds(moved, [a, b], slop: 16, start: false);
      expect(freed.startItemId, 'it_a');
      expect(freed.endItemId, isNull);
      expect(freed.pagePoints.first, both.pagePoints.first);
    });
  });

  group('following', () {
    final s = attachEnds(_arrow(_line(const Offset(160, 140), const Offset(460, 240))), [a, b], slop: 16);

    test('a moved box takes its end along; the other end and a straight line stay as they are', () {
      final movedB = b.withBox(x: 450, y: 300, w: b.w, h: b.h);
      final f = followBox(s, b, movedB);
      expect(f.pagePoints.last, offsetMoreOrLessEquals(s.pagePoints.last + const Offset(50, 100), epsilon: 0.15));
      expect(f.pagePoints.first, offsetMoreOrLessEquals(s.pagePoints.first, epsilon: 0.15));
      final p0 = f.pagePoints.first, p1 = f.pagePoints.last;
      for (final p in f.pagePoints) {
        final d = p1 - p0;
        expect(((p - p0).dx * d.dy - (p - p0).dy * d.dx).abs() / d.distance, lessThan(0.2)); // still straight
      }
      expect((f.startItemId, f.endItemId), ('it_a', 'it_b'));
    });

    test('a resized or turned box keeps the end on the same spot of its edge', () {
      final wide = b.withBox(x: 300, y: 200, w: 220, h: 160); // its left edge moved left, and it grew down
      final f = followBox(s, b, wide);
      expect(f.pagePoints.last.dx, closeTo(300, 0.15));
      final fraction = (s.pagePoints.last.dy - 200) / 80;
      expect(f.pagePoints.last.dy, closeTo(200 + fraction * 160, 0.15));

      final turned = b.withBox(x: b.x, y: b.y, w: b.w, h: b.h, rotation: 90);
      expect(distanceToOutline(turned, followBox(s, b, turned).pagePoints.last), lessThan(0.15));
    });

    test('the rubber band bends a curve without moving the far end', () {
      final curve = [for (var i = 0; i <= 20; i++) InkPoint(i * 10.0, math.sin(i / 3) * 20, 0.5, i)];
      final bent = rubberBand(curve, Offset.zero, const Offset(0, 40));
      expect(Offset(bent.first.x, bent.first.y), Offset(curve.first.x, curve.first.y));
      expect(bent.last.y, closeTo(curve.last.y + 40, 1e-9));
      expect(bent[10].y, closeTo(curve[10].y + 20, 3)); // about halfway along, about half the move
    });
  });

  test('attachments are saved on the stroke and read back', () {
    final s = attachEnds(_arrow(_line(const Offset(160, 140), const Offset(460, 240))), [a, b], slop: 16);
    final json = jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>;
    expect((json['startItemId'], json['endItemId']), ('it_a', 'it_b'));
    final back = decodeItem(json) as StrokeItem;
    expect((back.startItemId, back.endItemId), ('it_a', 'it_b'));
    final free = jsonDecode(jsonEncode(strokeFrom(_line(Offset.zero, const Offset(10, 10))).toJson())) as Map;
    expect(free.containsKey('startItemId'), isFalse);
    expect(s.bounds.inflate(-1).contains(s.pagePoints.first + Offset(-s.attachDotRadius + 1.5, 0)), isTrue);
  });
}
