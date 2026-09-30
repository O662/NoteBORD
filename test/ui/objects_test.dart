import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:endless/board/codec.dart';
import 'package:endless/board/ids.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/canvas/new_items.dart';
import 'package:endless/state/photos.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:endless/ui/canvas/canvas_screen.dart';
import 'package:endless/ui/canvas/insert_actions.dart';
import 'package:endless/ui/canvas/insert_menu.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

List<Item> _items(ProviderContainer c) => shownPage(c).items;

T _only<T extends Item>(ProviderContainer c) => _items(c).whereType<T>().single;

final _at = DateTime.utc(2026, 9, 29, 12);

/// A notebook with one page holding [items] (page coords = screen coords).
MemoryBoardStore _storeWith(List<Item> items, {AppSettings? settings}) {
  final now = DateTime.utc(2026, 9, 25, 9);
  final page = BoardPage(id: newId('pg'), items: items);
  final nb = Notebook(id: newId('nb'), title: 'Objects', createdAt: now, updatedAt: now, pageIds: [page.id]);
  return storeWith(LoadedNotebook(nb, [page]), settings: settings);
}

/// Draws [points] with the S Pen, 8 ms apart (one point is a tap).
Future<void> _pen(WidgetTester tester, List<Offset> points) async {
  final g = await tester.createGesture(kind: PointerDeviceKind.stylus);
  var t = const Duration(seconds: 20);
  await g.down(points.first, timeStamp: t);
  for (final p in points.skip(1)) {
    t += const Duration(milliseconds: 8);
    await g.moveTo(p, timeStamp: t);
  }
  await g.up(timeStamp: t);
  await tester.pump();
}

/// A finger tap, long after the pen was last seen (so it isn't the palm).
Future<void> _fingerTap(WidgetTester tester, Offset at, {int pointer = 60}) async {
  const later = Duration(minutes: 5);
  final f = await tester.createGesture(kind: PointerDeviceKind.touch, pointer: pointer);
  await f.down(at, timeStamp: later);
  await f.up(timeStamp: later);
  await tester.pump();
}

List<Offset> _line(Offset a, Offset b, {int n = 20}) => [for (var i = 0; i <= n; i++) Offset.lerp(a, b, i / n)!];

List<Offset> _zigzag(Offset from, {int legs = 8, double amp = 34, double step = 13}) {
  final corners = [for (var i = 0; i <= legs; i++) from + Offset(i * step, i.isEven ? 0 : -amp)];
  return [
    for (var i = 0; i < legs; i++)
      for (var s = 0; s < 6; s++) Offset.lerp(corners[i], corners[i + 1], s / 6)!,
    corners.last,
  ];
}

Future<void> _pick(WidgetTester tester, String label) async {
  await tester.tap(byLabel(label));
  await tester.pump();
}

Future<void> _useTool(WidgetTester tester, ProviderContainer c, CanvasTool tool) async {
  c.read(settingsProvider.notifier).apply((s) => s.copyWith(tool: tool));
  await tester.pump();
}

/// Opens a rail group and picks one of its rows.
Future<void> _rail(WidgetTester tester, String group, String item) async {
  await tester.tap(byLabel(group));
  await tester.pump();
  await tester.tap(find.text(item));
  await tester.pump();
}

Future<void> _action(WidgetTester tester, String label) async {
  await tester.tap(find.bySemanticsLabel(label));
  await tester.pump();
}

late ui.Image _picture;

