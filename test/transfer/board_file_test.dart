import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:archive/archive.dart';
import 'package:endless/board/codec.dart';
import 'package:endless/board/lock.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/transfer/board_file.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'everything.dart';

void main() {
  test('round trip: every item type, every page, the lock and the files come back', () async {
    final (store, password) = await everythingNotebook();
    const id = 'nb_board';
    final bytes = await exportBoardFile(store, id);

    final into = MemoryBoardStore();
    final result = await importBoardFile(into, bytes, folder: const ['Imports'], now: testNow);
    expect(result.notebookId, id, reason: 'new to this tablet, it keeps its id (a later import can replace it)');
    expect(result.unreadablePages, 0);

    final before = (await store.loadNotebook(id))!;
    final after = (await into.loadNotebook(result.notebookId))!;
    expect(after.notebook.title, before.notebook.title);
    expect(after.notebook.coverColor, before.notebook.coverColor);
    expect(after.notebook.pageIds, before.notebook.pageIds);
    expect(after.notebook.defaultPaper, Paper.grid);
    expect(after.notebook.createdAt, before.notebook.createdAt);
    expect(after.notebook.extra, before.notebook.extra);
    expect(after.notebook.folderPath, ['Imports']);
    expect(after.notebook.pinned, isFalse);

    // Every clear page is the same, item for item, field for field.
    for (final (i, page) in before.pages.indexed) {
      if (before.sealed.containsKey(page.id)) continue;
      expect(encodePage(after.pages[i]), encodePage(page), reason: 'page ${page.id}');
    }
    final types = {for (final p in after.pages) for (final i in p.items) i.type};
    expect(types, containsAll(['stroke', 'shape', 'text', 'sticky', 'frame', 'image', 'file', 'kanban', 'timeline', 'diagram', 'table', 'embed', 'math']));
    final connector = after.pages.first.items.whereType<StrokeItem>().singleWhere((s) => s.isAttached);
    expect((connector.startItemId, connector.endItemId, connector.arrow?.style), ('it_a', 'it_b', ArrowStyle.filled));
    final stack = after.pages.first.items.whereType<StickyItem>().singleWhere((s) => s.isStack);
    expect(stack.count, 5);
    expect(stack.items.whereType<StrokeItem>(), hasLength(4));

    // The locked page is still sealed, and opens with its password.
    expect(after.sealed.keys, ['pg_secret']);
    expect(after.sealed['pg_secret'], before.sealed['pg_secret']);
    final lock = LockFile.fromJson(after.lock!);
    final key = await testCrypto.open(lock.pages['pg_secret']!, password);
    expect(key, isNotNull);
    expect(decodePage(await testCrypto.unseal(key!, after.sealed['pg_secret']!)).items.single, isA<StrokeItem>());

    // Pictures and the PDF, byte for byte.
    expect((await into.listAssets(result.notebookId)).toSet(), (await store.listAssets(id)).toSet());
    for (final name in await store.listAssets(id)) {
      expect(await into.loadAsset(result.notebookId, name), await store.loadAsset(id, name));
    }

    // And exported again, it's the same file inside.
    final again = await exportBoardFile(into, result.notebookId);
    final x = ZipDecoder().decodeBytes(bytes), y = ZipDecoder().decodeBytes(again);
    expect({for (final f in y.files) f.name}, {for (final f in x.files) f.name});
    for (final f in x.files) {
      if (f.name == 'notebook.json') continue;
      expect(y.findFile(f.name)!.readBytes(), f.readBytes(), reason: f.name);
    }
  });

  test('some pages: only those pages, the files they use and their lock entry', () async {
    final (store, _) = await everythingNotebook();
    final bytes = await exportBoardFile(store, 'nb_board', pageIds: {'pg_pdf'});
    final names = {for (final f in ZipDecoder().decodeBytes(bytes).files) f.name};
    expect(names, contains('pages/pg_pdf.json'));
    expect(names, isNot(contains('pages/pg_board.json')));
    expect(names, isNot(contains('lock.json')), reason: 'the page with a password stayed behind');
    expect(names.where((n) => n.startsWith('assets/')), hasLength(2), reason: 'the PDF and its page picture, not the photo');
    final meta = decodeNotebook(utf8.decode(ZipDecoder().decodeBytes(bytes).findFile('notebook.json')!.readBytes()!));
    expect(meta.pageIds, ['pg_pdf']);

    final locked = {for (final f in ZipDecoder().decodeBytes(await exportBoardFile(store, 'nb_board', pageIds: {'pg_secret'})).files) f.name};
    expect(locked, containsAll(['pages/pg_secret.json.enc', 'lock.json']));
  });

  test('without images the pictures stay out', () async {
    final (store, _) = await everythingNotebook();
    final names = {for (final f in ZipDecoder().decodeBytes(await exportBoardFile(store, 'nb_board', includeAssets: false)).files) f.name};
    expect(names.where((n) => n.startsWith('assets/')), isEmpty);
  });

  group('import refuses or tidies what it shouldn’t trust', () {
    Uint8List zip(Map<String, String> files) {
      final a = Archive();
      for (final e in files.entries) {
        a.addFile(ArchiveFile.string(e.key, e.value));
      }
      return ZipEncoder().encodeBytes(a);
    }

    final meta = encodeNotebook(Notebook(id: 'nb_x', title: 'X', createdAt: everythingAt, updatedAt: everythingAt, pageIds: ['pg_1', '../../evil', 'pg_1']));
    final page = encodePage(BoardPage(id: 'pg_1', items: [strokeFrom([Offset.zero, const Offset(10, 10)])]));

    test('not a zip, or a zip without notebook.json', () async {
      await expectLater(importBoardFile(MemoryBoardStore(), Uint8List.fromList([1, 2, 3]), folder: const [], now: testNow), throwsA(isA<ImportProblem>()));
      await expectLater(importBoardFile(MemoryBoardStore(), zip({'readme.txt': 'hi'}), folder: const [], now: testNow), throwsA(isA<ImportProblem>()));
      await expectLater(importBoardFile(MemoryBoardStore(), zip({'notebook.json': '{"format":"other"}'}), folder: const [], now: testNow), throwsA(isA<ImportProblem>()));
    });

    test('paths that climb out, odd asset names and repeated pages are ignored', () async {
      final store = MemoryBoardStore();
      final result = await importBoardFile(
        store,
        zip({
          'notebook.json': meta,
          'pages/pg_1.json': page,
          'pages/../../evil.json': '{}',
          'assets/../escape.png': 'x',
          'assets/.hidden': 'x',
          'assets/ok.png': 'png',
        }),
        folder: const [],
        now: testNow,
      );
      final loaded = (await store.loadNotebook(result.notebookId))!;
      expect(loaded.notebook.pageIds, ['pg_1']);
      expect(loaded.pages.single.items, hasLength(1));
      expect(await store.listAssets(result.notebookId), ['ok.png']);
    });

    test('a zipped package folder works too, and a damaged page comes in empty', () async {
      final store = MemoryBoardStore();
      final result = await importBoardFile(
        store,
        zip({'Physics.board/notebook.json': meta, 'Physics.board/pages/pg_1.json': '{not json'}),
        folder: const ['School'],
        now: testNow,
      );
      expect(result.unreadablePages, 1);
      final loaded = (await store.loadNotebook(result.notebookId))!;
      expect(loaded.pages.single.items, isEmpty);
      expect(loaded.notebook.folderPath, ['School']);
    });
  });

  group('the same notebook again', () {
    Future<MemoryBoardStore> withPages(List<String> pageIds, {String title = 'Physics'}) async {
      final store = MemoryBoardStore();
      for (final p in pageIds) {
        await store.savePage('nb_same', BoardPage(id: p, items: [
          TextItem(id: 't_$p', x: 0, y: 0, z: 1, createdAt: testNow, wrap: 200, text: '$title $p', color: const Color(0xFF1E1C19)),
        ]));
      }
      await store.saveNotebook(Notebook(id: 'nb_same', title: title, folderPath: const ['From'], createdAt: testNow, updatedAt: testNow, pageIds: pageIds));
      return store;
    }

    test('a notebook already here: keep both gives the copy a new id', () async {
      final store = await withPages(['pg_1']);
      final bytes = await exportBoardFile(store, 'nb_same');
      final copy = await importBoardFile(store, bytes, folder: const [], now: testNow);
      expect(copy.notebookId, isNot('nb_same'));
      expect((await store.listNotebookIds()).toSet(), {'nb_same', copy.notebookId});
      expect(boardFileNotebook(bytes).id, 'nb_same');
    });

    test('replace: the file’s pages, files and flashcard progress, in the notebook’s place', () async {
      final file = await withPages(['pg_1', 'pg_2'], title: 'Physics (backup)');
      await file.saveStudy('nb_same', {'version': 1, 'cards': <String, dynamic>{}});
      await file.saveAsset('nb_same', 'kept.png', Uint8List.fromList([1, 2]));
      final bytes = await exportBoardFile(file, 'nb_same');

      final store = await withPages(['pg_1', 'pg_3']);
      await store.saveAsset('nb_same', 'old.png', Uint8List.fromList([3]));
      await store.saveStudy('nb_same', {'version': 1, 'cards': {'fc_old': <String, dynamic>{}}});
      final result = await importBoardFile(store, bytes, folder: const ['School'], now: testNow, replace: 'nb_same', pinned: true);
      expect(result.notebookId, 'nb_same');
      expect(await store.listNotebookIds(), ['nb_same']);
      final after = (await store.loadNotebook('nb_same'))!;
      expect(after.notebook.title, 'Physics (backup)');
      expect(after.notebook.folderPath, ['School']);
      expect(after.notebook.pinned, isTrue);
      expect([for (final p in after.pages) (p.items.single as TextItem).text], ['Physics (backup) pg_1', 'Physics (backup) pg_2']);
      expect(await store.listAssets('nb_same'), ['kept.png']);
      expect(((await store.loadStudy('nb_same'))?['cards'] as Map?)?.keys ?? const [], isNot(contains('fc_old')));
    });

    test('a damaged file changes nothing', () async {
      final store = await withPages(['pg_1']);
      final bad = ZipEncoder().encodeBytes(Archive()
        ..addFile(ArchiveFile.bytes('notebook.json', utf8.encode(encodeNotebook((await store.loadNotebook('nb_same'))!.notebook))))
        ..addFile(ArchiveFile.bytes('lock.json', utf8.encode('{nope'))));
      await expectLater(
        importBoardFile(store, Uint8List.fromList(bad), folder: const [], now: testNow, replace: 'nb_same'),
        throwsA(isA<ImportProblem>()),
      );
      expect((await store.loadNotebook('nb_same'))!.pages.single.items, hasLength(1));
    });
  });
}
