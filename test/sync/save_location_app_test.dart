import 'dart:async';

import 'package:endless/board/ids.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/library/library.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/sync/cloud.dart';
import 'package:endless/sync/cloud_auth.dart';
import 'package:endless/sync/sync_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'sync_app_helpers.dart';

// What the app says is waiting to sync, for notebooks saved to one place
// (Update 02: "Save to" on each notebook).

void main() {
  late MemoryCloud drive, onedrive;

  setUp(() {
    drive = MemoryCloud();
    onedrive = MemoryCloud(kind: CloudKind.onedrive);
  });

  Future<void> syncIn(WidgetTester tester, ProviderContainer c) async {
    var done = false;
    unawaited(c.read(syncProvider.notifier).syncNow().whenComplete(() => done = true));
    for (var i = 0; i < 200 && !done; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(done, isTrue, reason: 'sync didn’t finish');
  }

  String addSavedTo(MemoryBoardStore store, String? saveTo, {String title = 'Untitled notebook'}) {
    final now = DateTime.utc(2026, 9, 25, 9);
    final page = BoardPage(id: newId('pg'));
    final nb = Notebook(id: newId('nb'), title: title, createdAt: now, updatedAt: now, pageIds: [page.id], saveTo: saveTo);
    store.savePage(nb.id, page);
    store.saveNotebook(nb);
    return nb.id;
  }

  void syncingWith(MemoryBoardStore store, {bool google = true, bool onedrive = false}) {
    const account = CloudAccount('kim@example.com');
    store.saveSyncFile(
      'settings',
      SyncSettings(
        device: 'dv_a',
        google: CloudSetting(on: google, account: google ? account : null),
        onedrive: CloudSetting(on: onedrive, account: onedrive ? account : null),
      ).toJson(),
    );
  }

  String pillStatus(WidgetTester tester) {
    final t = find.textContaining('Page 1 of 1 · ').evaluate().single.widget as Text;
    return t.data!.split(' · ').skip(1).join(' · ');
  }

  Iterable<String> notebooksIn(MemoryCloud c) => c.files.keys.where((k) => k.endsWith('/notebook.json'));

  Future<void> write(WidgetTester tester, ProviderContainer c, String id) async {
    c.read(notebookProvider(id).notifier).addStroke(shownPage(c).id, strokeFrom([const Offset(10, 10), const Offset(80, 40)]));
    await tester.pump(NotebookNotifier.saveDelay);
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();
  }

  testWidgets('saved on this tablet only: never waiting to be sent, written in or not', (tester) async {
    final store = MemoryBoardStore();
    syncingWith(store);
    final id = addSavedTo(store, 'device');
    final c = await pumpCanvas(tester, store: store, notebookId: id, extra: syncOverrides(drive));
    final sync = c.read(syncProvider.notifier);
    await syncIn(tester, c);
    expect(notebooksIn(drive), isEmpty);
    expect(sync.hasChangesToSend, isFalse);
    expect(pillStatus(tester), 'Saved on this tablet');

    await write(tester, c, id);
    expect(sync.hasChangesToSend, isFalse);
    await syncIn(tester, c);
    expect(notebooksIn(drive), isEmpty);
    expect(c.read(syncProvider).dirty, isEmpty);
    expect(sync.hasChangesToSend, isFalse);
  });

  testWidgets('two clouds on, saved to one: synced once that one has it', (tester) async {
    final store = MemoryBoardStore();
    syncingWith(store, onedrive: true);
    final id = addSavedTo(store, 'google');
    final c = await pumpCanvas(tester, store: store, notebookId: id, extra: syncOverrides(drive, onedrive: onedrive));
    final sync = c.read(syncProvider.notifier);
    expect(pillStatus(tester), 'Saved');
    await syncIn(tester, c);
    await tester.pump();
    expect(notebooksIn(drive), hasLength(1));
    expect(notebooksIn(onedrive), isEmpty);
    expect(pillStatus(tester), 'Synced to Google Drive');
    expect(sync.hasChangesToSend, isFalse);

    await write(tester, c, id);
    expect(pillStatus(tester), 'Saved');
    expect(sync.hasChangesToSend, isTrue);
    await syncIn(tester, c);
    await tester.pump();
    expect(pillStatus(tester), 'Synced to Google Drive');
    expect(c.read(syncProvider).dirty, isEmpty);
    expect(sync.hasChangesToSend, isFalse);
  });

  testWidgets('two clouds on, one from before there was a choice: synced once both have it', (tester) async {
    final store = MemoryBoardStore();
    syncingWith(store, onedrive: true);
    final id = addSavedTo(store, null);
    final c = await pumpCanvas(tester, store: store, notebookId: id, extra: syncOverrides(drive, onedrive: onedrive));
    await syncIn(tester, c);
    await tester.pump();
    expect(notebooksIn(drive), hasLength(1));
    expect(notebooksIn(onedrive), hasLength(1));
    expect(pillStatus(tester), 'Synced to Google Drive and OneDrive');
    expect(c.read(syncProvider.notifier).hasChangesToSend, isFalse);
  });

  testWidgets('deleted for good: once the cloud is told, nothing is waiting', (tester) async {
    final store = MemoryBoardStore();
    syncingWith(store);
    final keep = addSavedTo(store, 'google', title: 'Kept');
    final gone = addSavedTo(store, 'google', title: 'Gone');
    final c = await pumpCanvas(tester, store: store, notebookId: keep, extra: syncOverrides(drive));
    final sync = c.read(syncProvider.notifier);
    await syncIn(tester, c);
    expect(notebooksIn(drive), hasLength(2));
    expect(sync.hasChangesToSend, isFalse);

    await c.read(libraryProvider.notifier).deleteForever(gone);
    expect(sync.hasChangesToSend, isTrue);
    await syncIn(tester, c);
    expect(notebooksIn(drive), hasLength(1));
    expect(c.read(syncProvider).dirty, isEmpty);
    expect(sync.hasChangesToSend, isFalse);
  });
}
