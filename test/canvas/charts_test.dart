// Charts linked to tables and Excel (Phase 7b, Charts.png): ranges, how a
// range's cells become series, the axes, labels, buttons and following the
// source.

import 'package:endless/board/model.dart';
import 'package:endless/canvas/charts.dart';
import 'package:endless/office/office_model.dart';
import 'package:endless/office/office_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../live_samples.dart';
import '../office_samples.dart';

final _at = DateTime.utc(2026, 9, 28);

ChartItem _chart(List<List<String>> cells, {ChartSource? source, double h = 404, ChartType type = ChartType.bar, bool linked = true, double unit = 1}) =>
    ChartItem(
      id: 'it_chart',
      x: 0,
      y: 0,
      z: 1,
      createdAt: _at,
      w: 700 * unit,
      h: h * unit,
      unit: unit,
      chartType: type,
      source: source ?? const ChartSource(kind: 'table', ref: 'it_table', name: 'Study hours'),
      linked: linked,
      cells: cells,
    );

CardItem _table(List<List<String>> cells, {String title = 'Study hours'}) =>
    CardItem(id: 'it_table', x: 0, y: 0, z: 1, createdAt: _at, w: 430, h: 156, data: TableData(cells), title: title, unit: 1);

const _lab = [
  ['Trial', 'p before', 'p after'],
  ['1', '1.00', '0.97'],
  ['2', '0.80', '0.78'],
  ['3', '1.20', '1.15'],
];

const _hours = [
  ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
  ['2', '1.5', '3', '2.5', '1'],
];

