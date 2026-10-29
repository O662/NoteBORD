import 'dart:convert';
import 'dart:ui' show Rect;

import '../board/codec.dart';
import '../board/model.dart';
import '../math/linear.dart' show latexToLinear;
import '../recognition/recognized.dart';
import 'remember.dart';

// What the Remember and Flashcards screens show, gathered from every page
// into the index (index.sqlite's `study_items`): each thing to remember and
// each flashcard, with a copy of the items they show. Like the search rows,
// these are a cache: the pages are the source of truth.

enum StudyKind { remember, card }

class StudyRow {
  const StudyRow({
    required this.notebookId,
    required this.pageId,
    required this.kind,
    required this.ref,
    required this.rect,
    required this.at,
    required this.data,
  });

  final String notebookId;
  final String pageId;
  final StudyKind kind;

  /// The remembered thing's id, or the flashcard's.
  final String ref;

  /// Where it is on the page.
  final Rect rect;

  /// When it was marked or made.
  final DateTime at;
  final Json data;

  String get dataJson => jsonEncode(data);
}

/// What [items] say: recognized handwriting (from [read]) and typed text,
/// in page order.
String textOf(List<Item> items, PageRecognition? read) {
  final parts = <String>[];
  final strokes = {for (final i in items) if (i is StrokeItem) i.id};
  if (read != null && strokes.isNotEmpty) {
    for (final line in read.lines) {
      if (line.holder != null) continue;
      final words = [
        for (final w in line.words)
          if (w.strokeIds.any(strokes.contains)) w.text,
      ];
      // A line whose words weren't tied to strokes: all of it, if it's ours.
      if (words.isEmpty && line.words.every((w) => w.strokeIds.isEmpty) && line.strokeIds.any(strokes.contains)) {
        words.add(line.text);
      }
      if (words.isNotEmpty) parts.add(words.join(' '));
    }
  }
  for (final i in items) {
    switch (i) {
      case TextItem t when t.text.trim().isNotEmpty:
        parts.add(t.text.trim());
      case StickyItem s:
        for (final n in s.items) {
          if (n is TextItem && n.text.trim().isNotEmpty) parts.add(n.text.trim());
        }
      case MathItem m when m.latex.trim().isNotEmpty:
        parts.add(latexToLinear(m.latex));
      default:
        break;
    }
  }
  return parts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

Json _side(CardSide side, Map<String, Item> byId, PageRecognition? read) {
  final items = [for (final id in side.ids) ?byId[id]];
  return {
    'items': [for (final i in items) i.toJson()],
    if (side.text.isNotEmpty) 'text': side.text,
    'said': textOf(items, read),
    'missing': side.ids.length - items.length,
  };
}

Rect? _around(Iterable<Item> items) {
  Rect? r;
  for (final i in items) {
    r = r == null ? i.extent : r.expandToInclude(i.extent);
  }
  return r;
}

/// The things to remember and flashcards on [page], with what they show.
List<StudyRow> studyRowsFor(String notebookId, BoardPage page, PageRecognition? read) {
  final rows = <StudyRow>[];
  final byId = {for (final i in page.items) i.id: i};
  for (final g in rememberGroups(page.items)) {
    final m = g.mark;
    rows.add(StudyRow(
      notebookId: notebookId,
      pageId: page.id,
      kind: StudyKind.remember,
      ref: m.id,
      rect: g.area,
      at: m.at ?? g.items.first.createdAt,
      data: {
        'items': [for (final i in g.items) i.toJson()],
        ...m.toJson(),
        'said': textOf(g.items, read),
      },
    ));
  }
  for (final card in page.items.whereType<FlashcardItem>()) {
    final front = [for (final id in card.front.ids) ?byId[id]];
    final back = [for (final id in card.back.ids) ?byId[id]];
    rows.add(StudyRow(
      notebookId: notebookId,
      pageId: page.id,
      kind: StudyKind.card,
      ref: card.id,
      rect: _around(front) ?? _around(back) ?? Rect.fromLTWH(card.x, card.y, 1, 1),
      at: card.createdAt,
      data: {
        'deck': card.deck,
        'deckName': card.deckName,
        'reverse': card.reverse,
        'front': _side(card.front, byId, read),
        'back': _side(card.back, byId, read),
      },
    ));
  }
  return rows;
}

/// One side of a flashcard as the index has it: the items it shows (as they
/// were when the page was last read), typed text, and what they say.
class SideView {
  SideView.fromJson(Object? json)
      : items = [
          if (json is Map)
            for (final i in (json['items'] as List? ?? const []))
              if (i is Map) decodeItem(i.cast<String, dynamic>()),
        ],
        text = json is Map ? json['text'] as String? ?? '' : '',
        said = json is Map ? json['said'] as String? ?? '' : '',
        missing = json is Map ? (json['missing'] as num?)?.toInt() ?? 0 : 0;

  final List<Item> items;
  final String text;
  final String said;

  /// Items it was made from that are gone from the page.
  final int missing;

  bool get isEmpty => items.isEmpty && text.trim().isEmpty;

  /// For screen readers and search: what it says.
  String get label => [said, text].where((s) => s.isNotEmpty).join(' · ');
}

/// A flashcard, for studying.
class StudyCard {
  StudyCard.fromRow(StudyRow row)
      : notebookId = row.notebookId,
        pageId = row.pageId,
        id = row.ref,
        rect = row.rect,
        at = row.at,
        deck = row.data['deck'] as String? ?? '',
        deckName = row.data['deckName'] as String? ?? '',
        reverse = row.data['reverse'] == true,
        front = SideView.fromJson(row.data['front']),
        back = SideView.fromJson(row.data['back']);

  final String notebookId;
  final String pageId;
  final String id;
  final Rect rect;
  final DateTime at;
  final String deck;
  final String deckName;
  final bool reverse;
  final SideView front;
  final SideView back;
}

/// A thing to remember, for the Remember screen.
class RememberedThing {
  RememberedThing.fromRow(StudyRow row)
      : notebookId = row.notebookId,
        pageId = row.pageId,
        id = row.ref,
        rect = row.rect,
        at = row.at,
        items = [
          for (final i in (row.data['items'] as List? ?? const []))
            if (i is Map) decodeItem(i.cast<String, dynamic>()),
        ],
        why = row.data['why'] as String? ?? '',
        remind = RemindKind.values.where((k) => k.name == row.data['remind']).firstOrNull ?? RemindKind.none,
        remindAt = DateTime.tryParse(row.data['remindAt'] as String? ?? '')?.toUtc(),
        flashcard = row.data['flashcard'] as String?,
        drawn = row.data['drawn'] == true,
        event = EventLink.fromJson(row.data['event']),
        said = row.data['said'] as String? ?? '';

  final String notebookId;
  final String pageId;
  final String id;
  final Rect rect;
  final DateTime at;
  final List<Item> items;
  final String why;
  final RemindKind remind;
  final DateTime? remindAt;
  final String? flashcard;
  final bool drawn;

  /// The event its reminder comes before.
  final EventLink? event;

  /// What it says (recognized handwriting and typed text), if known.
  final String said;

  bool get hasReminder => remindAt != null && remind != RemindKind.none;

  /// Only typed text (Remember.png's typed cards): no ink, pictures, or
  /// text in the handwriting font (that's drawn as it looks on the page).
  bool get typedOnly => items.isNotEmpty && items.every((i) => i is TextItem && i.font != 'hand');
}
