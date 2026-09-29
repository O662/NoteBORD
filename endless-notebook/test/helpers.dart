import 'dart:math' as math;

import 'package:endless/app.dart';
import 'package:endless/board/ids.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:endless/ui/canvas/canvas_screen.dart';
import 'package:endless/ui/common.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finds a chrome button by its accessible label.
Finder byLabel(String label) => find.byWidgetPredicate((w) => w is ChromeButton && w.label == label);

/// Loads the bundled fonts so text renders for real (not as boxes) in goldens.
Future<void> loadAppFonts() async {
  const families = {
    'Figtree': ['Regular', 'Medium', 'SemiBold', 'Bold'],
    'Newsreader': ['Regular', 'Medium', 'Italic', 'MediumItalic'],
    'Caveat': ['Regular', 'SemiBold'],
  };
  for (final e in families.entries) {
    final loader = FontLoader(e.key);
    for (final style in e.value) {
      loader.addFont(rootBundle.load('assets/fonts/${e.key}-$style.ttf'));
    }
    await loader.load();
  }
}

/// Pumps the app at the tablet size (1280×800) and returns its container.
Future<ProviderContainer> pumpCanvas(WidgetTester tester, {MemoryBoardStore? store}) async {
  tester.view.physicalSize = tokens.Sizes.tabletFrame;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final overrides = await bootstrap(store ?? MemoryBoardStore());
  await tester.pumpWidget(ProviderScope(overrides: overrides, child: const EndlessApp()));
  await tester.pump();
  return ProviderScope.containerOf(tester.element(find.byType(CanvasScreen)));
}

/// A store holding one notebook; optional settings.
MemoryBoardStore storeWith(LoadedNotebook nb, {AppSettings? settings}) {
  final store = MemoryBoardStore();
  store.saveNotebook(nb.notebook);
  for (final p in nb.pages) {
    store.savePage(nb.notebook.id, p);
  }
  store.pageWrites = 0;
  if (settings != null) store.settings = settings.toJson();
  return store;
}

StrokeItem strokeFrom(
  List<Offset> pts, {
  Color? color,
  double width = 2.5,
  InkTool tool = InkTool.pen,
  double Function(int i)? pressure,
  int z = 1,
}) =>
    StrokeItem.fromPagePoints(
      id: newId('it'),
      z: z,
      createdAt: DateTime.utc(2026, 9, 25, 10),
      tool: tool,
      penType: PenType.ballpoint,
      color: color ?? tokens.inkDefaults[0],
      width: width,
      usePressure: true,
      pagePoints: [
        for (final (i, p) in pts.indexed) InkPoint(p.dx, p.dy, pressure?.call(i) ?? 0.5, i * 8),
      ],
    );

/// "Physics — Lecture notes": 4 pages, ink on page 3, page 4 locked.
LoadedNotebook sampleNotebook() {
  final blue = tokens.inkDefaults[1];
  final clay = tokens.inkDefaults[2];
  final amber = tokens.extraInkDefaults[3];
  var z = 1;

  List<Offset> curve(Offset from, double length, double amp, double freq, {int n = 90}) => [
        for (var i = 0; i <= n; i++)
          Offset(from.dx + length * i / n, from.dy + amp * math.sin(i / n * freq * math.pi * 2)),
      ];
  List<Offset> ellipse(Offset c, double rx, double ry, {double turns = 1.08}) => [
        for (var i = 0; i <= 120; i++)
          Offset(c.dx + rx * math.cos(i / 120 * turns * 2 * math.pi - 2.2),
              c.dy + ry * math.sin(i / 120 * turns * 2 * math.pi - 2.2)),
      ];
  List<Offset> line(Offset a, Offset b) => [for (var i = 0; i <= 20; i++) Offset.lerp(a, b, i / 20)!];
  // Loopy "handwriting" line.
  List<Offset> scrawl(Offset from, double length, {double size = 14}) => [
        for (var i = 0; i <= 220; i++)
          Offset(from.dx + length * i / 220 + size * 0.5 * math.cos(i / 6), from.dy + size * math.sin(i / 6) * 0.9),
      ];
  double wobble(int i) => 0.35 + 0.35 * (1 + math.sin(i / 7)) / 2;

  final ink = <Item>[
    strokeFrom(scrawl(const Offset(730, 150), 380, size: 18), color: blue, width: 4, pressure: wobble, z: z++),
    strokeFrom(curve(const Offset(720, 184), 370, 3, 0.8), color: blue, width: 3, z: z++),
    strokeFrom(curve(const Offset(724, 296), 352, 1.5, 0.5), color: amber, width: 10, tool: InkTool.marker, z: z++),
    strokeFrom(scrawl(const Offset(736, 232), 150, size: 11), width: 3, pressure: wobble, z: z++),
    strokeFrom(scrawl(const Offset(736, 296), 330, size: 10), width: 2.5, pressure: wobble, z: z++),
    strokeFrom(scrawl(const Offset(736, 342), 200, size: 10), width: 2.5, pressure: wobble, z: z++),
    strokeFrom([...line(const Offset(726, 558), const Offset(1016, 558)), ...line(const Offset(1016, 558), const Offset(1016, 418)),
      ...line(const Offset(1016, 418), const Offset(726, 558))], width: 2.5, z: z++),
    strokeFrom(line(const Offset(884, 464), const Offset(884, 538)), color: clay, width: 2.5, z: z++),
    strokeFrom(line(const Offset(912, 452), const Offset(968, 425)), color: blue, width: 2.5, z: z++),
    strokeFrom(scrawl(const Offset(122, 376), 96, size: 14), color: blue, width: 3.5, pressure: wobble, z: z++),
    strokeFrom(scrawl(const Offset(132, 432), 130, size: 14), width: 3, pressure: wobble, z: z++),
    strokeFrom(ellipse(const Offset(204, 574), 78, 26), color: clay, width: 2.5, z: z++),
    strokeFrom(scrawl(const Offset(152, 574), 100, size: 10), color: clay, width: 3, pressure: wobble, z: z++),
    strokeFrom(scrawl(const Offset(128, 704), 220, size: 13), width: 3, pressure: wobble, z: z++),
  ];

  final pages = [
    BoardPage(id: 'pg_01'),
    BoardPage(id: 'pg_02'),
    BoardPage(id: 'pg_03', title: 'Lecture 3 — Momentum', items: ink),
    BoardPage(id: 'pg_04', locked: true),
  ];
  final nb = Notebook(
    id: 'nb_sample',
    title: 'Physics — Lecture notes',
    folderPath: ['School', 'Physics'],
    createdAt: DateTime.utc(2026, 9, 1, 14),
    updatedAt: DateTime.utc(2026, 9, 25, 10),
    pageIds: [for (final p in pages) p.id],
  );
  return LoadedNotebook(nb, pages);
}
