import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:flutter/painting.dart' show TextSelection;

import '../board/ids.dart';
import '../board/model.dart';
import '../recognition/convert.dart' show coreOf, mainInkColor;
import '../recognition/recognized.dart';
import '../recognition/segment.dart' show strokeMidX, strokesRect;
import 'my_handwriting.dart';
import 'words.dart';

// Spell check on a page (design/screens/Spell.png): which handwritten and
// typed words aren't in the dictionary, where they are, and the edits that
// fix them.

/// What spell check accepts: the word list, plus the words added to "my
/// dictionary".
class Speller {
  Speller(this.words, {Iterable<String> mine = const []}) : _mine = {for (final w in mine) w.toLowerCase()};

  final WordList words;
  final Set<String> _mine;

  /// Whether [word] (without punctuation around it) is spelled right, or
  /// isn't something to check: numbers, single letters, short all-capital
  /// abbreviations, addresses.
  bool accepts(String word) {
    final w = word.replaceAll('’', "'");
    if (!_checkable.hasMatch(w) || w.length < 2) return true;
    final letters = w.replaceAll(RegExp("['-]"), '');
    if (letters.length <= 5 && letters == letters.toUpperCase()) return true;
    if (_known(w)) return true;
    final lower = w.toLowerCase();
    if (lower.endsWith("'s") && _known(w.substring(0, w.length - 2))) return true;
    if (lower.endsWith("s'") && _known(w.substring(0, w.length - 1))) return true;
    if (w.contains('-')) return w.split('-').every((part) => part.isEmpty || accepts(part));
    return false;
  }

  bool _known(String w) => words.contains(w) || _mine.contains(w.toLowerCase());

  static final _checkable = RegExp(r"^[\p{L}\p{M}'-]+$", unicode: true);

  /// Up to 3 corrections for [word], best first. [hints] are other ways
  /// handwriting recognition read it.
  List<String> suggest(String word, {Iterable<String> hints = const []}) =>
      words.suggest(word.replaceAll('’', "'"), hints: hints);
}

enum SpellKind {
  handwriting('Handwriting'),
  typed('Typed text');

  const SpellKind(this.label);

  final String label;
}

/// A word that isn't in the dictionary.
class SpellIssue {
  const SpellIssue({
    required this.id,
    required this.kind,
    required this.word,
    required this.quad,
    this.strokeIds = const [],
    this.hints = const [],
    this.lead = '',
    this.trail = '',
    this.lineRect,
    this.laterStrokeIds = const [],
    this.itemId,
    this.start = 0,
    this.end = 0,
  });

  /// Stays the same while the word does.
  final String id;
  final SpellKind kind;

  /// As written, without punctuation around it.
  final String word;

  /// Where it is on the page: top left, top right, bottom right, bottom
  /// left (turned along with a turned text box or sticky note).
  final List<Offset> quad;

  Rect get rect => Rect.fromLTRB(
        quad.map((p) => p.dx).reduce(math.min),
        quad.map((p) => p.dy).reduce(math.min),
        quad.map((p) => p.dx).reduce(math.max),
        quad.map((p) => p.dy).reduce(math.max),
      );

  // Handwriting.

  /// The strokes that wrote it, punctuation included.
  final List<String> strokeIds;

  /// Other readings recognition had for it.
  final List<String> hints;

  /// Punctuation written with it (`colision:` has trail `:`).
  final String lead, trail;

  /// Its line of writing on the page.
  final Rect? lineRect;

  /// The strokes after it on its line, which move along when the fixed
  /// word is wider or narrower.
  final List<String> laterStrokeIds;

  // Typed text.

  /// The text box, or the sticky note it's typed on.
  final String? itemId;

  /// Where the word is in the text.
  final int start, end;
}

final _typedWord = RegExp(r"[\p{L}\p{M}\p{N}'’-]+", unicode: true);
final _edgeMarks = RegExp(r"^['’-]+|['’-]+$");

