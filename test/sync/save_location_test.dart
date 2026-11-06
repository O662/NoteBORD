import 'dart:convert';

import 'package:endless/board/model.dart';
import 'package:endless/sync/cloud.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sync_helpers.dart';

void main() {
  late MemoryCloud drive, onedrive;
  late Install a, b;

  setUp(() {
    drive = MemoryCloud();
    onedrive = MemoryCloud(kind: CloudKind.onedrive);
    a = Install('a');
    b = Install('b');
  });

  Set<String> notebooksIn(MemoryCloud c) => {
        for (final k in c.files.keys)
          if (k.endsWith('/notebook.json')) k,
      };

  Future<void> saveTo(Install i, String id, String? where) => i.edit(id, (nb) => nb.notebook.saveTo = where);

  test('a notebook goes only to its own place; one from before goes to every cloud', () async {
    final old = await a.newNotebook(title: 'Old');
    final tablet = await a.newNotebook(title: 'Diary');
    await saveTo(a, tablet, 'device');
    final od = await a.newNotebook(title: 'Work');
    await saveTo(a, od, 'onedrive');
    final gd = await a.newNotebook(title: 'School');
    await saveTo(a, gd, 'google');

    final rd = await a.sync(drive);
    final ro = await a.sync(onedrive);
    expect(rd.sent, {old, gd});
    expect(ro.sent, {old, od});
    expect(notebooksIn(drive).any((k) => k.contains(tablet)), isFalse);
    expect(notebooksIn(onedrive).any((k) => k.contains(tablet)), isFalse);
    // The place is in notebook.json, so other devices know it.
    final remote = jsonDecode(utf8.decode(onedrive.files[notebooksIn(onedrive).firstWhere((k) => k.contains(od))]!)) as Json;
    expect(remote['saveTo'], 'onedrive');

    // A quick sync while writing follows it too.
    await a.write(tablet);
    final quick = await a.engine.syncAll(drive, only: {tablet, gd});
    expect(quick.sent, isEmpty);
  });

  test('moved to another place: the old cloud is told once, then left alone; other devices stop too', () async {
    final id = await a.newNotebook(title: 'Lab');
    await saveTo(a, id, 'google');
    await a.sync(drive);
    await b.sync(drive);
    expect((await b.load(id)).notebook.saveTo, 'google');

    // Moved to OneDrive on a: Drive's copy is told where it went, once.
    await saveTo(a, id, 'onedrive');
    final told = await a.sync(drive);
    expect(told.sent, {id});
    final again = await a.write(id);
    drive.writes.clear();
    final after = await a.sync(drive);
    expect(after.sent, isEmpty);
    expect(drive.writes.where((w) => w.contains(id)), isEmpty);
    expect((await a.sync(onedrive)).sent, {id});

    // b learns where it went from Drive, and stops syncing it there.
    await b.sync(drive);
    expect((await b.load(id)).notebook.saveTo, 'onedrive');
    await b.write(id, x: 90);
    drive.writes.clear();
    await b.sync(drive);
    expect(drive.writes.where((w) => w.contains(id)), isEmpty);
    // a's newest stroke never went to Drive.
    expect((await b.itemIds(id)).contains(again), isFalse);
  });

  test('a device that never had it doesn\'t bring down the copy left in a cloud it moved from', () async {
    final id = await a.newNotebook(title: 'Moved');
    await saveTo(a, id, 'google');
    await a.sync(drive);
    await saveTo(a, id, 'device');
    await a.sync(drive);
    final rb = await b.sync(drive);
    expect(rb.changedHere, isEmpty);
    expect(await b.store.loadNotebookMeta(id), isNull);
  });

  test('saveTo round-trips through notebook.json and is left out when unset', () async {
    final id = await a.newNotebook(title: 'X');
    expect((await a.load(id)).notebook.saveTo, isNull);
    await saveTo(a, id, 'device');
    expect((await a.load(id)).notebook.saveTo, 'device');
  });
}
