import 'dart:ui';

import 'package:endless/board/model.dart';
import 'package:endless/recognition/convert.dart';
import 'package:endless/recognition/reader.dart';
import 'package:endless/recognition/recognized.dart';
import 'package:endless/recognition/segment.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:endless/transfer/pdf_export.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'fake_ink.dart';

void main() {
  group('lines, words and paragraphs', () {
    test('ink splits into lines in reading order, words by their gaps, paragraphs by space', () {
      final r = FakeRecognizer();
      final title = writeLine(r, 'Lecture three', at: const Offset(100, 100));
      final a = writeLine(r, 'total momentum is conserved', at: const Offset(100, 220));
      final b = writeLine(r, 'in a closed system', at: const Offset(100, 265));
      // Written in a muddle: the second line first.
      final lines = segmentLines([...b, ...title, ...a]);
      expect(lines, hasLength(3));
      expect(lines.map((l) => l.strokes.length), [2, 4, 4]);
      expect(lines.map((l) => l.words.length), [2, 4, 4]);
      expect(lines.map((l) => l.block), [0, 1, 1]);
      expect(lines[1].strokeIds, [for (final s in a) s.id]);
    });

    test('dots and small marks join the line they sit on', () {
      final r = FakeRecognizer();
      final word = writeLine(r, 'mini', at: const Offset(100, 100));
      final dot = strokeFrom([const Offset(130, 92), const Offset(131, 93)]);
      final lines = segmentLines([...word, dot]);
      expect(lines, hasLength(1));
      expect(lines.single.strokes, hasLength(2));
    });

    test('highlighter, shapes, arrows and connectors aren’t handwriting', () {
      final pen = strokeFrom([const Offset(0, 0), const Offset(40, 20)]);
      final marker = strokeFrom([const Offset(0, 0), const Offset(40, 20)], tool: InkTool.marker);
      final shape = pen.copyWith(id: 'x', shape: () => 'rect');
      final arrow = pen.copyWith(id: 'y', arrow: () => const ArrowHeads(end: true));
      final joined = pen.copyWith(id: 'z', startItemId: () => 'box');
      expect([pen, marker, shape, arrow, joined].map(isHandwriting), [true, false, false, false, false]);
      expect(segmentLines([marker, shape, arrow, joined]), isEmpty);
    });

    test('a line’s key stays when the ink moves, and changes when it changes', () {
      final r = FakeRecognizer();
      final ink = writeLine(r, 'momentum is conserved', at: const Offset(100, 100));
      final moved = [for (final s in ink) s.mapped((p) => p + const Offset(300, 450))];
      expect(lineKey(moved, 'en-US'), lineKey(ink, 'en-US'));
      expect(lineKey(ink, 'de-DE'), isNot(lineKey(ink, 'en-US')));
      final bigger = [for (final s in ink) s.mapped((p) => p * 1.5)];
      expect(lineKey(bigger, 'en-US'), isNot(lineKey(ink, 'en-US')));
      expect(lineKey(ink.sublist(1), 'en-US'), isNot(lineKey(ink, 'en-US')));
    });

    test('FNV-1a 64 matches the reference values', () {
      expect(fnv64(''), 'cbf29ce484222325');
      expect(fnv64('a'), 'af63dc4c8601ec8c');
      expect(fnv64('foobar'), '85944171f73967e8');
    });
  });

  group('reading', () {
    test('each word gets its strokes, and other readings where it wasn’t sure', () async {
      final r = FakeRecognizer()..alts['conserved'] = ['conversed', 'concerned'];
      final ink = writeLine(r, 'momentum is conserved', at: const Offset(100, 100));
      final read = await readInk(ink, language: 'en-US', recognizer: r);
      final line = read.lines.single;
      expect(line.text, 'momentum is conserved');
      expect(line.words.map((w) => w.strokeIds.single), [for (final s in ink) s.id]);
      expect(line.words.map((w) => w.alts), [isEmpty, isEmpty, ['conversed', 'concerned']]);
    });

    test('when the gaps don’t match the words, strokes go by their share of the line', () {
      final r = FakeRecognizer();
      // Two strokes that read as three words.
      final ink = writeLine(r, 'aaaaaa bbbbbbbbb', at: const Offset(0, 0));
      final line = segmentLines(ink).single;
      final aligned = alignLine(line, ['to be or'], key: 'k');
      expect(aligned.words.map((w) => w.text), ['to', 'be', 'or']);
      expect({for (final w in aligned.words) ...w.strokeIds}, {for (final s in ink) s.id});
      final strokes = {for (final s in ink) s.id: s};
      expect(aligned.wordRect(0, strokes), isNotNull);
    });

    test('lines read before are reused; new ones read with what came before', () async {
      final r = FakeRecognizer();
      final a = writeLine(r, 'total momentum', at: const Offset(100, 100));
      final first = await readInk(a, language: 'en-US', recognizer: r);
      expect(r.recognized, 1);
      final b = writeLine(r, 'is conserved', at: const Offset(100, 145));
      final second = await readInk([...a, ...b], language: 'en-US', recognizer: r, previous: first);
      expect(r.recognized, 2);
      expect(r.contexts.last, 'total momentum');
      expect(second.text, 'total momentum is conserved');
      // Another language reads everything again.
      r.models.add('de-DE');
      await readInk([...a, ...b], language: 'de-DE', recognizer: r, previous: second);
      expect(r.recognized, 4);
      // With no recognizer, what was read is kept and the rest left out.
      final c = writeLine(r, 'new words', at: const Offset(100, 400));
      final kept = await readInk([...a, ...b, ...c], language: 'en-US', previous: second);
      expect(kept.text, 'total momentum is conserved');
    });

    test('recognition.json round trip', () async {
      final r = FakeRecognizer()..alts['closed'] = ['dosed'];
      final ink = [
        ...writeLine(r, 'total momentum', at: const Offset(0, 0)),
        ...writeLine(r, 'in a closed system', at: const Offset(0, 200)),
      ];
      final read = await readInk(ink, language: 'en-US', recognizer: r);
      final back = PageRecognition.fromJson(read.toJson())!;
      expect(back.language, 'en-US');
      expect(back.text, 'total momentum\n\nin a closed system');
      expect(back.lines.map((l) => l.key), read.lines.map((l) => l.key));
      expect(back.lines.last.words[2].alts, ['dosed']);
      expect(back.lines.last.block, 1);
    });

    test('the PDF text layer puts each line over where its ink is now', () async {
      final r = FakeRecognizer();
      final ink = writeLine(r, 'momentum is conserved', at: const Offset(100, 100));
      final read = await readInk(ink, language: 'en-US', recognizer: r);
      final moved = [for (final s in ink) s.mapped((p) => p + const Offset(0, 500))];
      final page = BoardPage(id: 'p', items: moved);
      final runs = RecognizedHandwriting({'p': read}).runsFor(page);
      expect(runs.single.text, 'momentum is conserved');
      expect(runs.single.rect.top, closeTo(600, 1));
      expect(RecognizedHandwriting({'p': read}).runsFor(BoardPage(id: 'other')), isEmpty);
    });
  });

  group('convert preview', () {
    test('paragraphs start with a capital and sentences end with a full stop (Convert.png)', () async {
      final r = FakeRecognizer()..alts['conserved'] = ['conversed', 'concerned'];
      final ink = [
        ...writeLine(r, 'total momentum is conserved', at: const Offset(0, 0)),
        ...writeLine(r, 'in a closed system', at: const Offset(0, 45)),
        ...writeLine(r, 'p = mv', at: const Offset(0, 200)),
      ];
      final p = previewOf(await readInk(ink, language: 'en-US', recognizer: r));
      expect(p.text, 'Total momentum is conserved in a closed system.\n\nP = mv');
      expect(p.unsure.single.token, 3);
      expect(p.unsure.single.options, ['conserved', 'conversed', 'concerned']);
    });

    test('picking another reading keeps the word’s punctuation', () {
      expect(replaceToken('Total momentum is conserved.', 3, 'concerned'), 'Total momentum is concerned.');
      expect(replaceToken('“Total”, he said', 0, 'Whole'), '“Whole”, he said');
      expect(coreOf('(yes!)'), ('(', 'yes', '!)'));
      expect(replaceToken('a b', 7, 'c'), 'a b');
    });
  });

  group('convert plan', () {
    final now = DateTime.utc(2026, 10, 9);

    test('replace: the ink goes, serif text in its color takes its place, one box per paragraph', () {
      final r = FakeRecognizer();
      final blue = tokens.inkDefaults[1];
      final a = writeLine(r, 'total momentum is conserved', at: const Offset(300, 250), color: blue, height: 40);
      final b = writeLine(r, 'p = mv', at: const Offset(300, 500));
      final plan = planConvert(
        strokes: [...a, ...b],
        text: 'Total momentum is conserved.\n\nP = mv',
        place: ConvertPlace.replace,
        z: 10,
        now: now,
      );
      expect(plan.remove, hasLength(a.length + b.length));
      expect(plan.replace, isEmpty);
      expect(plan.insert.map((t) => t.text), ['Total momentum is conserved.', 'P = mv']);
      final first = plan.insert.first;
      expect((first.x, first.y), (300, 250));
      expect(first.font, 'serif');
      expect(first.color, blue);
      expect(first.size, textSizeFor(40));
      expect(plan.insert.map((t) => t.z), [10, 11]);
    });

    test('keep: the text goes where the ink was and the ink moves down under it', () {
      final r = FakeRecognizer();
      final a = writeLine(r, 'momentum is conserved', at: const Offset(300, 250));
      final b = writeLine(r, 'p = mv', at: const Offset(300, 400));
      final plan = planConvert(strokes: [...a, ...b], text: 'One.\n\nTwo.', place: ConvertPlace.keep, z: 1, now: now);
      expect(plan.remove, isEmpty);
      expect(plan.insert, hasLength(2));
      final t1 = plan.insert[0], t2 = plan.insert[1];
      expect(t1.y, 250);
      final moved = {for (final i in plan.replace) i.id: i as StrokeItem};
      final firstInk = strokesRect([for (final s in a) moved[s.id]!])!;
      expect(firstInk.top, closeTo(250 + t1.h + 12, 0.5));
      // The second paragraph's text moves down too, by the first one's text.
      expect(t2.y, closeTo(400 + t1.h + 12, 0.5));
      final secondInk = strokesRect([for (final s in b) moved[s.id]!])!;
      expect(secondInk.top, closeTo(t2.y + t2.h + 12, 0.5));
    });

    test('text that doesn’t split like the ink goes in one box; copy changes nothing', () {
      final r = FakeRecognizer();
      final a = writeLine(r, 'one', at: const Offset(0, 0));
      final b = writeLine(r, 'two', at: const Offset(0, 300));
      final plan = planConvert(strokes: [...a, ...b], text: 'all of it', place: ConvertPlace.replace, z: 1, now: now);
      expect(plan.insert.single.text, 'all of it');
      expect(plan.remove, hasLength(2));
      final copy = planConvert(strokes: [...a, ...b], text: 'x', place: ConvertPlace.copy, z: 1, now: now);
      expect([copy.remove, copy.replace, copy.insert], everyElement(isEmpty));
    });

    test('text size follows the writing, within the text box sizes', () {
      expect(textSizeFor(40), 28);
      expect(textSizeFor(5), 14);
      expect(textSizeFor(400), 64);
    });
  });

  test('a rect helper covers points, not pen width', () {
    final s = strokeFrom([const Offset(10, 10), const Offset(50, 30)], width: 8);
    expect(inkRect(s), const Rect.fromLTRB(10, 10, 50, 30));
  });
}
