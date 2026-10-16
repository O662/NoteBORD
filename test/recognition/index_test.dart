import 'dart:async';
import 'dart:ui';

import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/library/library.dart';
import 'package:endless/recognition/handwriting_index.dart';
import 'package:endless/recognition/models.dart';
import 'package:endless/recognition/recognizer.dart';
import 'package:endless/search/search.dart';
import 'package:endless/search/search_text.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/transfer/board_file.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'fake_ink.dart';

/// A container with notebook [id] open, reading handwriting with [r] 1.5 s
/// after the pen stops.
Future<ProviderContainer> _open(MemoryBoardStore store, String? id, InkRecognizer r) async {
  final c = ProviderContainer(
    overrides: await testOverrides(store, recognizer: r, recognitionIdle: const Duration(milliseconds: 1500)),
  );
  addTearDown(c.dispose);
  c.listen(settingsProvider, (_, _) {});
  c.listen(libraryProvider, (_, _) {});
  c.listen(inkModelsProvider, (_, _) {});
  if (id != null) {
    c.listen(loadedNotebookProvider(id), (_, _) {});
    await c.read(loadedNotebookProvider(id).future);
    c.listen(notebookProvider(id), (_, _) {});
  }
  return c;
}

/// Lets queued work and the in-memory database finish.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Waits for [f] while letting fake time run (the index's work and the
/// in-memory database live in the test's zone).
Future<T> _wait<T>(WidgetTester tester, Future<T> f) async {
  T? out;
  Object? error;
  var done = false;
  f.then((v) {
    out = v;
    done = true;
  }, onError: (Object e) {
    error = e;
    done = true;
  });
  for (var i = 0; i < 500 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  if (error != null) throw error!;
  expect(done, isTrue, reason: 'never finished');
  return out as T;
}

Future<List<SearchHit>> _search(WidgetTester tester, ProviderContainer c, MemoryBoardStore store, String q) =>
    _wait(tester, runSearch(q, db: c.read(indexDbProvider), library: c.read(libraryProvider), store: store));

void main() {
  testWidgets('handwriting is read 1.5 s after the pen stops, becomes searchable, and the ink is untouched', (tester) async {
    final store = MemoryBoardStore();
    final id = addUntitled(store);
    final r = FakeRecognizer();
    final c = await _open(store, id, r);
    final n = c.read(notebookProvider(id).notifier);
    final page = c.read(notebookProvider(id)).pages[0];
    final ink = writeLine(r, 'total momentum is conserved', at: const Offset(100, 200));
    for (final s in ink) {
      n.addStroke(page.id, s);
    }
    await tester.pump(const Duration(milliseconds: 1400));
    expect(r.recognized, 0);
    await tester.pump(const Duration(milliseconds: 200));
    await _settle(tester);
    expect(r.recognized, 1);

    final hits = await _search(tester, c, store, 'moment');
    expect(hits.single.row.kind, SearchKind.ink);
    expect(hits.single.row.text, 'total momentum is conserved');
    expect(hits.single.matchedWords, [1]);
    expect(hits.single.matchedStrokes, [ink[1].id]);
    expect(hits.single.pageIndex, 0);
    expect(await _search(tester, c, store, 'conserved total'), hasLength(1));
    expect(await _search(tester, c, store, 'entum'), isEmpty);

    // recognition.json holds it; the ink is as it was written.
    final json = await store.loadRecognition(id);
    expect((json!['pages'] as Map).keys, [page.id]);
    expect(page.items, ink);

    // More writing: only the new line goes to the recognizer.
    for (final s in writeLine(r, 'in a closed system', at: const Offset(100, 245))) {
      n.addStroke(page.id, s);
    }
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    expect(r.recognized, 2);
    expect(r.contexts.last, 'total momentum is conserved');
    final closed = await _search(tester, c, store, 'closed');
    expect(closed.single.row.context, 'total momentum is conserved in a closed system');
  });

  testWidgets('a page with a password leaves the search index and recognition.json at once', (tester) async {
    final store = MemoryBoardStore();
    final id = addUntitled(store);
    final r = FakeRecognizer();
    final c = await _open(store, id, r);
    final n = c.read(notebookProvider(id).notifier);
    final pageId = c.read(notebookProvider(id)).pages[0].id;
    for (final s in writeLine(r, 'secret plans', at: const Offset(100, 200))) {
      n.addStroke(pageId, s);
    }
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    expect(await _search(tester, c, store, 'secret'), hasLength(1));

    await _wait(tester, n.lockPage(pageId, 'pw'));
    await _settle(tester);
    expect(await _search(tester, c, store, 'secret'), isEmpty);
    expect(store.recognition[id], isNull);

    // Unlocked and written on: still never indexed while it has a password.
    await _wait(tester, n.unlock(pageId, 'pw'));
    for (final s in writeLine(r, 'more secrets', at: const Offset(100, 300))) {
      n.addStroke(pageId, s);
    }
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    expect(await _search(tester, c, store, 'secret'), isEmpty);
    expect(store.recognition[id], isNull);

    // A notebook password does the same for every page.
    final other = addUntitled(store);
    final c2 = await _open(store, other, r);
    final n2 = c2.read(notebookProvider(other).notifier);
    final p2 = c2.read(notebookProvider(other)).pages[0].id;
    for (final s in writeLine(r, 'diary', at: const Offset(100, 200))) {
      n2.addStroke(p2, s);
    }
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    expect(store.recognition[other], isNotNull);
    await _wait(tester, n2.lockNotebook('pw'));
    await _settle(tester);
    expect(store.recognition[other], isNull);
    expect(await _search(tester, c2, store, 'diary'), isEmpty);
  });

  testWidgets('a page locked while its handwriting is being read stays out of the index', (tester) async {
    final store = MemoryBoardStore();
    final id = addUntitled(store);
    final r = FakeRecognizer()..reading = Completer();
    final c = await _open(store, id, r);
    final n = c.read(notebookProvider(id).notifier);
    final pageId = c.read(notebookProvider(id)).pages[0].id;
    for (final s in writeLine(r, 'bank details', at: const Offset(100, 200))) {
      n.addStroke(pageId, s);
    }
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    // Being read now; the password goes on without waiting for it.
    await _wait(tester, n.lockPage(pageId, 'pw'));
    r.reading!.complete();
    await _settle(tester);
    expect(r.recognized, 1);
    expect(await _search(tester, c, store, 'bank'), isEmpty);
    expect(store.recognition[id], isNull);

    // Without the password it's read again.
    await _wait(tester, n.unlock(pageId, 'pw'));
    await _wait(tester, n.removePageLock(pageId));
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    expect(await _search(tester, c, store, 'bank'), hasLength(1));
  });

  testWidgets('an unlocked page with a password is searchable from memory only, until it locks or its notebook closes', (tester) async {
    final store = MemoryBoardStore();
    final id = addUntitled(store);
    final r = FakeRecognizer();
    final c = await _open(store, null, r);
    // Opened by hand, so it can be closed.
    final subs = <ProviderSubscription<Object?>>[
      c.listen(loadedNotebookProvider(id), (_, _) {}),
    ];
    await _wait(tester, c.read(loadedNotebookProvider(id).future));
    subs.add(c.listen(notebookProvider(id), (_, _) {}));
    final n = c.read(notebookProvider(id).notifier);
    final pageId = c.read(notebookProvider(id)).pages[0].id;
    for (final s in writeLine(r, 'bank details', at: const Offset(100, 200))) {
      n.addStroke(pageId, s);
    }
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    await _wait(tester, n.lockPage(pageId, 'pw'));
    await _settle(tester);
    final index = c.read(handwritingIndexProvider);
    Future<List<SearchHit>> search(String q) => _wait(
          tester,
          runSearch(q,
              db: c.read(indexDbProvider), library: c.read(libraryProvider), store: store, unlocked: index.unlockedRows),
        );
    expect(index.unlockedRows, isEmpty);
    expect(await search('bank'), isEmpty);

    // Unlocked: read into memory, found, marked; nothing written anywhere.
    await _wait(tester, n.unlock(pageId, 'pw'));
    await _settle(tester);
    final hits = await search('bank');
    expect(hits.single.row.private, isTrue);
    expect(hits.single.row.text, 'bank details');
    expect(index.openPage(id, pageId), isNotNull);
    expect(await _search(tester, c, store, 'bank'), isEmpty);
    expect(store.recognition[id], isNull);

    // Written on while unlocked: still from memory only.
    for (final s in writeLine(r, 'sort code', at: const Offset(100, 260))) {
      n.addStroke(pageId, s);
    }
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    expect(await search('sort'), hasLength(1));
    expect(await _search(tester, c, store, 'sort'), isEmpty);
    expect(store.recognition[id], isNull);

    // Locked again: gone.
    await _wait(tester, n.lockNow());
    await _settle(tester);
    expect(index.unlockedRows, isEmpty);
    expect(await search('bank'), isEmpty);

    // Unlocked, then the notebook closed (which locks it): gone.
    await _wait(tester, n.unlock(pageId, 'pw'));
    await _settle(tester);
    expect(await search('bank'), hasLength(1));
    for (final sub in subs.reversed) {
      sub.close();
    }
    await _settle(tester);
    expect(index.unlockedRows, isEmpty);
    expect(store.recognition[id], isNull);
  });

  testWidgets('typed text and text inside PDFs are searchable without a recognizer', (tester) async {
    final store = MemoryBoardStore();
    final id = addUntitled(store);
    final c = await _open(store, id, const NoInkRecognizer());
    final n = c.read(notebookProvider(id).notifier);
    final pageId = c.read(notebookProvider(id)).pages[0].id;
    n.insertItems(pageId, [
      TextItem(id: 't1', x: 10, y: 10, z: 1, createdAt: testNow, wrap: 300, text: 'Linear momentum notes', color: const Color(0xFF000000)),
      FileItem(
        id: 'f1',
        x: 0,
        y: 400,
        z: 2,
        createdAt: testNow,
        w: 600,
        h: 800,
        asset: 'a.pdf',
        mime: 'pdf',
        page: 214,
        name: 'Ch 9 Linear Momentum.pdf',
        text: 'Chapter 9. Linear Momentum and Collisions',
      ),
    ]);
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    final hits = await _search(tester, c, store, 'linear moment');
    expect(hits.map((h) => h.row.kind), [SearchKind.typed, SearchKind.pdf]);
    expect(hits.last.row.fileName, 'Ch 9 Linear Momentum.pdf');
    expect(hits.last.row.data['page'], 214);
    expect(store.recognition[id], isNull);
  });

  testWidgets('the model downloads on first use, with a note; offline the note says so', (tester) async {
    final store = MemoryBoardStore();
    final id = addUntitled(store);
    final r = FakeRecognizer(models: {})..gate = Completer();
    final c = await _open(store, id, r);
    final n = c.read(notebookProvider(id).notifier);
    final pageId = c.read(notebookProvider(id)).pages[0].id;
    for (final s in writeLine(r, 'hello there', at: const Offset(100, 200))) {
      n.addStroke(pageId, s);
    }
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    expect(c.read(inkModelsProvider)?.phase, ModelPhase.downloading);
    expect(c.read(inkModelsProvider)!.text, 'Getting English handwriting ready · first time only, about 20 MB');
    r.gate!.complete();
    await _settle(tester);
    expect(c.read(inkModelsProvider)?.phase, ModelPhase.ready);
    expect(r.recognized, 1);
    expect(await _search(tester, c, store, 'hello'), hasLength(1));

    // Another language, offline.
    final r2 = FakeRecognizer(models: {}, downloads: false);
    final c2 = await _open(store, id, r2);
    expect(await _wait(tester, c2.read(inkModelsProvider.notifier).ensure('de-DE')), isFalse);
    expect(c2.read(inkModelsProvider)!.text, 'Couldn’t download Deutsch handwriting · it will try again when you’re online');
    // Not tried again straight away.
    expect(await _wait(tester, c2.read(inkModelsProvider.notifier).ensure('de-DE')), isFalse);
    expect(r2.downloaded, 1);
  });

  testWidgets('catching up reads closed notebooks, skips locked ones and forgets deleted ones', (tester) async {
    final store = MemoryBoardStore();
    final r = FakeRecognizer();
    final now = DateTime.utc(2026, 9, 25, 9);
    BoardPage page(String id, String words) => BoardPage(id: id, items: writeLine(r, words, at: const Offset(50, 50)));
    final open = Notebook(id: 'nb_a', title: 'Physics', folderPath: ['School'], createdAt: now, updatedAt: now, pageIds: ['p1', 'p2']);
    final locked = Notebook(id: 'nb_b', title: 'Diary', createdAt: now, updatedAt: now, pageIds: ['p3'], locked: true);
    await store.savePage('nb_a', page('p1', 'momentum'));
    await store.savePage('nb_a', page('p2', 'impulse momentum'));
    await store.savePage('nb_b', page('p3', 'momentum secret'));
    await store.saveNotebook(open);
    await store.saveNotebook(locked);
    final c = await _open(store, null, r);
    final index = c.read(handwritingIndexProvider);
    await _wait(tester, index.catchUp());
    await _settle(tester);
    final hits = await _search(tester, c, store, 'momentum');
    expect(hits.map((h) => (h.notebook.title, h.pageIndex)), [('Physics', 0), ('Physics', 1)]);
    expect(store.recognition['nb_b'], isNull);
    expect(r.recognized, 2);

    // Nothing changed: nothing is read again.
    await _wait(tester, index.catchUp());
    await _settle(tester);
    expect(r.recognized, 2);

    // Folder and date filters.
    final all = hits;
    expect(narrow(all, folder: ['School'], now: testNow), hasLength(2));
    expect(narrow(all, folder: ['Home'], now: testNow), isEmpty);
    expect(narrow(all, date: SearchDate.week, now: DateTime.utc(2026, 9, 26)), hasLength(2));
    expect(narrow(all, date: SearchDate.week, now: DateTime.utc(2026, 11, 26)), isEmpty);
  });

  testWidgets('board files carry what the handwriting says, and import brings it back', (tester) async {
    final store = MemoryBoardStore();
    final id = addUntitled(store);
    final r = FakeRecognizer();
    final c = await _open(store, id, r);
    final n = c.read(notebookProvider(id).notifier);
    final pageId = c.read(notebookProvider(id)).pages[0].id;
    for (final s in writeLine(r, 'momentum is conserved', at: const Offset(100, 200))) {
      n.addStroke(pageId, s);
    }
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    await _wait(tester, n.flush());

    final bytes = await _wait(tester, exportBoardFile(store, id));
    final other = MemoryBoardStore();
    final imported = await _wait(tester, importBoardFile(other, bytes, folder: const [], now: testNow));
    final read = await other.loadRecognition(imported.notebookId);
    expect((read!['pages'] as Map).keys, [pageId]);
    expect(((read['pages'] as Map)[pageId] as Map)['lines'], hasLength(1));

    final without = await _wait(tester, exportBoardFile(store, id, includeRecognition: false));
    final third = MemoryBoardStore();
    final again = await _wait(tester, importBoardFile(third, without, folder: const [], now: testNow));
    expect(await third.loadRecognition(again.notebookId), isNull);
  });
}
