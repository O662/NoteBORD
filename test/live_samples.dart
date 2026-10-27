import 'dart:math' as math;
import 'dart:typed_data';

import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/canvas/charts.dart';
import 'package:endless/office/office_model.dart';
import 'package:endless/office/office_reader.dart';
import 'package:endless/state/assets.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:flutter/painting.dart';

import 'helpers.dart';
import 'office_samples.dart';

// Charts.png and LiveItems.png made of real items, where the designs have
// them at 100%.

final _at = DateTime.utc(2026, 9, 28, 20);

/// LiveItems.png's moment: Monday, September 28, 2026, 9:23:53 PM.
final liveSampleNow = DateTime(2026, 9, 28, 21, 23, 53);

/// A loopy line of "handwriting" from [from], [length] long.
List<Offset> scrawl(Offset from, double length, {double size = 8, double phase = 0}) => [
      for (var i = 0; i <= (length / 3).round(); i++)
        Offset(
          from.dx + length * i / (length / 3).round() + size * 0.5 * math.cos(i / 2.2 + phase),
          from.dy + size * math.sin(i / 2.2 + phase) * 0.9,
        ),
    ];

/// Charts.png: "Lab data.xlsx" with its chart of momentum before and after
/// (selected in the design), and the Study hours table with its chart.
/// Returns the notebook and the file's bytes (its asset).
(LoadedNotebook, OfficeItem, Uint8List) chartsSample({bool seventh = false}) {
  final xlsx = momentumXlsx(seventh: seventh);
  final book = readOffice(xlsx, OfficeKind.xlsx) as Workbook;
  final file = OfficeItem(
    id: 'it_labdata',
    x: 40,
    y: 96,
    z: 1,
    createdAt: _at,
    w: 430,
    h: 332,
    asset: assetNameFor(xlsx, ext: 'xlsx'),
    mime: 'xlsx',
    name: 'Lab data.xlsx',
    unit: 1,
  );
  const table = TableData([
    ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
    ['2', '1.5', '3', '2.5', '1'],
  ]);
  final hours = CardItem(id: 'it_hours', x: 40, y: 486, z: 2, createdAt: _at, w: 430, h: 156, data: table, title: 'Study hours', unit: 1);
  const labSource = ChartSource(kind: 'xlsx', ref: 'it_labdata', sheet: 'Sheet1', name: 'Lab data.xlsx');
  final momentum = ChartItem(
    id: 'it_momentum',
    x: 540,
    y: 96,
    z: 3,
    createdAt: _at,
    w: 700,
    h: 404,
    title: 'Momentum before vs. after',
    source: labSource,
    cells: sourceCells(labSource, file, book: book)!,
  );
  const hoursSource = ChartSource(kind: 'table', ref: 'it_hours', name: 'Study hours');
  final week = ChartItem(
    id: 'it_week',
    x: 540,
    y: 530,
    z: 4,
    createdAt: _at,
    w: 700,
    h: 232,
    title: 'Study hours this week',
    source: hoursSource,
    cells: sourceCells(hoursSource, hours)!,
    colors: [tokens.extraInkDefaults[0]],
    suffix: 'h',
  );
  final page = BoardPage(id: 'pg_charts', items: [file, hours, momentum, week]);
  final nb = Notebook(id: 'nb_lab', title: 'Lab journal', createdAt: _at, updatedAt: _at, pageIds: [page.id]);
  return (LoadedNotebook(nb, [page]), file, xlsx);
}

/// [chartsSample] in a store, with the Excel file in its assets.
MemoryBoardStore chartsStore({bool seventh = false}) {
  final (nb, file, bytes) = chartsSample(seventh: seventh);
  final store = storeWith(nb);
  store.saveAsset(nb.notebook.id, file.asset, bytes);
  return store;
}

StrokeItem _ink(List<Offset> points, String id, {Color? color}) => StrokeItem.fromPagePoints(
      id: id,
      z: 0,
      createdAt: _at,
      tool: InkTool.pen,
      penType: PenType.ballpoint,
      color: color ?? tokens.inkDefaults[0],
      width: 2.4,
      usePressure: false,
      pagePoints: [for (final p in points) InkPoint(p.dx, p.dy, 0.5, 0)],
    );

/// LiveItems.png: the title, today's date, the clock, the checklist Before
/// the lab (two of five done) and three time-stamped notes.
LoadedNotebook liveSample() {
  var z = 1;
  final items = <Item>[
    TextItem(
      id: 'it_title',
      x: 60,
      y: 90,
      z: z++,
      createdAt: _at,
      wrap: 320,
      text: 'Lab day plan',
      font: 'hand',
      size: 46,
      color: tokens.inkDefaults[1],
      autoWidth: true,
    ),
    LiveItem(id: 'it_date', x: 276, y: 103, z: z++, createdAt: _at, data: const DateData()),
    LiveItem(id: 'it_clock', x: 60, y: 166, z: z++, createdAt: _at, data: const ClockData()),
  ];
  // The checklist: each entry written by hand on its row.
  const lengths = [116.0, 150.0, 128.0, 168.0, 140.0];
  items.add(ChecklistItem(
    id: 'it_list',
    x: 370,
    y: 166,
    z: z++,
    createdAt: _at,
    w: ChecklistItem.width,
    title: 'Before the lab',
    entries: [
      for (final (i, length) in lengths.indexed)
        ChecklistEntry(
          done: i < 2,
          ink: [_ink(scrawl(const Offset(2, 23), length, phase: i.toDouble()), 'it_entry$i')],
        ),
    ],
  ));
  // Notes with the time they were written.
  for (final (i, mins) in [47, 31, 12].indexed) {
    final top = 218.0 + 43 * i;
    items
      ..add(LiveItem(
        id: 'it_stamp$i',
        x: 800,
        y: top,
        z: z++,
        createdAt: _at,
        data: StampData(liveSampleNow.subtract(Duration(minutes: mins)).toUtc()),
      ))
      ..add(_ink(scrawl(Offset(896, top + 13), 210.0 + 40 * (i % 2), size: 9, phase: i * 1.7), 'it_note$i'));
  }
  final page = BoardPage(id: 'pg_live', items: items);
  final nb = Notebook(id: 'nb_lab', title: 'Lab journal', createdAt: _at, updatedAt: _at, pageIds: [page.id]);
  return LoadedNotebook(nb, [page]);
}
