// The keys of the math keyboard: Math.dc.html's `sets`, then MathKit.dc.html's
// Symbols keypad and formula library (its `K` and `F`), as tabs of the one
// keyboard. What a key types is the keyboard's text (lib/math/linear.dart).

/// A key: its label, what it types and where the cursor ends up in that
/// (null: after it), and its name for screen readers.
class MathKey {
  const MathKey(this.label, this.types, {this.cursor, String? name}) : name = name ?? label;

  final String label;
  final String types;
  final int? cursor;
  final String name;
}

/// A tab of the keyboard: keys, or formulas.
class MathKeyTab {
  const MathKeyTab(this.label, this.keys, {this.formulas = const []});

  final String label;
  final List<MathKey> keys;
  final List<Formula> formulas;
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
  const MathKeyTab('Symbols', symbolKeys),
  const MathKeyTab('Math', [], formulas: mathFormulas),
  const MathKeyTab('Physics', [], formulas: physicsFormulas),
];

/// Where Formulas & tools opens the keyboard.
const symbolsTab = 4;

/// The Symbols tab: MathKit.png's Symbols keypad.
const symbolKeys = <MathKey>[
  MathKey('π', 'π', name: 'pi'),
  MathKey('e', 'e', name: 'Euler’s number'),
  MathKey('φ', 'φ', name: 'phi'),
  MathKey('τ', 'τ', name: 'tau'),
  MathKey('∞', '∞', name: 'infinity'),
  MathKey('√', '√()', cursor: 2, name: 'square root'),
  MathKey('∫', '∫ ', name: 'integral'),
  MathKey('∬', '∬ ', name: 'double integral'),
  MathKey('∭', '∭ ', name: 'triple integral'),
  MathKey('∮', '∮ ', name: 'contour integral'),
  MathKey('d/dx', 'd/dx ', name: 'derivative'),
  MathKey('d²/dx²', 'd²/dx² ', name: 'second derivative'),
  MathKey('∂/∂x', '∂/∂x ', name: 'partial derivative'),
  MathKey('∇', '∇', name: 'nabla'),
  MathKey('Σ', '∑ ', name: 'sum'),
  MathKey('Π', '∏ ', name: 'product'),
  MathKey('±', ' ± ', name: 'plus or minus'),
  MathKey('×', ' × ', name: 'times'),
  MathKey('÷', ' ÷ ', name: 'divide'),
  MathKey('≈', ' ≈ ', name: 'approximately equal'),
  MathKey('≠', ' ≠ ', name: 'not equal'),
  MathKey('≤', ' ≤ ', name: 'less than or equal'),
  MathKey('≥', ' ≥ ', name: 'greater than or equal'),
  MathKey('∝', ' ∝ ', name: 'proportional to'),
  MathKey('α', 'α', name: 'alpha'),
  MathKey('β', 'β', name: 'beta'),
  MathKey('γ', 'γ', name: 'gamma'),
  MathKey('δ', 'δ', name: 'delta'),
  MathKey('ε', 'ε', name: 'epsilon'),
  MathKey('θ', 'θ', name: 'theta'),
  MathKey('λ', 'λ', name: 'lambda'),
  MathKey('μ', 'μ', name: 'mu'),
  MathKey('σ', 'σ', name: 'sigma'),
  MathKey('ω', 'ω', name: 'omega'),
  MathKey('Δ', 'Δ', name: 'capital delta'),
  MathKey('Ω', 'Ω', name: 'capital omega'),
  MathKey('∈', ' ∈ ', name: 'element of'),
  MathKey('∉', ' ∉ ', name: 'not an element of'),
  MathKey('⊂', ' ⊂ ', name: 'subset of'),
  MathKey('∪', ' ∪ ', name: 'union'),
  MathKey('∩', ' ∩ ', name: 'intersection'),
  MathKey('∀', '∀', name: 'for all'),
  MathKey('∃', '∃', name: 'there exists'),
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

/// How a formula is shown on its key: ½ for 1/2.
String formulaLabel(String text) => text.replaceAll('1/2 ', '½');
