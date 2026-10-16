// The keys of the math keyboard (Math.dc.html's `sets`) and of the
// Symbols keypad and formula library (MathKit.dc.html's `K` and `F`). What
// a key types is the keyboard's text (lib/math/linear.dart).

/// A key: its label, what it types and where the cursor ends up in that
/// (null: after it), and its name for screen readers.
class MathKey {
  const MathKey(this.label, this.types, {this.cursor, String? name}) : name = name ?? label;

  final String label;
  final String types;
  final int? cursor;
  final String name;
}

class MathKeyTab {
  const MathKeyTab(this.label, this.keys);

  final String label;
  final List<MathKey> keys;
}

MathKey _plain(String s) => MathKey(s, s);

/// Operators get spaces around them, as Math.dc.html's keys type them.
MathKey _op(String s) => MathKey(s, ' $s ');

/// Units are typed as upright text.
MathKey _unit(String s) => MathKey(s, ' "$s"', name: s);

final mathKeyTabs = <MathKeyTab>[
  MathKeyTab('Greek  α β γ', [
    for (final g in 'α β γ δ ε ζ η θ ι κ λ μ ν ξ π ρ σ τ υ φ χ ψ ω ϕ Γ Δ Θ Λ Ξ Π Σ Φ Ψ Ω ∂ ∇'.split(' ')) _plain(g),
  ]),
  MathKeyTab('Operators  ± ≤ →', [
    for (final o in '+ − × ÷ ± ∓ = ≠ ≈ ≡ < > ≤ ≥ ∝ → ⇒ ⇔ ∈ ∉ ⊂ ∪ ∩'.split(' ')) _op(o),
    for (final o in '∀ ∃ ∞ · ° ′ ∠ ⊥ ∥ ! % ( )'.split(' '))
      o == '·' || o == '⊥' || o == '∥' ? _op(o) : _plain(o),
  ]),
  const MathKeyTab('Structures  √ ∫ ∑', [
    MathKey('a⁄b', ' / ', name: 'Fraction'),
    MathKey('xⁿ', '^', name: 'Power'),
    MathKey('xₙ', '_', name: 'Subscript'),
    MathKey('√x', '√()', cursor: 2, name: 'Square root'),
    MathKey('ⁿ√x', 'ⁿ√()', cursor: 3, name: 'Root'),
    MathKey('∫', '∫ ', name: 'Integral'),
    MathKey('∫ₐᵇ', '∫_()^() ', cursor: 3, name: 'Definite integral'),
    MathKey('∑', '∑_()^() ', cursor: 3, name: 'Sum'),
    MathKey('∏', '∏_()^() ', cursor: 3, name: 'Product'),
    MathKey('lim', 'lim_(→) ', cursor: 5, name: 'Limit'),
    MathKey('d⁄dx', 'd/dx ', name: 'Derivative'),
    MathKey('|x|', '||', cursor: 1, name: 'Absolute value'),
    MathKey('sin', 'sin '),
    MathKey('cos', 'cos '),
    MathKey('tan', 'tan '),
    MathKey('log', 'log '),
    MathKey('ln', 'ln '),
    MathKey('eˣ', 'e^()', cursor: 3, name: 'Exponential'),
    MathKey('x̄', '̄', name: 'Bar over'),
    MathKey('v⃗', '⃗', name: 'Vector arrow'),
    MathKey('[ ]', '[]', cursor: 1, name: 'Square brackets'),
    MathKey('( )', '()', cursor: 1, name: 'Brackets'),
    MathKey('matrix', '[[ , ], [ , ]]', cursor: 2, name: 'Matrix'),
    MathKey('n!', '!', name: 'Factorial'),
  ]),
  MathKeyTab('Units', [
    for (final u in 'm s kg N J W Pa Hz m/s m/s² kg·m/s °C K mol A V Ω eV cm mm km g mg L mL h min ms μs nm μm'.split(' '))
      _unit(u),
  ]),
];

/// A Symbols key (MathKit.png): what it shows, its name, what it types in
/// the keyboard, and the math it adds to the page.
class SymbolKey {
  const SymbolKey(this.label, this.name, this.types, this.latex, {this.cursor});

  final String label;
  final String name;
  final String types;
  final int? cursor;
  final String latex;
}

