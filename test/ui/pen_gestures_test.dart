import 'dart:math' as math;

import 'package:endless/board/ids.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/canvas/gestures.dart' show ScribbleLevel;
import 'package:endless/state/settings.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:endless/ui/canvas/canvas_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

List<Item> _items(ProviderContainer c) => shownPage(c).items;

List<StrokeItem> _strokes(ProviderContainer c) => _items(c).whereType<StrokeItem>().toList();

/// A notebook with one page holding [items] (page coords = screen coords).
MemoryBoardStore _storeWith(List<Item> items, {AppSettings? settings}) {
  final now = DateTime.utc(2026, 9, 25, 9);
  final page = BoardPage(id: newId('pg'), items: items);
  final nb = Notebook(id: newId('nb'), title: 'Gestures', createdAt: now, updatedAt: now, pageIds: [page.id]);
  return storeWith(LoadedNotebook(nb, [page]), settings: settings);
}

/// Draws [points] with the S Pen, 8 ms apart. With [hold], the pen stays
/// down at the last point that long before lifting.
Future<TestGesture> _pen(WidgetTester tester, List<Offset> points, {Duration? hold, bool lift = true}) async {
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
  if (lift) await g.up(timeStamp: t + (hold ?? Duration.zero));
  await tester.pump();
  return g;
}

List<Offset> _line(Offset a, Offset b, {int n = 40, double wobble = 3}) => [
      for (var i = 0; i <= n; i++) Offset.lerp(a, b, i / n)! + Offset(0, math.sin(i / n * math.pi * 3) * wobble),
    ];

List<Offset> _zigzag(Offset from, {int legs = 8, double amp = 34, double step = 13}) {
  final corners = [for (var i = 0; i <= legs; i++) from + Offset(i * step, i.isEven ? 0 : -amp)];
  return [
    for (var i = 0; i < legs; i++)
      for (var s = 0; s < 6; s++) Offset.lerp(corners[i], corners[i + 1], s / 6)!,
    corners.last,
  ];
}

/// A small "word" of ink at [at].
StrokeItem _word(Offset at, {Color? color}) =>
    strokeFrom([for (var i = 0; i <= 30; i++) at + Offset(i * 2.0, 8 * math.sin(i / 3))], color: color);

Future<void> _pickTool(WidgetTester tester, String label) async {
  await tester.tap(byLabel(label));
  await tester.pump();
}

