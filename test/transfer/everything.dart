import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Color, Offset;

import 'package:endless/board/codec.dart';
import 'package:endless/board/lock.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/canvas/connectors.dart';
import 'package:endless/canvas/new_items.dart';
import 'package:endless/state/assets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../sample_board.dart';

final everythingAt = DateTime.utc(2026, 9, 30, 9);

/// A notebook with every kind of item: ink (with an arrow, a straightened
/// line and a connector joined at both ends), shapes, text, sticky notes and
/// a stack, frames (plain and from a template), a picture, an imported PDF
/// page, the five cards, and an item type from a newer app. Page 2 has a
/// template and lined paper; page 3 has its own password.
Future<(MemoryBoardStore, String password)> everythingNotebook() async {
  final store = MemoryBoardStore();
  final board = sampleBoard();
  final nb = board.notebook;
  final png = fakePng(7), pdf = Uint8List.fromList([...ascii.encode('%PDF-1.7\n'), 1, 2, 3]), preview = fakePng(9);
  final image = assetNameFor(png), pdfName = assetNameFor(pdf), previewName = assetNameFor(preview);

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
    UnknownItem({'id': 'it_math', 'type': 'math', 'x': 0, 'y': 1400, 'z': 46, 'createdAt': everythingAt.toIso8601String(), 'w': 200, 'h': 60, 'latex': r'p = mv'}),
  ];
  final page1 = BoardPage(id: board.pages.single.id, title: 'Board', items: [...board.pages.single.items, ...extra]);
  final page2 = BoardPage(id: 'pg_pdf', title: 'Handout', paper: Paper.lines, template: 'cornell', items: [
    FileItem(id: 'it_pdf', x: 0, y: 0, z: 1, createdAt: everythingAt, w: 612, h: 792, asset: pdfName, mime: 'pdf', page: 1, preview: previewName, name: 'Handout.pdf', text: 'Momentum handout'),
    strokeFrom([const Offset(80, 80), const Offset(300, 90)], z: 2),
    newFrame(const Offset(900, 400), z: 3, now: everythingAt).withBox(x: 900, y: 0, w: 560, h: 792),
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
  await store.saveNotebook(notebook);
  return (store, password);
}

