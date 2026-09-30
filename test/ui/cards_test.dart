import 'package:endless/board/codec.dart';
import 'package:endless/board/ids.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/canvas/cards.dart';
import 'package:endless/state/links.dart';
import 'package:endless/state/settings.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../sample_board.dart';

List<Item> _items(ProviderContainer c) => shownPage(c).items;

CardItem _card(ProviderContainer c) => _items(c).whereType<CardItem>().single;

/// A notebook with one page holding [items] (page coords = screen coords).
MemoryBoardStore _storeWith(List<Item> items) {
  final now = DateTime.utc(2026, 9, 25, 9);
  final page = BoardPage(id: newId('pg'), items: items);
  final nb = Notebook(id: newId('nb'), title: 'Cards', createdAt: now, updatedAt: now, pageIds: [page.id]);
  return storeWith(LoadedNotebook(nb, [page]));
}

/// [card] moved so its top-left corner is at [at], where the chrome is clear.
CardItem _at(CardItem card, Offset at) => card.withBox(x: at.dx, y: at.dy, w: card.w, h: card.h);

Future<void> _pen(WidgetTester tester, List<Offset> points) async {
  final g = await tester.createGesture(kind: PointerDeviceKind.stylus);
  var t = const Duration(seconds: 20);
  await g.down(points.first, timeStamp: t);
  for (final p in points.skip(1)) {
    t += const Duration(milliseconds: 8);
    await g.moveTo(p, timeStamp: t);
  }
  await g.up(timeStamp: t);
  await tester.pump();
}

List<Offset> _line(Offset a, Offset b, {int n = 10}) => [for (var i = 0; i <= n; i++) Offset.lerp(a, b, i / n)!];

/// Picks something in the full Insert menu.
Future<void> _insert(WidgetTester tester, String tile) async {
  await tester.tap(byLabel('Insert'));
  await tester.pump();
  await tester.tap(find.text('Everything else'));
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsLabel(tile));
  await tester.pumpAndSettle();
}

Future<void> _action(WidgetTester tester, String label) async {
  await tester.tap(find.bySemanticsLabel(label));
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pump();
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  final field = find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextField));
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  await tester.pump();
}

Future<void> _undo(WidgetTester tester) async {
  await tester.tap(byLabel('Undo'));
  await tester.pump();
}

/// Opens the editor of the one card on the page (it must be selected, or
/// Select must be the tool).
Future<void> _edit(WidgetTester tester, ProviderContainer c) async {
  if (canvasPane.selection.isEmpty) {
    await tester.tap(byLabel('Select'));
    await tester.pump();
    await _pen(tester, [canvasPane.view.toScreen(_card(c).center)]);
  }
  await _action(tester, 'Edit');
}

