import 'dart:ui' show Rect;

import '../board/model.dart';
import 'recognized.dart';
import 'recognizer.dart';
import 'segment.dart';

/// Reads the handwriting in [strokes] line by line. Lines [previous] has
/// already read (same strokes, same shapes, same language) are reused, so
/// only new or changed writing goes to the recognizer. With [recognizer]
/// null nothing new is read: known lines are kept and the rest left out.
/// The lines are numbered into paragraphs from [blockBase] and marked as
/// written on [holder] ([sub]).
///
/// The ink itself is never changed.
Future<PageRecognition> readInk(
  Iterable<StrokeItem> strokes, {
  required String language,
  InkRecognizer? recognizer,
  PageRecognition? previous,
  String? holder,
  int? sub,
  int blockBase = 0,
}) async {
  final lines = segmentLines(strokes);
  final known = <String, RecognizedLine>{
    if (previous != null && previous.language == language)
      for (final l in previous.lines) l.key: l,
  };
  final out = <RecognizedLine>[];
  var pre = '';
  int? block;
  for (final line in lines) {
    if (line.block != block) pre = '';
    block = line.block;
    final key = lineKey(line.strokes, language);
    final cached = known[key];
    RecognizedLine? read;
    if (cached != null) {
      read = cached;
    } else if (recognizer != null) {
      List<String> candidates;
      try {
        candidates = await recognizer.recognize(
          [for (final s in line.reading) samplesOf(s)],
          language: language,
          preContext: pre,
          area: line.bounds.size,
        );
      } on RecognitionFailed {
        // Kept as unreadable, so it isn't tried again until it changes.
        candidates = const [];
      }
      read = alignLine(line, candidates, key: key);
    }
    if (read == null) continue;
    read = read.at(block: blockBase + line.block, holder: holder, sub: sub);
    out.add(read);
    if (read.text.isNotEmpty) pre = pre.isEmpty ? read.text : '$pre ${read.text}';
  }
  return PageRecognition(language: language, lines: out);
}

/// The strokes of [page] that are read as writing, in pen order (on the
/// page itself; see [inkGroupsOf] for sticky notes and Office cards too).
/// Letters straightened into lines and circles count ([writingIn]).
Iterable<StrokeItem> handwritingOn(BoardPage page) => writingIn(page.items.whereType<StrokeItem>());

/// Handwriting written in one place: on the page, on a sticky note, on
/// one page, slide or sheet of an Office file, or on a checklist.
class InkGroup {
  const InkGroup(this.strokes, {this.holder, this.sub});

  /// In pen order, in the holder's own coordinates (so a note or card
  /// that's moved, scaled or flipped through keeps its lines' keys).
  final List<StrokeItem> strokes;

  /// The sticky note or Office card, or null for the page.
  final String? holder;

  /// Which Office page (from 1) or which note under a stack's top one
  /// (from 1); null for the page and a top note.
  final int? sub;
}

/// Every place on [page] with handwriting.
List<InkGroup> inkGroupsOf(BoardPage page) {
  List<StrokeItem> hand(Iterable<Item> items) => writingIn(items.whereType<StrokeItem>());
  final groups = <InkGroup>[InkGroup(hand(page.items))];
  for (final item in page.items) {
    switch (item) {
      case StickyItem s:
        groups.add(InkGroup(hand(s.items), holder: s.id));
        for (final (i, note) in s.under.indexed) {
          groups.add(InkGroup(hand(note.items), holder: s.id, sub: i + 1));
        }
      case OfficeItem o:
        for (final e in o.inkByPage.entries) {
          groups.add(InkGroup(hand(e.value), holder: o.id, sub: e.key));
        }
      case ChecklistItem l:
        // Its rows, where they are on the card.
        groups.add(InkGroup(hand(l.cardInk), holder: l.id));
      default:
        break;
    }
  }
  return [for (final g in groups) if (g.strokes.isNotEmpty) g];
}

/// Reads all of [page]'s handwriting, place by place (see [readInk]).
Future<PageRecognition> readPage(
  BoardPage page, {
  required String language,
  InkRecognizer? recognizer,
  PageRecognition? previous,
}) async {
  final lines = <RecognizedLine>[];
  var base = 0;
  for (final g in inkGroupsOf(page)) {
    final read = await readInk(
      g.strokes,
      language: language,
      recognizer: recognizer,
      previous: previous,
      holder: g.holder,
      sub: g.sub,
      blockBase: base,
    );
    lines.addAll(read.lines);
    if (read.lines.isNotEmpty) base = read.lines.map((l) => l.block).reduce((a, b) => a > b ? a : b) + 1;
  }
  return PageRecognition(language: language, lines: lines);
}

/// Whether [page] has any handwriting to read.
bool hasHandwriting(BoardPage page) => inkGroupsOf(page).isNotEmpty;

/// The handwriting that can be seen on [page] right now, in page space, by
/// id: the page's own, each sticky note's top note, and the page or slide
/// each Office card shows. For placing lines and words.
Map<String, StrokeItem> visibleInk(BoardPage page) => {
      for (final item in page.items)
        ...switch (item) {
          StrokeItem s => {s.id: s},
          final InkHolder h => {for (final s in h.pageInk) s.id: s},
          _ => const <String, StrokeItem>{},
        },
    };

/// Every stroke on [page] by id, wherever it's written and whether it
/// shows or not (in its holder's coordinates). For when it was written.
Map<String, StrokeItem> allInk(BoardPage page) => {
      for (final item in page.items) ...switch (item) {
        StrokeItem s => {s.id: s},
        StickyItem n => {
            for (final i in [...n.items, for (final u in n.under) ...u.items])
              if (i is StrokeItem) i.id: i,
          },
        OfficeItem o => {
            for (final strokes in o.inkByPage.values)
              for (final s in strokes) s.id: s,
          },
        ChecklistItem l => {for (final s in l.ink) s.id: s},
        _ => const <String, StrokeItem>{},
      },
    };

/// Where [line] is on [page] now: around its strokes if they show, else
/// the note or card it's written on; null if it's gone.
Rect? lineRectOn(BoardPage page, RecognizedLine line, Map<String, StrokeItem> visible) {
  final r = line.rectOn(visible);
  if (r != null) return r;
  if (line.holder == null) return null;
  for (final item in page.items) {
    if (item.id == line.holder) return item.extent;
  }
  return null;
}
