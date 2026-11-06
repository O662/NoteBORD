import 'dart:async';
import 'dart:io';

import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/sync/cloud.dart';
import 'package:endless/sync/doc.dart';
import 'package:endless/sync/sync_state.dart';
import 'package:endless/ui/routes.dart';
import 'package:endless/ui/settings/settings_screen.dart' show SyncSwitch;
import 'package:endless/video/video_files.dart' show videosDirProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'sync_app_helpers.dart';

void main() {
  late MemoryCloud cloud;

  setUp(() => cloud = MemoryCloud());

  /// Syncs [c] now, pumping until it's done (everything here is in memory,
  /// so it runs in the test's fake time).
  Future<void> syncIn(WidgetTester tester, ProviderContainer c) async {
    var done = false;
    unawaited(c.read(syncProvider.notifier).syncNow().whenComplete(() => done = true));
    for (var i = 0; i < 200 && !done; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(done, isTrue, reason: 'sync didn’t finish');
  }

  /// A Sync & backup switch, by its label.
  Finder switchFor(String label) => find.byWidgetPredicate((w) => w is SyncSwitch && w.label == label);

  /// The text after "Page 1 of 1 · " in the title pill.
  String pillStatus(WidgetTester tester) {
    final t = find.textContaining('Page 1 of 1 · ').evaluate().single.widget as Text;
    return t.data!.split(' · ').skip(1).join(' · ');
  }

  testWidgets('Settings › Sync & backup: connect Google Drive, Sync now, the status everywhere', (tester) async {
    final store = MemoryBoardStore();
    addUntitled(store);
    final c = await pumpApp(tester, store: store, extra: syncOverrides(cloud));
    // Not set up: the sidebar says so.
    expect(find.text('Saved on this tablet'), findsOneWidget);
    expect(find.text('Sync isn’t set up'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel(RegExp('^Saved on this tablet')));
    await tester.pumpAndSettle();
    expect(find.text('Sync & backup'), findsWidgets);
    expect(find.text('Notebooks are saved on this tablet first, then copied to your cloud. You can keep writing offline.'), findsOneWidget);
    expect(find.text('Not connected.'), findsNWidgets(2));

    await tester.tap(find.bySemanticsLabel('Connect Google Drive'));
    await tester.pumpAndSettle();
    final s = c.read(syncProvider);
    expect(s.settings.google.on, isTrue);
    expect(s.settings.google.account!.email, 'kim@example.com');
    expect(s.settings.device, isNotEmpty);
    // Connecting synced: the notebook is in the cloud.
    expect(cloud.files.keys.where((k) => k.endsWith('/notebook.json')), hasLength(1));
    expect(find.textContaining('Connected · saving to “Endless Notebooks” · synced'), findsOneWidget);
    expect(find.text('Not connected. Turn on both to keep a copy in each.'), findsOneWidget);

    // What gets synced: switches.
    await tester.tap(switchFor('Also save a PDF copy of each notebook'));
    await tester.pump();
    expect(c.read(syncProvider).settings.pdfCopy, isTrue);
    await tester.tap(switchFor('Only sync on Wi-Fi'));
    await tester.pump();
    expect(c.read(syncProvider).settings.wifiOnly, isFalse);
    // Kept on this device.
    expect((await store.loadSyncFile('settings'))!['wifiOnly'], isFalse);

    // The conflict policy.
    await tester.tap(find.byType(PopupMenuButton<MergePolicy>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep the newest').last);
    await tester.pumpAndSettle();
    expect(c.read(syncProvider).settings.policy, MergePolicy.newestWins);

    // Turned off: the switch, then Sync now is off too.
    await tester.tap(switchFor('Sync with Google Drive'));
    await tester.pumpAndSettle();
    expect(c.read(syncProvider).settings.google.on, isFalse);
    expect(find.textContaining('kim@example.com · turned off'), findsOneWidget);
  });

  testWidgets('connecting without the client id in the build says what\'s missing', (tester) async {
    await pumpApp(tester, location: Routes.settings(), extra: syncOverrides(cloud, notReady: 'Google sign-in isn’t set up in this version of Endless yet.'));
    await tester.tap(find.bySemanticsLabel('Connect Google Drive'));
    await tester.pumpAndSettle();
    expect(find.text('Can’t connect Google Drive'), findsOneWidget);
    expect(find.text('Google sign-in isn’t set up in this version of Endless yet.'), findsOneWidget);
  });

  testWidgets('the title pill with no cloud: Saved on this tablet', (tester) async {
    await pumpCanvas(tester, store: MemoryBoardStore(), extra: syncOverrides(cloud));
    expect(pillStatus(tester), 'Saved on this tablet');
  });

  testWidgets('the title pill: Saved, Synced to Google Drive, Saving…, Saved, Synced', (tester) async {
    final store = MemoryBoardStore();
    syncingWithGoogle(store);
    final id = addUntitled(store);
    final c = await pumpCanvas(tester, store: store, notebookId: id, extra: syncOverrides(cloud));
    expect(pillStatus(tester), 'Saved');
    await syncIn(tester, c);
    await tester.pump();
    expect(pillStatus(tester), 'Synced to Google Drive');

    // Writing: Saving…, then Saved (waiting to sync), then synced again.
    c.read(notebookProvider(id).notifier).addStroke(shownPage(c).id, strokeFrom([const Offset(10, 10), const Offset(80, 40)]));
    await tester.pump();
    expect(pillStatus(tester), 'Saving…');
    await tester.pump(NotebookNotifier.saveDelay);
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();
    expect(pillStatus(tester), 'Saved');
    await syncIn(tester, c);
    await tester.pump();
    expect(pillStatus(tester), 'Synced to Google Drive');
  });

  testWidgets('only on Wi-Fi: on mobile data it waits, and the sidebar says so', (tester) async {
    final store = MemoryBoardStore();
    syncingWithGoogle(store);
    addUntitled(store);
    final c = await pumpApp(tester, store: store, extra: syncOverrides(cloud, unmetered: false));
    await syncIn(tester, c);
    await tester.pump();
    expect(c.read(syncProvider).phase, SyncPhase.waitingForWifi);
    expect(cloud.files, isEmpty);
    expect(find.text('Waiting for Wi-Fi'), findsOneWidget);
    // The cover says the notebook hasn't gone yet.
    await tester.tap(find.text('See all notebooks'));
    await tester.pumpAndSettle();
    expect(find.text('Waiting to sync'), findsWidgets);
  });

  testWidgets('offline: said in the sidebar; nothing sent', (tester) async {
    final store = MemoryBoardStore();
    syncingWithGoogle(store);
    addUntitled(store);
    final c = await pumpApp(tester, store: store, extra: syncOverrides(cloud, online: false));
    await syncIn(tester, c);
    await tester.pump();
    expect(find.text('Offline'), findsOneWidget);
    // The sidebar card, and the Continue writing cover's badge.
    expect(find.text('Waiting to sync'), findsNWidgets(2));
    expect(cloud.files, isEmpty);
  });

  testWidgets('signed out: said in the sidebar; nothing lost', (tester) async {
    final store = MemoryBoardStore();
    syncingWithGoogle(store);
    addUntitled(store);
    final c2 = await pumpApp(tester, store: store, extra: syncOverrides(cloud));
    cloud.failing = CloudFailure.signedOut;
    await syncIn(tester, c2);
    await tester.pump();
    expect(c2.read(syncProvider).phase, SyncPhase.signedOut);
    expect(find.text('Sign in again'), findsOneWidget);
    expect(await store.listNotebookIds(), hasLength(1));
  });

  testWidgets('synced just now: the sidebar card', (tester) async {
    final store = MemoryBoardStore();
    syncingWithGoogle(store);
    addUntitled(store);
    final c = await pumpApp(tester, store: store, extra: syncOverrides(cloud));
    await syncIn(tester, c);
    await tester.pump();
    expect(find.text('Synced · Google Drive'), findsOneWidget);
    expect(find.text('Just now'), findsOneWidget);
  });

  testWidgets('two tablets with the notebook open: strokes from each show on the other, as they write', (tester) async {
    // Tablet A makes a notebook and syncs it; tablet B gets it.
    final storeA = MemoryBoardStore(), storeB = MemoryBoardStore();
    syncingWithGoogle(storeA, device: 'dv_a');
    syncingWithGoogle(storeB, device: 'dv_b');
    final id = addUntitled(storeA);
    final a = ProviderContainer(overrides: [...await testOverrides(storeA), ...syncOverrides(cloud)]);
    final b = ProviderContainer(overrides: [...await testOverrides(storeB), ...syncOverrides(cloud)]);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await syncIn(tester, a);
    await syncIn(tester, b);
    expect(await storeB.loadNotebookMeta(id), isNotNull);

    // Both open it.
    Future<NotebookNotifier> open(ProviderContainer c) async {
      c.listen(loadedNotebookProvider(id), (_, _) {});
      await c.read(loadedNotebookProvider(id).future);
      c.listen(notebookProvider(id), (_, _) {});
      return c.read(notebookProvider(id).notifier);
    }

    final na = await open(a);
    final nb = await open(b);
    final pageId = a.read(notebookProvider(id)).pages.first.id;
    final s1 = strokeFrom([const Offset(10, 10), const Offset(60, 30)]);
    final s2 = strokeFrom([const Offset(100, 10), const Offset(160, 30)]);
    na.addStroke(pageId, s1);
    nb.addStroke(pageId, s2);
    await syncIn(tester, a);
    await syncIn(tester, b);
    await syncIn(tester, a);
    Set<String> ids(ProviderContainer c) => {for (final i in c.read(notebookProvider(id)).pages.first.items) i.id};
    expect(ids(a), {s1.id, s2.id});
    expect(ids(b), {s1.id, s2.id});
    // B's own stroke is still B's to undo; A's arrived without an undo step.
    expect(nb.canUndo(pageId), isFalse);
    // And it's on B's disk.
    await nb.flush();
    await tester.pump(const Duration(milliseconds: 20));
    expect({for (final i in (await storeB.loadNotebook(id))!.pages.first.items) i.id}, {s1.id, s2.id});

    // Erased on A: gone from B's open notebook too.
    na.removeItems(pageId, [s2.id]);
    await syncIn(tester, a);
    await syncIn(tester, b);
    expect(ids(b), {s1.id});
  });

  testWidgets('Version history: earlier versions of the page, a preview, Restore, Undo', (tester) async {
    final store = MemoryBoardStore();
    final id = addUntitled(store);
    final c = await pumpCanvas(tester, store: store, notebookId: id);
    final nb = c.read(notebookProvider(id).notifier);
    final pageId = shownPage(c).id;
    final first = strokeFrom([const Offset(10, 10), const Offset(60, 30)]);
    nb.addStroke(pageId, first);
    await tester.pump(NotebookNotifier.saveDelay);
    await tester.pump(const Duration(milliseconds: 20));
    // Then a page that looks quite different.
    nb.removeItems(pageId, [first.id]);
    nb.addStroke(pageId, strokeFrom([const Offset(300, 300), const Offset(400, 380)]));
    await tester.pump(NotebookNotifier.saveDelay);
    await tester.pump(const Duration(milliseconds: 20));

    await tester.tap(byLabel('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Version history'));
    await tester.pumpAndSettle();
    expect(find.text('Version history'), findsWidgets);
    expect(find.text('While writing'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Restore this version'));
    await tester.pumpAndSettle();
    expect([for (final i in shownPage(c).items) i.id], [first.id]);
    expect(find.textContaining('Restored the version from'), findsOneWidget);
    // One undo step puts the page back.
    nb.undo(pageId);
    expect(shownPage(c).items.single.id, isNot(first.id));
    // The page as it was before the restore is kept too.
    final versions = await nb.versionsOf(pageId);
    expect(versions.map((v) => v.reason.name), contains('restore'));
  });

  testWidgets('a big video goes to the cloud with its card, and the page keeps a link', (tester) async {
    final videos = (await tester.runAsync(() => Directory.systemTemp.createTemp('endless_videos_')))!;
    addTearDown(() => videos.delete(recursive: true));
    final file = File('${videos.path}${Platform.pathSeparator}vid_test.mp4');
    await tester.runAsync(() => file.writeAsBytes(List.filled(2048, 7)));
    final store = MemoryBoardStore();
    syncingWithGoogle(store);
    final id = addUntitled(store);
    final c = await pumpCanvas(tester, store: store, notebookId: id, extra: [
      ...syncOverrides(cloud),
      videosDirProvider.overrideWithValue(() async => videos),
    ]);
    final pageId = shownPage(c).id;
    final video = VideoItem(
      id: 'it_video',
      x: 0,
      y: 0,
      z: 1,
      createdAt: testNow.toUtc(),
      link: 'vid_test.mp4',
      name: 'lab-trial-2.mov',
      durationMs: 65000,
    );
    c.read(notebookProvider(id).notifier).insertItems(pageId, [video]);
    late Future<void> moving;
    await tester.runAsync(() async {
      moving = c.read(syncProvider.notifier).moveVideo(id, video.id);
      // The card shows while it goes.
      for (var i = 0; i < 200 && c.read(syncProvider).uploads.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await tester.pump();
    expect(find.textContaining('Uploading to Google Drive'), findsOneWidget);
    expect(find.text('lab-trial-2.mov'), findsOneWidget);
    await tester.runAsync(() => moving);
    await tester.pump();
    expect(find.textContaining('Uploading to Google Drive'), findsNothing);
    expect(cloud.files.keys, contains('Videos/vid_test.mp4'));
    final now = shownPage(c)[video.id]! as VideoItem;
    expect(now.cloud!.kind, 'google');
    expect(now.cloud!.path, 'Videos/vid_test.mp4');
    expect(now.link, 'vid_test.mp4');
    // Moved: this device keeps it only in the cache (fetched again from
    // there, or the cloud, to play).
    expect(file.existsSync(), isFalse);
    expect(File('${videos.path}${Platform.pathSeparator}cloud${Platform.pathSeparator}vid_test.mp4').existsSync(), isTrue);
  });
}
