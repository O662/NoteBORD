import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/library/library.dart';
import 'package:endless/library/thumbs.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:endless/ui/canvas/canvas_screen.dart';
import 'package:endless/ui/routes.dart';
import 'package:endless/ui/settings/settings_rows.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

List<Item> _items(ProviderContainer c) => shownPage(c).items;

Future<void> _stylusStroke(
  WidgetTester tester,
  List<Offset> points, {
  int buttons = kPrimaryButton,
  Duration start = const Duration(seconds: 10),
  PointerDeviceKind kind = PointerDeviceKind.stylus,
}) async {
  final g = await tester.createGesture(kind: kind, buttons: buttons);
  var t = start;
  await g.down(points.first, timeStamp: t);
  for (final p in points.skip(1)) {
    t += const Duration(milliseconds: 8);
    await g.moveTo(p, timeStamp: t);
  }
  await g.up(timeStamp: t);
  await tester.pump();
}

final _scribble = [for (var i = 0; i <= 20; i++) Offset(400 + i * 10.0, 400 + (i.isEven ? 0 : 12))];

void main() {
  setUpAll(loadAppFonts);

  testWidgets('shows the floating chrome with labels for every button', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpCanvas(tester, store: storeWith(sampleNotebook()));

    expect(find.text('Physics — Lecture notes'), findsOneWidget);
    expect(find.text('Page 1 of 4 · Saved on this tablet'), findsOneWidget);
    for (final label in [
      'Back to library', 'Undo', 'Redo', 'Select', 'Lasso select', 'Pen', 'Marker', 'Eraser', 'Shapes', 'Text',
      'Quick color: Ink black', 'Quick color: Deep blue', 'Quick color: Terracotta', 'More colors',
      'Color and thickness', 'Share', 'More options',
      'Insert', 'Study & math', 'Writing help', 'Ruler, laser & view', 'Search',
      'Previous page', 'Next page', 'Preview this page', 'Show all pages', 'Page options',
      'Zoom out', 'Zoom level 100%, tap to reset', 'Zoom in', 'Zoom out to the whole board',
      'Full screen: hide menus', 'Hide map', 'Add a color', 'Edit colors: change or remove',
    ]) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
    // Update 01: no Export button and no spell check in the top bar; no map button while the map shows.
    for (final gone in ['Export', 'Spell check and dictionary', 'Show map', 'Password protect']) {
      expect(find.bySemanticsLabel(gone), findsNothing, reason: gone);
    }
    expect(find.text('6/10'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('Tap the pen again for colors and thickness'), findsOneWidget);

    // Buttons are 44×44, except where the design itself is tighter: the
    // 36–40 px wide color swatches, the 40×40 zoom pill buttons and the 36 px map toggle.
    for (final e in find.byType(InkWell).evaluate()) {
      final size = e.size!;
      expect(size.shortestSide, greaterThanOrEqualTo(36), reason: '$size');
      expect(size.longestSide, greaterThanOrEqualTo(40), reason: '$size');
    }
    semantics.dispose();
  });

  testWidgets('the S Pen draws with pressure and the stroke autosaves', (tester) async {
    final store = MemoryBoardStore();
    final c = await pumpCanvas(tester, store: store);
    store.pageWrites = 0;

    await _stylusStroke(tester, _scribble);
    expect(_items(c), hasLength(1));
    final s = _items(c).single as StrokeItem;
    expect(s.tool, InkTool.pen);
    expect(s.color, tokens.inkDefaults[1]);
    expect(s.points, hasLength(_scribble.length));
    expect(find.textContaining('Saving…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    expect(store.pageWrites, 1);
    expect(find.textContaining('· Saved'), findsOneWidget);

    await tester.tap(byLabel('Undo'));
    await tester.pump();
    expect(_items(c), isEmpty);
    await tester.tap(byLabel('Redo'));
    await tester.pump();
    expect(_items(c), hasLength(1));
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('an autosave waits for the pen to lift, then happens at once', (tester) async {
    final store = MemoryBoardStore();
    await pumpCanvas(tester, store: store);
    store.pageWrites = 0;

    await _stylusStroke(tester, _scribble);
    // The next word starts before the save is due, and is still being
    // written when it would have been.
    final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    var t = const Duration(seconds: 30);
    await pen.down(const Offset(400, 600), timeStamp: t);
    for (var i = 1; i <= 8; i++) {
      t += const Duration(milliseconds: 100);
      await pen.moveTo(Offset(400 + i * 12.0, 600 + (i.isEven ? 0 : 10)), timeStamp: t);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(store.pageWrites, 0, reason: 'nothing is written mid-stroke');
    await pen.up(timeStamp: t);
    await tester.pump();
    expect(store.pageWrites, 1, reason: 'written as the pen lifts');
    // With the stroke just finished too.
    final saved = (await store.loadNotebook(canvasPane.notebookId))!.pages[canvasPane.page];
    expect(saved.items, hasLength(2));
    await tester.pump(const Duration(milliseconds: 600));
    expect(store.pageWrites, 1);
    expect(find.textContaining('· Saved'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('autosaves make the library cover again only now and then', (tester) async {
    final c = await pumpCanvas(tester);
    InkThumb? cover() => c.read(libraryProvider).byId(canvasPane.notebookId)!.thumb;

    await _stylusStroke(tester, _scribble);
    await tester.pump(const Duration(milliseconds: 600));
    expect(cover()!.strokes, hasLength(1));

    // Another stroke saved soon after: the cover waits (making it reads all
    // the ink on the page).
    await _stylusStroke(tester, [for (final p in _scribble) p + const Offset(0, 100)]);
    await tester.pump(const Duration(milliseconds: 600));
    expect(cover()!.strokes, hasLength(1));

    // Leaving the notebook (or the app going to the background) catches it up.
    await c.read(notebookProvider(canvasPane.notebookId).notifier).flush();
    await tester.pump();
    expect(cover()!.strokes, hasLength(2));
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('going back to the library shows the cover with what was just written', (tester) async {
    // Opened from the library, as on the tablet.
    final c = await pumpApp(tester, store: storeWith(sampleNotebook()), location: Routes.all);
    await tester.tap(find.text('Physics — Lecture notes'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    canvasPane = tester.widget<CanvasScreen>(find.byType(CanvasScreen)).pane;
    final id = canvasPane.notebookId;
    final before = c.read(libraryProvider).byId(id)!.thumb;
    expect(before, isNotNull, reason: 'it has a cover already');
    int inked() => shownPage(c).items.whereType<StrokeItem>().length;

    await _stylusStroke(tester, _scribble);
    await tester.pump(const Duration(milliseconds: 600));
    await _stylusStroke(tester, [for (final p in _scribble) p + const Offset(0, 100)]);
    await tester.pump(const Duration(milliseconds: 600));
    final strokes = inked();

    await tester.tap(byLabel('Back to library'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(c.read(libraryProvider).byId(id)!.thumb!.strokes, hasLength(strokes));
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('fingers pan and pinch-zoom but never draw', (tester) async {
    final c = await pumpCanvas(tester);
    final one = await tester.startGesture(const Offset(500, 400));
    await one.moveBy(const Offset(-120, -40));
    await one.up();
    await tester.pump();
    expect(_items(c), isEmpty);

    final a = await tester.startGesture(const Offset(500, 400), pointer: 11);
    final b = await tester.startGesture(const Offset(700, 400), pointer: 12);
    await a.moveTo(const Offset(400, 400));
    await b.moveTo(const Offset(800, 400));
    await a.up();
    await b.up();
    await tester.pump();
    expect(_items(c), isEmpty);
    expect(find.text('100%'), findsNothing);
    expect(find.text('200%'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the palm is ignored while the S Pen writes, even after it lifts', (tester) async {
    final c = await pumpCanvas(tester);
    final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await pen.down(const Offset(400, 400), timeStamp: const Duration(seconds: 20));
    await pen.moveTo(const Offset(420, 400), timeStamp: const Duration(milliseconds: 20010));

    // The palm lands while the pen writes…
    final palm = await tester.createGesture(pointer: 21);
    await palm.down(const Offset(600, 500), timeStamp: const Duration(milliseconds: 20020));
    await palm.moveTo(const Offset(610, 500), timeStamp: const Duration(milliseconds: 20030));
    await pen.moveTo(const Offset(460, 400), timeStamp: const Duration(milliseconds: 20040));
    await pen.up(timeStamp: const Duration(milliseconds: 20050));
    // …and slides off as the hand moves on, long after: the page stays put.
    await palm.moveTo(const Offset(800, 450), timeStamp: const Duration(seconds: 22));
    await palm.up(timeStamp: const Duration(seconds: 22));
    await tester.pump();
    expect(canvasPane.view.translation, Offset.zero);
    expect(_items(c), hasLength(1));
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a palm landing while the S Pen hovers is ignored once the pen writes', (tester) async {
    final c = await pumpCanvas(tester);
    final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await pen.addPointer(location: const Offset(400, 400), timeStamp: const Duration(seconds: 20));
    await pen.moveTo(const Offset(405, 400), timeStamp: const Duration(seconds: 20)); // hovering

    // Two contacts of palm, shifting a little: nothing happens yet.
    final a = await tester.createGesture(pointer: 21);
    final b = await tester.createGesture(pointer: 22);
    await a.down(const Offset(600, 500), timeStamp: const Duration(milliseconds: 20100));
    await b.down(const Offset(650, 520), timeStamp: const Duration(milliseconds: 20100));
    await a.moveTo(const Offset(615, 505), timeStamp: const Duration(milliseconds: 20150));
    await b.moveTo(const Offset(640, 530), timeStamp: const Duration(milliseconds: 20150));
    await tester.pump();
    expect(canvasPane.view.translation, Offset.zero);
    expect(find.text('100%'), findsOneWidget);

    // The pen writes: they were the palm, however far they go now.
    await pen.down(const Offset(405, 400), timeStamp: const Duration(milliseconds: 20200));
    await pen.moveTo(const Offset(460, 400), timeStamp: const Duration(milliseconds: 20220));
    await pen.up(timeStamp: const Duration(milliseconds: 20240));
    await a.moveTo(const Offset(400, 600), timeStamp: const Duration(milliseconds: 20300));
    await b.moveTo(const Offset(900, 600), timeStamp: const Duration(milliseconds: 20300));
    await a.up();
    await b.up();
    await tester.pump();
    expect(canvasPane.view.translation, Offset.zero);
    expect(find.text('100%'), findsOneWidget);
    expect(_items(c), hasLength(1));
    await pen.removePointer();
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a finger pans and pinches the first time, even with the S Pen hovering', (tester) async {
    await pumpCanvas(tester);
    final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await pen.addPointer(location: const Offset(900, 600), timeStamp: const Duration(seconds: 20));
    await pen.moveTo(const Offset(905, 600), timeStamp: const Duration(seconds: 20)); // hovering

    // One finger drags: once it's clearly travelling, the page follows it.
    final f = await tester.createGesture(pointer: 21);
    await f.down(const Offset(500, 400), timeStamp: const Duration(milliseconds: 20100));
    await f.moveTo(const Offset(450, 400), timeStamp: const Duration(milliseconds: 20120));
    await pen.moveTo(const Offset(906, 600), timeStamp: const Duration(milliseconds: 20130)); // still hovering
    await f.moveTo(const Offset(350, 380), timeStamp: const Duration(milliseconds: 20150));
    await f.up();
    await tester.pump();
    expect(canvasPane.view.translation, const Offset(-100, -20));

    // Two fingers pinch: it zooms.
    await pen.moveTo(const Offset(905, 600), timeStamp: const Duration(seconds: 21));
    final a = await tester.createGesture(pointer: 22);
    final b = await tester.createGesture(pointer: 23);
    await a.down(const Offset(500, 400), timeStamp: const Duration(milliseconds: 21100));
    await b.down(const Offset(700, 400), timeStamp: const Duration(milliseconds: 21100));
    await a.moveTo(const Offset(450, 400), timeStamp: const Duration(milliseconds: 21120));
    await b.moveTo(const Offset(750, 400), timeStamp: const Duration(milliseconds: 21120));
    await a.moveTo(const Offset(400, 400), timeStamp: const Duration(milliseconds: 21150));
    await b.moveTo(const Offset(800, 400), timeStamp: const Duration(milliseconds: 21150));
    await a.up();
    await b.up();
    await tester.pump();
    expect(find.text('100%'), findsNothing);

    // Once the pen has been gone a while, fingers work straight away.
    final g = await tester.createGesture(pointer: 24);
    final before = canvasPane.view.translation;
    await g.down(const Offset(500, 400), timeStamp: const Duration(seconds: 25));
    await g.moveTo(const Offset(490, 400), timeStamp: const Duration(seconds: 25));
    await g.up();
    await tester.pump();
    expect(canvasPane.view.translation, before + const Offset(-10, 0));
    await pen.removePointer();
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('holding the S Pen button erases, as does the eraser tool', (tester) async {
    final c = await pumpCanvas(tester);
    await _stylusStroke(tester, _scribble);
    await _stylusStroke(tester, [for (final p in _scribble) p + const Offset(0, 150)]);
    expect(_items(c), hasLength(2));

    // Side button held: erases instead of drawing.
    await _stylusStroke(tester, [const Offset(500, 380), const Offset(500, 430)],
        buttons: kPrimaryButton | kPrimaryStylusButton);
    expect(_items(c), hasLength(1));

    await tester.tap(byLabel('Eraser'));
    await tester.pump();
    expect(find.textContaining('Erase whole strokes'), findsOneWidget);
    await _stylusStroke(tester, [const Offset(500, 530), const Offset(500, 580)]);
    expect(_items(c), isEmpty);

    await tester.tap(byLabel('Undo'));
    await tester.pump();
    expect(_items(c), hasLength(1));
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('tapping the pen again opens colors and thickness', (tester) async {
    final c = await pumpCanvas(tester);
    await tester.tap(byLabel('Pen'));
    await tester.pump();
    expect(find.text('Pressure changes thickness'), findsOneWidget);
    expect(find.text('Ballpoint'), findsOneWidget);
    expect(find.text('0.5 mm'), findsOneWidget);
    expect(find.text('6/10'), findsNothing); // the tray hides under the popover

    await tester.tap(find.bySemanticsLabel('Thickness 2.0 mm'));
    await tester.tap(find.text('Fountain'));
    await tester.tap(find.bySemanticsLabel('Terracotta'));
    await tester.tap(find.text('Pressure changes thickness'));
    await tester.pump();
    final s = c.read(settingsProvider);
    expect(s.penSize, 4);
    expect(s.penType, PenType.fountain);
    expect(s.penColor, tokens.inkDefaults[2]);
    expect(s.pressure, isFalse);
    expect(find.text('2.0 mm'), findsOneWidget);

    await tester.tap(byLabel('Close'));
    await tester.pump();
    expect(find.text('Pressure changes thickness'), findsNothing);

    // The marker has its own popover without pen types.
    await tester.tap(byLabel('Marker'));
    await tester.pump();
    await tester.tap(byLabel('Marker'));
    await tester.pump();
    expect(find.text('Ballpoint'), findsNothing);
    expect(find.text('Marker'), findsOneWidget);

    await _stylusStroke(tester, _scribble);
    expect(find.text('Pressure changes thickness'), findsNothing); // writing closes it
    expect((_items(c).single as StrokeItem).tool, InkTool.marker);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the More colors tray adds up to 10 colors and can remove them', (tester) async {
    final c = await pumpCanvas(tester);
    for (var i = 0; i < 4; i++) {
      await tester.tap(byLabel('Add a color'));
      await tester.pump();
    }
    expect(find.text('10/10'), findsOneWidget);
    expect(byLabel('Add a color'), findsNothing);

    await tester.tap(byLabel('Edit colors: change or remove'));
    await tester.pump();
    await tester.tap(byLabel('Remove color: Green'));
    await tester.pump();
    expect(find.text('9/10'), findsOneWidget);
    await tester.tap(byLabel('Done editing colors'));
    await tester.pump();

    await tester.tap(byLabel('Color: Sky blue'));
    await tester.pump();
    expect(c.read(settingsProvider).penColor, tokens.extraInkDefaults[4]);

    await tester.tap(byLabel('More colors'));
    await tester.pump();
    expect(find.text('9/10'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('tapping a rail button pins its menu until a tap outside, a re-tap, or an item', (tester) async {
    final c = await pumpCanvas(tester);

    await tester.tap(byLabel('Insert'));
    await tester.pump();
    expect(find.text('INSERT'), findsOneWidget);
    expect(find.text('Pinned'), findsOneWidget);
    for (final item in ['Sticky note', 'Paper frame', 'Image', 'Record audio', 'Templates', 'Everything else']) {
      expect(find.text(item), findsOneWidget, reason: item);
    }
    expect(find.text('Tap the pen again for colors and thickness'), findsNothing); // hint hides under a pinned menu

    // A pen tap outside only closes the menu; it doesn't draw.
    await _stylusStroke(tester, _scribble);
    expect(find.text('INSERT'), findsNothing);
    expect(_items(c), isEmpty);

    // Re-tapping the same button closes it.
    await tester.tap(byLabel('Study & math'));
    await tester.pump();
    expect(find.text('Math tools'), findsOneWidget);
    await tester.tap(byLabel('Study & math'));
    await tester.pump();
    expect(find.text('Math tools'), findsNothing);

    // Tapping another group switches menus.
    await tester.tap(byLabel('Writing help'));
    await tester.pump();
    await tester.tap(byLabel('Ruler, laser & view'));
    await tester.pump();
    expect(find.text('Spell check'), findsNothing);
    expect(find.text('Laser pointer'), findsOneWidget);

    // Picking an item closes the menu.
    await tester.tap(find.text('Laser pointer'));
    await tester.pump();
    expect(find.text('RULER, LASER & VIEW'), findsNothing);
    // The laser is a tool now: its hint and colors show.
    expect(find.text(toolHints[CanvasTool.laser]!), findsOneWidget);
    expect(find.bySemanticsLabel('Red laser'), findsOneWidget);

    // The close button in a pinned menu.
    await tester.tap(byLabel('Writing help'));
    await tester.pump();
    await tester.tap(byLabel('Close menu'));
    await tester.pump();
    expect(find.text('WRITING HELP'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('hovering the rail with the S Pen or a mouse previews a menu', (tester) async {
    await pumpCanvas(tester);
    for (final kind in [PointerDeviceKind.stylus, PointerDeviceKind.mouse]) {
      final hover = await tester.createGesture(kind: kind);
      await hover.addPointer(location: const Offset(600, 500));
      await hover.moveTo(tester.getCenter(byLabel('Study & math')));
      await tester.pump();
      expect(find.text('STUDY & MATH'), findsOneWidget, reason: '$kind');
      expect(find.text('Tap to keep open'), findsOneWidget);

      // Moving across the gap into the menu keeps it open.
      await hover.moveTo(tester.getCenter(find.text('Make flashcards')));
      await tester.pump();
      expect(find.text('STUDY & MATH'), findsOneWidget);

      // Leaving the rail and menu closes it.
      await hover.moveTo(const Offset(700, 600));
      await tester.pump();
      expect(find.text('STUDY & MATH'), findsNothing, reason: '$kind');
      await hover.removePointer();
    }

    // A tap while previewing pins it; then leaving doesn't close it.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(600, 500));
    await mouse.moveTo(tester.getCenter(byLabel('Writing help')));
    await tester.pump();
    await tester.tap(byLabel('Writing help'), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(find.text('Pinned'), findsOneWidget);
    await mouse.moveTo(const Offset(700, 600));
    await tester.pump();
    expect(find.text('WRITING HELP'), findsOneWidget);
    await mouse.removePointer();
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('⋯ holds Export and the rest; Settings opens the Settings screen', (tester) async {
    final c = await pumpCanvas(tester);
    await tester.tap(byLabel('More options'));
    await tester.pump();
    for (final item in ['Export', 'Import', 'Print…', 'Password protect', 'Page & paper', 'Version history', 'Settings']) {
      expect(find.text(item), findsOneWidget, reason: item);
    }
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    // Export opens Import and export (tested in test/ui/transfer_test.dart).
    expect(find.text('WHAT TO EXPORT'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Import'), findsNothing);

    // Tapping outside closes it.
    await tester.tap(byLabel('More options'));
    await tester.pump();
    await tester.tapAt(const Offset(600, 500));
    await tester.pump();
    expect(find.text('Import'), findsNothing);

    await tester.tap(byLabel('More options'));
    await tester.pump();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('How Endless opens, looks and feels day to day.'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Pen & S Pen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate((w) => w is SettingsSwitch && w.label == 'Fingers can draw'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).fingerDraws, isTrue);
    await tester.tap(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Back to library'));
    await tester.pumpAndSettle();
    expect(find.text('How Endless opens, looks and feels day to day.'), findsNothing);
    expect(byLabel('More options'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  // The Tab S9 FE uses font_scale 1.1; also try well beyond it.
  for (final scale in [1.1, 1.3, 1.5]) {
    testWidgets('the zoom pill fits at font scale $scale in every state', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpCanvas(tester);
      expect(tester.takeException(), isNull, reason: 'default');
      await tester.tap(byLabel('Hide map')); // adds the map button to the pill
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'map hidden');
      await tester.tap(byLabel('Full screen: hide menus'));
      await tester.pump();
      for (var i = 0; i < 12; i++) {
        await tester.tap(byLabel('Zoom in')); // up to 800%
      }
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'full screen, 800%');
      expect(tester.getSize(byLabel('Exit full screen')).width, greaterThanOrEqualTo(30));
      await tester.pump(const Duration(seconds: 5));
    });
  }

  testWidgets('S Pen hover over the chrome shows no tooltip popups', (tester) async {
    await pumpCanvas(tester);
    final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await pen.addPointer(location: const Offset(600, 500));
    for (final label in ['Undo', 'Pen', 'Share', 'More options', 'Zoom in', 'Full screen: hide menus']) {
      await pen.moveTo(tester.getCenter(byLabel(label)));
      await tester.pump(const Duration(seconds: 2));
    }
    expect(find.byType(Tooltip), findsNothing);
    await pen.removePointer();
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('full screen hides every menu except the zoom pill', (tester) async {
    await pumpCanvas(tester);
    await tester.tap(byLabel('Full screen: hide menus'));
    await tester.pump();
    for (final gone in ['Undo', 'Insert', 'Share', 'Page options', 'Hide map', 'More colors']) {
      expect(byLabel(gone), findsNothing, reason: gone);
    }
    expect(byLabel('Zoom in'), findsOneWidget);
    expect(byLabel('Show map'), findsOneWidget);

    await tester.tap(byLabel('Exit full screen'));
    await tester.pump();
    expect(byLabel('Undo'), findsOneWidget);
    expect(byLabel('Hide map'), findsOneWidget);

    // "Show map" from full screen brings the menus back with the map.
    await tester.tap(byLabel('Full screen: hide menus'));
    await tester.pump();
    await tester.tap(byLabel('Show map'));
    await tester.pump();
    expect(byLabel('Undo'), findsOneWidget);
    expect(byLabel('Hide map'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the map collapses into a button on the zoom pill', (tester) async {
    await pumpCanvas(tester);
    await tester.tap(byLabel('Hide map'));
    await tester.pump();
    expect(find.text('Map'), findsNothing);
    await tester.tap(byLabel('Show map'));
    await tester.pump();
    expect(find.text('Map'), findsOneWidget);
    expect(byLabel('Show map'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('zoom buttons and fit', (tester) async {
    await pumpCanvas(tester, store: storeWith(sampleNotebook()));
    await tester.tap(byLabel('Zoom in'));
    await tester.pump();
    expect(find.text('125%'), findsOneWidget);
    await tester.tap(byLabel('Zoom out'));
    await tester.tap(byLabel('Zoom out'));
    await tester.pump();
    expect(find.text('75%'), findsOneWidget);
    await tester.tap(find.text('75%'));
    await tester.pump();
    expect(find.text('100%'), findsOneWidget);
    await tester.tap(byLabel('Zoom out to the whole board'));
    await tester.pump();
    expect(find.text('100%'), findsOneWidget); // page 1 is empty: back to the start
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a mouse draws, and fingers draw only when that is turned on', (tester) async {
    final c = await pumpCanvas(tester);
    await _stylusStroke(tester, _scribble, kind: PointerDeviceKind.mouse);
    expect(_items(c), hasLength(1));

    await tester.dragFrom(const Offset(400, 600), const Offset(200, 0));
    await tester.pump();
    expect(_items(c), hasLength(1));

    c.read(settingsProvider.notifier).apply((s) => s.copyWith(fingerDraws: true));
    await tester.dragFrom(const Offset(400, 600), const Offset(200, 0));
    await tester.pump();
    expect(_items(c), hasLength(2));
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('dark mode brightens ink for display only', (tester) async {
    final store = storeWith(sampleNotebook(), settings: AppSettings(themeMode: ThemeMode.dark));
    final c = await pumpCanvas(tester, store: store);
    final context = tester.element(find.text('Physics — Lecture notes'));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(Theme.of(context).scaffoldBackgroundColor, const Color(0xFF1C1A17));
    await _stylusStroke(tester, _scribble);
    expect((_items(c).single as StrokeItem).color, tokens.inkDefaults[1]); // stored as the original
    await tester.pump(const Duration(seconds: 5));
  });
}
