// Phase 6b: the Graph screen (Graph.png) and Math tools (MathKit.png), end
// to end with S Pen and finger events.

import 'package:endless/board/ids.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/canvas/gesture_overlay.dart';
import 'package:endless/canvas/graph_card.dart';
import 'package:endless/canvas/math_mode.dart';
import 'package:endless/canvas/math_tools.dart';
import 'package:endless/canvas/selection.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/state/settings.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'math_mode_test.dart' show FakeMathReader, mathOverrides;

final _now = DateTime.utc(2026, 10, 21, 9);

/// Graph.png's graph, where the design has it.
GraphItem _sampleGraph({List<GraphLine>? functions}) => GraphItem(
      id: 'it_graph',
      x: 40,
      y: 96,
      z: 1,
      createdAt: _now,
      w: 860,
      h: 660,
      unit: 1,
      functions: functions ??
          const [
            GraphLine(r'y=\frac{x^{2}}{2}', Color(0xFF2B5A8C)),
            GraphLine(r'y=2\sin x', Color(0xFFB5532A)),
            GraphLine(r'y=x+1', Color(0xFF3E7B4F)),
          ],
      surfaces: const [GraphLine(r'z=\frac{x^{2}-y^{2}}{4}', Color(0xFF2B5A8C))],
      view: const Rect.fromLTRB(-5, -4, 5, 8),
    );

MemoryBoardStore _store(List<Item> items) {
  final page = BoardPage(id: 'pg_math', items: items);
  final nb = Notebook(id: newId('nb'), title: 'Calculus II', createdAt: _now, updatedAt: _now, pageIds: [page.id]);
  return storeWith(LoadedNotebook(nb, [page]));
}

GraphItem _graph(ProviderContainer c) => shownPage(c).items.whereType<GraphItem>().single;
List<MathToolItem> _tools(ProviderContainer c) => shownPage(c).items.whereType<MathToolItem>().toList();
MathToolItem _tool(ProviderContainer c, String id) => shownPage(c)[id]! as MathToolItem;
List<StrokeItem> _strokes(ProviderContainer c) => shownPage(c).items.whereType<StrokeItem>().toList();

/// Where [local] on [item] is on screen.
Offset _on(BoxItem item, Offset local) => canvasPane.view.toScreen(item.toPage(local));

/// Where (x, y) on the graph's plot is on screen.
Offset _plotAt(GraphItem g, double x, double y) {
  final plot = graphPlotRect(g);
  final v = g.view;
  return _on(g, Offset(plot.left + (x - v.left) / v.width * plot.width, plot.bottom - (y - v.top) / v.height * plot.height));
}

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

