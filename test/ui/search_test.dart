import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/recognition/recognizer.dart';
import 'package:endless/ui/canvas/canvas_screen.dart';
import 'package:endless/ui/search/search_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../recognition/fake_ink.dart';

/// Search.png's library: lecture notes with handwriting and typed text, a
/// lab journal, and a notebook made from a PDF.
MemoryBoardStore searchLibrary(FakeRecognizer r) {
  final store = MemoryBoardStore();
  final now = DateTime.utc(2026, 9, 24, 9);
  void add(String id, String title, List<String> folder, List<BoardPage> pages, {DateTime? updated}) {
    for (final p in pages) {
      store.savePage(id, p);
    }
    store.saveNotebook(Notebook(
      id: id,
      title: title,
      folderPath: folder,
      createdAt: now,
      updatedAt: updated ?? now,
      pageIds: [for (final p in pages) p.id],
    ));
  }

  add('nb_physics', 'Physics — Lecture notes', ['School', 'Physics'], [
    BoardPage(id: 'pg_1'),
    BoardPage(id: 'pg_2'),
    BoardPage(id: 'pg_3', items: [
      ...writeLine(r, 'Lecture three Momentum', at: const Offset(120, 120), height: 44),
      ...writeLine(r, 'total momentum is conserved', at: const Offset(120, 300), height: 36, z: 10),
      ...writeLine(r, 'in a closed system', at: const Offset(120, 350), height: 36, z: 20),
      TextItem(id: 't1', x: 120, y: 600, z: 40, createdAt: now, wrap: 400, text: 'Momentum = mass × velocity', color: const Color(0xFF1E1C19)),
    ]),
  ], updated: DateTime.utc(2026, 9, 25, 9));
  add('nb_lab', 'Lab journal', ['School', 'Physics'], [
    BoardPage(id: 'pg_l1'),
    BoardPage(id: 'pg_l2', items: writeLine(r, 'momentum before', at: const Offset(100, 100))),
  ]);
  add('nb_pdf', 'Ch 9 reading', ['School'], [
    BoardPage(id: 'pg_p1', items: [
      FileItem(
        id: 'f1',
        x: 0,
        y: 0,
        z: 1,
        createdAt: now,
        w: 612,
        h: 792,
        asset: 'a.pdf',
        mime: 'pdf',
        page: 214,
        name: 'Ch 9 Linear Momentum.pdf',
        text: '9.1 Linear Momentum and Force',
      ),
    ]),
  ]);
  add('nb_home', 'Groceries', ['Home'], [
    BoardPage(id: 'pg_h1', items: writeLine(r, 'apples pears', at: const Offset(140, 180))),
  ]);
  return store;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

Future<void> _search(WidgetTester tester, String q) async {
  await tester.enterText(find.byType(TextField), q);
  await tester.pump(const Duration(milliseconds: 250));
  await _settle(tester);
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the rail’s Search finds handwriting, typed text and PDFs everywhere, with counts and filters', (tester) async {
    final r = FakeRecognizer();
    await pumpCanvas(tester, store: searchLibrary(r), notebookId: 'nb_home', recognizer: r);
    await tester.tap(byLabel('Search'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);
    // Opening it reads the notebooks not read yet.
    await _settle(tester);
    await _search(tester, 'momentum');

    expect(find.text('5 matches in 3 notebooks'), findsOneWidget);
    expect(find.bySemanticsLabel('All, 5'), findsOneWidget);
    expect(find.bySemanticsLabel('Handwriting, 3'), findsOneWidget);
    expect(find.bySemanticsLabel('Typed text, 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Inside PDFs, 1'), findsOneWidget);
    // Newest notebook first, then by page and down the page.
    final rows = tester.widgetList<Semantics>(find.byWidgetPredicate(
      (w) => w is Semantics && (w.properties.label?.contains(', Page ') ?? false) && w.properties.button == true,
    ));
    expect(rows.first.properties.label, startsWith('Physics — Lecture notes, Page 3 · School › Physics, Handwriting'));
    expect(find.text('Ch 9 Linear Momentum.pdf'), findsOneWidget);
    expect(find.text('Page 214 · Imported into School'), findsOneWidget);

    // The first match is shown on its page.
    expect(find.text('Open at this spot'), findsOneWidget);
    expect(find.text('RECOGNIZED AS'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Typed text, 1'));
    await tester.pump();
    expect(find.text('TYPED TEXT'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('All, 5'));
    await tester.pump();

    // Folders.
    await tester.tap(find.bySemanticsLabel('Folder: All folders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();
    expect(find.text('No matches with these filters'), findsOneWidget);
    expect(find.bySemanticsLabel('All, 0'), findsOneWidget);
  });

  testWidgets('Open at this spot opens the page with the match in the middle', (tester) async {
    final r = FakeRecognizer();
    await pumpCanvas(tester, store: searchLibrary(r), notebookId: 'nb_home', recognizer: r);
    await tester.tap(byLabel('Search'));
    await tester.pumpAndSettle();
    await _settle(tester);
    await _search(tester, 'conserved');
    expect(find.text('1 match in 1 notebook'), findsOneWidget);
    await tester.tap(find.text('Open at this spot'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    final screen = tester.widget<CanvasScreen>(find.byType(CanvasScreen));
    expect(screen.pane.notebookId, 'nb_physics');
    expect(screen.pane.page, 2);
    // "conserved" (the fourth word of its line) is in the middle of the screen.
    final view = screen.pane.view;
    final word = Offset(120 + (5 + 8 + 2) * 14.0 + 3 * 20 + 9 * 7, 318);
    expect((view.toScreen(word) - view.size.center(Offset.zero)).distance, lessThan(4));
    expect(find.byType(CustomPaint), findsWidgets);
    await tester.pump(const Duration(seconds: 3));
    // Back goes where search was opened from.
    await tester.tap(byLabel('Back to library'));
    await tester.pumpAndSettle();
    expect(tester.widget<CanvasScreen>(find.byType(CanvasScreen)).pane.notebookId, 'nb_home');
  });

  testWidgets('search from the Start page’s sidebar; on a computer the footer says where handwriting is read', (tester) async {
    await pumpApp(tester, store: searchLibrary(FakeRecognizer()), recognizer: const NoInkRecognizer());
    await tester.tap(find.bySemanticsLabel('Search notes & handwriting'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(find.textContaining('Handwriting is recognized on the tablet. Here, search finds typed text'), findsOneWidget);
    await _settle(tester);
    // Typed text and PDFs are found without a recognizer.
    await _search(tester, 'momentum');
    expect(find.text('2 matches in 2 notebooks'), findsOneWidget);
    await _search(tester, 'zebra');
    expect(find.text('No matches for “zebra”'), findsOneWidget);
  });

  testWidgets('write the search with the pen', (tester) async {
    final r = FakeRecognizer();
    await pumpCanvas(tester, store: searchLibrary(r), notebookId: 'nb_home', recognizer: r);
    await tester.tap(byLabel('Search'));
    await tester.pumpAndSettle();
    await _settle(tester);
    await tester.tap(find.bySemanticsLabel('Write your search with the S Pen'));
    await tester.pumpAndSettle();
    final pad = tester.getTopLeft(find.bySemanticsLabel('Writing pad'));
    const start = Offset(60, 80);
    // The pad's 1 px border: its points start just inside it.
    r
      ..labelAt(start, 'pears')
      ..labelAt(start - const Offset(1, 1), 'pears');
    final g = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await g.down(pad + start);
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(pad + start + Offset(i * 8.0, i.isEven ? 0 : 20));
    }
    await g.up();
    await tester.pump(const Duration(milliseconds: 900));
    await _settle(tester);
    expect(find.text('pears'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Search').last);
    await tester.pumpAndSettle();
    await _settle(tester);
    expect(find.text('1 match in 1 notebook'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'pears');
  });
}
