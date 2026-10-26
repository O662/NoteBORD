import 'dart:math' as math;
import 'dart:ui';

// Pen shapes for the star tests.

/// A five-pointed star in one stroke through its tips (0, 2, 4, 1, 3),
/// [r] across, with a little wobble, starting at the top tip.
List<Offset> pentagram(Offset c, double r, {double wobble = 0.03, bool clockwise = true, int seed = 1}) {
  final rand = math.Random(seed);
  final tips = [
    for (var k = 0; k < 5; k++)
      c + Offset.fromDirection((-90 + (clockwise ? 1 : -1) * 144.0 * k) * math.pi / 180, r),
    c + Offset.fromDirection(-90 * math.pi / 180, r),
  ];
  return [
    for (var i = 0; i < 5; i++)
      for (var t = 0; t < 20; t++)
        Offset.lerp(tips[i], tips[i + 1], t / 20)! + Offset(rand.nextDouble() - 0.5, rand.nextDouble() - 0.5) * r * wobble,
    tips.last,
  ];
}

/// The star's outline (10 corners, not crossing itself).
List<Offset> starOutline(Offset c, double r) {
  final corners = [
    for (var k = 0; k <= 10; k++) c + Offset.fromDirection((-90 + 36.0 * k) * math.pi / 180, k.isEven ? r : r * 0.42),
  ];
  return [
    for (var i = 0; i < 10; i++)
      for (var t = 0; t < 10; t++) Offset.lerp(corners[i], corners[i + 1], t / 10)!,
    corners.last,
  ];
}

List<Offset> circle(Offset c, double r) => [
      for (var i = 0; i <= 80; i++) c + Offset.fromDirection(i / 80 * 2 * math.pi, r),
    ];

List<Offset> zigzag(Offset from, double w, double h, int n) => [
      for (var i = 0; i <= n * 10; i++)
        Offset(from.dx + w * ((i ~/ 10).isEven ? (i % 10) / 10 : 1 - (i % 10) / 10), from.dy + h * i / (n * 10)),
    ];

List<Offset> polygon(Offset c, double r, int sides) {
  final corners = [
    for (var k = 0; k <= sides; k++) c + Offset.fromDirection((-90 + 360.0 / sides * k) * math.pi / 180, r),
  ];
  return [
    for (var i = 0; i < sides; i++)
      for (var t = 0; t < 15; t++) Offset.lerp(corners[i], corners[i + 1], t / 15)!,
    corners.last,
  ];
}

List<Offset> scrawl(Offset from, double length, {double size = 14}) => [
      for (var i = 0; i <= 220; i++)
        Offset(from.dx + length * i / 220 + size * 0.5 * math.cos(i / 6), from.dy + size * math.sin(i / 6) * 0.9),
    ];
