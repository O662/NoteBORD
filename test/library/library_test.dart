import 'package:endless/board/codec.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/library/index_db.dart';
import 'package:endless/library/library.dart';
import 'package:endless/library/thumbs.dart';
import 'package:endless/templates/templates.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:endless/ui/library/format.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

Future<ProviderContainer> _library(MemoryBoardStore store) async {
  final c = ProviderContainer(overrides: await testOverrides(store));
  addTearDown(c.dispose);
  c.listen(libraryProvider, (_, _) {});
  return c;
}

void main() {
  group('index', () {
    testWidgets('rows round trip, and startup refreshes them from the files', (tester) async {
      final store = storeWith(sampleNotebook());
      final db = IndexDb.memory();
      addTearDown(db.close);

      var lib = await loadLibrary(store, db, testNow.toUtc());
      final entry = lib.byId('nb_sample')!;
      expect(entry.title, 'Physics — Lecture notes');
      expect(entry.folder, ['School', 'Physics']);
      expect(entry.pageCount, 4);
      expect(entry.lockedPages, 1);
      expect(entry.thumb, isNotNull);
      expect((await db.all()).single.thumb!.strokes, hasLength(entry.thumb!.strokes.length));

      // This device's reading position survives a refresh; a deleted notebook's row goes.
      await db.upsert(entry.copyWith(lastPage: 2));
      final nb = decodeNotebook(store.notebooks['nb_sample']!)..title = 'Renamed elsewhere';
      await store.saveNotebook(nb);
      lib = await loadLibrary(store, db, testNow.toUtc());
      expect(lib.byId('nb_sample')!.title, 'Renamed elsewhere');
      expect(lib.byId('nb_sample')!.lastPage, 2);

      await store.deleteNotebook('nb_sample');
      lib = await loadLibrary(store, db, testNow.toUtc());
      expect(lib.notebooks, isEmpty);
      expect(await db.all(), isEmpty);
    });

    testWidgets('the Trash empties itself after 30 days', (tester) async {
      final store = storeWith(sampleNotebook());
      final nb = decodeNotebook(store.notebooks['nb_sample']!)..trashedAt = testNow.toUtc().subtract(const Duration(days: 31));
      await store.saveNotebook(nb);
      final db = IndexDb.memory();
      addTearDown(db.close);
      final lib = await loadLibrary(store, db, testNow.toUtc());
      expect(lib.notebooks, isEmpty);
      expect(store.notebooks, isEmpty);
    });

    test('cover thumbnails stay small and skip locked pages', () {
      final page = sampleNotebook().pages[2];
      final t = InkThumb.fromPage(page)!;
      expect(t.strokes.fold<int>(0, (n, s) => n + s.points.length), lessThanOrEqualTo(InkThumb.pointBudget));
      final back = InkThumb.decode(t.encode())!;
      expect(back.strokes, hasLength(t.strokes.length));
      expect(back.bounds.width, closeTo(t.bounds.width, 1));
      final locked = BoardPage(id: 'x', locked: true, items: [...page.items]);
      expect(coverThumb([locked], 0, const {}), isNull);
      expect(coverThumb([BoardPage(id: 'e'), page], 0, const {}), isNotNull);
    });
  });

  group('notebooks', () {
    testWidgets('create, rename, move, color, pin, trash, restore, delete', (tester) async {
      final store = MemoryBoardStore();
      final c = await _library(store);
      final lib = c.read(libraryProvider.notifier);
      final id = await lib.createNotebook(title: 'Garden ideas', folder: ['Personal'], template: 'todo', paper: Paper.lines);
      var e = c.read(libraryProvider).byId(id)!;
      expect(e.folder, ['Personal']);
      expect(c.read(libraryProvider).folder(['Personal']), isNotNull);
      final page = decodePage(store.pages[id]!.values.single);
      expect(page.template, 'todo');
      expect(page.paper, Paper.lines);

      await lib.rename(id, '  Garden  ');
      await lib.move(id, ['Personal', 'Home']);
      await lib.setCover(id, tokens.coverColors[2]);
      await lib.setPinned(id, true);
      e = c.read(libraryProvider).byId(id)!;
      expect(e.title, 'Garden');
      expect(e.folder, ['Personal', 'Home']);
      expect(c.read(libraryProvider).coverOf(e), tokens.coverColors[2]);
      expect(c.read(libraryProvider).pinned.single.id, id);
      final saved = decodeNotebook(store.notebooks[id]!);
      expect(saved.title, 'Garden');
      expect(saved.folderPath, ['Personal', 'Home']);
      expect(saved.pinned, isTrue);

      await lib.trash(id);
      expect(c.read(libraryProvider).active, isEmpty);
      expect(c.read(libraryProvider).trash.single.id, id);
      expect(c.read(libraryProvider).pinned, isEmpty);
      await lib.restore(id);
      expect(c.read(libraryProvider).active.single.id, id);

      await lib.trash(id);
      await lib.emptyTrash();
      expect(c.read(libraryProvider).notebooks, isEmpty);
      expect(store.notebooks, isEmpty);
    });

    testWidgets('Continue writing, Pinned and Recent', (tester) async {
      final store = MemoryBoardStore();
      final c = await _library(store);
      final lib = c.read(libraryProvider.notifier);
      final a = await lib.createNotebook(title: 'A');
      final b = await lib.createNotebook(title: 'B');
      lib.recordOpened(a, 0);
      expect(c.read(libraryProvider).continueWriting!.id, a);
      expect(c.read(libraryProvider).recent(except: a).map((n) => n.id), [b]);
      await lib.setPinned(b, true);
      expect(c.read(libraryProvider).pinned.map((n) => n.title), ['B']);
    });
  });

  group('folders', () {
    testWidgets('create, reject duplicates, rename with contents, delete to Trash', (tester) async {
      final store = MemoryBoardStore();
      final c = await _library(store);
      final lib = c.read(libraryProvider.notifier);
      expect(await lib.createFolder([], 'School'), isTrue);
      expect(await lib.createFolder([], 'School'), isFalse);
      expect(await lib.createFolder(['School'], 'Physics'), isTrue);
      final id = await lib.createNotebook(title: 'Lab journal', folder: ['School', 'Physics']);
      var state = c.read(libraryProvider);
      expect(state.childrenOf([]).map((f) => f.name), ['School']);
      expect(state.childrenOf(['School']).map((f) => f.name), ['Physics']);
      expect(state.countUnder(['School']), 1);
      expect(store.library!['folders'], hasLength(2));

      expect(await lib.renameFolder(['School'], 'Uni'), isTrue);
      state = c.read(libraryProvider);
      expect(state.byId(id)!.folder, ['Uni', 'Physics']);
      expect(state.folder(['Uni', 'Physics']), isNotNull);
      expect(state.folder(['School']), isNull);
      expect(decodeNotebook(store.notebooks[id]!).folderPath, ['Uni', 'Physics']);

      await lib.setFolderColor(['Uni'], tokens.coverColors[3]);
      expect(c.read(libraryProvider).folder(['Uni'])!.color, tokens.coverColors[3]);

      await lib.deleteFolder(['Uni']);
      state = c.read(libraryProvider);
      expect(state.folders, isEmpty);
      expect(state.trash.single.id, id);
    });
  });

  group('templates', () {
    test('every built-in layout draws and has bounds', () {
      for (final t in builtInTemplates) {
        if (!t.layout) {
          expect(layoutBounds(t.id), isNull, reason: t.id);
          continue;
        }
        expect(layoutBounds(t.id), isNotNull, reason: t.id);
        expect(layoutPicture(t.id, tokens.paperLight), isNotNull, reason: t.id);
        expect(layoutPicture(t.id, tokens.paperDark), isNotNull, reason: t.id);
      }
      expect(builtInTemplates, hasLength(11));
    });

    testWidgets('a page saved as a template is reused with fresh ids', (tester) async {
      final store = MemoryBoardStore();
      final c = ProviderContainer(overrides: await testOverrides(store));
      addTearDown(c.dispose);
      c.listen(userTemplatesProvider, (_, _) {});
      final page = sampleNotebook().pages[2]..template = 'cornell';
      final t = await c.read(userTemplatesProvider.notifier).saveFromPage(page, 'Lecture');
      expect(store.templates[t.id]!['name'], 'Lecture');
      expect((await loadUserTemplates(store)).single.layout, 'cornell');
      final items = t.freshItems();
      expect(items, hasLength(page.items.length));
      expect(items.map((i) => i.id).toSet().intersection(page.items.map((i) => i.id).toSet()), isEmpty);
      await c.read(userTemplatesProvider.notifier).delete(t.id);
      expect(store.templates, isEmpty);
    });
  });

  test('dates read like the design', () {
    final now = DateTime(2026, 9, 25, 10);
    expect(longDate(now), 'Friday, September 25');
    expect(shortWhen(DateTime(2026, 9, 25, 8), now), 'Edited 2h ago');
    expect(shortWhen(DateTime(2026, 9, 24, 18), now), 'Yesterday');
    expect(shortWhen(DateTime(2026, 9, 21, 12), now), 'Monday');
    expect(shortWhen(DateTime(2026, 9, 12), now), 'Sep 12');
    expect(shortWhen(DateTime(2025, 9, 12), now), 'Sep 12, 2025');
    expect(agoPhrase(DateTime(2026, 9, 25, 8), now), '2 hours ago');
    expect(agoPhrase(DateTime(2026, 9, 25, 9, 59, 30), now), 'just now');
    expect(agoPhrase(DateTime(2026, 9, 18), now), 'on Sep 18');
  });
}
