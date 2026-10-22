import 'dart:math' as math;

import 'latex.dart' show latexSymbols;

// Math to evaluate, read from LaTeX: functions of x for 2D graphs ("Graph
// it"), surfaces z = f(x, y) and 3D points for 3D graphs, polar curves
// r = f(θ) for the polar grid, and plain numbers (√2, π, −2.5) and
// intervals ([1, π)) for the number line. `y = x^{2}/2`, `f(x) = 2\sin x`,
// `\frac{1}{x}`, `\sqrt{x+1}`, `|x|`, `e^{-x}`, `\ln x`; implicit
// multiplication (`2x`, `3\sin x`, `xy`) included.

/// A function of x read from LaTeX.
class GraphFunction {
  const GraphFunction(this.f);

  final double Function(double x) f;

  double call(double x) => f(x);
}

/// A surface z = f(x, y) read from LaTeX.
class SurfaceFunction {
  const SurfaceFunction(this.f);

  final double Function(double x, double y) f;

  double call(double x, double y) => f(x, y);
}

/// A polar curve r = f(θ) read from LaTeX.
class PolarFunction {
  const PolarFunction(this.f);

  final double Function(double theta) f;

  double call(double theta) => f(theta);
}

/// [latex] as a function of x, or null when it isn't one: other letters
/// than x (`y` and `f(x)` only on the left of `=`), or nothing to plot.
GraphFunction? graphable(String latex) {
  final rhs = _rightSide(latex, names: const {'y', 'f(x)', 'g(x)', 'h(x)', 'y(x)'}, swapped: 'y');
  if (rhs == null) return null;
  final v = _Vars();
  final e = _parse(rhs, v, const {'x'});
  if (e == null || !e.used.contains('x')) return null;
  final f = e.fn;
  return GraphFunction((x) {
    v.x = x;
    return f();
  });
}

/// [latex] as a surface over x and y: `z = …`, `f(x, y) = …` or just the
/// expression (which must use x or y).
SurfaceFunction? surfaceOf(String latex) {
  final named = latexSymbols(latex).contains('=');
  final rhs = _rightSide(latex, names: const {'z', 'f(x,y)', 'z(x,y)'}, swapped: 'z');
  if (rhs == null) return null;
  final v = _Vars();
  final e = _parse(rhs, v, const {'x', 'y'});
  // A bare constant isn't a surface; z = 2 (a plane) is.
  if (e == null || (!named && e.used.isEmpty)) return null;
  final f = e.fn;
  return SurfaceFunction((x, y) {
    v
      ..x = x
      ..y = y;
    return f();
  });
}

/// [latex] as a polar curve: `r = …`, `r(\theta) = …` or just the
/// expression in θ.
PolarFunction? polarOf(String latex) {
  final named = latexSymbols(latex).contains('=');
  final rhs = _rightSide(latex, names: const {'r', r'r(\theta)'}, swapped: 'r');
  if (rhs == null) return null;
  final v = _Vars();
  final e = _parse(rhs, v, const {r'\theta'});
  // r = 2 is a circle; a bare 2 isn't a curve.
  if (e == null || (!named && !e.used.contains(r'\theta'))) return null;
  final f = e.fn;
  return PolarFunction((t) {
    v.t = t;
    return f();
  });
}

/// The number [latex] is (`\sqrt{2}`, `\pi`, `-2.5`, `\frac{1}{2}`), or
/// null when it isn't one. `\infty` is infinity.
double? constantOf(String latex) {
  final toks = _tokens(latex);
  if (toks.isEmpty) return null;
  if (toks.join() == r'\infty' || toks.join() == r'+\infty') return double.infinity;
  if (toks.join() == r'-\infty') return double.negativeInfinity;
  final e = _parse(toks, _Vars(), const {});
  if (e == null) return null;
  final v = e.fn();
  return v.isFinite ? v : null;
}

/// A point in 3D, `(1, 2, 3)`, or null.
List<double>? point3dOf(String latex) {
  final toks = _tokens(latex);
  if (toks.length < 7 || toks.first != '(' || toks.last != ')') return null;
  final parts = _split(toks.sublist(1, toks.length - 1), ',');
  if (parts.length != 3) return null;
  final out = <double>[];
  for (final p in parts) {
    final e = _parse(p, _Vars(), const {});
    final v = e?.fn();
    if (v == null || !v.isFinite) return null;
    out.add(v);
  }
  return out;
}

