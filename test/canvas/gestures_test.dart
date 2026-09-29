import 'dart:convert';
import 'dart:math' as math;
import 'package:endless/board/codec.dart';
import 'package:endless/board/model.dart';
import 'package:endless/canvas/gestures.dart';
import 'package:endless/canvas/selection.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

Matcher _near(Offset o, double d) => within(distance: d, from: o);

/// Points along [from]→[to] with a little hand wobble.
List<Offset> _line(Offset from, Offset to, {int n = 40, double wobble = 2, double jitter = 1, int seed = 1}) {
  final r = math.Random(seed);
  final d = to - from;
  final normal = Offset(-d.dy, d.dx) / d.distance;
  return [
    for (var i = 0; i <= n; i++)
      Offset.lerp(from, to, i / n)! + normal * (math.sin(i / n * math.pi * 3) * wobble + (r.nextDouble() - .5) * jitter),
  ];
}

List<Offset> _ellipse(Offset c, double rx, double ry, {double turns = 1.05, int n = 90, double wobble = 2}) {
  final r = math.Random(7);
  return [
    for (var i = 0; i <= n; i++)
      c +
          Offset(math.cos(i / n * turns * 2 * math.pi - 1.4) * (rx + (r.nextDouble() - .5) * wobble),
              math.sin(i / n * turns * 2 * math.pi - 1.4) * (ry + (r.nextDouble() - .5) * wobble)),
  ];
}

/// A closed polygon drawn by hand: every corner, then back to the start.
List<Offset> _polygon(List<Offset> corners, {double wobble = 1.5}) {
  final out = <Offset>[];
  for (var i = 0; i < corners.length; i++) {
    final seg = _line(corners[i], corners[(i + 1) % corners.length], n: 25, wobble: wobble, seed: i + 3);
    out.addAll(i == 0 ? seg : seg.skip(1));
  }
  return out;
}

/// Zig-zag from [from], [legs] legs of [amp] height, [step] apart.
List<Offset> _zigzag(Offset from, {int legs = 8, double amp = 34, double step = 13}) {
  final corners = [for (var i = 0; i <= legs; i++) from + Offset(i * step, i.isEven ? 0 : -amp)];
  final out = <Offset>[];
  for (var i = 0; i < legs; i++) {
    for (var s = 0; s < 8; s++) {
      out.add(Offset.lerp(corners[i], corners[i + 1], s / 8)!);
    }
  }
  return out..add(corners.last);
}

/// [main] followed by a straight hook to [hookTo].
List<Offset> _withHook(List<Offset> main, Offset hookTo, {int n = 6}) => [
      ...main,
      for (var i = 1; i <= n; i++) Offset.lerp(main.last, hookTo, i / n)!,
    ];

