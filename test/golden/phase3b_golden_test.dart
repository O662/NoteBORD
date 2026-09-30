// Golden images of Phase 3b at 1280×800: the Insert menu, the whole board,
// and text boxes, sticky notes, paper frames, images and shapes. Compare
// with design/screens/Insert.png and Board.png.
//
// Regenerate after an intended visual change:
//   flutter test --update-goldens test/golden
@Tags(['golden'])
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/canvas/new_items.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/templates/templates.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

Future<void> _withShadows(Future<void> Function() body) async {
  debugDisableShadows = false;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
  }
}

final _at = DateTime.utc(2026, 9, 29, 12);

/// A loopy line of "handwriting".
List<Offset> _scrawl(Offset from, double length, {double size = 12}) => [
      for (var i = 0; i <= 160; i++)
        Offset(from.dx + length * i / 160 + size * 0.5 * math.cos(i / 5), from.dy + size * math.sin(i / 5) * 0.9),
    ];

double _wobble(int i) => 0.35 + 0.35 * (1 + math.sin(i / 7)) / 2;

/// A board like design/screens/Board.png, with what this phase can put on
/// it: a lined sheet with writing, a sticky note, a stack of five, an arrow,
/// a picture, typed text, shapes and a Cornell sheet.
LoadedNotebook _board() {
  final blue = tokens.inkDefaults[1], clay = tokens.inkDefaults[2], black = tokens.inkDefaults[0];
  var z = 1;
  StrokeItem ink(List<Offset> pts, {Color? color, double width = 3}) =>
      strokeFrom(pts, color: color ?? black, width: width, pressure: _wobble, z: z++);

  final frame = newFrame(const Offset(332, 140), z: 0, now: _at);
  final onFrame = [
    ink(_scrawl(Offset(frame.x + 100, frame.y + 80), 250, size: 13), color: blue, width: 3.5),
    for (final (i, len) in [300.0, 330.0, 280.0, 290.0].indexed)
      ink(_scrawl(Offset(frame.x + 100, frame.y + 120 + i * 40), len)),
    for (final (i, len) in [310.0, 260.0].indexed) ink(_scrawl(Offset(frame.x + 100, frame.y + 320 + i * 40), len)),
  ];

  var note = newSticky(const Offset(780, 252), z: z++, now: _at);
  for (final (i, len) in [150.0, 170.0, 120.0].indexed) {
    note = note.withInk(ink(_scrawl(Offset(700, 200 + i * 42.0), len, size: 11)));
  }

  var stack = newStickyStack(const Offset(780, 560), z: z++, now: _at).copyWith(count: 5);
  stack = stack.withInk(ink(_scrawl(const Offset(690, 490), 170, size: 13), width: 3.5));
  for (final (i, len) in [100.0, 150.0, 120.0].indexed) {
    stack = stack.withInk(ink(_scrawl(Offset(690, 540 + i * 38.0), len, size: 10), width: 2.5));
  }

  final arrow = StrokeItem.fromPagePoints(
    id: 'it_arrow',
    z: z++,
    createdAt: _at,
    tool: InkTool.pen,
    penType: PenType.ballpoint,
    color: clay,
    width: 3.5,
    usePressure: true,
    arrow: const ArrowHeads(end: true),
    pagePoints: [
      for (var i = 0; i <= 40; i++)
        InkPoint(870 + 110 * i / 40, 690 + 60 * math.sin(i / 40 * math.pi / 2), 0.5, i * 8),
    ],
  );

  final picture = ImageItem(id: 'it_image', x: 990, y: 140, z: z++, createdAt: _at, w: 560, h: 360, asset: 'picture.png');
  final title = TextItem(
    id: 'it_title', x: 990, y: 530, z: z++, createdAt: _at, wrap: textAutoWrap, //
    text: 'Lab 4 — Collisions', font: 'serif', size: 40, color: black, autoWidth: true,
  );
  final body = TextItem(
    id: 'it_body', x: 990, y: 596, z: z++, createdAt: _at, wrap: 520, //
    text: 'Momentum before equals momentum after. Carts: 0.5 kg + 0.5 kg. The track must be level.',
    size: 22, color: black,
  );
  ShapeItem shape(ShapeType kind, Offset a, Offset b, Color color) =>
      shapeBetween(kind, a, b, id: 'it_${kind.name}$z', z: z++, now: _at, color: color, strokeWidth: 3);
  final shapes = [
    shape(ShapeType.rect, const Offset(990, 760), const Offset(1130, 850), blue),
    shape(ShapeType.arrow, const Offset(1140, 805), const Offset(1200, 805), black),
    shape(ShapeType.ellipse, const Offset(1210, 760), const Offset(1350, 850), clay),
    shape(ShapeType.arrow, const Offset(1360, 805), const Offset(1420, 805), black),
    shape(ShapeType.triangle, const Offset(1430, 755), const Offset(1550, 850), tokens.extraInkDefaults[0]),
  ];
  final cornell = newFrame(const Offset(1900, 140), z: -1, now: _at, template: templateById('cornell'));

  final page = BoardPage(
    id: 'pg_board',
    title: 'Board',
    items: [cornell, frame, ...onFrame, note, stack, arrow, picture, title, body, ...shapes],
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

late ui.Image _picture;

Future<TestGesture> _pen(WidgetTester t, List<Offset> pts) async {
  final g = await t.createGesture(kind: PointerDeviceKind.stylus);
  var ts = const Duration(seconds: 20);
  await g.down(pts.first, timeStamp: ts);
  for (final p in pts.skip(1)) {
    ts += const Duration(milliseconds: 8);
    await g.moveTo(p, timeStamp: ts);
  }
  await g.up(timeStamp: ts);
  await t.pump();
  return g;
}

/// Opens [notebook] (default: the board), runs [setUp], and compares with
/// `<name>.png`.
void _golden(
  String name, {
  LoadedNotebook Function() notebook = _board,
  int page = 0,
  ThemeMode mode = ThemeMode.light,
  required Future<void> Function(WidgetTester t, ProviderContainer c) setUp,
}) {
  testWidgets(name, (tester) => _withShadows(() async {
        final store = storeWith(notebook(), settings: AppSettings(themeMode: mode));
        store.assets['nb_board'] = {'picture.png': fakePng()};
        final c = await pumpCanvas(tester, store: store, extra: [decodeAs(_picture)]);
        if (page != 0) canvasPane.goTo(page);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await setUp(tester, c);
        await tester.pump();
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('$name.png'));
        await tester.pump(const Duration(seconds: 5));
      }));
}

Future<void> _openInsert(WidgetTester t) async {
  await t.tap(byLabel('Insert'));
  await t.pump();
  await t.tap(find.text('Everything else'));
  await t.pumpAndSettle();
}

Future<void> _wholeBoard(WidgetTester t) async {
  await t.tap(byLabel('Zoom out to the whole board'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
  await t.pump(const Duration(seconds: 5)); // the hint times out, like Board.png
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    _picture = testPicture(w: 560, h: 360);
  });
  tearDownAll(() => _picture.dispose());

  // Insert.png: the full menu over page 3 of the sample notebook.
  _golden('insert', notebook: sampleNotebook, page: 2, setUp: (t, c) => _openInsert(t));

  _golden('insert_dark', notebook: sampleNotebook, page: 2, mode: ThemeMode.dark, setUp: (t, c) => _openInsert(t));

  _golden('insert_search', notebook: sampleNotebook, page: 2, setUp: (t, c) async {
    await _openInsert(t);
    await t.enterText(find.byType(TextField), 'board');
    await t.pump();
  });

  // A later-phase tile's card, over the menu.
  _golden('insert_coming_soon', notebook: sampleNotebook, page: 2, setUp: (t, c) async {
    await _openInsert(t);
    await t.tap(find.text('PowerPoint'));
    await t.pumpAndSettle();
  });

  // Board.png: everything on the page at once, no menus.
  _golden('board', setUp: (t, c) => _wholeBoard(t));

  _golden('board_dark', mode: ThemeMode.dark, setUp: (t, c) => _wholeBoard(t));

  // The same page at 100%, as it opens: the sheet, the note and the stack.
  _golden('objects', setUp: (t, c) async {
    await t.pump(const Duration(seconds: 5));
  });

  // A sticky note selected: its outline follows its tilt, with edge handles
  // and the toolbar for objects.
  _golden('objects_selected', setUp: (t, c) async {
    await t.tap(byLabel('Select'));
    await t.pump();
    await _pen(t, const [Offset(780, 330)]);
    await t.tap(find.bySemanticsLabel('Color'));
    await t.pump();
    await t.pump(const Duration(seconds: 5));
  });

  // Typing in a new text box: the field and its font and size bar.
  _golden('text_editing', setUp: (t, c) async {
    await t.tap(byLabel('Text'));
    await t.pump();
    await _pen(t, const [Offset(140, 640)]);
    await t.enterText(find.byType(TextField), 'Result: close — check friction on cart B');
    await t.pump();
    await t.pump(const Duration(seconds: 5));
  });

  // The Shapes tool: its strip under the tool pill, and a shape just drawn.
  _golden('shapes', setUp: (t, c) async {
    await t.tap(byLabel('Shapes'));
    await t.pump();
    await t.tap(byLabel('Oval'));
    await t.pump();
    await _pen(t, [for (var i = 0; i <= 10; i++) Offset.lerp(const Offset(120, 560), const Offset(300, 690), i / 10)!]);
    await t.tap(byLabel('Shapes'));
    await t.pump();
  });
}
