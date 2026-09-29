import 'dart:ui';

import 'package:endless/board/model.dart';
import 'package:endless/canvas/canvas_view.dart';
import 'package:endless/canvas/page_runtime.dart';
import 'package:endless/canvas/spatial_index.dart';
import 'package:endless/canvas/stroke_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

Rect _outline(List<Offset> pts, double pressure, {bool usePressure = true, PenType type = PenType.ballpoint}) =>
    strokeOutline(
      points: pts,
      pressures: List.filled(pts.length, pressure),
      width: 4,
      penType: type,
      usePressure: usePressure,
    ).getBounds();

void main() {
  final line = [for (var x = 0; x <= 100; x += 5) Offset(x.toDouble(), 50)];

  group('stroke outline', () {
    test('a single tap is a dot', () {
      final b = _outline([const Offset(10, 10)], 0.5);
      expect(b.center.dx, closeTo(10, 0.01));
      expect(b.width, closeTo(4, 0.1)); // width 4 × factor 1 at medium pressure
    });

    test('pressure changes thickness', () {
      final light = _outline(line, 0.1).height;
      final medium = _outline(line, 0.5).height;
      final hard = _outline(line, 1.0).height;
      expect(light, lessThan(medium));
      expect(medium, lessThan(hard));
      expect(medium, closeTo(4, 0.2));
    });

    test('with pressure off the width is constant', () {
      expect(_outline(line, 0.1, usePressure: false).height, closeTo(_outline(line, 1.0, usePressure: false).height, 0.01));
    });

    test('the fountain pen varies more than the pencil', () {
      final fountain = _outline(line, 1.0, type: PenType.fountain).height / _outline(line, 0.1, type: PenType.fountain).height;
      final pencil = _outline(line, 1.0, type: PenType.pencil).height / _outline(line, 0.1, type: PenType.pencil).height;
      expect(fountain, greaterThan(pencil));
    });

    test('caps extend past both ends', () {
      final b = _outline(line, 0.5);
      expect(b.left, closeTo(-2, 0.3));
      expect(b.right, closeTo(102, 0.3));
    });

    test('a sharp V is filled at the tip', () {
      final v = [
        for (var i = 0; i <= 10; i++) Offset(i * 5.0, i * 10.0),
        for (var i = 9; i >= 0; i--) Offset(100 - i * 5.0, i * 10.0),
      ];
      final path = strokeOutline(
          points: v, pressures: List.filled(v.length, 0.5), width: 6, penType: PenType.ballpoint, usePressure: true);
      expect(path.contains(const Offset(50, 99)), isTrue);
      expect(path.contains(const Offset(50, 60)), isFalse);
    });
  });

  group('eraser hit test', () {
    test('segment distance', () {
      expect(segmentDistance(const Offset(0, 0), const Offset(10, 0), const Offset(5, -5), const Offset(5, 5)), 0);
      expect(segmentDistance(const Offset(0, 0), const Offset(10, 0), const Offset(0, 3), const Offset(10, 3)), 3);
      expect(segmentDistance(const Offset(0, 0), const Offset(0, 0), const Offset(3, 4), const Offset(3, 4)), 5);
    });

    test('hits strokes within reach and misses others', () {
      final s = strokeFrom(line, width: 2);
      expect(strokeHit(s, const Offset(50, 40), const Offset(50, 60), 1), isTrue); // crosses it
      // 4 px away; reach is the eraser radius plus half the widest stroke (3 + 1.8).
      expect(strokeHit(s, const Offset(50, 46), const Offset(60, 46), 3), isTrue);
      expect(strokeHit(s, const Offset(50, 30), const Offset(60, 30), 3), isFalse);
    });
  });

  group('spatial index', () {
    test('finds items by area, across cells and negative coordinates', () {
      final index = SpatialIndex()
        ..insert('a', const Rect.fromLTWH(0, 0, 10, 10))
        ..insert('b', const Rect.fromLTWH(-2000, -900, 3000, 20))
        ..insert('c', const Rect.fromLTWH(5000, 5000, 10, 10));
      expect(index.query(const Rect.fromLTWH(-5, -5, 20, 20)), {'a'});
      expect(index.query(const Rect.fromLTWH(-1500, -895, 1, 1)), {'b'});
      expect(index.query(const Rect.fromLTWH(4990, 4990, 30, 30)), {'c'});
      index.remove('c');
      expect(index.query(const Rect.fromLTWH(4990, 4990, 30, 30)), isEmpty);
      expect(index.length, 2);
    });

    test('a page runtime indexes items and tracks bounds', () {
      final page = PageRuntime(BoardPage(id: 'p'));
      expect(page.contentBounds, isNull);
      final s = strokeFrom(line);
      page.insert(s);
      expect(page.index.query(const Rect.fromLTWH(40, 40, 20, 20)), {s.id});
      expect(page.contentBounds!.contains(const Offset(50, 50)), isTrue);
      final removed = page.remove(s.id)!;
      expect(removed.$1, 0);
      expect(page.contentBounds, isNull);
      expect(page.revision, 2);
    });
  });

  group('canvas view', () {
    CanvasView view() => CanvasView()..size = const Size(1280, 800);

    test('screen and page coordinates are inverses', () {
      final v = view()
        ..panBy(const Offset(30, -40))
        ..zoomAt(const Offset(200, 200), 2);
      const p = Offset(123, 456);
      expect(v.toPage(v.toScreen(p)).dx, closeTo(p.dx, 1e-9));
      expect(v.toPage(v.toScreen(p)).dy, closeTo(p.dy, 1e-9));
    });

    test('zooming keeps the point under the fingers still', () {
      final v = view();
      const focal = Offset(300, 500);
      final before = v.toPage(focal);
      v.zoomAt(focal, 1.7);
      expect(v.scale, 1.7);
      expect((v.toPage(focal) - before).distance, lessThan(1e-9));
    });

    test('zoom is clamped and steps through presets', () {
      final v = view()..setScale(100);
      expect(v.scale, CanvasView.maxScale);
      v
        ..setScale(1)
        ..zoomStep(1);
      expect(v.scale, 1.25);
      v.zoomStep(-1);
      v.zoomStep(-1);
      expect(v.scale, 0.75);
    });

    test('fit shows all content inside the area', () {
      final v = view()..fit(const Rect.fromLTWH(-3000, 0, 6000, 1000), const Rect.fromLTWH(0, 0, 1280, 800));
      expect(v.toScreen(const Offset(-3000, 0)).dx, greaterThanOrEqualTo(-0.001));
      expect(v.toScreen(const Offset(3000, 1000)).dx, lessThanOrEqualTo(1280.001));
    });
  });
}
