import 'dart:ui';

import 'package:endless/board/codec.dart';
import 'package:endless/board/ids.dart';
import 'package:endless/board/model.dart';
import 'package:endless/recognition/reader.dart';
import 'package:endless/recognition/segment.dart' show strokesRect;
import 'package:endless/spelling/spell_check.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:flutter_test/flutter_test.dart';

import '../recognition/fake_ink.dart';
import 'spelling_fixtures.dart';

/// Spell.png's page: three lines of handwriting and a text box.
({BoardPage page, List<StrokeItem> title, List<StrokeItem> line2, List<StrokeItem> line3, TextItem box}) spellPage(
  FakeRecognizer r,
) {
  final title = writeLine(r, 'Lecture 3 — Momentem', at: const Offset(104, 110), height: 42, color: tokens.inkDefaults[1]);
  final line2 = writeLine(r, 'total momentum is conserved in a closed sistem', at: const Offset(104, 190), height: 38, z: 10);
  final line3 = writeLine(r, 'elastic colision: kinetic energy is conserved too', at: const Offset(104, 258), height: 38, z: 30);
  final box = TextItem(
    id: newId('it'),
    x: 100,
    y: 322,
    z: 50,
    createdAt: DateTime.utc(2026, 9, 25, 10),
    wrap: 720,
    text: 'Recieve lab data from Maya by Sunday',
    size: 18,
    color: tokens.inkDefaults[0],
  );
  final page = BoardPage(id: newId('pg'), items: [...title, ...line2, ...line3, box]);
  return (page: page, title: title, line2: line2, line3: line3, box: box);
}