void main() {
  setUpAll(loadAppFonts);

  group('Kanban board', () {
    testWidgets('comes from the Insert menu, is edited in its editor, and each save is one undo step', (tester) async {
      final c = await pumpCanvas(tester, store: _storeWith(const []));
      await _insert(tester, 'Kanban board');

      var card = _card(c);
      expect(card.type, 'kanban');
      expect((card.data as KanbanData).columns.map((col) => col.title), ['To do', 'Doing', 'Done']);
      expect(Size(card.w, card.h), const Size(578, 374)); // 420 × 272 on Board.png, at the scale cards are drawn
      expect(card.center, const Offset(640, 400));
      expect(find.text('Added a Kanban board to the page'), findsOneWidget);
      expect(c.read(settingsProvider).tool, CanvasTool.select);
      expect(canvasPane.selection.ids, {card.id});
      for (final label in ['Edit', 'Copy', 'To front', 'To back', 'Delete']) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      expect(find.bySemanticsLabel('Color'), findsNothing);

      await _edit(tester, c);
      expect(find.text('Add column'), findsOneWidget); // its editor is open
      await _type(tester, 'card-name', 'Study tasks');
      await _tapKey(tester, 'kanban-add-0');
      await _type(tester, 'kanban-card-0-0', 'Read chapter 9');
      await _tapKey(tester, 'kanban-add-0');
      await _type(tester, 'kanban-card-0-1', 'Lab 4 report');
      await _tapKey(tester, 'kanban-add-0'); // left empty: not kept
      await _tapKey(tester, 'kanban-right-0-1'); // "Lab 4 report" goes to Doing
      expect(find.byKey(const ValueKey('kanban-card-1-0')), findsOneWidget);
      await _type(tester, 'kanban-column-2', 'Finished');
      await _action(tester, 'Save');

      card = _card(c);
      final data = card.data as KanbanData;
      expect(card.title, 'Study tasks');
      expect(data.columns.map((col) => col.title), ['To do', 'Doing', 'Finished']);
      expect(data.columns.map((col) => col.cards.map((k) => k.text)), [
        ['Read chapter 9'],
        ['Lab 4 report'],
        [],
      ]);

      // Columns can be added (up to five) and removed; Cancel changes nothing.
      await _edit(tester, c);
      await _action(tester, 'Add column');
      await _type(tester, 'kanban-column-3', 'Later');
      await _action(tester, 'Remove column 2');
      await _action(tester, 'Cancel');
      expect((_card(c).data as KanbanData).columns, hasLength(3));
      await _edit(tester, c);
      await _action(tester, 'Add column');
      await _type(tester, 'kanban-column-3', 'Later');
      await _tapKey(tester, 'kanban-delete-0-0');
      await _action(tester, 'Save');
      expect((_card(c).data as KanbanData).columns.map((col) => col.title), ['To do', 'Doing', 'Finished', 'Later']);
      expect((_card(c).data as KanbanData).columns.first.cards, isEmpty);

      await _undo(tester);
      expect((_card(c).data as KanbanData).columns, hasLength(3));
      expect((_card(c).data as KanbanData).columns.first.cards.single.text, 'Read chapter 9');
      await _undo(tester);
      expect(_card(c).title, '');
      await _undo(tester);
      expect(_items(c), isEmpty);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('grows when it needs room for more cards', (tester) async {
      final card = _at(sampleKanban, const Offset(200, 150));
      final c = await pumpCanvas(tester, store: _storeWith([card]));
      await _edit(tester, c);
      for (var i = 2; i < 10; i++) {
        await _tapKey(tester, 'kanban-add-0');
        await _type(tester, 'kanban-card-0-$i', 'Problem set ${i + 3}');
      }
      await _action(tester, 'Save');
      final grown = _card(c);
      expect((grown.data as KanbanData).columns.first.cards, hasLength(10));
      expect(grown.h, greaterThan(card.h + 80));
      expect(grown.h, closeTo(cardNaturalHeight(grown.data, grown.w / grown.unit) * grown.unit, 0.01));
      expect((grown.x, grown.y, grown.w), (card.x, card.y, card.w));
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('timeline, diagram and table', () {
    testWidgets('a timeline’s events can be changed, marked, reordered and removed', (tester) async {
      final c = await pumpCanvas(tester, store: _storeWith(const []));
      await _insert(tester, 'Timeline');
      var card = _card(c);
      expect(card.type, 'timeline');
      expect((card.data as TimelineData).events, hasLength(3));
      expect((card.data as TimelineData).events.first.state, EventState.now);
      expect(find.text('Added a timeline to the page'), findsOneWidget);

      await _edit(tester, c);
      await _type(tester, 'card-name', 'Semester');
      await _type(tester, 'timeline-date-0', 'Sep 30');
      await _type(tester, 'timeline-label-0', 'Lab report');
      await _tapKey(tester, 'timeline-state-0'); // up next → to come
      await _tapKey(tester, 'timeline-state-0'); // to come → done
      await _type(tester, 'timeline-date-1', 'Oct 14');
      await _type(tester, 'timeline-label-1', 'Midterm');
      await _tapKey(tester, 'timeline-delete-2');
      await _action(tester, 'Add event');
      await _type(tester, 'timeline-date-2', 'Dec 9');
      await _type(tester, 'timeline-label-2', 'Final exam');
      await _action(tester, 'Add event'); // left empty: not kept
      await _action(tester, 'Save');

      card = _card(c);
      expect(card.title, 'Semester');
      expect([for (final e in (card.data as TimelineData).events) (e.date, e.label, e.state)], [
        ('Sep 30', 'Lab report', EventState.done),
        ('Oct 14', 'Midterm', EventState.later),
        ('Dec 9', 'Final exam', EventState.later),
      ]);

      await _edit(tester, c);
      await tester.tap(find.bySemanticsLabel('Move later').first);
      await tester.pump();
      await _action(tester, 'Save');
      expect((_card(c).data as TimelineData).events.map((e) => e.date), ['Oct 14', 'Sep 30', 'Dec 9']);
      await _undo(tester);
      expect((_card(c).data as TimelineData).events.map((e) => e.date), ['Sep 30', 'Oct 14', 'Dec 9']);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a diagram’s steps point to the next; shapes and colors change with a tap', (tester) async {
      final c = await pumpCanvas(tester, store: _storeWith(const []));
      await _insert(tester, 'Diagram');
      var data = _card(c).data as DiagramData;
      expect(data.nodes.map((n) => n.text), ['Start', 'Step', 'Done?']);
      expect(data.edges, [(data.nodes[0].id, data.nodes[1].id), (data.nodes[1].id, data.nodes[2].id)]);
      expect(find.text('Added a diagram to the page'), findsOneWidget);

      await _edit(tester, c);
      await _type(tester, 'diagram-step-1', 'Collide');
      await _tapKey(tester, 'diagram-shape-1'); // box → rounded
      await _tapKey(tester, 'diagram-color-1'); // blue → terracotta
      await _action(tester, 'Add step');
      await _type(tester, 'diagram-step-3', 'Write it up');
      await _tapKey(tester, 'diagram-delete-0');
      await _action(tester, 'Save');

      data = _card(c).data as DiagramData;
      expect([for (final n in data.nodes) (n.text, n.shape, n.color)], [
        ('Collide', NodeShape.pill, NodeColor.clay),
        ('Done?', NodeShape.diamond, NodeColor.green),
        ('Write it up', NodeShape.box, NodeColor.blue),
      ]);
      expect(data.edges, [(data.nodes[0].id, data.nodes[1].id), (data.nodes[1].id, data.nodes[2].id)]);
      await _undo(tester);
      expect((_card(c).data as DiagramData).nodes.first.text, 'Start');
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('arrows from another app are kept when a diagram is edited here', (tester) async {
      final branching = sampleDiagram.copyWith(
        data: DiagramData((sampleDiagram.data as DiagramData).nodes, const [('n1', 'n2'), ('n1', 'n3'), ('n3', 'n4')]),
      );
      final c = await pumpCanvas(tester, store: _storeWith([_at(branching, const Offset(200, 200))]));
      await _edit(tester, c);
      await _type(tester, 'diagram-step-0', 'Measure speed');
      await _tapKey(tester, 'diagram-delete-3');
      await _action(tester, 'Save');
      final data = _card(c).data as DiagramData;
      expect(data.nodes.first.text, 'Measure speed');
      expect(data.edges, [('n1', 'n2'), ('n1', 'n3')]); // only the arrow to the removed step went
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a table’s cells, rows and columns', (tester) async {
      final c = await pumpCanvas(tester, store: _storeWith(const []));
      await _insert(tester, 'Table');
      var card = _card(c);
      var data = card.data as TableData;
      expect((data.rows, data.columns, data.header), (4, 3, true));
      expect(find.text('Added a table to the page'), findsOneWidget);

      await _edit(tester, c);
      await _type(tester, 'card-name', 'Lab data');
      for (final (i, name) in ['Trial', 'm', 'v'].indexed) {
        await _type(tester, 'table-cell-0-$i', name);
      }
      await _type(tester, 'table-cell-1-0', '1');
      await _type(tester, 'table-cell-1-1', '0.50');
      await _action(tester, 'Add column');
      await _type(tester, 'table-cell-0-3', 'p');
      await _action(tester, 'Remove row');
      await _action(tester, 'Save');

      card = _card(c);
      data = card.data as TableData;
      expect(card.title, 'Lab data');
      expect(data.cells, [
        ['Trial', 'm', 'v', 'p'],
        ['1', '0.50', '', ''],
        ['', '', '', ''],
      ]);

      await _edit(tester, c);
      await _action(tester, 'The first row is the column names');
      for (var i = 0; i < 9; i++) {
        await _action(tester, 'Add row');
      }
      await _action(tester, 'Save');
      final taller = _card(c);
      expect((taller.data as TableData).header, isFalse);
      expect((taller.data as TableData).rows, 12);
      expect(taller.h, greaterThan(card.h)); // it grew to show every row

      await _undo(tester);
      expect((_card(c).data as TableData).rows, 3);
      expect(_card(c).h, card.h);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('website', () {
    testWidgets('asks for the address first; Open hands it to the browser', (tester) async {
      final browser = FakeLinkOpener();
      final c = await pumpCanvas(tester,
          store: _storeWith(const []), extra: [linkOpenerProvider.overrideWithValue(browser)]);
      await _insert(tester, 'Website');
      expect(find.text('Web address'), findsOneWidget);
      expect(_items(c), isEmpty);

      // Not an address: it says so, and can't be added.
      await tester.enterText(find.byType(TextField).first, 'not an address');
      await tester.pump();
      expect(find.text('That doesn’t look like a web address'), findsOneWidget);
      await tester.tap(find.text('Add to page'));
      await tester.pumpAndSettle();
      expect(find.text('Web address'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'example.com/collision-lab');
      await tester.enterText(find.byType(TextField).last, 'Collision lab simulation');
      await tester.pump();
      expect(find.text('That doesn’t look like a web address'), findsNothing);
      await _action(tester, 'Add to page');

      final card = _card(c);
      expect(card.type, 'embed');
      expect((card.data as EmbedData).url, 'https://example.com/collision-lab');
      expect(card.title, 'Collision lab simulation');
      expect(Size(card.w, card.h), const Size(399, 275));
      expect(find.text('Added a website to the page'), findsOneWidget);

      await _action(tester, 'Open');
      expect(browser.opened, [Uri.parse('https://example.com/collision-lab')]);

      // A finger tap on the card's Open button opens it too, whatever the tool.
      await tester.tap(byLabel('Pen'));
      await tester.pump();
      const later = Duration(minutes: 5);
      final finger = await tester.createGesture(kind: PointerDeviceKind.touch, pointer: 70);
      await finger.down(card.toPage(embedOpenRect(card).center), timeStamp: later);
      await finger.up(timeStamp: later);
      await tester.pump();
      expect(browser.opened, hasLength(2));
      // A tap anywhere else on it does nothing.
      await finger.down(card.center, timeStamp: later);
      await finger.up(timeStamp: later);
      await tester.pump();
      expect(browser.opened, hasLength(2));

      // Its address can be changed; backing out of the first question adds nothing.
      await _edit(tester, c);
      await tester.enterText(find.byType(TextField).first, 'https://example.org');
      await tester.pump();
      await _action(tester, 'Save');
      expect((_card(c).data as EmbedData).url, 'https://example.org');
      await _insert(tester, 'Website');
      await _action(tester, 'Cancel');
      expect(_items(c), hasLength(1));
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('an address that isn’t a web page is never opened', (tester) async {
      final browser = FakeLinkOpener();
      final unsafe = _at(sampleWebsite.copyWith(data: const EmbedData('javascript:alert(1)')), const Offset(300, 250));
      await pumpCanvas(tester, store: _storeWith([unsafe]), extra: [linkOpenerProvider.overrideWithValue(browser)]);
      await tester.tap(byLabel('Select'));
      await tester.pump();
      await _pen(tester, [unsafe.center]);
      await _action(tester, 'Open');
      expect(browser.opened, isEmpty);
      expect(find.text('Couldn’t open that address'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('cards on the page', () {
    testWidgets('move, scale by a corner and stretch by an edge, each one undo step', (tester) async {
      final card = _at(sampleKanban, const Offset(200, 150)); // 577.5 × 374: 200…777.5, 150…524
      final on = strokeFrom(_line(const Offset(300, 300), const Offset(400, 310)), z: 40);
      final off = strokeFrom(_line(const Offset(900, 600), const Offset(1000, 610)), z: 41);
      final c = await pumpCanvas(tester, store: _storeWith([card, on, off]));
      await tester.tap(byLabel('Select'));
      await tester.pump();
      await _pen(tester, const [Offset(500, 450)]);
      expect(canvasPane.selection.ids, {card.id});

      // Dragged: what's written on it goes along; what isn't stays.
      await _pen(tester, _line(const Offset(500, 450), const Offset(540, 480)));
      var moved = _card(c);
      expect((moved.x, moved.y), (240.0, 180.0));
      expect(_items(c).whereType<StrokeItem>().first.x, closeTo(on.x + 40, 0.2));
      expect(_items(c).whereType<StrokeItem>().last.x, off.x);
      await _undo(tester);
      expect((_card(c).x, _card(c).y), (200.0, 150.0));

      // The right edge (its handle is 8 px outside): wider, same text size.
      await _pen(tester, _line(const Offset(785.5, 337), const Offset(885.5, 337)));
      final wider = _card(c);
      expect(wider.w, closeTo(card.w + 100, 0.01));
      expect(wider.unit, card.unit);
      expect(wider.x, closeTo(200, 0.01));
      await _undo(tester);

      // The bottom-right corner: everything scales together.
      await _pen(tester, _line(const Offset(785.5, 532), const Offset(885.5, 597)));
      final bigger = _card(c);
      expect(bigger.unit, greaterThan(card.unit * 1.1));
      expect(bigger.w / bigger.h, closeTo(card.w / card.h, 1e-6));
      expect(bigger.unit / card.unit, closeTo(bigger.w / card.w, 1e-6));
      await _undo(tester);
      expect(_card(c).unit, card.unit);

      // Copy and delete work as for anything else.
      await _action(tester, 'Copy');
      expect(_items(c).whereType<CardItem>(), hasLength(2));
      expect(_items(c).whereType<CardItem>().last.id, isNot(card.id));
      await _action(tester, 'Delete');
      expect(_items(c).whereType<CardItem>().single.id, card.id);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('are saved in the page and come back', (tester) async {
      final store = _storeWith(const []);
      final c = await pumpCanvas(tester, store: store);
      for (final tile in ['Kanban board', 'Timeline', 'Diagram', 'Table']) {
        await _insert(tester, tile);
      }
      await tester.pump(const Duration(seconds: 1));
      expect(_items(c), hasLength(4));

      final id = canvasPane.notebookId;
      final saved = decodePage(store.pages[id]!.values.single);
      expect(saved.items.map((i) => i.type), ['kanban', 'timeline', 'diagram', 'table']);
      expect(saved.items.every((i) => i is CardItem), isTrue);
      expect(find.textContaining('· Saved'), findsOneWidget);
      final again = (await store.loadNotebook(id))!;
      expect([for (final i in again.pages.single.items) (i as CardItem).data.runtimeType],
          [KanbanData, TimelineData, DiagramData, TableData]);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('the whole sample board draws, in the page and on the whole board', (tester) async {
      final c = await pumpCanvas(tester, store: storeWith(sampleBoard()));
      expect(_items(c).whereType<CardItem>().map((i) => i.type), ['kanban', 'table', 'timeline', 'embed', 'diagram']);
      expect(tester.takeException(), isNull);
      await tester.tap(byLabel('Zoom out to the whole board'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final view = canvasPane.view;
      for (final card in _items(c).whereType<CardItem>()) {
        expect(view.visiblePage.contains(card.extent.topLeft), isTrue, reason: card.type);
        expect(view.visiblePage.contains(card.extent.bottomRight), isTrue, reason: card.type);
      }
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
