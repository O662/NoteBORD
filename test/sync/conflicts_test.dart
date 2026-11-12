// Update 04: pages to check. A page changed on two devices while one was
// offline is still merged at once, and both sides are kept as versions.
import 'dart:convert';

import 'package:endless/board/model.dart';
import 'package:endless/sync/cloud.dart';
import 'package:endless/sync/conflicts.dart';
import 'package:endless/sync/versions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sync_helpers.dart';

void main() {
  late MemoryCloud cloud;
  late Install a, b;
  final t = DateTime.utc(2026, 11, 5, 12);

  setUp(() {
    cloud = MemoryCloud();
    a = Install('a', clock: () => t);
    b = Install('b', clock: () => t);
  });

  Future<String> shared() async {
    final id = await a.newNotebook();
    await a.write(id, x: 10);
    await a.sync(cloud);
    await b.sync(cloud);
    return id;
  }

  test('the other device wrote offline: merged, both kept, and the page goes on the list', () async {
    final id = await shared();
    final pageId = (await a.load(id)).pages.first.id;
    // B writes, offline; A writes later; B comes online and syncs; then A.
    b.clock = () => t.add(const Duration(minutes: 1));
    final fromB = await b.write(id, x: 100);
    a.clock = () => t.add(const Duration(minutes: 5));
    final fromA = await a.write(id, x: 50);
    b.clock = () => t.add(const Duration(minutes: 9));
    await b.sync(cloud);
    a.clock = () => t.add(const Duration(minutes: 10));
    await a.sync(cloud);

    // Merged: every stroke is on A's page; nothing waited.
    expect(await a.itemIds(id), containsAll([fromA, fromB]));
    final c = a.host.conflicts.single;
    expect(c.notebookId, id);
    expect(c.pageId, pageId);
    expect(c.device, 'b');
    expect(c.theirsAt, t.add(const Duration(minutes: 1)));

    // Both sides are in version history: A's page before, and B's.
    final versions = await VersionStore(a.store).list(id, pageId);
    final ours = versions.firstWhere((v) => v.name == c.ours);
    final theirs = versions.firstWhere((v) => v.name == c.theirs);
    expect(ours.reason, VersionReason.sync);
    expect(theirs.reason, VersionReason.remote);
    Future<Set<String>> ids(String name) async {
      final page = jsonDecode(utf8.decode((await a.store.loadVersion(id, pageId, name))!)) as Json;
      return {for (final i in page['items'] as List) (i as Map)['id'] as String};
    }

    expect(await ids(c.ours), contains(fromA));
    expect(await ids(c.ours), isNot(contains(fromB)));
    expect(await ids(c.theirs), contains(fromB));
    expect(await ids(c.theirs), isNot(contains(fromA)));
  });

  test('both online, a few seconds apart: just merged, nothing to check', () async {
    final id = await shared();
    b.clock = () => t.add(const Duration(minutes: 3));
    final fromB = await b.write(id, x: 100);
    a.clock = () => t.add(const Duration(minutes: 3, seconds: 2));
    final fromA = await a.write(id, x: 50);
    b.clock = () => t.add(const Duration(minutes: 3, seconds: 5));
    await b.sync(cloud);
    a.clock = () => t.add(const Duration(minutes: 3, seconds: 10));
    await a.sync(cloud);
    expect(await a.itemIds(id), containsAll([fromA, fromB]));
    expect(a.host.conflicts, isEmpty);
  });

  test('only the other device changed it: taken as it is', () async {
    final id = await shared();
    b.clock = () => t.add(const Duration(minutes: 1));
    await b.write(id, x: 100);
    await b.sync(cloud);
    a.clock = () => t.add(const Duration(hours: 1));
    await a.sync(cloud);
    expect(a.host.conflicts, isEmpty);
  });

  test('the list round trips', () {
    final c = PageConflict(
      notebookId: 'nb',
      pageId: 'pg',
      device: 'Kim’s phone',
      theirsAt: t,
      oursAt: t.add(const Duration(minutes: 5)),
      ours: '1-sync.json',
      theirs: '2-remote.json',
    );
    final back = PageConflict.fromJson(jsonDecode(jsonEncode(c.toJson())))!;
    expect(back.toJson(), c.toJson());
    expect(PageConflict.fromJson({'notebook': 'nb'}), isNull);
  });
}
