import 'dart:math' as math;

import 'package:endless/board/model.dart';
import 'package:endless/canvas/graph_card.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 10, 21, 9);

/// Graph.png's graph: 860 × 660, three functions, x from −5 to 5 and y
/// from −4 to 8.
GraphItem _graph({double w = 860, double h = 660, double unit = 1, GraphMode mode = GraphMode.d2, GraphTrace? trace}) => GraphItem(
      id: 'it_graph',
      x: 40,
      y: 96,
      z: 1,
      createdAt: _now,
      w: w,
      h: h,
      unit: unit,
      mode: mode,
      trace: trace,
      functions: const [
        GraphLine(r'y=\frac{x^{2}}{2}', Color(0xFF2B5A8C)),
        GraphLine(r'y=2\sin x', Color(0xFFB5532A)),
        GraphLine(r'y=x+1', Color(0xFF3E7B4F)),
      ],
      surfaces: const [GraphLine(r'z=\frac{x^{2}-y^{2}}{4}', Color(0xFF2B5A8C))],
      view: const Rect.fromLTRB(-5, -4, 5, 8),
    );

/// Where the point (x, y) is drawn, relative to the card.
Offset _at(GraphItem g, double x, double y) {
  final plot = graphPlotRect(g);
  final v = g.view;
  return Offset(plot.left + (x - v.left) / v.width * plot.width, plot.bottom - (y - v.top) / v.height * plot.height);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the plot is where Graph.dc.html has it: 530 × 540, 285 in and 80 down', () {
    expect(graphPlotRect(_graph()), const Rect.fromLTWH(285, 80, 530, 540));
    // Scaled by a corner, it scales; stretched, the plot takes the room.
    expect(graphPlotRect(_graph(w: 430, h: 330, unit: 0.5)), const Rect.fromLTWH(142.5, 40, 265, 270));
    expect(graphPlotRect(_graph(w: 1060)).width, 730);
  });

  test('buttons: zoom, 2D / 3D, a dot per function, the equation box, the plot', () {
    final g = _graph();
    expect(graphHitAt(g, const Offset(826, 30)), const GraphHit(GraphPart.zoomIn));
    expect(graphHitAt(g, const Offset(772, 30)), const GraphHit(GraphPart.zoomOut));
    // The switch ends 10 left of zoom out (3 px of it is its padding): 3D
    // is its right half, 2D left of that.
    expect(graphHitAt(g, const Offset(730, 30)), const GraphHit(GraphPart.mode3d));
    final along = [for (var x = 400.0; x < 750; x += 2) graphHitAt(g, Offset(x, 30))];
    expect(along.indexOf(const GraphHit(GraphPart.mode2d)), lessThan(along.indexOf(const GraphHit(GraphPart.mode3d))));
    expect(along.indexOf(const GraphHit(GraphPart.mode2d)), greaterThan(0));
    // The dots, 22 + 14 + 10 in, centered on each 60-high chip (88 with
    // handwriting).
    expect(graphHitAt(g, const Offset(46, 104)), const GraphHit(GraphPart.toggle, 0));
    expect(graphHitAt(g, const Offset(46, 172)), const GraphHit(GraphPart.toggle, 1));
    expect(graphHitAt(g, const Offset(46, 240)), const GraphHit(GraphPart.toggle, 2));
    expect(graphHitAt(g, const Offset(150, 104)), const GraphHit(GraphPart.edit, 0));
    expect(graphHitAt(g, const Offset(130, 300)), const GraphHit(GraphPart.add));
    expect(graphHitAt(g, const Offset(500, 300)), const GraphHit(GraphPart.plot));
    // The header's title and the empty list are the card (they move it).
    expect(graphHitAt(g, const Offset(80, 30)), isNull);
    expect(graphHitAt(g, const Offset(130, 500)), isNull);
    expect(graphHitAt(g, const Offset(900, 30)), isNull);
    // At half size, half as far.
    expect(graphHitAt(_graph(w: 430, h: 330, unit: 0.5), const Offset(413, 15)), const GraphHit(GraphPart.zoomIn));
  });

  test('in 3D: turn buttons, Wireframe / Surface, and the surface’s square', () {
    final g = _graph(mode: GraphMode.d3);
    expect(graphHitAt(g, const Offset(826, 30)), const GraphHit(GraphPart.zoomIn));
    expect(graphHitAt(g, const Offset(718, 30)), const GraphHit(GraphPart.turnRight));
    expect(graphHitAt(g, const Offset(664, 30)), const GraphHit(GraphPart.turnLeft));
    expect(graphHitAt(g, const Offset(30, 104)), const GraphHit(GraphPart.toggle, 0));
    expect(graphHitAt(g, const Offset(150, 104)), const GraphHit(GraphPart.edit, 0));
    // Wireframe, then Surface, under the surface's formula.
    expect(graphHitAt(g, const Offset(30, 138)), const GraphHit(GraphPart.wireframe));
    final along = [for (var x = 26.0; x < 256; x += 2) graphHitAt(g, Offset(x, 138))];
    expect(along.lastIndexOf(const GraphHit(GraphPart.wireframe)), lessThan(along.indexOf(const GraphHit(GraphPart.surface))));
    expect(graphHitAt(g, const Offset(500, 300)), const GraphHit(GraphPart.plot));
  });

  test('where the curves cross: x²/2 and 2 sin x at 0 and 1.93, x²/2 and x + 1 at 1 ± √3', () {
    final xs = graphCrossings(_graph());
    bool has(double x, int a, int b) => xs.any((c) => (c.$1 - x).abs() < 1e-6 && c.$3 == a && c.$4 == b);
    expect(has(0, 0, 1), isTrue);
    expect(xs.firstWhere((c) => c.$3 == 0 && c.$4 == 1 && c.$1 > 1).$1, closeTo(1.9338, 1e-3));
    expect(has(1 - math.sqrt(3), 0, 2), isTrue);
    expect(has(1 + math.sqrt(3), 0, 2), isTrue);
    expect([for (final c in xs) c.$1], orderedEquals([...xs.map((c) => c.$1)]..sort()));
    // A hidden function crosses nothing.
    final g = _graph();
    final hidden = g.copyWith(functions: [g.functions[0], g.functions[1].copyWith(hidden: true), g.functions[2]]);
    expect(graphCrossings(hidden).any((c) => c.$3 == 1 || c.$4 == 1), isFalse);
  });

  test('tracing: the nearest curve at that x, snapped to tenths and to crossings', () {
    final g = _graph();
    // Graph.png's trace: (2, 2) on y = x²/2, from a touch a little off it.
    final traced = graphTracedAt(g, _at(g, 2.02, 2.3))!;
    expect(traced.trace, const GraphTrace(0, 2));
    final point = graphTracePoint(traced)!;
    expect((point.x, point.y, point.crossing), (2.0, 2.0, false));
    // On the marker at x ≈ 1.93, where it meets 2 sin x: snapped to the
    // crossing (nearer than any tenth).
    final crossing = graphTracedAt(g, _at(g, 1.94, 1.88))!;
    expect(crossing.trace!.x, closeTo(1.9338, 1e-3));
    expect(graphTracePoint(crossing)!.crossing, isTrue);
    // On 2 sin x, low down.
    expect(graphTracedAt(g, _at(g, -2, -1.8))!.trace!.line, 1);
    // A hidden function isn't traced.
    final hidden = g.copyWith(functions: [g.functions[0].copyWith(hidden: true), g.functions[1], g.functions[2]], trace: () => const GraphTrace(0, 2));
    expect(graphTracePoint(hidden), isNull);
    expect(graphTracedAt(hidden, _at(g, 2.02, 2.3))!.trace!.line, isNot(0));
    expect(graphTracedAt(_graph(mode: GraphMode.d3), _at(g, 2, 2)), isNull);
  });

  test('zooming and dragging the window; turning and tilting in 3D', () {
    final g = _graph();
    final zoomed = graphZoomed(g, 2);
    expect(zoomed.view, const Rect.fromLTRB(-2.5, -1, 2.5, 5));
    // About a point: it stays where it was.
    final about = graphZoomed(g, 2, local: _at(g, 2, 2));
    expect(_at(about, 2, 2).dx, closeTo(_at(g, 2, 2).dx, 1e-9));
    expect(_at(about, 2, 2).dy, closeTo(_at(g, 2, 2).dy, 1e-9));
    // Dragged 53 px right (one unit): the window moves one unit left.
    final dragged = graphDragged(g, const Offset(53, 0));
    expect(dragged.view.left, closeTo(-6, 1e-9));
    expect(dragged.view.top, -4);

    final g3 = _graph(mode: GraphMode.d3);
    expect(graphTurned(g3, 20).view3d.turn, 55);
    expect(graphTurned(g3, 160).view3d.turn, -165);
    final turned = graphDragged(g3, const Offset(-40, 20));
    expect(turned.view3d.turn, 55);
    expect(turned.view3d.tilt, 33);
    expect(graphDragged(g3, const Offset(0, 1000)).view3d.tilt, 89);
    expect(graphZoomed(g3, 100).view3d.zoom, 5);
  });

  test('numbers as the trace shows them', () {
    expect(graphNumber(2), '2');
    expect(graphNumber(1.93384), '1.93');
    expect(graphNumber(-0.5), '−0.5');
    expect(graphNumber(-0.001), '0');
    expect(graphNumber(2.999), '3');
  });

  test('new functions take the next color not in use', () {
    expect(nextGraphColor(const []), const Color(0xFF2B5A8C));
    expect(nextGraphColor(const [Color(0xFF2B5A8C), Color(0xFFB5532A)]), const Color(0xFF3E7B4F));
  });
}
