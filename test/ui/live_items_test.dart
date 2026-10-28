// Phase 7b end to end, with S Pen and finger events: charts linked to
// tables and Excel (Charts.png) and live items (LiveItems.png).

import 'dart:ui' as ui;

import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/canvas/charts.dart';
import 'package:endless/canvas/live_items.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/theme/colors.dart';
import 'package:endless/ui/canvas/canvas_screen.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../live_samples.dart';

// Gestures, each a couple of seconds after the last, so a finger isn't
// taken for the palm just after the pen.
var _clock = const Duration(seconds: 10);
Duration _tick() => _clock += const Duration(seconds: 2);

Future<void> _tap(WidgetTester tester, Offset at, {bool pen = false}) async {
  final g = await tester.createGesture(kind: pen ? PointerDeviceKind.stylus : PointerDeviceKind.touch);
  final t = _tick();
  await g.down(at, timeStamp: t);
  await g.up(timeStamp: t + const Duration(milliseconds: 60));
  await tester.pump();
}

Future<void> _draw(WidgetTester tester, List<Offset> points, {bool pen = true}) async {
  final g = await tester.createGesture(kind: pen ? PointerDeviceKind.stylus : PointerDeviceKind.touch);
  var t = _tick();
  await g.down(points.first, timeStamp: t);
  for (final p in points.skip(1)) {
    t += const Duration(milliseconds: 8);
    await g.moveTo(p, timeStamp: t);
  }
  await g.up(timeStamp: t);
  await tester.pump();
}

List<Offset> _line(Offset a, Offset b, {int n = 12}) => [for (var i = 0; i <= n; i++) Offset.lerp(a, b, i / n)!];

/// Where [local] on [item] is on screen.
Offset _on(BoxItem item, Offset local) => canvasPane.view.toScreen(item.toPage(local));

Future<void> _insert(WidgetTester tester, String tile) async {
  await tester.tap(byLabel('Insert'));
  await tester.pump();
  await tester.tap(find.text('Everything else'));
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsLabel(tile));
  await tester.pumpAndSettle();
}

Future<void> _press(WidgetTester tester, String label) async {
  await tester.tap(find.bySemanticsLabel(label).last);
  await tester.pumpAndSettle();
}

/// Lets the autosave and the last message finish.
Future<void> _done(WidgetTester tester) => tester.pump(const Duration(seconds: 5));

void _useTool(ProviderContainer c, CanvasTool tool) => c.read(settingsProvider.notifier).apply((s) => s.copyWith(tool: tool));

/// Charts.png's notebook with only [keep] of its items.
MemoryBoardStore _charts(Set<String> keep) {
  final (nb, file, bytes) = chartsSample();
  final page = BoardPage(id: 'pg_charts', items: [for (final i in nb.pages.single.items) if (keep.contains(i.id)) i]);
  // Charts.png has no pages rail or map in the way.
  final store = storeWith(LoadedNotebook(nb.notebook, [page]), settings: AppSettings(pagesOpen: false, mapOpen: false, trayOpen: false));
  store.saveAsset(nb.notebook.id, file.asset, bytes);
  return store;
}

List<ChartItem> _chartsOn(ProviderContainer c) => shownPage(c).items.whereType<ChartItem>().toList();
T _item<T extends Item>(ProviderContainer c, String id) => shownPage(c)[id]! as T;
bool _canUndo(ProviderContainer c) => c.read(notebookProvider(canvasPane.notebookId).notifier).canUndo(shownPage(c).id);
void _undo(ProviderContainer c) => c.read(notebookProvider(canvasPane.notebookId).notifier).undo(shownPage(c).id);

