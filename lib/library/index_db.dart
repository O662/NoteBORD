import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../board/model.dart';
import 'library.dart';
import 'thumbs.dart';

/// The library index: one row per notebook, so the Start page and Library
/// can list, sort and draw covers without opening every `.board` package.
///
/// The `.board` files are the source of truth. The index is a cache rebuilt
/// from them (see [LibraryLoader]); only `last_page` and `opened_at`, which
/// are this device's reading position, live here alone. Phase 4 adds the
/// handwriting search tables.
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
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => customStatement('''
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
          )'''),
      );

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
