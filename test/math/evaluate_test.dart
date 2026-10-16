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
}
