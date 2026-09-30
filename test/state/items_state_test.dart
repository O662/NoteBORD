import 'dart:ui' as ui;

import 'package:endless/board/codec.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/canvas/new_items.dart';
import 'package:endless/library/library.dart';
import 'package:endless/state/assets.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/templates/templates.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

late ui.Image _picture;

/// A container with notebook [id] open (as a screen showing it would).
Future<ProviderContainer> _open(MemoryBoardStore store, String id) async {
  final c = ProviderContainer(overrides: [...await testOverrides(store), decodeAs(_picture)]);
  addTearDown(c.dispose);
  c.listen(loadedNotebookProvider(id), (_, _) {});
  await c.read(loadedNotebookProvider(id).future);
  c.listen(notebookProvider(id), (_, _) {});
  c.listen(settingsProvider, (_, _) {});
  c.listen(libraryProvider, (_, _) {});
  return c;
}

final _at = DateTime.utc(2026, 9, 29, 12);

StrokeItem _line(double y) => strokeFrom([Offset(0, y), Offset(50, y), Offset(100, y)]);

void main() {
  setUpAll(() {
    _picture = testPicture(w: 800, h: 400);
  });
  tearDownAll(() => _picture.dispose());

  group('one undo step', () {
    testWidgets('replace, remove and insert together; undo puts everything back in place', (tester) async {
      final store = MemoryBoardStore();
      final id = addUntitled(store);
      final c = await _open(store, id);
      final n = c.read(notebookProvider(id).notifier);
      final pageId = c.read(notebookProvider(id)).pages[0].id;
      List<Item> items() => c.read(notebookProvider(id)).pages[0].items;
      final a = _line(10), b = _line(20), d = _line(30);
      final note = newSticky(const Offset(300, 300), z: 4, now: _at);
      n.insertItems(pageId, [a, b, note, d]);

      // Like fanning out a stack: the note changes, a stroke goes, two notes arrive right above it.
      final n1 = newSticky(const Offset(600, 300), z: 5, now: _at);
      final n2 = newSticky(const Offset(900, 300), z: 6, now: _at);
      n.edit(pageId, replace: [note.copyWith(color: tokens.stickyColors[1])], remove: [a.id], insert: [n1, n2], insertAt: 2);
      expect(items().map((i) => i.id), [b.id, note.id, n1.id, n2.id, d.id]);
      expect((items()[1] as StickyItem).color, tokens.stickyColors[1]);

      n.undo(pageId);
      expect(items().map((i) => i.id), [a.id, b.id, note.id, d.id]);
      expect((items()[2] as StickyItem).color, tokens.stickyColors[0]);
      n.redo(pageId);
      expect(items().map((i) => i.id), [b.id, note.id, n1.id, n2.id, d.id]);
      n.undo(pageId);

      // Paper goes under everything; the z-order is the order in the list.
      final frame = newFrame(const Offset(400, 100), z: 0, now: _at);
      n.insertItems(pageId, [frame], at: 0);
      expect(items().first.id, frame.id);
      n.undo(pageId);
      expect(items().map((i) => i.id), [a.id, b.id, note.id, d.id]);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('to front and to back keep the moved items in order', (tester) async {
      final store = MemoryBoardStore();
      final id = addUntitled(store);
      final c = await _open(store, id);
      final n = c.read(notebookProvider(id).notifier);
      final pageId = c.read(notebookProvider(id)).pages[0].id;
      List<String> ids() => [for (final i in c.read(notebookProvider(id)).pages[0].items) i.id];
      final s = [for (var i = 0; i < 5; i++) _line(i * 10.0)];
      n.insertItems(pageId, s);

      n.reorder(pageId, [s[3].id, s[1].id], toFront: true);
      expect(ids(), [s[0].id, s[2].id, s[4].id, s[1].id, s[3].id]);
      n.undo(pageId);
      expect(ids(), [for (final x in s) x.id]);

      n.reorder(pageId, [s[2].id, s[4].id], toFront: false);
      expect(ids(), [s[2].id, s[4].id, s[0].id, s[1].id, s[3].id]);
      n.undo(pageId);
      expect(ids(), [for (final x in s) x.id]);
      n.redo(pageId);
      expect(ids().first, s[2].id);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the eraser rubs ink off a sticky note without taking the note', (tester) async {
      final store = MemoryBoardStore();
      final id = addUntitled(store);
      final c = await _open(store, id);
      final n = c.read(notebookProvider(id).notifier);
      final pageId = c.read(notebookProvider(id)).pages[0].id;
      StickyItem note() => c.read(notebookProvider(id)).pages[0].items.whereType<StickyItem>().single;
      final onPage = _line(10);
      final a = strokeFrom([const Offset(250, 280), const Offset(300, 280)]);
      final b = strokeFrom([const Offset(250, 320), const Offset(300, 320)]);
      n.insertItems(pageId, [onPage, newSticky(const Offset(300, 300), z: 2, now: _at).withInk(a).withInk(b)]);

      n.beginErase(pageId);
      n.eraseInk(note().id, {a.id});
      n.erase([onPage.id]);
      n.eraseInk(note().id, {b.id, 'missing'});
      n.eraseInk('missing', {a.id});
      n.endErase();
      expect(note().ink, isEmpty);
      expect(c.read(notebookProvider(id)).pages[0].items, hasLength(1));

      // One drag, one step.
      n.undo(pageId);
      expect(note().ink.map((s) => s.id), [a.id, b.id]);
      expect(c.read(notebookProvider(id)).pages[0].items, hasLength(2));
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('saving', () {
    testWidgets('text, sticky notes, frames and shapes are on disk within a second', (tester) async {
      final store = MemoryBoardStore();
      final id = addUntitled(store);
      final c = await _open(store, id);
      final n = c.read(notebookProvider(id).notifier);
      final pageId = c.read(notebookProvider(id)).pages[0].id;
      n.insertItems(pageId, [
        newFrame(const Offset(400, 100), z: 0, now: _at),
        newSticky(const Offset(900, 300), z: 1, now: _at).withText('Ask in office hours', color: Colors.black, at: _at),
        newStickyStack(const Offset(900, 600), z: 2, now: _at),
        TextItem(id: 'it_text', x: 50, y: 50, z: 3, createdAt: _at, wrap: 480, text: 'Typed', color: Colors.black, autoWidth: true),
        shapeAt(ShapeType.ellipse, const Offset(200, 900), z: 4, now: _at, color: Colors.black, strokeWidth: 2.5),
      ]);
      await tester.pump(const Duration(seconds: 1));

      final saved = decodePage(store.pages[id]![pageId]!);
      expect(saved.items.map((i) => i.type), ['frame', 'sticky', 'sticky', 'text', 'shape']);
      expect((saved.items[1] as StickyItem).text, 'Ask in office hours');
      expect((saved.items[2] as StickyItem).count, 3);
      expect((saved.items[3] as TextItem).text, 'Typed');
      expect((saved.items[4] as ShapeItem).kind, ShapeType.ellipse);
      expect(c.read(notebookProvider(id)).saveStatus, SaveStatus.saved);
    });

    testWidgets('an image’s file goes in assets and the picture on the page; undo takes it off', (tester) async {
      final store = MemoryBoardStore();
      final id = addUntitled(store);
      final c = await _open(store, id);
      final n = c.read(notebookProvider(id).notifier);
      final pageId = c.read(notebookProvider(id)).pages[0].id;
      final png = fakePng();

      final item = (await n.addImage(pageId, png, center: const Offset(640, 400)))!;
      // 800 × 400 fits 480 × 360 at 480 × 240, centered where asked.
      expect(Size(item.w, item.h), const Size(480, 240));
      expect(item.center, const Offset(640, 400));
      expect(item.asset, assetNameFor(png));
      expect(store.assets[id], {item.asset: png});

      await tester.pump(const Duration(seconds: 1));
      final saved = decodePage(store.pages[id]![pageId]!).items.single as ImageItem;
      expect(saved.asset, item.asset);

      n.undo(pageId);
      expect(c.read(notebookProvider(id)).pages[0].items, isEmpty);
      n.redo(pageId);
      expect(c.read(notebookProvider(id)).pages[0].items.single.id, item.id);

      // The same picture twice is stored once.
      await n.addImage(pageId, png, center: const Offset(100, 100));
      expect(store.assets[id], hasLength(1));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a file that isn’t a picture is refused and nothing is stored', (tester) async {
      final store = MemoryBoardStore();
      final id = addUntitled(store);
      final c = ProviderContainer(overrides: [
        ...await testOverrides(store),
        imageDecoderProvider.overrideWithValue((_) async => throw const FormatException('not an image')),
      ]);
      addTearDown(c.dispose);
      c.listen(loadedNotebookProvider(id), (_, _) {});
      await c.read(loadedNotebookProvider(id).future);
      c.listen(notebookProvider(id), (_, _) {});
      final n = c.read(notebookProvider(id).notifier);
      final pageId = c.read(notebookProvider(id)).pages[0].id;
      await expectLater(n.addImage(pageId, fakePng(), center: Offset.zero), throwsFormatException);
      expect(store.assets[id], isNull);
      expect(c.read(notebookProvider(id)).pages[0].items, isEmpty);
    });

    testWidgets('a saved template leaves pictures out (their files stay with the notebook)', (tester) async {
      final store = MemoryBoardStore();
      final id = addUntitled(store);
      final c = await _open(store, id);
      final n = c.read(notebookProvider(id).notifier);
      final page = c.read(notebookProvider(id)).pages[0];
      n.insertItems(page.id, [newSticky(const Offset(300, 300), z: 1, now: _at)]);
      await n.addImage(page.id, fakePng(), center: Offset.zero);
      final t = await c.read(userTemplatesProvider.notifier).saveFromPage(page.page, 'Mine');
      expect(t.items.map((j) => j['type']), ['sticky']);
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('locked pages', () {
    testWidgets('locking a page seals its images; removing the password puts them back', (tester) async {
      final store = storeWith(sampleNotebook());
      final c = await _open(store, 'nb_sample');
      final n = c.read(notebookProvider('nb_sample').notifier);
      final png = fakePng(), other = fakePng(2), gone = fakePng(3);
      final onPage3 = (await n.addImage('pg_03', png, center: Offset.zero))!;
      final onPage1 = (await n.addImage('pg_01', other, center: Offset.zero))!;
      // A picture deleted from the page before it's locked.
      final deleted = (await n.addImage('pg_03', gone, center: Offset.zero))!;
      n.removeItems('pg_03', [deleted.id]);
      Map<String, Object> files() => store.assets['nb_sample']!;
      expect(files().keys.toSet(), {onPage3.asset, onPage1.asset, deleted.asset});

      await n.lockPage('pg_03', 'momentum42');
      // The locked page's picture is only there sealed; the deleted one is gone; page 1's is untouched.
      expect(files().keys.toSet(), {'${onPage3.asset}.enc', onPage1.asset});
      expect(store.assets['nb_sample']!['${onPage3.asset}.enc'], isNot(png));
      expect(String.fromCharCodes(store.assets['nb_sample']!['${onPage3.asset}.enc']!.take(4)), 'EBL1');

      // Unlocked, a new picture on it is sealed from the start.
      expect(await n.unlock('pg_03', 'momentum42'), isTrue);
      final fresh = fakePng(4);
      final added = (await n.addImage('pg_03', fresh, center: Offset.zero))!;
      expect(files().keys.toSet(), {'${onPage3.asset}.enc', '${added.asset}.enc', onPage1.asset});
      expect(await testCrypto.unsealBytes((await testCrypto.open(c.read(notebookProvider('nb_sample')).lockFor('pg_03')!, 'momentum42'))!,
          store.assets['nb_sample']!['${added.asset}.enc']!), fresh);

      await n.removePageLock('pg_03');
      expect(files().keys.toSet(), {onPage3.asset, added.asset, onPage1.asset});
      expect(store.assets['nb_sample']![onPage3.asset], png);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a notebook password seals every image, and they open again with it', (tester) async {
      final store = storeWith(sampleNotebook());
      final c = await _open(store, 'nb_sample');
      final n = c.read(notebookProvider('nb_sample').notifier);
      final a = (await n.addImage('pg_01', fakePng(), center: Offset.zero))!;
      final b = (await n.addImage('pg_03', fakePng(2), center: Offset.zero))!;
      await n.lockNotebook('whole-book');
      expect(store.assets['nb_sample']!.keys.toSet(), {'${a.asset}.enc', '${b.asset}.enc'});

      // Reopened and unlocked, the pictures load from their sealed files.
      final again = await _open(store, 'nb_sample');
      final n2 = again.read(notebookProvider('nb_sample').notifier);
      expect(again.read(notebookProvider('nb_sample')).isSealed('pg_01'), isTrue);
      expect(await n2.unlock('pg_01', 'whole-book'), isTrue);
      final page = again.read(notebookProvider('nb_sample')).pages[0];
      expect(page.items.single, isA<ImageItem>());
      expect(page.images!(a.asset), isNull); // not decoded yet: it loads in the background
      final revision = again.read(notebookProvider('nb_sample')).revision;
      await tester.pump();
      await tester.pump();
      expect(page.images!(a.asset), isNotNull);
      expect(again.read(notebookProvider('nb_sample')).revision, greaterThan(revision)); // and the page repaints

      await n2.removeNotebookLock();
      expect(store.assets['nb_sample']!.keys.toSet(), {a.asset, b.asset});
      await tester.pump(const Duration(seconds: 1));
    });
  });

  test('the tools that drop something aren’t where the app reopens', () {
    for (final tool in [CanvasTool.text, CanvasTool.sticky, CanvasTool.stack, CanvasTool.frame, CanvasTool.shape, CanvasTool.laser]) {
      expect(tool.momentary, isTrue);
      expect(AppSettings.fromJson(AppSettings(tool: tool).toJson()).tool, CanvasTool.pen);
    }
    expect(AppSettings.fromJson(AppSettings(tool: CanvasTool.lasso, shapeKind: ShapeType.arrow).toJson()).shapeKind,
        ShapeType.arrow);
    expect(AppSettings.fromJson(AppSettings(tool: CanvasTool.lasso).toJson()).tool, CanvasTool.lasso);
  });
}
