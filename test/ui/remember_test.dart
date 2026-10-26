import 'dart:math' as math;

import 'package:endless/board/ids.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/library/library.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/study/remember.dart';
import 'package:endless/study/study_state.dart';
import 'package:endless/ui/canvas/canvas_screen.dart';
import 'package:endless/ui/routes.dart';
import 'package:endless/ui/study/remember_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../study/shapes.dart';
import '../study/study_samples.dart';

/// A notebook with one page holding [items] (page coords = screen coords).
MemoryBoardStore _storeWith(List<Item> items, {AppSettings? settings}) {
  final now = DateTime.utc(2026, 9, 25, 9);
  final page = BoardPage(id: newId('pg'), items: items);
  final nb = Notebook(id: newId('nb'), title: 'Physics — Lecture notes', createdAt: now, updatedAt: now, pageIds: [page.id]);
  return storeWith(LoadedNotebook(nb, [page]), settings: settings);
}

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

List<Offset> _loop(Offset c, double rx, double ry) => [
      for (var i = 0; i <= 40; i++) c + Offset(math.cos(i / 40 * 2 * math.pi) * rx, math.sin(i / 40 * 2 * math.pi) * ry),
    ];

StrokeItem _word(Offset at) => strokeFrom([for (var i = 0; i <= 30; i++) at + Offset(i * 2.0, 8 * math.sin(i / 3))]);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _lassoToRemember(WidgetTester tester, Offset center, double rx, double ry) async {
  await tester.tap(byLabel('Study & math'));
  await tester.pump();
  await tester.tap(find.text('Need to remember'));
  await tester.pump();
  await _pen(tester, _loop(center, rx, ry));
}