/// The misspelled words on [page], in reading order: handwriting on the
/// page (as [read] recognized it), and text typed in text boxes and on
/// sticky notes. Words in the page's ignore list are left out.
List<SpellIssue> findIssues(BoardPage page, PageRecognition? read, Speller speller) {
  final ignored = {for (final w in page.spellIgnore) w.toLowerCase()};
  bool flagged(String word) => word.isNotEmpty && !ignored.contains(word.toLowerCase()) && !speller.accepts(word);
  final out = <SpellIssue>[];

  // Handwriting on the page itself.
  final ink = {for (final s in page.items.whereType<StrokeItem>()) s.id: s};
  for (final line in read?.lines ?? const <RecognizedLine>[]) {
    if (line.holder != null) continue;
    final lineRect = line.rectOn(ink);
    if (lineRect == null) continue;
    for (final (i, w) in line.words.indexed) {
      final (lead, core, trail) = coreOf(w.text);
      if (!flagged(core)) continue;
      final own = [for (final id in w.strokeIds) if (ink.containsKey(id)) id];
      // Its own strokes are gone (fixed or erased since it was read): it's not there any more.
      if (w.strokeIds.isNotEmpty && own.isEmpty) continue;
      final rect = own.isNotEmpty ? strokesRect([for (final id in own) ink[id]!]) : line.wordRect(i, ink);
      if (rect == null) continue;
      final mine = own.isNotEmpty
          ? own
          : [
              for (final id in line.strokeIds)
                if (ink[id] case final s? when rect.left <= strokeMidX(s) && strokeMidX(s) <= rect.right) id,
            ];
      out.add(SpellIssue(
        id: 'ink:${line.key}:$i',
        kind: SpellKind.handwriting,
        word: core,
        quad: _quad(rect),
        strokeIds: mine,
        laterStrokeIds: [
          for (final id in line.strokeIds)
            if (ink[id] case final s? when !mine.contains(id) && strokeMidX(s) > rect.right) id,
        ],
        hints: [for (final a in w.alts) coreOf(a).$2],
        lead: lead,
        trail: trail,
        lineRect: lineRect,
      ));
    }
  }

  // Typed text.
  void typed(String itemId, TextItem text, Offset Function(Offset) toPage) {
    final words = [
      for (final m in _typedWord.allMatches(text.text)) ?_trimmed(m),
    ];
    if (!words.any((r) => flagged(text.text.substring(r.$1, r.$2)))) return;
    final painter = layoutText(text.text, text.font, text.size, text.wrap);
    for (final (start, end) in words) {
      final word = text.text.substring(start, end);
      if (!flagged(word)) continue;
      final boxes = painter.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: end));
      if (boxes.isEmpty) continue;
      // A word broken across lines is marked on its first line.
      final first = boxes.first;
      final local = Rect.fromLTRB(
        first.left,
        first.top,
        boxes.where((b) => (b.top - first.top).abs() < 1).map((b) => b.right).reduce(math.max),
        first.bottom,
      );
      out.add(SpellIssue(
        id: 'text:$itemId:$start',
        kind: SpellKind.typed,
        word: word,
        quad: [
          for (final c in [local.topLeft, local.topRight, local.bottomRight, local.bottomLeft]) toPage(text.toPage(c)),
        ],
        itemId: itemId,
        start: start,
        end: end,
      ));
    }
    painter.dispose();
  }

  for (final item in page.items) {
    switch (item) {
      case TextItem t:
        typed(t.id, t, (p) => p);
      case StickyItem s:
        if (s.items.whereType<TextItem>().firstOrNull case final t?) typed(s.id, t, s.toPage);
      default:
        break;
    }
  }
  return inReadingOrder(out);
}

(int, int)? _trimmed(RegExpMatch m) {
  final text = m.group(0)!;
  final lead = _edgeMarks.firstMatch(text)?.group(0)?.length ?? 0;
  if (lead == text.length) return null;
  final trail = RegExp(r"['’-]+$").firstMatch(text)?.group(0)?.length ?? 0;
  final word = text.substring(lead, text.length - trail);
  // Possessives stay with their word ("Maya’s"); numbers aren't checked.
  if (word.contains(RegExp(r'\d'))) return null;
  return (m.start + lead, m.end - trail);
}

List<Offset> _quad(Rect r) => [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];

/// [issues] in reading order: line by line down the page, then left to
/// right along each line.
List<SpellIssue> inReadingOrder(List<SpellIssue> issues) {
  final byTop = [...issues]..sort((a, b) => a.rect.center.dy.compareTo(b.rect.center.dy));
  final rows = <List<SpellIssue>>[];
  for (final issue in byTop) {
    final row = rows.lastOrNull;
    if (row != null) {
      final first = row.first.rect;
      final r = issue.rect;
      // Same line: its middle is within the line's first word, or theirs within it.
      if ((r.center.dy >= first.top && r.center.dy <= first.bottom) ||
          (first.center.dy >= r.top && first.center.dy <= r.bottom)) {
        row.add(issue);
        continue;
      }
    }
    rows.add([issue]);
  }
  return [
    for (final row in rows) ...row..sort((a, b) => a.rect.left.compareTo(b.rect.left)),
  ];
}

