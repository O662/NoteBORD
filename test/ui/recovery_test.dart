// Update 04e: crash recovery (Recovery.png) and the conflict screen
// (Conflict.png).
import 'dart:convert';
import 'dart:typed_data';

import 'package:endless/board/codec.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/state/bootstrap.dart';
import 'package:endless/state/changes.dart' show versionStoreProvider;
import 'package:endless/state/journal.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/sync/conflicts.dart';
import 'package:endless/sync/versions.dart';
import 'package:endless/transfer/files.dart';
import 'package:endless/ui/canvas/conflict_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// A journal line for [item] on page [pageId].
String _line(String pageId, Item item, {int t = 1790000000000}) =>
    '${jsonEncode({'t': t, 'page': pageId, 'item': jsonDecode(item.encoded)})}\n';

List<Item> _items(ProviderContainer c, String pageId) {
  final nb = c.read(notebookProvider('nb_sample'));
  return nb.pages[nb.indexOf(pageId)].items;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

void main() {
  setUpAll(loadAppFonts);

  group('the journal', () {
    test('a line cut off by a crash is skipped', () {
      final a = strokeFrom([const Offset(0, 0), const Offset(10, 0)]);
      final text = '${_line('pg_1', a)}{"t": 17900, "page": "pg_1", "item": {"id": "st_';
      final entries = StrokeJournal.parse(text);
      expect(entries.single.item.id, a.id);
      expect(entries.single.pageId, 'pg_1');
    });

    testWidgets('strokes are journaled as they’re written, and the journal goes once they’re saved', (tester) async {
      final store = storeWith(sampleNotebook());
      final c = await pumpCanvas(tester, store: store, notebookId: 'nb_sample');
      final nb = c.read(notebookProvider('nb_sample').notifier);
      final pageId = shownPage(c).id;
      final s = strokeFrom([const Offset(100, 100), const Offset(160, 120)]);
      nb.addStroke(pageId, s);
      await tester.pump();
      expect(store.journals['nb_sample'], contains(s.id));
      await tester.pump(NotebookNotifier.saveDelay);
      await tester.pump(const Duration(milliseconds: 50));
      expect(store.journals['nb_sample'], isNull);
    });

    testWidgets('never for a page with a password', (tester) async {
      final store = storeWith(sampleNotebook());
      final c = await pumpCanvas(tester, store: store, notebookId: 'nb_sample');
      final nb = c.read(notebookProvider('nb_sample').notifier);
      final pageId = shownPage(c).id;
      var locked = false;
      nb.lockPage(pageId, 'secret').then((_) => locked = true);
      await settleReal(tester, () => locked);
      nb.addStroke(pageId, strokeFrom([const Offset(100, 100), const Offset(160, 120)]));
      await tester.pump();
      expect(store.journals['nb_sample'] ?? '', isEmpty);
    });

    test('at launch, the notebook with a journal opens first', () async {
      final store = storeWith(sampleNotebook());
      await store.appendJournal('nb_sample', _line('pg_01', strokeFrom([const Offset(0, 0), const Offset(9, 9)])));
      final overrides = await bootstrap(store);
      final c = ProviderContainer(overrides: overrides);
      addTearDown(c.dispose);
      expect(c.read(initialRecoveryProvider), 'nb_sample');
    });
  });

  testWidgets('after a crash: the lost strokes come back, with the card, Undo restore and a crash report', (tester) async {
    final nb = sampleNotebook();
    final target = nb.pages.firstWhere((p) => p.items.isNotEmpty);
    final pageId = target.id;
    final saved = target.items.first;
    final lost1 = strokeFrom([const Offset(400, 600), const Offset(500, 610)]);
    final lost2 = strokeFrom([const Offset(520, 600), const Offset(600, 612)]);
    final store = storeWith(nb);
    // The journal has one stroke the page already has, and two it doesn't.
    await store.appendJournal('nb_sample', _line(pageId, saved) + _line(pageId, lost1) + _line(pageId, lost2));
    final files = FakeFileTransfer();
    final c = await pumpCanvas(tester, store: store, notebookId: 'nb_sample', extra: [fileTransferProvider.overrideWithValue(files)]);
    await _settle(tester);

    final items = {for (final i in _items(c, pageId)) i.id};
    expect(items, containsAll([lost1.id, lost2.id]));
    expect(_items(c, pageId).where((i) => i.id == saved.id), hasLength(1), reason: 'not twice');
    expect(find.text('We brought back your last strokes'), findsOneWidget);
    expect(find.text('2 strokes'), findsOneWidget);
    expect(find.text('1 line of writing'), findsOneWidget);
    expect(find.text('Lost: about 2 seconds'), findsOneWidget);
    expect(find.text('Hide highlights'), findsOneWidget);

    await tester.tap(find.text('Undo restore'));
    await _settle(tester);
    expect({for (final i in _items(c, pageId)) i.id}, isNot(contains(lost1.id)));
    await tester.tap(find.text('Redo restore'));
    await _settle(tester);
    expect({for (final i in _items(c, pageId)) i.id}, contains(lost1.id));

    await tester.tap(find.text('Hide highlights'));
    await _settle(tester);
    expect(find.text('Show what came back'), findsOneWidget);

    // The report is opt-in, and never has notes in it.
    await tester.tap(find.bySemanticsLabel('Send an anonymous crash report (no notes or handwriting)'));
    await tester.tap(find.text('Keep writing'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await _settle(tester);
    expect(find.text('We brought back your last strokes'), findsNothing);
    final report = utf8.decode(files.shared.single.bytes);
    expect(files.shared.single.name, 'endless-crash-report.txt');
    expect(report, contains('Strokes brought back: 2'));
    expect(report, isNot(contains('Physics')));
    expect(report, isNot(contains('Momentum')));

    // Saved, the journal is gone.
    await tester.pump(const Duration(seconds: 1));
    expect(store.journals['nb_sample'], isNull);
  });

  testWidgets('a journal with nothing new is just cleared', (tester) async {
    final nb = sampleNotebook();
    final store = storeWith(nb);
    final target = nb.pages.firstWhere((p) => p.items.isNotEmpty);
    await store.appendJournal('nb_sample', _line(target.id, target.items.first));
    await pumpCanvas(tester, store: store, notebookId: 'nb_sample');
    await _settle(tester);
    expect(find.text('We brought back your last strokes'), findsNothing);
    expect(store.journals['nb_sample'], isNull);
  });

  group('pages to check', () {
    Future<(ProviderContainer, String, Item, Item)> setUpConflict(WidgetTester tester, MemoryBoardStore store) async {
      final c = await pumpCanvas(tester, store: store, notebookId: 'nb_sample');
      canvasPane.goTo(2);
      await _settle(tester);
      final page = shownPage(c).page;
      final ours = strokeFrom([const Offset(100, 500), const Offset(200, 520)]);
      final theirs = strokeFrom([const Offset(500, 500), const Offset(600, 520)]);
      Uint8List bytes(BoardPage p) => Uint8List.fromList(utf8.encode(encodePage(p)));
      final versions = c.read(versionStoreProvider);
      final (o, t) = (await tester.runAsync(() async {
        final o = await versions.keep('nb_sample', page.id, bytes(BoardPage(id: page.id, items: [...page.items, ours])),
            reason: VersionReason.sync, device: 'Kim’s phone');
        final t = await versions.keep('nb_sample', page.id, bytes(BoardPage(id: page.id, items: [...page.items, theirs])),
            reason: VersionReason.remote, device: 'Kim’s phone');
        return (o!, t!);
      }))!;
      // The merge, as sync left it: both.
      c.read(notebookProvider('nb_sample').notifier).insertItems(page.id, [ours, theirs]);
      await tester.runAsync(() => c.read(conflictsProvider.notifier).add(PageConflict(
            notebookId: 'nb_sample',
            pageId: page.id,
            device: 'Kim’s phone',
            theirsAt: testNow.toUtc().subtract(const Duration(minutes: 30)),
            oursAt: testNow.toUtc().subtract(const Duration(minutes: 5)),
            ours: o,
            theirs: t,
          )));
      await _settle(tester);
      return (c, page.id, ours as Item, theirs as Item);
    }

    testWidgets('the chip opens the page; Keep the phone’s takes its version, with Undo', (tester) async {
      final store = storeWith(sampleNotebook());
      final (c, pageId, ours, theirs) = await setUpConflict(tester, store);
      expect(find.text('1 page to check'), findsOneWidget);
      await tester.tap(find.text('1 page to check'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await _settle(tester);
      expect(find.byType(ConflictScreen), findsOneWidget);
      expect(find.text('This page changed on two devices'), findsOneWidget);
      expect(find.text('1 of 1 page to check'), findsOneWidget);
      expect(find.text('This tablet'), findsOneWidget);
      expect(find.text('Kim’s phone'), findsOneWidget);
      expect(find.text('Only here: 1 stroke'), findsNWidgets(2));
      expect(find.text('Merge and continue'), findsOneWidget);
      expect(find.text('Keep the phone’s'), findsOneWidget);

      await tester.tap(find.text('Keep the phone’s'));
      await tester.pump();
      expect(find.text('Keep and continue'), findsOneWidget);
      await tester.tap(find.text('Keep and continue'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await _settle(tester);
      final ids = {for (final i in _items(c, pageId)) i.id};
      expect(ids, contains(theirs.id));
      expect(ids, isNot(contains(ours.id)));
      expect(c.read(conflictsProvider), isEmpty);
      expect(find.text('1 page to check'), findsNothing);
      expect(find.text('Kept the phone’s version'), findsOneWidget);
      c.read(notebookProvider('nb_sample').notifier).undo(pageId);
      expect({for (final i in _items(c, pageId)) i.id}, containsAll([ours.id, theirs.id]));
    });

    testWidgets('Keep both as pages: this tablet’s here, the phone’s right after', (tester) async {
      final store = storeWith(sampleNotebook());
      final (c, pageId, ours, theirs) = await setUpConflict(tester, store);
      final pages = c.read(notebookProvider('nb_sample')).pages.length;
      await tester.tap(find.text('1 page to check'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await _settle(tester);
      await tester.tap(find.text('Keep both as pages'));
      await tester.pump();
      await tester.tap(find.text('Keep and continue'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await _settle(tester);
      final nb = c.read(notebookProvider('nb_sample'));
      expect(nb.pages, hasLength(pages + 1));
      final here = nb.pages[nb.indexOf(pageId)].page;
      final next = nb.pages[nb.indexOf(pageId) + 1].page;
      expect({for (final i in here.items) i.id}, contains(ours.id));
      expect({for (final i in here.items) i.id}, isNot(contains(theirs.id)));
      expect(next.items, hasLength(here.items.length), reason: 'a copy of the phone’s, new ids');
      expect(next.title, contains('Kim’s phone'));
    });

    testWidgets('Decide later keeps the merge and the chip; Merge both just clears it', (tester) async {
      final store = storeWith(sampleNotebook());
      final (c, pageId, ours, theirs) = await setUpConflict(tester, store);
      await tester.tap(find.text('1 page to check'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await _settle(tester);
      await tester.tap(find.text('Decide later'));
      await _settle(tester);
      expect(find.text('1 page to check'), findsOneWidget);
      expect({for (final i in _items(c, pageId)) i.id}, containsAll([ours.id, theirs.id]));

      await tester.tap(find.text('1 page to check'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await _settle(tester);
      await tester.tap(find.text('Merge and continue'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await _settle(tester);
      expect(find.text('1 page to check'), findsNothing);
      expect({for (final i in _items(c, pageId)) i.id}, containsAll([ours.id, theirs.id]));
      // Saved on this tablet: still gone after a restart.
      expect((await tester.runAsync(() => store.loadSyncFile('conflicts')))!['pages'], isEmpty);
    });

    test('device names', () {
      expect(shortDevice('Kim’s phone'), 'the phone');
      expect(shortDevice("Sam's tablet"), 'the tablet');
      expect(shortDevice('Pixel 8'), 'Pixel 8');
    });
  });
}
