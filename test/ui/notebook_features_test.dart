import 'package:endless/board/model.dart';
import 'package:endless/library/library.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/templates/templates.dart';
import 'package:endless/ui/canvas/canvas_screen.dart';
import 'package:endless/ui/routes.dart';
import 'package:endless/ui/split/split_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../sample_library.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

Future<void> _stylus(WidgetTester tester, List<Offset> points, {Duration start = const Duration(seconds: 10)}) async {
  final g = await tester.createGesture(kind: PointerDeviceKind.stylus);
  var t = start;
  await g.down(points.first, timeStamp: t);
  for (final p in points.skip(1)) {
    t += const Duration(milliseconds: 8);
    await g.moveTo(p, timeStamp: t);
  }
  await g.up(timeStamp: t);
  await tester.pump();
}

List<Offset> _scribble(Offset at) => [for (var i = 0; i <= 12; i++) at + Offset(i * 10.0, i.isEven ? 0 : 12)];

Future<ProviderContainer> _openPhysics(WidgetTester tester, {FakeBiometric? biometric}) async {
  final (store, db) = await sampleLibrary();
  final c = await pumpApp(tester, store: store, index: db, location: Routes.notebook('nb_physics', page: 2), biometric: biometric);
  canvasPane = tester.widget<CanvasScreen>(find.byType(CanvasScreen)).pane;
  return c;
}

Future<void> _openTemplates(WidgetTester tester) async {
  await tester.tap(byLabel('Insert'));
  await tester.pump();
  await tester.tap(find.text('Templates'));
  await _pump(tester);
}

