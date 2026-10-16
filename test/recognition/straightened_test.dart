import 'package:endless/board/ids.dart';
import 'package:endless/board/model.dart';
import 'package:endless/recognition/reader.dart';
import 'package:endless/recognition/segment.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ink.dart';

// Letters straightened by "Straighten lines" (or a hold) are still writing
// when they're letter-sized lines, circles or ovals on a line of writing;
// bigger shapes, boxes and triangles, and shapes on their own, are drawings.

/// [s] straightened into [shape] with [points].
StrokeItem _straight(StrokeItem s, String shape, List<Offset> points) =>
    s.copyWith(id: newId('it'), pagePoints: [for (final (i, p) in points.indexed) InkPoint(p.dx, p.dy, 0.5, i * 10)], shape: () => shape);

List<Offset> _circle(Offset c, double r) => [
      for (var a = 0; a <= 24; a++) c + Offset.fromDirection(a * 3.14159 / 12, r),
    ];

void main() {
  test('a letter straightened into a line or a circle stays in its line and word', () {
    final r = FakeRecognizer();
    // "hello" then "lo": the l straightened into a line, the o into a circle.
    final hello = writeLine(r, 'hello', at: const Offset(100, 100));
    final lo = writeLine(r, 'l o', at: const Offset(200, 100));
    final l = _straight(lo[0], 'line', [const Offset(200, 100), const Offset(200, 130)]);
    final o = _straight(lo[1], 'circle', _circle(const Offset(246, 118), 11));
    final lines = segmentLines([...hello, l, o]);
    expect(lines, hasLength(1));
    expect(lines.single.strokes.map((s) => s.id), [hello.single.id, l.id, o.id]);
    expect(writingIn([...hello, l, o]), [...hello, l, o]);
  });

  test('boxes, triangles, big shapes and shapes on their own aren’t writing', () {
    final r = FakeRecognizer();
    final words = writeLine(r, 'buy milk', at: const Offset(140, 100));
    StrokeItem shape(String kind, List<Offset> pts) => _straight(words.first, kind, pts);
    // A checkbox in front of a to-do, the size of a letter.
    final box = shape('rect', const [Offset(100, 104), Offset(124, 104), Offset(124, 128), Offset(100, 128), Offset(100, 104)]);
    final triangle = shape('triangle', const [Offset(400, 128), Offset(412, 104), Offset(424, 128), Offset(400, 128)]);
    // An underline and a circle around the words.
    final underline = shape('line', const [Offset(140, 140), Offset(340, 140)]);
    final ring = shape('ellipse', _circle(const Offset(220, 115), 120));
    final all = [...words, box, triangle, underline, ring];
    final read = writingIn(all);
    expect(read, words);
    // Straightened shapes with no writing around them: no lines at all.
    final alone = [
      shape('line', const [Offset(500, 500), Offset(500, 530)]),
      shape('circle', _circle(const Offset(540, 515), 12)),
    ];
    expect(segmentLines(alone), isEmpty);
  });

  test('a straightened letter is read with its word', () async {
    final r = FakeRecognizer();
    final ink = writeLine(r, 'total momentum is conserved', at: const Offset(100, 100));
    // "is" was written at x 322–350.
    final isWord = _straight(ink[2], 'line', [const Offset(336, 100), const Offset(336, 130)]);
    r.labelAt(const Offset(336, 100), 'is');
    final page = BoardPage(id: 'pg', items: [ink[0], ink[1], isWord, ink[3]]);
    expect(handwritingOn(page), hasLength(4));
    final read = await readPage(page, language: 'en-US', recognizer: r);
    expect(read.text, 'total momentum is conserved');
    expect(read.lines.single.words[2].strokeIds, [isWord.id]);
  });
}
