import 'dart:ui';

import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/library/library.dart';
import 'package:endless/recognition/convert.dart';
import 'package:endless/recognition/handwriting_index.dart';
import 'package:endless/recognition/segment.dart' show strokesRect;
import 'package:endless/recognition/reader.dart';
import 'package:endless/search/search.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:endless/ui/canvas/canvas_screen.dart';
import 'package:endless/ui/search/search_screen.dart';
import 'package:flutter/material.dart' show TextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'fake_ink.dart';

// Handwriting on sticky notes and Office cards: read note by note and slide
// by slide, searchable, and found again on the slide it was written on.

final _at = DateTime.utc(2026, 10, 1, 12);

/// A sticky note at (600, 100) with [top] written on it and [under] on the
/// note beneath (each in the note's own coordinates).
StickyItem _sticky(FakeRecognizer r, String top, {String? under}) => StickyItem(
      id: 'it_sticky',
      x: 600,
      y: 100,
      z: 5,
      createdAt: _at,
      w: 242,
      h: 220,
      color: tokens.stickyColors[0],
      items: writeLine(r, top, at: const Offset(20, 40)),
      under: [
        if (under != null) StickyNote(color: tokens.stickyColors[1], items: writeLine(r, under, at: const Offset(24, 60))),
      ],
    );

/// A PowerPoint card showing slide [page], with [byPage] written on slides
/// (in the slide's own points).
OfficeItem _slides(FakeRecognizer r, Map<int, String> byPage, {int page = 1}) => OfficeItem(
      id: 'it_ppt',
      x: 100,
      y: 400,
      z: 6,
      createdAt: _at,
      w: 495,
      h: 378,
      asset: 'abc.pptx',
      mime: 'pptx',
      name: 'Ch 9 slides.pptx',
      page: page,
      pages: 24,
      pageSize: const Size(960, 540),
      inkByPage: {
        for (final e in byPage.entries) e.key: writeLine(r, e.value, at: Offset(80.0 + e.key, 100)),
      },
    );

MemoryBoardStore _store(BoardPage page) {
  final store = MemoryBoardStore();
  final now = DateTime.utc(2026, 9, 25, 9);
  store.savePage('nb_board', page);
  store.saveNotebook(Notebook(id: 'nb_board', title: 'Board', createdAt: now, updatedAt: now, pageIds: [page.id]));
  return store;
}

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

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