Future<void> _drag(WidgetTester tester, List<Offset> points, {bool pen = false}) async {
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

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

final _insert = find.descendant(of: find.bySemanticsLabel('Math keyboard'), matching: find.bySemanticsLabel('Insert'));

Future<void> _type(WidgetTester tester, String text) async {
  canvasPane.math.draft!.text.text = text;
  await tester.tap(_insert);
  await _settle(tester);
}

void _useTool(ProviderContainer c, CanvasTool tool) => c.read(settingsProvider.notifier).apply((s) => s.copyWith(tool: tool));

void main() {
  setUpAll(loadAppFonts);
  setUp(() => _clock = const Duration(seconds: 10));

  testWidgets('Math tools: Number line, Unit circle and Polar grid go on the page, clear of each other; each is one undo step', (tester) async {
    final c = await pumpCanvas(tester, extra: mathOverrides(FakeMathReader(null)));
    await tester.tap(byLabel('Study & math'));
    await tester.pump();
    await tester.tap(find.text('Math tools'));
    await tester.pump();
    final keyboard = tester.getRect(find.bySemanticsLabel('Math keyboard'));

    await tester.tap(find.bySemanticsLabel('Number line'));
    await _settle(tester);
    expect(find.text('Added a number line to the page'), findsOneWidget);
    final line = _tools(c).single;
    expect(line.data, isA<NumberLineData>());
    // On screen, above the keyboard, clear of the bar.
    final shown = Rect.fromPoints(_on(line, Offset.zero), _on(line, Offset(line.w, line.h)));
    expect(shown.top, greaterThan(84));
    expect(shown.bottom, lessThan(keyboard.top));

    await tester.tap(find.bySemanticsLabel('Unit circle'));
    await _settle(tester);
    expect(find.text('Added the unit circle to the page'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Polar grid'));
    await _settle(tester);
    expect(find.text('Added a polar grid to the page'), findsOneWidget);
    final tools = _tools(c);
    expect([for (final t in tools) t.data.kind], ['numberline', 'unitcircle', 'polar']);
    for (final a in tools) {
      for (final b in tools) {
        if (a != b) expect(a.extent.overlaps(b.extent), isFalse, reason: '${a.data.kind} / ${b.data.kind}');
      }
    }
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(_tools(c).map((t) => t.data.kind), ['numberline', 'unitcircle']);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the unit circle steps through the 16 angles with − and + (finger or pen), without undo steps or ink', (tester) async {
    final circle = MathToolItem(id: 'it_circle', x: 100, y: 120, z: 1, createdAt: _now, w: 400, h: 424, data: const UnitCircleData());
    final c = await pumpCanvas(tester, store: _store([circle]));
    final next = _on(circle, const Offset(400 - 16 - 22, 32));
    await _tap(tester, next);
    expect((_tool(c, 'it_circle').data as UnitCircleData).step, 5);
    // The pen presses it too, and doesn't write.
    await _tap(tester, next, pen: true);
    expect((_tool(c, 'it_circle').data as UnitCircleData).step, 6);
    expect(_strokes(c), isEmpty);
    for (var i = 0; i < 10; i++) {
      await _tap(tester, next);
    }
    expect((_tool(c, 'it_circle').data as UnitCircleData).step, 0, reason: 'round to 0°');
    // Where you are, not a change: nothing to undo.
    expect(c.read(notebookProvider(canvasPane.notebookId).notifier).canUndo(shownPage(c).id), isFalse);
    // − is left of the angle.
    final previous = [for (var x = 16.0; x < 340; x += 4) Offset(x, 32)].firstWhere((p) {
      final local = p;
      return local.dx > 150 && local.dx < 220;
    });
    await _tap(tester, _on(circle, previous));
    expect((_tool(c, 'it_circle').data as UnitCircleData).step, 15);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the number line: points and intervals typed in, ends opened and closed, intervals hidden, points changed and taken off', (tester) async {
    final line = MathToolItem(id: 'it_line', x: 40, y: 90, z: 1, createdAt: _now, w: 790, h: 160, data: const NumberLineData());
    final c = await pumpCanvas(tester, store: _store([line]), extra: mathOverrides(FakeMathReader(null)));
    NumberLineData data() => _tool(c, 'it_line').data as NumberLineData;
    const y = 12 + 36 + 6 + 43.0;
    double x(double v) => 55 + (v + 5) * 68;

    // + point, at the right of the header.
    await _tap(tester, _on(line, const Offset(790 - 16 - 10, 30)));
    final draft = canvasPane.math.draft!;
    expect((draft.purpose, draft.itemId, draft.hint), (DraftFor.numberLine, 'it_line', '√2, or an interval like [1, π)'));
    expect(find.text('√2, or an interval like [1, π)'), findsOneWidget);
    await _type(tester, '√2');
    expect(data().points.single.value, r'\sqrt{2}');
    expect(find.text('Added √2 to the number line'), findsOneWidget);
    expect(canvasPane.math.draft, isNull);

    await _tap(tester, _on(line, const Offset(790 - 16 - 10, 30)));
    await _type(tester, 'x + 1');
    expect(find.text('Type a number like √2, or an interval like [1, π)'), findsOneWidget);
    await _type(tester, '[1, π)');
    final span = data().spans.single;
    expect((span.from, span.to, span.openFrom, span.openTo), ('1', r'\pi', false, true));
    expect(find.text('Added [1, π) to the number line'), findsOneWidget);

    // Its end at π closes: one undo step.
    var tool = _tool(c, 'it_line');
    await _tap(tester, _on(tool, Offset(x(3.14159), y)));
    expect(data().spans.single.openTo, isFalse);
    c.read(notebookProvider(canvasPane.notebookId).notifier).undo(shownPage(c).id);
    await tester.pump();
    expect(data().spans.single.openTo, isTrue);

    // Its chip hides it (and shows it again).
    tool = _tool(c, 'it_line');
    final chip = [for (var cx = 140.0; cx < 760; cx += 4) Offset(cx, 30)]
        .firstWhere((p) => mathToolHitAt(tool, p) == const MathToolHit(MathToolPart.chip, 0));
    await _tap(tester, _on(tool, chip));
    expect(data().spans.single.hidden, isTrue);
    await _tap(tester, _on(tool, chip));
    expect(data().spans.single.hidden, isFalse);

    // A point, tapped: the keyboard on it; empty takes it off.
    await _tap(tester, _on(tool, Offset(x(1.41421), y - 26)));
    expect((canvasPane.math.draft!.index, canvasPane.math.draft!.text.text), (0, '√2'));
    await _type(tester, '');
    expect(data().points, isEmpty);
    expect(find.text('Took it off the number line'), findsOneWidget);
    // The interval, tapped on its bar: changed in place.
    await _tap(tester, _on(_tool(c, 'it_line'), Offset(x(2), y)));
    expect(canvasPane.math.draft!.text.text, '[1, π)');
    await _type(tester, '(−∞, 2]');
    expect(data().spans.single.openFrom, isTrue);
    expect(data().spans.single.from, r'-\infty');
    expect(find.text('Changed the number line'), findsOneWidget);
    // Outside math mode, a tap on the paper puts the keyboard away.
    await _tap(tester, _on(_tool(c, 'it_line'), const Offset(790 - 16 - 10, 30)));
    expect(canvasPane.math.draft, isNotNull);
    await _tap(tester, const Offset(600, 360));
    expect(canvasPane.math.draft, isNull);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the polar grid: chips show and hide curves, + adds one, a curve is tapped to change it', (tester) async {
    final polar = MathToolItem(
      id: 'it_polar',
      x: 460,
      y: 120,
      z: 1,
      createdAt: _now,
      w: 370,
      h: 406,
      data: const PolarData(curves: [
        GraphLine(r'r=1+\cos\theta', Color(0xFF2B5A8C)),
        GraphLine(r'r=2\cos 3\theta', Color(0xFFB5532A), hidden: true),
      ]),
    );
    final c = await pumpCanvas(tester, store: _store([polar]), extra: mathOverrides(FakeMathReader(null)));
    PolarData data() => _tool(c, 'it_polar').data as PolarData;
    // The rose's chip, just left of +.
    await _tap(tester, _on(polar, const Offset(370 - 16 - 36 - 8 - 20, 30)));
    expect(data().curves[1].hidden, isFalse);
    await _tap(tester, _on(polar, const Offset(370 - 16 - 18, 30)));
    expect(canvasPane.math.draft!.purpose, DraftFor.polarCurve);
    await _type(tester, 'r = x');
    expect(find.text('Type a polar curve like r = 1 + cos θ'), findsOneWidget);
    await _type(tester, 'r = 2 sin θ');
    expect(data().curves.last.expr, r'r=2\sin\theta');
    expect(find.text('Added r = 2 sin θ to the polar grid'), findsOneWidget);
    // The cardioid at θ = 0, on the outer ring.
    final tool = _tool(c, 'it_polar');
    final plotTop = tool.h - 12 - 2 - 338;
    await _tap(tester, _on(tool, Offset(16 + 169 + 140, plotTop + 169)));
    expect(canvasPane.math.draft!.text.text, 'r = 1 + cos θ');
    await _type(tester, 'r = 1 + sin θ');
    expect(data().curves.first.expr, r'r=1+\sin\theta');
    expect(find.text('Changed the polar grid'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a graph’s buttons: show and hide a function, 2D and 3D, turn, zoom, wireframe and surface', (tester) async {
    final c = await pumpCanvas(tester, store: _store([_sampleGraph()]));
    var g = _graph(c);
    // The dot of y = 2 sin x hides it; again shows it.
    await _tap(tester, _on(g, const Offset(46, 172)));
    expect(_graph(c).functions[1].hidden, isTrue);
    await _tap(tester, _on(g, const Offset(46, 172)), pen: true);
    expect(_graph(c).functions[1].hidden, isFalse);
    expect(_strokes(c), isEmpty);
    // Zoom in, then out.
    await _tap(tester, _on(g, const Offset(826, 30)));
    expect(_graph(c).view.width, closeTo(10 / 1.5, 1e-9));
    await _tap(tester, _on(g, const Offset(772, 30)));
    expect(_graph(c).view.width, closeTo(10, 1e-9));
    // 3D · x y z, turned right, then shaded.
    await _tap(tester, _on(g, const Offset(730, 30)));
    g = _graph(c);
    expect(g.mode, GraphMode.d3);
    await _tap(tester, _on(g, const Offset(718, 30)));
    expect(_graph(c).view3d.turn, 55);
    final row = [for (var x = 26.0; x < 256; x += 2) Offset(x, 138)];
    final surface = row.firstWhere((p) => graphHitAt(_graph(c), p)?.part == GraphPart.surface);
    await _tap(tester, _on(g, surface));
    expect(_graph(c).view3d.surface, isTrue);
    // None of that is an undo step.
    expect(c.read(notebookProvider(canvasPane.notebookId).notifier).canUndo(shownPage(c).id), isFalse);
    // A pen drag on the plot (with Select) turns it.
    _useTool(c, CanvasTool.select);
    await tester.pump();
    await _drag(tester, _line(_on(g, const Offset(500, 300)), _on(g, const Offset(440, 300))), pen: true);
    expect(_graph(c).view3d.turn, closeTo(85, 1e-9));
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('typing a function: added, changed, refused, taken off; the pen opens the writing pad', (tester) async {
    final c = await pumpCanvas(tester, store: _store([_sampleGraph()]), extra: mathOverrides(FakeMathReader(null)));
    final g = _graph(c);
    // "write or type an equation…", with a finger: the keys.
    await _tap(tester, _on(g, const Offset(130, 300)));
    var draft = canvasPane.math.draft!;
    expect((draft.purpose, draft.itemId, draft.index, draft.write), (DraftFor.graphLine, 'it_graph', null, false));
    expect(find.text('y = x² / 2'), findsOneWidget, reason: 'the hint');
    expect(find.bySemanticsLabel('Write it instead'), findsOneWidget);
    await _type(tester, 'x² + y² = 1');
    expect(find.text('Only a function of x can be graphed, like y = x²'), findsOneWidget);
    await _type(tester, 'y = x / 3');
    expect(_graph(c).functions, hasLength(4));
    expect(_graph(c).functions.last.expr, r'y=\frac{x}{3}');
    expect(_graph(c).functions.last.color, const Color(0xFF7A4E73), reason: 'the next color not in use');
    expect(find.text('Added y = x / 3 to the graph'), findsOneWidget);
    // Its chip: the keyboard on it; changed, then taken off.
    await _tap(tester, _on(_graph(c), const Offset(150, 104)));
    draft = canvasPane.math.draft!;
    expect((draft.index, draft.text.text), (0, 'y = x² / 2'));
    await _type(tester, 'y = x²');
    expect(_graph(c).functions.first.expr, r'y=x^{2}');
    expect(_graph(c).functions.first.color, const Color(0xFF2B5A8C));
    expect(find.text('Changed the graph'), findsOneWidget);
    await _tap(tester, _on(_graph(c), const Offset(150, 104)));
    await _type(tester, '');
    expect(_graph(c).functions, hasLength(3));
    expect(find.text('Took it off the graph'), findsOneWidget);
    c.read(notebookProvider(canvasPane.notebookId).notifier).undo(shownPage(c).id);
    await tester.pump();
    expect(_graph(c).functions, hasLength(4));
    // With the pen, it opens on the writing pad.
    await _tap(tester, _on(_graph(c), const Offset(130, 380)), pen: true);
    expect(canvasPane.math.draft!.write, isTrue);
    expect(find.bySemanticsLabel('Type it instead'), findsOneWidget);
    expect(_strokes(c), isEmpty);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('tracing: Select and the pen follow a curve, snapping to tenths and crossings; a finger tap traces; the pen writes on the plot', (tester) async {
    final c = await pumpCanvas(tester, store: _store([_sampleGraph()]));
    var g = _graph(c);
    // A finger tap on the plot, near (2, 2).
    await _tap(tester, _plotAt(g, 2.02, 2.3));
    expect(_graph(c).trace, const GraphTrace(0, 2));
    expect(graphTracePoint(_graph(c))!.y, 2);
    // With Select, the pen drags along it, ending on the crossing at 1.93.
    _useTool(c, CanvasTool.select);
    await tester.pump();
    await _drag(tester, _line(_plotAt(g, -1, 0.5), _plotAt(g, 1.94, 1.88)), pen: true);
    g = _graph(c);
    expect(g.trace!.x, closeTo(1.9338, 1e-3));
    expect(graphTracePoint(g)!.crossing, isTrue);
    expect(canvasPane.selection.isEmpty, isTrue, reason: 'tracing doesn’t select');
    // With the pen tool, outside math mode, the pen writes on the plot.
    _useTool(c, CanvasTool.pen);
    await tester.pump();
    await _drag(tester, _line(_plotAt(g, -3, 6), _plotAt(g, -1, 6)), pen: true);
    expect(_strokes(c), hasLength(1));
    expect(_graph(c).trace, g.trace);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('fingers on a selected graph’s plot pan and pinch its window; elsewhere they pan the page', (tester) async {
    final c = await pumpCanvas(tester, store: _store([_sampleGraph()]));
    final g = _graph(c);
    // Not selected: a finger drag pans the page.
    final before = canvasPane.view.translation;
    await _drag(tester, _line(_plotAt(g, 0, 0), _plotAt(g, 0, 0) + const Offset(0, 80)));
    expect(canvasPane.view.translation, isNot(before));
    expect(_graph(c).view, g.view);
    canvasPane.view.jumpTo(1, before);
    await tester.pump();

    // Selected (Select, a tap on its title), one finger drags the window.
    _useTool(c, CanvasTool.select);
    await tester.pump();
    await _tap(tester, _on(g, const Offset(80, 30)), pen: true);
    expect(canvasPane.selection.ids, {'it_graph'});
    await _drag(tester, _line(_plotAt(g, 0, 0), _plotAt(g, 2, 0), n: 20));
    final panned = _graph(c);
    expect(panned.view.left, lessThan(-5.5));
    expect((panned.x, panned.y), (g.x, g.y), reason: 'the graph stays put');

    // Two fingers pinch it.
    final a = await tester.createGesture(kind: PointerDeviceKind.touch);
    final b = await tester.createGesture(kind: PointerDeviceKind.touch);
    final t = _tick();
    final mid = _plotAt(panned, -1, 2);
    await a.down(mid - const Offset(40, 0), timeStamp: t);
    await b.down(mid + const Offset(40, 0), timeStamp: t);
    for (var i = 1; i <= 10; i++) {
      await a.moveTo(mid - Offset(40.0 + i * 8, 0), timeStamp: t + Duration(milliseconds: i * 8));
      await b.moveTo(mid + Offset(40.0 + i * 8, 0), timeStamp: t + Duration(milliseconds: i * 8));
    }
    await a.up();
    await b.up();
    await tester.pump();
    expect(_graph(c).view.width, lessThan(panned.view.width * 0.6));
    expect(canvasPane.selection.ids, {'it_graph'});
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Graph it puts the handwriting’s function on the graph on screen, from your handwriting; otherwise a new graph', (tester) async {
    final reader = FakeMathReader(r'y=2\sin x');
    final c = await pumpCanvas(
      tester,
      store: _store([_sampleGraph(functions: const [GraphLine(r'y=\frac{x^{2}}{2}', Color(0xFF2B5A8C)), GraphLine(r'y=x+1', Color(0xFF3E7B4F))])]),
      extra: mathOverrides(reader),
    );
    c.read(settingsProvider.notifier).apply((s) => s.copyWith(penColor: const Color(0xFFB5532A)));
    await tester.tap(byLabel('Study & math'));
    await tester.pump();
    await tester.tap(find.text('Math & graphs'));
    await tester.pump();
    // y = 2 sin x, written right of the graph (Graph.png).
    for (final (a, b) in [
      (const Offset(990, 210), const Offset(1000, 240)),
      (const Offset(1000, 240), const Offset(1012, 205)),
      (const Offset(1030, 220), const Offset(1050, 220)),
      (const Offset(1030, 230), const Offset(1050, 230)),
    ]) {
      await _drag(tester, _line(a, b), pen: true);
    }
    await tester.pump(const Duration(milliseconds: 1300));
    await _settle(tester);
    expect(canvasPane.selection.menu, SelectionMenu.math);
    await tester.tap(find.bySemanticsLabel('Graph it'));
    await _settle(tester);
    final g = _graph(c);
    expect(g.functions, hasLength(3));
    final added = g.functions.last;
    expect(added.expr, r'y=2\sin x');
    // In the ink's color (Graph.png's terracotta), with a copy of the ink.
    expect(added.color, const Color(0xFFB5532A));
    expect(added.ink, hasLength(4));
    expect(find.text('Added y = 2 sin x to the graph'), findsOneWidget);
    expect(_strokes(c), hasLength(4), reason: 'the ink stays');
    // Graph.png's "Graphed": the writing stays outlined, with its badge…
    final ink = _strokes(c).map((s) => s.bounds).reduce((a, b) => a.expandToInclude(b));
    final marked = _overlay(tester).graphed;
    expect(marked, isNotNull);
    expect(marked!.getBounds().contains(ink.topLeft) && marked.getBounds().contains(ink.bottomRight), isTrue);
    expect(canvasPane.selection.isEmpty, isTrue);
    // …while you trace the graph…
    await _drag(tester, _line(_plotAt(g, -1, 0.5), _plotAt(g, 1, 0.5)), pen: true);
    expect(_graph(c).trace, isNotNull);
    expect(_overlay(tester).graphed, same(marked));

    // …and goes when you write again. With no graph on screen, a new one
    // beside the ink.
    canvasPane.view.jumpTo(1, const Offset(0, -2000));
    await tester.pump();
    await _drag(tester, _line(const Offset(400, 300), const Offset(440, 300)), pen: true);
    expect(_overlay(tester).graphed, isNull);
    await tester.pump(const Duration(milliseconds: 1300));
    await _settle(tester);
    await tester.tap(find.bySemanticsLabel('Graph it'));
    await _settle(tester);
    final graphs = shownPage(c).items.whereType<GraphItem>().toList();
    expect(graphs, hasLength(2));
    expect((graphs.last.w, graphs.last.h, graphs.last.unit), (860.0, 660.0, 1.0));
    expect(find.text('Graphed it'), findsOneWidget);
    // In math mode the pen traces the plot instead of writing on it.
    final fresh = graphs.last;
    await _drag(tester, _line(_plotAt(fresh, -1, 0), _plotAt(fresh, 1, 0)), pen: true);
    expect((shownPage(c)[fresh.id]! as GraphItem).trace, isNotNull);
    expect(_strokes(c), hasLength(5));
    // Leaving math mode takes the mark away.
    expect(_overlay(tester).graphed, isNotNull);
    await tester.tap(find.bySemanticsLabel('Done'));
    await tester.pump();
    expect(_overlay(tester).graphed, isNull);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a function written on a graph’s pad goes on the graph, with the writing; changed by hand, without it', (tester) async {
    final reader = FakeMathReader(r'y=2\sin x');
    final c = await pumpCanvas(
      tester,
      store: _store([_sampleGraph(functions: const [GraphLine(r'y=\frac{x^{2}}{2}', Color(0xFF2B5A8C)), GraphLine(r'y=x+1', Color(0xFF3E7B4F))])]),
      extra: mathOverrides(reader),
    );
    /// "write or type an equation…", wherever it is now.
    Offset addBox() {
      final g = _graph(c);
      final local = [for (var y = 60.0; y < 600; y += 4) Offset(130, y)].firstWhere((p) => graphHitAt(g, p)?.part == GraphPart.add);
      return _on(g, local + const Offset(0, 8));
    }

    Future<void> writeOnPad() async {
      final pad = tester.getRect(_pad);
      // Two strokes with the S Pen, then the pen rests.
      await _drag(tester, _line(pad.center + const Offset(-60, -20), pad.center + const Offset(-40, 20)), pen: true);
      await _drag(tester, _line(pad.center + const Offset(-10, 0), pad.center + const Offset(40, 0)), pen: true);
      await tester.pump(const Duration(milliseconds: 900));
      await _settle(tester);
    }

    // The pen on the box: the keyboard opens on its writing pad.
    await _tap(tester, addBox(), pen: true);
    expect(canvasPane.math.draft!.purpose, DraftFor.graphLine);
    expect(_pad, findsOneWidget);
    await writeOnPad();
    expect(reader.reads, 1);
    expect(canvasPane.math.draft!.text.text, 'y = 2 sin x', reason: 'what the model read, as the keyboard writes it');

    await tester.tap(_insert);
    await _settle(tester);
    final added = _graph(c).functions.last;
    expect(_graph(c).functions, hasLength(3));
    expect(added.expr, r'y=2\sin x');
    expect(added.color, const Color(0xFFB5532A));
    expect(added.ink, hasLength(2), reason: 'from your handwriting');
    expect(find.text('Added y = 2 sin x to the graph'), findsOneWidget);
    expect(_strokes(c), isEmpty, reason: 'the pad’s writing isn’t put on the page');
    expect(canvasPane.math.draft, isNull);

    // Written, then changed with the keys: the writing no longer says it.
    reader.latex = r'y=3\sin x';
    await _tap(tester, addBox(), pen: true);
    await writeOnPad();
    expect(canvasPane.math.draft!.text.text, 'y = 3 sin x');
    canvasPane.math.draft!.text.text = 'y = 3 cos x';
    await tester.tap(_insert);
    await _settle(tester);
    expect(_graph(c).functions.last.expr, r'y=3\cos x');
    expect(_graph(c).functions.last.ink, isEmpty);
    await tester.pump(const Duration(seconds: 5));
  });
}

/// The math keyboard's writing pad.
final _pad = find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Writing pad');

/// What the canvas's gesture overlay is showing.
GestureOverlayState _overlay(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<GestureOverlayPainter>()
    .first
    .overlay;