void main() {
  setUpAll(() async {
    await loadAppFonts();
    _picture = testPicture(w: 800, h: 400);
  });
  tearDownAll(() => _picture.dispose());

  group('sticky notes', () {
    testWidgets('the Insert flyout drops one where you tap; the pen writes on it and the ink goes where it goes',
        (tester) async {
      final c = await pumpCanvas(tester, store: _storeWith(const []));
      await _rail(tester, 'Insert', 'Sticky note');
      expect(c.read(settingsProvider).tool, CanvasTool.sticky);
      expect(find.text('Tap the page to drop a sticky note'), findsOneWidget);

      await _pen(tester, const [Offset(500, 400)]);
      final note = _only<StickyItem>(c);
      expect(note.center, const Offset(500, 400));
      expect(note.color, tokens.stickyColors[0]);
      expect(note.rotation, -2);
      expect(c.read(settingsProvider).tool, CanvasTool.pen); // ready to write on it
      expect(find.text('Added a sticky note to the page'), findsOneWidget);

      // Ink that starts on the note is written on it; ink beside it is on the page.
      await _pen(tester, _line(const Offset(440, 380), const Offset(560, 392)));
      expect(_items(c), hasLength(1));
      expect(_only<StickyItem>(c).ink, hasLength(1));
      await _pen(tester, _line(const Offset(800, 380), const Offset(900, 392)));
      expect(_items(c), hasLength(2));
      final before = _only<StickyItem>(c).pageInk.single.pagePoints.first;
      expect((before - const Offset(440, 380)).distance, lessThan(0.2));

      // Select the note and drag it: its ink moves with it, the page's doesn't.
      await _pick(tester, 'Select');
      await _pen(tester, const [Offset(500, 470)]);
      expect(find.bySemanticsLabel('Edit text'), findsOneWidget);
      await _pen(tester, _line(const Offset(500, 470), const Offset(600, 520), n: 10));
      final moved = _only<StickyItem>(c);
      expect((moved.center - const Offset(600, 450)).distance, lessThan(0.2));
      expect((moved.pageInk.single.pagePoints.first - before - const Offset(100, 50)).distance, lessThan(0.3));
      expect(_only<StrokeItem>(c).x, closeTo(800, 0.2));

      // Undo: the move, the page ink, the ink on the note, then the note.
      for (final expected in [const Offset(500, 400), null, null]) {
        await _pick(tester, 'Undo');
        if (expected != null) expect((_only<StickyItem>(c).center - expected).distance, lessThan(0.2));
      }
      expect(_items(c), hasLength(1));
      expect(_only<StickyItem>(c).ink, isEmpty);
      await _pick(tester, 'Undo');
      expect(_items(c), isEmpty);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a finger tap drops one too, and a finger drag still pans', (tester) async {
      final c = await pumpCanvas(tester, store: _storeWith(const []));
      await _useTool(tester, c, CanvasTool.sticky);
      await _fingerTap(tester, const Offset(500, 400));
      expect(_only<StickyItem>(c).center, const Offset(500, 400));

      await _useTool(tester, c, CanvasTool.sticky);
      await tester.dragFrom(const Offset(500, 600), const Offset(-100, 0));
      await tester.pump();
      expect(_items(c), hasLength(1));
      expect(canvasPane.view.translation.dx, closeTo(-100, 25)); // the page panned instead
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('the Text tool types on a note, and the eraser rubs ink off it', (tester) async {
      final note = newSticky(const Offset(500, 400), z: 1, now: _at);
      final c = await pumpCanvas(tester, store: _storeWith([note]));
      await _pick(tester, 'Text');
      await _pen(tester, const [Offset(500, 400)]);
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Ask in office hours');
      await _pick(tester, 'Done typing');
      expect(_only<StickyItem>(c).text, 'Ask in office hours');
      expect(_items(c), hasLength(1));
      expect(find.byType(TextField), findsNothing);

      // Two lines of ink on the note; the eraser takes one and leaves the note.
      await _pick(tester, 'Pen');
      await _pen(tester, _line(const Offset(420, 440), const Offset(580, 444)));
      await _pen(tester, _line(const Offset(420, 480), const Offset(580, 484)));
      expect(_only<StickyItem>(c).ink, hasLength(2));
      await _pick(tester, 'Eraser');
      await _pen(tester, _line(const Offset(500, 425), const Offset(500, 455), n: 6));
      final left = _only<StickyItem>(c);
      expect(left.ink, hasLength(1));
      expect(left.text, 'Ask in office hours');
      await _pick(tester, 'Undo');
      expect(_only<StickyItem>(c).ink, hasLength(2));
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('hold to straighten works on a note, and Undo gives the ink back', (tester) async {
      final note = newSticky(const Offset(500, 400), z: 1, now: _at).copyWith(rotation: 0);
      final c = await pumpCanvas(tester, store: _storeWith([note]));
      final shaky = [
        for (var i = 0; i <= 40; i++)
          Offset.lerp(const Offset(420, 440), const Offset(580, 390), i / 40)! + Offset(0, math.sin(i / 40 * math.pi * 3) * 3),
      ];
      final g = await tester.createGesture(kind: PointerDeviceKind.stylus);
      await g.down(shaky.first);
      for (final p in shaky.skip(1)) {
        await g.moveTo(p);
      }
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 400));
      await g.up();
      await tester.pump();

      expect(_items(c), hasLength(1)); // still only the note
      expect(_only<StickyItem>(c).ink.single.straightened, 'line');
      expect(find.text('Line straightened'), findsOneWidget);
      await _action(tester, 'Undo: Line straightened');
      expect(_only<StickyItem>(c).ink.single.straightened, isNull);
      expect(_only<StickyItem>(c).ink.single.points, hasLength(shaky.length));
      await _pick(tester, 'Undo');
      expect(_only<StickyItem>(c).ink, isEmpty);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a scribble on a note erases the note’s ink only', (tester) async {
      final under = strokeFrom([for (var i = 0; i <= 30; i++) Offset(430 + i * 2.0, 400 + 8 * math.sin(i / 3))]);
      final note = newSticky(const Offset(500, 400), z: 2, now: _at)
          .copyWith(rotation: 0)
          .withInk(strokeFrom([for (var i = 0; i <= 30; i++) Offset(430 + i * 2.0, 400 + 8 * math.sin(i / 3))]));
      final c = await pumpCanvas(tester, store: _storeWith([under, note]));
      await _pen(tester, _zigzag(const Offset(422, 418)));
      expect(_only<StickyItem>(c).ink, isEmpty);
      expect(_items(c).first.id, under.id); // the page ink under the note is untouched
      expect(find.text('Erased 1 stroke'), findsOneWidget);
      await _action(tester, 'Undo: Erased 1 stroke');
      expect(_only<StickyItem>(c).ink, hasLength(1));
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a stack fans out and stacks again, and steps through its notes', (tester) async {
      final c = await pumpCanvas(tester, store: _storeWith(const []));
      await _rail(tester, 'Insert', 'Everything else');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sticky stack'));
      await tester.pumpAndSettle();
      expect(c.read(settingsProvider).tool, CanvasTool.stack);
      expect(find.text('Tap the page to drop a stack of sticky notes'), findsOneWidget);

      await _pen(tester, const [Offset(500, 400)]);
      var stack = _only<StickyItem>(c);
      expect(stack.count, 3);
      expect(stack.color, tokens.stickyColors[1]);
      expect(find.text('Added a stack of notes to the page'), findsOneWidget);
      await _pen(tester, _line(const Offset(440, 380), const Offset(560, 392))); // on the top note
      expect(_only<StickyItem>(c).ink, hasLength(1));

      await _pick(tester, 'Select');
      await _pen(tester, const [Offset(500, 450)]);
      expect(find.bySemanticsLabel('Fan out'), findsOneWidget);
      await _action(tester, 'Next note');
      stack = _only<StickyItem>(c);
      expect(stack.color, tokens.stickyColors[2]); // the peach one came up
      expect(stack.ink, isEmpty);
      expect(stack.under.last.color, tokens.stickyColors[1]);
      expect(stack.under.last.items, hasLength(1)); // the written one went to the bottom
      expect(stack.count, 3);

      await _action(tester, 'Fan out');
      final notes = _items(c).whereType<StickyItem>().toList();
      expect(notes.map((n) => n.count), [1, 1, 1]);
      expect(notes.map((n) => n.color), [tokens.stickyColors[2], tokens.stickyColors[3], tokens.stickyColors[1]]);
      expect(notes[1].x, greaterThan(notes[0].x + notes[0].w));
      expect(notes[2].ink, hasLength(1));
      expect(find.text('Fanned out 3 notes'), findsOneWidget);

      // The three are selected, so they can go straight back.
      await _action(tester, 'Stack');
      stack = _only<StickyItem>(c);
      expect(stack.count, 3);
      expect(stack.color, tokens.stickyColors[1]); // the topmost of them is on top
      expect(stack.ink, hasLength(1));
      expect(find.text('Stacked 3 notes'), findsOneWidget);

      await _pick(tester, 'Undo'); // the stacking
      expect(_items(c), hasLength(3));
      await _pick(tester, 'Undo'); // the fanning out
      expect(_only<StickyItem>(c).count, 3);

      // Tapping the "3 notes" badge with Select fans it out as well.
      await _pen(tester, const [Offset(800, 650)]); // clear the selection
      final s = _only<StickyItem>(c);
      await _pen(tester, [s.toPage(Offset(s.w + 4, -4))]);
      expect(_items(c), hasLength(3));
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('text boxes', () {
    testWidgets('type, edit, restyle and clear', (tester) async {
      final c = await pumpCanvas(tester, store: _storeWith(const []));
      await _pick(tester, 'Text');
      expect(c.read(settingsProvider).tool, CanvasTool.text);
      expect(find.text(placeHints[CanvasTool.text]!), findsOneWidget);

      await _pen(tester, const [Offset(400, 300)]);
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Momentum is conserved');
      await tester.pump();
      expect(_items(c), isEmpty); // on the page once you're done
      await _pick(tester, 'Done typing');
      var t = _only<TextItem>(c);
      expect(t.text, 'Momentum is conserved');
      expect(t.autoWidth, isTrue);
      expect(t.color, c.read(settingsProvider).penColor);
      expect(t.x, 400);
      expect(t.center.dy, closeTo(300, 0.5)); // the tap is the middle of the line
      expect(t.w, lessThan(320));
      expect(find.byType(TextField), findsNothing);

      // Tap it to edit; a tap elsewhere finishes (and doesn't start another box).
      await _pen(tester, [t.center]);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Momentum is conserved');
      await tester.enterText(find.byType(TextField), 'Momentum');
      await _pen(tester, const [Offset(800, 600)]);
      expect(find.byType(TextField), findsNothing);
      t = _only<TextItem>(c);
      expect(t.text, 'Momentum');
      expect(t.x, 400);

      // Bigger, and in the serif font.
      await _pen(tester, [t.center]);
      await _pick(tester, 'Larger text');
      await _pick(tester, 'Serif font');
      await _pick(tester, 'Done typing');
      t = _only<TextItem>(c);
      expect(t.size, 28);
      expect(t.font, 'serif');
      expect(t.x, 400);

      // Emptied, the box goes; Undo brings it back.
      await _pen(tester, [t.center]);
      await tester.enterText(find.byType(TextField), '  ');
      await _pick(tester, 'Done typing');
      expect(_items(c), isEmpty);
      await _pick(tester, 'Undo');
      expect(_only<TextItem>(c).text, 'Momentum');

      // Esc finishes typing too, and an empty new box leaves nothing behind.
      await _pen(tester, const [Offset(700, 500)]);
      expect(find.byType(TextField), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
      expect(_items(c), hasLength(1));
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('select one to recolor it, stretch it to a width, or edit it', (tester) async {
      final text = TextItem(
        id: 'it_text', x: 300, y: 300, z: 1, createdAt: _at, wrap: 480, //
        text: 'Total momentum is conserved in a closed system', color: tokens.inkDefaults[0], autoWidth: true,
      );
      final c = await pumpCanvas(tester, store: _storeWith([text]));
      await _pick(tester, 'Select');
      await _pen(tester, [text.center]);
      for (final label in ['Edit text', 'Copy', 'Color', 'To front', 'To back', 'Delete']) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      expect(find.bySemanticsLabel('Convert to text'), findsNothing);

      await _action(tester, 'Color');
      await _pick(tester, 'Change color to Terracotta');
      expect(_only<TextItem>(c).color, tokens.inkDefaults[2]);

      // Drag the left edge in: it wraps narrower, and the right edge stays.
      final right = text.x + text.w;
      await _pen(tester, _line(Offset(text.x - 8, text.center.dy), Offset(text.x - 8 + 200, text.center.dy), n: 10));
      final narrow = _only<TextItem>(c);
      expect(narrow.autoWidth, isFalse);
      expect(narrow.w, closeTo(text.w - 200, 0.5));
      expect(narrow.x + narrow.w, closeTo(right, 0.5));
      expect(narrow.h, greaterThan(text.h)); // two lines now
      await _pick(tester, 'Undo');
      expect(_only<TextItem>(c).autoWidth, isTrue);

      await _action(tester, 'Edit text');
      expect(find.byType(TextField), findsOneWidget);
      await _pick(tester, 'Done typing');
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('paper frames', () {
    testWidgets('go under what’s written, and take it along when moved, copied or deleted', (tester) async {
      final already = strokeFrom(_line(const Offset(450, 300), const Offset(600, 300)));
      final away = strokeFrom(_line(const Offset(900, 650), const Offset(1000, 650)));
      final c = await pumpCanvas(tester, store: _storeWith([already, away]));
      await _rail(tester, 'Insert', 'Paper frame');
      expect(find.text('Tap the page to place a lined sheet'), findsOneWidget);
      await _pen(tester, const [Offset(500, 200)]);

      final frame = _only<FrameItem>(c);
      expect(_items(c).first.id, frame.id); // under the ink that was there
      expect(Rect.fromLTWH(frame.x, frame.y, frame.w, frame.h), const Rect.fromLTWH(220, 200, 560, 792));
      expect(frame.paper, 'lined-a4');
      expect(find.text('Added a paper frame to the page'), findsOneWidget);
      expect(c.read(settingsProvider).tool, CanvasTool.pen);

      await _pen(tester, _line(const Offset(320, 420), const Offset(520, 424))); // written on the sheet
      expect(_items(c), hasLength(4));
      expect(_items(c).last, isA<StrokeItem>());

      await _pick(tester, 'Select');
      await _pen(tester, const [Offset(300, 600)]);
      expect(find.bySemanticsLabel('Rename'), findsOneWidget);
      await _pen(tester, _line(const Offset(300, 600), const Offset(350, 630), n: 10));
      var strokes = _items(c).whereType<StrokeItem>().toList();
      expect(_only<FrameItem>(c).x, closeTo(270, 0.2));
      expect(strokes[0].x, closeTo(already.x + 50, 0.2)); // what's on the sheet went with it
      expect(strokes[2].y, closeTo(420 + 30, 1.5));
      expect(strokes[1].x, away.x); // what isn't stayed

      await _pick(tester, 'Undo'); // one step for the sheet and its ink
      strokes = _items(c).whereType<StrokeItem>().toList();
      expect(_only<FrameItem>(c).x, 220);
      expect(strokes[0].x, already.x);

      await _action(tester, 'Copy');
      expect(_items(c).whereType<FrameItem>(), hasLength(2));
      expect(_items(c).whereType<StrokeItem>(), hasLength(5)); // the two on the sheet were copied with it
      await _pick(tester, 'Undo');

      await _pen(tester, const [Offset(300, 600)]);
      await _action(tester, 'Delete');
      expect(_items(c).map((i) => i.id), [away.id]);
      await _pick(tester, 'Undo');
      expect(_items(c), hasLength(4));
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('Templates can be used for a frame', (tester) async {
      final c = await pumpCanvas(tester, store: _storeWith(const []));
      await _rail(tester, 'Insert', 'Templates');
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Frame'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Use “Cornell notes”'));
      await tester.pumpAndSettle();
      final frame = _only<FrameItem>(c);
      expect(frame.template, 'cornell');
      expect(frame.w, 560);
      expect(frame.center.dx, closeTo(640, 0.5));
      expect(shownNotebook(c).pages, hasLength(1)); // a frame, not a new page
      expect(find.text('Added a paper frame to the page'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('shapes', () {
    testWidgets('drag one out, stretch an edge, turn it upright', (tester) async {
      final c = await pumpCanvas(tester, store: _storeWith(const []));
      await _pick(tester, 'Shapes');
      expect(c.read(settingsProvider).tool, CanvasTool.shape);
      expect(find.text(placeHints[CanvasTool.shape]!), findsOneWidget);
      await _pick(tester, 'Oval');
      expect(c.read(settingsProvider).shapeKind, ShapeType.ellipse);

      await _pen(tester, _line(const Offset(300, 300), const Offset(500, 400), n: 10));
      var oval = _only<ShapeItem>(c);
      expect(oval.kind, ShapeType.ellipse);
      expect(Rect.fromLTWH(oval.x, oval.y, oval.w, oval.h), const Rect.fromLTRB(300, 300, 500, 400));
      expect(oval.stroke, c.read(settingsProvider).penColor);
      expect(find.text('Added an oval to the page'), findsOneWidget);
      // It's selected, with Select as the tool, ready to adjust.
      expect(c.read(settingsProvider).tool, CanvasTool.select);
      expect(find.bySemanticsLabel('Selection actions'), findsOneWidget);

      // The right edge's handle (8 px outside the box): 100 px wider, the left edge stays.
      await _pen(tester, _line(const Offset(508, 350), const Offset(608, 350), n: 10));
      oval = _only<ShapeItem>(c);
      expect(Rect.fromLTWH(oval.x, oval.y, oval.w, oval.h), rectMoreOrLessEquals(const Rect.fromLTRB(300, 300, 600, 400), epsilon: 0.01));

      // The rotate knob, 30 px under the bottom edge: a quarter turn.
      final center = oval.center;
      final knob = Offset(center.dx, 400 + 8 + 30);
      await _pen(tester, [
        for (var i = 0; i <= 10; i++)
          center + Offset(math.cos(math.pi / 2 - i / 10 * math.pi / 2), math.sin(math.pi / 2 - i / 10 * math.pi / 2)) * (knob - center).distance,
      ]);
      oval = _only<ShapeItem>(c);
      expect(oval.rotation.abs(), closeTo(90, 1e-6));
      expect((oval.center - center).distance, lessThan(0.01));

      await _pick(tester, 'Undo');
      await _pick(tester, 'Undo');
      await _pick(tester, 'Undo');
      expect(_items(c), isEmpty);

      // A tap drops one at its usual size; lines run from the pen down to the pen up.
      await _pick(tester, 'Shapes');
      await _pick(tester, 'Arrow');
      await _pen(tester, _line(const Offset(300, 500), const Offset(500, 500), n: 10));
      final arrow = _only<ShapeItem>(c);
      expect(arrow.kind, ShapeType.arrow);
      expect(arrow.w, 200);
      expect(arrow.rotation, 0);
      expect(find.text('Added an arrow to the page'), findsOneWidget);
      await _pick(tester, 'Shapes');
      await _pick(tester, 'Rectangle');
      await _pen(tester, const [Offset(800, 400)]);
      expect(_items(c).whereType<ShapeItem>().last.center, const Offset(800, 400));
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a tilted sticky note settles upright when turned a little', (tester) async {
      final note = newSticky(const Offset(500, 400), z: 1, now: _at); // −2°
      final c = await pumpCanvas(tester, store: _storeWith([note]));
      await _pick(tester, 'Select');
      await _pen(tester, const [Offset(500, 400)]);
      final down = Offset(-math.sin(note.angle), math.cos(note.angle));
      final knob = note.center + down * (note.h / 2 + 8 + 30);
      await _pen(tester, _line(knob, knob + const Offset(-6, 0), n: 6));
      expect(_only<StickyItem>(c).rotation, closeTo(0, 1e-6));
      expect((_only<StickyItem>(c).center - note.center).distance, lessThan(0.01));
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('images', () {
    testWidgets('the Insert flyout adds a picture to the middle of the view, selected', (tester) async {
      final store = _storeWith(const []);
      final picker = FakePhotoPicker(fakePng());
      final c = await pumpCanvas(tester,
          store: store, extra: [photoPickerProvider.overrideWithValue(picker), decodeAs(_picture)]);
      await _rail(tester, 'Insert', 'Image');
      await tester.pump();

      expect(picker.asked, [PhotoOrigin.tablet]); // no camera here, so no question
      final image = _only<ImageItem>(c);
      expect(Size(image.w, image.h), const Size(480, 240));
      expect(image.center, const Offset(640, 400));
      expect(store.assets[canvasPane.notebookId]!.keys, [image.asset]);
      expect(c.read(settingsProvider).tool, CanvasTool.select);
      expect(find.bySemanticsLabel('Selection actions'), findsOneWidget);
      expect(find.bySemanticsLabel('Color'), findsNothing); // a picture has no color to change
      expect(find.text('Added an image to the page'), findsOneWidget);

      // It saves with the page, and the corner handle resizes it in proportion.
      await tester.pump(const Duration(seconds: 1));
      expect(decodePage(store.pages[canvasPane.notebookId]!.values.single).items.single, isA<ImageItem>());
      await _pen(tester, _line(const Offset(888, 528), const Offset(948, 558), n: 10));
      final bigger = _only<ImageItem>(c);
      expect(bigger.w / bigger.h, closeTo(2, 1e-6));
      expect(bigger.w, greaterThan(500));
      expect(bigger.x, closeTo(image.x, 1.5)); // the opposite corner of the outline stayed

      await _pick(tester, 'Undo');
      await _pick(tester, 'Undo');
      expect(_items(c), isEmpty);

      // Backing out of the picker adds nothing.
      picker.bytes = null;
      await _rail(tester, 'Insert', 'Image');
      await tester.pump();
      expect(_items(c), isEmpty);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('what’s written on a picture moves with it', (tester) async {
      // Its file is missing, so it shows as a placeholder; it still selects and moves.
      final picture = ImageItem(id: 'it_img', x: 300, y: 250, z: 1, createdAt: _at, w: 400, h: 300, asset: 'gone.png');
      final on = strokeFrom(_line(const Offset(350, 300), const Offset(500, 320)), z: 2);
      final off = strokeFrom(_line(const Offset(800, 300), const Offset(900, 320)), z: 3);
      final c = await pumpCanvas(tester, store: _storeWith([picture, on, off]));
      await _pick(tester, 'Select');
      await _pen(tester, const [Offset(500, 450)]);
      expect(canvasPane.selection.ids, {'it_img'});
      await _pen(tester, _line(const Offset(500, 450), const Offset(560, 480), n: 10));
      final strokes = _items(c).whereType<StrokeItem>().toList();
      expect(_only<ImageItem>(c).x, closeTo(360, 0.2));
      expect(strokes[0].x, closeTo(on.x + 60, 0.2));
      expect(strokes[1].x, off.x);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('with a camera it asks where the picture comes from', (tester) async {
      final picker = FakePhotoPicker(fakePng(), hasCamera: true);
      final c = await pumpCanvas(tester, store: _storeWith(const []), extra: [
        photoPickerProvider.overrideWithValue(picker),
        decodeAs(_picture),
      ]);
      await _rail(tester, 'Insert', 'Image');
      await tester.pumpAndSettle();
      expect(find.text('Add an image'), findsOneWidget);
      await tester.tap(find.text('Camera'));
      await tester.pumpAndSettle();
      expect(picker.asked, [PhotoOrigin.camera]);
      expect(_items(c).single, isA<ImageItem>());
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('selecting objects', () {
    testWidgets('sticky notes recolor as paper; to back and to front; copy and delete', (tester) async {
      final a = newSticky(const Offset(400, 400), z: 1, now: _at);
      final b = newSticky(const Offset(560, 440), z: 2, now: _at); // overlaps a, on top
      final c = await pumpCanvas(tester, store: _storeWith([a, b]));
      await _pick(tester, 'Select');
      await _pen(tester, const [Offset(480, 420)]); // where they overlap: the top one
      expect(canvasPane.selection.ids, {b.id});

      await _action(tester, 'Color');
      expect(byLabel('Change color to Green'), findsNothing); // paper colors, not ink
      await _pick(tester, 'Change note to pink');
      expect((_items(c)[1] as StickyItem).color, tokens.stickyColors[1]);

      await _action(tester, 'To back');
      expect(_items(c).map((i) => i.id), [b.id, a.id]);
      await _pen(tester, const [Offset(800, 650)]);
      await _pen(tester, const [Offset(480, 420)]);
      expect(canvasPane.selection.ids, {a.id}); // a is on top there now
      await _pick(tester, 'Undo');
      expect(_items(c).map((i) => i.id), [a.id, b.id]);

      // A box around both selects both; together they offer Stack.
      await _pen(tester, const [Offset(800, 650)]);
      await _pen(tester, _line(const Offset(250, 260), const Offset(720, 580), n: 10));
      expect(canvasPane.selection.ids, {a.id, b.id});
      expect(find.bySemanticsLabel('Stack'), findsOneWidget);
      await _action(tester, 'Copy');
      expect(_items(c), hasLength(4));
      expect((_items(c)[2] as StickyItem).x, closeTo(a.x + 24, 0.01));
      await _action(tester, 'Delete');
      expect(_items(c).map((i) => i.id), [a.id, b.id]);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a lasso takes ink and objects together', (tester) async {
      final word = strokeFrom([for (var i = 0; i <= 30; i++) Offset(400 + i * 2.0, 300 + 8 * math.sin(i / 3))]);
      final text = TextItem(id: 'it_t', x: 400, y: 340, z: 2, createdAt: _at, wrap: 480, text: 'typed', color: Colors.black, autoWidth: true);
      final c = await pumpCanvas(tester, store: _storeWith([word, text]));
      await _pick(tester, 'Lasso select');
      await _pen(tester, [
        for (var i = 0; i <= 40; i++)
          const Offset(440, 330) + Offset(math.cos(i / 40 * 2 * math.pi) * 110, math.sin(i / 40 * 2 * math.pi) * 70),
      ]);
      expect(canvasPane.selection.ids, {word.id, text.id});
      expect(find.bySemanticsLabel('Convert to text'), findsOneWidget); // ink is in it
      await _pen(tester, _line(const Offset(440, 330), const Offset(540, 330), n: 10));
      expect((_items(c)[0] as StrokeItem).x, closeTo(word.x + 100, 0.2));
      expect((_items(c)[1] as TextItem).x, closeTo(500, 0.2));
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('the Insert menu', () {
    testWidgets('lists everything, searches, and wires what exists', (tester) async {
      final c = await pumpCanvas(tester, store: _storeWith(const []));
      await _rail(tester, 'Insert', 'Everything else');
      await tester.pumpAndSettle();

      for (final title in ['ON THE PAGE', 'FILES', 'BUILD ON THE BOARD', 'LIVE WIDGETS']) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      for (final s in insertSections) {
        for (final e in s.entries) {
          expect(find.bySemanticsLabel(e.label), findsOneWidget, reason: e.label);
        }
      }
      expect(insertSections.expand((s) => s.entries), hasLength(26));
      for (final chip in ['This tablet', 'Google Drive', 'OneDrive', 'Camera', 'Scan a document']) {
        expect(find.text(chip), findsOneWidget, reason: chip);
      }
      expect(find.text('Browse templates'), findsOneWidget);
      expect(find.textContaining('Files show a live preview on the board'), findsOneWidget);

      // Search narrows it down.
      await tester.enterText(find.byType(TextField), 'pdf');
      await tester.pump();
      expect(find.text('PDF'), findsNWidgets(2)); // its badge and its name
      expect(find.text('Sticky note'), findsNothing);
      expect(find.text('ON THE PAGE'), findsNothing);
      expect(find.text('This tablet'), findsNothing);
      await tester.enterText(find.byType(TextField), 'lined');
      await tester.pump();
      expect(find.text('Paper frame'), findsOneWidget); // found by what it is
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();
      expect(find.text('Nothing to insert matches “zzz”.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      // Later phases open a card and leave the menu open.
      await tester.tap(find.text('Kanban board'));
      await tester.pumpAndSettle();
      expect(find.text('Coming soon'), findsOneWidget);
      expect(find.text('To do, Doing and Done columns, with cards you can drag across.'), findsOneWidget);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.text('Coming soon'), findsNothing);
      expect(find.text('ON THE PAGE'), findsOneWidget);
      await tester.tap(find.text('Google Drive'));
      await tester.pumpAndSettle();
      expect(find.text('Pick files straight from Google Drive.'), findsOneWidget);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();

      // What exists closes the menu and starts.
      await tester.tap(find.text('Text box'));
      await tester.pumpAndSettle();
      expect(find.text('ON THE PAGE'), findsNothing);
      expect(c.read(settingsProvider).tool, CanvasTool.text);
      expect(find.text(placeHints[CanvasTool.text]!), findsOneWidget);

      await _rail(tester, 'Insert', 'Everything else');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Browse templates'));
      await tester.pumpAndSettle();
      expect(find.text('Cornell notes'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('every tile outside this phase opens its own card', (tester) async {
      await pumpCanvas(tester, store: _storeWith(const []));
      await _rail(tester, 'Insert', 'Everything else');
      await tester.pumpAndSettle();
      final later = [
        for (final s in insertSections)
          for (final e in s.entries)
            if (e.action == null) e,
        for (final e in insertSources)
          if (e.action == null) e,
      ];
      expect(later.map((e) => e.label), [
        'Video', 'Audio', 'PDF', 'Word document', 'PowerPoint', 'Excel sheet', //
        'Math', 'Graph', 'Table', 'Diagram', 'Timeline', 'Kanban board', 'Website', //
        'Calendar', 'Planner', 'Flashcards', 'Need to remember', 'Chart', 'Clock & date', 'Checklist', //
        'Google Drive', 'OneDrive', 'Scan a document',
      ]);
      for (final e in later) {
        await tester.tap(find.bySemanticsLabel(e.label));
        await tester.pumpAndSettle();
        expect(find.text('Coming soon'), findsOneWidget, reason: e.label);
        expect(find.text(e.soon!), findsOneWidget, reason: e.label);
        await tester.tap(find.text('Got it'));
        await tester.pumpAndSettle();
      }
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('Record audio in the flyout opens the card too', (tester) async {
      await pumpCanvas(tester, store: _storeWith(const []));
      await _rail(tester, 'Insert', 'Record audio');
      await tester.pumpAndSettle();
      expect(find.text('Coming soon'), findsOneWidget);
      expect(find.text('Audio'), findsOneWidget);
      expect(find.textContaining('Record while you write'), findsOneWidget);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('the whole board', () {
    testWidgets('shows everything with no menus; a tap zooms in there; the button goes back', (tester) async {
      final near = newSticky(const Offset(400, 400), z: 1, now: _at);
      final far = newFrame(const Offset(3200, 1900), z: 0, now: _at);
      final c = await pumpCanvas(tester, store: _storeWith([far, near]));
      final view = canvasPane.view;
      view.panBy(const Offset(-40, -20));
      await tester.pump();
      final before = (view.scale, view.translation);

      await _pick(tester, 'Zoom out to the whole board');
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 200));
      expect(view.scale, lessThan(0.5));
      expect(view.visiblePage.contains(near.extent.topLeft), isTrue);
      expect(view.visiblePage.contains(far.extent.bottomRight), isTrue);
      for (final gone in ['Undo', 'Insert', 'Share', 'Hide pages', 'Hide map']) {
        expect(byLabel(gone), findsNothing, reason: gone);
      }
      expect(byLabel('Back from the whole board'), findsOneWidget);
      expect(find.text(boardHint), findsOneWidget);

      // The pen doesn't write here.
      await _pen(tester, _line(const Offset(300, 300), const Offset(500, 300)));
      expect(_items(c), hasLength(2));
      expect(byLabel('Back from the whole board'), findsOneWidget); // a drag isn't a tap

      // Tap the far frame: back at the zoom you had, centered there, menus back.
      final target = view.toScreen(far.center);
      await _pen(tester, [target]);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 200));
      expect(view.scale, closeTo(1, 1e-9));
      expect((view.toPage(const Offset(640, 400)) - far.center).distance, lessThan(1));
      expect(byLabel('Undo'), findsOneWidget);
      expect(byLabel('Zoom out to the whole board'), findsOneWidget);

      // The button, and Esc, go back to exactly where you were.
      view.jumpTo(before.$1, before.$2);
      for (final leave in [() => _pick(tester, 'Back from the whole board'), () => tester.sendKeyEvent(LogicalKeyboardKey.escape)]) {
        await _pick(tester, 'Zoom out to the whole board');
        await tester.pump(const Duration(milliseconds: 350));
        expect(view.scale, lessThan(0.5));
        await leave();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        await tester.pump(const Duration(milliseconds: 200));
        expect(view.scale, closeTo(before.$1, 1e-9));
        expect((view.translation - before.$2).distance, lessThan(1e-6));
      }

      // A finger taps to zoom in as well; two fingers still pinch.
      await _pick(tester, 'Zoom out to the whole board');
      await tester.pump(const Duration(milliseconds: 350));
      await _fingerTap(tester, view.toScreen(near.center));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 200));
      expect(view.scale, closeTo(1, 1e-9));
      expect((view.toPage(const Offset(640, 400)) - near.center).distance, lessThan(1));
      await tester.pump(const Duration(seconds: 5));
    });
  });

  testWidgets('everything put on the page is saved and comes back', (tester) async {
    final store = _storeWith(const []);
    final c = await pumpCanvas(tester, store: store);
    await _useTool(tester, c, CanvasTool.frame);
    await _pen(tester, const [Offset(420, 160)]);
    await _useTool(tester, c, CanvasTool.sticky);
    await _pen(tester, const [Offset(950, 300)]);
    await _pen(tester, _line(const Offset(900, 280), const Offset(1000, 290))); // on the note
    await _useTool(tester, c, CanvasTool.stack);
    await _pen(tester, const [Offset(950, 600)]);
    await _pick(tester, 'Text');
    await _pen(tester, const [Offset(250, 300)]);
    await tester.enterText(find.byType(TextField), 'Lab 4');
    await _pick(tester, 'Done typing');
    await tester.pump(const Duration(seconds: 1));

    final id = canvasPane.notebookId;
    final saved = decodePage(store.pages[id]!.values.single);
    expect(saved.items.map((i) => i.type), ['frame', 'sticky', 'sticky', 'text']);
    expect((saved.items[1] as StickyItem).ink, hasLength(1));
    expect((saved.items[2] as StickyItem).count, 3);
    expect((saved.items[3] as TextItem).text, 'Lab 4');
    expect(find.textContaining('· Saved'), findsOneWidget);

    // Loaded again from storage, it's all there.
    final again = (await store.loadNotebook(id))!;
    expect(again.pages.single.items.map((i) => i.runtimeType), [FrameItem, StickyItem, StickyItem, TextItem]);
    await tester.pump(const Duration(seconds: 5));
  });
}
