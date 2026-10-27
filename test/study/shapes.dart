import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:endless/board/codec.dart';
import 'package:endless/board/model.dart';

// Pen shapes for the star tests.

/// A five-pointed star in one stroke through its tips (0, 2, 4, 1, 3),
/// [r] across, with a little wobble, starting at the top tip.
List<Offset> pentagram(Offset c, double r, {double wobble = 0.03, bool clockwise = true, int seed = 1}) {
  final rand = math.Random(seed);
  final tips = [
    for (var k = 0; k < 5; k++) c + Offset.fromDirection((-90 + (clockwise ? 1 : -1) * 144.0 * k) * math.pi / 180, r),
    c + Offset.fromDirection(-90 * math.pi / 180, r),
  ];
  return [
    for (var i = 0; i < 5; i++)
      for (var t = 0; t < 20; t++)
        Offset.lerp(tips[i], tips[i + 1], t / 20)! +
            Offset(rand.nextDouble() - 0.5, rand.nextDouble() - 0.5) * r * wobble,
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

/// A hand-drawn star: tips rounded by [round] (share of r), arms ±[jitter],
/// the end stopping [gap] (share of the diagonal) short of the start,
/// [hook] px of landing hook, drawn as a pentagram or its outline.
List<Offset> handStar(
  math.Random rand, {
  double r = 25,
  double round = 0.12,
  double jitter = 0.12,
  double gap = 0.2,
  double hook = 0,
  bool outline = false,
  double angle = 0,
}) {
  final start = -90 + angle + (rand.nextDouble() - 0.5) * 20;
  final corners = <Offset>[];
  if (outline) {
    for (var k = 0; k < 10; k++) {
      final rr = (k.isEven ? r : r * 0.42) * (1 + (rand.nextDouble() - 0.5) * 2 * jitter);
      corners.add(Offset.fromDirection((start + 36.0 * k + (rand.nextDouble() - 0.5) * 12) * math.pi / 180, rr));
    }
  } else {
    for (var k = 0; k < 5; k++) {
      final rr = r * (1 + (rand.nextDouble() - 0.5) * 2 * jitter);
      corners.add(Offset.fromDirection((start + 144.0 * k + (rand.nextDouble() - 0.5) * 16) * math.pi / 180, rr));
    }
  }
  corners.add(corners.first);
  // Straight runs between corners, the corners rounded (chaikin-ish).
  final pts = <Offset>[];
  for (var i = 0; i < corners.length - 1; i++) {
    final a = corners[i], b = corners[i + 1];
    final n = 18;
    for (var t = 0; t < n; t++) {
      pts.add(Offset.lerp(a, b, t / n)! + Offset(rand.nextDouble() - 0.5, rand.nextDouble() - 0.5) * r * 0.03);
    }
  }
  pts.add(corners.last);
  var out = pts;
  final rounds = (round * 10).round();
  for (var k = 0; k < rounds; k++) {
    out = [out.first, for (var i = 1; i < out.length - 1; i++) (out[i - 1] + out[i] * 2 + out[i + 1]) / 4, out.last];
  }
  // Stop short of the start.
  final diag = r * 2 * 1.4;
  var cut = 0.0;
  while (out.length > 10 && cut < gap * diag) {
    cut += (out.last - out[out.length - 2]).distance;
    out.removeLast();
  }
  if (hook > 0) {
    final d = out.last - out[out.length - 3];
    final back = Offset(-d.dy, d.dx) / (d.distance == 0 ? 1 : d.distance) * hook;
    out = [...out, out.last + back * 0.5, out.last + back];
  }
  return [for (final p in out) p + const Offset(200, 200)];
}

/// Every stroke of real writing in the fixtures: the owner's page from the
/// tablet (2026-10-15) and MathWriting's handwritten math.
List<List<Offset>> realStrokes() {
  final out = <List<Offset>>[];
  final page = decodePage(File('test/fixtures/recognition/tablet_2026-10-15.json').readAsStringSync());
  for (final i in page.items) {
    if (i is StrokeItem) out.add(i.pagePoints.toList());
  }
  for (final s
      in (jsonDecode(File('test/fixtures/math/ink_samples.json').readAsStringSync()) as List)
          .cast<Map<String, dynamic>>()) {
    for (final stroke in s['strokes'] as List) {
      out.add([for (final p in stroke as List) Offset((p[0] as num).toDouble(), (p[1] as num).toDouble())]);
    }
  }
  return out;
}
