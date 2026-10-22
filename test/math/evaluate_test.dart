import 'dart:math' as math;

import 'package:endless/math/evaluate.dart';
import 'package:endless/math/linear.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('functions of x are graphable, written the ways the recognizer and keyboard write them', () {
    final cases = <String, double Function(double)>{
      r'y=\frac{x^{2}}{2}': (x) => x * x / 2, // Graph.png
      r'y = 2 \sin x': (x) => 2 * math.sin(x),
      r'y=x+1': (x) => x + 1,
      r'f ( x ) = x ^ { 3 } - 2 x': (x) => x * x * x - 2 * x,
      r'\sqrt{x+1}': (x) => math.sqrt(x + 1),
      r'y=|x|': (x) => x.abs(),
      r'y=e^{-x}': (x) => math.exp(-x),
      r'y=\ln x': math.log,
      r'y=\sin^{2}x+\cos^{2}x': (x) => 1,
      r'y=(x+1)(x-1)': (x) => (x + 1) * (x - 1),
      r'y=\frac{1}{x}': (x) => 1 / x,
      r'y=3\cdot x\div 2': (x) => 3 * x / 2,
      r'y=\sqrt[3]{x}': (x) => x < 0 ? -math.pow(-x, 1 / 3).toDouble() : math.pow(x, 1 / 3).toDouble(),
      r'2x=y': (x) => 2 * x,
      linearToLatex('y = x²/2'): (x) => x * x / 2,
      linearToLatex('y = 2 sin x'): (x) => 2 * math.sin(x),
    };
    for (final MapEntry(key: latex, value: want) in cases.entries) {
      final f = graphable(latex);
      expect(f, isNotNull, reason: latex);
      for (final x in [-2.5, -0.7, 0.3, 1.9]) {
        final got = f!(x), expected = want(x);
        if (expected.isNaN) {
          expect(got.isNaN, isTrue, reason: '$latex at $x');
        } else {
          expect(got, closeTo(expected, 1e-9), reason: '$latex at $x');
        }
      }
    }
  });

  test('anything else is not', () {
    for (final latex in [r'E=mc^{2}', r'a^{2}+b^{2}=c^{2}', '3+4', r'\int x dx', 'y=', r'x=\frac{1}{2}', '']) {
      expect(graphable(latex), isNull, reason: latex);
    }
  });

  test('the view shows x from −5 to 5 and where the curve is', () {
    final v = graphView([graphable(r'y=\frac{x^{2}}{2}')!]);
    expect((v.xMin, v.xMax), (-5.0, 5.0));
    expect(v.yMin, lessThanOrEqualTo(0));
    expect(v.yMax, greaterThan(10));
    final flat = graphView([graphable('y=x+1-x')!]);
    expect(flat.yMax - flat.yMin, greaterThan(1));
  });

  test('a function’s argument takes the number before its letter: sin 2x, cos 3θ', () {
    expect(graphable(r'y=2\sin 2x')!(0.4), closeTo(2 * math.sin(0.8), 1e-12));
    expect(graphable(r'y=\sin x\cdot 2')!(0.4), closeTo(2 * math.sin(0.4), 1e-12));
  });

  test('surfaces over x and y, as the 3D graph reads them', () {
    final saddle = surfaceOf(linearToLatex('z = (x² − y²) / 4'))!; // Graph.png's 3D
    expect(saddle(1, 2), closeTo(-0.75, 1e-12));
    expect(surfaceOf(r'z=xy')!(2, 3), 6);
    expect(surfaceOf(r'f(x,y)=x^{2}+y^{2}')!(1, 2), 5);
    expect(surfaceOf(r'\sin x+\cos y')!(0, 0), 1);
    expect(surfaceOf(r'z=2')!(5, -5), 2, reason: 'a plane');
    for (final no in [r'x+y=3', '3', r'z=w', '', r'E=mc^{2}']) {
      expect(surfaceOf(no), isNull, reason: no);
    }
  });

  test('polar curves r = f(θ)', () {
    final cardioid = polarOf(linearToLatex('r = 1 + cos θ'))!;
    expect(cardioid(0), 2);
    expect(cardioid(math.pi), closeTo(0, 1e-12));
    // MathKit.png's rose: 2 cos 3θ, not (2 cos 3)·θ.
    expect(polarOf(linearToLatex('r = 2 cos 3θ'))!(math.pi / 9), closeTo(1, 1e-12));
    expect(polarOf(r'r=2')!(1.3), 2, reason: 'a circle');
    expect(polarOf(r'\theta')!(2), 2);
    for (final no in ['2', r'y=x', r'r=x', '']) {
      expect(polarOf(no), isNull, reason: no);
    }
  });

  test('numbers for the number line: irrational ones too', () {
    expect(constantOf(r'\sqrt{2}'), closeTo(math.sqrt2, 1e-12));
    expect(constantOf(r'\pi'), math.pi);
    expect(constantOf('-2.5'), -2.5);
    expect(constantOf(r'\frac{1}{2}'), 0.5);
    expect(constantOf(r'-\frac{\sqrt{3}}{2}'), closeTo(-math.sqrt(3) / 2, 1e-12));
    expect(constantOf('e'), math.e);
    expect(constantOf(r'\infty'), double.infinity);
    expect(constantOf(r'-\infty'), double.negativeInfinity);
    for (final no in ['x', '', r'\frac{1}{0}', '1+']) {
      expect(constantOf(no), isNull, reason: no);
    }
  });

  test('3D points', () {
    expect(point3dOf('(1,2,3)'), [1, 2, 3]);
    expect(point3dOf(r'\left(-1,\frac{1}{2},\pi\right)'), [-1, 0.5, math.pi]);
    for (final no in ['(1,2)', '(1,2,3,4)', '(x,1,2)', '1,2,3']) {
      expect(point3dOf(no), isNull, reason: no);
    }
  });

  test('where curves cross: Graph.png’s x = 0 and x ≈ 1.93, and no crossing at an asymptote', () {
    final half = graphable(r'y=\frac{x^{2}}{2}')!, sine = graphable(r'y=2\sin x')!;
    final xs = crossingsOf(half, sine, -5, 5, maxJump: 18);
    expect(xs, hasLength(2));
    expect(xs[0], closeTo(0, 1e-9));
    expect(xs[1], closeTo(1.9338, 1e-3));
    // y = x² / 2 meets y = x + 1 at 1 ± √3.
    final line = graphable('y=x+1')!;
    final ys = crossingsOf(half, line, -5, 5);
    expect(ys[0], closeTo(1 - math.sqrt(3), 1e-9));
    expect(ys[1], closeTo(1 + math.sqrt(3), 1e-9));
    // 1/x changes sign at 0 by jumping, not by crossing 0.
    expect(zerosOf(graphable(r'y=\frac{1}{x}')!.f, -5, 5, maxJump: 18), isEmpty);
    expect(zerosOf(graphable(r'y=\tan x')!.f, -3, 3, maxJump: 18), [closeTo(0, 1e-9)]);
  });
}
