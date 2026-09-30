import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Size;
import 'package:endless/board/codec.dart';
import 'package:endless/board/model.dart';
import 'package:endless/canvas/gestures.dart';
import 'package:endless/canvas/ruler.dart';
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

    /// A pen-like line: it slows into a rounded tip of [radius], turns back
    /// by [180 - fold]°, and flicks [hook] px, curving by [curl]°.
    (List<Offset>, List<int>) penFlick({
      Offset from = const Offset(50, 300),
      double heading = -20,
      double length = 250,
      double hook = 22,
      double fold = 25,
      double radius = 3,
      double curl = 0,
      double side = 1,
      int seed = 1,
    }) {
      final r = math.Random(seed);
      final pts = <Offset>[];
      final times = <int>[];
      var t = 0;
      var p = from;
      var a = heading * math.pi / 180;
      void step(double len, int ms) {
        p += Offset(math.cos(a), math.sin(a)) * len + Offset(r.nextDouble() - .5, r.nextDouble() - .5) * 0.4;
        pts.add(p);
        t += ms;
        times.add(t);
      }

      pts.add(p);
      times.add(0);
      // The line, slowing down near its end.
      for (var d = 0.0; d < length;) {
        final len = d > length - 20 ? 1.5 : 5.0;
        step(len, 4);
        d += len;
      }
      // Round the tip: turn by 180 - fold degrees along a small arc.
      final turn = (180 - fold) * math.pi / 180 * side;
      final arcLen = math.max(radius * (180 - fold) * math.pi / 180, 0.1);
      final n = math.max(1, (arcLen / 1).round());
      for (var i = 0; i < n; i++) {
        a += turn / n;
        step(arcLen / n, 4);
      }
      // The flick, fast, curling a little.
      final m = (hook / 3).round();
      for (var i = 0; i < m; i++) {
        a += curl * math.pi / 180 / m * side;
        step(hook / m, 4);
      }
      return (pts, times);
    }

    test('pen-like flicks: rounded tips, curved hooks, either side', () {
      for (final (radius, curl, side) in [(0.0, 0.0, 1.0), (3.0, 0.0, 1.0), (5.0, 15.0, -1.0), (4.0, -20.0, 1.0)]) {
        final (pts, times) = penFlick(radius: radius, curl: curl, side: side);
        final f = detectFlicks(pts, times: times);
        expect(f, isNotNull, reason: 'radius $radius, curl $curl');
        expect((f!.start, f.end), (false, true));
      }
    });

    test('twenty flicks of all kinds make twenty arrows that point forward', () {
      final r = math.Random(42);
      for (var k = 0; k < 20; k++) {
        final heading = r.nextDouble() * 360 - 180;
        final (pts, times) = penFlick(
          heading: heading,
          length: 120 + r.nextDouble() * 300,
          hook: 12 + r.nextDouble() * 24,
          fold: 5 + r.nextDouble() * 50,
          radius: r.nextDouble() * 5,
          curl: r.nextDouble() * 30 - 15,
          side: r.nextBool() ? 1 : -1,
          seed: k,
        );
        final f = detectFlicks(pts, times: times);
        expect(f, isNotNull, reason: 'flick $k');
        expect((f!.start, f.end), (false, true), reason: 'flick $k');
        // What's kept ends heading the way the line went.
        final kept = pts.sublist(f.from, f.to + 1);
        final h = heading * math.pi / 180;
        final lastBit = kept.last - kept[kept.length - 6];
        expect(lastBit.dx * math.cos(h) + lastBit.dy * math.sin(h), greaterThan(0), reason: 'flick $k');
      }
    });

    test('a backswing as the pen lands is not an arrow; a real barb is', () {
      final line = _line(const Offset(100, 300), const Offset(400, 300), n: 60, wobble: 0.5);
      // Lands, goes back 8 px along the line, then draws forward.
      final swing = [
        for (var i = 0; i <= 4; i++) Offset(100 + 8 - i * 2.0, 300),
        for (var i = 0; i <= 3; i++) Offset(100 + i * 2.7, 300),
        ...line.skip(2),
      ];
      expect(detectFlicks(swing), isNull);
      // A longer swing straight back along the line: still not a barb.
      final long = [for (var i = 0; i <= 8; i++) Offset(100 + 20 - i * 2.5, 300.3), ...line];
      expect(detectFlicks(long), isNull);
      // A barb 30° off the line, drawn into the tip first: an arrowhead at the start.
      final barb = [for (var i = 0; i <= 6; i++) Offset.lerp(const Offset(117, 290), line.first, i / 6)!, ...line.skip(1)];
      final f = detectFlicks(barb)!;
      expect((f.start, f.end), (true, false));
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
      final one = _zigzag(Offset.zero, legs: 2); // 1 back-and-forth
      final two = _zigzag(Offset.zero, legs: 3);
      final three = _zigzag(Offset.zero, legs: 4);
      expect(looksLikeScribble(one, ScribbleLevel.light), isFalse);
      expect(looksLikeScribble(two, ScribbleLevel.light), isTrue);
      expect(looksLikeScribble(two, ScribbleLevel.normal), isFalse);
      expect(looksLikeScribble(three, ScribbleLevel.normal), isTrue);
      expect(looksLikeScribble(zig, ScribbleLevel.firm), isFalse); // not dense enough
      final dense = _zigzag(Offset.zero, legs: 6, amp: 40, step: 4);
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

  group('ruler', () {
    Ruler shown() => Ruler()..show(const Size(1280, 800));

    test('angles are counter-clockwise and signed; fingers settle on whole degrees', () {
      final r = shown();
      r.rotateAbout(r.center, -20.4 * math.pi / 180); // fingers turn it up to the right
      expect(r.degrees, closeTo(20, 1e-9));
      r.rotateAbout(r.center, 30 * math.pi / 180); // on down past level
      expect(r.degrees, closeTo(-10, 1e-9));
      r.rotateAbout(r.center, -53.5 * math.pi / 180); // 43.5°: close to 45, it settles there
      expect(r.degrees, closeTo(45, 1e-9));
    });

    test('an exact angle, to three decimals', () {
      final r = shown()..setDegrees(22.125);
      expect(r.degrees, closeTo(22.125, 1e-9));
      expect(formatDegrees(r.degrees), '22.125°');
      expect(formatDegrees(-8), '−8°');
      expect(formatDegrees(30.5), '30.5°');
      r.setDegrees(180);
      expect(r.degrees, closeTo(180, 1e-9));
    });

    test('length stays between 240 and 2400; the chip is a big target', () {
      final r = shown()..resizeBy(10);
      expect(r.length, Ruler.maxLength);
      r.resizeBy(0.01);
      expect(r.length, Ruler.minLength);
      expect(r.chipContains(r.center + const Offset(40, 20)), isTrue);
      expect(r.chipContains(r.center + const Offset(100, 0)), isFalse);
      expect(r.contains(r.center + const Offset(100, 0)), isTrue);
    });

    test('dragging an end swings and stretches it about the other end', () {
      final r = shown(); // center (640, 496), 620 long: ends at x 330 and 950
      expect(r.endAt(const Offset(930, 496)), 1);
      expect(r.endAt(const Offset(350, 496)), -1);
      expect(r.endAt(const Offset(640, 496)), isNull);
      expect(r.endAt(const Offset(930, 560)), isNull); // off the ruler

      // Grab the right end 20 px in, pull it up and out to 30°.
      r.grabEnd(1, const Offset(930, 496));
      final target = const Offset(330, 496) + Offset(math.cos(-math.pi / 6), math.sin(-math.pi / 6)) * 780;
      r.dragEnd(target + const Offset(0.3, 0.4)); // a hair off: it settles on 30°
      r.releaseEnd();
      expect(r.degrees, closeTo(30, 1e-9));
      expect(r.length, closeTo(800, 0.5)); // 780 to the finger + the 20 px it was grabbed in
      final left = r.center - Offset(math.cos(r.angle), math.sin(r.angle)) * (r.length / 2);
      expect(left.dx, closeTo(330, 0.01));
      expect(left.dy, closeTo(496, 0.01));

      // The left end, dragged in close, shortens it, down to the minimum.
      final right = r.center + Offset(math.cos(r.angle), math.sin(r.angle)) * (r.length / 2);
      r.grabEnd(-1, left + Offset(math.cos(r.angle), math.sin(r.angle)) * 10);
      r.dragEnd(right - Offset(math.cos(r.angle), math.sin(r.angle)) * 100);
      expect(r.length, Ruler.minLength);
      final newRight = r.center + Offset(math.cos(r.angle), math.sin(r.angle)) * (r.length / 2);
      expect(newRight.dx, closeTo(right.dx, 0.01));
      expect(newRight.dy, closeTo(right.dy, 0.01));
    });

    test('units read the page: an inch is 160 px', () {
      expect(RulerUnit.inch.format(240), '1.50 in');
      expect(RulerUnit.cm.format(160 / 2.54 * 4.2), '4.2 cm');
      expect(RulerUnit.mm.format(160 / 2.54 * 4.2), '42 mm');
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
