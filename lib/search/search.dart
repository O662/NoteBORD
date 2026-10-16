import 'dart:ui' show Rect;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/model.dart';
import '../board/store.dart';
import '../library/index_db.dart';
import '../library/library.dart';
import '../state/settings.dart';
import 'search_text.dart';

/// One match: where it is and what to highlight.
class SearchHit {
  const SearchHit({
    required this.row,
    required this.notebook,
    required this.pageIndex,
    this.matchedWords = const [],
  });

  final SearchRow row;
  final NotebookEntry notebook;

  /// The page's place in the notebook, from 0.
  final int pageIndex;

  /// For handwriting: which words of the line matched.
  final List<int> matchedWords;

  /// The strokes of the words that matched (handwriting).
  List<String> get matchedStrokes => [
        for (final i in matchedWords)
          if (i < row.words.length) ...row.words[i].$2,
      ];
}

/// The Search screen's chips: everything, or one kind of match.
enum SearchFilter {
  all('All'),
  ink('Handwriting'),
  typed('Typed text'),
  files('Inside PDFs');

  const SearchFilter(this.label);

  final String label;

  bool takes(SearchKind k) => switch (this) {
        SearchFilter.all => true,
        SearchFilter.ink => k == SearchKind.ink,
        SearchFilter.typed => k == SearchKind.typed,
        SearchFilter.files => k == SearchKind.pdf || k == SearchKind.office,
      };
}

/// "Any date" and the windows it narrows to.
enum SearchDate {
  any('Any date', null),
  today('Today', Duration(days: 1)),
  week('Past 7 days', Duration(days: 7)),
  month('Past 30 days', Duration(days: 30)),
  year('Past year', Duration(days: 365));

  const SearchDate(this.label, this.within);

  final String label;
  final Duration? within;

  bool takes(DateTime at, DateTime now) {
    final w = within;
    if (w == null) return true;
    if (this == SearchDate.today) {
      final local = now.toLocal(), t = at.toLocal();
      return t.year == local.year && t.month == local.month && t.day == local.day;
    }
    return now.difference(at) <= w;
  }
}

/// Which words of a handwriting line [row] start with one of [terms].
List<int> matchedWordsOf(SearchRow row, List<String> terms) => [
      for (final (i, (word, _)) in row.words.indexed)
        if (terms.any((t) => searchNorm(word).contains(' $t'))) i,
    ];

/// Runs a search across every notebook: the matches in notebooks that
/// aren't in the Trash or locked, on pages that still exist, newest
/// notebook first, then by page and down the page.
Future<List<SearchHit>> runSearch(
  String query, {
  required IndexDb db,
  required LibraryState library,
  required BoardStore store,
  List<SearchRow> unlocked = const [],
}) async {
  final terms = searchTerms(query);
  if (terms.isEmpty) return const [];
  final rows = [
    ...await db.searchText(terms),
    // Unlocked pages with a password, from memory.
    for (final r in unlocked)
      if (matchesTerms(r.text, terms)) r,
  ];
  final pageOrder = <String, List<String>?>{};
  final hits = <SearchHit>[];
  for (final row in rows) {
    final nb = library.byId(row.notebookId);
    if (nb == null || nb.trashed || (nb.locked && !row.private)) continue;
    final order = pageOrder.containsKey(nb.id)
        ? pageOrder[nb.id]
        : pageOrder[nb.id] = (await store.loadNotebookMeta(nb.id))?.pageIds;
    final index = order?.indexOf(row.pageId) ?? -1;
    if (index < 0) continue;
    hits.add(SearchHit(
      row: row,
      notebook: nb,
      pageIndex: index,
      matchedWords: row.kind == SearchKind.ink ? matchedWordsOf(row, terms) : const [],
    ));
  }
  hits.sort((a, b) {
    if (a.notebook.id != b.notebook.id) return b.notebook.updatedAt.compareTo(a.notebook.updatedAt);
    if (a.pageIndex != b.pageIndex) return a.pageIndex.compareTo(b.pageIndex);
    final dy = a.row.rect.top.compareTo(b.row.rect.top);
    return dy != 0 ? dy : a.row.rect.left.compareTo(b.row.rect.left);
  });
  return hits;
}

/// The hits a folder and date leave (before the kind chips).
List<SearchHit> narrow(List<SearchHit> hits, {List<String>? folder, SearchDate date = SearchDate.any, required DateTime now}) => [
      for (final h in hits)
        if ((folder == null || isInside(h.notebook.folder, folder)) && date.takes(h.row.at, now)) h,
    ];

/// The part of the page to point at for [hit]: the words that matched, or
/// the whole line or item.
Rect spotOf(SearchHit hit, Map<String, StrokeItem> strokes) {
  if (hit.row.kind != SearchKind.ink) return hit.row.rect;
  Rect? r;
  for (final id in hit.matchedStrokes) {
    final s = strokes[id];
    if (s == null) continue;
    r = r == null ? s.bounds : r.expandToInclude(s.bounds);
  }
  return r ?? hit.row.rect;
}

/// A notebook's pages, read from storage, for drawing results.
final searchPagesProvider = FutureProvider.autoDispose.family<Map<String, BoardPage>, String>((ref, id) async {
  final loaded = await ref.read(boardStoreProvider).loadNotebook(id);
  return {
    for (final p in loaded?.pages ?? const <BoardPage>[])
      if (!p.locked) p.id: p,
  };
});
