import 'dart:ui';

import 'package:endless/board/model.dart';
import 'package:endless/recognition/recognized.dart';
import 'package:endless/recognition/segment.dart' show strokesRect;
import 'package:endless/spelling/my_handwriting.dart';
import 'package:endless/spelling/spell_check.dart';
import 'package:flutter_test/flutter_test.dart';

import 'hand_fixtures.dart';
import 'spelling_fixtures.dart';

void main() {
  setUpAll(loadSpelling);

  group('the sample', () {
    test('a letter written in its box is measured against the guide lines', () {
      const cell = Rect.fromLTWH(200, 50, 80, 100);
      final xLine = 50 + 100 * SampleGuides.xLine, base = 50 + 100 * SampleGuides.baseline;
      final xh = 100 * SampleGuides.xHeight;
      // A small letter from the x-line to the baseline, and a dot above it.
      final g = HandGlyph.fromBox([
        [InkPoint(220, xLine, 0.4, 0), InkPoint(240, base, 0.6, 30)],
        [InkPoint(230, xLine - 12, 0.5, 0)],
      ], cell)!;
      expect(g.strokes.first.first.x, 0);
      expect(g.strokes.first.first.y, closeTo(-1, 1e-9));
      expect(g.strokes.first.last.y, closeTo(0, 1e-9));
      expect(g.strokes.last.single.y, closeTo(-1 - 12 / xh, 1e-9));
      expect(g.width, closeTo(20 / xh, 1e-9));
      expect(g.strokes.first.last.pressure, 0.6);
      expect(HandGlyph.fromBox(const [], cell), isNull);
    });

    test('saved and read back', () {
      final hand = testHand(extra: 'M.');
      final back = MyHandwriting.fromJson(hand.toJson())!;
      expect(back.glyphs.keys, hand.glyphs.keys);
      expect(back.createdAt, hand.createdAt);
      final a = hand.glyphs['g']!, b = back.glyphs['g']!;
      expect(b.width, a.width);
      double r(double v) => (v * 1000).round() / 1000;
      expect([for (final p in b.strokes.single) (p.x, p.y, p.pressure, p.t)], [
        for (final p in a.strokes.single) (r(p.x), r(p.y), r(p.pressure), p.t),
      ]);
      expect(MyHandwriting.fromJson(null), isNull);
      expect(MyHandwriting.fromJson({'glyphs': {}}), isNull);
      expect(MyHandwriting.fromJson({'glyphs': {'a': {'w': 1, 's': [[1, 2, 3]]}}}), isNull);
    });

    test('what it can write: capitals from small letters, curly quotes, built-in marks', () {
      final hand = testHand();
      final m = hand.glyphFor('M')!;
      expect(m.width, closeTo(0.6 * capitalFromSmall, 1e-9));
      expect(m.strokes.single.map((p) => p.y).reduce((a, b) => a < b ? a : b), closeTo(-capitalFromSmall, 1e-9));
      expect(hand.glyphFor('’'), same(builtInMarks["'"]));
      expect(hand.glyphFor('.'), same(builtInMarks['.']));
      expect(hand.glyphFor('“')!.strokes, hasLength(2));
      expect(hand.canWrite("collision: don’t-stop!"), isTrue);
      expect(hand.canWrite('café'), isFalse);
      // A written capital or mark wins over the stand-in.
      expect(testHand(extra: 'M').glyphFor('M')!.width, 0.6);
    });
  });

  group('laying out and writing a word', () {
    test('letters side by side, marks closer, the same every time', () {
      final hand = testHand();
      final line = layOutInHand(hand, 'ab', gap: 0.2)!;
      expect(line.width, closeTo(0.6 + 0.2 + 0.6, 1e-9));
      expect((line.top, line.bottom), (-2.0, 0.0));
      expect(layOutInHand(hand, 'ab.', gap: 0.2)!.width, lessThan(line.width + 0.2 + builtInMarks['.']!.width));
      final a = layOutInHand(hand, 'momentum', seed: 3)!, b = layOutInHand(hand, 'momentum', seed: 3)!;
      expect(a.width, b.width);
      // A touch of variety, no more.
      expect(a.width, closeTo(layOutInHand(hand, 'momentum')!.width, 0.2));
      expect(layOutInHand(hand, 'café'), isNull);
    });

    test('the fix is fitted to the word it replaces: size, baseline, spacing, pen', () {
      final hand = testHand();
      final original = inkInHand(hand, 'momentem', left: 120, baseline: 300, scale: 24, gap: 0.35);
      final before = strokesRect(original)!;
      final out = writeInHand(hand, text: 'momentum', wrote: 'momentem', original: original, z: 50, now: DateTime.utc(2026, 10, 16))!;
      final after = strokesRect(out.strokes)!;
      expect(out.strokes, hasLength(8));
      expect(after.left, closeTo(before.left, 2));
      expect(after.top, closeTo(before.top, 0.06 * before.height));
      expect(after.bottom, closeTo(300, 0.06 * 24));
      expect(after.height, closeTo(before.height, 0.08 * before.height));
      expect(out.widthChange, closeTo(0, 0.05 * before.width));
      final s = out.strokes.first;
      expect((s.color, s.width, s.penType, s.usePressure, s.z), (original.first.color, 2.5, PenType.fountain, true, 50));
      expect(out.strokes.map((s) => s.id).toSet(), hasLength(8));
    });

    test('a shorter word says how much narrower it is; a capital and a tail fit too', () {
      final hand = testHand();
      final original = inkInHand(hand, 'Momentem', scale: 20, gap: 0.3);
      final out = writeInHand(hand, text: 'Moment', wrote: 'Momentem', original: original, z: 0, now: DateTime.utc(2026))!;
      expect(out.widthChange, closeTo(-2 * (0.6 + 0.3) * 20, 4));
      final tail = writeInHand(hand, text: 'momentgy', wrote: 'momentem', original: inkInHand(hand, 'momentem'), z: 0, now: DateTime.utc(2026))!;
      expect(strokesRect(tail.strokes)!.bottom, closeTo(200 + 0.9 * 30, 0.06 * 30));
      expect(writeInHand(hand, text: 'café', wrote: 'cafe', original: inkInHand(hand, 'cafe'), z: 0, now: DateTime.utc(2026)), isNull);
    });
  });

  group('spell check fixes in the hand', () {
    /// "the sistem is closd": one line, its words tied to their strokes.
    (BoardPage, PageRecognition, Map<String, List<StrokeItem>>) page(MyHandwriting hand) {
      final words = <String, List<StrokeItem>>{};
      var x = 100.0;
      for (final w in ['the', 'sistem', 'is', 'closd']) {
        words[w] = inkInHand(hand, w, left: x);
        x = strokesRect(words[w]!)!.right + 24;
      }
      final all = [for (final w in words.values) ...w];
      final read = PageRecognition(language: 'en-US', lines: [
        RecognizedLine(
          key: 'line',
          strokeIds: [for (final s in all) s.id],
          text: words.keys.join(' '),
          words: [
            for (final e in words.entries) RecognizedWord(e.key, strokeIds: [for (final s in e.value) s.id]),
          ],
        ),
      ]);
      return (BoardPage(id: 'pg', items: all), read, words);
    }

    test('the word is written in the hand and the rest of the line moves along', () {
      final hand = testHand();
      final (p, read, words) = page(hand);
      final issues = findIssues(p, read, Speller(testWords));
      expect(issues.map((i) => i.word), ['sistem', 'closd']);
      expect(issues.first.laterStrokeIds, [for (final w in ['is', 'closd']) for (final s in words[w]!) s.id]);

      final edit = planFixes(p, [(issues.first, 'systems')], z: 100, now: DateTime.utc(2026, 10, 16), hand: hand);
      expect(edit.remove.toSet(), {for (final s in words['sistem']!) s.id});
      expect(edit.insert, hasLength(7));
      expect(edit.insert.every((i) => i is StrokeItem), isTrue);
      // One letter longer: what follows moves right by about a letter.
      final moved = {for (final i in edit.replace) i.id: i as StrokeItem};
      expect(moved.keys.toSet(), {for (final w in ['is', 'closd']) for (final s in words[w]!) s.id});
      final dx = strokesRect([moved[words['is']!.first.id]!])!.left - strokesRect([words['is']!.first])!.left;
      expect(dx, closeTo((0.6 + 0.3) * 30, 6));
      expect(moved.values.first.pageInk.first.y, words['is']!.first.pageInk.first.y);
    });

    test('Fix all on one line: each fix starts where the one before left the line', () {
      final hand = testHand();
      final (p, read, words) = page(hand);
      final issues = findIssues(p, read, Speller(testWords));
      final edit = planFixes(p, [(issues[0], 'systems'), (issues[1], 'closed')], z: 100, now: DateTime.utc(2026, 10, 16), hand: hand);
      final closed = edit.insert.cast<StrokeItem>().skip(7).toList();
      expect(closed, hasLength(6));
      // "closed" starts where "closd" had moved to, and "is" moved once.
      final closdMoved = strokesRect(words['closd']!)!.left + (strokesRect(edit.insert.cast<StrokeItem>().take(7))!.width -
          strokesRect(words['sistem']!)!.width);
      expect(strokesRect(closed)!.left, closeTo(closdMoved, 6));
      expect(edit.replace.map((i) => i.id).toSet(), {for (final s in words['is']!) s.id});
    });

    test('without a sample, or a letter it lacks, the word is typed in the handwriting font', () {
      final hand = testHand();
      final (p, read, _) = page(hand);
      final issues = findIssues(p, read, Speller(testWords));
      for (final (h, word) in [(null, 'systems'), (hand, 'systèm')]) {
        final edit = planFixes(p, [(issues.first, word)], z: 100, now: DateTime.utc(2026), hand: h);
        expect((edit.insert.single as TextItem).font, 'hand');
        expect(edit.replace, isEmpty);
      }
    });
  });
}
