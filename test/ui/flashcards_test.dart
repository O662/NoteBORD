import 'dart:math' as math;

import 'package:endless/board/ids.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/canvas/selection.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/study/fsrs.dart';
import 'package:endless/study/study_state.dart';
import 'package:endless/ui/canvas/canvas_screen.dart';
import 'package:endless/ui/routes.dart';
import 'package:endless/ui/study/study_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../study/study_samples.dart';

MemoryBoardStore _storeWith(List<Item> items, {String title = 'Physics — Lecture notes'}) {
  final now = DateTime.utc(2026, 9, 25, 9);
  final page = BoardPage(id: newId('pg'), items: items);
  final nb = Notebook(id: newId('nb'), title: title, createdAt: now, updatedAt: now, pageIds: [page.id]);
  return storeWith(LoadedNotebook(nb, [page]));
}

Future<void> _pen(WidgetTester tester, List<Offset> points, {PointerDeviceKind kind = PointerDeviceKind.stylus}) async {
  final g = await tester.createGesture(kind: kind);
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

Future<void> _makeFlashcards(WidgetTester tester) async {
  await tester.tap(byLabel('Study & math'));
  await tester.pump();
  await tester.tap(find.text('Make flashcards'));
  await tester.pump();
}

void main() {
  setUpAll(loadAppFonts);

  group('making flashcards (FlashMake.png)', () {
    testWidgets('circle the front, then the back, then Add card', (tester) async {
      final front = _word(const Offset(150, 220));
      final back = [_word(const Offset(150, 330)), _word(const Offset(230, 334))];
      final c = await pumpCanvas(tester, store: _storeWith([front, ...back]));
      await _makeFlashcards(tester);

      expect(find.text('Making flashcards'), findsOneWidget);
      expect(find.text('Deck: Physics — Lecture notes'), findsOneWidget);
      expect(find.text('Circle the front, then the back · images, typed text and ink all work'), findsOneWidget);
      expect(find.text('New card 1'), findsOneWidget);
      expect(find.text('0 cards in this deck so far'), findsOneWidget);
      expect(c.read(settingsProvider).tool, CanvasTool.lasso);
      // The rail, pages and map make way.
      expect(byLabel('Study & math'), findsNothing);

      await _pen(tester, _loop(const Offset(180, 222), 60, 35));
      expect(find.text('FRONT'), findsNWidgets(2));
      expect(find.text('Now circle the back · images, typed text and ink all work'), findsOneWidget);
      await _pen(tester, _loop(const Offset(220, 332), 110, 40));
      expect(find.text('BACK'), findsNWidgets(2));
      expect(find.text('Front and back circled · images, typed text and ink all work'), findsOneWidget);
      // Nothing is selected while circling.
      expect(canvasPane.selection.isEmpty, isTrue);

      await tester.tap(find.bySemanticsLabel('Also quiz me back to front'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Add card'));
      await tester.pump();

      final card = shownPage(c).items.whereType<FlashcardItem>().single;
      expect(card.front.ids, [front.id]);
      expect(card.back.ids, unorderedEquals(back.map((b) => b.id)));
      expect(card.reverse, isTrue);
      expect(card.deckName, 'Physics — Lecture notes');
      expect(c.read(decksProvider).single.id, card.deck);
      expect(find.text('Card added to Physics — Lecture notes'), findsOneWidget);
      expect(find.bySemanticsLabel('Study now'), findsOneWidget);
      expect(find.text('New card 2'), findsOneWidget);
      expect(find.text('1 card in this deck so far'), findsOneWidget);
      // Front and back apart on the page: a chip on each.
      expect(find.text('Card 1 · front'), findsOneWidget);
      expect(find.text('Card 1 · back'), findsOneWidget);
      // Ready for the next one.
      expect(find.text('FRONT'), findsOneWidget);

      // Undo takes it back.
      c.read(notebookProvider(canvasPane.notebookId).notifier).undo(shownPage(c).id);
      await tester.pump();
      expect(shownPage(c).items.whereType<FlashcardItem>(), isEmpty);
    });

    testWidgets('a tap picks a picture or text box; Clear starts again; a card\'s chip deletes it', (tester) async {
      final text = sampleText('t1', 'Impulse', at: const Offset(150, 200), size: 40);
      final answer = sampleText('t2', 'J = F · Δt', at: const Offset(150, 320), size: 36);
      final c = await pumpCanvas(tester, store: _storeWith([text, answer]));
      await _makeFlashcards(tester);
      await _pen(tester, [const Offset(170, 225)]);
      expect(find.text('Now circle the back · images, typed text and ink all work'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Clear'));
      await tester.pump();
      expect(find.text('Circle the front, then the back · images, typed text and ink all work'), findsOneWidget);
      await _pen(tester, [const Offset(170, 225)]);
      await _pen(tester, [const Offset(170, 340)]);
      await tester.tap(find.bySemanticsLabel('Add card'));
      await tester.pump();
      final card = shownPage(c).items.whereType<FlashcardItem>().single;
      expect(card.front.ids, ['t1']);
      expect(card.back.ids, ['t2']);
      // Front and back far apart: a chip on each.
      expect(find.text('Card 1 · front'), findsOneWidget);
      expect(find.text('Card 1 · back'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Card 1 · front. Delete it'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete card'));
      await tester.pumpAndSettle();
      expect(shownPage(c).items.whereType<FlashcardItem>(), isEmpty);
      expect(find.text('Card 1 · front'), findsNothing);
    });

    testWidgets('another deck, a new deck; Done or Esc goes back to the pen', (tester) async {
      final c = await pumpCanvas(tester, store: _storeWith([_word(const Offset(150, 220)), _word(const Offset(150, 330))]));
      c.read(decksProvider.notifier).add('Lab safety');
      await _makeFlashcards(tester);
      expect(find.text('Deck: Lab safety'), findsNothing, reason: 'a new deck after the notebook');
      await tester.tap(find.bySemanticsLabel(RegExp('^Deck: ')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New deck…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Vocab');
      await tester.pump();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(find.text('Deck: Vocab'), findsOneWidget);
      expect(c.read(settingsProvider).lastDeck, c.read(decksProvider).last.id);

      await _pen(tester, [const Offset(170, 222)]);
      await _pen(tester, [const Offset(170, 332)]);
      await tester.tap(find.bySemanticsLabel('Add card'));
      await tester.pump();
      expect(shownPage(c).items.whereType<FlashcardItem>().single.deckName, 'Vocab');

      await tester.tap(find.bySemanticsLabel('Done making flashcards'));
      await tester.pump();
      expect(find.text('Making flashcards'), findsNothing);
      expect(c.read(settingsProvider).tool, CanvasTool.pen);
      expect(byLabel('Study & math'), findsOneWidget);

      await _makeFlashcards(tester);
      expect(find.text('Deck: Vocab'), findsOneWidget, reason: 'the deck used last');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('Making flashcards'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('the Remember toolbar\'s Flashcard: what\'s lassoed is the front', (tester) async {
      final a = _word(const Offset(400, 400)), b = _word(const Offset(400, 260));
      final c = await pumpCanvas(tester, store: _storeWith([a, b]));
      await tester.tap(byLabel('Study & math'));
      await tester.pump();
      await tester.tap(find.text('Need to remember'));
      await tester.pump();
      await _pen(tester, _loop(const Offset(430, 400), 70, 40));
      await tester.tap(find.bySemanticsLabel('Flashcard'));
      await tester.pump();
      expect(find.text('Making flashcards'), findsOneWidget);
      expect(find.text('Now circle the back · images, typed text and ink all work'), findsOneWidget);
      // Clear of the New card panel along the bottom.
      await _pen(tester, _loop(const Offset(430, 260), 70, 40));
      await tester.tap(find.bySemanticsLabel('Add card'));
      await tester.pump();
      final card = shownPage(c).items.whereType<FlashcardItem>().single;
      expect(card.front.ids, [a.id]);
      expect(card.back.ids, [b.id]);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('the Insert menu\'s Flashcards and Need to remember tiles start them', (tester) async {
      await pumpCanvas(tester, store: _storeWith([_word(const Offset(150, 220))]));
      Future<void> insert(String tile) async {
        await tester.tap(byLabel('Insert'));
        await tester.pump();
        await tester.tap(find.text('Everything else'));
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel(tile));
        await tester.pumpAndSettle();
      }

      await insert('Need to remember');
      expect(find.text('Coming soon'), findsNothing);
      expect(find.text('Circle what you need to remember'), findsOneWidget);
      expect(canvasPane.selection.menu, SelectionMenu.remember);

      await insert('Flashcards');
      expect(find.text('Coming soon'), findsNothing);
      expect(find.text('Making flashcards'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('Study now opens the deck', (tester) async {
      final c = await pumpCanvas(tester, store: _storeWith([_word(const Offset(150, 220)), _word(const Offset(150, 330))]));
      await _makeFlashcards(tester);
      await _pen(tester, [const Offset(170, 222)]);
      await _pen(tester, [const Offset(170, 332)]);
      await tester.tap(find.bySemanticsLabel('Add card'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Study now'));
      await _settle(tester);
      await c.read(studyProvider.notifier).refresh();
      await _settle(tester);
      expect(find.byType(StudyScreen), findsOneWidget);
      expect(find.text('Card 1 of 1 due'), findsOneWidget);
      expect(find.text('FRONT'), findsOneWidget);
    });
  });

  group('studying (Study.png)', () {
    Future<void> open(WidgetTester tester, MemoryBoardStore store, {String? deck}) async {
      final c = await pumpApp(tester, store: store, location: Routes.flashcards(deck));
      await indexAll(tester, c);
      await _settle(tester);
    }

    testWidgets('the decks, with what\'s due', (tester) async {
      await open(tester, studySample());
      expect(find.text('Flashcards'), findsWidgets);
      expect(find.bySemanticsLabel('Physics — Momentum, 5 due · 12 cards · from 2 notebooks'), findsOneWidget);
      expect(find.bySemanticsLabel('Calculus II — Integrals, 2 due · 3 cards'), findsOneWidget);
      expect(find.bySemanticsLabel('Lab safety, All caught up · 3 cards'), findsOneWidget);
      expect(find.text('Card 1 of 5 due'), findsOneWidget);
      expect(find.text('Tap the card to flip'), findsOneWidget);
    });

    testWidgets('flip, rate, and through to the end; how well each is known is saved', (tester) async {
      final store = studySample();
      await open(tester, store, deck: 'dk_calc');
      expect(find.text('Calculus II — Integrals'), findsWidgets);
      expect(find.text('Card 1 of 2 due'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Show answer'));
      await tester.pump();
      expect(find.text('BACK'), findsOneWidget);
      expect(find.text('From Calculus II · page 1'), findsOneWidget);
      for (final r in ['Again', 'Hard', 'Good', 'Easy']) {
        expect(find.bySemanticsLabel(RegExp('^$r, next in ')), findsOneWidget, reason: r);
      }
      await tester.tap(find.bySemanticsLabel(RegExp('^Good, next in ')));
      await tester.pump();
      expect(find.text('Card 2 of 2 due'), findsOneWidget);
      // Saved in the notebook's study.json.
      await _settle(tester);
      final saved = await store.loadStudy('nb_calc');
      final state = CardState.fromJson(((saved!['cards'] as Map)['fc_c0'] as Map)['f'])!;
      expect(state.reps, 2);
      expect(state.lastReview, DateTime(2026, 9, 25, 10).toUtc());

      // Again comes back in the round.
      await tester.tap(find.byType(StudyScreen));
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.pump();
      expect(find.text('Card 2 of 2 due'), findsOneWidget, reason: 'not done yet');
      await tester.tap(find.bySemanticsLabel('Show answer'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(RegExp('^Easy, next in ')));
      await tester.pump();
      expect(find.textContaining('All 2 due cards done. Next review: '), findsOneWidget);
      expect(find.text('Done for today'), findsOneWidget);
      await tester.tap(find.text('Study again'));
      await tester.pump();
      expect(find.text('Card 1 of 3 due'), findsOneWidget);
    });

    testWidgets('write the answer, then check it', (tester) async {
      await open(tester, studySample());
      await tester.tap(find.bySemanticsLabel('Write the answer'));
      await tester.pump();
      expect(find.text('Write your answer here with the S Pen'), findsOneWidget);
      expect(find.text('Tap the card to flip'), findsNothing);
      // The pad is labelled for screen readers.
      expect(
        find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Write your answer here with the S Pen'),
        findsOneWidget,
      );
      final pad = tester.getCenter(find.text('Write your answer here with the S Pen'));
      await _pen(tester, [for (var i = 0; i <= 20; i++) pad + Offset(i * 4.0 - 40, 10 * math.sin(i / 2))]);
      expect(find.text('BACK'), findsNothing, reason: 'writing doesn\'t flip the card');
      await tester.tap(find.bySemanticsLabel('Check my answer'));
      await tester.pump();
      expect(find.text('BACK'), findsOneWidget);
      expect(find.text('YOUR ANSWER'), findsOneWidget);
    });

    testWidgets('Open in notes; a new deck; nothing yet', (tester) async {
      await open(tester, studySample());
      await tester.tap(find.bySemanticsLabel('Open in notes'));
      await _settle(tester);
      expect(find.byType(CanvasScreen), findsOneWidget);
      final pane = tester.widget<CanvasScreen>(find.byType(CanvasScreen)).pane;
      expect(pane.notebookId, 'nb_phys');
      expect(pane.page, 2);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a new deck, and no decks at all', (tester) async {
      await open(tester, MemoryBoardStore());
      expect(find.text('No flashcards yet'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('New deck'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Spanish');
      await tester.pump();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Spanish, No cards yet'), findsOneWidget);
      expect(find.text('No cards in this deck yet'), findsOneWidget);
    });

    testWidgets('the sidebar counts cards due and things to remember', (tester) async {
      final c = await pumpApp(tester, store: studySample());
      await indexAll(tester, c);
      await _settle(tester);
      // 5 + 2 due.
      expect(find.bySemanticsLabel('Flashcards'), findsOneWidget);
      final flash = tester.getSemantics(find.bySemanticsLabel('Flashcards'));
      expect(flash.value, '7 due');
      await tester.tap(find.bySemanticsLabel('Flashcards'));
      await _settle(tester);
      expect(find.byType(StudyScreen), findsOneWidget);
    });
  });
}
