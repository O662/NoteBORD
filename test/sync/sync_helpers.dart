import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:endless/board/codec.dart';
import 'package:endless/board/ids.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/sync/cloud.dart';
import 'package:endless/sync/doc.dart';
import 'package:endless/sync/engine.dart';
import 'package:endless/sync/stamps.dart';
import 'package:endless/sync/versions.dart';

import '../helpers.dart';

/// One install of Endless (a device), with its own storage, syncing
/// through whatever cloud it's given.
class Install {
  Install(String name, {BoardStore? store, DateTime Function()? clock, SyncOptions? options})
      : store = store ?? MemoryBoardStore(),
        clock = clock ?? (() => DateTime.utc(2026, 11, 5, 12)) {
    host = TestHost(this.store);
    engine = SyncEngine(
      store: this.store,
      host: host,
      stamper: Stamper('dv_$name', clock: () => this.clock()),
      versions: VersionStore(this.store, clock: () => this.clock()),
      options: options ?? SyncOptions(deviceName: name),
    );
  }

  final BoardStore store;
  DateTime Function() clock;
  late final TestHost host;
  late final SyncEngine engine;

  Future<SyncReport> sync(CloudDrive cloud) => engine.syncAll(cloud);

  /// Creates a notebook with one empty page; returns its id.
  Future<String> newNotebook({String title = 'Physics', DateTime? at}) async {
    final now = at ?? clock();
    final page = BoardPage(id: newId('pg', now: now));
    final nb = Notebook(
      id: newId('nb', now: now),
      title: title,
      createdAt: now,
      updatedAt: now,
      pageIds: [page.id],
    );
    await store.savePage(nb.id, page);
    await store.saveNotebook(nb);
    return nb.id;
  }

  Future<LoadedNotebook> load(String id) async => (await store.loadNotebook(id))!;

  /// Changes notebook [id] as the app would: [change] the loaded copy,
  /// then every page and notebook.json are written, with updatedAt [at].
  Future<void> edit(String id, void Function(LoadedNotebook nb) change, {DateTime? at}) async {
    final nb = await load(id);
    change(nb);
    nb.notebook.updatedAt = at ?? clock();
    for (final p in nb.pages) {
      if (!nb.sealed.containsKey(p.id)) await store.savePage(id, p);
    }
    await store.saveNotebook(nb.notebook);
  }

  /// Adds a stroke to page [page] of notebook [id]; returns the stroke's id.
  Future<String> write(String id, {int page = 0, double x = 10, DateTime? at}) async {
    final s = strokeFrom([Offset(x, 10), Offset(x + 20, 30)]);
    await edit(id, (nb) => nb.pages[page].items.add(s), at: at);
    return s.id;
  }

  Future<Set<String>> itemIds(String id, {int page = 0}) async =>
      {for (final i in (await load(id)).pages[page].items) i.id};
}

/// The app's side, for an engine with no open notebooks: writes folders and
/// decks straight to the store.
class TestHost implements SyncHost {
  TestHost(this.store);

  final BoardStore store;
  final written = <String>[];
  final deleted = <String>[];

  /// Open notebooks: the changes last put into each.
  final open = <String, BoardDoc?>{};

  /// Something written in an open notebook, saved at its next flush.
  Future<void> Function()? unsaved;
  Future<void>? _applying;

  @override
  bool isOpen(String id) => open.containsKey(id);

  @override
  Future<void> flush(String id) async {
    await _applying;
    final u = unsaved;
    unsaved = null;
    if (u != null) await u();
  }

  /// As the open notebook does: takes the changes, then saves them.
  @override
  bool applyOpen(String id, BoardDoc from, BoardDoc to) {
    open[id] = to;
    _applying = () async {
      for (final e in to.pages.entries) {
        await store.savePage(id, decodePage(jsonEncode(e.value)));
      }
      await store.saveNotebook(decodeNotebook(jsonEncode(to.notebook)));
    }();
    return true;
  }

  @override
  Future<void> notebookWritten(String id, {required bool added}) async => written.add(id);

  @override
  Future<void> deleteNotebook(String id) async {
    deleted.add(id);
    await store.deleteNotebook(id);
  }

  @override
  Future<void> applyRoot({
    required Map<String, Object?> foldersFrom,
    required Map<String, Object?> foldersTo,
    required Map<String, Object?> decksFrom,
    required Map<String, Object?> decksTo,
  }) async {
    await store.saveLibrary({
      'version': 1,
      'folders': [for (final v in foldersTo.values) v],
    });
    await store.saveDecks({
      'decks': [for (final v in decksTo.values) v],
    });
  }

  Uint8List? pdf;

  @override
  Future<Uint8List?> pdfOf(String id) async => pdf;

  @override
  Future<T> exclusive<T>(Future<T> Function() task) => task();
}

/// A page's items' ids in order.
List<String> idsOf(Json page) => [for (final i in page['items'] as List) (i as Map)['id'] as String];

Json pageJson(BoardPage p) => jsonDecode(encodePage(p)) as Json;

/// A cloud folder's files, decoded, for comparing two clouds or rounds.
Map<String, String> cloudText(MemoryCloud c) => {for (final e in c.files.entries) e.key: base64Encode(e.value)};
