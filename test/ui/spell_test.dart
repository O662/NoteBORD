import 'dart:ui' show CheckedState;

import 'package:endless/board/codec.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/spelling/my_handwriting.dart';
import 'package:endless/spelling/spell_check.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/ui/dialogs.dart' show PrimaryButton;
import 'package:endless/ui/spell/spell_mode.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../recognition/fake_ink.dart';
import '../spelling/hand_fixtures.dart';
import '../spelling/spell_check_test.dart' show spellPage;
import '../spelling/spelling_fixtures.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Spell.png's page in a notebook, on the canvas.
Future<(ProviderContainer, ({BoardPage page, List<StrokeItem> title, List<StrokeItem> line2, List<StrokeItem> line3, TextItem box}))>
    _pump(WidgetTester tester, {FakeSpeech? speech, FakeRecognizer? recognizer, MyHandwriting? hand}) async {
  final r = recognizer ?? FakeRecognizer();
  final p = spellPage(r);
  final now = DateTime.utc(2026, 9, 25, 9);
  final nb = Notebook(id: 'nb_spell', title: 'Physics — Lecture notes', createdAt: now, updatedAt: now, pageIds: [p.page.id]);
  final store = storeWith(LoadedNotebook(nb, [p.page]), settings: AppSettings(trayOpen: false));
  store.handwriting = hand?.toJson();
  final c = await pumpCanvas(
    tester,
    store: store,
    recognizer: r,
    extra: spellingOverrides(speech: speech),
  );
  return (c, p);
}

Future<void> _rail(WidgetTester tester, String item) async {
  await tester.tap(byLabel('Writing help'));
  await tester.pump();
  await tester.tap(find.text(item));
  await _settle(tester);
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(find.bySemanticsLabel(label));
  await _settle(tester);
}

SpellController _spell(WidgetTester tester) => tester.widget<SpellBar>(find.byType(SpellBar)).spell;

String _count(WidgetTester tester) => _spell(tester).countLabel;

List<TextItem> _texts(ProviderContainer c) => shownPage(c).items.whereType<TextItem>().toList();

List<StrokeItem> _ink(ProviderContainer c) => shownPage(c).items.whereType<StrokeItem>().toList();

