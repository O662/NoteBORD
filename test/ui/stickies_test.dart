import 'package:endless/app.dart' show routerProvider;
import 'package:endless/board/model.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/study/study_rows.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:endless/ui/canvas/canvas_screen.dart';
import 'package:endless/ui/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../sample_stickies.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('every sticky note, stacks fanned with their count, where each lives; what is left out', (tester) async {
    final semantics = tester.ensureSemantics();
    final (store, db) = await stickyLibrary();
    await pumpApp(tester, store: store, index: db, location: Routes.stickies);
    await _pump(tester);
    expect(find.text('5 notes · 1 stack · from 2 notebooks. Tap one to jump to where it lives.'), findsOneWidget);
    expect(find.text('Stack · 3'), findsOneWidget);
    expect(find.text('Page 2 · Exam notes'), findsNWidgets(2));
    expect(find.text('Page 1 · Results'), findsOneWidget);
    // The locked notebook and the page with a password are left out, and it says so.
    expect(find.textContaining('secret'), findsNothing);
    expect(
      find.text('1 locked notebook isn’t shown, and 1 page with a password isn’t either. Remove their passwords to include their sticky notes.'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('filters: stacks, loose notes, a color, a notebook, and searching what is written', (tester) async {
    final semantics = tester.ensureSemantics();
    final (store, db) = await stickyLibrary();
    await pumpApp(tester, store: store, index: db, location: Routes.stickies);
    await _pump(tester);
    int cards() => find
        .byWidgetPredicate((w) => w is Semantics && RegExp(r'^(Sticky note:|Stack of \d+:)').hasMatch(w.properties.label ?? ''))
        .evaluate()
        .length;
    expect(cards(), 3);

    await tester.tap(find.bySemanticsLabel('Stacks, 1'));
    await _pump(tester);
    expect(cards(), 1);
    await tester.tap(find.bySemanticsLabel('Loose notes, 2'));
    await _pump(tester);
    expect(cards(), 2);
    await tester.tap(find.bySemanticsLabel('All, 3'));
    await _pump(tester);

    // Green: the loose green note, and the stack with a green note in it.
    await tester.tap(find.bySemanticsLabel('Only green notes'));
    await _pump(tester);
    expect(cards(), 2);
    await tester.tap(find.bySemanticsLabel('Showing green notes'));
    await _pump(tester);
    expect(cards(), 3);

    await tester.tap(find.bySemanticsLabel('Lab journal').last);
    await _pump(tester);
    expect(cards(), 1);
    await tester.tap(find.bySemanticsLabel('All notebooks').last);
    await _pump(tester);

    // Words on a note under the top one count too.
    await tester.enterText(find.byType(TextField), 'conservation');
    await _pump(tester);
    expect(cards(), 1);
    expect(find.text('Stack · 3'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'zebra');
    await _pump(tester);
    expect(find.text('No sticky notes match'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await _pump(tester);
    expect(cards(), 3);
    semantics.dispose();
  });

  testWidgets('a stack opens to all its notes, and Open on the page goes to its page', (tester) async {
    final semantics = tester.ensureSemantics();
    final (store, db) = await stickyLibrary();
    await pumpApp(tester, store: store, index: db, location: Routes.stickies);
    await _pump(tester);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Stack of 3')));
    await _pump(tester);
    expect(find.text('Stack of 3 · Physics — Lecture notes · Page 2 · Exam notes'), findsOneWidget);
    expect(find.text('1 of 3'), findsOneWidget);
    expect(find.text('3 of 3'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Open on the page'));
    await _pump(tester);
    expect(find.byType(CanvasScreen), findsOneWidget);
    expect(tester.widget<CanvasScreen>(find.byType(CanvasScreen)).pane.page, 1);
    await tester.pump(const Duration(seconds: 5));
    semantics.dispose();
  });

  testWidgets('a note put on a page shows up here, from the index', (tester) async {
    final store = storeWith(sampleNotebook());
    final c = await pumpCanvas(tester, store: store);
    final page = shownPage(c).page;
    c.read(notebookProvider(canvasPane.notebookId).notifier).insertItems(page.id, [stickyNote('remember the units')]);
    await tester.pump(const Duration(seconds: 1));
    c.read(routerProvider).go(Routes.stickies);
    await _pump(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('1 note · 0 stacks · from 1 notebook. Tap one to jump to where it lives.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  test('stickyText: typed text, top note first, then the notes under it', () {
    final s = stickyNote('top', under: [
      StickyNote(color: tokens.stickyColors[1], items: [
        TextItem(id: 'it_u', x: 0, y: 0, z: 1, createdAt: stickyAt, text: 'under', size: 20, color: tokens.inkDefaults[0], wrap: 200),
      ]),
    ]);
    expect(stickyText(s, null), 'top under');
    final row = studyRowsFor('nb', BoardPage(id: 'pg', title: 'T', items: [s]), null).single;
    expect(row.kind, StudyKind.sticky);
    final e = StickyEntry.fromRow(row);
    expect(e.isStack, isTrue);
    expect(e.count, 2);
    expect(e.colors, [tokens.stickyColors[0], tokens.stickyColors[1]]);
    expect(e.pageTitle, 'T');
  });
}
