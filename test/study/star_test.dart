import 'dart:math' as math;

import 'package:endless/board/model.dart';
import 'package:endless/study/star.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'shapes.dart';

void main() {
  group('looksLikeStar', () {
    test('a pentagram in one stroke, either way round, at any size', () {
      for (final r in [14.0, 30.0, 80.0]) {
        expect(looksLikeStar(pentagram(const Offset(200, 200), r)), isTrue, reason: 'r $r');
        expect(looksLikeStar(pentagram(const Offset(200, 200), r, clockwise: false)), isTrue, reason: 'ccw $r');
      }
    });

    test('with a wobbly hand', () {
      var found = 0;
      for (var seed = 0; seed < 50; seed++) {
        if (looksLikeStar(pentagram(const Offset(100, 100), 30, wobble: 0.06, seed: seed))) found++;
      }
      expect(found, greaterThanOrEqualTo(45));
    });

    // Owner, 2026-10-27: stars took a few tries on the tablet. Hand-drawn
    // ones round their tips, stop short of where they started, and wobble.
    test('as a hand draws it: rounded, open, uneven, hooked, an outline', () {
      final rand = math.Random(7);
      final kinds = <String, List<Offset> Function()>{
        'typical': () => handStar(rand),
        'very rounded': () => handStar(rand, round: 0.5),
        'stopping short': () => handStar(rand, gap: 0.35),
        'uneven': () => handStar(rand, jitter: 0.25),
        'with a hook': () => handStar(rand, hook: 6),
        'outline, rounded': () => handStar(rand, outline: true, round: 0.3),
        'messy': () => handStar(rand, round: 0.3, gap: 0.35, jitter: 0.2, hook: 4),
      };
      for (final e in kinds.entries) {
        var found = 0;
        for (var i = 0; i < 100; i++) {
          if (looksLikeStar(e.value())) found++;
        }
        expect(found, greaterThanOrEqualTo(95), reason: e.key);
      }
    });

    test('never real writing, letters with corners, or shapes gone round twice', () {
      final real = realStrokes();
      expect(real.length, greaterThan(100));
      expect([
        for (final s in real)
          if (s.length > 3 && looksLikeStar(s)) s,
      ], isEmpty);
      final rand = math.Random(3);
      List<Offset> poly(List<List<double>> c, {double s = 40}) {
        final pts = <Offset>[];
        for (var i = 0; i < c.length - 1; i++) {
          for (var t = 0; t < 12; t++) {
            pts.add(
              Offset(
                200 + s * (c[i][0] + (c[i + 1][0] - c[i][0]) * t / 12) + (rand.nextDouble() - .5),
                200 + s * (c[i][1] + (c[i + 1][1] - c[i][1]) * t / 12),
              ),
            );
          }
        }
        pts.add(Offset(200 + s * c.last[0], 200 + s * c.last[1]));
        return pts;
      }

      final negatives = {
        'W': [
          [0.0, 0.0],
          [0.25, 1.0],
          [0.5, 0.2],
          [0.75, 1.0],
          [1.0, 0.0],
        ],
        'M': [
          [0.0, 1.0],
          [0.2, 0.0],
          [0.5, 0.8],
          [0.8, 0.0],
          [1.0, 1.0],
        ],
        'N': [
          [0.0, 1.0],
          [0.0, 0.0],
          [0.8, 1.0],
          [0.8, 0.0],
        ],
        'Z': [
          [0.0, 0.0],
          [1.0, 0.0],
          [0.0, 1.0],
          [1.0, 1.0],
        ],
        '4': [
          [0.7, 1.0],
          [0.7, 0.0],
          [0.0, 0.7],
          [1.0, 0.7],
        ],
        'E': [
          [1.0, 0.0],
          [0.0, 0.0],
          [0.0, 0.5],
          [0.8, 0.5],
          [0.0, 0.5],
          [0.0, 1.0],
          [1.0, 1.0],
        ],
        'bolt': [
          [0.6, 0.0],
          [0.2, 0.55],
          [0.6, 0.45],
          [0.2, 1.0],
        ],
        'triangle twice': [
          [0.5, 0.0],
          [1.0, 1.0],
          [0.0, 1.0],
          [0.5, 0.0],
          [1.0, 1.0],
          [0.0, 1.0],
          [0.5, 0.05],
        ],
        'square': [
          [0.0, 0.0],
          [1.0, 0.0],
          [1.0, 1.0],
          [0.0, 1.0],
          [0.0, 0.05],
        ],
        'square and a bit': [
          [0.0, 0.0],
          [1.0, 0.0],
          [1.0, 1.0],
          [0.0, 1.0],
          [0.0, 0.0],
          [1.0, 0.0],
        ],
        'hexagon': [
          for (var k = 0; k <= 6; k++) [0.5 + 0.5 * math.cos(k * math.pi / 3), 0.5 + 0.5 * math.sin(k * math.pi / 3)],
        ],
        'zigzag': [
          for (var k = 0; k <= 8; k++) [k / 8, k.isEven ? 0.0 : 0.8],
        ],
        'spiral': [
          for (var k = 0; k <= 40; k++) [0.5 + k / 80 * math.cos(k / 3), 0.5 + k / 80 * math.sin(k / 3)],
        ],
      };
      for (final e in negatives.entries) {
        expect(looksLikeStar(poly(e.value)), isFalse, reason: e.key);
      }
    });

    test('its outline', () {
      expect(looksLikeStar(starOutline(const Offset(100, 100), 30)), isTrue);
    });

    test('not a circle, triangle, square, scribble or handwriting', () {
      expect(looksLikeStar(circle(const Offset(100, 100), 30)), isFalse);
      expect(looksLikeStar(polygon(const Offset(100, 100), 30, 3)), isFalse);
      expect(looksLikeStar(polygon(const Offset(100, 100), 30, 4)), isFalse);
      expect(looksLikeStar(zigzag(const Offset(100, 100), 60, 40, 6)), isFalse);
      expect(looksLikeStar(scrawl(const Offset(100, 100), 200)), isFalse);
    });

    test('not when it is too small on screen to be meant', () {
      expect(looksLikeStar(pentagram(const Offset(100, 100), 6)), isFalse);
      // The same star zoomed out to a quarter is big enough on the page.
      expect(looksLikeStar(pentagram(const Offset(100, 100), 14), unit: 0.25), isTrue);
    });

    test('not an open zig-zag that doesn’t come back', () {
      final open = pentagram(const Offset(100, 100), 30).sublist(0, 70);
      expect(looksLikeStar(open), isFalse);
    });
  });

  group('besideStar', () {
    StrokeItem ink(List<Offset> pts) => strokeFrom(pts);

    test('the line of writing to its left, not the lines above and below', () {
      final above = ink(scrawl(const Offset(40, 40), 200));
      final words = [ink(scrawl(const Offset(40, 100), 90)), ink(scrawl(const Offset(150, 100), 80))];
      final below = ink(scrawl(const Offset(40, 160), 200));
      final star = ink(pentagram(const Offset(280, 100), 16));
      final picked = besideStar(star, [above, ...words, below, star]);
      expect(picked.map((i) => i.id), unorderedEquals(words.map((w) => w.id)));
    });

    test('a circle around the words comes along (RememberMark.png)', () {
      final words = ink(scrawl(const Offset(150, 574), 100, size: 10));
      final ring = ink(circle(const Offset(204, 574), 60).map((p) => Offset(p.dx, 574 + (p.dy - 574) * 0.4)).toList());
      final star = ink(pentagram(const Offset(340, 574), 26));
      final picked = besideStar(star, [ring, words, star]);
      expect(picked.map((i) => i.id), unorderedEquals([ring.id, words.id]));
    });

    test('the nearer side wins', () {
      final left = ink(scrawl(const Offset(0, 100), 80));
      final right = ink(scrawl(const Offset(262, 100), 80));
      final star = ink(pentagram(const Offset(220, 100), 16));
      expect(besideStar(star, [left, right, star]).map((i) => i.id), [right.id]);
    });

    test('nothing when nothing is near', () {
      final far = ink(scrawl(const Offset(600, 100), 80));
      final star = ink(pentagram(const Offset(100, 100), 16));
      expect(besideStar(star, [far, star]), isEmpty);
    });

    test('not the frame it is drawn on, nor highlighter', () {
      final frame = FrameItem(id: 'f', x: 0, y: 0, z: 1, createdAt: testNow, w: 560, h: 792, paper: 'lined-a4');
      final words = ink(scrawl(const Offset(40, 100), 90));
      final marker = strokeFrom([const Offset(30, 100), const Offset(250, 100)], tool: InkTool.marker, width: 10);
      final star = ink(pentagram(const Offset(200, 100), 16));
      expect(besideStar(star, [frame, marker, words, star]).map((i) => i.id), [words.id]);
    });
  });
}
