import 'package:endless/board/codec.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

Future<ProviderContainer> _container(MemoryBoardStore store) async {
  final c = ProviderContainer(overrides: await bootstrap(store));
  addTearDown(c.dispose);
  c.listen(notebookProvider, (_, _) {});
  c.listen(settingsProvider, (_, _) {});
  return c;
}

StrokeItem _line(double y) => strokeFrom([Offset(0, y), Offset(50, y), Offset(100, y)]);

void main() {
  group('first run', () {
    testWidgets('creates and saves an untitled notebook with one page', (tester) async {
      final store = MemoryBoardStore();
      final c = await _container(store);
      final nb = c.read(notebookProvider);
      expect(nb.notebook.title, 'Untitled notebook');
      expect(nb.pages, hasLength(1));
      expect(store.notebooks.keys, [nb.notebook.id]);
      expect(store.settings!['lastNotebookId'], nb.notebook.id);
    });

    testWidgets('reopens the last notebook', (tester) async {
      final store = storeWith(sampleNotebook());
      final c = await _container(store);
      expect(c.read(notebookProvider).notebook.title, 'Physics — Lecture notes');
      expect(c.read(notebookProvider).pages, hasLength(4));
    });
  });

  group('undo and redo', () {
    testWidgets('strokes undo and redo per page', (tester) async {
      final c = await _container(MemoryBoardStore());
      final n = c.read(notebookProvider.notifier);
      expect(c.read(notebookProvider).canUndo, isFalse);

      n.addStroke(_line(10));
      n.addStroke(_line(20));
      expect(c.read(notebookProvider).page.items, hasLength(2));
      expect(c.read(notebookProvider).canUndo, isTrue);

      n.undo();
      expect(c.read(notebookProvider).page.items, hasLength(1));
      expect(c.read(notebookProvider).canRedo, isTrue);
      n.redo();
      expect(c.read(notebookProvider).page.items, hasLength(2));

      n.undo();
      n.addStroke(_line(30)); // a new edit clears redo
      expect(c.read(notebookProvider).canRedo, isFalse);

      n.addPage();
      expect(c.read(notebookProvider).current, 1);
      expect(c.read(notebookProvider).canUndo, isFalse); // page 2 has its own history
      n.goToPage(0);
      expect(c.read(notebookProvider).canUndo, isTrue);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('one eraser drag is one undo step and restores z-order', (tester) async {
      final c = await _container(MemoryBoardStore());
      final n = c.read(notebookProvider.notifier);
      final strokes = [_line(10), _line(20), _line(30), _line(40)];
      strokes.forEach(n.addStroke);

      n.beginErase();
      n.erase([strokes[1].id]);
      n.erase([strokes[3].id, 'missing']);
      n.endErase();
      expect(c.read(notebookProvider).page.items.map((i) => i.id), [strokes[0].id, strokes[2].id]);

      n.undo();
      expect(c.read(notebookProvider).page.items.map((i) => i.id), strokes.map((s) => s.id));
      n.redo();
      expect(c.read(notebookProvider).page.items, hasLength(2));
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('autosave', () {
    testWidgets('every change is on disk within a second', (tester) async {
      final store = MemoryBoardStore();
      final c = await _container(store);
      final n = c.read(notebookProvider.notifier);
      final id = c.read(notebookProvider).notebook.id;
      final pageId = c.read(notebookProvider).page.id;
      store.pageWrites = 0;

      n.addStroke(_line(10));
      expect(c.read(notebookProvider).saveStatus, SaveStatus.saving);
      // More strokes while the save is pending join the same write.
      await tester.pump(const Duration(milliseconds: 200));
      n.addStroke(_line(20));
      await tester.pump(const Duration(milliseconds: 300));

      expect(store.pageWrites, 1);
      expect(c.read(notebookProvider).saveStatus, SaveStatus.saved);
      expect(decodePage(store.pages[id]![pageId]!).items, hasLength(2));

      n.addStroke(_line(30));
      await tester.pump(const Duration(seconds: 1));
      expect(store.pageWrites, 2);
      expect(decodePage(store.pages[id]![pageId]!).items, hasLength(3));
    });

    testWidgets('flush writes immediately, and a new page lands in notebook.json', (tester) async {
      final store = MemoryBoardStore();
      final c = await _container(store);
      final n = c.read(notebookProvider.notifier);
      n.addPage();
      await n.flush();
      final nb = decodeNotebook(store.notebooks.values.single);
      expect(nb.pageIds, hasLength(2));
      expect(store.pages[nb.id]!.keys, containsAll(nb.pageIds));
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
      final c = await _container(store);
      c.read(notebookProvider.notifier).addStroke(_line(10));
      await tester.pump(const Duration(seconds: 1));
      final saved = decodePage(store.pages['nb_sample']!['pg_01']!);
      expect(saved.items.first.toJson()['sparkle'], 11);
      expect(saved.items, hasLength(2));
    });
  });

  group('settings', () {
    testWidgets('the tray holds at most 10 colors', (tester) async {
      final c = await _container(MemoryBoardStore());
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
      final c = await _container(MemoryBoardStore());
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
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.toJson(), s.toJson());
      expect(AppSettings.fromJson({'penSize': 99}).penSize, 4);
    });
  });
}