void main() {
  setUpAll(loadAppFonts);

  group('Templates', () {
    testWidgets('lists every template by category and adds a page from one', (tester) async {
      final c = await _openPhysics(tester);
      await _openTemplates(tester);
      for (final t in builtInTemplates) {
        expect(find.bySemanticsLabel(t.name), findsOneWidget, reason: t.name);
      }
      for (final label in ['All', 'Paper', 'Study', 'Planning', 'Boards', 'My templates', 'New page', 'Frame', 'New notebook']) {
        expect(find.bySemanticsLabel(label), findsWidgets, reason: label);
      }
      expect(find.text('Use “Cornell notes”'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Study'));
      await _pump(tester);
      expect(find.bySemanticsLabel('Dot grid'), findsNothing);
      expect(find.bySemanticsLabel('Lab report'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Lab report'));
      await tester.pump();
      await tester.tap(find.text('Use “Lab report”'));
      await _pump(tester);

      expect(find.textContaining('Page 4 of 13'), findsOneWidget);
      final page = shownPage(c).page;
      expect(page.template, 'lab');
      expect(page.paper, Paper.lines);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('saves this page as a template and reuses it', (tester) async {
      final c = await _openPhysics(tester);
      await _openTemplates(tester);
      await tester.tap(find.bySemanticsLabel('Save as template, from this page'));
      await _pump(tester);
      await tester.enterText(find.byType(TextField), 'Lecture layout');
      await tester.pump();
      await tester.tap(find.text('Save').last);
      await _pump(tester);
      expect(find.bySemanticsLabel('Lecture layout'), findsOneWidget);
      expect(find.text('Use “Lecture layout”'), findsOneWidget);
      await tester.tap(find.text('Use “Lecture layout”'));
      await _pump(tester);
      expect(shownPage(c).items, hasLength(14));
      expect(c.read(userTemplatesProvider).single.name, 'Lecture layout');
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('from the Start page, a template starts a new notebook', (tester) async {
      final (store, db) = await sampleLibrary();
      final c = await pumpApp(tester, store: store, index: db);
      await tester.tap(find.text('From a template'));
      await _pump(tester);
      expect(find.text('Starts a new notebook'), findsOneWidget);
      expect(find.bySemanticsLabel('Save as template, from this page'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Weekly planner'));
      await tester.pump();
      await tester.tap(find.text('Use “Weekly planner”'));
      await _pump(tester);
      expect(find.byType(CanvasScreen), findsOneWidget);
      expect(find.text('Untitled notebook'), findsOneWidget);
      canvasPane = tester.widget<CanvasScreen>(find.byType(CanvasScreen)).pane;
      expect(shownPage(c).page.template, 'weekly');
      expect(c.read(libraryProvider).active, hasLength(15));
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('Password protect', () {
    testWidgets('locks a page, then unlocks it with the password or a fingerprint', (tester) async {
      final bio = FakeBiometric();
      final c = await _openPhysics(tester, biometric: bio);
      await tester.tap(byLabel('More options'));
      await tester.pump();
      await tester.tap(find.text('Password protect'));
      await _pump(tester);

      for (final text in [
        'Password protect', 'This page', 'Page 3 only', 'Whole notebook', 'All 12 pages', 'Password', 'Type it again',
        'Hint (optional)', 'Unlock with fingerprint or face', 'The password still works on your other devices',
        'Cancel', 'Lock page',
      ]) {
        expect(find.text(text), findsWidgets, reason: text);
      }
      expect(find.textContaining('nobody can recover them'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), 'momentum42');
      await tester.enterText(find.byType(TextField).at(1), 'momentum43');
      await tester.enterText(find.byType(TextField).at(2), 'units');
      await tester.pump();
      await tester.tap(find.text('Lock page'));
      await tester.pump();
      expect(find.text('The passwords don’t match'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(1), 'momentum42');
      await tester.pump();
      await tester.tap(find.text('Lock page'));
      await _pump(tester);

      expect(find.text('This page is locked'), findsOneWidget);
      expect(find.text('Hint: units'), findsOneWidget);
      expect(byLabel('Undo'), findsNothing); // no tools on a locked page
      expect(shownPage(c).items, isEmpty);

      await tester.enterText(find.byType(TextField), 'nope');
      await tester.pump();
      await tester.tap(find.text('Unlock'));
      await _pump(tester);
      expect(find.text('That password didn’t work. Try again.'), findsOneWidget);

      await tester.tap(find.text('Use fingerprint'));
      await _pump(tester);
      expect(find.text('This page is locked'), findsNothing);
      expect(shownPage(c).items, hasLength(14));
      expect(byLabel('Undo'), findsOneWidget);

      // With a password set, ⋯ → Password protect offers to lock now or remove it.
      await tester.tap(byLabel('More options'));
      await tester.pump();
      await tester.tap(find.text('Password protect'));
      await _pump(tester);
      await tester.tap(find.text('Remove password'));
      await _pump(tester);
      expect(shownNotebook(c).hasPageLock(shownPage(c).id), isFalse);
      expect(bio.saved, isEmpty);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a locked notebook opens behind its password', (tester) async {
      final (store, db) = await sampleLibrary();
      final c = await pumpApp(tester, store: store, index: db, location: Routes.notebook('nb_thesis'));
      expect(find.text('This notebook is locked'), findsOneWidget);
      expect(find.text('Hint: the usual'), findsOneWidget);
      expect(find.text('Use fingerprint'), findsNothing);
      expect(find.bySemanticsLabel('Add page'), findsNothing);
      await tester.enterText(find.byType(TextField), 'thesis');
      await tester.pump();
      await tester.tap(find.text('Unlock'));
      await _pump(tester);
      expect(find.text('This notebook is locked'), findsNothing);
      expect(c.read(notebookProvider('nb_thesis')).sealed, isEmpty);
      expect(byLabel('Undo'), findsOneWidget);

      await tester.tap(find.text('Back to library').hitTestable().evaluate().isEmpty
          ? byLabel('Back to library')
          : find.text('Back to library'));
      await _pump(tester);
      expect(c.read(libraryProvider).byId('nb_thesis')!.locked, isTrue);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('Split view', () {
    testWidgets('two notes side by side; the pen writes in the focused side', (tester) async {
      final c = await _openPhysics(tester);
      await tester.tap(byLabel('Ruler, laser & view'));
      await tester.pump();
      await tester.tap(find.text('Split view'));
      await _pump(tester);

      expect(find.byType(SplitScreen), findsOneWidget);
      expect(find.text('Split view'), findsOneWidget);
      expect(find.text('Pen writes here'), findsOneWidget);
      expect(find.textContaining('Writing in: Physics — Lecture notes · page 3 (left)'), findsOneWidget);
      // The right side shows the most recently edited other notebook.
      expect(find.text('Calculus II'), findsOneWidget);
      for (final label in ['Close split view', 'Swap panes', 'Previous page', 'Next page', 'Close this pane']) {
        expect(find.bySemanticsLabel(label), findsWidgets, reason: label);
      }
      List<Item> items(String id, int page) => c.read(notebookProvider(id)).pages[page].items;
      final calcBefore = items('nb_calc', 0).length;

      // The pen on the right side only moves the focus there…
      await _stylus(tester, _scribble(const Offset(900, 400)));
      await _pump(tester);
      expect(items('nb_calc', 0), hasLength(calcBefore));
      expect(find.textContaining('Writing in: Calculus II · page 1 (right)'), findsOneWidget);
      // …then writes there.
      await _stylus(tester, _scribble(const Offset(900, 400)), start: const Duration(seconds: 20));
      expect(items('nb_calc', 0), hasLength(calcBefore + 1));
      expect(items('nb_physics', 2), hasLength(14));

      // Undo acts on the focused side.
      await tester.tap(byLabel('Undo'));
      await tester.pump();
      expect(items('nb_calc', 0), hasLength(calcBefore));

      // Page buttons, Same note and swap.
      await tester.tap(find.bySemanticsLabel('Next page').last);
      await _pump(tester);
      expect(find.text('2 / 8'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Same note'));
      await _pump(tester);
      expect(find.text('Page 4 · same notebook'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Other note'));
      await _pump(tester);
      expect(find.text('Calculus II'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Swap panes'));
      await _pump(tester);
      expect(tester.getTopLeft(find.text('Calculus II')).dx, lessThan(tester.getTopLeft(find.text('Physics — Lecture notes')).dx));

      // Closing a pane keeps the other one open in the canvas.
      await tester.tap(byLabel('Close this pane').first);
      await _pump(tester);
      expect(find.byType(SplitScreen), findsNothing);
      expect(find.byType(CanvasScreen), findsOneWidget);
      expect(find.text('Page 3 of 12 · Saved'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('sticky notes and text go in the focused side', (tester) async {
      final c = await _openPhysics(tester);
      await tester.tap(byLabel('Ruler, laser & view'));
      await tester.pump();
      await tester.tap(find.text('Split view'));
      await _pump(tester);
      List<Item> items(String id, int page) => c.read(notebookProvider(id)).pages[page].items;
      final calcBefore = items('nb_calc', 0).length;

      await tester.tap(byLabel('Insert'));
      await tester.pump();
      await tester.tap(find.text('Sticky note'));
      await tester.pump();
      await _stylus(tester, const [Offset(400, 600)]);
      expect(items('nb_physics', 2).whereType<StickyItem>(), hasLength(1));
      expect(items('nb_calc', 0), hasLength(calcBefore));
      expect(find.text('Added a sticky note to the page'), findsOneWidget);

      await tester.tap(byLabel('Text'));
      await tester.pump();
      await _stylus(tester, const [Offset(300, 300)], start: const Duration(seconds: 20));
      await tester.enterText(find.byType(TextField), 'See page 4');
      await tester.tap(byLabel('Done typing'));
      await tester.pump();
      expect(items('nb_physics', 2).whereType<TextItem>().single.text, 'See page 4');
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('opens from Continue writing on the Start page', (tester) async {
      final (store, db) = await sampleLibrary();
      await pumpApp(tester, store: store, index: db);
      await tester.tap(find.text('Split view'));
      await _pump(tester);
      expect(find.byType(SplitScreen), findsOneWidget);
      expect(find.text('Physics — Lecture notes'), findsOneWidget);
      await tester.tap(byLabel('Close split view'));
      await _pump(tester);
      expect(find.byType(CanvasScreen), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
