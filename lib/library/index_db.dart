import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../board/model.dart';
import '../search/search_text.dart';
import '../study/study_rows.dart';
import 'library.dart';
import 'thumbs.dart';

/// The library index: one row per notebook, so the Start page and Library
/// can list, sort and draw covers without opening every `.board` package.
///
/// The `.board` files are the source of truth. The index is a cache rebuilt
/// from them (see [LibraryLoader]); only `last_page` and `opened_at`, which
/// are this device's reading position, live here alone.
///
/// `search_text` holds what can be searched on each page (recognized
/// handwriting, typed text, text inside files), and `search_state` which
/// version of each notebook it was taken from. Both are caches too: the
/// handwriting comes from each package's `index/recognition.json`.
///
/// `study_items` holds each thing to remember and each flashcard on a page,
/// with copies of what they show, for the Remember and Flashcards screens
/// (a cache as well).
///
/// Queries are plain SQL, because drift's code generator can't run on this
/// Flutter SDK yet; move to generated tables when it can.
class IndexDb extends GeneratedDatabase {
  IndexDb(super.executor);

  /// The app's index file, queried on a background isolate.
  factory IndexDb.file(File file) => IndexDb(NativeDatabase.createInBackground(file));

  /// For tests.
  factory IndexDb.memory() => IndexDb(NativeDatabase.memory());

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await _createNotebooks();
          await _createSearch();
          await _createStudy();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) await _createSearch();
          if (from < 3) await _createStudy();
        },
      );

  Future<void> _createNotebooks() => customStatement('''
          CREATE TABLE notebooks (
            id TEXT NOT NULL PRIMARY KEY,
            title TEXT NOT NULL,
            folder TEXT NOT NULL,
            cover TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            page_count INTEGER NOT NULL,
            locked INTEGER NOT NULL,
            locked_pages INTEGER NOT NULL,
            pinned INTEGER NOT NULL,
            trashed_at INTEGER,
            last_page INTEGER NOT NULL DEFAULT 0,
            opened_at INTEGER,
            thumb TEXT
          )''');

  Future<void> _createSearch() async {
    await customStatement('''
      CREATE TABLE search_text (
        notebook_id TEXT NOT NULL,
        page_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        ref TEXT NOT NULL,
        text TEXT NOT NULL,
        norm TEXT NOT NULL,
        context TEXT NOT NULL,
        x REAL NOT NULL,
        y REAL NOT NULL,
        w REAL NOT NULL,
        h REAL NOT NULL,
        at INTEGER NOT NULL,
        data TEXT NOT NULL
      )''');
    await customStatement('CREATE INDEX search_text_page ON search_text (notebook_id, page_id)');
    await customStatement('''
      CREATE TABLE search_state (
        notebook_id TEXT NOT NULL PRIMARY KEY,
        updated_at INTEGER NOT NULL,
        lang TEXT NOT NULL,
        version INTEGER NOT NULL
      )''');
  }

  Future<void> _createStudy() async {
    await customStatement('''
      CREATE TABLE study_items (
        notebook_id TEXT NOT NULL,
        page_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        ref TEXT NOT NULL,
        x REAL NOT NULL,
        y REAL NOT NULL,
        w REAL NOT NULL,
        h REAL NOT NULL,
        at INTEGER NOT NULL,
        data TEXT NOT NULL
      )''');
    await customStatement('CREATE INDEX study_items_page ON study_items (notebook_id, page_id)');
  }

  Future<List<NotebookEntry>> all() async {
    final rows = await customSelect('SELECT * FROM notebooks').get();
    return [for (final r in rows) _entry(r)];
  }

  Future<void> upsert(NotebookEntry e) => customStatement(
        'INSERT OR REPLACE INTO notebooks (id, title, folder, cover, created_at, updated_at, page_count, locked, '
        'locked_pages, pinned, trashed_at, last_page, opened_at, thumb) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          e.id,
          e.title,
          jsonEncode(e.folder),
          e.cover == null ? null : colorToHex(e.cover!),
          e.createdAt.millisecondsSinceEpoch,
          e.updatedAt.millisecondsSinceEpoch,
          e.pageCount,
          e.locked ? 1 : 0,
          e.lockedPages,
          e.pinned ? 1 : 0,
          e.trashedAt?.millisecondsSinceEpoch,
          e.lastPage,
          e.openedAt?.millisecondsSinceEpoch,
          e.thumb?.encode(),
        ],
      );

  Future<void> remove(String id) => customStatement('DELETE FROM notebooks WHERE id = ?', [id]);

  // Search.

  /// Replaces what can be searched on a page with [rows].
  Future<void> replacePageText(String notebookId, String pageId, List<SearchRow> rows) => transaction(() async {
        await customStatement('DELETE FROM search_text WHERE notebook_id = ? AND page_id = ?', [notebookId, pageId]);
        for (final r in rows) {
          await customStatement(
            'INSERT INTO search_text (notebook_id, page_id, kind, ref, text, norm, context, x, y, w, h, at, data) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
              r.notebookId,
              r.pageId,
              r.kind.name,
              r.ref,
              r.text,
              searchNorm(r.text),
              r.context,
              r.rect.left,
              r.rect.top,
              r.rect.width,
              r.rect.height,
              r.at.millisecondsSinceEpoch,
              r.dataJson,
            ],
          );
        }
      });

  /// Forgets a notebook's searchable text (and what's remembered and the
  /// flashcards in it), or only the pages not in [keepPages].
  Future<void> removeNotebookText(String notebookId, {Set<String>? keepPages}) async {
    if (keepPages == null) {
      await customStatement('DELETE FROM search_text WHERE notebook_id = ?', [notebookId]);
      await customStatement('DELETE FROM search_state WHERE notebook_id = ?', [notebookId]);
      await customStatement('DELETE FROM study_items WHERE notebook_id = ?', [notebookId]);
      return;
    }
    final study = await customSelect(
      'SELECT DISTINCT page_id FROM study_items WHERE notebook_id = ?',
      variables: [Variable.withString(notebookId)],
    ).get();
    for (final r in study) {
      final page = r.read<String>('page_id');
      if (!keepPages.contains(page)) {
        await customStatement('DELETE FROM study_items WHERE notebook_id = ? AND page_id = ?', [notebookId, page]);
      }
    }
    final rows = await customSelect(
      'SELECT DISTINCT page_id FROM search_text WHERE notebook_id = ?',
      variables: [Variable.withString(notebookId)],
    ).get();
    for (final r in rows) {
      final page = r.read<String>('page_id');
      if (!keepPages.contains(page)) {
        await customStatement('DELETE FROM search_text WHERE notebook_id = ? AND page_id = ?', [notebookId, page]);
      }
    }
  }

  // Need to remember and flashcards.

  /// Replaces what's remembered and the flashcards on a page with [rows].
  Future<void> replacePageStudy(String notebookId, String pageId, List<StudyRow> rows) => transaction(() async {
        await customStatement('DELETE FROM study_items WHERE notebook_id = ? AND page_id = ?', [notebookId, pageId]);
        for (final r in rows) {
          await customStatement(
            'INSERT INTO study_items (notebook_id, page_id, kind, ref, x, y, w, h, at, data) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
              r.notebookId,
              r.pageId,
              r.kind.name,
              r.ref,
              r.rect.left,
              r.rect.top,
              r.rect.width,
              r.rect.height,
              r.at.millisecondsSinceEpoch,
              r.dataJson,
            ],
          );
        }
      });

  /// Every thing to remember and flashcard (of [kind] only, if given),
  /// oldest first.
  Future<List<StudyRow>> studyRows({StudyKind? kind}) async {
    final rows = await customSelect(
      kind == null ? 'SELECT * FROM study_items ORDER BY at' : 'SELECT * FROM study_items WHERE kind = ? ORDER BY at',
      variables: [if (kind != null) Variable.withString(kind.name)],
    ).get();
    return [
      for (final r in rows)
        if (StudyKind.values.where((k) => k.name == r.read<String>('kind')).firstOrNull case final k?)
          StudyRow(
            notebookId: r.read<String>('notebook_id'),
            pageId: r.read<String>('page_id'),
            kind: k,
            ref: r.read<String>('ref'),
            rect: Rect.fromLTWH(r.read<double>('x'), r.read<double>('y'), r.read<double>('w'), r.read<double>('h')),
            at: DateTime.fromMillisecondsSinceEpoch(r.read<int>('at'), isUtc: true),
            data: (jsonDecode(r.read<String>('data')) as Map).cast<String, dynamic>(),
          ),
    ];
  }

  /// The notebooks that have searchable text or were indexed.
  Future<Set<String>> indexedNotebooks() async {
    final rows = await customSelect(
      'SELECT notebook_id FROM search_state UNION SELECT DISTINCT notebook_id FROM search_text '
      'UNION SELECT DISTINCT notebook_id FROM study_items',
    ).get();
    return {for (final r in rows) r.read<String>('notebook_id')};
  }

  /// Rows with every one of [terms] at the start of a word (see
  /// [searchTerms]).
  Future<List<SearchRow>> searchText(List<String> terms) async {
    if (terms.isEmpty) return const [];
    // Terms are letters and digits only, so nothing in them needs escaping.
    final rows = await customSelect(
      'SELECT * FROM search_text WHERE ${[for (final _ in terms) 'norm LIKE ?'].join(' AND ')}',
      variables: [for (final t in terms) Variable.withString('% $t%')],
    ).get();
    return [
      for (final r in rows)
        SearchRow(
          notebookId: r.read<String>('notebook_id'),
          pageId: r.read<String>('page_id'),
          kind: searchKindFromName(r.read<String>('kind')),
          ref: r.read<String>('ref'),
          text: r.read<String>('text'),
          context: r.read<String>('context'),
          rect: Rect.fromLTWH(r.read<double>('x'), r.read<double>('y'), r.read<double>('w'), r.read<double>('h')),
          at: DateTime.fromMillisecondsSinceEpoch(r.read<int>('at'), isUtc: true),
          data: (jsonDecode(r.read<String>('data')) as Map).cast<String, dynamic>(),
        ),
    ];
  }

  /// Which version of the notebook its searchable text was taken from:
  /// (its `updatedAt`, the handwriting language, the indexer's version).
  Future<(DateTime, String, int)?> indexedState(String notebookId) async {
    final r = await customSelect(
      'SELECT * FROM search_state WHERE notebook_id = ?',
      variables: [Variable.withString(notebookId)],
    ).getSingleOrNull();
    if (r == null) return null;
    return (
      DateTime.fromMillisecondsSinceEpoch(r.read<int>('updated_at'), isUtc: true),
      r.read<String>('lang'),
      r.read<int>('version'),
    );
  }

  Future<void> setIndexedState(String notebookId, DateTime updatedAt, String language, int version) => customStatement(
        'INSERT OR REPLACE INTO search_state (notebook_id, updated_at, lang, version) VALUES (?, ?, ?, ?)',
        [notebookId, updatedAt.millisecondsSinceEpoch, language, version],
      );

  static NotebookEntry _entry(QueryRow r) {
    DateTime? time(String col) {
      final v = r.read<int?>(col);
      return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v, isUtc: true);
    }

    final cover = r.read<String?>('cover');
    return NotebookEntry(
      id: r.read<String>('id'),
      title: r.read<String>('title'),
      folder: (jsonDecode(r.read<String>('folder')) as List).cast<String>(),
      cover: cover == null ? null : colorFromHex(cover),
      createdAt: time('created_at')!,
      updatedAt: time('updated_at')!,
      pageCount: r.read<int>('page_count'),
      locked: r.read<int>('locked') != 0,
      lockedPages: r.read<int>('locked_pages'),
      pinned: r.read<int>('pinned') != 0,
      trashedAt: time('trashed_at'),
      lastPage: r.read<int>('last_page'),
      openedAt: time('opened_at'),
      thumb: InkThumb.decode(r.read<String?>('thumb')),
    );
  }
}
