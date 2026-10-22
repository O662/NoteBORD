import 'dart:math' as math;

import 'package:endless/board/model.dart';
import 'package:endless/canvas/math_tools.dart';
import 'package:endless/math/evaluate.dart';
import 'package:endless/math/linear.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

final _now = DateTime.utc(2026, 10, 21, 9);
const _blue = Color(0xFF2B5A8C), _green = Color(0xFF3E7B4F);

MathToolItem _tool(MathToolData data, {double w = 0}) {
  final t = newMathTool(data.kind, const Offset(40, 90), z: 1, now: _now).copyWith(data: data);
  return fitMathTool(w == 0 ? t : t.withBox(x: t.x, y: t.y, w: w, h: t.h));
}

/// MathKit.png's number line: −2.5, and [1, π).
const _sample = NumberLineData(
  points: [NumberPoint('-2.5', _blue)],
  spans: [NumberSpan('1', r'\pi', _green, openTo: true)],
);

/// The number a unit circle's exact value is (√3/2, −1/2…).
double _exact(String s) => constantOf(linearToLatex(s))!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  test('new tools are MathKit.dc.html’s sizes', () {
    final line = newMathTool('numberline', Offset.zero, z: 1, now: _now);
    final circle = newMathTool('unitcircle', Offset.zero, z: 1, now: _now);
    final polar = newMathTool('polar', Offset.zero, z: 1, now: _now);
    expect((line.w, line.h), (790.0, 160.0));
    expect((circle.w, circle.h), (400.0, 424.0));
    expect((polar.w, polar.h), (370.0, 406.0));
    expect((circle.data as UnitCircleData).step, 4, reason: '90°, as in the design');
    // The cardioid shows; the rose is listed, off.
    final curves = (polar.data as PolarData).curves;
    expect([for (final c in curves) (c.expr, c.hidden)], [(r'r=1+\cos\theta', false), (r'r=2\cos 3\theta', true)]);
    expect(mathToolName(line.data), 'a number line');
  });

  test('the 16 special angles, exactly', () {
    expect(specialAngles, hasLength(16));
    for (final (deg, rad, cos, sin, tan) in specialAngles) {
      final t = deg * math.pi / 180;
      expect(_exact(rad.replaceAll('π', ' π')), closeTo(t, 1e-12), reason: rad);
      expect(_exact(cos), closeTo(math.cos(t), 1e-12), reason: '$deg° cos');
      expect(_exact(sin), closeTo(math.sin(t), 1e-12), reason: '$deg° sin');
      if (tan == 'undefined') {
        expect(math.cos(t).abs(), lessThan(1e-12), reason: '$deg°');
      } else {
        expect(_exact(tan), closeTo(math.tan(t), 1e-9), reason: '$deg° tan');
      }
    }
    final c = _tool(const UnitCircleData(step: 15));
    expect((unitCircleStepped(c, 1).data as UnitCircleData).step, 0);
    expect((unitCircleStepped(_tool(const UnitCircleData(step: 0)), -1).data as UnitCircleData).step, 15);
  });

  test('what’s typed for the number line: a number or an interval', () {
    expect(readNumberLine('√2', linearToLatex, _blue)!.point, r'\sqrt{2}');
    expect(readNumberLine('−2.5', linearToLatex, _blue)!.point, '-2.5');
    final span = readNumberLine('[1, π)', linearToLatex, _green)!.span!;
    expect((span.from, span.to, span.openFrom, span.openTo), ('1', r'\pi', false, true));
    final ray = readNumberLine('(−∞, 2]', linearToLatex, _green)!.span!;
    expect((ray.openFrom, ray.openTo, numberValue(ray.from)), (true, false, double.negativeInfinity));
    for (final no in ['[3, 1]', 'x', '', '[1, x)', '∞']) {
      expect(readNumberLine(no, linearToLatex, _blue), isNull, reason: no);
    }
    expect(numberLabel('-2.5'), '−2.5');
    expect(numberLabel(r'\sqrt{2}'), '√2');
    expect(intervalLabel(span), '[1, π)');
    expect(intervalLabel(ray), '(−∞, 2]');
  });

  test('the number line’s parts: its chips, its points and the ends of its intervals', () {
    final t = _tool(_sample);
    // The line is 43 into its 92-high strip, under the header row; −5 to 5
    // is 55 to 735.
    const y = 12 + 36 + 6 + 43.0;
    double x(double v) => 55 + (v + 5) * 68;
    expect(mathToolHitAt(t, Offset(x(-2.5), y)), const MathToolHit(MathToolPart.item, 0));
    expect(mathToolHitAt(t, Offset(x(-2.5), y - 26)), const MathToolHit(MathToolPart.item, 0), reason: 'its label');
    expect(mathToolHitAt(t, Offset(x(1), y)), const MathToolHit(MathToolPart.spanFrom, 0));
    expect(mathToolHitAt(t, Offset(x(math.pi) + 3, y)), const MathToolHit(MathToolPart.spanTo, 0));
    expect(mathToolHitAt(t, Offset(x(2), y)), const MathToolHit(MathToolPart.span, 0));
    expect(mathToolHitAt(t, Offset(x(4), y)), isNull);
    // The header: "interval [1, π)", then "+ point" at the right.
    expect(mathToolHitAt(t, const Offset(790 - 16 - 10, 30)), const MathToolHit(MathToolPart.add));
    final chips = [for (var cx = 100.0; cx < 760; cx += 2) mathToolHitAt(t, Offset(cx, 30))];
    expect(chips, contains(const MathToolHit(MathToolPart.chip, 0)));
    // Further out, the line reaches the numbers: −5 to 13 for a point at 12.
    final wide = _tool(const NumberLineData(points: [NumberPoint('12', _blue)]));
    expect(mathToolHitAt(wide, Offset(55 + 17 / 18 * 680, y)), const MathToolHit(MathToolPart.item, 0));
    // A hidden interval can't be hit on the line.
    final hidden = _tool(NumberLineData(spans: [_sample.spans.single.copyWith(hidden: true)]));
    expect(mathToolHitAt(hidden, Offset(x(2), y)), isNull);
  });

  test('more intervals than fit wrap onto another row; the tool grows', () {
    final many = _tool(NumberLineData(spans: [
      for (var i = 0; i < 8; i++) NumberSpan('$i', '${i + 1}', _green),
    ]));
    expect(many.h, greaterThan(160));
    expect(_tool(_sample).h, 160);
  });

  test('the unit circle’s − and +', () {
    final t = _tool(const UnitCircleData());
    expect(mathToolHitAt(t, const Offset(400 - 16 - 22, 32)), const MathToolHit(MathToolPart.next));
    final along = [for (var x = 16.0; x < 340; x += 2) mathToolHitAt(t, Offset(x, 32))];
    expect(along, contains(const MathToolHit(MathToolPart.previous)));
    expect(mathToolHitAt(t, const Offset(199, 216)), isNull);
  });

  test('the polar grid: chips show and hide curves, + adds one, a curve is tapped to edit it', () {
    final t = _tool(PolarData(curves: [
      const GraphLine(r'r=1+\cos\theta', _blue),
      const GraphLine(r'r=2\cos 3\theta', Color(0xFFB5532A), hidden: true),
    ]));
    expect(mathToolHitAt(t, const Offset(370 - 16 - 18, 30)), const MathToolHit(MathToolPart.add));
    final chips = [for (var x = 100.0; x < 320; x += 2) mathToolHitAt(t, Offset(x, 30))];
    expect(chips, containsAll([const MathToolHit(MathToolPart.chip, 0), const MathToolHit(MathToolPart.chip, 1)]));
    // The cardioid reaches 2 at θ = 0: the outer ring, 140 right of the middle.
    const center = Offset(16 + 169, 54 + 169.0);
    expect(mathToolHitAt(t, center + const Offset(140, 0)), const MathToolHit(MathToolPart.item, 0));
    expect(mathToolHitAt(t, center + const Offset(-100, 100)), isNull);
  });

  test('what each tool says, for search and the PDF text layer', () {
    expect(mathToolText(_sample), 'Number line −2.5 [1, π)');
    expect(mathToolText(const UnitCircleData()), 'Unit circle θ = 90° = π/2 cos θ = 0 sin θ = 1 tan θ = undefined');
    expect(mathToolText(const PolarData(curves: [GraphLine(r'r=1+\cos\theta', _blue)])), 'Polar grid r = 1 + cos θ');
  });
}