void main() {
  setUpAll(loadAppFonts);

  group('Remember this', () {
    testWidgets('lasso, Remember: why it matters, a reminder and a flashcard, as one undo step', (tester) async {
      final a = _word(const Offset(400, 400)), b = _word(const Offset(470, 404));
      final other = _word(const Offset(400, 600));
      final fake = FakeReminders();
      final c = await pumpCanvas(tester, store: _storeWith([a, b, other]), reminders: fake);
      await _lassoToRemember(tester, const Offset(465, 404), 110, 40);
      await tester.tap(find.bySemanticsLabel('Remember'));
      await tester.pump();

      expect(find.text('Remember this'), findsOneWidget);
      expect(find.text('WHY IT MATTERS (OPTIONAL)'), findsOneWidget);
      expect(find.text('Tip: draw a star next to anything to mark it'), findsOneWidget);
      for (final chip in ['No reminder', 'Tomorrow', 'Before an event', 'Pick a date']) {
        expect(find.bySemanticsLabel(chip), findsOneWidget, reason: chip);
      }
      await tester.enterText(find.byType(TextField), 'always on the exam');
      await tester.tap(find.bySemanticsLabel('Before an event'));
      await tester.pump();
      expect(find.text('Reminders before an event come with the calendar'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Tomorrow'));
      await tester.tap(find.bySemanticsLabel('Also make it a flashcard'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Save'));
      await tester.pump();

      final page = shownPage(c);
      final marks = {for (final i in page.items) i.id: ?RememberMark.of(i)};
      expect(marks.keys, unorderedEquals([a.id, b.id]));
      final mark = marks[a.id]!;
      expect(marks[b.id]!.id, mark.id);
      expect(mark.why, 'always on the exam');
      expect(mark.remind, RemindKind.tomorrow);
      // Tomorrow at 9 in the morning, the tablet's time.
      expect(mark.remindAt, DateTime(2026, 9, 26, 9).toUtc());
      final card = page.items.whereType<FlashcardItem>().single;
      expect(mark.flashcard, card.id);
      expect(card.front.ids, unorderedEquals([a.id, b.id]));
      expect(card.back.text, 'always on the exam');
      expect(card.deckName, 'Physics — Lecture notes');
      // Asked to show notifications, once there's a reminder.
      expect(fake.asked, 1);

      const toast = 'Saved to Need to remember · reminder tomorrow · flashcard made';
      expect(find.text(toast), findsOneWidget);
      expect(find.bySemanticsLabel('Open: $toast'), findsOneWidget);
      expect(find.text('Remember this'), findsNothing);
      expect(find.bySemanticsLabel('Remembered. Change or forget it'), findsOneWidget);

      // One undo step takes back the marks and the card.
      await tester.tap(find.bySemanticsLabel('Undo: $toast'));
      await tester.pump();
      expect(shownPage(c).items.where((i) => i.remember != null), isEmpty);
      expect(shownPage(c).items.whereType<FlashcardItem>(), isEmpty);
      expect(find.bySemanticsLabel('Remembered. Change or forget it'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('its chip changes it, or forgets it', (tester) async {
      final a = _word(const Offset(400, 400));
      final c = await pumpCanvas(tester, store: _storeWith([a]));
      await _lassoToRemember(tester, const Offset(430, 400), 70, 40);
      await tester.tap(find.bySemanticsLabel('Remember'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'know it cold');
      await tester.tap(find.bySemanticsLabel('Save'));
      await tester.pump();
      expect(find.text('Saved to Need to remember'), findsOneWidget);

      // Back to the pen: the chip is still there.
      await tester.tap(byLabel('Pen'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Remembered. Change or forget it'));
      await tester.pump();
      expect(find.text('Remember this'), findsOneWidget);
      expect(find.text('know it cold'), findsOneWidget);
      expect(find.text('Tip: draw a star next to anything to mark it'), findsNothing);
      await tester.tap(find.text('Forget it'));
      await tester.pump();
      expect(shownPage(c).items.single.remember, isNull);
      expect(find.text('No longer remembered'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('anything lassoed from "Need to remember" gets Remember, and so does what\'s selected already', (tester) async {
      final note = sampleText('t1', 'Lab report due', at: const Offset(400, 380), typed: true, size: 20);
      final c = await pumpCanvas(tester, store: _storeWith([note]));
      // Select the text box, then Need to remember: its toolbar turns to Remember.
      await tester.tap(byLabel('Select'));
      await tester.pump();
      await _pen(tester, [const Offset(420, 392), const Offset(421, 392)]);
      expect(find.bySemanticsLabel('Edit text'), findsOneWidget);
      await tester.tap(byLabel('Study & math'));
      await tester.pump();
      await tester.tap(find.text('Need to remember'));
      await tester.pump();
      expect(find.bySemanticsLabel('Remember'), findsOneWidget);
      expect(find.bySemanticsLabel('Edit text'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Remember'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Save'));
      await tester.pump();
      expect(RememberMark.of(shownPage(c).items.single), isNotNull);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('a drawn star', () {
    testWidgets('next to writing marks it to remember; Undo keeps the star as ink', (tester) async {
      final words = [_word(const Offset(150, 574)), _word(const Offset(220, 578))];
      final above = _word(const Offset(150, 470));
      final c = await pumpCanvas(tester, store: _storeWith([...words, above]));
      await _pen(tester, pentagram(const Offset(340, 576), 26));

      final page = shownPage(c);
      final star = page.items.whereType<StrokeItem>().last;
      final groups = rememberGroups(page.items);
      expect(groups.single.items.map((i) => i.id), unorderedEquals(words.map((w) => w.id)));
      expect(groups.single.star!.id, star.id);
      expect(groups.single.mark.drawn, isTrue);
      expect(RememberMark.of(above), isNull);
      expect(find.text('Drawn star · remembered'), findsWidgets);
      expect(find.bySemanticsLabel('Remembered with a drawn star. Change or forget it'), findsOneWidget);

      // Undo: the star stays, as ink.
      await tester.tap(find.bySemanticsLabel('Undo: Drawn star · remembered'));
      await tester.pump();
      expect(shownPage(c).items.where((i) => i.remember != null), isEmpty);
      expect(shownPage(c).items.whereType<StrokeItem>().length, 4);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('on its own, or with the setting off, it\'s just ink', (tester) async {
      final word = _word(const Offset(150, 300));
      final c = await pumpCanvas(tester, store: _storeWith([word]));
      await _pen(tester, pentagram(const Offset(700, 500), 26));
      expect(shownPage(c).items.where((i) => i.remember != null), isEmpty);

      c.read(settingsProvider.notifier).apply((s) => s.copyWith(starRemember: false));
      await _pen(tester, pentagram(const Offset(240, 302), 20));
      expect(shownPage(c).items.where((i) => i.remember != null), isEmpty);
      expect(shownPage(c).items, hasLength(3));
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('Need to remember', () {
    testWidgets('gathers what\'s remembered across notebooks, with filters (Remember.png)', (tester) async {
      final store = rememberSample();
      final c = await pumpApp(tester, store: store, location: Routes.remember);
      await indexAll(tester, c);
      await _settle(tester);

      expect(find.text('Need to remember'), findsWidgets);
      expect(find.text('8 things from 6 notebooks · lasso anything and tap Remember, or draw a star next to it'), findsOneWidget);
      expect(find.bySemanticsLabel('All, 8'), findsOneWidget);
      expect(find.bySemanticsLabel('Has a reminder, 3'), findsOneWidget);
      expect(find.bySemanticsLabel('Physics, 4'), findsOneWidget);
      expect(find.bySemanticsLabel('Work, 1'), findsOneWidget);
      // The sidebar counts them.
      expect(find.bySemanticsLabel(RegExp('^Remember')), findsWidgets);

      expect(find.text('“always on the exam”'), findsOneWidget);
      expect(find.text('Oct 14 · 9 AM'), findsOneWidget);
      expect(find.text('Also a flashcard'), findsOneWidget);
      expect(find.text('Drawn star'), findsOneWidget);
      expect(find.text('Lab report due Sep 30, 11:59 PM — submit as PDF'), findsOneWidget);
      await _settle(tester);
      expect(find.text('Physics — Lecture notes · p. 3'), findsNWidgets(3));
      expect(find.text('Calculus II · p. 8'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Has a reminder, 3'));
      await tester.pump();
      expect(find.text('Also a flashcard'), findsNothing);
      expect(find.text('Lab report due Sep 30, 11:59 PM — submit as PDF'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('All, 8'));
      await tester.pump();
    });

    testWidgets('a star unstars it in its notebook, and stars it again; Review all; open where it is', (tester) async {
      final store = rememberSample();
      final c = await pumpApp(tester, store: store, location: Routes.remember);
      await indexAll(tester, c);
      await _settle(tester);

      final stars = byLabel('Remove from Need to remember');
      expect(stars, findsNWidgets(8));
      // The newest first: "total momentum…".
      await tester.tap(stars.first);
      await _settle(tester);
      expect(byLabel('Add back to Need to remember'), findsOneWidget);
      expect(find.text('7 things from 6 notebooks · lasso anything and tap Remember, or draw a star next to it'), findsOneWidget);
      final saved = (await store.loadNotebook('nb_phys'))!.pages.last.items.firstWhere((i) => i.id == 't_mom');
      expect(saved.remember, isNull, reason: 'unmarked in its notebook, on disk');

      await tester.tap(byLabel('Add back to Need to remember'));
      await _settle(tester);
      expect(byLabel('Remove from Need to remember'), findsNWidgets(8));
      final back = (await store.loadNotebook('nb_phys'))!.pages.last.items.firstWhere((i) => i.id == 't_mom');
      expect(RememberMark.of(back)!.why, 'always on the exam');

      await tester.tap(find.bySemanticsLabel('Review all'));
      await tester.pump();
      expect(find.text('1 of 8'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Next'));
      await tester.pump();
      expect(find.text('2 of 8'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Previous'));
      await tester.pump();
      expect(find.text('1 of 8'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Done'));
      await tester.pump();
      expect(find.text('1 of 8'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Open Calculus II · p. 8'));
      await _settle(tester);
      expect(find.byType(CanvasScreen), findsOneWidget);
      final pane = tester.widget<CanvasScreen>(find.byType(CanvasScreen)).pane;
      expect(pane.notebookId, 'nb_calc');
      expect(pane.page, 7);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('nothing yet', (tester) async {
      final c = await pumpApp(tester, location: Routes.remember);
      await indexAll(tester, c);
      expect(find.text('Nothing to remember yet'), findsOneWidget);
      expect(find.bySemanticsLabel('Review all'), findsNothing);
    });

    testWidgets('the toast\'s Open goes there from the canvas', (tester) async {
      final a = _word(const Offset(400, 400));
      final c = await pumpCanvas(tester, store: _storeWith([a]));
      await _lassoToRemember(tester, const Offset(430, 400), 70, 40);
      await tester.tap(find.bySemanticsLabel('Remember'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Save'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Open: Saved to Need to remember'));
      await _settle(tester);
      expect(find.byType(RememberScreen), findsOneWidget);
      expect(c.read(studyProvider)!.remembered.single.items.single.id, a.id);
      expect(find.text('1 thing from 1 notebook · lasso anything and tap Remember, or draw a star next to it'), findsOneWidget);
      expect(c.read(libraryProvider).notebooks, hasLength(1));
      expect(c.read(notebookProvider(canvasPane.notebookId)).pages, hasLength(1));
    });
  });
}