/// A point on [chart]'s header that presses [hit].
Offset _button(ChartItem chart, ChartHit hit) {
  for (var x = 0.0; x < chart.w; x += 2) {
    if (chartHitAt(chart, Offset(x, 28 * chart.unit)) == hit) return _on(chart, Offset(x + 6, 28 * chart.unit));
  }
  throw StateError('no $hit');
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() {
    _clock = const Duration(seconds: 10);
    liveNow = () => liveSampleNow;
  });
  tearDown(() => liveNow = DateTime.now);

  group('making a chart', () {
    testWidgets('Insert → Chart with a table on the page: linked, beside it, selected; one undo step', (tester) async {
      final c = await pumpCanvas(tester, store: _charts({'it_hours'}));
      await _insert(tester, 'Chart');
      final chart = _chartsOn(c).single;
      final table = _item<CardItem>(c, 'it_hours');
      expect(chart.source, const ChartSource(kind: 'table', ref: 'it_hours', name: 'Study hours'));
      expect(chart.live, isTrue);
      expect(chart.cells, (table.data as TableData).cells);
      expect(chart.x, table.extent.right + 70);
      expect(canvasPane.selection.ids, {chart.id});
      expect(find.text('Chart selected'), findsOneWidget);
      expect(find.textContaining('Added a chart of “Study hours”'), findsOneWidget);
      _undo(c);
      await tester.pump();
      expect(_chartsOn(c), isEmpty);
      await _done(tester);
    });

    testWidgets('with a table and an Excel sheet, it asks which; the sheet the card shows', (tester) async {
      final c = await pumpCanvas(tester, store: _charts({'it_labdata', 'it_hours'}));
      await _insert(tester, 'Chart');
      expect(find.text('Make a chart from'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chart-from-it_labdata')));
      await tester.pumpAndSettle();
      final chart = _chartsOn(c).single;
      expect(chart.source!.isExcel, isTrue);
      expect(chart.source!.sheet, 'Sheet1');
      expect(chart.cells.length, 7);
      expect(chartLinkLabel(chart), 'Lab data.xlsx › Sheet1 › A1:C7 · live');
      await _done(tester);
    });

    testWidgets('on an empty page, a table and a chart that follows it', (tester) async {
      final c = await pumpCanvas(tester);
      await _insert(tester, 'Chart');
      final table = shownPage(c).items.whereType<CardItem>().single;
      expect(table.data, isA<TableData>());
      expect(_chartsOn(c).single.source!.ref, table.id);
      expect(canvasPane.selection.ids, {table.id});
      _undo(c);
      await tester.pump();
      expect(shownPage(c).items, isEmpty);
      await _done(tester);
    });

    testWidgets('Make a chart for a selected table', (tester) async {
      final c = await pumpCanvas(tester, store: _charts({'it_hours'}));
      _useTool(c, CanvasTool.select);
      canvasPane.selection.select(['it_hours']);
      await tester.pump();
      await _press(tester, 'Make a chart');
      expect(_chartsOn(c).single.source!.ref, 'it_hours');
      await _done(tester);
    });
  });

  group('following and the Chart selected bar', () {
    testWidgets('editing the table changes the chart; one Undo puts both back', (tester) async {
      final c = await pumpCanvas(tester, store: _charts({'it_hours', 'it_week'}));
      _useTool(c, CanvasTool.select);
      canvasPane.selection.select(['it_hours']);
      await tester.pump();
      await _press(tester, 'Edit');
      await tester.enterText(find.byKey(const ValueKey('table-cell-1-4')), '4');
      await _press(tester, 'Save');
      expect(_item<ChartItem>(c, 'it_week').cells[1].last, '4');
      expect(chartTotal(_item<ChartItem>(c, 'it_week')), '13 h');
      _undo(c);
      await tester.pump();
      expect(_item<ChartItem>(c, 'it_week').cells[1].last, '1');
      await _done(tester);
    });

    testWidgets('Unlink (snapshot), Link again, Done', (tester) async {
      final c = await pumpCanvas(tester, store: _charts({'it_hours', 'it_week'}));
      _useTool(c, CanvasTool.select);
      canvasPane.selection.select(['it_week']);
      await tester.pump();
      expect(find.text('Change data'), findsOneWidget);
      await _press(tester, 'Unlink (snapshot)');
      expect(_item<ChartItem>(c, 'it_week').linked, isFalse);
      expect(find.text('Unlinked · the chart keeps these numbers'), findsOneWidget);
      // The table changes; the snapshot doesn't.
      final table = _item<CardItem>(c, 'it_hours');
      c.read(notebookProvider(canvasPane.notebookId).notifier).replaceItems(shownPage(c).id, [
        table.copyWith(data: TableData([(table.data as TableData).cells.first, ['1', '1', '1', '1', '1']])),
      ]);
      await tester.pump();
      expect(chartTotal(_item<ChartItem>(c, 'it_week')), '10 h');
      await _press(tester, 'Link again');
      expect(_item<ChartItem>(c, 'it_week').linked, isTrue);
      expect(chartTotal(_item<ChartItem>(c, 'it_week')), '5 h');
      await _press(tester, 'Done');
      expect(canvasPane.selection.isEmpty, isTrue);
      expect(c.read(settingsProvider).tool, CanvasTool.pen);
      expect(find.text('Chart selected'), findsNothing);
      await _done(tester);
    });

    testWidgets('the chart type on the card, by finger and pen: not an undo step', (tester) async {
      final c = await pumpCanvas(tester, store: _charts({'it_labdata', 'it_momentum'}));
      await _tap(tester, _button(_item(c, 'it_momentum'), const ChartTypeHit(ChartType.line)));
      expect(_item<ChartItem>(c, 'it_momentum').chartType, ChartType.line);
      // Selected with Select, a finger still presses it rather than moving
      // the chart (the tablet, 2026-10-28).
      _useTool(c, CanvasTool.select);
      canvasPane.selection.select(['it_momentum']);
      await tester.pump();
      final before = _item<ChartItem>(c, 'it_momentum');
      await _tap(tester, _button(before, const ChartTypeHit(ChartType.area)));
      expect(_item<ChartItem>(c, 'it_momentum').chartType, ChartType.area);
      expect(_item<ChartItem>(c, 'it_momentum').x, before.x);
      _useTool(c, CanvasTool.pen);
      await tester.pump();
      await _tap(tester, _button(_item(c, 'it_momentum'), const ChartTypeHit(ChartType.scatter)), pen: true);
      expect(_item<ChartItem>(c, 'it_momentum').chartType, ChartType.scatter);
      expect(shownPage(c).items.whereType<StrokeItem>(), isEmpty, reason: 'the pen pressed, it did not write');
      expect(_canUndo(c), isFalse);
      await _done(tester);
    });

    testWidgets('Data: another range, a name and what follows the numbers', (tester) async {
      final c = await pumpCanvas(tester, store: _charts({'it_labdata', 'it_momentum'}));
      await _tap(tester, _button(_item(c, 'it_momentum'), const ChartDataHit()));
      await tester.pumpAndSettle();
      expect(find.text('Chart data'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('chart-range')), 'A1:Z');
      await tester.pump();
      expect(find.text('That isn’t a range of cells, like A1:C7'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('chart-range')), 'a1:b7');
      await tester.enterText(find.byKey(const ValueKey('chart-suffix')), 'kg·m/s');
      await tester.pump();
      expect(find.text('6 groups · p before'), findsOneWidget);
      await _press(tester, 'Save');
      final chart = _item<ChartItem>(c, 'it_momentum');
      expect(chart.source!.range, 'A1:B7');
      expect(chart.suffix, 'kg·m/s');
      expect(chartDataOf(chart).series.single.name, 'p before');
      expect(chartLinkLabel(chart), 'Lab data.xlsx › Sheet1 › A1:B7 · live');
      await _done(tester);
    });

    testWidgets('Colors', (tester) async {
      final c = await pumpCanvas(tester, store: _charts({'it_hours', 'it_week'}));
      _useTool(c, CanvasTool.select);
      canvasPane.selection.select(['it_week']);
      await tester.pump();
      await _press(tester, 'Colors');
      final plum = colorToHex(const Color(0xFF7A4E73));
      await tester.tap(find.byKey(ValueKey('chart-color-0-$plum')));
      await tester.pump();
      await _press(tester, 'Save');
      expect(_item<ChartItem>(c, 'it_week').colors.single.toARGB32(), 0xFF7A4E73);
      await _done(tester);
    });
  });

  group('live items', () {
    testWidgets('Insert → Clock & date: the bar; a clock, the date, stamps and a checklist where there is room', (tester) async {
      final c = await pumpCanvas(tester);
      await _insert(tester, 'Clock & date');
      expect(find.text('Live items'), findsOneWidget);
      expect(find.textContaining('stamps keep the moment they were made'), findsOneWidget);
      for (final label in ['Clock', 'Today’s date', 'Checklist']) {
        await _press(tester, label);
      }
      final added = shownPage(c).items.whereType<BoxItem>().toList();
      expect(added.length, 3);
      // Clear of each other.
      for (var i = 0; i < added.length; i++) {
        for (var j = i + 1; j < added.length; j++) {
          expect(added[i].extent.overlaps(added[j].extent), isFalse);
        }
      }
      await _press(tester, 'Stamp time');
      expect(find.text('Stamped 9:23 PM · write beside it'), findsOneWidget);
      final first = shownPage(c).items.last as LiveItem;
      expect((first.data as StampData).at, liveSampleNow.toUtc());
      // Something written beside it; the next stamp goes under that.
      final beside = first.toPage(const Offset(130, 13));
      await _draw(tester, _line(canvasPane.view.toScreen(beside), canvasPane.view.toScreen(beside + const Offset(120, 30))));
      await _press(tester, 'Stamp time');
      final second = shownPage(c).items.last as LiveItem;
      expect(second.x, first.x);
      expect(second.y, greaterThan(first.y + 30 + 8));
      _undo(c);
      await tester.pump();
      expect(shownPage(c)[second.id], isNull);
      await _press(tester, 'Done');
      expect(find.text('Live items'), findsNothing);
      // Esc puts it away too.
      await _insert(tester, 'Clock & date');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('Live items'), findsNothing);
      await _done(tester);
    });

    testWidgets('the clock: Analog or Digital; stamps: clock time or how long ago; not undo steps', (tester) async {
      final c = await pumpCanvas(tester, store: storeWith(liveSample()));
      final clock = _item<LiveItem>(c, 'it_clock');
      final (_, digital) = clockButtons(const ClockData());
      await _tap(tester, _on(clock, digital.center));
      expect((_item<LiveItem>(c, 'it_clock').data as ClockData).analog, isFalse);
      expect(_item<LiveItem>(c, 'it_clock').h, 148);
      await _tap(tester, _on(_item(c, 'it_stamp1'), const Offset(20, 13)));
      for (final id in ['it_stamp0', 'it_stamp1', 'it_stamp2']) {
        expect((_item<LiveItem>(c, id).data as StampData).ago, isTrue, reason: id);
      }
      expect(find.text('Time stamps show how long ago'), findsOneWidget);
      expect(stampLabel(_item<LiveItem>(c, 'it_stamp0').data as StampData, liveNow()), '47 min ago');
      expect(_canUndo(c), isFalse);
      // With Select, a stamp is selected, not turned.
      _useTool(c, CanvasTool.select);
      await tester.pump();
      await _tap(tester, _on(_item(c, 'it_stamp1'), const Offset(20, 13)), pen: true);
      expect(canvasPane.selection.ids, {'it_stamp1'});
      expect((_item<LiveItem>(c, 'it_stamp1').data as StampData).ago, isTrue);
      await _done(tester);
    });

    testWidgets('a checklist: written in with the pen, ticked by finger, pen tap or a drawn tick, erased', (tester) async {
      final c = await pumpCanvas(tester);
      await _insert(tester, 'Checklist');
      await tester.pump();
      var list = shownPage(c).items.whereType<ChecklistItem>().single;
      expect(c.read(settingsProvider).tool, CanvasTool.pen);
      // Written on "write another item…": a new entry.
      final slot = list.toPage(list.slot.centerLeft + const Offset(20, 0));
      await _draw(tester, _line(canvasPane.view.toScreen(slot), canvasPane.view.toScreen(slot + const Offset(90, 4))));
      list = _item(c, list.id);
      expect(list.entries.single.ink, hasLength(1));
      expect(shownPage(c).items.whereType<StrokeItem>(), isEmpty, reason: 'the ink is on the checklist');
      await _draw(tester, _line(canvasPane.view.toScreen(list.toPage(list.slot.centerLeft + const Offset(20, 0))),
          canvasPane.view.toScreen(list.toPage(list.slot.centerLeft + const Offset(110, 0)))));
      list = _item(c, list.id);
      expect(list.entries.length, 2);

      // Ticked by a finger, Undo; by a pen tap; by a tick drawn on its box.
      await _tap(tester, _on(list, list.boxRect(0).center));
      expect(_item<ChecklistItem>(c, list.id).entries.first.done, isTrue);
      _undo(c);
      await tester.pump();
      expect(_item<ChecklistItem>(c, list.id).entries.first.done, isFalse);
      await _tap(tester, _on(list, list.boxRect(0).center), pen: true);
      expect(_item<ChecklistItem>(c, list.id).entries.first.done, isTrue);
      final box = list.boxRect(1);
      await _draw(tester, [
        _on(list, box.center + const Offset(-6, 0)),
        _on(list, box.center + const Offset(-2, 5)),
        _on(list, box.center + const Offset(8, -8)),
      ]);
      list = _item(c, list.id);
      expect(list.entries[1].done, isTrue);
      expect(list.doneCount, 2);
      expect(list.ink.length, 2, reason: 'the tick isn’t kept as ink');

      // The eraser rubs an entry's writing off, and the entry with it.
      _useTool(c, CanvasTool.eraser);
      await tester.pump();
      final ink = list.pageInk.first;
      await _draw(tester, [for (final p in ink.pagePoints) canvasPane.view.toScreen(p)]);
      expect(_item<ChecklistItem>(c, list.id).entries.length, 1);
      await _done(tester);
    });

    testWidgets('Edit: rename it, tick, add and remove typed items', (tester) async {
      final c = await pumpCanvas(tester, store: storeWith(liveSample()));
      _useTool(c, CanvasTool.select);
      canvasPane.selection.select(['it_list']);
      await tester.pump();
      await _press(tester, 'Edit');
      expect(find.text('Written by hand'), findsNWidgets(5));
      await tester.enterText(find.byKey(const ValueKey('card-name')), 'Lab day');
      await tester.tap(find.byKey(const ValueKey('checklist-done-2')));
      await tester.tap(find.byKey(const ValueKey('checklist-remove-4')));
      await tester.pump();
      await _press(tester, 'Add item');
      await tester.enterText(find.byKey(const ValueKey('checklist-text-4')), 'print data table');
      await _press(tester, 'Save');
      final list = _item<ChecklistItem>(c, 'it_list');
      expect(list.title, 'Lab day');
      expect(list.entries.length, 5);
      expect(list.doneCount, 3);
      expect(list.entries.last.text, 'print data table');
      expect(list.entries.last.ink, isEmpty);
      await _done(tester);
    });

    testWidgets('a clock is drawn again when the time it shows changes, and only then', (tester) async {
      final c = await pumpCanvas(tester, store: storeWith(liveSample()));
      var now = liveSampleNow;
      liveNow = () => now;
      final context = tester.element(find.byType(CanvasScreen));
      ui.Picture region() => shownPage(c).regionPicture(canvasPane.view.visiblePage, Theme.of(context).brightness, context.colors);
      await tester.pump(const Duration(seconds: 1));
      final first = region();
      await tester.pump(const Duration(seconds: 1));
      expect(identical(region(), first), isTrue, reason: 'the same second');
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(identical(region(), first), isFalse);
      await _done(tester);
    });
  });
}