void main() {
  group('ranges', () {
    test('column names and ranges', () {
      expect([columnName(0), columnName(2), columnName(25), columnName(26), columnName(27)], ['A', 'C', 'Z', 'AA', 'AB']);
      expect(parseRange('A1:C7'), (top: 0, left: 0, bottom: 6, right: 2));
      expect(parseRange(r'$c$7:a1'), (top: 0, left: 0, bottom: 6, right: 2));
      expect(parseRange('B2'), (top: 1, left: 1, bottom: 1, right: 1));
      expect(parseRange(''), isNull);
      expect(parseRange('A1:C7:D2'), isNull);
      expect(parseRange('hello'), isNull);
      expect(rangeLabel(parseRange('c7:a1')!), 'A1:C7');
    });

    test('the cells in a range, without empty rows and columns at the end', () {
      final grid = [
        ['Trial', 'p before', 'p after', ''],
        ['1', '1.00', '0.97', ''],
        ['', '', '', ''],
      ];
      expect(cellsIn(grid, ''), [
        ['Trial', 'p before', 'p after'],
        ['1', '1.00', '0.97'],
      ]);
      expect(cellsIn(grid, 'B1:C2'), [
        ['p before', 'p after'],
        ['1.00', '0.97'],
      ]);
      // Past the end of what was read: what there is.
      expect(cellsIn(grid, 'A1:Z99'), cellsIn(grid, ''));
      expect(cellsIn(const [], ''), isEmpty);
    });

    test('a sheet or table as the source', () {
      final book = readOffice(momentumXlsx(), OfficeKind.xlsx) as Workbook;
      final file = OfficeItem(id: 'it_xlsx', x: 0, y: 0, z: 1, createdAt: _at, w: 430, h: 300, asset: 'a.xlsx', mime: 'xlsx', name: 'Lab data.xlsx');
      const excel = ChartSource(kind: 'xlsx', ref: 'it_xlsx', sheet: 'Sheet1');
      expect(sourceCells(excel, file, book: book)!.first, ['Trial', 'p before', 'p after']);
      expect(sourceCells(excel, file, book: book)!.length, 7);
      expect(sourceCells(excel.copyWith(range: 'B1:B3'), file, book: book), [
        ['p before'],
        ['1.00'],
        ['0.80'],
      ]);
      // Not read yet, a sheet that isn't there, the wrong kind of item.
      expect(sourceCells(excel, file), isNull);
      expect(sourceCells(excel.copyWith(sheet: 'Gone'), file, book: book), isNull);
      expect(sourceCells(excel, _table(_hours), book: book), isNull);
      expect(sourceCells(const ChartSource(kind: 'table', ref: 'it_table'), _table(_hours)), _hours);
      expect(sourceName(file), 'Lab data.xlsx');
      expect(sourceName(_table(_hours)), 'Study hours');
    });
  });

  test('numbers in cells', () {
    expect(chartNumber('1.00'), 1);
    expect(chartNumber(' 2 '), 2);
    expect(chartNumber('1,234.5'), 1234.5);
    expect(chartNumber('-0.5'), -0.5);
    expect(chartNumber('−3'), -3);
    expect(chartNumber('45%'), 45);
    expect(chartNumber(r'$3.20'), 3.2);
    expect(chartNumber('2 h'), 2);
    expect(chartNumber('.5'), 0.5);
    expect(chartNumber('1.2E+03'), 1200);
    expect(chartNumber('Trial 1'), isNull);
    expect(chartNumber('9/30/2026'), isNull);
    expect(chartNumber('2026-09-30'), isNull);
    expect(chartNumber(''), isNull);
  });

  group('series', () {
    test('Charts.png\'s sheet: a column per series, the trials along the bottom', () {
      final d = readChart(_lab);
      expect(d.categories, ['Trial 1', 'Trial 2', 'Trial 3']);
      expect([for (final s in d.series) s.name], ['p before', 'p after']);
      expect(d.series.first.values, [1.0, 0.8, 1.2]);
      expect([for (final s in d.series) s.column], [1, 2]);
      expect(d.extent, (0.78, 1.2));
    });

    test('Charts.png\'s week: the days across, one series named after the table', () {
      final d = readChart(_hours, name: 'Study hours');
      expect(d.categories, ['Mon', 'Tue', 'Wed', 'Thu', 'Fri']);
      expect(d.series.single.name, 'Study hours');
      expect(d.series.single.values, [2, 1.5, 3, 2.5, 1]);
    });

    test('a row of names across, a name down the side', () {
      final d = readChart(const [
        ['', 'Q1', 'Q2', 'Q3', 'Q4'],
        ['Sales', '1', '2', '3', '4'],
        ['Costs', '2', '2', '2', '2'],
      ]);
      expect(d.categories, ['Q1', 'Q2', 'Q3', 'Q4']);
      expect([for (final s in d.series) s.name], ['Sales', 'Costs']);
    });

    test('words down the side, a column of numbers', () {
      final d = readChart(const [
        ['Fruit', 'Count'],
        ['Apples', '3'],
        ['Pears', '5'],
        ['Plums', '1'],
      ]);
      expect(d.categories, ['Apples', 'Pears', 'Plums']);
      expect(d.series.single.name, 'Count');
    });

    test('only numbers: numbered, columns named by letter', () {
      final d = readChart(const [
        ['1', '2'],
        ['3', '4'],
        ['5', '6'],
      ]);
      expect(d.categories, ['1', '2', '3']);
      expect([for (final s in d.series) s.name], ['Column A', 'Column B']);
    });

    test('gaps and columns with no numbers', () {
      final d = readChart(const [
        ['Trial', 'p', 'note'],
        ['1', '1.0', 'ok'],
        ['2', '', 'redo'],
      ]);
      expect(d.series.single.name, 'p');
      expect(d.series.single.values, [1.0, null]);
      expect(readChart(const []).isEmpty, isTrue);
      expect(readChart(const [
        ['a', 'b'],
        ['c', 'd'],
      ]).isEmpty, isTrue);
    });
  });

  test('axes: from zero with headroom (Charts.dc.html), or around the numbers', () {
    final bars = chartAxis(0.78, 1.2, 250, fromZero: true);
    expect([bars.lo, bars.decimals], [0, 1]);
    expect(bars.hi, closeTo(1.4, 1e-9));
    expect(bars.step, closeTo(0.2, 1e-9));
    expect(chartAxis(1, 3, 140, fromZero: true), (lo: 0.0, hi: 4.0, step: 1.0, decimals: 0));
    final scatter = chartAxis(0.78, 1.15, 250, fromZero: false);
    expect(scatter.step, closeTo(0.1, 1e-9));
    expect(scatter.lo, closeTo(0.7, 1e-9));
    expect(scatter.hi, closeTo(1.2, 1e-9));
    final negative = chartAxis(-3, 5, 250, fromZero: true);
    expect(negative.lo, lessThan(-3));
    expect(negative.hi, greaterThan(5));
    // All the same: still an axis.
    expect(chartAxis(2, 2, 250, fromZero: false).hi, greaterThan(2));
    expect(chartAxis(0, 0, 250, fromZero: true).hi, greaterThan(0));
  });

  test('names, links and totals', () {
    final week = _chart(_hours, h: 232).copyWith(title: 'Study hours this week', suffix: 'h');
    expect(chartTitle(week), 'Study hours this week');
    expect(chartLinkLabel(week), 'Study hours table · live');
    expect(chartTotal(week), '10 h');
    expect(chartLinkLabel(week.copyWith(linked: false)), 'Snapshot of Study hours table');
    expect(chartLinkLabel(week.copyWith(source: () => week.source!.copyWith(range: 'a1:e2'))), 'Study hours › A1:E2 · live');

    final lab = _chart(_lab, source: const ChartSource(kind: 'xlsx', ref: 'it_xlsx', sheet: 'Sheet1', name: 'Lab data.xlsx'));
    expect(chartLinkLabel(lab), 'Lab data.xlsx › Sheet1 › A1:C4 · live');
    expect(chartTitle(lab), 'p before vs. p after');
    expect(chartTotal(lab), isNull);
    expect(chartTitle(_chart(const []).copyWith(source: () => null)), 'Chart');
    expect(chartLinkLabel(_chart(const []).copyWith(source: () => null)), 'Snapshot');
    expect(chartNumberText(1.5), '1.5');
    expect(chartNumberText(-0.0, decimals: 1), '0.0');
    expect(chartNumberText(-2), '−2');
    expect(chartText(lab), contains('p after'));
    expect(chartText(lab), contains('Trial 3'));
  });

  test('buttons: the chart type and Data on a tall chart, at any scale', () {
    for (final unit in [1.0, 2.0]) {
      final c = _chart(_lab, unit: unit);
      // Charts.dc.html: the switch and Data at the right of the 56 px header.
      expect(chartHitAt(c, Offset(c.w - 40 * unit, 28 * unit)), const ChartDataHit());
      final hits = {
        for (var x = c.w - 400 * unit; x < c.w - 90 * unit; x += 4) ?chartHitAt(c, Offset(x, 28 * unit)),
      };
      expect(hits, {for (final t in ChartType.values) ChartTypeHit(t)});
      expect(chartHitAt(c, Offset(c.w / 2, c.h / 2)), isNull);
    }
    // A short chart has no buttons (Charts.png's second chart).
    final short = _chart(_hours, h: 232);
    expect([for (var x = 0.0; x < short.w; x += 5) ?chartHitAt(short, Offset(x, 24))], isEmpty);
  });

  group('following the source', () {
    test('new numbers from the table', () {
      final chart = _chart(_hours);
      final edited = _table([
        ..._hours.take(1),
        ['2', '1.5', '3.5', '2.5', '1'],
      ]);
      final next = refreshedChart(chart, edited)!;
      expect(next.cells[1][2], '3.5');
      expect(next.id, chart.id);
      // Nothing changed; unlinked; another item.
      expect(refreshedChart(chart, _table(_hours)), isNull);
      expect(refreshedChart(chart.copyWith(linked: false), edited), isNull);
      expect(refreshedChart(chart.copyWith(source: () => chart.source!.copyWith(name: 'x')), _table(_hours))!.source!.name, 'Study hours');
    });

    test('a renamed table renames the link', () {
      final next = refreshedChart(_chart(_hours), _table(_hours, title: 'Hours'))!;
      expect(next.source!.name, 'Hours');
    });

    test('Charts.png\'s sheet with a seventh trial: the whole sheet grows to A1:C8', () {
      final (nb, file, _) = chartsSample();
      final chart = nb.pages.single.items.whereType<ChartItem>().first;
      expect(chartLinkLabel(chart), 'Lab data.xlsx › Sheet1 › A1:C7 · live');
      final book = readOffice(momentumXlsx(seventh: true), OfficeKind.xlsx) as Workbook;
      final next = refreshedChart(chart, file, book: book)!;
      expect(next.cells.length, 8);
      expect(chartLinkLabel(next), 'Lab data.xlsx › Sheet1 › A1:C8 · live');
      expect(chartDataOf(next).categories.last, 'Trial 7');
      expect(refreshedChart(chart, file), isNull, reason: 'the file is not read yet');
    });
  });

  test('the link leaves the side facing the chart', () {
    final table = _table(_hours);
    ChartItem at(Offset p) => _chart(_hours).withBox(x: p.dx, y: p.dy, w: 700, h: 404);
    expect(chartLinkEnds(table, at(const Offset(540, 0))), (const Offset(430, 78), const Offset(540, 202), const Offset(1, 0)));
    expect(chartLinkEnds(table, at(const Offset(-800, 0))).$3, const Offset(-1, 0));
    expect(chartLinkEnds(table, at(const Offset(0, 300))).$3, const Offset(0, 1));
    expect(chartLinkEnds(table, at(const Offset(0, -500))).$3, const Offset(0, -1));
  });
}