void main() {
  group('reading', () {
    test('ink on the page, a sticky note, the note under it and each slide is read place by place', () async {
      final r = FakeRecognizer();
      final page = BoardPage(id: 'p', items: [
        ...writeLine(r, 'page words', at: const Offset(100, 600)),
        _sticky(r, 'buy milk', under: 'call mum'),
        _slides(r, {1: 'first slide', 2: 'momentum here'}),
      ]);
      final groups = inkGroupsOf(page);
      expect(groups.map((g) => (g.holder, g.sub)), [
        (null, null),
        ('it_sticky', null),
        ('it_sticky', 1),
        ('it_ppt', 1),
        ('it_ppt', 2),
      ]);
      final read = await readPage(page, language: 'en-US', recognizer: r);
      expect(read.lines.map((l) => l.text), ['page words', 'buy milk', 'call mum', 'first slide', 'momentum here']);
      // Each place is its own paragraph.
      expect(read.lines.map((l) => l.block), [0, 1, 2, 3, 4]);

      // The slide showing is placed on the card; the others are the card.
      final visible = visibleInk(page);
      final card = page.items.whereType<OfficeItem>().single;
      final shown = lineRectOn(page, read.lines[3], visible)!;
      expect(card.extent.contains(shown.center), isTrue);
      expect(shown.width, lessThan(card.w));
      expect(lineRectOn(page, read.lines[4], visible), card.extent);
      // The note under a stack's top one is the stack.
      expect(lineRectOn(page, read.lines[2], visible), page.items.whereType<StickyItem>().single.extent);
    });

    test('moving or turning the note, or turning the card to another slide, reads nothing again', () async {
      final r = FakeRecognizer();
      final sticky = _sticky(r, 'buy milk');
      final card = _slides(r, {1: 'first slide', 2: 'momentum here'});
      final first = await readPage(BoardPage(id: 'p', items: [sticky, card]), language: 'en-US', recognizer: r);
      expect(r.recognized, 3);
      final moved = sticky.placed(center: sticky.center + const Offset(300, 200), rotation: 8);
      final turned = card.copyWith(page: 2);
      final again = await readPage(BoardPage(id: 'p', items: [moved, turned]), language: 'en-US', recognizer: r, previous: first);
      expect(r.recognized, 3);
      expect(again.text, first.text);
    });
  });

  testWidgets('search finds them, says where, and the PDF text layer has what shows', (tester) async {
    final r = FakeRecognizer();
    final page = BoardPage(id: 'pg_board', items: [
      _sticky(r, 'buy momentum', under: 'momentum underneath'),
      _slides(r, {1: 'first slide', 3: 'conserved momentum'}),
    ]);
    final store = _store(page);
    final c = ProviderContainer(overrides: await testOverrides(store, recognizer: r));
    addTearDown(c.dispose);
    c.listen(settingsProvider, (_, _) {});
    c.listen(libraryProvider, (_, _) {});
    final index = c.read(handwritingIndexProvider);
    await _wait(tester, index.catchUp());
    final hits = await _wait(
      tester,
      runSearch('momentum', db: c.read(indexDbProvider), library: c.read(libraryProvider), store: store),
    );
    expect({for (final h in hits) h.row.label}, {
      'Handwriting on a sticky note',
      'Handwriting on a note in a stack',
      'Handwriting on slide 3',
    });
    final slide = hits.firstWhere((h) => h.row.on == 'pptx');
    expect(slide.row.holder, 'it_ppt');
    expect(slide.row.sub, 3);
    expect(slide.row.rect, page.items.whereType<OfficeItem>().single.extent);

    final text = await _wait(tester, index.pdfText('nb_board', [page]));
    expect([for (final run in text.runsFor(page)) run.text], ['buy momentum', 'first slide']);
  });

  testWidgets('Open at this spot turns the card to the slide the match was written on', (tester) async {
    final r = FakeRecognizer();
    final page = BoardPage(id: 'pg_board', items: [
      _slides(r, {1: 'first slide', 3: 'conserved momentum'}),
    ]);
    final store = _store(page);
    final c = await pumpCanvas(tester, store: store, recognizer: r);
    await tester.tap(byLabel('Search'));
    await tester.pumpAndSettle();
    await _settle(tester);
    await tester.enterText(find.byType(TextField), 'conserved');
    await tester.pump(const Duration(milliseconds: 250));
    await _settle(tester);
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(find.text('Handwriting on slide 3'), findsOneWidget);
    await tester.tap(find.text('Open at this spot'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    final pane = tester.widget<CanvasScreen>(find.byType(CanvasScreen)).pane;
    final card = c.read(notebookProvider(pane.notebookId)).pageAt(pane.page).items.whereType<OfficeItem>().single;
    expect(card.page, 3);
    // Turning it isn't an undo step.
    expect(c.read(notebookProvider(pane.notebookId).notifier).canUndo(page.id), isFalse);
    await tester.pump(const Duration(seconds: 3));
  });

  group('sticky notes', () {
    test('bringing a note to the top keeps the stack’s order, as Next note does', () {
      final r = FakeRecognizer();
      final a = _sticky(r, 'top note');
      final stack = a.copyWith(under: [
        StickyNote(color: tokens.stickyColors[1], items: writeLine(r, 'second', at: const Offset(30, 40))),
        StickyNote(color: tokens.stickyColors[2], items: writeLine(r, 'third', at: const Offset(40, 40))),
      ]);
      final third = stack.broughtToTop(2);
      expect(third.color, tokens.stickyColors[2]);
      expect(third.under.map((n) => n.color), [tokens.stickyColors[0], tokens.stickyColors[1]]);
      expect(third.items, stack.under[1].items);
      expect(third.count, 3);
      expect(stack.broughtToTop(1).broughtToTop(1).items, third.items);
      expect(stack.broughtToTop(3), same(stack));
      expect(stack.broughtToTop(0), same(stack));
    });

    test('convert on a note: replace types it there; keep moves the ink under it and grows the note', () {
      final r = FakeRecognizer();
      final arrow = strokeFrom([const Offset(10, 200), const Offset(100, 200)]).copyWith(arrow: () => const ArrowHeads(end: true));
      final note = _sticky(r, 'buy milk');
      final withArrow = note.copyWith(items: [...note.items, arrow]);
      final now = DateTime.utc(2026, 10, 15);

      final replaced = convertOnSticky(withArrow, 'Buy milk.', ConvertPlace.replace, now: now);
      expect(replaced.items.whereType<TextItem>().single.text, 'Buy milk.');
      expect(replaced.items.whereType<TextItem>().single.font, 'serif');
      // Only the handwriting goes.
      expect(replaced.items.whereType<StrokeItem>().map((s) => s.id), [arrow.id]);
      expect(replaced.id, note.id);

      // Typed text already there comes first.
      final typed = note.withText('Shopping', color: tokens.inkDefaults[0], at: now);
      expect(convertOnSticky(typed, 'Buy milk.', ConvertPlace.replace, now: now).items.whereType<TextItem>().single.text,
          'Shopping\nBuy milk.');

      final kept = convertOnSticky(note, 'Buy milk. ' * 12, ConvertPlace.keep, now: now);
      final t = kept.items.whereType<TextItem>().single;
      final ink = strokesRect(kept.items.whereType<StrokeItem>())!;
      expect(ink.top, greaterThanOrEqualTo(t.y + t.h));
      expect(kept.h, greaterThanOrEqualTo(ink.bottom));
      expect(kept.h, greaterThan(note.h));

      expect(convertOnSticky(note, 'x', ConvertPlace.copy, now: now), same(note));
    });

    testWidgets('select a sticky note with writing: Convert to text leads, and types it on the note (one undo step)', (tester) async {
      final r = FakeRecognizer();
      final page = BoardPage(id: 'pg_board', items: [_sticky(r, 'buy milk')]);
      final c = await pumpCanvas(tester, store: _store(page), recognizer: r);
      c.read(settingsProvider.notifier).apply((s) => s.copyWith(tool: CanvasTool.select));
      await tester.pump();
      canvasPane.selection.select(['it_sticky']);
      await tester.pump();
      expect(find.bySemanticsLabel('Convert to text'), findsOneWidget);
      expect(find.bySemanticsLabel('Edit text'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Convert to text'));
      await _settle(tester);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Buy milk');
      // A note's own ink: no "whole page".
      expect(find.bySemanticsLabel('Convert the whole page'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Convert'));
      await tester.pump();
      StickyItem note() => shownPage(c).items.whereType<StickyItem>().single;
      expect(note().items.whereType<TextItem>().single.text, 'Buy milk');
      expect(note().ink, isEmpty);
      expect(find.text('Handwriting on the note converted to text'), findsOneWidget);
      expect(canvasPane.selection.ids, {'it_sticky'});
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(note().ink, hasLength(2));
      expect(note().items.whereType<TextItem>(), isEmpty);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('Open at this spot brings the note a match is on to the top of its stack', (tester) async {
      final r = FakeRecognizer();
      final page = BoardPage(id: 'pg_board', items: [_sticky(r, 'top note', under: 'buried treasure')]);
      final c = await pumpCanvas(tester, store: _store(page), recognizer: r);
      await tester.tap(byLabel('Search'));
      await tester.pumpAndSettle();
      await _settle(tester);
      await tester.enterText(find.byType(TextField), 'treasure');
      await tester.pump(const Duration(milliseconds: 250));
      await _settle(tester);
      expect(find.text('Handwriting on a note in a stack'), findsOneWidget);
      await tester.tap(find.text('Open at this spot'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      final pane = tester.widget<CanvasScreen>(find.byType(CanvasScreen)).pane;
      final stack = c.read(notebookProvider(pane.notebookId)).pageAt(pane.page).items.whereType<StickyItem>().single;
      ids(List<Item> items) => [for (final i in items) i.id];
      expect(ids(stack.items), ids(page.items.whereType<StickyItem>().single.under.single.items));
      expect(stack.count, 2);
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
