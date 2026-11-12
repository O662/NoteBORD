import 'dart:convert';

import 'package:endless/board/codec.dart';
import 'package:endless/board/ids.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/library/library.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/sync/doc.dart';
import 'package:endless/ui/routes.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

// A screen stays on its page when pages are added, removed or moved before
// it by something else: another device's changes (cloud sync), or the other
// side of Split view.

/// A notebook of pages titled [titles], one stroke on each.
(MemoryBoardStore, String) _notebook(List<String> titles) {
  final store = MemoryBoardStore();
  final now = DateTime.utc(2026, 9, 25, 9);
  final pages = [
    for (final (i, t) in titles.indexed)
      BoardPage(id: newId('pg'), title: t, items: [strokeFrom([Offset(10, 10.0 + i), const Offset(80, 40)])]),
  ];
  final nb = Notebook(id: newId('nb'), title: 'Notes', createdAt: now, updatedAt: now, pageIds: [for (final p in pages) p.id]);
  for (final p in pages) {
    store.savePage(nb.id, p);
  }
  store.saveNotebook(nb);
  return (store, nb.id);
}

BoardDoc _docOf(NotebookState s) => BoardDoc(
      notebook: jsonDecode(encodeNotebook(s.notebook)) as Json,
      pages: {for (final p in s.pages) p.id: jsonDecode(encodePage(p.page)) as Json},
    );

void main() {
  setUpAll(loadAppFonts);

  testWidgets('pages added, removed and moved before the page on screen: it stays on screen', (tester) async {
    final (store, id) = _notebook(['A', 'B', 'C']);
    final c = await pumpCanvas(tester, store: store, notebookId: id);
    final n = c.read(notebookProvider(id).notifier);
    canvasPane.goTo(2);
    await tester.pump();
    final shown = shownPage(c).id;
    expect(shownPage(c).page.title, 'C');
    expect(find.text('3 of 3'), findsOneWidget);
    // Somewhere on the page, zoomed in: that stays too.
    canvasPane.view.jumpTo(2, const Offset(-300, -120));
    await tester.pump();

    // Another device adds a page at the front (cloud sync).
    final from = _docOf(shownNotebook(c));
    final to = _docOf(shownNotebook(c));
    final added = BoardPage(id: newId('pg'), title: 'From the other tablet');
    to.pages[added.id] = jsonDecode(encodePage(added)) as Json;
    to.notebook['pages'] = [added.id, ...from.pageOrder];
    expect(n.applyRemote(from, to), isTrue);
    // At once: a stroke finished right now goes on the page being written on.
    expect(shownPage(c).id, shown);
    expect(canvasPane.page, 3);
    await tester.pump();
    expect(find.text('4 of 4'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
    expect(canvasPane.view.scale, 2);
    expect(canvasPane.view.translation, const Offset(-300, -120));
    // The library opens the notebook here again, under the page's new number.
    expect(c.read(libraryProvider).byId(id)!.lastPage, 3);

    // It removes that page again.
    expect(n.applyRemote(to, from), isTrue);
    expect(shownPage(c).id, shown);
    expect(canvasPane.page, 2);
    await tester.pump();
    expect(find.text('3 of 3'), findsOneWidget);

    // Pages put in another order.
    n.movePage(0, 2);
    expect(shownPage(c).id, shown);
    expect(canvasPane.page, 1);
    await tester.pump();
    expect(find.text('2 of 3'), findsOneWidget);

    // The page itself goes: the screen shows the one now in its place.
    n.removePage(shown, force: true);
    await tester.pump();
    expect(canvasPane.page, 1);
    expect(shownPage(c).page.title, 'A');
    expect(find.text('2 of 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('going to a page is still the screen’s own doing', (tester) async {
    final (store, id) = _notebook(['A', 'B', 'C']);
    final c = await pumpCanvas(tester, store: store, notebookId: id);
    final n = c.read(notebookProvider(id).notifier);

    // A new page, and the screen is sent to it (the page strip's +).
    canvasPane.goTo(n.addPage(after: 0));
    await tester.pump();
    expect(canvasPane.page, 1);
    expect(shownPage(c).page.title, '');
    expect(find.text('2 of 4'), findsOneWidget);

    // A page put back where the screen already is (Undo of Delete page): the
    // screen is told to show that number, and shows the page put back.
    final b = shownNotebook(c).pages[2].id;
    canvasPane.goTo(2);
    await tester.pump();
    final removed = n.removePage(b)!;
    canvasPane.goTo(2);
    await tester.pump();
    expect(shownPage(c).page.title, 'C');
    n.restorePage(removed.$1, removed.$2);
    canvasPane.goTo(removed.$2);
    await tester.pump();
    expect(shownPage(c).page.title, 'B');
    expect(find.text('3 of 4'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Split view on two pages of one notebook: a page added in front moves both sides along', (tester) async {
    final (store, id) = _notebook(['A', 'B', 'C']);
    final c = await pumpApp(tester, store: store, location: Routes.split((id, 0), (id, 2)));
    await tester.pump();
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.text('3 / 3'), findsOneWidget);

    c.read(notebookProvider(id).notifier).addPage(after: -1);
    await tester.pump();
    expect(find.text('2 / 4'), findsOneWidget);
    expect(find.text('4 / 4'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
  });
}