void main() {
  setUpAll(loadAppFonts);

  group('hold to straighten', () {
    testWidgets('holding at the end snaps to a line; Undo gives the ink back', (tester) async {
      final c = await pumpCanvas(tester, store: _storeWith(const []));
      final shaky = _line(const Offset(300, 450), const Offset(604, 336));

      final g = await tester.createGesture(kind: PointerDeviceKind.stylus);
      await g.down(shaky.first);
      for (final p in shaky.skip(1)) {
        await g.moveTo(p);
      }
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Hold to straighten…'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Hold to straighten…'), findsNothing);
      await g.up();
      await tester.pump();

      final s = _strokes(c).single;
      expect(s.straightened, 'line');
      for (final p in s.pagePoints) {
        // Every point on the chord from the first point to the last.
        final a = s.pagePoints.first, b = s.pagePoints.last;
        final d = b - a;
        expect(((p - a).dx * d.dy - (p - a).dy * d.dx).abs() / d.distance, lessThan(0.5));
      }
      expect(find.text('Line straightened'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Undo: Line straightened'));
      await tester.pump();
      expect(_strokes(c).single.straightened, isNull);
      expect(_strokes(c).single.points, hasLength(shaky.length));
      expect(find.text('Line straightened'), findsNothing);
      await tester.tap(byLabel('Undo'));
      await tester.pump();
      expect(_items(c), isEmpty);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a circle and a rectangle', (tester) async {
      final c = await pumpCanvas(tester, store: _storeWith(const []));
      final circle = [
        for (var i = 0; i <= 60; i++)
          const Offset(400, 400) + Offset(math.cos(i / 60 * 2.1 * math.pi), math.sin(i / 60 * 2.1 * math.pi)) * 90,
      ];
      await _pen(tester, circle, hold: const Duration(milliseconds: 600));
      expect(_strokes(c).last.straightened, 'circle');
      expect(find.text('Circle straightened'), findsOneWidget);

      final rect = [
        ..._line(const Offset(600, 250), const Offset(820, 250), n: 20, wobble: 1),
        ..._line(const Offset(820, 250), const Offset(820, 380), n: 20, wobble: 0).skip(1),
        ..._line(const Offset(820, 380), const Offset(600, 380), n: 20, wobble: 1).skip(1),
        ..._line(const Offset(600, 380), const Offset(600, 252), n: 20, wobble: 0).skip(1),
      ];
      await _pen(tester, rect, hold: const Duration(milliseconds: 600));
      expect(_strokes(c).last.straightened, 'rect');
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('does nothing when "snap shapes" is off, or without a hold', (tester) async {
      final c = await pumpCanvas(tester, store: _storeWith(const [], settings: AppSettings(snap: false)));
      await _pen(tester, _line(const Offset(300, 450), const Offset(604, 336)), hold: const Duration(milliseconds: 700));
      expect(_strokes(c).single.straightened, isNull);
      expect(find.text('Hold to straighten…'), findsNothing);

      c.read(settingsProvider.notifier).apply((s) => s.copyWith(snap: true));
      await _pen(tester, _line(const Offset(300, 550), const Offset(604, 436)));
      expect(_strokes(c).last.straightened, isNull);
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('flick back for an arrow', () {
    final line = _line(const Offset(300, 450), const Offset(580, 340), n: 50, wobble: 1);
    List<Offset> hooked() => [...line, for (var i = 1; i <= 5; i++) Offset.lerp(line.last, const Offset(556, 358), i / 5)!];

    testWidgets('a quick hook makes an arrowhead in the chosen style; Undo keeps the ink', (tester) async {
      final c = await pumpCanvas(
        tester,
        store: _storeWith(const [], settings: AppSettings(arrowStyle: ArrowStyle.filled)),
      );
      await _pen(tester, hooked());
      final s = _strokes(c).single;
      expect(s.arrow, const ArrowHeads(end: true, style: ArrowStyle.filled));
      expect(s.points, hasLength(lessThan(hooked().length)));
      expect(find.text('Made an arrow'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Undo: Made an arrow'));
      await tester.pump();
      expect(_strokes(c).single.arrow, isNull);
      expect(_strokes(c).single.points, hasLength(hooked().length));
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('off in the popover means plain ink', (tester) async {
      final c = await pumpCanvas(tester, store: _storeWith(const [], settings: AppSettings(arrows: false)));
      await _pen(tester, hooked());
      expect(_strokes(c).single.arrow, isNull);
      expect(find.text('Made an arrow'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the next stroke dismisses the Undo toast', (tester) async {
      final c = await pumpCanvas(tester, store: _storeWith(const []));
      await _pen(tester, hooked());
      expect(find.text('Made an arrow'), findsOneWidget);
      await _pen(tester, _line(const Offset(300, 600), const Offset(500, 600)));
      expect(find.text('Made an arrow'), findsNothing);
      expect(_strokes(c), hasLength(2));
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('scribble to erase', () {
    testWidgets('erases only the strokes under the scribble, and Undo brings them back', (tester) async {
      final oops = _word(const Offset(430, 400));
      final keep = _word(const Offset(250, 400));
      final c = await pumpCanvas(tester, store: _storeWith([keep, oops]));

      final zig = _zigzag(const Offset(422, 418));
      final g = await _pen(tester, zig, lift: false);
      expect(find.text('Lift the pen to erase 1 stroke'), findsOneWidget);
      await g.up();
      await tester.pump();
      expect(_items(c).map((i) => i.id), [keep.id]);
      expect(find.text('Erased 1 stroke'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Undo: Erased 1 stroke'));
      await tester.pump();
      expect(_items(c).map((i) => i.id), [keep.id, oops.id]);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('over empty paper, or with Firm sensitivity or the toggle off, it stays ink', (tester) async {
      final oops = _word(const Offset(430, 400));
      final c = await pumpCanvas(
        tester,
        store: _storeWith([oops], settings: AppSettings(scribbleLevel: ScribbleLevel.firm)),
      );
      await _pen(tester, _zigzag(const Offset(422, 418)));
      expect(_items(c), hasLength(2)); // Firm needs a denser scribble

      c.read(settingsProvider.notifier).apply((s) => s.copyWith(scribbleLevel: ScribbleLevel.normal, scribble: false));
      await _pen(tester, _zigzag(const Offset(422, 418)));
      expect(_items(c), hasLength(3));

      c.read(settingsProvider.notifier).apply((s) => s.copyWith(scribble: true));
      await _pen(tester, _zigzag(const Offset(700, 600)));
      expect(_items(c), hasLength(4)); // nothing under it
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('select and lasso', () {
    Future<(ProviderContainer, StrokeItem, StrokeItem)> lassoed(WidgetTester tester) async {
      final a = _word(const Offset(400, 400));
      final b = _word(const Offset(700, 300), color: tokens.inkDefaults[2]);
      final c = await pumpCanvas(tester, store: _storeWith([a, b]));
      await _pickTool(tester, 'Lasso select');
      final loop = [
        for (var i = 0; i <= 40; i++) const Offset(430, 400) + Offset(math.cos(i / 40 * 2 * math.pi) * 70, math.sin(i / 40 * 2 * math.pi) * 40),
      ];
      await _pen(tester, loop);
      return (c, a, b);
    }

    testWidgets('a lasso selects what it circles and shows the Convert toolbar', (tester) async {
      await lassoed(tester);
      for (final label in ['Convert to text', 'Copy', 'Color', 'Straighten lines', 'Delete']) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      await tester.tap(find.bySemanticsLabel('Convert to text'));
      await tester.pump();
      expect(find.text('Convert to text is coming soon'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('delete, then undo', (tester) async {
      final (c, a, b) = await lassoed(tester);
      await tester.tap(find.bySemanticsLabel('Delete'));
      await tester.pump();
      expect(_items(c).map((i) => i.id), [b.id]);
      expect(find.bySemanticsLabel('Selection actions'), findsNothing);
      await tester.tap(byLabel('Undo'));
      await tester.pump();
      expect(_items(c).map((i) => i.id), [a.id, b.id]);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('drag to move is one undo step', (tester) async {
      final (c, a, _) = await lassoed(tester);
      await _pen(tester, _line(const Offset(430, 400), const Offset(530, 460), n: 10, wobble: 0));
      final moved = _strokes(c).first;
      expect(moved.id, a.id);
      expect(moved.x, closeTo(a.x + 100, 0.2));
      expect(moved.y, closeTo(a.y + 60, 0.2));
      expect(find.bySemanticsLabel('Selection actions'), findsOneWidget); // still selected

      await tester.tap(byLabel('Undo'));
      await tester.pump();
      expect(_strokes(c).first.x, a.x);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('one finger moves the selection; two fingers pinch it', (tester) async {
      final (c, a, _) = await lassoed(tester);
      // Touch timestamps well after the pen's, so they're not taken for the palm.
      const later = Duration(minutes: 5);
      final f = await tester.createGesture(kind: PointerDeviceKind.touch);
      await f.down(const Offset(430, 400), timeStamp: later);
      await f.moveTo(const Offset(480, 400), timeStamp: later);
      await f.up(timeStamp: later);
      await tester.pump();
      expect(_strokes(c).first.x, closeTo(a.x + 50, 0.2));

      final f1 = await tester.createGesture(kind: PointerDeviceKind.touch, pointer: 20);
      final f2 = await tester.createGesture(kind: PointerDeviceKind.touch, pointer: 21);
      await f1.down(const Offset(460, 400), timeStamp: later);
      await f2.down(const Offset(500, 400), timeStamp: later);
      await f1.moveTo(const Offset(440, 400), timeStamp: later);
      await f2.moveTo(const Offset(520, 400), timeStamp: later);
      await f1.up(timeStamp: later);
      await f2.up(timeStamp: later);
      await tester.pump();
      final s = _strokes(c).first;
      expect(s.width, closeTo(a.width * 2, 0.01));
      expect(s.bounds.width, greaterThan(a.bounds.width * 1.8));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('resize and rotate with the handles', (tester) async {
      final (c, a, _) = await lassoed(tester);
      final before = _strokes(c).first.bounds;
      // The bottom-right corner handle of the lasso's box (430 ± 70, 400 ± 40).
      await _pen(tester, _line(const Offset(500, 440), const Offset(570, 480), n: 10, wobble: 0));
      final resized = _strokes(c).first;
      expect(resized.bounds.width, greaterThan(before.width * 1.4));
      expect(resized.width, greaterThan(a.width));

      await tester.tap(byLabel('Undo'));
      await tester.pump();
      // The rotate knob, 30 px under the box (the outline is now a box around the stroke).
      final box = _strokes(c).first.bounds.inflate(8);
      final knob = box.bottomCenter + const Offset(0, 30);
      await _pen(tester, [
        for (var i = 0; i <= 10; i++)
          box.center + Offset(math.cos(math.pi / 2 - i / 10 * math.pi / 2), math.sin(math.pi / 2 - i / 10 * math.pi / 2)) * (knob - box.center).distance,
      ]);
      final turned = _strokes(c).first.bounds;
      expect(turned.height, greaterThan(turned.width)); // a wide word turned upright
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('copy, recolor and straighten', (tester) async {
      final (c, a, _) = await lassoed(tester);
      await tester.tap(find.bySemanticsLabel('Copy'));
      await tester.pump();
      expect(_strokes(c), hasLength(3));
      final copy = _strokes(c).last;
      expect(copy.id, isNot(a.id));
      expect(copy.x, closeTo(a.x + 24, 0.2));

      await tester.tap(find.bySemanticsLabel('Color'));
      await tester.pump();
      await tester.tap(byLabel('Change color to Green'));
      await tester.pump();
      expect(_strokes(c).last.color, tokens.extraInkDefaults[0]);
      expect(_strokes(c).first.color, a.color); // only the copy was selected

      await tester.tap(find.bySemanticsLabel('Straighten lines'));
      await tester.pump();
      expect(find.text('Nothing here to straighten'), findsOneWidget); // a wavy word is no shape
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('the Select tool: tap a stroke, or drag a box', (tester) async {
      final a = _word(const Offset(400, 400));
      final b = strokeFrom(_line(const Offset(600, 300), const Offset(800, 300), wobble: 0));
      final c = await pumpCanvas(tester, store: _storeWith([a, b]));
      await _pickTool(tester, 'Select');
      expect(find.text(toolHints[CanvasTool.select]!), findsOneWidget);

      await _pen(tester, const [Offset(700, 300)]);
      expect(find.bySemanticsLabel('Selection actions'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Straighten lines'));
      await tester.pump();
      expect(_strokes(c).last.straightened, 'line');

      // Tapping empty paper clears; a box selects what it covers.
      await _pen(tester, const [Offset(300, 650)]);
      expect(find.bySemanticsLabel('Selection actions'), findsNothing);
      await _pen(tester, _line(const Offset(380, 370), const Offset(480, 430), n: 8, wobble: 0));
      await tester.tap(find.bySemanticsLabel('Delete'));
      await tester.pump();
      expect(_items(c).map((i) => i.id), [b.id]);

      // Picking the pen ends selecting.
      await _pickTool(tester, 'Pen');
      expect(find.bySemanticsLabel('Selection actions'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('"Need to remember" starts a lasso that leads with Remember', (tester) async {
      final a = _word(const Offset(400, 400));
      await pumpCanvas(tester, store: _storeWith([a]));
      await tester.tap(byLabel('Study & math'));
      await tester.pump();
      await tester.tap(find.text('Need to remember'));
      await tester.pump();
      expect(find.text('Circle what you need to remember'), findsOneWidget);
      await _pen(tester, [
        for (var i = 0; i <= 40; i++) const Offset(430, 400) + Offset(math.cos(i / 40 * 2 * math.pi) * 70, math.sin(i / 40 * 2 * math.pi) * 40),
      ]);
      for (final label in ['Remember', 'To text', 'Flashcard', 'Copy', 'Delete']) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      await tester.tap(find.bySemanticsLabel('Remember'));
      await tester.pump();
      expect(find.text('Need to remember is coming soon'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('ruler and laser', () {
    Future<void> openRailItem(WidgetTester tester, String label) async {
      await tester.tap(byLabel('Ruler, laser & view'));
      await tester.pump();
      await tester.tap(find.text(label));
      await tester.pump();
    }

    testWidgets('the pen follows the ruler edge; two fingers turn it', (tester) async {
      final c = await pumpCanvas(tester, store: _storeWith(const []));
      await openRailItem(tester, 'Ruler');
      expect(find.text(rulerHint), findsOneWidget);
      // The ruler sits level across the lower middle: center (640, 496), 72 tall.
      await _pen(tester, _line(const Offset(420, 452), const Offset(760, 440), n: 30, wobble: 4));
      final s = _strokes(c).single;
      final ys = s.pagePoints.map((p) => p.dy).toSet();
      expect(ys.reduce(math.max) - ys.reduce(math.min), lessThan(0.2));
      expect(ys.first, lessThan(496 - 36)); // just outside the top edge
      expect(s.straightened, isNull);

      const later = Duration(minutes: 5);
      final f1 = await tester.createGesture(kind: PointerDeviceKind.touch, pointer: 30);
      final f2 = await tester.createGesture(kind: PointerDeviceKind.touch, pointer: 31);
      await f1.down(const Offset(540, 496), timeStamp: later);
      await f2.down(const Offset(740, 496), timeStamp: later);
      await f2.moveTo(Offset(740, 496 - 200 * math.tan(20 * math.pi / 180)), timeStamp: later);
      await tester.pump();
      await f1.up(timeStamp: later);
      await f2.up(timeStamp: later);
      await tester.pump();
      expect(canvasPane.ruler.degrees, 20);
      expect(canvasPane.view.translation, Offset.zero); // the page didn't pan

      await openRailItem(tester, 'Ruler');
      expect(canvasPane.ruler.visible, isFalse);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('the laser draws a fading trail and saves nothing', (tester) async {
      final store = _storeWith(const []);
      final c = await pumpCanvas(tester, store: store);
      await openRailItem(tester, 'Laser pointer');
      expect(find.bySemanticsLabel('Green laser'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Green laser'));
      await tester.pump();
      expect(c.read(settingsProvider).laserColor, 1);

      store.pageWrites = 0;
      await _pen(tester, _line(const Offset(300, 400), const Offset(700, 450)));
      await tester.pump(const Duration(seconds: 2));
      expect(_items(c), isEmpty);
      expect(store.pageWrites, 0);
      expect(find.byTooltip('Undo'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