/// Writes each of [letters] in its box of "Teach Endless your handwriting"
/// with the S Pen, as [zigzagGlyph] draws it.
Future<void> writeSample(WidgetTester tester, String letters, {required String step}) async {
  final pad = tester.getRect(find.bySemanticsLabel('Handwriting sample: write each letter in its box'));
  const columns = 13, gap = 6.0, h = 112.0;
  final w = (pad.width - (columns - 1) * gap) / columns;
  for (final (i, ch) in letters.split('').indexed) {
    final at = step.indexOf(ch);
    final cell = Rect.fromLTWH(pad.left + (at % columns) * (w + gap), pad.top + (at ~/ columns) * (h + gap), w, h);
    final xh = h * SampleGuides.xHeight;
    final base = cell.top + h * SampleGuides.baseline;
    final glyph = '.,\'-:;!?'.contains(ch) ? builtInMarks[ch]! : ch == ch.toLowerCase() ? zigzagGlyph(ch) : zigzagGlyph('a').scaled(1.45);
    for (final stroke in glyph.strokes) {
      Offset pt(InkPoint p) => Offset(cell.left + 14 + p.x * xh, base + p.y * xh);
      final g = await tester.startGesture(pt(stroke.first), kind: PointerDeviceKind.stylus, pointer: 900 + i);
      for (final p in stroke.skip(1)) {
        await g.moveTo(pt(p));
      }
      await g.up();
    }
    await tester.pump();
  }
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    await loadSpelling();
  });

  testWidgets('spell check: the count, previous and next, a tap on a word, and Done', (tester) async {
    await _pump(tester);
    await _rail(tester, 'Spell check');

    // The bar takes the tool pill's place; the rail and pages go.
    expect(find.byType(SpellBar), findsOneWidget);
    expect(byLabel('Writing help'), findsNothing);
    expect(find.text('Spell check'), findsOneWidget);
    expect(_count(tester), '1 of 4');
    expect(find.text('Not in the dictionary:'), findsOneWidget);
    expect(find.text('Momentem'), findsOneWidget);
    expect(find.text('Handwriting'), findsOneWidget);
    for (final s in ['Momentum', 'Moment']) {
      expect(find.bySemanticsLabel('Change to $s'), findsOneWidget, reason: s);
    }

    await _tap(tester, 'Next issue');
    expect(_count(tester), '2 of 4');
    expect(find.text('sistem'), findsOneWidget);
    await _tap(tester, 'Previous issue');
    await _tap(tester, 'Previous issue');
    expect(_count(tester), '4 of 4');
    expect(find.text('Recieve'), findsOneWidget);
    expect(find.text('Typed text'), findsOneWidget);

    // A tap on an underlined word on the page.
    final colision = _spell(tester).issues.firstWhere((i) => i.word == 'colision');
    await tester.tapAt(canvasPane.view.toScreen(colision.rect.center));
    await _settle(tester);
    expect(_count(tester), '3 of 4');
    expect(find.text('colision'), findsOneWidget);

    await _tap(tester, 'Done');
    expect(find.byType(SpellBar), findsNothing);
    expect(byLabel('Writing help'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('fixing typed text and handwriting, each one undo step', (tester) async {
    final (c, p) = await _pump(tester);
    await _rail(tester, 'Spell check');

    // Handwriting: the word goes, typed in the handwriting font where it was.
    await _tap(tester, 'Change to Momentum');
    expect(shownPage(c)[p.title.last.id], isNull);
    final momentum = _texts(c).firstWhere((t) => t.text == 'Momentum');
    expect(momentum.font, 'hand');
    expect(find.text('Changed “Momentem” to “Momentum”'), findsOneWidget);
    expect(_count(tester), '1 of 3');
    expect(find.text('sistem'), findsOneWidget);

    // Typed text changes in place.
    await _tap(tester, 'Previous issue');
    expect(find.text('Recieve'), findsOneWidget);
    await _tap(tester, 'Change to Receive');
    expect((shownPage(c)[p.box.id]! as TextItem).text, 'Receive lab data from Maya by Sunday');
    expect(_count(tester), '2 of 2');

    await tester.tap(find.text('Undo'));
    await _settle(tester);
    expect((shownPage(c)[p.box.id]! as TextItem).text, 'Recieve lab data from Maya by Sunday');
    expect(_spell(tester).issues.map((i) => i.word), ['sistem', 'colision', 'Recieve']);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Fix all: every word in one undo step, then all clear', (tester) async {
    final (c, p) = await _pump(tester);
    await _rail(tester, 'Spell check');
    await _tap(tester, 'Fix all');
    expect(find.text('Fixed 4 words'), findsOneWidget);
    expect(_count(tester), 'All clear');
    expect(find.text('No spelling issues left on this page'), findsOneWidget);
    expect(_texts(c).map((t) => t.text), containsAll(['Momentum', 'system', 'collision:']));
    expect((shownPage(c)[p.box.id]! as TextItem).text, 'Receive lab data from Maya by Sunday');

    await tester.tap(find.text('Undo'));
    await _settle(tester);
    expect(_count(tester), '1 of 4');
    expect(shownPage(c)[p.title.last.id], isNotNull);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Ignore keeps the word on this page; Start over brings it back; Add to my dictionary', (tester) async {
    final (c, p) = await _pump(tester);
    await _rail(tester, 'Spell check');

    await _tap(tester, 'Ignore');
    expect(shownPage(c).page.spellIgnore, ['Momentem']);
    expect(_count(tester), '1 of 3');
    await tester.pump(const Duration(seconds: 1));
    final store = c.read(boardStoreProvider) as MemoryBoardStore;
    expect(decodePage(store.pages['nb_spell']![p.page.id]!).spellIgnore, ['Momentem']);

    await _tap(tester, 'Add to my dictionary');
    expect(c.read(settingsProvider).myWords, ['sistem']);
    expect(_count(tester), '1 of 2');
    await _tap(tester, 'Ignore');
    await _tap(tester, 'Ignore');
    expect(find.text('No spelling issues left on this page'), findsOneWidget);

    await _tap(tester, 'Start over');
    expect(shownPage(c).page.spellIgnore, isEmpty);
    // "sistem" is in my dictionary now, everywhere.
    expect(_spell(tester).issues.map((i) => i.word), ['Momentem', 'colision', 'Recieve']);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Look up opens the dictionary at the suggestion; thesaurus, recent and Hear it', (tester) async {
    final speech = FakeSpeech();
    final (c, _) = await _pump(tester, speech: speech);
    await _rail(tester, 'Spell check');
    await _tap(tester, 'Look up');

    expect(find.bySemanticsLabel('Dictionary and thesaurus'), findsOneWidget);
    expect(find.text('momentum'), findsWidgets);
    expect(find.textContaining('moh-MEN-təm', findRichText: true), findsOneWidget);
    expect(find.text('noun'), findsOneWidget);
    expect(find.text('Works offline · English (US)'), findsOneWidget);
    expect(c.read(settingsProvider).recentLookups, ['momentum']);

    await _tap(tester, 'Hear it');
    expect(speech.said, ['momentum']);

    await _tap(tester, 'Thesaurus');
    expect(find.text('SIMILAR WORDS'), findsOneWidget);
    expect(find.text('OPPOSITES'), findsOneWidget);
    await _tap(tester, 'Look up impulse');
    expect(find.text('impulse'), findsWidgets);
    expect(find.text('SIMILAR WORDS'), findsNothing); // back to the dictionary tab
    expect(c.read(settingsProvider).recentLookups, ['impulse', 'momentum']);

    // Recent.
    await _tap(tester, 'Look up momentum');
    expect(find.textContaining('moh-MEN-təm', findRichText: true), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the dictionary from Writing help: search, not found, add a definition, flashcards, close', (tester) async {
    final (c, _) = await _pump(tester);
    await _rail(tester, 'Dictionary & thesaurus');
    expect(find.text('Type a word to see what it means, words like it and its opposites.'), findsOneWidget);
    // Writing still works beside it: the rail stays, the pages rail goes.
    expect(byLabel('Writing help'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'momentem');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _settle(tester);
    expect(find.text('“momentem” isn’t in the dictionary.'), findsOneWidget);
    expect(find.text('DID YOU MEAN'), findsOneWidget);
    await _tap(tester, 'Look up momentum');
    expect(find.textContaining('moh-MEN-təm', findRichText: true), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'conserve');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _settle(tester);
    expect(find.textContaining('kən-SURV', findRichText: true), findsOneWidget);
    expect(find.text('verb'), findsOneWidget);
    expect(find.text('Keep constant through physical or chemical reactions or evolutionary change.'), findsOneWidget);
    expect(find.text('“Energy is conserved in this process”'), findsOneWidget);

    final before = _texts(c).length;
    await _tap(tester, 'Add definition to page');
    final added = _texts(c);
    expect(added, hasLength(before + 1));
    expect(added.last.text, 'conserve · verb\nKeep constant through physical or chemical reactions or evolutionary change.');
    expect(find.text('Added the definition of “conserve” to the page'), findsOneWidget);

    await _tap(tester, 'Make flashcard');
    expect(find.text('Making flashcards is coming soon'), findsOneWidget);

    await _tap(tester, 'Close the dictionary');
    expect(find.bySemanticsLabel('Dictionary and thesaurus'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Fix it in my handwriting: the sample first, then fixes written in your letters', (tester) async {
    final (c, p) = await _pump(tester);
    await _rail(tester, 'Spell check');
    expect(c.read(myHandwritingProvider), isNull);

    // No sample yet: the box opens "Teach Endless your handwriting".
    await _tap(tester, 'Fix it in my handwriting');
    expect(find.text('Teach Endless your handwriting'), findsOneWidget);
    expect(find.text('Step 1 of 2 · Small letters'), findsOneWidget);
    expect(tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed, isNull);
    final small = sampleSteps[0].letters;
    await writeSample(tester, small.substring(0, 24), step: small);
    expect(find.text('2 letters to go: y, z'), findsOneWidget);
    await writeSample(tester, 'yz', step: small);
    expect(find.text('All the small letters are there.'), findsOneWidget);
    await _tap(tester, 'Next');

    // Capitals and marks are optional; the preview uses what's there.
    expect(find.text('Step 2 of 2 · Capitals and marks'), findsOneWidget);
    expect(find.bySemanticsLabel('Preview: Spelling, fixed. in your handwriting'), findsOneWidget);
    await writeSample(tester, 'M.', step: sampleSteps[1].letters);
    await _tap(tester, 'Save my handwriting');
    expect(find.text('Teach Endless your handwriting'), findsNothing);

    final hand = c.read(myHandwritingProvider)!;
    expect(hand.glyphs.keys.toSet(), {...small.split(''), 'M', '.'});
    final saved = (c.read(boardStoreProvider) as MemoryBoardStore).handwriting;
    expect(MyHandwriting.fromJson(saved)!.glyphs, hasLength(28));
    expect(c.read(settingsProvider).fixInHandwriting, isTrue);
    // A small letter sits on the baseline, a tail goes below it.
    final g = hand.glyphs['g']!.strokes.single.map((p) => p.y);
    expect(g.reduce((a, b) => a > b ? a : b), closeTo(0.9, 0.05));
    expect(hand.glyphs['a']!.strokes.single.map((p) => p.y).reduce((a, b) => a < b ? a : b), closeTo(-1, 0.05));

    // The fix is written in those letters: no typed word.
    final before = _ink(c).length;
    await _tap(tester, 'Change to Momentum');
    expect(shownPage(c)[p.title.last.id], isNull);
    expect(_texts(c).where((t) => t.text == 'Momentum'), isEmpty);
    expect(_ink(c), hasLength(before - 1 + 8));
    final written = _ink(c).skip(before - 1).toList();
    expect(written.first.color, p.title.last.color);
    expect(find.text('Changed “Momentem” to “Momentum”'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await _settle(tester);
    expect(_ink(c), hasLength(before));
    expect(shownPage(c)[p.title.last.id], isNotNull);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('unticked, the word is typed; Settings can write the sample again or forget it', (tester) async {
    final (c, p) = await _pump(tester, hand: testHand());
    await _rail(tester, 'Spell check');
    expect(tester.getSemantics(find.bySemanticsLabel('Fix it in my handwriting')).flagsCollection.isChecked, CheckedState.isTrue);
    await _tap(tester, 'Fix it in my handwriting');
    expect(c.read(settingsProvider).fixInHandwriting, isFalse);
    await _tap(tester, 'Change to Momentum');
    expect(_texts(c).singleWhere((t) => t.text == 'Momentum').font, 'hand');
    // Typed text has no box to tick.
    await _tap(tester, 'Previous issue');
    expect(find.text('Recieve'), findsOneWidget);
    expect(find.bySemanticsLabel('Fix it in my handwriting'), findsNothing);
    await _tap(tester, 'Done');

    await tester.tap(byLabel('More options'));
    await tester.pump();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('My handwriting'), findsOneWidget);
    expect(find.bySemanticsLabel('Write it again'), findsOneWidget);
    await tester.ensureVisible(find.bySemanticsLabel('Forget it'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Forget it'));
    await tester.pumpAndSettle();
    expect(c.read(myHandwritingProvider), isNull);
    expect((c.read(boardStoreProvider) as MemoryBoardStore).handwriting, isNull);
    expect(find.bySemanticsLabel('Write it'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a page with nothing misspelled is all clear', (tester) async {
    final r = FakeRecognizer();
    final ink = writeLine(r, 'total momentum is conserved', at: const Offset(104, 190), height: 38);
    final page = BoardPage(id: 'pg_clean', items: ink);
    final now = DateTime.utc(2026, 9, 25, 9);
    final nb = Notebook(id: 'nb_clean', title: 'Clean', createdAt: now, updatedAt: now, pageIds: [page.id]);
    await pumpCanvas(tester, store: storeWith(LoadedNotebook(nb, [page])), recognizer: r, extra: spellingOverrides());
    await _rail(tester, 'Spell check');
    expect(_count(tester), 'All clear');
    expect(find.text('No spelling issues left on this page'), findsOneWidget);
    expect(_spell(tester).issues, isEmpty);
    expect(_spell(tester).issues, isA<List<SpellIssue>>());
    await tester.pump(const Duration(seconds: 5));
  });
}
