import 'dart:math' as math;
import 'dart:ui' show Color, Offset, Rect;

import '../board/ids.dart';
import '../board/model.dart';
import 'recognized.dart';
import 'segment.dart';

// Convert to text (design/screens/Convert.png): the preview's text with the
// words recognition wasn't sure of, and what converting does to the page.

/// A word of the preview recognition wasn't sure of.
class UnsureWord {
  const UnsureWord(this.token, this.options);

  /// Which word of the preview text (counting every word from 0).
  final int token;

  /// What it was read as first, then the other readings.
  final List<String> options;
}

/// The text the Convert panel starts with.
class ConvertPreview {
  const ConvertPreview(this.text, this.unsure);

  /// Paragraphs, separated by blank lines.
  final String text;
  final List<UnsureWord> unsure;
}

final _endsSentence = RegExp(r'[.!?:;…,)"”’]$');

/// The preview of [read]: each paragraph's lines joined, starting with a
/// capital, and, when it reads as a sentence (four words or more), ending
/// with a full stop (as Convert.png does: “Total momentum is conserved in a
/// closed system.”). Words with other readings are listed in [ConvertPreview.unsure].
ConvertPreview previewOf(PageRecognition read) {
  final paragraphs = <String>[];
  final unsure = <UnsureWord>[];
  var token = 0;
  for (var b = 0; b < read.blockCount; b++) {
    final words = [
      for (final line in read.lines)
        if (line.block == b) ...line.words,
    ];
    if (words.isEmpty) continue;
    final texts = [for (final w in words) w.text];
    texts[0] = capitalized(texts[0]);
    if (texts.length >= 4 && !_endsSentence.hasMatch(texts.last)) texts[texts.length - 1] = '${texts.last}.';
    for (final (i, w) in words.indexed) {
      if (w.unsure) {
        final first = i == 0;
        unsure.add(UnsureWord(token + i, [
          coreOf(texts[i]).$2,
          for (final a in w.alts) first ? capitalized(a) : a,
        ]));
      }
    }
    token += words.length;
    paragraphs.add(texts.join(' '));
  }
  return ConvertPreview(paragraphs.join('\n\n'), unsure);
}

String capitalized(String w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1);

final _lead = RegExp(r'^[^\p{L}\p{N}]*', unicode: true);
final _trail = RegExp(r'[^\p{L}\p{N}]*$', unicode: true);

/// A word split into its leading punctuation, the word, and its trailing
/// punctuation (`“total,` → `“`, `total`, `,`).
(String, String, String) coreOf(String token) {
  final lead = _lead.firstMatch(token)!.group(0)!;
  if (lead.length == token.length) return ('', token, '');
  final rest = token.substring(lead.length);
  final trail = _trail.firstMatch(rest)!.group(0)!;
  return (lead, rest.substring(0, rest.length - trail.length), trail);
}

/// Where each word of [text] is, as (start, end).
List<(int, int)> tokenRanges(String text) => [for (final m in RegExp(r'\S+').allMatches(text)) (m.start, m.end)];

/// [text] with word [token] swapped for [word], keeping its punctuation.
String replaceToken(String text, int token, String word) {
  final ranges = tokenRanges(text);
  if (token < 0 || token >= ranges.length) return text;
  final (s, e) = ranges[token];
  final (lead, _, trail) = coreOf(text.substring(s, e));
  return text.replaceRange(s, e, '$lead$word$trail');
}

/// What happens to the ink (Convert.png's "Then").
enum ConvertPlace {
  replace('Replace the ink', 'Handwriting converted to text'),
  keep('Keep ink too', 'Text added above your ink'),
  copy('Copy text only', 'Copied the text');

  const ConvertPlace(this.label, this.done);

  final String label;

  /// What the message says afterwards.
  final String done;
}

/// The page edit a conversion makes: one undo step.
class ConvertPlan {
  const ConvertPlan({this.remove = const [], this.replace = const [], this.insert = const []});

  final List<String> remove;
  final List<Item> replace;
  final List<TextItem> insert;
}

/// How big typed text is for handwriting whose lines are [lineHeight] tall.
double textSizeFor(double lineHeight) => (lineHeight * 0.7).clamp(14.0, 64.0).roundToDouble();

