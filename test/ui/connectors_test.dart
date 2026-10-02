import 'dart:math' as math;

import 'package:endless/board/codec.dart';
import 'package:endless/board/ids.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/canvas/connectors.dart';
import 'package:endless/canvas/new_items.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

final _at = DateTime.utc(2026, 10, 1, 12);

ShapeItem _box(String id, Rect r) => ShapeItem(
      id: id, x: r.left, y: r.top, z: 1, createdAt: _at, kind: ShapeType.rect, //
      w: r.width, h: r.height, stroke: tokens.inkDefaults[0],
    );

/// Box A (250…410 × 250…350) and box B (650…810 × 400…500).
final _a = _box('it_a', const Rect.fromLTWH(250, 250, 160, 100));
final _b = _box('it_b', const Rect.fromLTWH(650, 400, 160, 100));

MemoryBoardStore _storeWith(List<Item> items) {
  final now = DateTime.utc(2026, 9, 25, 9);
  final page = BoardPage(id: newId('pg'), items: items);
  final nb = Notebook(id: newId('nb'), title: 'Connectors', createdAt: now, updatedAt: now, pageIds: [page.id]);
  return storeWith(LoadedNotebook(nb, [page]));
}

List<Item> _items(ProviderContainer c) => shownPage(c).items;

StrokeItem _stroke(ProviderContainer c) => _items(c).whereType<StrokeItem>().single;

ShapeItem _shape(ProviderContainer c, String id) => shownPage(c)[id]! as ShapeItem;

Future<void> _pen(WidgetTester tester, List<Offset> points, {Duration? hold}) async {
  final g = await tester.createGesture(kind: PointerDeviceKind.stylus);
  var t = const Duration(seconds: 20);
  await g.down(points.first, timeStamp: t);
  for (final p in points.skip(1)) {
    t += const Duration(milliseconds: 8);
    await g.moveTo(p, timeStamp: t);
  }
  if (hold != null) {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(hold - const Duration(milliseconds: 200));
  }
  await g.up(timeStamp: t + (hold ?? Duration.zero));
  await tester.pump();
}

List<Offset> _line(Offset a, Offset b, {int n = 40}) => [for (var i = 0; i <= n; i++) Offset.lerp(a, b, i / n)!];

/// A line from [a] to [b] with a quick flick back at the end: an arrow.
List<Offset> _flick(Offset a, Offset b) {
  final d = (a - b) / (a - b).distance; // back along the line
  const turn = 15 * math.pi / 180;
  final hook = Offset(d.dx * math.cos(turn) - d.dy * math.sin(turn), d.dx * math.sin(turn) + d.dy * math.cos(turn)) * 30;
  return [..._line(a, b, n: 50), for (var i = 1; i <= 5; i++) Offset.lerp(b, b + hook, i / 5)!];
}

Future<void> _tool(WidgetTester tester, String label) async {
  await tester.tap(byLabel(label));
  await tester.pump();
}

/// Draws the arrow from inside A to inside B.
Future<void> _connect(WidgetTester tester) => _pen(tester, _flick(const Offset(330, 300), const Offset(720, 450)));

