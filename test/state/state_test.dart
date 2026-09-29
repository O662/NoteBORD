import 'package:endless/board/codec.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/library/library.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// A container with notebook [id] open (as a screen showing it would).
Future<ProviderContainer> _container(MemoryBoardStore store, String id) async {
  final c = ProviderContainer(overrides: await testOverrides(store));
  addTearDown(c.dispose);
  c.listen(loadedNotebookProvider(id), (_, _) {});
  await c.read(loadedNotebookProvider(id).future);
  c.listen(notebookProvider(id), (_, _) {});
  c.listen(settingsProvider, (_, _) {});
  c.listen(libraryProvider, (_, _) {});
  return c;
}

StrokeItem _line(double y) => strokeFrom([Offset(0, y), Offset(50, y), Offset(100, y)]);

void main() {
  group('opening', () {
    testWidgets('a new install starts with an empty library', (tester) async {
      final store = MemoryBoardStore();
      final c = ProviderContainer(overrides: await testOverrides(store));
      addTearDown(c.dispose);
      expect(c.read(libraryProvider).notebooks, isEmpty);
      expect(store.notebooks, isEmpty);
    });

    testWidgets('loads a notebook from storage', (tester) async {
      final c = await _container(storeWith(sampleNotebook()), 'nb_sample');
      expect(c.read(notebookProvider('nb_sample')).notebook.title, 'Physics — Lecture notes');
      expect(c.read(notebookProvider('nb_sample')).pages, hasLength(4));
      expect(c.read(libraryProvider).byId('nb_sample')!.pageCount, 4);
    });
  });

  group('undo and redo', () {
    testWidgets('strokes undo and redo per page', (tester) async {
      final store = MemoryBoardStore();
      final id = addUntitled(store);
      final c = await _container(store, id);
      final n = c.read(notebookProvider(id).notifier);
      String page(int i) => c.read(notebookProvider(id)).pages[i].id;
      List<Item> items(int i) => c.read(notebookProvider(id)).pages[i].items;
      expect(n.canUndo(page(0)), isFalse);

      n.addStroke(page(0), _line(10));
      n.addStroke(page(0), _line(20));
      expect(items(0), hasLength(2));
      expect(n.canUndo(page(0)), isTrue);

      n.undo(page(0));
      expect(items(0), hasLength(1));
      expect(n.canRedo(page(0)), isTrue);
      n.redo(page(0));
      expect(items(0), hasLength(2));

      n.undo(page(0));
      n.addStroke(page(0), _line(30)); // a new edit clears redo
      expect(n.canRedo(page(0)), isFalse);

      expect(n.addPage(), 1);
      expect(n.canUndo(page(1)), isFalse); // page 2 has its own history
      expect(n.canUndo(page(0)), isTrue);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('one eraser drag is one undo step and restores z-order', (tester) async {
      final store = MemoryBoardStore();
      final id = addUntitled(store);
      final c = await _container(store, id);
      final n = c.read(notebookProvider(id).notifier);
      final pageId = c.read(notebookProvider(id)).pages.first.id;
      final strokes = [_line(10), _line(20), _line(30), _line(40)];
      for (final s in strokes) {
        n.addStroke(pageId, s);
      }
      List<String> ids() => c.read(notebookProvider(id)).pages.first.items.map((i) => i.id).toList();

      n.beginErase(pageId);
      n.erase([strokes[1].id]);
      n.erase([strokes[3].id, 'missing']);
      n.endErase();
      expect(ids(), [strokes[0].id, strokes[2].id]);

      n.undo(pageId);
      expect(ids(), strokes.map((s) => s.id));
      n.redo(pageId);
      expect(ids(), hasLength(2));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('pages can be added after a given page, with a template', (tester) async {
      final c = await _container(storeWith(sampleNotebook()), 'nb_sample');
      final n = c.read(notebookProvider('nb_sample').notifier);
      final i = n.addPage(after: 0, paper: Paper.lines, template: 'cornell');
      expect(i, 1);
      final page = c.read(notebookProvider('nb_sample')).pages[1].page;
      expect(page.paper, Paper.lines);
      expect(page.template, 'cornell');
      expect(c.read(notebookProvider('nb_sample')).notebook.pageIds[1], page.id);
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('autosave', () {
    testWidgets('every change is on disk within a second', (tester) async {
      final store = MemoryBoardStore();
      final id = addUntitled(store);
      final c = await _container(store, id);
      final n = c.read(notebookProvider(id).notifier);
      final pageId = c.read(notebookProvider(id)).pages.first.id;
      store.pageWrites = 0;

      n.addStroke(pageId, _line(10));
      expect(c.read(notebookProvider(id)).saveStatus, SaveStatus.saving);
      // More strokes while the save is pending join the same write.
      await tester.pump(const Duration(milliseconds: 200));
      n.addStroke(pageId, _line(20));
      await tester.pump(const Duration(milliseconds: 300));

      expect(store.pageWrites, 1);
      expect(c.read(notebookProvider(id)).saveStatus, SaveStatus.saved);
      expect(decodePage(store.pages[id]![pageId]!).items, hasLength(2));

      n.addStroke(pageId, _line(30));
      await tester.pump(const Duration(seconds: 1));
      expect(store.pageWrites, 2);
      expect(decodePage(store.pages[id]![pageId]!).items, hasLength(3));
      // The library index follows: a cover thumbnail and "Last edited".
      final entry = c.read(libraryProvider).byId(id)!;
      expect(entry.thumb, isNotNull);
      expect(entry.updatedAt, testNow.toUtc());
    });

    testWidgets('flush writes immediately, and a new page lands in notebook.json', (tester) async {
      final store = MemoryBoardStore();
      final id = addUntitled(store);
      final c = await _container(store, id);
      final n = c.read(notebookProvider(id).notifier);
      n.addPage();
      await n.flush();
      final nb = decodeNotebook(store.notebooks.values.single);
      expect(nb.pageIds, hasLength(2));
      expect(store.pages[nb.id]!.keys, containsAll(nb.pageIds));
      expect(c.read(libraryProvider).byId(id)!.pageCount, 2);
    });

    testWidgets('unknown items survive editing the page', (tester) async {
      final sample = sampleNotebook();
      sample.pages[0].items.add(UnknownItem({
        'id': 'it_future',
        'type': 'hologram',
        'x': 1,
        'y': 2,
        'z': 1,
        'createdAt': '2026-09-01T00:00:00.000Z',
        'sparkle': 11,
      }));
      final store = storeWith(sample);
      final c = await _container(store, 'nb_sample');
      c.read(notebookProvider('nb_sample').notifier).addStroke('pg_01', _line(10));
      await tester.pump(const Duration(seconds: 1));
      final saved = decodePage(store.pages['nb_sample']!['pg_01']!);
      expect(saved.items.first.toJson()['sparkle'], 11);
      expect(saved.items, hasLength(2));
    });

    testWidgets('a rename from the library while the notebook is open is not overwritten', (tester) async {
      final store = storeWith(sampleNotebook());
      final c = await _container(store, 'nb_sample');
      c.read(notebookProvider('nb_sample').notifier).addStroke('pg_01', _line(10));
      await c.read(libraryProvider.notifier).rename('nb_sample', 'Physics 101');
      await tester.pump(const Duration(seconds: 1));
      expect(decodeNotebook(store.notebooks['nb_sample']!).title, 'Physics 101');
      expect(c.read(notebookProvider('nb_sample')).notebook.title, 'Physics 101');
    });
  });

  group('settings', () {
    testWidgets('the tray holds at most 10 colors', (tester) async {
      final c = ProviderContainer(overrides: await testOverrides(MemoryBoardStore()));
      addTearDown(c.dispose);
      c.listen(settingsProvider, (_, _) {});
      final s = c.read(settingsProvider.notifier);
      expect(c.read(settingsProvider).extraColors, hasLength(6));
      for (var i = 0; i < 8; i++) {
        s.addExtraColor();
      }
      expect(c.read(settingsProvider).extraColors, hasLength(tokens.extraInkMax));
      expect(c.read(settingsProvider).penColor, c.read(settingsProvider).extraColors.last);
      s.removeExtraColor(tokens.extraInkDefaults[0]);
      expect(c.read(settingsProvider).extraColors, hasLength(9));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('pen and marker keep their own color and size', (tester) async {
      final c = ProviderContainer(overrides: await testOverrides(MemoryBoardStore()));
      addTearDown(c.dispose);
      c.listen(settingsProvider, (_, _) {});
      final s = c.read(settingsProvider.notifier);
      s.pickColor(tokens.inkDefaults[2]);
      s.pickSize(4);
      s.apply((st) => st.copyWith(tool: CanvasTool.marker));
      expect(c.read(settingsProvider).color, tokens.extraInkDefaults[3]);
      expect(c.read(settingsProvider).strokeWidth, 10); // 0.5 mm marker = 2.5 × 4
      s.apply((st) => st.copyWith(tool: CanvasTool.eraser));
      s.pickColor(tokens.inkDefaults[0]); // picking a color leaves the eraser
      expect(c.read(settingsProvider).tool, CanvasTool.pen);
      expect(c.read(settingsProvider).penSize, 4);
      await tester.pump(const Duration(seconds: 1));
    });

    test('settings survive JSON', () {
      final s = AppSettings(
        tool: CanvasTool.marker,
        penColor: tokens.inkDefaults[2],
        penSize: 3,
        penType: PenType.fountain,
        pressure: false,
        extraColors: [tokens.extraInkAddable[0]],
        fingerDraws: true,
        lastNotebookId: 'nb_1',
        userName: 'Kieth',
        libraryView: LibraryView.list,
        librarySort: LibrarySort.title,
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.toJson(), s.toJson());
      expect(AppSettings.fromJson({'penSize': 99}).penSize, 4);
    });
  });
}
