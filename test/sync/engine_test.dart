import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/sync/cloud.dart';
import 'package:endless/sync/engine.dart';
import 'package:endless/sync/stamps.dart';
import 'package:endless/sync/versions.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'sync_helpers.dart';

void main() {
  late MemoryCloud cloud;
  late Install a, b;

  setUp(() {
    cloud = MemoryCloud();
    a = Install('a');
    b = Install('b');
  });

  /// Syncs a, then b, then a again (so each has the other's changes).
  Future<void> round() async {
    await a.sync(cloud);
    await b.sync(cloud);
    await a.sync(cloud);
  }

  test('a notebook made on one device shows up on the other, with its pages, ink and pictures', () async {
    final id = await a.newNotebook(title: 'Lab journal');
    final s = await a.write(id);
    await a.store.saveAsset(id, 'abc.png', fakePng());
    final report = await a.sync(cloud);
    expect(report.sent, {id});
    // Its folder is named after it, then its id.
    final dir = 'Lab journal · $id.board';
    expect(cloud.files.keys, containsAll(['endless.json', '$dir/notebook.json', '$dir/assets/abc.png']));

    final rb = await b.sync(cloud);
    expect(rb.changedHere, {id});
    expect(b.host.written, [id]);
    final nb = await b.load(id);
    expect(nb.notebook.title, 'Lab journal');
    expect(nb.pages.single.items.single.id, s);
    expect(await b.store.loadAsset(id, 'abc.png'), fakePng());
    // The cloud copy is a .board package: notebook.json lists its pages.
    final remote = jsonDecode(utf8.decode(cloud.files['$dir/notebook.json']!)) as Json;
    expect(remote['pages'], nb.notebook.pageIds);
  });

  test('nothing changed: a second sync sends nothing', () async {
    final id = await a.newNotebook();
    await a.write(id);
    await round();
    await b.sync(cloud);
    cloud.writes.clear();
    final ra = await a.sync(cloud);
    final rb = await b.sync(cloud);
    expect(cloud.writes, isEmpty);
    expect(ra.sent, isEmpty);
    expect(rb.changedHere, isEmpty);
    expect(ra.synced.keys, {id});
  });

  test('writing on the same page on two devices offline: every stroke is kept on both', () async {
    final id = await a.newNotebook();
    await round();
    final fromA = {await a.write(id, x: 10), await a.write(id, x: 50)};
    final fromB = {await b.write(id, x: 100)};
    await round();
    await b.sync(cloud);
    expect(await a.itemIds(id), {...fromA, ...fromB});
    expect(await b.itemIds(id), {...fromA, ...fromB});
    final orderA = [for (final i in (await a.load(id)).pages.first.items) i.id];
    final orderB = [for (final i in (await b.load(id)).pages.first.items) i.id];
    expect(orderA, orderB);
  });

  test('the slow part runs on another isolate, with the same result', () async {
    // No fallback here: anything that can't be sent there fails the test.
    var ran = 0;
    Future<R> isolate<R>(FutureOr<R> Function() task) {
      ran++;
      return Isolate.run(task);
    }

    final c = Install('c', worker: isolate, stamper: Stamper('dv_c', clock: _fixedClock));
    final d = Install('d', worker: isolate, stamper: Stamper('dv_d', clock: _fixedClock));
    final id = await c.newNotebook(title: 'Lab journal');
    final s1 = await c.write(id, x: 10);
    await c.sync(cloud);
    await d.sync(cloud);
    expect(await d.itemIds(id), {s1});
    expect(ran, greaterThan(0));

    // Both write offline, then sync: every stroke on both.
    final s2 = await c.write(id, x: 50);
    final s3 = await d.write(id, x: 90);
    await c.sync(cloud);
    await d.sync(cloud);
    await c.sync(cloud);
    expect(await c.itemIds(id), {s1, s2, s3});
    expect(await d.itemIds(id), {s1, s2, s3});

    // And a sync with nothing new sends nothing.
    cloud.writes.clear();
    await c.sync(cloud);
    await d.sync(cloud);
    expect(cloud.writes, isEmpty);
  });

  test('a stroke erased on one device goes on the other and doesn\'t come back', () async {
    final id = await a.newNotebook();
    final s1 = await a.write(id, x: 10);
    final s2 = await a.write(id, x: 60);
    await round();
    await b.sync(cloud);
    await a.edit(id, (nb) => nb.pages.first.items.removeWhere((i) => i.id == s1),
        at: DateTime.utc(2026, 11, 5, 12, 5));
    final s3 = await b.write(id, x: 90, at: DateTime.utc(2026, 11, 5, 12, 6));
    await round();
    await b.sync(cloud);
    expect(await a.itemIds(id), {s2, s3});
    expect(await b.itemIds(id), {s2, s3});
    // Another round changes nothing.
    await round();
    expect(await b.itemIds(id), {s2, s3});
  });

  test('a page changed by another device is kept in version history first', () async {
    final id = await a.newNotebook();
    await a.write(id, x: 10);
    await round();
    await b.sync(cloud);
    final pageId = (await b.load(id)).pages.first.id;
    await a.write(id, x: 40);
    await a.sync(cloud);
    await b.sync(cloud);
    final versions = await VersionStore(b.store).list(id, pageId);
    expect(versions.single.reason, VersionReason.sync);
    expect(versions.single.device, 'a');
    final old = jsonDecode(utf8.decode((await b.store.loadVersion(id, pageId, versions.single.name))!)) as Json;
    expect((old['items'] as List).length, 1);
  });

  test('renamed on one, pinned on the other: both', () async {
    final id = await a.newNotebook(title: 'Old');
    await round();
    await b.sync(cloud);
    await a.edit(id, (nb) => nb.notebook.title = 'New');
    await b.edit(id, (nb) => nb.notebook.pinned = true);
    await round();
    await b.sync(cloud);
    for (final d in [a, b]) {
      final nb = await d.load(id);
      expect(nb.notebook.title, 'New');
      expect(nb.notebook.pinned, isTrue);
    }
  });

  test('pages added on both devices are both kept', () async {
    final id = await a.newNotebook();
    await round();
    await b.sync(cloud);
    await a.edit(id, (nb) {
      final p = BoardPage(id: 'pg_fromA');
      nb.pages.add(p);
      nb.notebook.pageIds.add(p.id);
    });
    await b.edit(id, (nb) {
      final p = BoardPage(id: 'pg_fromB');
      nb.pages.add(p);
      nb.notebook.pageIds.add(p.id);
    });
    await round();
    await b.sync(cloud);
    expect((await a.load(id)).notebook.pageIds, (await b.load(id)).notebook.pageIds);
    expect((await a.load(id)).notebook.pageIds, containsAll(['pg_fromA', 'pg_fromB']));
  });

  test('deleted for good on one device: gone from the other and from the cloud', () async {
    final id = await a.newNotebook();
    await round();
    await b.sync(cloud);
    await a.store.deleteNotebook(id);
    await a.sync(cloud);
    expect(cloud.files.keys.where((k) => k.contains('$id.board')), isEmpty);
    await b.sync(cloud);
    expect(b.host.deleted, [id]);
    expect(await b.store.loadNotebookMeta(id), isNull);
    // And a third device that never saw it doesn't fetch it.
    final c = Install('c');
    await c.sync(cloud);
    expect(await c.store.listNotebookIds(), isEmpty);
  });

  test('folders and decks travel', () async {
    await a.store.saveLibrary({
      'version': 1,
      'folders': [
        {'path': ['School'], 'color': '#2B5A8C'},
        {'path': ['School', 'Physics'], 'color': '#3B6E47'},
      ],
    });
    await a.store.saveDecks({
      'decks': [
        {'id': 'dk_1', 'name': 'Momentum', 'createdAt': '2026-11-01T00:00:00.000Z'},
      ],
    });
    await a.sync(cloud);
    await b.sync(cloud);
    expect([for (final f in (await b.store.loadLibrary())!['folders'] as List) (f as Map)['path']], [
      ['School'],
      ['School', 'Physics'],
    ]);
    expect(((await b.store.loadDecks())!['decks'] as List).single['name'], 'Momentum');
    // Deleted on b: gone from a too.
    await b.store.saveLibrary({
      'version': 1,
      'folders': [
        {'path': ['School'], 'color': '#2B5A8C'},
      ],
    });
    await b.sync(cloud);
    await a.sync(cloud);
    expect(((await a.store.loadLibrary())!['folders'] as List).length, 1);
  });

  test('images and PDFs stay off the cloud when that\'s turned off; recordings still go', () async {
    final small = Install('small', options: const SyncOptions(media: false));
    final id = await small.newNotebook();
    await small.store.saveAsset(id, 'pic.png', fakePng());
    await small.store.saveAsset(id, 'talk.m4a', Uint8List.fromList([1, 2, 3]));
    await small.sync(cloud);
    expect(cloud.files.keys, contains('Physics · $id.board/assets/talk.m4a'));
    expect(cloud.files.keys, isNot(contains('Physics · $id.board/assets/pic.png')));
  });

  test('a page with a password syncs sealed, with its password entry', () async {
    final id = await a.newNotebook();
    final pageId = (await a.load(id)).pages.first.id;
    await round();
    await b.sync(cloud);
    await a.store.saveSealedPage(id, pageId, Uint8List.fromList([9, 9, 9]));
    await a.store.saveLock(id, {
      'version': 1,
      'notebook': null,
      'pages': {
        pageId: {'salt': 'c2FsdA=='},
      },
    });
    await a.edit(id, (nb) => nb.notebook.extra['touched'] = true);
    await a.sync(cloud);
    final pageFiles = cloud.files.keys.where((k) => k.startsWith('Physics · $id.board/pages/$pageId.')).toList();
    expect(pageFiles, hasLength(1));
    expect(pageFiles.single, endsWith('.json.enc'));
    await b.sync(cloud);
    final nb = await b.load(id);
    expect(nb.sealed[pageId], [9, 9, 9]);
    expect((nb.lock!['pages'] as Map).keys, [pageId]);
  });

  test('a cloud write lost to another device\'s at the same moment is put right on the next sync', () async {
    final id = await a.newNotebook();
    await round();
    await b.sync(cloud);
    final pageId = (await a.load(id)).pages.first.id;
    final s1 = await a.write(id, x: 10);
    final s2 = await b.write(id, x: 90);
    // Both read the cloud, then both write: b's page and notebook.json
    // land last, over a's.
    final before = {...cloud.files};
    await a.sync(cloud);
    final afterA = {...cloud.files};
    cloud.files
      ..clear()
      ..addAll(before);
    await b.sync(cloud);
    // a's page file landed after b's (a slower upload), and b's
    // notebook.json after a's.
    for (final e in afterA.entries) {
      if (e.key.startsWith('Physics · $id.board/pages/$pageId.')) cloud.files.putIfAbsent(e.key, () => e.value);
    }
    await b.sync(cloud);
    await a.sync(cloud);
    await b.sync(cloud);
    expect(await a.itemIds(id), {s1, s2});
    expect(await b.itemIds(id), {s1, s2});
  });

  test('an open notebook gets the changes through the app, which then sends what it has', () async {
    final id = await a.newNotebook();
    await round();
    await b.sync(cloud);
    await a.write(id, x: 10);
    await a.sync(cloud);
    b.host.open[id] = null;
    // Written on b while it's open, not saved yet when sync starts.
    b.host.unsaved = () => b.write(id, x: 200);
    await b.sync(cloud);
    expect(b.host.open[id]!.pages.values.single['items'], hasLength(2));
    expect(await b.itemIds(id), hasLength(2));
    // What b wrote went to the cloud with the rest.
    await a.sync(cloud);
    expect(await a.itemIds(id), hasLength(2));
  });

  test('also a PDF copy of each notebook, renamed with the notebook', () async {
    final pdfs = Install('p', options: const SyncOptions(pdfCopy: true));
    pdfs.host.pdf = fakePdfBytes();
    final id = await pdfs.newNotebook(title: 'Lab: week 1');
    await pdfs.sync(cloud);
    final names = cloud.files.keys.where((k) => k.startsWith('PDF/')).toList();
    expect(names, ['PDF/Lab  week 1 (${id.substring(id.length - 4)}).pdf']);
    cloud.writes.clear();
    await pdfs.sync(cloud);
    expect(cloud.writes, isEmpty);
    await pdfs.edit(id, (nb) => nb.notebook.title = 'Lab 1');
    await pdfs.sync(cloud);
    expect(cloud.files.keys.where((k) => k.startsWith('PDF/')), ['PDF/Lab 1 (${id.substring(id.length - 4)}).pdf']);
  });

  test('can\'t reach the cloud: it says so, and nothing here changes', () async {
    final id = await a.newNotebook();
    cloud.failing = CloudFailure.offline;
    await expectLater(a.sync(cloud), throwsA(isA<CloudException>()));
    expect(await a.load(id), isNotNull);
    cloud.failing = null;
    expect((await a.sync(cloud)).sent, {id});
  });

  test('two installs on real files, syncing through a folder', () async {
    final tmp = await Directory.systemTemp.createTemp('endless_sync_');
    addTearDown(() => tmp.delete(recursive: true));
    final folder = FolderCloud(Directory('${tmp.path}/cloud'));
    final one = Install('one', store: FileBoardStore(Directory('${tmp.path}/one')));
    final two = Install('two', store: FileBoardStore(Directory('${tmp.path}/two')));
    final id = await one.newNotebook(title: 'Shared');
    final s1 = await one.write(id);
    await one.store.saveAsset(id, 'photo.png', fakePng());
    await one.sync(folder);
    await two.sync(folder);
    final s2 = await two.write(id, x: 80);
    final s3 = await one.write(id, x: 120);
    await two.sync(folder);
    await one.sync(folder);
    await two.sync(folder);
    expect(await one.itemIds(id), {s1, s2, s3});
    expect(await two.itemIds(id), {s1, s2, s3});
    expect(await two.store.loadAsset(id, 'photo.png'), fakePng());
    expect(File('${tmp.path}/cloud/Shared · $id.board/notebook.json').existsSync(), isTrue);
  });

  test('folders are named after their notebooks, and renamed with them', () async {
    final id = await a.newNotebook(title: 'Lab: week 1');
    await a.sync(cloud);
    expect(cloud.files.keys, contains('Lab week 1 · $id.board/notebook.json'));
    await b.sync(cloud);
    // Renamed on b: the folder follows, and a still finds it.
    await b.edit(id, (nb) => nb.notebook.title = 'Lab journal');
    await b.sync(cloud);
    expect(cloud.files.keys.where((k) => k.contains(id)).every((k) => k.startsWith('Lab journal · $id.board/')), isTrue);
    await a.sync(cloud);
    expect((await a.load(id)).notebook.title, 'Lab journal');
    expect(cloud.files.keys.where((k) => k.contains(id)).every((k) => k.startsWith('Lab journal · $id.board/')), isTrue);
  });

  test('a folder named the old way (just the id) is found and renamed', () async {
    final id = await a.newNotebook(title: 'Physics');
    await a.sync(cloud);
    // As Endless named folders before.
    await cloud.rename('Physics · $id.board', '$id.board');
    await b.sync(cloud);
    expect(await b.store.loadNotebookMeta(id), isNotNull);
    expect(cloud.files.keys.where((k) => k.contains(id)).every((k) => k.startsWith('Physics · $id.board/')), isTrue);
  });

  test('two folders for one notebook (named on two devices at once): one is kept, nothing is lost', () async {
    final id = await a.newNotebook(title: 'Physics');
    await round();
    await b.sync(cloud);
    final s1 = await a.write(id, x: 10);
    await a.sync(cloud);
    // A second folder with an older name, as another device left it.
    for (final e in {...cloud.files}.entries) {
      if (e.key.startsWith('Physics · $id.board/')) cloud.files[e.key.replaceFirst('Physics · ', 'Old name · ')] = e.value;
    }
    final s2 = await b.write(id, x: 90);
    await b.sync(cloud);
    await a.sync(cloud);
    await b.sync(cloud);
    expect(await a.itemIds(id), {s1, s2});
    expect(await b.itemIds(id), {s1, s2});
    expect({for (final k in cloud.files.keys) if (k.contains(id)) k.split('/').first}, hasLength(1));
  });

  test('folder names: unsafe characters go, long titles are cut, no title is just the id', () {
    expect(SyncEngine.folderNameFor('Lab: 1/2 "draft"?', 'nb_1'), 'Lab 1 2 draft · nb_1.board');
    expect(SyncEngine.folderNameFor('', 'nb_1'), 'nb_1.board');
    expect(SyncEngine.folderNameFor('x' * 100, 'nb_1').length, 60 + ' · nb_1.board'.length);
    expect(SyncEngine.idOfFolder('Lab · journal · nb_1.board'), 'nb_1');
    expect(SyncEngine.idOfFolder('nb_1.board'), 'nb_1');
    expect(SyncEngine.idOfFolder('PDF'), isNull);
  });

  test('a quick sync sends only the notebooks named, in a few requests', () async {
    final busy = await a.newNotebook(title: 'Busy');
    final other = await a.newNotebook(title: 'Other');
    await round();
    await b.sync(cloud);
    final s1 = await a.write(busy);
    await a.write(other, x: 50);
    cloud.reads.clear();
    cloud.writes.clear();
    final r = await a.engine.syncAll(cloud, only: {busy});
    expect(r.sent, {busy});
    // notebook.json read, the page and notebook.json written: no other
    // notebook, no endless.json.
    expect(cloud.reads, ['Busy · $busy.board/notebook.json']);
    expect(cloud.writes, hasLength(2));
    expect(cloud.writes.every((w) => w.startsWith('Busy · $busy.board/')), isTrue);
    await b.sync(cloud);
    expect(await b.itemIds(busy), {s1});
    expect(await b.itemIds(other), isEmpty);
  });

  test('a quick sync never brings back a notebook deleted here', () async {
    final id = await a.newNotebook();
    await round();
    await a.store.deleteNotebook(id);
    await a.engine.syncAll(cloud, only: {id});
    expect(await a.store.loadNotebookMeta(id), isNull);
    // The full sync deletes it from the cloud.
    await a.sync(cloud);
    expect(cloud.files.keys.where((k) => k.contains(id)), isEmpty);
  });
}

/// A clock that can go to another isolate (a top-level function).
DateTime _fixedClock() => DateTime.utc(2026, 11, 5, 12);
