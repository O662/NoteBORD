import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../board/model.dart';
import '../../canvas/cards.dart' show newCard, starterTable;
import '../../canvas/charts.dart';
import '../../canvas/page_runtime.dart';
import '../../canvas/pane.dart';
import '../../canvas/selection.dart';
import '../../office/office_model.dart';
import '../../state/notebook.dart';
import '../../state/settings.dart';
import 'card_editors.dart';

// Charts linked to tables and Excel (Charts.png): making one (Insert →
// Chart, or Make a chart for a selected table or Excel card), and what the
// Chart selected bar and a chart's Data button do. Shared by the canvas and
// the Canvas screen.

/// The tables and Excel cards on [page] a chart can follow.
List<BoxItem> chartSources(PageRuntime page) => [
      for (final i in page.items)
        if ((i is CardItem && i.data is TableData) || (i is OfficeItem && i.mime == 'xlsx')) i as BoxItem,
    ];

/// An Excel card's workbook, read if it isn't yet; null if it can't be.
Future<Workbook?> readWorkbook(WidgetRef ref, String notebookId, OfficeItem file) async {
  final preview = await ref.read(notebookProvider(notebookId).notifier).loadOffice(file.asset, OfficeKind.xlsx);
  return switch (preview?.doc) {
    final Workbook book => book,
    _ => null,
  };
}

/// The page [pane] shows, if it can be written to.
PageRuntime? _writablePage(WidgetRef ref, Pane pane) {
  final nb = ref.read(notebookProvider(pane.notebookId));
  final page = nb.pageAt(pane.page);
  return nb.isSealed(page.id) ? null : page;
}

void _select(WidgetRef ref, Pane pane, String id) {
  ref.read(settingsProvider.notifier).apply((s) => s.copyWith(tool: CanvasTool.select));
  pane.selection
    ..menu = SelectionMenu.convert
    ..select([id]);
}

/// Makes a chart that follows [from], or a table or Excel card on the page
/// (asking which when there are several). With none, it adds a table and a
/// chart that follows it. The chart goes to the right of what it follows,
/// selected. One undo step.
Future<void> makeChart(BuildContext context, WidgetRef ref, Pane pane, {BoxItem? from}) async {
  final notebookId = pane.notebookId;
  final page = _writablePage(ref, pane);
  if (page == null) return;
  final notifier = ref.read(notebookProvider(notebookId).notifier);
  final now = DateTime.now().toUtc();
  var source = from;
  if (source == null) {
    final options = chartSources(page);
    if (options.isEmpty) {
      // Something to follow first: a table, with the chart beside it.
      final view = pane.view.visiblePage;
      final table = newCard(starterTable(), view.center - const Offset(380, 0), z: page.nextZ, now: now);
      final s = ChartSource(kind: 'table', ref: table.id, name: sourceName(table));
      final chart = newChart(s, sourceCells(s, table) ?? const [], at: Offset(table.extent.right + 70, table.y), z: page.nextZ + 1, now: now);
      notifier.insertItems(page.id, [table, chart]);
      _select(ref, pane, table.id);
      pane.toast('Added a table and a chart that follows it · Edit the table to fill it in', undoPageId: page.id);
      return;
    }
    source = options.length == 1 ? options.single : await showChartSourcePicker(context, options);
  }
  if (source == null || !context.mounted || pane.notebookId != notebookId) return;
  String? sheet;
  Workbook? book;
  if (source is OfficeItem) {
    book = await readWorkbook(ref, notebookId, source);
    // The sheet the card shows.
    sheet = book?.sheets.elementAtOrNull(source.page - 1)?.name ?? book?.sheets.firstOrNull?.name;
  }
  final s = ChartSource(kind: source is OfficeItem ? 'xlsx' : 'table', ref: source.id, sheet: sheet, name: sourceName(source));
  final chart = newChart(
    s,
    sourceCells(s, source, book: book) ?? const [],
    at: Offset(source.extent.right + 70, source.extent.top),
    z: page.nextZ,
    now: now,
  );
  notifier.insertItems(page.id, [chart]);
  _select(ref, pane, chart.id);
  final name = s.name.isEmpty ? 'the table' : '“${s.name}”';
  pane.toast('Added a chart of $name · it follows ${source is OfficeItem ? 'the sheet' : 'the table'}', undoPageId: page.id);
}

/// Change data (and the chart's Data button): where its numbers come from,
/// which cells, its name and what follows the numbers. One undo step.
Future<void> editChartData(BuildContext context, WidgetRef ref, Pane pane, ChartItem chart) async {
  final notebookId = pane.notebookId;
  final page = _writablePage(ref, pane);
  if (page == null) return;
  final edited = await showChartDataEditor(
    context,
    chart: chart,
    sources: chartSources(page),
    readBook: (file) => readWorkbook(ref, notebookId, file),
  );
  if (edited == null || pane.notebookId != notebookId) return;
  ref.read(notebookProvider(notebookId).notifier).replaceItems(page.id, [edited]);
  pane.toast('Changed the chart’s data', undoPageId: page.id);
}

/// Colors: a color for each series. One undo step.
Future<void> editChartColors(BuildContext context, WidgetRef ref, Pane pane, ChartItem chart) async {
  final notebookId = pane.notebookId;
  final page = _writablePage(ref, pane);
  if (page == null) return;
  final colors = await showChartColors(context, chart);
  if (colors == null || pane.notebookId != notebookId) return;
  ref.read(notebookProvider(notebookId).notifier).replaceItems(page.id, [chart.copyWith(colors: colors)]);
  pane.toast('Changed the chart’s colors', undoPageId: page.id);
}

/// Unlink (snapshot): the chart keeps the numbers it has and stops
/// following its source. One undo step.
void unlinkChart(WidgetRef ref, Pane pane, ChartItem chart) {
  final page = _writablePage(ref, pane);
  if (page == null) return;
  ref.read(notebookProvider(pane.notebookId).notifier).replaceItems(page.id, [chart.copyWith(linked: false)]);
  pane.toast('Unlinked · the chart keeps these numbers', undoPageId: page.id);
}

/// Whether [chart] can follow its source again: it's unlinked and the
/// table or Excel card is still on [page].
bool canLinkAgain(PageRuntime page, ChartItem chart) {
  final s = chart.source;
  return !chart.linked && s != null && page[s.ref] is BoxItem;
}

/// Link again: an unlinked chart follows its source again, with its
/// numbers read now. One undo step.
Future<void> linkChartAgain(WidgetRef ref, Pane pane, ChartItem chart) async {
  final notebookId = pane.notebookId;
  final page = _writablePage(ref, pane);
  final s = chart.source;
  final item = s == null ? null : page?[s.ref];
  if (page == null || s == null || item is! BoxItem) return;
  final book = item is OfficeItem ? await readWorkbook(ref, notebookId, item) : null;
  if (pane.notebookId != notebookId) return;
  final cells = sourceCells(s, item, book: book);
  final linked = chart.copyWith(linked: true, cells: cells ?? chart.cells, source: () => s.copyWith(name: sourceName(item)));
  ref.read(notebookProvider(notebookId).notifier).replaceItems(page.id, [linked]);
  pane.toast('Linked to “${sourceName(item)}” again', undoPageId: page.id);
}
