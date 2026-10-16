import 'dart:math' as math;

import 'latex.dart' show latexSymbols;

// "Graph it": LaTeX for a function of x as something to evaluate.
// `y = x^{2}/2`, `f(x) = 2\sin x`, `\frac{1}{x}`, `\sqrt{x+1}`, `|x|`,
// `e^{-x}`, `\ln x`; implicit multiplication (`2x`, `3\sin x`) included.

/// A function of x read from LaTeX.
class GraphFunction {
  const GraphFunction(this.f);

  final double Function(double x) f;

  double call(double x) => f(x);
}

/// [latex] as a function of x, or null when it isn't one: other letters
/// than x (`y` and `f(x)` only on the left of `=`), or nothing to plot.
GraphFunction? graphable(String latex) {
  final toks = latexSymbols(latex).where((t) => t != r'\left' && t != r'\right' && t != r'\,' && t != r'\limits').toList();
  if (toks.isEmpty) return null;
  final eq = toks.indexOf('=');
  List<String> rhs;
  if (eq < 0) {
    rhs = toks;
  } else {
    final lhs = toks.sublist(0, eq).join();
    final right = toks.sublist(eq + 1);
    if (const {'y', 'f(x)', 'g(x)', 'h(x)', 'y(x)'}.contains(lhs)) {
      rhs = right;
    } else if (right.join() == 'y') {
      rhs = toks.sublist(0, eq);
    } else {
      return null;
    }
  }
  try {
    final p = _Parser(rhs);
    final e = p.expr();
    if (p.i != rhs.length || !p.usesX) return null;
    return GraphFunction(e);
  } on FormatException {
    return null;
  }
}

typedef _Fn = double Function(double x);

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
  _Parser(this.t);

  final List<String> t;
  var i = 0;
  var usesX = false;

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
      left = op == '+' ? (x) => a(x) + b(x) : (x) => a(x) - b(x);
    }
    return left;
  }

  bool get _startsFactor {
    final p = peek;
    if (p == null) return false;
    return p == '(' || p == '{' || p == '[' || (p == '|' && _abs == 0) || p == 'x' || p == 'e' || RegExp(r'^[0-9.]$').hasMatch(p) ||
        const {r'\pi', r'\frac', r'\dfrac', r'\sqrt'}.contains(p) || _functions.containsKey(p);
  }

  _Fn term() {
    var left = unary();
    while (true) {
      final p = peek;
      if (p == r'\cdot' || p == r'\times' || p == '*') {
        i++;
        final a = left, b = unary();
        left = (x) => a(x) * b(x);
      } else if (p == '/' || p == r'\div') {
        i++;
        final a = left, b = unary();
        left = (x) => a(x) / b(x);
      } else if (_startsFactor) {
        // 2x, 3\sin x, (x+1)(x-1)
        final a = left, b = power();
        left = (x) => a(x) * b(x);
      } else {
        return left;
      }
    }
  }

  _Fn unary() {
    if (peek == '-') {
      i++;
      final a = unary();
      return (x) => -a(x);
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
      return (x) => math.pow(base(x), exp(x)).toDouble();
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
      final v = double.tryParse(b.toString()) ?? _fail();
      return (_) => v;
    }
    i++;
    switch (p) {
      case 'x':
        usesX = true;
        return (x) => x;
      case 'e':
        return (_) => math.e;
      case r'\pi':
        return (_) => math.pi;
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
        return (x) => e(x).abs();
      case r'\frac' || r'\dfrac':
        final a = _group(), b = _group();
        return (x) => a(x) / b(x);
      case r'\sqrt':
        _Fn? n;
        if (peek == '[') {
          i++;
          n = expr();
          _expect(']');
        }
        final a = _group();
        final root = n;
        return root == null ? (x) => math.sqrt(a(x)) : (x) => _nthRoot(a(x), root(x));
    }
    if (_functions[p] case final f?) {
      // \sin^{2} x is (\sin x)^2.
      _Fn? exp;
      if (peek == '^') {
        i++;
        exp = _script();
      }
      final arg = peek == '(' ? atom() : power();
      final e = exp;
      return e == null ? (x) => f(arg(x)) : (x) => math.pow(f(arg(x)), e(x)).toDouble();
    }
    _fail();
  }
}

double _nthRoot(double v, double n) {
  // Odd roots of negative numbers are real.
  if (v < 0 && n.round() == n && n.round().isOdd) return -math.pow(-v, 1 / n).toDouble();
  return math.pow(v, 1 / n).toDouble();
}

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