/// Where [d] (the difference of two curves) is zero between [a] and [b]:
/// sign changes found in [samples] steps, then narrowed down. A change
/// across a jump bigger than [maxJump] is an asymptote, not a crossing.
List<double> zerosOf(double Function(double x) d, double a, double b, {int samples = 400, double maxJump = double.infinity}) {
  final out = <double>[];
  var x0 = a, y0 = d(a);
  for (var k = 1; k <= samples; k++) {
    final x1 = a + (b - a) * k / samples, y1 = d(x1);
    if (y0.isFinite && y1.isFinite) {
      if (y0 == 0) {
        if (out.isEmpty || (x0 - out.last).abs() > (b - a) / samples) out.add(x0);
      } else if (y0.sign != y1.sign && y1 != 0 && (y1 - y0).abs() <= maxJump) {
        var lo = x0, hi = x1, flo = y0;
        for (var i = 0; i < 60; i++) {
          final mid = (lo + hi) / 2, fm = d(mid);
          if (!fm.isFinite) break;
          if (fm.sign == flo.sign) {
            lo = mid;
            flo = fm;
          } else {
            hi = mid;
          }
        }
        final x = (lo + hi) / 2;
        // Close to zero there, not a jump that only changes sign.
        if (d(x).abs() < 1e-6 * math.max(1, y0.abs() + y1.abs())) out.add(x);
      }
    }
    x0 = x1;
    y0 = y1;
  }
  return out;
}

/// Where [f] and [g] cross between [a] and [b].
List<double> crossingsOf(GraphFunction f, GraphFunction g, double a, double b, {double maxJump = double.infinity}) =>
    zerosOf((x) => f(x) - g(x), a, b, maxJump: maxJump);

/// Where to look at [f]: x from -5 to 5, and the y range most of the curve
/// is in (with 0 when it's near).
({double xMin, double xMax, double yMin, double yMax}) graphView(List<GraphFunction> fs) {
  const xMin = -5.0, xMax = 5.0;
  final ys = <double>[];
  for (final f in fs) {
    for (var k = 0; k <= 200; k++) {
      final y = f(xMin + (xMax - xMin) * k / 200);
      if (y.isFinite) ys.add(y);
    }
  }
  if (ys.isEmpty) return (xMin: xMin, xMax: xMax, yMin: -5, yMax: 5);
  ys.sort();
  var lo = ys[(ys.length * 0.05).floor()], hi = ys[math.min(ys.length - 1, (ys.length * 0.95).ceil())];
  if (lo > 0 && lo < (hi - lo)) lo = 0;
  if (hi < 0 && -hi < (hi - lo)) hi = 0;
  if (hi - lo < 1e-6) {
    lo -= 1;
    hi += 1;
  }
  final pad = (hi - lo) * 0.12;
  return (xMin: xMin, xMax: xMax, yMin: lo - pad, yMax: hi + pad);
}

// Reading.

List<String> _tokens(String latex) => latexSymbols(latex)
    .where((t) => t != r'\left' && t != r'\right' && t != r'\,' && t != r'\limits' && t != r'\;' && t != r'\!')
    .toList();

/// The side of an equation to evaluate: the right of `name = …`, the left
/// of `… = swapped`, or the whole of an expression with no `=`.
List<String>? _rightSide(String latex, {required Set<String> names, required String swapped}) {
  final toks = _tokens(latex);
  if (toks.isEmpty) return null;
  final eq = toks.indexOf('=');
  if (eq < 0) return toks;
  if (toks.lastIndexOf('=') != eq) return null;
  final lhs = toks.sublist(0, eq).join();
  final right = toks.sublist(eq + 1);
  if (names.contains(lhs)) return right;
  if (right.join() == swapped) return toks.sublist(0, eq);
  return null;
}

/// [toks] split at top-level [sep]s.
List<List<String>> _split(List<String> toks, String sep) {
  final out = <List<String>>[[]];
  var depth = 0;
  for (final t in toks) {
    if (t == '(' || t == '{' || t == '[') depth++;
    if (t == ')' || t == '}' || t == ']') depth--;
    if (t == sep && depth == 0) {
      out.add([]);
    } else {
      out.last.add(t);
    }
  }
  return out;
}

class _Vars {
  double x = 0, y = 0, t = 0;
}

typedef _Fn = double Function();

({_Fn fn, Set<String> used})? _parse(List<String> toks, _Vars v, Set<String> vars) {
  if (toks.isEmpty) return null;
  try {
    final p = _Parser(toks, v, vars);
    final e = p.expr();
    if (p.i != toks.length) return null;
    return (fn: e, used: p.used);
  } on FormatException {
    return null;
  }
}

const _functions = <String, double Function(double)>{
  r'\sin': math.sin,
  r'\cos': math.cos,
  r'\tan': math.tan,
  r'\sec': _sec,
  r'\csc': _csc,
  r'\cot': _cot,
  r'\arcsin': math.asin,
  r'\arccos': math.acos,
  r'\arctan': math.atan,
  r'\sinh': _sinh,
  r'\cosh': _cosh,
  r'\tanh': _tanh,
  r'\ln': math.log,
  r'\log': _log10,
  r'\exp': math.exp,
};

double _sec(double x) => 1 / math.cos(x);
double _csc(double x) => 1 / math.sin(x);
double _cot(double x) => 1 / math.tan(x);
double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;
double _cosh(double x) => (math.exp(x) + math.exp(-x)) / 2;
double _tanh(double x) => _sinh(x) / _cosh(x);
double _log10(double x) => math.log(x) / math.ln10;

