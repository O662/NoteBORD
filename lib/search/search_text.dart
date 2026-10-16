import 'dart:convert';
import 'dart:ui' show Rect;

import '../board/model.dart';

/// What a match was found in (the Search screen's chips).
enum SearchKind {
  ink('Handwriting'),
  typed('Typed text'),
  pdf('Text inside PDF'),
  office('Text inside file');

  const SearchKind(this.label);

  final String label;
}

SearchKind searchKindFromName(String? name) =>
    SearchKind.values.firstWhere((k) => k.name == name, orElse: () => SearchKind.typed);

/// One searchable piece of a page: a line of handwriting, a text box, the
/// text of an imported PDF page or of an Office file.
class SearchRow {
  const SearchRow({
    required this.notebookId,
    required this.pageId,
    required this.kind,
    required this.ref,
    required this.text,
    this.context = '',
    required this.rect,
    required this.at,
    this.data = const {},
    this.private = false,
  });

  final String notebookId;
  final String pageId;
  final SearchKind kind;

  /// The line's key, or the item's id.
  final String ref;
  final String text;

  /// For handwriting, the whole paragraph the line is in.
  final String context;

  /// Where it is on the page.
  final Rect rect;

  /// When it was written (the newest stroke) or added.
  final DateTime at;

  /// For handwriting `strokes` (the line's ids) and `words` (each word's
  /// text `t` and stroke ids `s`); for items `item` and, for files, `name`.
  final Json data;

  /// From a page with a password that's unlocked right now: kept in memory
  /// only, never in the index.
  final bool private;

  /// The same row, marked as from an unlocked page with a password.
  SearchRow unlocked() => SearchRow(
        notebookId: notebookId,
        pageId: pageId,
        kind: kind,
        ref: ref,
        text: text,
        context: context,
        rect: rect,
        at: at,
        data: data,
        private: true,
      );

  String get dataJson => jsonEncode(data);

  /// The ids of the line's strokes (handwriting).
  List<String> get strokeIds => [...?(data['strokes'] as List?)?.whereType<String>()];

  /// Each word and its strokes (handwriting).
  List<(String, List<String>)> get words => [
        for (final w in (data['words'] as List?) ?? const [])
          if (w is Map && w['t'] is String) (w['t'] as String, [...?(w['s'] as List?)?.whereType<String>()]),
      ];

  String? get itemId => data['item'] as String?;

  /// For handwriting on a sticky note or an Office card: its id.
  String? get holder => data['holder'] as String?;

  /// Which page, slide or sheet of an Office card it's on (from 1), or
  /// which note of a sticky stack under the top one.
  int? get sub => (data['sub'] as num?)?.toInt();

  /// What it's written on, for its label: `sticky`, `docx`, `pptx`, `xlsx`.
  String? get on => data['on'] as String?;

  /// "Handwriting on slide 3", "Typed text"…
  String get label => switch (on) {
        'sticky' => sub == null ? '${kind.label} on a sticky note' : '${kind.label} on a note in a stack',
        'pptx' => '${kind.label} on slide $sub',
        'docx' => '${kind.label} on page $sub of a Word file',
        'xlsx' => '${kind.label} on sheet $sub',
        _ => kind.label,
      };

  /// The file's name, for text inside a PDF or Office file.
  String? get fileName => data['name'] as String?;
}

/// Lower case with punctuation as spaces, padded with a space each side,
/// so a search term can be matched at the start of any word.
String searchNorm(String text) {
  final plain = text.toLowerCase().replaceAll(_punct, ' ').replaceAll(_spaces, ' ').trim();
  return ' $plain ';
}

final _punct = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
final _spaces = RegExp(r'\s+');

/// The words of a search, normalized like [searchNorm].
List<String> searchTerms(String query) => searchNorm(query).trim().split(' ').where((t) => t.isNotEmpty).toList();

/// Whether [text] has every term at the start of one of its words.
bool matchesTerms(String text, List<String> terms) {
  if (terms.isEmpty) return false;
  final norm = searchNorm(text);
  return terms.every((t) => norm.contains(' $t'));
}

/// Where [terms] start words in [text], as (start, end) ranges of [text]
/// to highlight: each match runs to the end of the term.
List<(int, int)> matchRanges(String text, List<String> terms) {
  if (terms.isEmpty) return const [];
  final lower = text.toLowerCase();
  final out = <(int, int)>[];
  for (final t in terms) {
    var from = 0;
    while (true) {
      final i = lower.indexOf(t, from);
      if (i < 0) break;
      final startsWord = i == 0 || _punct.hasMatch(lower[i - 1]) || lower[i - 1] == ' ';
      if (startsWord) out.add((i, i + t.length));
      from = i + 1;
    }
  }
  out.sort((a, b) => a.$1.compareTo(b.$1));
  // Merge overlaps.
  final merged = <(int, int)>[];
  for (final r in out) {
    if (merged.isNotEmpty && r.$1 <= merged.last.$2) {
      final last = merged.removeLast();
      merged.add((last.$1, r.$2 > last.$2 ? r.$2 : last.$2));
    } else {
      merged.add(r);
    }
  }
  return merged;
}