void main() {
  group('hold to straighten', () {
    test('a shaky line becomes a straight line with its angle', () {
      final fit = fitShape(_line(const Offset(40, 230), const Offset(344, 116), wobble: 4))!;
      expect(fit.kind, ShapeKind.line);
      expect(fit.points.first, _near(const Offset(40, 230), 1));
      expect(fit.points.last.dx, closeTo(344, 2));
      expect(fit.angle, 21); // the design's 20° line (atan(114/304))
    });

    test('a nearly level line snaps to 0°', () {
      final fit = fitShape(_line(const Offset(0, 0), const Offset(300, 8)))!;
      expect(fit.angle, 0);
      expect(fit.points.last.dy, closeTo(fit.points.first.dy, 0.01));
    });

    test('circles, ellipses, rectangles and triangles', () {
      expect(fitShape(_ellipse(const Offset(200, 200), 80, 76))!.kind, ShapeKind.circle);
      expect(fitShape(_ellipse(const Offset(200, 200), 140, 60))!.kind, ShapeKind.ellipse);
      final rect = fitShape(_polygon(const [Offset(0, 0), Offset(220, 4), Offset(218, 120), Offset(-2, 116)]))!;
      expect(rect.kind, ShapeKind.rect);
      // Squared up to the page: the top edge is level.
      expect(rect.points.first.dy, closeTo(rect.points[5].dy, 0.01));
      final tri = fitShape(_polygon(const [Offset(10, 176), Offset(300, 176), Offset(300, 36)]))!;
      expect(tri.kind, ShapeKind.triangle);
    });

    test('a rotated square stays rotated', () {
      final fit = fitShape(_polygon(const [Offset(100, 0), Offset(200, 100), Offset(100, 200), Offset(0, 100)]))!;
      expect(fit.kind, ShapeKind.rect);
      expect(fit.points.first.dx, isNot(closeTo(fit.points[5].dx, 5)));
    });

    test('open curves, scribbles and tiny marks are left alone', () {
      final arc = [for (var i = 0; i <= 40; i++) Offset(100 + 80 * math.cos(i / 40 * math.pi), 100 - 80 * math.sin(i / 40 * math.pi))];
      expect(fitShape(arc), isNull);
      expect(fitShape(_zigzag(const Offset(0, 0))), isNull);
      expect(fitShape(const [Offset(0, 0), Offset(3, 2), Offset(6, 1)]), isNull);
    });

    test('thresholds follow the zoom (unit = page px per screen px)', () {
      final small = _line(const Offset(0, 0), const Offset(20, 5), wobble: 0.3, jitter: 0.2);
      expect(fitShape(small), isNull); // 20 px on screen at 100%: too short
      expect(fitShape(small, unit: 0.25)!.kind, ShapeKind.line); // 80 px on screen at 400%
    });

    test('lineAngle is the acute angle to horizontal', () {
      expect(lineAngle(Offset.zero, const Offset(10, -10)), closeTo(45, 1e-9));
      expect(lineAngle(Offset.zero, const Offset(-10, -10)), closeTo(45, 1e-9));
      expect(lineAngle(Offset.zero, const Offset(0, 10)), closeTo(90, 1e-9));
    });
  });

  group('flick back for an arrow', () {
    final line = _line(const Offset(50, 230), const Offset(330, 120), n: 60, wobble: 1);

    test('a short hook at the end makes an end arrow and is trimmed off', () {
      // The design's flick: from the tip back and down (Arrows.dc.html).
      final pts = _withHook(line, const Offset(306, 138));
      final f = detectFlicks(pts)!;
      expect((f.start, f.end), (false, true));
      expect(f.from, 0);
      expect(pts[f.to], _near(line.last, 3));
    });

    test('hooks at both ends make a double-headed arrow', () {
      final main = _line(const Offset(300, 110), const Offset(540, 110), n: 60, wobble: 0.5);
      final pts = [
        for (var i = 0; i < 6; i++) Offset.lerp(const Offset(320, 96), main.first, i / 6)!,
        ...main,
        for (var i = 1; i <= 6; i++) Offset.lerp(main.last, const Offset(520, 124), i / 6)!,
      ];
      final f = detectFlicks(pts)!;
      expect((f.start, f.end), (true, true));
      expect(pts[f.from], _near(main.first, 3));
      expect(pts[f.to], _near(main.last, 3));
    });

    test('curves keep their curve', () {
      final curve = [
        for (var i = 0; i <= 60; i++)
          Offset(150 - 100 * math.cos(i / 60 * math.pi * 0.8), 300 - 180 * math.sin(i / 60 * math.pi * 0.8)),
      ];
      final end = curve.last, before = curve[curve.length - 4];
      final back = (before - end) / (before - end).distance;
      final pts = _withHook(curve, end + Offset(back.dx * 0.9 - back.dy * 0.4, back.dy * 0.9 + back.dx * 0.4) * 22);
      final f = detectFlicks(pts)!;
      expect(f.end, isTrue);
      expect(f.to, curve.length - 1);
    });

    test('zig-zags, check marks, long strokes back and plain lines stay ink', () {
      expect(detectFlicks(line), isNull);
      expect(detectFlicks(_zigzag(const Offset(0, 100))), isNull);
      // A check mark: short leg down, long leg up.
      final check = [
        ..._line(const Offset(0, 0), const Offset(14, 18), n: 8, wobble: 0.2),
        ..._line(const Offset(14, 18), const Offset(60, -50), n: 25, wobble: 0.2).skip(1),
      ];
      expect(detectFlicks(check), isNull);
      // Going a long way back along the line.
      expect(detectFlicks(_withHook(line, const Offset(200, 175), n: 30)), isNull);
      // Too short a line for an arrow.
      final short = _line(const Offset(0, 0), const Offset(30, 0), n: 10, wobble: 0.2);
      expect(detectFlicks(_withHook(short, const Offset(24, 5))), isNull);
    });

    test('a slow hook is deliberate ink, not a flick', () {
      final pts = _withHook(line, const Offset(306, 138));
      final fast = [for (var i = 0; i < pts.length; i++) i * 8];
      expect(detectFlicks(pts, times: fast), isNotNull);
      final slow = [for (var i = 0; i < pts.length; i++) i < line.length ? i * 8 : line.length * 8 + (i - line.length + 1) * 150];
      expect(detectFlicks(pts, times: slow), isNull);
    });
  });

  group('scribble to erase', () {
    // "oops" (two strokes) under a zig-zag, next to "Δt" (Scribble.dc.html).
    final oops = strokeFrom([for (var i = 0; i <= 30; i++) Offset(230 + i * 2.0, 140 + 8 * math.sin(i / 3))]);
    final oops2 = strokeFrom([for (var i = 0; i <= 12; i++) Offset(262 + i * 2.0, 145 + 6 * math.cos(i / 2))]);
    final delta = strokeFrom(_polygon(const [Offset(170, 150), Offset(190, 120), Offset(205, 150)]));
    final zig = _zigzag(const Offset(222, 158), legs: 8, amp: 34, step: 13);

    test('a zig-zag counts its back-and-forth strokes', () {
      expect(countCusps(zig), 7);
      expect(countCusps(_line(const Offset(0, 0), const Offset(200, 50))), 0);
    });

    test('sensitivity: Light, Normal and Firm', () {
      final two = _zigzag(Offset.zero, legs: 4);
      final three = _zigzag(Offset.zero, legs: 6);
      expect(looksLikeScribble(two, ScribbleLevel.light), isTrue);
      expect(looksLikeScribble(two, ScribbleLevel.normal), isFalse);
      expect(looksLikeScribble(three, ScribbleLevel.normal), isTrue);
      expect(looksLikeScribble(zig, ScribbleLevel.firm), isFalse);
      final dense = _zigzag(Offset.zero, legs: 12, amp: 40, step: 4);
      expect(looksLikeScribble(dense, ScribbleLevel.firm), isTrue);
    });

    test('only the strokes under the scribble are erased', () {
      final hit = scribbleTargets(zig, [oops, oops2, delta]);
      expect(hit, containsAll([oops, oops2]));
      expect(hit, isNot(contains(delta)));
    });

    test('a long line the scribble only clips is safe', () {
      // The incline's long edge, with the scribble sitting on it.
      final incline = strokeFrom(_line(const Offset(10, 176), const Offset(300, 36), n: 80, wobble: 0));
      final onEdge = _zigzag(const Offset(200, 90), legs: 6, amp: 30, step: 10);
      expect(scribbleTargets(onEdge, [incline]), isEmpty);
    });

    test('shading over empty paper erases nothing', () {
      expect(scribbleTargets(_zigzag(const Offset(600, 600)), [oops, oops2, delta]), isEmpty);
    });
  });

  group('moving a selection', () {
    test('a similarity scales and turns about its pivot, and composes', () {
      final t = Similarity.about(const Offset(100, 100), scale: 2, rotation: math.pi / 2);
      expect(t.apply(const Offset(100, 100)), _near(const Offset(100, 100), 1e-9));
      expect(t.apply(const Offset(110, 100)), _near(const Offset(100, 120), 1e-9));
      final both = t.then(const Similarity.translate(Offset(5, 0)));
      expect(both.apply(const Offset(110, 100)), _near(const Offset(105, 120), 1e-9));
      final s = strokeFrom(const [Offset(100, 100), Offset(110, 100)]);
      final moved = t.applyTo(s);
      expect(moved.id, s.id);
      expect(moved.width, s.width * 2);
      expect(moved.pagePoints.last, _near(const Offset(100, 120), 0.1));
    });
  });

  group('lasso', () {
    test('selects items at least half inside the loop', () {
      final loop = _ellipse(const Offset(200, 150), 140, 60, turns: 1);
      final inside = strokeFrom(_line(const Offset(120, 150), const Offset(280, 150)));
      final half = strokeFrom(_line(const Offset(220, 150), const Offset(420, 150)));
      final outside = strokeFrom(_line(const Offset(500, 150), const Offset(600, 150)));
      final picked = itemsInPolygon(loop, [inside, half, outside]);
      expect(picked, contains(inside));
      expect(picked, isNot(contains(outside)));
      expect(insidePolygon(const Offset(200, 150), loop), isTrue);
      expect(insidePolygon(const Offset(400, 150), loop), isFalse);
    });
  });

  group('stroke model', () {
    test('arrows and straightened shapes round-trip and grow the bounds', () {
      final s = strokeFrom(_line(const Offset(0, 0), const Offset(100, 0)));
      final a = s.copyWith(arrow: () => const ArrowHeads(end: true, style: ArrowStyle.filled), shape: () => 'line');
      expect(a.id, s.id);
      expect(a.toJson()['arrow'], {'end': true, 'style': 'filled'});
      expect(a.toJson()['straightened'], 'line');
      expect(a.bounds.right, greaterThan(s.bounds.right));
      expect(ArrowHeads.fromJson(a.toJson()['arrow']), a.arrow);
      final back = decodeItem(jsonDecode(a.encoded) as Map<String, dynamic>) as StrokeItem;
      expect(back.arrow, a.arrow);
      expect(back.straightened, 'line');
      expect(back.extra, isEmpty); // known fields, not kept as unknown
      expect(ArrowHeads.fromJson({'style': 'open'}), isNull);
    });
  });
}
