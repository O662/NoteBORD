// Update 04: the Version history screen (History.png, History-naming.png)
// and how long versions are kept.
import 'dart:convert';
import 'dart:typed_data';

import 'package:endless/board/codec.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/canvas/clusters.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/sync/versions.dart';
import 'package:endless/ui/canvas/version_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

Uint8List _bytes(BoardPage p) => Uint8List.fromList(utf8.encode(encodePage(p)));

void main() {
  setUpAll(loadAppFonts);

  group('keeping versions', () {
    test('unnamed versions go after the days set; named ones stay', () async {
      final store = MemoryBoardStore();
      var now = DateTime.utc(2026, 9, 1, 9);
      var days = 30;
      final versions = VersionStore(store, clock: () => now, keepDays: () => days);
      Future<void> keep(int n) => versions.keep('nb', 'pg', _bytes(BoardPage(id: 'pg', title: 'v$n')), reason: VersionReason.edit);

      await keep(1);
      final first = (await versions.list('nb', 'pg')).single;
      await versions.setLabel('nb', 'pg', first.name, 'Before the midterm');
      now = now.add(const Duration(days: 2));
      await keep(2);
      expect((await versions.list('nb', 'pg')).map((v) => v.label), [null, 'Before the midterm']);

      // 40 days on: the unnamed one has gone, the named one is there.
      now = now.add(const Duration(days: 40));
      await keep(3);
      final left = await versions.list('nb', 'pg');
      expect(left, hasLength(2));
      expect(left.last.label, 'Before the midterm');
      expect(left.first.at, now);

      // 7 days: a version 8 days old goes at the next keep.
      days = 7;
      now = now.add(const Duration(days: 8));
      await keep(4);
      expect((await versions.list('nb', 'pg')).where((v) => v.label == null), hasLength(1));

      // A name taken away: it goes like the others.
      await versions.setLabel('nb', 'pg', first.name, '');
      expect((await versions.list('nb', 'pg')).where((v) => v.label != null), isEmpty);
    });

    test('Settings: 7, 30 or 90 days', () {
      expect(AppSettings().versionDays, 30);
      expect(AppSettings().withPref('versionDays', 0).versionDays, 7);
      expect(AppSettings().withPref('versionDays', 2).versionDays, 90);
    });
  });

  group('what changed', () {
    test('summaries and clusters', () {
      final a = strokeFrom([const Offset(0, 0), const Offset(20, 0)]);
      final b = strokeFrom([const Offset(30, 0), const Offset(50, 0)]);
      final far = strokeFrom([const Offset(600, 600), const Offset(620, 600)]);
      final before = BoardPage(id: 'p', items: [a]);
      final after = BoardPage(id: 'p', items: [b, far]);
      final (:added, :removed) = itemChanges(before, after);
      expect(added.map((i) => i.id), [b.id, far.id]);
      expect(removed.map((i) => i.id), [a.id]);
      expect(changeSummary(added, removed), '+2 strokes · −1 stroke');
      expect(changeSummary(const [], const []), isNull);
      // Near ones are one box; a far one its own.
      expect(clusterRects([a.bounds, b.bounds, far.bounds]), hasLength(2));
    });
  });

  testWidgets('the screen: by day, Show changes, name a version, Named only, save as a new page', (tester) async {
    final store = MemoryBoardStore();
    final id = addUntitled(store);
    final c = await pumpCanvas(tester, store: store, notebookId: id);
    final nb = c.read(notebookProvider(id).notifier);
    final pageId = shownPage(c).id;
    final first = strokeFrom([const Offset(10, 10), const Offset(60, 30)]);
    nb.addStroke(pageId, first);
    await tester.pump(NotebookNotifier.saveDelay);
    await tester.pump(const Duration(milliseconds: 20));
    // A second version 11 minutes on (versions are kept at most every 10).
    final versions = VersionStore(store, clock: () => testNow.toUtc().add(const Duration(minutes: 11)));
    final second = strokeFrom([const Offset(300, 300), const Offset(360, 330)]);
    await tester.runAsync(() => versions.keep(id, pageId, _bytes(BoardPage(id: pageId, items: [first, second])),
        reason: VersionReason.sync, device: 'Kim’s phone'));
    // Now the first stroke is erased.
    nb.removeItems(pageId, [first.id]);
    await tester.pump(NotebookNotifier.saveDelay);

    await tester.tap(byLabel('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Version history'));
    await tester.pumpAndSettle();
    expect(find.text('Version history'), findsOneWidget);
    expect(find.text('All versions'), findsOneWidget);
    expect(find.text('2 VERSIONS'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Before changes from Kim’s phone · +1 stroke'), findsOneWidget);
    expect(find.text('First notes on this page'), findsOneWidget);
    expect(find.text('Added in this version'), findsOneWidget);
    expect(find.text('Erased later'), findsOneWidget);
    expect(find.textContaining('kept for 30 days'), findsWidgets);

    // Name the picked (newest) version.
    await tester.tap(find.text('Name this version'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Before the midterm');
    await tester.tap(find.text('Save name'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Before the midterm'), findsOneWidget);
    await tester.tap(find.text('Named only'));
    await tester.pump();
    expect(find.text('1 VERSION'), findsOneWidget);
    await tester.tap(find.text('All versions'));
    await tester.pump();

    // Save as a new page: after this one, with the version's ink, new ids.
    final pages = c.read(notebookProvider(id)).pages.length;
    await tester.tap(find.text('Save as a new page'));
    await tester.pumpAndSettle();
    final now = c.read(notebookProvider(id));
    expect(now.pages, hasLength(pages + 1));
    final copy = now.pages[now.indexOf(pageId) + 1].page;
    expect(copy.items, hasLength(2));
    expect(copy.items.map((i) => i.id), isNot(contains(first.id)));
    expect(find.textContaining('as page 2'), findsOneWidget);
  });

  testWidgets('portrait: the list goes under the preview', (tester) async {
    final store = MemoryBoardStore();
    final id = addUntitled(store);
    final c = await pumpCanvas(tester, store: store, notebookId: id, size: portraitSize);
    final nb = c.read(notebookProvider(id).notifier);
    nb.addStroke(shownPage(c).id, strokeFrom([const Offset(10, 10), const Offset(60, 30)]));
    await tester.pump(NotebookNotifier.saveDelay);
    await tester.tap(byLabel('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Version history'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(VersionHistoryScreen), findsOneWidget);
  });
}
