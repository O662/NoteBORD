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
