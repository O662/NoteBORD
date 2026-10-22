import 'dart:convert';
import 'dart:ui';

import 'package:endless/board/codec.dart';
import 'package:endless/board/model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 15, 9);

  test('math round-trips through a page file', () {
    final m = MathItem(
      id: 'it_m',
      x: 110,
      y: 156,
      z: 3,
      createdAt: now,
      latex: r'v=\sqrt{v_{0}^{2}+2gh}',
      w: 206.5,
      h: 64,
      size: 32,
      color: const Color(0xFF2B5A8C),
    );
    final json = jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>;
    expect(json['type'], 'math');
    expect(json['latex'], r'v=\sqrt{v_{0}^{2}+2gh}');
    final back = decodeItem(json) as MathItem;
    expect((back.latex, back.w, back.h, back.size, back.color), (m.latex, m.w, m.h, m.size, m.color));
  });

  test('a graph round-trips with its functions and view', () {
    final g = GraphItem(
      id: 'it_g',
      x: 0,
      y: 0,
      z: 1,
      createdAt: now,
      w: 560,
      h: 380,
      functions: const [GraphLine(r'y=\frac{x^{2}}{2}', Color(0xFF2B5A8C)), GraphLine(r'y=2\sin x', Color(0xFFB5532A))],
      view: const Rect.fromLTRB(-5, -3, 5, 8),
    );
    final json = jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>;
    expect(json['mode'], '2d');
    expect(json['view'], {'xMin': -5.0, 'xMax': 5.0, 'yMin': -3.0, 'yMax': 8.0});
    final back = decodeItem(json) as GraphItem;
    expect(back.functions, g.functions);
    expect(back.view, g.view);
  });

  test('a 3D graph round-trips: surfaces and points, the view, the trace, hidden functions and handwriting', () {
    final g = GraphItem(
      id: 'it_g',
      x: 40,
      y: 96,
      z: 1,
      createdAt: now,
      w: 860,
      h: 660,
      unit: 1,
      mode: GraphMode.d3,
      functions: const [
        GraphLine(r'y=\frac{x^{2}}{2}', Color(0xFF2B5A8C), hidden: true),
        GraphLine(r'y=2\sin x', Color(0xFFB5532A), ink: [
          [Offset(0, 10), Offset(4.5, 0), Offset(9, 10)],
          [Offset(12, 5), Offset(20, 5)],
        ]),
      ],
      trace: const GraphTrace(1, 1.93),
      surfaces: const [GraphLine(r'z=\frac{x^{2}-y^{2}}{4}', Color(0xFF2B5A8C)), GraphLine('(1,2,3)', Color(0xFFB5532A))],
      view3d: const GraphView3d(turn: 55, tilt: 30, zoom: 1.5, surface: true),
      view: const Rect.fromLTRB(-5, -4, 5, 8),
    );
    final json = jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>;
    expect(json['mode'], '3d');
    expect(json['view3d'], {'turn': 55.0, 'tilt': 30.0, 'zoom': 1.5, 'style': 'surface'});
    expect(json['trace'], {'fn': 1, 'x': 1.93});
    expect((json['functions'] as List)[0], {'expr': r'y=\frac{x^{2}}{2}', 'color': '#2B5A8C', 'hidden': true});
    expect((json['functions'] as List)[1]['ink'], [
      [0.0, 10.0, 4.5, 0.0, 9.0, 10.0],
      [12.0, 5.0, 20.0, 5.0],
    ]);
    final back = decodeItem(json) as GraphItem;
    expect((back.mode, back.unit, back.trace, back.view3d), (g.mode, g.unit, g.trace, g.view3d));
    expect(back.functions, g.functions);
    expect(back.surfaces, g.surfaces);
    expect(jsonEncode(back.toJson()), jsonEncode(g.toJson()));
  });

  test('a graph from Phase 6a (no unit, no 3D) reads with its scale from its width', () {
    final back = decodeItem({
      'id': 'it_old',
      'type': 'graph',
      'x': 0,
      'y': 0,
      'rotation': 0,
      'z': 1,
      'createdAt': now.toIso8601String(),
      'w': 430,
      'h': 330,
      'mode': '2d',
      'functions': [
        {'expr': 'y=x', 'color': '#2B5A8C'},
      ],
      'view': {'xMin': -5, 'xMax': 5, 'yMin': -5, 'yMax': 5},
    }) as GraphItem;
    expect((back.unit, back.mode, back.trace, back.view3d), (0.5, GraphMode.d2, null, const GraphView3d()));
    expect(back.surfaces, isEmpty);
    // Scaled by a corner, its parts grow; stretched by an edge, they don't.
    expect((back.placed(center: back.center, scale: 2) as GraphItem).unit, 1);
    expect(back.withBox(x: 0, y: 0, w: 600, h: 330).unit, 0.5);
  });

  test('math tools round-trip as widget items; unknown fields and kinds are kept', () {
    final tools = [
      MathToolItem(
        id: 'it_line',
        x: 40,
        y: 90,
        z: 1,
        createdAt: now,
        w: 790,
        h: 160,
        data: const NumberLineData(
          points: [NumberPoint('-2.5', Color(0xFF2B5A8C)), NumberPoint(r'\sqrt{2}', Color(0xFFB5532A))],
          spans: [NumberSpan('1', r'\pi', Color(0xFF3E7B4F), openTo: true), NumberSpan(r'-\infty', '0', Color(0xFF7A4E73), openFrom: true, hidden: true)],
          rest: {'ticks': 'every 1'},
        ),
      ),
      MathToolItem(id: 'it_circle', x: 40, y: 262, z: 2, createdAt: now, w: 400, h: 424, unit: 1.25, data: const UnitCircleData(step: 7)),
      MathToolItem(
        id: 'it_polar',
        x: 460,
        y: 262,
        z: 3,
        createdAt: now,
        w: 370,
        h: 406,
        data: const PolarData(curves: [GraphLine(r'r=1+\cos\theta', Color(0xFF2B5A8C)), GraphLine(r'r=2\cos 3\theta', Color(0xFFB5532A), hidden: true)]),
      ),
    ];
    for (final t in tools) {
      final json = jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>;
      expect(json['type'], 'widget');
      expect(json['widget'], t.data.kind);
      final back = decodeItem(json) as MathToolItem;
      expect(jsonEncode(back.toJson()), jsonEncode(t.toJson()), reason: t.data.kind);
    }
    final line = jsonDecode(jsonEncode(tools[0].toJson())) as Map<String, dynamic>;
    expect((line['config'] as Map)['intervals'], [
      {'from': '1', 'to': r'\pi', 'openFrom': false, 'openTo': true, 'color': '#3E7B4F'},
      {'from': r'-\infty', 'to': '0', 'openFrom': true, 'openTo': false, 'color': '#7A4E73', 'hidden': true},
    ]);
    expect((line['config'] as Map)['ticks'], 'every 1');
    // A widget this version doesn't have yet (a calendar) stays as it was.
    final calendar = {
      'id': 'it_cal',
      'type': 'widget',
      'widget': 'calendar',
      'x': 0,
      'y': 0,
      'z': 4,
      'createdAt': now.toIso8601String(),
      'w': 300,
      'h': 300,
      'config': {'month': '2026-10'},
    };
    final kept = decodeItem(calendar);
    expect(kept, isA<UnknownItem>());
    expect(kept.toJson(), calendar);
  });

  test('math scales with its card, by a corner or a pinch', () {
    final m = MathItem(id: 'it_m', x: 0, y: 0, z: 1, createdAt: now, latex: 'x', w: 100, h: 50, color: const Color(0xFF000000));
    expect((m.placed(center: m.center, scale: 2) as MathItem).size, 64);
    expect(m.withBox(x: 0, y: 0, w: 150, h: 75).size, 48);
  });

  test('the card is the typeset math plus padding, at its size', () {
    final box = MathItem.boxFor(const Size(200, 60), 40, 32);
    final pad = MathItem.padding(32);
    expect(box.width, closeTo(160 + pad.horizontal, 1e-9));
    expect(box.height, closeTo(48 + pad.vertical, 1e-9));
  });
}
