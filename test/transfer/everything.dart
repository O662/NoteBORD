import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Color, Offset, Rect, Size;

import 'package:endless/board/codec.dart';
import 'package:endless/board/lock.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/canvas/connectors.dart';
import 'package:endless/canvas/new_items.dart';
import 'package:endless/state/assets.dart';
import 'package:endless/study/remember.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../office_samples.dart';
import '../sample_board.dart';

final everythingAt = DateTime.utc(2026, 9, 30, 9);

/// A notebook with every kind of item: ink (with an arrow, a straightened
/// line and a connector joined at both ends), shapes, text, sticky notes and
/// a stack, frames (plain and from a template), a picture, an imported PDF
/// page, the five cards, a PowerPoint with ink on its second slide, and an
/// item type from a newer app. Page 2 has a
/// template and lined paper; page 3 has its own password.
Future<(MemoryBoardStore, String password)> everythingNotebook() async {
  final store = MemoryBoardStore();
  final board = sampleBoard();
  final nb = board.notebook;
  final png = fakePng(7), pdf = Uint8List.fromList([...ascii.encode('%PDF-1.7\n'), 1, 2, 3]), preview = fakePng(9);
  final image = assetNameFor(png), pdfName = assetNameFor(pdf), previewName = assetNameFor(preview);
  final slides = officeFixture('Ch 9 slides.pptx');
  final slidesName = assetNameFor(slides, ext: 'pptx');

  final a = ShapeItem(id: 'it_a', x: 0, y: 900, z: 40, createdAt: everythingAt, kind: ShapeType.rect, w: 200, h: 120, stroke: const Color(0xFF2B5A8C), fill: const Color(0x332B5A8C), strokeWidth: 2.5);
  final b = ShapeItem(id: 'it_b', x: 500, y: 900, z: 41, createdAt: everythingAt, kind: ShapeType.ellipse, w: 180, h: 120, stroke: const Color(0xFFB5532A), strokeWidth: 3);
  final line = strokeFrom([for (var i = 0; i <= 20; i++) Offset(210 + i * 14.0, 960)], z: 42);
  final joined = attachEnds(line.copyWith(shape: () => 'line', arrow: () => const ArrowHeads(end: true, style: ArrowStyle.filled)), [a, b], slop: 16);
  expect(joined.startItemId, 'it_a');
  expect(joined.endItemId, 'it_b');

  final extra = [
    a,
    b,
    joined,
    ShapeItem(id: 'it_tri', x: 800, y: 900, z: 43, createdAt: everythingAt, kind: ShapeType.triangle, w: 90, h: 80, stroke: const Color(0xFF3E7B4F), strokeWidth: 2, rotation: 12),
    TextItem(id: 'it_text', x: 0, y: 1100, z: 44, createdAt: everythingAt, wrap: 300, text: 'Impulse = change in momentum\nJ = F·Δt', font: 'serif', size: 24, color: const Color(0xFF1E1C19), extra: {'futureField': true}),
    ImageItem(id: 'it_image', x: 400, y: 1100, z: 45, createdAt: everythingAt, w: 240, h: 180, asset: image, rotation: -4),
    OfficeItem(
      id: 'it_slides',
      x: 700,
      y: 1100,
      z: 47,
      createdAt: everythingAt,
      w: 495,
      h: 378,
      asset: slidesName,
      mime: 'pptx',
      name: 'Ch 9 slides.pptx',
      page: 2,
      pages: 3,
      pageSize: const Size(960, 540),
      inkByPage: {
        2: [strokeFrom([const Offset(120, 200), const Offset(400, 220)], z: 1)],
      },
    ),
    UnknownItem({'id': 'it_math', 'type': 'math', 'x': 0, 'y': 1400, 'z': 46, 'createdAt': everythingAt.toIso8601String(), 'w': 200, 'h': 60, 'latex': r'p = mv'}),
    // Phase 6b: a 3D graph that remembers a 2D trace and handwriting, and
    // the three math tools; a calendar widget from a newer app.
    GraphItem(
      id: 'it_graph',
      x: 0,
      y: 1600,
      z: 48,
      createdAt: everythingAt,
      w: 430,
      h: 330,
      unit: 0.5,
      mode: GraphMode.d3,
      functions: const [
        GraphLine(r'y=2\sin x', Color(0xFFB5532A), ink: [
          [Offset(0, 8), Offset(6, 0), Offset(12, 8)],
        ]),
      ],
      trace: const GraphTrace(0, 1.5),
      surfaces: const [GraphLine(r'z=\frac{x^{2}-y^{2}}{4}', Color(0xFF2B5A8C)), GraphLine('(1,2,3)', Color(0xFF3E7B4F), hidden: true)],
      view3d: const GraphView3d(turn: -45, tilt: 40, surface: true),
      view: const Rect.fromLTRB(-5, -3, 5, 3),
    ),
    MathToolItem(
      id: 'it_line',
      x: 500,
      y: 1600,
      z: 49,
      createdAt: everythingAt,
      w: 790,
      h: 160,
      data: const NumberLineData(
        points: [NumberPoint('-2.5', Color(0xFF2B5A8C))],
        spans: [NumberSpan('1', r'\pi', Color(0xFF3E7B4F), openTo: true)],
      ),
    ),
    MathToolItem(id: 'it_circle', x: 500, y: 1800, z: 50, createdAt: everythingAt, w: 400, h: 424, data: const UnitCircleData(step: 2)),
    MathToolItem(
      id: 'it_polar',
      x: 950,
      y: 1800,
      z: 51,
      createdAt: everythingAt,
      w: 370,
      h: 406,
      data: const PolarData(curves: [GraphLine(r'r=1+\cos\theta', Color(0xFF2B5A8C))]),
    ),
    UnknownItem({'id': 'it_cal', 'type': 'widget', 'widget': 'calendar', 'x': 0, 'y': 2300, 'z': 52, 'createdAt': everythingAt.toIso8601String(), 'w': 300, 'h': 300, 'config': {'month': '2026-10'}}),
  ];
  final page1 = BoardPage(id: board.pages.single.id, title: 'Board', items: [...board.pages.single.items, ...extra]);
  // Phase 7a: ink marked to remember (with a reminder), and a flashcard
  // made from it and a line of the handout.
  final remembered = withRemember(strokeFrom([const Offset(80, 140), const Offset(300, 150)], z: 4), {
    ...const RememberMark(id: 'rm_1', why: 'on the exam', remind: RemindKind.date, flashcard: 'fc_1').toJson(),
    'remindAt': '2026-10-14T07:00:00.000Z',
  });
  final handoutLine = strokeFrom([const Offset(80, 80), const Offset(300, 90)], z: 2);
  final page2 = BoardPage(id: 'pg_pdf', title: 'Handout', paper: Paper.lines, template: 'cornell', items: [
    FileItem(id: 'it_pdf', x: 0, y: 0, z: 1, createdAt: everythingAt, w: 612, h: 792, asset: pdfName, mime: 'pdf', page: 1, preview: previewName, name: 'Handout.pdf', text: 'Momentum handout'),
    handoutLine,
    newFrame(const Offset(900, 400), z: 3, now: everythingAt).withBox(x: 900, y: 0, w: 560, h: 792),
    remembered,
    FlashcardItem(
      id: 'fc_1',
      x: 80,
      y: 140,
      z: 5,
      createdAt: everythingAt,
      deck: 'dk_1',
      deckName: 'Physics — Momentum',
      front: CardSide(ids: [remembered.id]),
      back: CardSide(ids: [handoutLine.id], text: 'on the exam'),
      reverse: true,
    ),
  ], extra: {'pageFuture': 'kept'});
  final secret = BoardPage(id: 'pg_secret', title: 'Grades', items: [strokeFrom([const Offset(0, 0), const Offset(50, 50)])]);

  const password = 'impulse-2026';
  final (entry, key) = await testCrypto.create(password, hint: 'unit of momentum');
  final notebook = Notebook(
    id: nb.id,
    title: nb.title,
    folderPath: nb.folderPath,
    coverColor: '#2B5A8C',
    createdAt: nb.createdAt,
    updatedAt: nb.updatedAt,
    pageIds: [page1.id, page2.id, secret.id],
    defaultPaper: Paper.grid,
    pinned: true,
    extra: {'notebookFuture': 1},
  );
  await store.savePage(nb.id, page1);
  await store.savePage(nb.id, page2);
  await store.saveSealedPage(nb.id, secret.id, await testCrypto.seal(key, encodePage(secret)));
  await store.saveLock(nb.id, LockFile(pages: {secret.id: entry}).toJson());
  await store.saveAsset(nb.id, image, png);
  await store.saveAsset(nb.id, pdfName, pdf);
  await store.saveAsset(nb.id, previewName, preview);
  await store.saveAsset(nb.id, slidesName, slides);
  await store.saveNotebook(notebook);
  return (store, password);
}

