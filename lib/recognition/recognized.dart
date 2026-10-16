import 'dart:math' as math;
import 'dart:ui' show Rect;

import '../board/model.dart';
import 'segment.dart';

// What handwriting was recognized as, line by line, with each word tied to
// the strokes that wrote it. Stored per notebook in `index/recognition.json`
// (docs/BOARD_FORMAT.md) and in the search index.

/// One word of a recognized line.
class RecognizedWord {
  const RecognizedWord(this.text, {this.strokeIds = const [], this.alts = const []});

  final String text;

  /// The strokes that wrote it (may be empty when the line's words and
  /// its gaps didn't line up; then it's placed by its share of the line).
  final List<String> strokeIds;

  /// Other readings, best first, when recognition wasn't sure. Empty when
  /// it was.
  final List<String> alts;

  bool get unsure => alts.isNotEmpty;

  Json toJson() => {
        't': text,
        if (strokeIds.isNotEmpty) 's': strokeIds,
        if (alts.isNotEmpty) 'alts': alts,
      };

  static RecognizedWord? fromJson(Object? j) {
    if (j is! Map || j['t'] is! String) return null;
    return RecognizedWord(
      j['t'] as String,
      strokeIds: [...?(j['s'] as List?)?.whereType<String>()],
      alts: [...?(j['alts'] as List?)?.whereType<String>()],
    );
  }
}

/// One line of handwriting and what it says.
class RecognizedLine {
  const RecognizedLine({
    required this.key,
    required this.strokeIds,
    required this.text,
    required this.words,
    this.block = 0,
    this.holder,
    this.sub,
  });

  /// [lineKey] of its strokes: the same ink gets the same key.
  final String key;

  /// In pen order.
  final List<String> strokeIds;
  final String text;
  final List<RecognizedWord> words;

  /// Its paragraph on the page, counting from 0 in reading order.
  final int block;

  /// The sticky note or Office card it's written on, or null for ink on
  /// the page itself.
  final String? holder;

  /// On an Office card, which page, slide or sheet (from 1); in a sticky
  /// stack, which note under the top one (from 1). Null otherwise.
  final int? sub;

  RecognizedLine inBlock(int b) => at(block: b, holder: holder, sub: sub);

  /// The same line in paragraph [block], written on [holder] ([sub]).
  RecognizedLine at({required int block, String? holder, int? sub}) =>
      block == this.block && holder == this.holder && sub == this.sub
          ? this
          : RecognizedLine(
              key: key,
              strokeIds: strokeIds,
              text: text,
              words: words,
              block: block,
              holder: holder,
              sub: sub,
            );

  Json toJson() => {
        'key': key,
        'strokes': strokeIds,
        'text': text,
        'words': [for (final w in words) w.toJson()],
        'block': block,
        if (holder != null) 'holder': holder,
        if (sub != null) 'sub': sub,
      };

  static RecognizedLine? fromJson(Object? j) {
    if (j is! Map || j['key'] is! String || j['text'] is! String) return null;
    return RecognizedLine(
      key: j['key'] as String,
      strokeIds: [...?(j['strokes'] as List?)?.whereType<String>()],
      text: j['text'] as String,
      words: [
        for (final w in (j['words'] as List?) ?? const []) ?RecognizedWord.fromJson(w),
      ],
      block: (j['block'] as num?)?.toInt() ?? 0,
      holder: j['holder'] as String?,
      sub: (j['sub'] as num?)?.toInt(),
    );
  }

  /// Where the line is now: around its strokes still on [page], or null if
  /// none are left.
  Rect? rectOn(Map<String, StrokeItem> strokes) => strokesRect([
        for (final id in strokeIds) ?strokes[id],
      ]);

  /// Where word [i] is now, given the line's strokes.
  Rect? wordRect(int i, Map<String, StrokeItem> strokes) {
    final own = strokesRect([
      for (final id in words[i].strokeIds) ?strokes[id],
    ]);
    if (own != null) return own;
    // No strokes of its own: its share of the line, by letters.
    final line = rectOn(strokes);
    if (line == null) return null;
    final total = words.fold<int>(0, (n, w) => n + w.text.length);
    if (total == 0) return line;
    final before = words.take(i).fold<int>(0, (n, w) => n + w.text.length);
    final l = line.left + line.width * before / total;
    return Rect.fromLTRB(l, line.top, l + line.width * words[i].text.length / total, line.bottom);
  }
}

