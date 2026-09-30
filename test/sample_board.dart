import 'dart:math' as math;

import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/canvas/new_items.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:flutter/painting.dart';

import 'helpers.dart';

// The board on design/screens/Board.png, made of real items: the lined
// sheet, the sticky note, the stack of five, the Kanban board, the table,
// the timeline, the arrow, the website and the diagram. Page coordinates
// are the design's × 1.375 (the scale new cards are drawn at), so zoomed
// out to about 73% it sits where the design does.

const _u = CardItem.defaultUnit;
final _at = DateTime.utc(2026, 9, 29, 12);

Offset _p(double x, double y) => Offset(x, y) * _u;

/// A loopy line of "handwriting".
List<Offset> _scrawl(Offset from, double length, {double size = 9}) => [
      for (var i = 0; i <= 140; i++)
        Offset(from.dx + length * i / 140 + size * 0.5 * math.cos(i / 5), from.dy + size * math.sin(i / 5) * 0.9),
    ];

double _wobble(int i) => 0.35 + 0.35 * (1 + math.sin(i / 7)) / 2;

CardItem _card(String id, CardData data, String title, Rect box, int z) => CardItem(
      id: id,
      x: box.left * _u,
      y: box.top * _u,
      z: z,
      createdAt: _at,
      w: box.width * _u,
      h: box.height * _u,
      data: data,
      title: title,
    );

final sampleKanban = _card(
  'it_kanban',
  const KanbanData([
    KanbanColumn('To do', [KanbanCard('Read chapter 9'), KanbanCard('Problem set 4')]),
    KanbanColumn('Doing', [KanbanCard('Lab 4 report')]),
    KanbanColumn('Done', [KanbanCard('Chapter 8 quiz')]),
  ]),
  'Study tasks',
  const Rect.fromLTWH(584, 96, 420, 272),
  30,
);

final sampleTable = _card(
  'it_table',
  const TableData([
    ['Trial', 'm', 'v', 'p'],
    ['1', '0.50', '2.0', '1.00'],
    ['2', '0.50', '1.6', '0.80'],
    ['3', '1.00', '1.0', '1.00'],
  ]),
  'Lab data',
  const Rect.fromLTWH(1030, 96, 220, 200),
  31,
);

final sampleTimeline = _card(
  'it_timeline',
  const TimelineData([
    TimelineEvent(date: 'Sep 30', label: 'Lab report', state: EventState.done),
    TimelineEvent(date: 'Oct 14', label: 'Midterm', state: EventState.now),
    TimelineEvent(date: 'Nov 4', label: 'Project draft'),
    TimelineEvent(date: 'Dec 9', label: 'Final exam'),
  ]),
  'Semester',
  const Rect.fromLTWH(584, 400, 666, 132),
  32,
);

final sampleWebsite = _card(
  'it_website',
  const EmbedData('https://website-address.com/collision-lab'),
  'Collision lab simulation',
  const Rect.fromLTWH(516, 556, 290, 200),
  33,
);

final sampleDiagram = _card(
  'it_diagram',
  DiagramData.flow(const [
    DiagramNode(id: 'n1', text: 'Measure v₁'),
    DiagramNode(id: 'n2', text: 'Collide', shape: NodeShape.pill, color: NodeColor.clay),
    DiagramNode(id: 'n3', text: 'Measure v₂'),
    DiagramNode(id: 'n4', text: 'p equal?', shape: NodeShape.diamond, color: NodeColor.green),
  ]),
  'Experiment steps',
  const Rect.fromLTWH(830, 556, 420, 200),
  34,
);

/// "Physics — Lab 4": one page laid out like Board.png.
LoadedNotebook sampleBoard() {
  final blue = tokens.inkDefaults[1], clay = tokens.inkDefaults[2], black = tokens.inkDefaults[0];
  var z = 1;
  StrokeItem ink(List<Offset> pts, {Color? color, double width = 2.6}) =>
      strokeFrom(pts, color: color ?? black, width: width, pressure: _wobble, z: z++);

  // The design's sheet is 300 × 400: a lined A4 frame scaled to that width.
  final a4 = newFrame(Offset.zero, z: 0, now: _at);
  final frame = a4.withBox(
    id: 'it_frame',
    x: _p(36, 96).dx,
    y: _p(36, 96).dy,
    w: 300 * _u,
    h: 400 * _u,
    scale: 300 * _u / a4.w,
  );
  final rule = 40 * frame.unit;
  final onFrame = [
    ink(_scrawl(Offset(frame.x + 110 * frame.unit, frame.y + 96 * frame.unit - 10), 170), color: blue, width: 3),
    for (final (i, len) in [200.0, 215.0, 185.0, 190.0, 0.0, 205.0, 175.0].indexed)
      if (len > 0) ink(_scrawl(Offset(frame.x + 110 * frame.unit, frame.y + 96 * frame.unit - 10 + (i + 1) * rule), len)),
  ];

  var note = newSticky(_p(372 + 88, 96 + 80), z: z++, now: _at);
  for (final (i, len) in [150.0, 170.0, 110.0].indexed) {
    note = note.withInk(ink(_scrawl(_p(392, 128 + i * 30), len, size: 10), width: 3));
  }

  var stack = newStickyStack(_p(372 + 88, 300 + 80), z: z++, now: _at).copyWith(count: 5);
  stack = stack.withInk(ink(_scrawl(_p(390, 328), 160, size: 11), width: 3.4));
  for (final (i, len) in [90.0, 140.0, 110.0].indexed) {
    stack = stack.withInk(ink(_scrawl(_p(390, 362 + i * 27), len), width: 2.4));
  }

  // The arrow from the stack to the timeline: M8 8 C 20 40, 44 50, 70 46.
  Offset bezier(double t) {
    const a = Offset(8, 8), b = Offset(20, 40), c = Offset(44, 50), d = Offset(70, 46);
    final m = 1 - t;
    return a * (m * m * m) + b * (3 * m * m * t) + c * (3 * m * t * t) + d * (t * t * t);
  }

  final arrow = StrokeItem.fromPagePoints(
    id: 'it_arrow',
    z: z++,
    createdAt: _at,
    tool: InkTool.pen,
    penType: PenType.ballpoint,
    color: clay,
    width: 3.4,
    usePressure: true,
    arrow: const ArrowHeads(end: true),
    pagePoints: [
      for (var i = 0; i <= 30; i++)
        InkPoint(_p(510, 470).dx + bezier(i / 30).dx * _u, _p(510, 470).dy + bezier(i / 30).dy * _u, 0.5, i * 8),
    ],
  );

  final page = BoardPage(
    id: 'pg_board',
    title: 'Board',
    items: [
      frame, ...onFrame, note, stack, arrow, //
      sampleKanban, sampleTable, sampleTimeline, sampleWebsite, sampleDiagram,
    ],
  );
  final nb = Notebook(
    id: 'nb_board',
    title: 'Physics — Lab 4',
    folderPath: ['School', 'Physics'],
    createdAt: DateTime.utc(2026, 9, 1, 14),
    updatedAt: DateTime.utc(2026, 9, 25, 10),
    pageIds: [page.id],
  );
  return LoadedNotebook(nb, [page]);
}