void main() {
  setUpAll(loadAppFonts);

  testWidgets('an arrow from one box to another joins both edges; Undo keeps the ink', (tester) async {
    final c = await pumpCanvas(tester, store: _storeWith([_a, _b]));
    await _connect(tester);

    final s = _stroke(c);
    expect(s.arrow?.end, isTrue); // the flick still makes the head
    expect((s.startItemId, s.endItemId), ('it_a', 'it_b'));
    expect(s.pagePoints.first.dx, closeTo(410, 0.3)); // where it leaves A's right edge
    expect(s.pagePoints.last.dx, closeTo(650, 0.3)); // where it meets B's left edge
    expect(find.text('Made an arrow'), findsOneWidget);

    // Undo goes back to the ink as drawn: no head, not joined.
    await tester.tap(find.bySemanticsLabel('Undo: Made an arrow'));
    await tester.pump();
    expect(_stroke(c).arrow, isNull);
    expect(_stroke(c).isAttached, isFalse);
    expect(_stroke(c).pagePoints.first, const Offset(330, 300));
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('it follows a box that is moved or stretched, in the same undo step', (tester) async {
    final c = await pumpCanvas(tester, store: _storeWith([_a, _b]));
    await _connect(tester);
    final joined = _stroke(c);

    await _tool(tester, 'Select');
    await _pen(tester, const [Offset(700, 400)]); // B's top edge
    expect(canvasPane.selection.ids, {'it_b'});
    await _pen(tester, _line(const Offset(700, 400), const Offset(700, 500), n: 10));
    expect(_shape(c, 'it_b').y, closeTo(500, 0.2));
    expect(_stroke(c).pagePoints.last, offsetMoreOrLessEquals(joined.pagePoints.last + const Offset(0, 100), epsilon: 0.3));
    expect(_stroke(c).pagePoints.first, offsetMoreOrLessEquals(joined.pagePoints.first, epsilon: 0.3));
    expect(_stroke(c).endItemId, 'it_b');

    await tester.tap(byLabel('Undo'));
    await tester.pump();
    expect(_stroke(c).pagePoints.last, offsetMoreOrLessEquals(joined.pagePoints.last, epsilon: 0.3));

    // B's left edge (its handle is 8 px outside) dragged 50 px left: the end stays on it.
    await _pen(tester, _line(const Offset(642, 450), const Offset(592, 450), n: 10));
    expect(_shape(c, 'it_b').x, closeTo(600, 0.2));
    expect(_stroke(c).pagePoints.last.dx, closeTo(600, 0.3));
    expect(_stroke(c).endItemId, 'it_b');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('dragging an end away lets go; dragging it onto a box joins it', (tester) async {
    final c = await pumpCanvas(tester, store: _storeWith([_a, _b]));
    await _connect(tester);
    final end = _stroke(c).pagePoints.last;

    await _tool(tester, 'Select');
    await _pen(tester, [_stroke(c).pagePoints.elementAt(20)]);
    expect(canvasPane.selection.ids, {_stroke(c).id});

    await _pen(tester, _line(end, const Offset(900, 620), n: 10));
    expect(_stroke(c).endItemId, isNull);
    expect(_stroke(c).startItemId, 'it_a'); // the other end stays joined
    expect(_stroke(c).pagePoints.last, offsetMoreOrLessEquals(const Offset(900, 620), epsilon: 0.3));
    expect(find.text('Let go'), findsOneWidget);

    // Back onto B, a little above its top edge: it snaps onto the edge.
    await _pen(tester, _line(const Offset(900, 620), const Offset(730, 392), n: 10));
    expect(_stroke(c).endItemId, 'it_b');
    expect(_stroke(c).pagePoints.last, offsetMoreOrLessEquals(const Offset(730, 400), epsilon: 0.3));
    expect(find.text('Joined'), findsOneWidget);

    await tester.tap(byLabel('Undo'));
    await tester.pump();
    expect(_stroke(c).endItemId, isNull);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a straightened line joins too; deleting a box lets go, and Undo joins again', (tester) async {
    final store = _storeWith([_a, _b]);
    final c = await pumpCanvas(tester, store: store);
    final shaky = [
      for (final (i, p) in _line(const Offset(330, 300), const Offset(720, 450)).indexed)
        p + Offset(0, math.sin(i / 40 * math.pi * 3) * 3),
    ];
    await _pen(tester, shaky, hold: const Duration(milliseconds: 600));
    expect(_stroke(c).straightened, 'line');
    expect((_stroke(c).startItemId, _stroke(c).endItemId), ('it_a', 'it_b'));

    await tester.pump(const Duration(seconds: 1));
    final saved = decodePage(store.pages[canvasPane.notebookId]!.values.single).items.whereType<StrokeItem>().single;
    expect((saved.startItemId, saved.endItemId), ('it_a', 'it_b'));

    await _tool(tester, 'Select');
    await _pen(tester, const [Offset(700, 400)]);
    await tester.tap(find.bySemanticsLabel('Delete'));
    await tester.pump();
    expect((_stroke(c).startItemId, _stroke(c).endItemId), ('it_a', null));
    await tester.tap(byLabel('Undo'));
    await tester.pump();
    expect(_stroke(c).endItemId, 'it_b');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('copied with its boxes, the copy joins the copies', (tester) async {
    final c = await pumpCanvas(tester, store: _storeWith([_a, _b]));
    await _connect(tester);
    await _tool(tester, 'Select');
    await _pen(tester, _line(const Offset(220, 220), const Offset(840, 530), n: 10)); // a box around everything
    expect(canvasPane.selection.ids, hasLength(3));
    await tester.tap(find.bySemanticsLabel('Copy'));
    await tester.pump();

    final strokes = _items(c).whereType<StrokeItem>().toList();
    expect(strokes, hasLength(2));
    final copy = strokes.last;
    final boxes = _items(c).whereType<ShapeItem>().toList();
    expect(boxes, hasLength(4));
    expect(copy.startItemId, boxes[2].id);
    expect(copy.endItemId, boxes[3].id);
    expect(distanceToOutline(boxes[3], copy.pagePoints.last), lessThan(0.3));
    expect(strokes.first.startItemId, 'it_a'); // the original is as it was
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('an arrow from a sticky note out to a box joins both; one drawn on the note stays on it', (tester) async {
    final note = newSticky(const Offset(400, 300), z: 1, now: _at).copyWith(rotation: 0); // 279…521 × 190…410
    final c = await pumpCanvas(tester, store: _storeWith([note, _b]));

    await _pen(tester, _flick(const Offset(380, 280), const Offset(460, 330)));
    expect(_items(c).whereType<StrokeItem>(), isEmpty);
    expect((shownPage(c)[note.id]! as StickyItem).ink.single.arrow, isNotNull); // written on the note

    await _pen(tester, _flick(const Offset(420, 360), const Offset(720, 450)));
    final s = _stroke(c);
    expect((s.startItemId, s.endItemId), (note.id, 'it_b'));
    expect(distanceToOutline(note, s.pagePoints.first), lessThan(0.3));
    expect((shownPage(c)[note.id]! as StickyItem).ink, hasLength(1)); // the connector isn't on the note

    // Moving the note brings the connector's start along.
    await _tool(tester, 'Select');
    await _pen(tester, const [Offset(330, 240)]);
    await _pen(tester, _line(const Offset(330, 240), const Offset(330, 200), n: 8));
    expect(_stroke(c).pagePoints.first.dy, closeTo(s.pagePoints.first.dy - 40, 0.3));
    await tester.pump(const Duration(seconds: 5));
  });
}
