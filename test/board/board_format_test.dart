import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:endless/board/codec.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  group('.board codec', () {
    test('strokes round trip, rounded to 0.1 px, relative to the item origin', () {
      final s = strokeFrom([const Offset(100.04, 200.06), const Offset(150.123, 180.987)],
          pressure: (i) => i == 0 ? 0.12345 : 0.9);
      final page = BoardPage(id: 'pg_1', items: [s]);
      final json = jsonDecode(encodePage(page)) as Map<String, dynamic>;
      final item = (json['items'] as List).single as Map<String, dynamic>;

      expect(item['type'], 'stroke');
      expect(item['x'], 100.0);
      expect(item['y'], 181.0);
      expect(item['points'], [
        [0.0, 19.1, 0.123, 0],
        [50.1, 0.0, 0.9, 8],
      ]);
      expect(item['color'], '#1E1C19');

      final back = decodePage(encodePage(page)).items.single as StrokeItem;
      expect(back.id, s.id);
      expect(back.pagePoints.first.dx, closeTo(100.0, 0.001));
      expect(back.pagePoints.last.dy, closeTo(181.0, 0.001));
      expect(back.color, s.color);
      expect(back.tool, InkTool.pen);
    });

    test('unknown item types and fields survive a load and save', () {
      const source = '''
{"id":"pg_9","title":"From a newer app","paper":"grid","template":{"kind":"cornell"},"locked":false,
 "futureField":{"a":1},
 "items":[
  {"id":"it_1","type":"hologram","x":10,"y":20,"rotation":0,"z":1,"createdAt":"2026-09-01T00:00:00.000Z",
   "author":"user_x","remember":null,"w":200,"h":180,"color":"#FBEFC4","items":[],"depth":{"layers":3}},
  {"id":"it_2","type":"stroke","x":0,"y":0,"rotation":0,"z":2,"createdAt":"2026-09-01T00:00:00.000Z",
   "author":"user_x","remember":{"why":"exam","remindAt":null,"flashcard":false},
   "tool":"pen","color":"#2B5A8C","width":2.5,"points":[[0,0,0.5,0],[10,5,0.6,8]],
   "arrow":{"end":true,"style":"open"},"straightened":"line"}
 ]}''';
      final page = decodePage(source);
      expect(page.paper, Paper.grid);
      expect(page.items[0], isA<UnknownItem>());
      expect(page.items[1], isA<StrokeItem>());

      final again = jsonDecode(encodePage(page)) as Map<String, dynamic>;
      final original = jsonDecode(source) as Map<String, dynamic>;
      expect(again['futureField'], original['futureField']);
      expect(again['template'], original['template']);
      final items = again['items'] as List;
      expect(items[0], (original['items'] as List)[0]);
      final stroke = items[1] as Map<String, dynamic>;
      expect(stroke['arrow'], {'end': true, 'style': 'open'});
      expect(stroke['straightened'], 'line');
      expect(stroke['remember'], {'why': 'exam', 'remindAt': null, 'flashcard': false});
      expect(stroke['author'], 'user_x');
    });

    test('notebook.json carries the format marker and keeps unknown fields', () {
      final nb = sampleNotebook().notebook..extra['sync'] = {'drive': 'abc'};
      final json = jsonDecode(encodeNotebook(nb)) as Map<String, dynamic>;
      expect(json['format'], 'endless.board');
      expect(json['version'], 1);
      expect(json['pages'], ['pg_01', 'pg_02', 'pg_03', 'pg_04']);
      expect(json['defaults'], {'paper': 'dots', 'theme': 'paper'});

      final back = decodeNotebook(encodeNotebook(nb));
      expect(back.title, 'Physics — Lecture notes');
      expect(back.folderPath, ['School', 'Physics']);
      expect(back.extra['sync'], {'drive': 'abc'});
      expect(() => decodeNotebook('{"format":"other"}'), throwsFormatException);
    });
  });

  group('FileBoardStore', () {
    late Directory dir;
    late FileBoardStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('endless_test');
      store = FileBoardStore(dir);
    });
    tearDown(() => dir.delete(recursive: true));

    test('writes the .board folder layout and reads it back', () async {
      final sample = sampleNotebook();
      for (final p in sample.pages) {
        await store.savePage('nb_sample', p);
      }
      await store.saveNotebook(sample.notebook);

      expect(File('${dir.path}/notebooks/nb_sample.board/notebook.json').existsSync(), isTrue);
      expect(File('${dir.path}/notebooks/nb_sample.board/pages/pg_03.json').existsSync(), isTrue);
      expect(await store.listNotebookIds(), ['nb_sample']);

      final loaded = (await store.loadNotebook('nb_sample'))!;
      expect(loaded.pages.map((p) => p.id), ['pg_01', 'pg_02', 'pg_03', 'pg_04']);
      expect(loaded.pages[2].items.length, sample.pages[2].items.length);
      expect(loaded.pages[3].locked, isTrue);
    });

    test('overwrites atomically and leaves no temp files', () async {
      final page = BoardPage(id: 'pg_1');
      await store.savePage('nb', page);
      page.items.add(strokeFrom([Offset.zero, const Offset(5, 5)]));
      await store.savePage('nb', page);
      final pagesDir = Directory('${dir.path}/notebooks/nb.board/pages');
      expect(pagesDir.listSync().map((e) => e.uri.pathSegments.last), ['pg_1.json']);
      expect(decodePage(File('${pagesDir.path}/pg_1.json').readAsStringSync()).items, hasLength(1));
    });

    test('a page listed but never written loads empty', () async {
      final sample = sampleNotebook();
      await store.saveNotebook(sample.notebook);
      final loaded = (await store.loadNotebook('nb_sample'))!;
      expect(loaded.pages.every((p) => p.items.isEmpty), isTrue);
    });

    test('settings round trip', () async {
      expect(await store.loadSettings(), isNull);
      await store.saveSettings({'tool': 'marker'});
      expect(await store.loadSettings(), {'tool': 'marker'});
    });

    test('a sealed page replaces the clear one (and back), with lock.json beside it', () async {
      final sample = sampleNotebook();
      await store.saveNotebook(sample.notebook);
      for (final p in sample.pages) {
        await store.savePage('nb_sample', p);
      }
      final pages = Directory('${dir.path}/notebooks/nb_sample.board/pages');
      await store.saveLock('nb_sample', {'version': 1, 'notebook': null, 'pages': {}});
      await store.saveSealedPage('nb_sample', 'pg_03', Uint8List.fromList([69, 66, 76, 49, 1, 2, 3]));
      expect(File('${pages.path}/pg_03.json').existsSync(), isFalse);
      expect(File('${pages.path}/pg_03.json.enc').existsSync(), isTrue);
      expect(File('${dir.path}/notebooks/nb_sample.board/lock.json').existsSync(), isTrue);

      var loaded = (await store.loadNotebook('nb_sample'))!;
      expect(loaded.sealed.keys, ['pg_03']);
      expect(loaded.pages[2].locked, isTrue);
      expect(loaded.pages[2].items, isEmpty);
      expect(loaded.lock, isNotNull);

      await store.savePage('nb_sample', sample.pages[2]);
      await store.saveLock('nb_sample', null);
      loaded = (await store.loadNotebook('nb_sample'))!;
      expect(loaded.sealed, isEmpty);
      expect(loaded.pages[2].items, hasLength(14));
      expect(loaded.lock, isNull);
    });

    test('library.json, templates and deleting a notebook', () async {
      await store.saveLibrary({'version': 1, 'folders': []});
      expect(await store.loadLibrary(), {'version': 1, 'folders': []});
      await store.saveTemplate('tp_1', {'format': 'endless.template', 'id': 'tp_1'});
      expect(await store.loadTemplates(), hasLength(1));
      await store.deleteTemplate('tp_1');
      expect(await store.loadTemplates(), isEmpty);

      final sample = sampleNotebook();
      await store.saveNotebook(sample.notebook);
      expect((await store.loadNotebookMeta('nb_sample'))!.title, 'Physics — Lecture notes');
      await store.deleteNotebook('nb_sample');
      expect(await store.listNotebookIds(), isEmpty);
    });
  });
}
