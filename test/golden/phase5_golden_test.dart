// Golden images of Phase 5 at 1280×800: handwriting search
// (design/screens/Search.png) in light and dark, Convert to text
// (design/screens/Convert.png) with a word it isn't sure of, and spell
// check with the dictionary (design/screens/Spell.png) in light and dark,
// plus the thesaurus and "Teach Endless your handwriting".
//
// Regenerate after an intended visual change:
//   flutter test --update-goldens test/golden
@Tags(['golden'])
library;

import 'package:endless/board/ids.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/spelling/my_handwriting.dart' show sampleSteps;
import 'package:endless/state/settings.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:endless/ui/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../recognition/fake_ink.dart';
import '../spelling/spell_check_test.dart' show spellPage;
import '../spelling/spelling_fixtures.dart';
import '../ui/spell_test.dart' show writeSample;
import '../ui/search_test.dart' show searchLibrary;

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

void _search(String name, {ThemeMode mode = ThemeMode.light}) {
  testWidgets(name, (tester) async {
    debugDisableShadows = false;
    try {
      final r = FakeRecognizer();
      final store = searchLibrary(r);
      store.settings = AppSettings(themeMode: mode).toJson();
      await pumpApp(tester, store: store, location: Routes.search('momentum'), recognizer: r);
      await _settle(tester);
      // The second match, as Search.png picks it.
      await tester.tap(find.text('Page 3 · School › Physics').at(1));
      await _settle(tester);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('$name.png'));
    } finally {
      debugDisableShadows = true;
    }
  });
}

/// Spell.png's page on the canvas, with the design's recent lookups.
Future<void> _spellCanvas(WidgetTester tester, ThemeMode mode) async {
  final r = FakeRecognizer();
  final p = spellPage(r);
  final now = DateTime.utc(2026, 9, 25, 9);
  final nb = Notebook(id: 'nb_spell', title: 'Physics — Lecture notes', createdAt: now, updatedAt: now, pageIds: [p.page.id]);
  await pumpCanvas(
    tester,
    store: storeWith(
      LoadedNotebook(nb, [p.page]),
      settings: AppSettings(trayOpen: false, themeMode: mode, recentLookups: ['collision', 'conserve']),
    ),
    recognizer: r,
    extra: spellingOverrides(),
  );
}

Future<void> _writingHelp(WidgetTester tester, String item) async {
  await tester.tap(byLabel('Writing help'));
  await tester.pump();
  await tester.tap(find.text(item));
  await _settle(tester);
}

void _spell(String name, {ThemeMode mode = ThemeMode.light}) {
  testWidgets(name, (tester) async {
    debugDisableShadows = false;
    try {
      await _spellCanvas(tester, mode);
      await _writingHelp(tester, 'Spell check');
      await tester.tap(find.bySemanticsLabel('Look up'));
      await _settle(tester);
      await tester.pump(const Duration(seconds: 5));
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('$name.png'));
    } finally {
      debugDisableShadows = true;
    }
  });
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    await loadSpelling();
  });

  _spell('spell');
  _spell('spell_dark', mode: ThemeMode.dark);

  testWidgets('teach_handwriting', (tester) async {
    debugDisableShadows = false;
    try {
      await _spellCanvas(tester, ThemeMode.light);
      await _writingHelp(tester, 'Spell check');
      await tester.tap(find.bySemanticsLabel('Fix it in my handwriting'));
      await _settle(tester);
      final small = sampleSteps[0].letters;
      await writeSample(tester, small, step: small);
      await tester.tap(find.bySemanticsLabel('Next'));
      await _settle(tester);
      await writeSample(tester, 'ABCDEFGS.,', step: sampleSteps[1].letters);
      await _settle(tester);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('teach_handwriting.png'));
    } finally {
      debugDisableShadows = true;
    }
  });

  testWidgets('spell_thesaurus', (tester) async {
    debugDisableShadows = false;
    try {
      await _spellCanvas(tester, ThemeMode.light);
      await _writingHelp(tester, 'Dictionary & thesaurus');
      await tester.enterText(find.byType(TextField), 'conserve');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel('Thesaurus'));
      await _settle(tester);
      await tester.pump(const Duration(seconds: 5));
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('spell_thesaurus.png'));
    } finally {
      debugDisableShadows = true;
    }
  });

  _search('search');
  _search('search_dark', mode: ThemeMode.dark);

  testWidgets('convert', (tester) async {
    debugDisableShadows = false;
    try {
      final r = FakeRecognizer()..alts['conserved'] = ['conversed', 'concerned'];
      final blue = tokens.inkDefaults[1];
      final title = writeLine(r, 'Lecture three Momentum', at: const Offset(300, 96), height: 50, color: blue);
      final para = [
        ...writeLine(r, 'total momentum is conserved', at: const Offset(306, 262), height: 36, z: 10),
        ...writeLine(r, 'in a closed system', at: const Offset(306, 312), height: 36, z: 20),
      ];
      final now = DateTime.utc(2026, 9, 25, 9);
      final page = BoardPage(id: newId('pg'), items: [...title, ...para]);
      final nb = Notebook(id: 'nb_convert', title: 'Physics — Lecture notes', createdAt: now, updatedAt: now, pageIds: [page.id]);
      final c = await pumpCanvas(
        tester,
        store: storeWith(LoadedNotebook(nb, [page]), settings: AppSettings(trayOpen: false, tool: CanvasTool.lasso)),
        recognizer: r,
      );
      await tester.pump();
      canvasPane.selection.select([for (final s in para) s.id]);
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Convert to text'));
      await _settle(tester);
      await tester.pump(const Duration(seconds: 5));
      expect(c.read(settingsProvider).tool, CanvasTool.lasso);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('convert.png'));
    } finally {
      debugDisableShadows = true;
    }
  });
}