class _Parser {
  _Parser(this.t, this.v, this.vars);

  final List<String> t;
  final _Vars v;

  /// The variables allowed (`x`, `y`, `\theta`), and those used.
  final Set<String> vars;
  final used = <String>{};
  var i = 0;

  /// Inside |…|, where a | closes rather than opens.
  var _abs = 0;

  String? get peek => i < t.length ? t[i] : null;

  Never _fail() => throw const FormatException();

  void _expect(String s) {
    if (peek != s) _fail();
    i++;
  }

  _Fn expr() {
    var left = term();
    while (peek == '+' || peek == '-') {
      final op = t[i++];
      final a = left, b = term();
      left = op == '+' ? () => a() + b() : () => a() - b();
    }
    return left;
  }

  bool get _startsFactor {
    final p = peek;
    if (p == null) return false;
    return p == '(' || p == '{' || p == '[' || (p == '|' && _abs == 0) || vars.contains(p) || p == 'e' ||
        RegExp(r'^[0-9.]$').hasMatch(p) || const {r'\pi', r'\frac', r'\dfrac', r'\sqrt'}.contains(p) ||
        _functions.containsKey(p);
  }

  _Fn term() {
    var left = unary();
    while (true) {
      final p = peek;
      if (p == r'\cdot' || p == r'\times' || p == '*') {
        i++;
        final a = left, b = unary();
        left = () => a() * b();
      } else if (p == '/' || p == r'\div') {
        i++;
        final a = left, b = unary();
        left = () => a() / b();
      } else if (_startsFactor) {
        // 2x, 3\sin x, (x+1)(x-1), xy
        final a = left, b = power();
        left = () => a() * b();
      } else {
        return left;
      }
    }
  }

  _Fn unary() {
    if (peek == '-') {
      i++;
      final a = unary();
      return () => -a();
    }
    if (peek == '+') {
      i++;
      return unary();
    }
    return power();
  }

  _Fn power() {
    final base = atom();
    if (peek == '^') {
      i++;
      final exp = _script();
      return () => math.pow(base(), exp()).toDouble();
    }
    return base;
  }

  /// A script: {…} or one symbol.
  _Fn _script() {
    if (peek == '{') return _group();
    return atom();
  }

  _Fn _group() {
    _expect('{');
    final e = expr();
    _expect('}');
    return e;
  }

  _Fn atom() {
    final p = peek;
    if (p == null) _fail();
    if (RegExp(r'^[0-9.]$').hasMatch(p)) {
      final b = StringBuffer();
      while (peek != null && RegExp(r'^[0-9.]$').hasMatch(peek!)) {
        b.write(t[i++]);
      }
      final n = double.tryParse(b.toString()) ?? _fail();
      return () => n;
    }
    i++;
    if (vars.contains(p)) {
      used.add(p);
      return switch (p) {
        'x' => () => v.x,
        'y' => () => v.y,
        _ => () => v.t,
      };
    }
    switch (p) {
      case 'e':
        return () => math.e;
      case r'\pi':
        return () => math.pi;
      case '(' || '[':
        final e = expr();
        _expect(p == '(' ? ')' : ']');
        return e;
      case '{':
        final e = expr();
        _expect('}');
        return e;
      case '|':
        _abs++;
        final e = expr();
        _abs--;
        _expect('|');
        return () => e().abs();
      case r'\frac' || r'\dfrac':
        final a = _group(), b = _group();
        return () => a() / b();
      case r'\sqrt':
        _Fn? n;
        if (peek == '[') {
          i++;
          n = expr();
          _expect(']');
        }
        final a = _group();
        final root = n;
        return root == null ? () => math.sqrt(a()) : () => _nthRoot(a(), root());
    }
    if (_functions[p] case final f?) {
      // \sin^{2} x is (\sin x)^2.
      _Fn? exp;
      if (peek == '^') {
        i++;
        exp = _script();
      }
      final arg = peek == '(' ? atom() : _argument();
      final e = exp;
      return e == null ? () => f(arg()) : () => math.pow(f(arg()), e()).toDouble();
    }
    _fail();
  }

  /// A function's argument without brackets: `\sin x`, `\cos 3\theta`,
  /// `\sin 2x` (a number and what it multiplies).
  _Fn _argument() {
    var a = power();
    while (peek != null && (vars.contains(peek) || peek == r'\pi') && i > 0 && RegExp(r'^[0-9.]$').hasMatch(t[i - 1])) {
      final left = a, right = power();
      a = () => left() * right();
    }
    return a;
  }
}

double _nthRoot(double v, double n) {
  // Odd roots of negative numbers are real.
  if (v < 0 && n.round() == n && n.round().isOdd) return -math.pow(-v, 1 / n).toDouble();
  return math.pow(v, 1 / n).toDouble();
}
