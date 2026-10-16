import 'package:endless/math/latex.dart';
import 'package:endless/math/linear.dart';
import 'package:flutter_math_fork/tex.dart';
import 'package:flutter_test/flutter_test.dart';

/// The same math, however it's spaced or braced.
String same(String latex) => TexParser(latex, const TexParserSettings()).parse().encodeTeX();

void main() {
  group('the keyboard\'s text to LaTeX', () {
    const cases = {
      // Math.png
      'ω = Δθ / Δt': r'\omega=\frac{\Delta\theta}{\Delta t}',
      'v = √(v₀² + 2gh)': r'v=\sqrt{v_{0}^{2}+2gh}',
      'F = dp / dt': r'F=\frac{dp}{dt}',
      'KE = 1/2 mv²': r'KE=\frac{1}{2}mv^{2}',
      'J = ∫_(t₀)^(t₁) F dt = Δp': r'J=\int_{t_{0}}^{t_{1}}Fdt=\Delta p',
      'Σ p_(before) = Σ p_(after)': r'\Sigma p_{before}=\Sigma p_{after}',
      // MathKit.png's formulas
      'x = (−b ± √(b² − 4ac)) / 2a': r'x=\frac{-b\pm\sqrt{b^{2}-4ac}}{2a}',
      'm = (y₂ − y₁) / (x₂ − x₁)': r'm=\frac{y_{2}-y_{1}}{x_{2}-x_{1}}',
      'd/dx xⁿ = n·xⁿ⁻¹': r'\frac{d}{dx}x^{n}=n\cdot x^{n-1}',
      'sin²θ + cos²θ = 1': r'\sin^{2}\theta+\cos^{2}\theta=1',
      'log(ab) = log a + log b': r'\log(ab)=\log a+\log b',
      // Scripts, roots, limits, units, matrices, accents and raw LaTeX.
      'x^2 + x^(n+1) + x_i': r'x^{2}+x^{n+1}+x_{i}',
      'ⁿ√(x) + ∛8': r'\sqrt[n]{x}+\sqrt[3]{8}',
      'lim_(x→0) (sin x)/x': r'\lim\limits_{x\rightarrow 0}\frac{\sin x}{x}',
      'g = 9.8 "m/s²"': r'g=9.8\,\mathrm{m/s^{2}}',
      '[[a, b], [c, d]]': r'\begin{bmatrix}a&b\\c&d\end{bmatrix}',
      'x̄ + v⃗': r'\bar{x}+\vec{v}',
      r'\overline{AB} = 3': r'\overline{AB}=3',
      'sinx': r'\sin x',
      '90°': r'90^{\circ}',
    };
    for (final MapEntry(key: linear, value: latex) in cases.entries) {
      test(linear, () {
        final out = linearToLatex(linear);
        expect(isDrawable(out), isTrue, reason: out);
        expect(same(out), same(latex), reason: out);
      });
    }
  });

  group('LaTeX to the keyboard\'s text', () {
    const cases = {
      r'\omega=\frac{\Delta\theta}{\Delta t}': 'ω = Δθ / Δt',
      // As the recognizer writes it.
      r'\frac { 1 } { 2 } m v ^ { 2 }': '1 / 2 mv²',
      r'\sqrt { v _ { 0 } ^ { 2 } + 2 g h }': '√(v₀² + 2gh)',
      r'\frac { a + b } { 2 }': '(a + b) / 2',
      r'\lim _ { x \rightarrow 0 } \frac { \sin x } { x }': 'lim_(x → 0) (sin x) / x',
      r'\sin x': 'sin x',
      r'\begin{bmatrix}a&b\\c&d\end{bmatrix}': '[[a, b], [c, d]]',
      r'x ^ { 2 } + 1 = 0': 'x² + 1 = 0',
    };
    for (final MapEntry(key: latex, value: linear) in cases.entries) {
      test(latex, () => expect(latexToLinear(latex), linear));
    }
  });

  test('editing math keeps it the same math', () {
    // Recognizer-style LaTeX, through the keyboard's text and back.
    const corpus = [
      r'\frac { 1 } { \sqrt { k + 1 } }',
      r'\frac { 9 } { 9 + \sqrt { 9 } }',
      r'h ( s ) = \frac { 1 } { 1 + s T }',
      r'\sum _ { i = 1 } ^ { n } i ^ { 2 }',
      r'\int _ { 0 } ^ { 1 } x d x',
      r'\lim \limits _ { x \rightarrow \infty } \frac { 1 } { x } = 0',
      r'a b ^ { 2 } + a ( b - c ) - b c ^ { 2 }',
      r'\sqrt [ 3 ] { 2 7 } = 3',
      r'y = \frac { x ^ { 2 } } { 2 }',
      r'\alpha + \beta \geq \gamma \times \pi',
      r'\cos ( 2 \theta ) = \cos ^ { 2 } \theta - \sin ^ { 2 } \theta',
      r'x _ { 1 } , x _ { 2 } , \ldots , x _ { n }',
      r'f ^ { \prime } ( x ) = 2 x',
      r'\frac { d y } { d x } = \frac { 1 } { 2 } x',
      r'\{ a , b \} \in X',
      r'| x | \leq 1',
      r'\Delta x \neq 0',
      r'\forall x \exists y',
      r'\log _ { 2 } 8 = 3',
      r'9.8\,\mathrm{m/s^{2}}',
    ];
    for (final latex in corpus) {
      final linear = latexToLinear(latex);
      final back = linearToLatex(linear);
      expect(isDrawable(back), isTrue, reason: '$latex → $linear → $back');
      expect(same(back), same(latex), reason: '$latex → $linear → $back');
    }
  });
}