/// Turns [strokes] into [text] on the page. Each paragraph of [text] goes
/// where a paragraph of the ink was, when there are as many; otherwise it
/// all goes where the ink starts. The text is serif, in the ink's color,
/// about the size of the writing, wrapping at its width. [ConvertPlace.keep]
/// moves the ink down under its text; [ConvertPlace.replace] removes it.
ConvertPlan planConvert({
  required List<StrokeItem> strokes,
  required String text,
  required ConvertPlace place,
  required int z,
  required DateTime now,
}) {
  if (place == ConvertPlace.copy || strokes.isEmpty) return const ConvertPlan();
  final paragraphs = [
    for (final p in text.split(RegExp(r'\n\s*\n')))
      if (p.trim().isNotEmpty) p.trim(),
  ];
  if (paragraphs.isEmpty) return const ConvertPlan();
  final lines = segmentLines(strokes);
  final blocks = <List<InkLine>>[];
  for (final line in lines) {
    if (blocks.isEmpty || blocks.last.first.block != line.block) {
      blocks.add([line]);
    } else {
      blocks.last.add(line);
    }
  }
  // Ink that isn't handwriting, or text that doesn't split the same way:
  // one box for all of it.
  final groups = blocks.length == paragraphs.length && blocks.isNotEmpty
      ? [
          for (final (i, b) in blocks.indexed) (paragraphs[i], [for (final l in b) ...l.strokes]),
        ]
      : [(paragraphs.join('\n\n'), strokes)];

  final inserted = <TextItem>[];
  final moved = <Item>[];
  var shift = 0.0;
  for (final (i, (para, ink)) in groups.indexed) {
    final rect = strokesRect(ink)!;
    final heights = [for (final l in segmentLines(ink)) l.bounds.height]..sort();
    final lineHeight = heights.isEmpty ? rect.height : heights[heights.length ~/ 2];
    final item = TextItem(
      id: newId('it', now: now),
      x: rect.left,
      y: rect.top + shift,
      z: z + i,
      createdAt: now,
      wrap: math.max(rect.width * 1.15, 160),
      text: para,
      font: 'serif',
      size: textSizeFor(lineHeight),
      color: mainInkColor(ink),
    );
    inserted.add(item);
    if (place == ConvertPlace.keep) {
      // The ink moves down under its text, and everything after it with it.
      shift += item.h + 12;
      final d = Offset(0, shift);
      for (final s in ink) {
        moved.add(s.copyWith(pagePoints: [for (final p in s.pageInk) InkPoint(p.x + d.dx, p.y + d.dy, p.pressure, p.t)]));
      }
    }
  }
  return ConvertPlan(
    remove: place == ConvertPlace.replace ? [for (final s in strokes) s.id] : const [],
    replace: moved,
    insert: inserted,
  );
}

/// Turns the handwriting on sticky note [note] (its top note) into [text]
/// typed on the note, after any text typed there already. In serif, in the
/// ink's main color, about the writing's size (what's typed there already
/// keeps its own). [ConvertPlace.replace] takes the ink off the note;
/// [ConvertPlace.keep] moves it down under the text, making the note
/// taller if it has to. Ink that isn't handwriting stays as it is.
StickyItem convertOnSticky(StickyItem note, String text, ConvertPlace place, {required DateTime now}) {
  final ink = writingIn(note.items.whereType<StrokeItem>());
  final words = text.trim();
  if (place == ConvertPlace.copy || ink.isEmpty || words.isEmpty) return note;
  final typed = note.items.whereType<TextItem>().firstOrNull;
  final all = typed == null || typed.text.trim().isEmpty ? words : '${typed.text.trimRight()}\n$words';
  final heights = [for (final l in segmentLines(ink)) l.bounds.height]..sort();
  final size = textSizeFor(heights.isEmpty ? 30 : heights[heights.length ~/ 2]).clamp(14.0, 32.0);
  final ids = {for (final s in ink) s.id};
  final written = (place == ConvertPlace.replace ? note.withoutInk(ids) : note)
      .withText(all, color: mainInkColor(ink), at: now, font: typed == null ? 'serif' : null, size: typed == null ? size : null);
  if (place == ConvertPlace.replace) return written;

  // Keep: the ink goes down under the text.
  final t = written.items.whereType<TextItem>().first;
  final area = strokesRect(ink)!;
  final shift = math.max(0.0, t.y + t.h + 8 - area.top);
  if (shift == 0) return written;
  final moved = written.copyWith(items: [
    for (final i in written.items)
      if (i is StrokeItem && ids.contains(i.id))
        i.copyWith(pagePoints: [for (final p in i.pageInk) InkPoint(p.x, p.y + shift, p.pressure, p.t)])
      else
        i,
  ]);
  final bottom = area.bottom + shift + StickyItem.padding;
  return bottom <= moved.h ? moved : moved.withBox(x: moved.x, y: moved.y, w: moved.w, h: bottom);
}

/// The color most of [ink] is written in.
Color mainInkColor(List<StrokeItem> ink) {
  final counts = <int, int>{};
  for (final s in ink) {
    counts.update(s.color.toARGB32(), (n) => n + s.points.length, ifAbsent: () => s.points.length);
  }
  final top = counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  return Color(top);
}

/// The page-space box around a conversion's ink.
Rect? convertArea(List<StrokeItem> strokes) => strokesRect(strokes);