/// What the handwriting on one page says, for one language.
class PageRecognition {
  const PageRecognition({required this.language, this.lines = const []});

  final String language;

  /// In reading order.
  final List<RecognizedLine> lines;

  /// The lines of paragraph [block], joined.
  String blockText(int block) => [
        for (final l in lines)
          if (l.block == block && l.text.isNotEmpty) l.text,
      ].join(' ');

  int get blockCount => lines.isEmpty ? 0 : lines.map((l) => l.block).reduce(math.max) + 1;

  /// Every paragraph, separated by blank lines.
  String get text => [
        for (var b = 0; b < blockCount; b++)
          if (blockText(b) case final t when t.isNotEmpty) t,
      ].join('\n\n');

  Json toJson() => {
        'lang': language,
        'lines': [for (final l in lines) l.toJson()],
      };

  static PageRecognition? fromJson(Object? j) {
    if (j is! Map || j['lang'] is! String) return null;
    return PageRecognition(
      language: j['lang'] as String,
      lines: [
        for (final l in (j['lines'] as List?) ?? const []) ?RecognizedLine.fromJson(l),
      ],
    );
  }
}

/// Words in [text] (split on spaces).
List<String> wordsOf(String text) => text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

/// Lower case, letters and digits only: how words are compared.
String plainWord(String w) => w.toLowerCase().replaceAll(_notWord, '');

final _notWord = RegExp(r'[^\p{L}\p{N}]', unicode: true);

/// How many runner-up readings are looked at for a word's alternatives.
const altCandidates = 4;

/// Turns recognition [candidates] (best first) for [line] into a line with
/// words tied to strokes and alternatives where the candidates disagree.
RecognizedLine alignLine(InkLine line, List<String> candidates, {required String key}) {
  final top = candidates.isEmpty ? '' : candidates.first.trim();
  final tokens = wordsOf(top);
  final alts = <List<String>>[for (final _ in tokens) []];
  for (final c in candidates.skip(1).take(altCandidates)) {
    final other = wordsOf(c);
    if (other.length != tokens.length) continue;
    for (var i = 0; i < tokens.length; i++) {
      final w = plainWord(other[i]);
      if (w.isEmpty || w == plainWord(tokens[i])) continue;
      if (alts[i].any((a) => plainWord(a) == w)) continue;
      alts[i].add(other[i]);
    }
  }
  final strokes = _wordStrokes(line, tokens);
  return RecognizedLine(
    key: key,
    strokeIds: line.strokeIds,
    text: tokens.join(' '),
    block: line.block,
    words: [
      for (var i = 0; i < tokens.length; i++)
        RecognizedWord(tokens[i], strokeIds: strokes[i], alts: alts[i].take(2).toList()),
    ],
  );
}

/// Which strokes wrote each of [tokens]: the line's own word gaps when
/// there are as many, else each stroke goes to the word whose share of the
/// line (by letters) its middle falls in.
List<List<String>> _wordStrokes(InkLine line, List<String> tokens) {
  if (tokens.isEmpty) return const [];
  if (line.words.length == tokens.length) {
    return [
      for (final w in line.words) [for (final s in w) s.id],
    ];
  }
  final out = [for (final _ in tokens) <String>[]];
  final total = tokens.fold<int>(0, (n, t) => n + t.length);
  final b = line.bounds;
  final ends = <double>[];
  var acc = 0;
  for (final t in tokens) {
    acc += t.length;
    ends.add(b.left + b.width * acc / total);
  }
  for (final s in line.strokes) {
    final x = strokeMidX(s);
    var i = ends.indexWhere((e) => x <= e);
    if (i < 0) i = tokens.length - 1;
    out[i].add(s.id);
  }
  return out;
}