void main() {
  setUpAll(loadSpelling);

  group('what spell check accepts', () {
    test('words, forms and names; not misspellings', () {
      final s = Speller(testWords);
      for (final w in ['momentum', 'Momentum', 'conserved', 'Sunday', 'Maya', "Maya's", 'Maya’s', "students'", 'well-known', "don't"]) {
        expect(s.accepts(w), isTrue, reason: w);
      }
      for (final w in ['Momentem', 'sistem', 'colision', 'Recieve', 'self-colision']) {
        expect(s.accepts(w), isFalse, reason: w);
      }
    });

    test('numbers, single letters, short abbreviations and addresses are not checked', () {
      final s = Speller(testWords);
      for (final w in ['3', '2nd', 'x', 'ATP', 'NADPH', 'a@b.com', 'E=mc2']) {
        expect(s.accepts(w), isTrue, reason: w);
      }
      expect(s.accepts('XYZZYQ'), isFalse);
    });

    test('my dictionary', () {
      expect(Speller(testWords).accepts('Endlessly-ish'), isFalse);
      expect(Speller(testWords, mine: ['Feynmanesque']).accepts('feynmanesque'), isTrue);
    });
  });

  group('the issues on a page', () {
    test('Spell.png: three handwritten words and one typed, in reading order', () async {
      final r = FakeRecognizer()..alts['sistem'] = ['sisten'];
      final p = spellPage(r);
      final read = await readPage(p.page, language: 'en-US', recognizer: r);
      final issues = findIssues(p.page, read, Speller(testWords));
      expect([for (final i in issues) i.word], ['Momentem', 'sistem', 'colision', 'Recieve']);
      expect([for (final i in issues) i.kind], [...List.filled(3, SpellKind.handwriting), SpellKind.typed]);

      final momentem = issues[0];
      expect(momentem.strokeIds, [p.title.last.id]);
      expect(momentem.rect, strokesRect([p.title.last]));
      expect(issues[1].hints, ['sisten']);
      expect((issues[2].lead, issues[2].trail), ('', ':'));

      final recieve = issues[3];
      expect(recieve.itemId, p.box.id);
      expect((recieve.start, recieve.end), (0, 7));
      expect(recieve.rect.left, closeTo(100, 0.5));
      expect(recieve.rect.top, closeTo(322, 6));
      expect(recieve.rect.width, inInclusiveRange(50, 7 * 18));
    });

    test('words ignored on the page, and in my dictionary, are left out', () async {
      final r = FakeRecognizer();
      final p = spellPage(r);
      p.page.spellIgnore.add('SISTEM');
      final read = await readPage(p.page, language: 'en-US', recognizer: r);
      final issues = findIssues(p.page, read, Speller(testWords, mine: ['recieve']));
      expect([for (final i in issues) i.word], ['Momentem', 'colision']);
    });

    test('a word whose strokes are gone is not flagged from an old reading', () async {
      final r = FakeRecognizer();
      final p = spellPage(r);
      final read = await readPage(p.page, language: 'en-US', recognizer: r);
      p.page.items.remove(p.title.last);
      final issues = findIssues(p.page, read, Speller(testWords));
      expect(issues.map((i) => i.word), isNot(contains('Momentem')));
    });

    test('typed text on a turned sticky note', () {
      final note = StickyItem(
        id: newId('it'),
        x: 400,
        y: 400,
        rotation: 2,
        z: 1,
        createdAt: DateTime.utc(2026, 9, 25),
        w: 242,
        h: 220,
        color: tokens.stickyColors[0],
      ).withText('Remember teh lab', color: tokens.inkDefaults[0], at: DateTime.utc(2026, 9, 25));
      final page = BoardPage(id: newId('pg'), items: [note]);
      final issue = findIssues(page, null, Speller(testWords)).single;
      expect((issue.word, issue.itemId, issue.start, issue.end), ('teh', note.id, 9, 12));
      // The box turns with the note: its bottom edge isn't level.
      expect(issue.quad[2].dy, isNot(closeTo(issue.quad[3].dy, 0.5)));

      final fix = planFixes(page, [(issue, 'the')], z: 2, now: DateTime.utc(2026, 9, 26));
      expect((fix.replace.single as StickyItem).text, 'Remember the lab');
    });

    test('reading order: down the page, then along each line', () {
      SpellIssue at(String word, Rect r) =>
          SpellIssue(id: word, kind: SpellKind.typed, word: word, quad: [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft]);
      final order = inReadingOrder([
        at('d', const Rect.fromLTWH(10, 200, 50, 30)),
        at('b', const Rect.fromLTWH(300, 104, 50, 30)),
        at('a', const Rect.fromLTWH(10, 100, 50, 40)),
        at('c', const Rect.fromLTWH(600, 112, 50, 20)),
      ]);
      expect([for (final i in order) i.word], ['a', 'b', 'c', 'd']);
    });
  });

  group('fixes', () {
    test('typed words change in their text; handwriting is replaced by the word in the handwriting font', () async {
      final r = FakeRecognizer();
      final p = spellPage(r);
      final read = await readPage(p.page, language: 'en-US', recognizer: r);
      final issues = findIssues(p.page, read, Speller(testWords));
      final now = DateTime.utc(2026, 9, 26);
      final fix = planFixes(p.page, [(issues[0], 'Momentum'), (issues[2], 'collision'), (issues[3], 'Receive')], z: 100, now: now);

      expect(fix.remove, [p.title.last.id, p.line3[1].id]);
      final typed = fix.replace.single as TextItem;
      expect(typed.text, 'Receive lab data from Maya by Sunday');
      final words = fix.insert.cast<TextItem>();
      expect([for (final t in words) t.text], ['Momentum', 'collision:']);
      final momentum = words.first;
      expect(momentum.font, 'hand');
      expect(momentum.color, tokens.inkDefaults[1]);
      expect(momentum.x, closeTo(issues[0].rect.left, 0.01));
      // About the size of the writing, centered on its line.
      expect(momentum.size, inkTextSize(42));
      expect(momentum.y + momentum.h / 2, closeTo(issues[0].lineRect!.center.dy, 0.5));
      expect(momentum.z, 100);
    });

    test('two words in one text box', () {
      final box = TextItem(
        id: newId('it'),
        x: 0,
        y: 0,
        z: 1,
        createdAt: DateTime.utc(2026),
        wrap: 400,
        text: 'teh sistem works',
        color: tokens.inkDefaults[0],
      );
      final page = BoardPage(id: newId('pg'), items: [box]);
      final issues = findIssues(page, null, Speller(testWords));
      expect(issues.map((i) => i.word), ['teh', 'sistem']);
      final fix = planFixes(page, [(issues[0], 'the'), (issues[1], 'system')], z: 2, now: DateTime.utc(2026));
      expect((fix.replace.single as TextItem).text, 'the system works');
    });
  });

  test('the ignore list is saved with the page', () {
    final page = BoardPage(id: 'pg_1', spellIgnore: ['Feynman', 'sistem']);
    final json = encodePage(page);
    expect(json, contains('"spelling":{"ignore":["Feynman","sistem"]}'));
    expect(decodePage(json).spellIgnore, ['Feynman', 'sistem']);
    expect(encodePage(BoardPage(id: 'pg_2')), isNot(contains('spelling')));
    expect(decodePage(encodePage(BoardPage(id: 'pg_2'))).spellIgnore, isEmpty);
  });

  test('my dictionary and recent lookups are saved in settings', () {
    final s = AppSettings(myWords: ['Feynmanesque'], recentLookups: ['conserve', 'momentum']);
    final back = AppSettings.fromJson(s.toJson());
    expect(back.myWords, ['Feynmanesque']);
    expect(back.recentLookups, ['conserve', 'momentum']);
    expect(AppSettings().toJson().containsKey('myWords'), isFalse);
  });
}
