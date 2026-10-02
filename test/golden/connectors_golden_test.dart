// Golden images of connectors at 1280×800: an arrow joining two boxes, as
// in the "snaps to shapes, moves with them" corner of design/screens/Arrows.png
// (drawn at twice its size), selected with its end handles, and after one
// box was moved.
//
// Regenerate after an intended visual change:
//   flutter test --update-goldens test/golden
@Tags(['golden'])
library;

import 'package:endless/board/ids.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/canvas/connectors.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

final _at = DateTime.utc(2026, 10, 1, 12);

/// The design's point (Arrows.dc.html) on the page, at twice the size.
Offset _p(double x, double y) => (Offset(x, y) - const Offset(280, 180)) * 2 + const Offset(240, 160);

ShapeItem _box(String id, double x, double y) => ShapeItem(
      id: id, x: _p(x, y).dx, y: _p(x, y).dy, z: 1, createdAt: _at, kind: ShapeType.rect, //
      w: 192, h: 120, stroke: tokens.inkDefaults[0], strokeWidth: 5,
    );

TextItem _label(String id, String text, double x, double y) => TextItem(
      id: id, x: _p(x, y).dx, y: _p(x, y).dy, z: 2, createdAt: _at, wrap: 400, //
      text: text, size: 28, color: tokens.inkDefaults[0], autoWidth: true,
    );

LoadedNotebook _notebook() {
  final collide = _box('it_collide', 300, 220);
  final measure = _box('it_measure', 470, 270);
  // M396 250 C 430 250, 440 300, 470 300, drawn a little past both ends.
  Offset bezier(double t) {
    final a = _p(386, 250), b = _p(430, 250), c = _p(440, 300), d = _p(480, 300);
    final m = 1 - t;
    return a * (m * m * m) + b * (3 * m * m * t) + c * (3 * m * t * t) + d * (t * t * t);
  }

  final drawn = StrokeItem.fromPagePoints(
    id: 'it_connector',
    z: 3,
    createdAt: _at,
    tool: InkTool.pen,
    penType: PenType.ballpoint,
    color: tokens.extraInkDefaults[0], // green
    width: 6,
    usePressure: false,
    arrow: const ArrowHeads(end: true),
    pagePoints: [for (var i = 0; i <= 40; i++) InkPoint(bezier(i / 40).dx, bezier(i / 40).dy, 0.5, i * 8)],
  );
  final connector = attachEnds(drawn, [collide, measure], slop: 16);
  final page = BoardPage(
    id: newId('pg'),
    items: [collide, measure, _label('it_l1', 'Collide', 312, 236), _label('it_l2', 'Measure', 480, 286), connector],
  );
  final now = DateTime.utc(2026, 9, 25, 9);
  return LoadedNotebook(
    Notebook(id: 'nb_connectors', title: 'Connectors', createdAt: now, updatedAt: now, pageIds: [page.id]),
    [page],
  );
}

Future<void> _pen(WidgetTester t, List<Offset> pts) async {
  final g = await t.createGesture(kind: PointerDeviceKind.stylus);
  var ts = const Duration(seconds: 20);
  await g.down(pts.first, timeStamp: ts);
  for (final p in pts.skip(1)) {
    ts += const Duration(milliseconds: 8);
    await g.moveTo(p, timeStamp: ts);
  }
  await g.up(timeStamp: ts);
  await t.pump();
}

void _golden(String name, Future<void> Function(WidgetTester t) setUp) {
  testWidgets(name, (tester) async {
    debugDisableShadows = false;
    try {
      await pumpCanvas(tester, store: storeWith(_notebook(), settings: AppSettings(trayOpen: false)));
      await tester.pump();
      await setUp(tester);
      await tester.pump(const Duration(seconds: 5));
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('$name.png'));
    } finally {
      debugDisableShadows = true;
    }
  });
}

void main() {
  setUpAll(loadAppFonts);

  _golden('connectors', (t) async {});

  // Selected: the dots on its two ends can be dragged onto a box or off it.
  _golden('connectors_selected', (t) async {
    await t.tap(byLabel('Select'));
    await t.pump();
    final s = shownPage(ProviderScope.containerOf(t.element(find.byType(MaterialApp)))).items.whereType<StrokeItem>().single;
    await _pen(t, [s.pagePoints.elementAt(14)]);
  });

  // "Measure" (box and label) moved down and right: the arrow bends to follow.
  _golden('connectors_moved', (t) async {
    await t.tap(byLabel('Select'));
    await t.pump();
    // A box around "Measure" and its label selects both; drag them together.
    await _pen(t, [for (var i = 0; i <= 10; i++) Offset.lerp(_p(460, 260), _p(575, 337), i / 10)!]);
    final inside = _p(540, 315);
    await _pen(t, [for (var i = 0; i <= 10; i++) Offset.lerp(inside, inside + const Offset(120, 150), i / 10)!]);
    await _pen(t, const [Offset(1000, 150)]); // clear the selection
  });
}
