import 'package:endless/board/codec.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:endless/ui/common.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

Future<void> _tapLabel(WidgetTester tester, String label) async {
  await tester.tap(find.bySemanticsLabel(label).hitTestable().first);
  await tester.pump();
}

/// The toast's Undo (or other action) button.
Future<void> _toastAction(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(InkWell, label).last);
  await tester.pumpAndSettle();
}

List<String> _titles(ProviderContainer c) => [for (final p in shownNotebook(c).pages) p.page.title];

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the page bar: previous and next, the page and "3 of 4", the preview card', (tester) async {
    final semantics = tester.ensureSemantics();
    final c = await pumpCanvas(tester, store: storeWith(sampleNotebook()));
    expect(find.text('1 of 4'), findsOneWidget);
    expect(find.text('Untitled page'), findsOneWidget);

    await tester.tap(byLabel('Next page'));
    await tester.pump();
    await tester.tap(byLabel('Next page'));
    await tester.pump();
    expect(canvasPane.page, 2);
    expect(find.text('3 of 4'), findsOneWidget);
    expect(find.text('Lecture 3 — Momentum'), findsOneWidget);

    // Tapping the title opens the preview: the whole page, when it was edited, and its neighbors.
    await _tapLabel(tester, 'Page 3: Lecture 3 — Momentum. Tap for the preview');
    await tester.pumpAndSettle();
    expect(find.text('PREVIEW'), findsOneWidget);
    expect(find.textContaining('Page 3 of 4 · edited'), findsOneWidget);
    expect(find.bySemanticsLabel('Previous page: Untitled page'), findsOneWidget);
    await _tapLabel(tester, 'Next page: Untitled page');
    expect(canvasPane.page, 3);

    await tester.tap(byLabel('Close preview'));
    await tester.pump();
    expect(find.text('PREVIEW'), findsNothing);
    expect(byLabel('Next page'), findsOneWidget);
    expect(tester.widget<ChromeButton>(byLabel('Next page')).enabled, isFalse);
    expect(c.read(notebookProvider(canvasPane.notebookId)).pages, hasLength(4));
    semantics.dispose();
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('All pages: a strip of every page, Add page, tap to go, Hide; reorder keeps your page', (tester) async {
    final semantics = tester.ensureSemantics();
    final c = await pumpCanvas(tester, store: storeWith(sampleNotebook()));
    await tester.tap(byLabel('Show all pages'));
    await tester.pump();
    expect(find.text('ALL PAGES · 4'), findsOneWidget);
    expect(find.bySemanticsLabel('Page 4: Untitled page, locked'), findsOneWidget);

    await _tapLabel(tester, 'Add page');
    expect(find.text('ALL PAGES · 5'), findsOneWidget);
    expect(canvasPane.page, 4);
    await _tapLabel(tester, 'Page 3: Lecture 3 — Momentum');
    expect(canvasPane.page, 2);

    // Moving page 3 to the front: you stay on it.
    shownNotebook(c);
    c.read(notebookProvider(canvasPane.notebookId).notifier).movePage(2, 0);
    await tester.pump();
    expect(shownNotebook(c).pages.first.id, 'pg_03');
    expect(shownNotebook(c).notebook.pageIds.first, 'pg_03');

    // The grid button toggles the strip, and so does Hide.
    await _tapLabel(tester, 'Hide all pages');
    expect(find.textContaining('ALL PAGES'), findsNothing);
    await tester.tap(byLabel('Show all pages'));
    await tester.pump();
    await tester.tap(byLabel('Show all pages'));
    await tester.pump();
    expect(find.textContaining('ALL PAGES'), findsNothing);
    semantics.dispose();
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('page menu: Rename in the bar, Page color, Duplicate and Delete with Undo', (tester) async {
    final semantics = tester.ensureSemantics();
    final store = storeWith(sampleNotebook());
    final c = await pumpCanvas(tester, store: store);
    await tester.tap(byLabel('Next page'));
    await tester.pump();
    await tester.tap(byLabel('Next page'));
    await tester.pump();

    // Rename.
    await tester.tap(byLabel('Page options'));
    await tester.pump();
    expect(find.text('LECTURE 3 — MOMENTUM'), findsOneWidget);
    await _tapLabel(tester, 'Rename. Change the page title');
    await tester.enterText(find.byType(TextField), 'Momentum & impulse');
    await _tapLabel(tester, 'Save name');
    expect(shownPage(c).page.title, 'Momentum & impulse');
    expect(find.text('Momentum & impulse'), findsOneWidget);

    // Page color: the dot, and saved in the page file.
    await tester.tap(byLabel('Page options'));
    await tester.pump();
    await _tapLabel(tester, 'Teal');
    expect(shownPage(c).page.color, tokens.pageColors[5]);
    await _tapLabel(tester, 'No color');
    expect(shownPage(c).page.color, isNull);
    await _tapLabel(tester, 'Teal');
    await tester.pump(const Duration(seconds: 1));
    expect(decodePage(store.pages[canvasPane.notebookId]!['pg_03']!).color, tokens.pageColors[5]);

    // Duplicate: after it, with new ids; Undo takes it away.
    await _tapLabel(tester, 'Duplicate. Adds a copy after this page');
    expect(find.text('Page duplicated'), findsOneWidget);
    expect(_titles(c), ['', '', 'Momentum & impulse', 'Momentum & impulse (copy)', '']);
    expect(canvasPane.page, 3);
    final original = shownNotebook(c).pages[2].page, copy = shownNotebook(c).pages[3].page;
    expect(copy.items, hasLength(original.items.length));
    expect(copy.color, tokens.pageColors[5]);
    expect({for (final i in copy.items) i.id}.intersection({for (final i in original.items) i.id}), isEmpty);
    await _toastAction(tester, 'Undo');
    expect(_titles(c), ['', '', 'Momentum & impulse', '']);

    // Delete, then Undo puts it back where it was.
    await tester.tap(byLabel('Page options'));
    await tester.pump();
    await _tapLabel(tester, 'Delete page');
    expect(find.text('Page deleted'), findsOneWidget);
    expect(shownNotebook(c).pages.map((p) => p.id), ['pg_01', 'pg_02', 'pg_04']);
    await _toastAction(tester, 'Undo');
    expect(shownNotebook(c).pages.map((p) => p.id), ['pg_01', 'pg_02', 'pg_03', 'pg_04']);
    expect(canvasPane.page, 2);

    semantics.dispose();
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Move to…: the page goes to another notebook with its ink; Undo brings it back', (tester) async {
    final semantics = tester.ensureSemantics();
    final store = storeWith(sampleNotebook());
    final other = addUntitled(store);
    final c = await pumpCanvas(tester, store: store, notebookId: 'nb_sample');
    await tester.tap(byLabel('Next page'));
    await tester.pump();
    await tester.tap(byLabel('Next page'));
    await tester.pump();
    final ink = shownPage(c).items.length;

    await tester.tap(byLabel('Page options'));
    await tester.pump();
    await _tapLabel(tester, 'Move to…. Another notebook');
    expect(find.text('Move page to…'), findsOneWidget);
    expect(find.textContaining('This notebook · 4 pages'), findsOneWidget);
    await tester.tap(find.text('Untitled notebook'));
    await tester.pumpAndSettle();
    expect(find.text('Moved to Untitled notebook'), findsOneWidget);
    expect(shownNotebook(c).pages.map((p) => p.id), ['pg_01', 'pg_02', 'pg_04']);
    final there = store.notebooks[other]!;
    expect(decodeNotebook(there).pageIds, hasLength(2));
    expect(decodePage(store.pages[other]!['pg_03']!).items, hasLength(ink));

    await _toastAction(tester, 'Undo');
    await tester.pumpAndSettle();
    expect(shownNotebook(c).pages.map((p) => p.id), ['pg_01', 'pg_02', 'pg_03', 'pg_04']);
    expect(decodeNotebook(store.notebooks[other]!).pageIds, hasLength(1));
    semantics.dispose();
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Edit page: paper and template, live; ⋯ → Page & paper opens it too', (tester) async {
    final semantics = tester.ensureSemantics();
    final c = await pumpCanvas(tester, store: storeWith(sampleNotebook()));
    await tester.tap(byLabel('Page options'));
    await tester.pump();
    await _tapLabel(tester, 'Edit page. Paper, template and background');
    await tester.pumpAndSettle();
    expect(find.text('Edit page'), findsOneWidget);
    await _tapLabel(tester, 'Grid');
    expect(shownPage(c).page.paper, Paper.grid);
    await _tapLabel(tester, 'Cornell notes');
    expect(shownPage(c).page.template, 'cornell');
    await _tapLabel(tester, 'None');
    expect(shownPage(c).page.template, isNull);
    await _tapLabel(tester, 'Done');
    await tester.pumpAndSettle();

    await tester.tap(byLabel('More options'));
    await tester.pump();
    await tester.tap(find.text('Page & paper'));
    await tester.pumpAndSettle();
    expect(find.text('Edit page'), findsOneWidget);
    semantics.dispose();
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('swipe up to tuck the colors tray away, pull the tab down to bring it back; the setting', (tester) async {
    final semantics = tester.ensureSemantics();
    final c = await pumpCanvas(tester);
    expect(find.text('6/10'), findsOneWidget);

    final handle = find.bySemanticsLabel('Tuck colors away (or swipe up)');
    await tester.drag(handle, const Offset(0, -30), kind: PointerDeviceKind.stylus);
    await tester.pumpAndSettle();
    expect(find.text('6/10'), findsNothing);
    expect(c.read(settingsProvider).trayOpen, isFalse);

    final tab = find.bySemanticsLabel('Pull down for more colors');
    expect(tab, findsOneWidget);
    // Pulling up does nothing; down brings it back.
    await tester.drag(tab, const Offset(0, -20));
    await tester.pumpAndSettle();
    expect(find.text('6/10'), findsNothing);
    await tester.drag(tab, const Offset(0, 30));
    await tester.pumpAndSettle();
    expect(find.text('6/10'), findsOneWidget);

    // A tap tucks it too.
    await _tapLabel(tester, 'Tuck colors away (or swipe up)');
    expect(find.text('6/10'), findsNothing);
    await _tapLabel(tester, 'Pull down for more colors');
    expect(find.text('6/10'), findsOneWidget);

    // The pen settings panel tucks away the same way.
    await tester.tap(byLabel('Color and thickness'));
    await tester.pump();
    expect(find.text('Swipe up to tuck away'), findsOneWidget);
    await tester.drag(find.bySemanticsLabel('Tuck pen settings away (or swipe up)'), const Offset(0, -40));
    await tester.pumpAndSettle();
    expect(find.text('Swipe up to tuck away'), findsNothing);

    // Turned off: no handles and no tab; the tool bar's button still shows and hides the tray.
    c.read(settingsProvider.notifier).apply((s) => s.copyWith(swipeTuck: false));
    await tester.pump();
    expect(find.bySemanticsLabel('Tuck colors away (or swipe up)'), findsNothing);
    await tester.tap(byLabel('More colors'));
    await tester.pump();
    expect(find.text('6/10'), findsNothing);
    expect(find.bySemanticsLabel('Pull down for more colors'), findsNothing);
    semantics.dispose();
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the tool menu is centered on the left edge', (tester) async {
    await pumpCanvas(tester);
    final rail = tester.getRect(find.bySemanticsLabel('Page tools'));
    expect(rail.left, 12);
    expect(rail.center.dy, closeTo(400, 1));
    await tester.pump(const Duration(seconds: 5));
  });

  test('copyPage gives new ids to the page, its items and what they hold, and keeps links between them', () {
    final a = strokeFrom([const Offset(0, 0), const Offset(10, 0)]);
    final page = BoardPage(id: 'pg_1', title: 'T', color: tokens.pageColors[0], items: [a]);
    final copy = copyPage(page);
    expect(copy.id, isNot('pg_1'));
    expect(copy.title, 'T');
    expect(copy.color, tokens.pageColors[0]);
    expect(copy.items.single.id, isNot(a.id));
    expect(copy.items.single.id, startsWith('it_'));
    expect(encodePage(copy), isNot(contains(a.id)));
  });

  test('a page color round-trips through the page file; none is left out', () {
    final page = BoardPage(id: 'pg_1', color: tokens.pageColors[2]);
    expect(decodePage(encodePage(page)).color, tokens.pageColors[2]);
    expect(encodePage(BoardPage(id: 'pg_2')), isNot(contains('"color"')));
    expect(MemoryBoardStore().pageWritten('nb', 'pg'), completion(isNull));
  });
}