/// A page edit spell check makes: one undo step.
class SpellEdit {
  const SpellEdit({this.remove = const [], this.replace = const [], this.insert = const []});

  final List<String> remove;
  final List<Item> replace;
  final List<Item> insert;

  bool get isEmpty => remove.isEmpty && replace.isEmpty && insert.isEmpty;
}

/// The edit that puts each word of [fixes] in place of its issue on
/// [page] (in reading order). Typed words are changed in their text.
///
/// A handwritten word is written in the user's letters when [hand] (their
/// sample) is given and has every letter: sized, placed and spaced like the
/// word it replaces, and the rest of its line moves along by the change in
/// width. Otherwise it's typed in the handwriting font, in the ink's color,
/// about the size of the writing, where the word was.
SpellEdit planFixes(
  BoardPage page,
  List<(SpellIssue, String)> fixes, {
  required int z,
  required DateTime now,
  MyHandwriting? hand,
}) {
  final items = {for (final i in page.items) i.id: i};
  final remove = <String>{};
  final replace = <String, Item>{};
  final insert = <Item>[];
  final byItem = <String, List<(SpellIssue, String)>>{};
  // How far strokes have moved along their line for earlier fixes.
  final shift = <String, double>{};
  StrokeItem moved(StrokeItem s) {
    final d = shift[s.id] ?? 0;
    return d == 0 ? s : s.copyWith(pagePoints: [for (final p in s.pageInk) InkPoint(p.x + d, p.y, p.pressure, p.t)]);
  }

  for (final fix in fixes) {
    final (issue, word) = fix;
    if (issue.kind == SpellKind.typed) {
      if (issue.itemId != null) (byItem[issue.itemId!] ??= []).add(fix);
      continue;
    }
    final strokes = [
      for (final id in issue.strokeIds)
        if (items[id] case final StrokeItem s when !remove.contains(id)) moved(s),
    ];
    if (strokes.isEmpty) continue;
    remove.addAll(strokes.map((s) => s.id));
    final z0 = z + insert.length;
    final written = hand == null
        ? null
        : writeInHand(
            hand,
            text: '${issue.lead}$word${issue.trail}',
            wrote: '${issue.lead}${issue.word}${issue.trail}',
            original: strokes,
            z: z0,
            now: now,
          );
    if (written != null) {
      insert.addAll(written.strokes);
      if (written.widthChange.abs() >= 0.5) {
        for (final id in issue.laterStrokeIds) {
          shift[id] = (shift[id] ?? 0) + written.widthChange;
        }
      }
      continue;
    }
    final at = strokesRect(strokes)!;
    final line = issue.lineRect ?? at;
    final text = TextItem(
      id: newId('it', now: now),
      x: at.left,
      y: line.top,
      z: z0,
      createdAt: now,
      wrap: 2000,
      text: '${issue.lead}$word${issue.trail}',
      font: 'hand',
      size: inkTextSize(line.height),
      color: mainInkColor(strokes),
      autoWidth: true,
    );
    insert.add(text.copyWith(y: line.center.dy - text.h / 2));
  }
  for (final MapEntry(key: id, value: list) in byItem.entries) {
    final item = items[id];
    // Later words first, so earlier positions still hold.
    list.sort((a, b) => b.$1.start.compareTo(a.$1.start));
    String fixed(String text) {
      for (final (issue, word) in list) {
        if (issue.end <= text.length && text.substring(issue.start, issue.end) == issue.word) {
          text = text.replaceRange(issue.start, issue.end, word);
        }
      }
      return text;
    }

    switch (item) {
      case TextItem t:
        replace[id] = t.copyWith(text: fixed(t.text));
      case StickyItem s:
        replace[id] = s.copyWith(items: [
          for (final i in s.items) i is TextItem ? i.copyWith(text: fixed(i.text)) : i,
        ]);
      default:
        break;
    }
  }
  for (final MapEntry(key: id, value: d) in shift.entries) {
    if (d == 0 || remove.contains(id)) continue;
    if (items[id] case final StrokeItem s) replace[id] = moved(s);
  }
  return SpellEdit(remove: remove.toList(), replace: replace.values.toList(), insert: insert);
}

/// How big the handwriting font is for a line of writing [lineHeight] tall.
double inkTextSize(double lineHeight) => (lineHeight * 0.85).clamp(14.0, 96.0).roundToDouble();
