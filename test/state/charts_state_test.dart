// Charts following their tables and Excel cards (Phase 7b): in the same
// undo step as the change, and as a snapshot once their source is gone.

import 'package:endless/board/model.dart';
import 'package:endless/canvas/charts.dart';
import 'package:endless/state/notebook.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../live_samples.dart';
import '../office_samples.dart';

/// Charts.png's notebook, open.
Future<(ProviderContainer, NotebookNotifier)> _open() async {
  final store = chartsStore();
  final c = ProviderContainer(overrides: await testOverrides(store));
  addTearDown(c.dispose);
  c.listen(loadedNotebookProvider('nb_lab'), (_, _) {});
  await c.read(loadedNotebookProvider('nb_lab').future);
  c.listen(notebookProvider('nb_lab'), (_, _) {});
  return (c, c.read(notebookProvider('nb_lab').notifier));
}

const _page = 'pg_charts';

/// Lets the autosave finish.
Future<void> _saved(WidgetTester tester) => tester.pump(const Duration(seconds: 2));

void main() {
  late ProviderContainer c;
  late NotebookNotifier n;
  Item item(String id) => c.read(notebookProvider('nb_lab')).pages.first[id]!;
  ChartItem week() => item('it_week') as ChartItem;
  ChartItem momentum() => item('it_momentum') as ChartItem;
  CardItem hours() => item('it_hours') as CardItem;

  CardItem withHours(List<String> row) => hours().copyWith(data: TableData([(hours().data as TableData).cells.first, row]));

  testWidgets('editing the table changes the chart, and one Undo puts both back', (tester) async {
    (c, n) = await _open();
    final before = week();
    n.replaceItems(_page, [withHours(['2', '1.5', '3', '2.5', '4'])]);
    expect(week().cells[1].last, '4');
    expect(chartTotal(week()), '13 h');
    expect(momentum().cells, isNotEmpty, reason: 'the other chart is left alone');
    n.undo(_page);
    expect(week().cells, before.cells);
    expect((hours().data as TableData).cells[1].last, '1');
    n.redo(_page);
    expect(week().cells[1].last, '4');
    // Renamed: the link says so.
    n.replaceItems(_page, [hours().copyWith(title: 'Hours')]);
    expect(week().source!.name, 'Hours');
    await _saved(tester);
  });

  testWidgets('moved to the front, the table is still followed', (tester) async {
    (c, n) = await _open();
    n.reorder(_page, ['it_hours'], toFront: true);
    expect(week().live, isTrue);
    n.reorder(_page, ['it_week'], toFront: false);
    n.replaceItems(_page, [withHours(['1', '1', '1', '1', '1'])]);
    expect(chartTotal(week()), '5 h');
    await _saved(tester);
  });

  testWidgets('an unlinked chart keeps its numbers', (tester) async {
    (c, n) = await _open();
    n.replaceItems(_page, [week().copyWith(linked: false)]);
    n.replaceItems(_page, [withHours(['9', '9', '9', '9', '9'])]);
    expect(week().cells[1].first, '2');
    expect(chartLinkLabel(week()), 'Snapshot of Study hours table');
    await _saved(tester);
  });

  testWidgets('deleting the table leaves a snapshot; Undo links it again', (tester) async {
    (c, n) = await _open();
    n.removeItems(_page, ['it_hours']);
    expect(week().linked, isFalse);
    expect(week().cells, isNotEmpty);
    n.undo(_page);
    expect(week().linked, isTrue);
    expect(hours().id, 'it_hours');
    // Deleted with its chart: nothing left to unlink.
    n.removeItems(_page, ['it_hours', 'it_week']);
    n.undo(_page);
    expect(week().linked, isTrue);
    await _saved(tester);
  });

  testWidgets('a newer Excel file (Charts.png\'s Add trial 7) changes the chart in the same undo step', (tester) async {
    (c, n) = await _open();
    expect(await n.updateOffice(_page, 'it_labdata', momentumXlsx(seventh: true)), isNotNull);
    expect(momentum().cells.length, 8);
    expect(chartLinkLabel(momentum()), 'Lab data.xlsx › Sheet1 › A1:C8 · live');
    expect(chartDataOf(momentum()).categories.last, 'Trial 7');
    n.undo(_page);
    expect(momentum().cells.length, 7);
    await _saved(tester);
  });
}
