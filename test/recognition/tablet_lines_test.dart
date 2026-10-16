import 'dart:io';

import 'package:endless/board/codec.dart';
import 'package:endless/board/model.dart';
import 'package:endless/recognition/segment.dart';
import 'package:flutter_test/flutter_test.dart';

// Real S Pen ink from the tablet (owner's test page, 2026-10-15): four lines,
// "lets test" / "this out bc" / "I am Not" / "about to photosynthesise".
// The last line rises to the right, and its "p" was erased and written again
// after the rest of the word. Lines used to break apart on it.

List<StrokeItem> _ink() =>
    decodePage(File('test/fixtures/recognition/tablet_2026-10-15.json').readAsStringSync())
        .items
        .cast<StrokeItem>();

/// Stroke numbers (in the order they're stored, which is the order written).
List<int> _nums(List<StrokeItem> all, Iterable<StrokeItem> some) => [for (final s in some) all.indexOf(s)]..sort();

List<int> _range(int from, int to) => [for (var i = from; i <= to; i++) i];

void main() {
  test('the lines as written, rising writing and a rewritten letter included', () {
    final ink = _ink();
    final lines = segmentLines(ink);
    expect([for (final l in lines) _nums(ink, l.strokes)], [
      _range(0, 10),
      _range(11, 22),
      _range(23, 31),
      _range(32, 55),
    ]);
  });

  test('the words on each line', () {
    final ink = _ink();
    final words = [
      for (final l in segmentLines(ink)) [for (final w in l.words) _nums(ink, w)],
    ];
    expect(words, [
      [_range(0, 4), _range(5, 10)], // lets test
      [_range(11, 16), _range(17, 20), _range(21, 22)], // this out bc
      [_range(23, 25), _range(26, 27), _range(28, 31)], // I am Not
      [_range(32, 37), _range(38, 39), _range(40, 55)], // about to photosynthesise
    ]);
  });

  test('the recognizer reads a letter written again later where it is in its word', () {
    final ink = _ink();
    final line = segmentLines(ink).last;
    final order = [for (final s in line.reading) ink.indexOf(s)];
    // The p (54, 55) comes before the rest of the word (40…), not after it.
    expect(order.indexOf(54), lessThan(order.indexOf(40)));
    expect(order.indexOf(55), lessThan(order.indexOf(40)));
    // Everything else keeps the order it was written in.
    expect([for (final i in order) if (i != 54 && i != 55) i], [..._range(32, 53)]);
    // A line written in order reads in that order: t-crosses and i-dots stay with their letters.
    expect([for (final s in segmentLines(ink).first.reading) ink.indexOf(s)], _range(0, 10));
  });
}