const symbolKeys = <SymbolKey>[
  SymbolKey('π', 'pi', 'π', r'\pi'),
  SymbolKey('e', 'Euler’s number', 'e', 'e'),
  SymbolKey('φ', 'phi', 'φ', r'\varphi'),
  SymbolKey('τ', 'tau', 'τ', r'\tau'),
  SymbolKey('∞', 'infinity', '∞', r'\infty'),
  SymbolKey('√', 'square root', '√()', r'\surd', cursor: 2),
  SymbolKey('∫', 'integral', '∫ ', r'\int'),
  SymbolKey('∬', 'double integral', '∬ ', r'\iint'),
  SymbolKey('∭', 'triple integral', '∭ ', r'\iiint'),
  SymbolKey('∮', 'contour integral', '∮ ', r'\oint'),
  SymbolKey('d/dx', 'derivative', 'd/dx ', r'\frac{d}{dx}'),
  SymbolKey('d²/dx²', 'second derivative', 'd²/dx² ', r'\frac{d^{2}}{dx^{2}}'),
  SymbolKey('∂/∂x', 'partial derivative', '∂/∂x ', r'\frac{\partial}{\partial x}'),
  SymbolKey('∇', 'nabla', '∇', r'\nabla'),
  SymbolKey('Σ', 'sum', '∑ ', r'\sum'),
  SymbolKey('Π', 'product', '∏ ', r'\prod'),
  SymbolKey('±', 'plus or minus', ' ± ', r'\pm'),
  SymbolKey('×', 'times', ' × ', r'\times'),
  SymbolKey('÷', 'divide', ' ÷ ', r'\div'),
  SymbolKey('≈', 'approximately equal', ' ≈ ', r'\approx'),
  SymbolKey('≠', 'not equal', ' ≠ ', r'\neq'),
  SymbolKey('≤', 'less than or equal', ' ≤ ', r'\leq'),
  SymbolKey('≥', 'greater than or equal', ' ≥ ', r'\geq'),
  SymbolKey('∝', 'proportional to', ' ∝ ', r'\propto'),
  SymbolKey('α', 'alpha', 'α', r'\alpha'),
  SymbolKey('β', 'beta', 'β', r'\beta'),
  SymbolKey('γ', 'gamma', 'γ', r'\gamma'),
  SymbolKey('δ', 'delta', 'δ', r'\delta'),
  SymbolKey('ε', 'epsilon', 'ε', r'\varepsilon'),
  SymbolKey('θ', 'theta', 'θ', r'\theta'),
  SymbolKey('λ', 'lambda', 'λ', r'\lambda'),
  SymbolKey('μ', 'mu', 'μ', r'\mu'),
  SymbolKey('σ', 'sigma', 'σ', r'\sigma'),
  SymbolKey('ω', 'omega', 'ω', r'\omega'),
  SymbolKey('Δ', 'capital delta', 'Δ', r'\Delta'),
  SymbolKey('Ω', 'capital omega', 'Ω', r'\Omega'),
  SymbolKey('∈', 'element of', ' ∈ ', r'\in'),
  SymbolKey('∉', 'not an element of', ' ∉ ', r'\notin'),
  SymbolKey('⊂', 'subset of', ' ⊂ ', r'\subset'),
  SymbolKey('∪', 'union', ' ∪ ', r'\cup'),
  SymbolKey('∩', 'intersection', ' ∩ ', r'\cap'),
  SymbolKey('∀', 'for all', '∀', r'\forall'),
  SymbolKey('∃', 'there exists', '∃', r'\exists'),
];

/// A formula in the library: its name and the keyboard's text for it.
class Formula {
  const Formula(this.name, this.text);

  final String name;
  final String text;
}

const mathFormulas = <Formula>[
  Formula('Quadratic formula', 'x = (−b ± √(b² − 4ac)) / 2a'),
  Formula('Pythagorean theorem', 'a² + b² = c²'),
  Formula('Area of a circle', 'A = πr²'),
  Formula('Slope', 'm = (y₂ − y₁) / (x₂ − x₁)'),
  Formula('Power rule', 'd/dx xⁿ = n·xⁿ⁻¹'),
  Formula('Integral of xⁿ', '∫ xⁿ dx = xⁿ⁺¹ / (n + 1) + C'),
  Formula('Log of a product', 'log(ab) = log a + log b'),
  Formula('Pythagorean identity', 'sin²θ + cos²θ = 1'),
];

const physicsFormulas = <Formula>[
  Formula('Velocity', 'v = v₀ + at'),
  Formula('Position', 'x = x₀ + v₀t + 1/2 at²'),
  Formula('Newton’s 2nd law', 'F = ma'),
  Formula('Momentum', 'p = mv'),
  Formula('Kinetic energy', 'KE = 1/2 mv²'),
  Formula('Potential energy', 'PE = mgh'),
  Formula('Work', 'W = Fd cos θ'),
  Formula('Ohm’s law', 'V = IR'),
];
