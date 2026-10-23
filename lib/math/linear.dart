import 'latex.dart' show latexSymbols;

// The math keyboard's text: math written in a line, as Math.png's field
// shows it ("ω = Δθ / Δt"), and the LaTeX it stands for.
//
// * `a / b` is a fraction of the runs on each side (`Δθ / Δt`,
//   `(a + b) / 2`); a space ends a run, so `1/2 mv²` is ½·mv².
// * `x^2`, `x^(n+1)`, `x_i`, `x²`, `v₀`; `√x`, `√(x + 1)`, `ⁿ√(x)`.
// * `∫ₐᵇ`, `∫_0^1`, `∑_(i=1)^n`, `lim_(x→0)`; sin, cos, log, ln…
// * `"m/s"`: upright text, for units.
// * `[[a, b], [c, d]]`: a matrix.
// * Anything else LaTeX can say goes in as is: `\overline{AB}`.

/// LaTeX for the keyboard's text.
String linearToLatex(String linear) {
  final parser = _LinearParser(_lex(linear));
  return _latex(parser.sequence(null));
}

/// The keyboard's text for [latex] (math on the page being edited).
String latexToLinear(String latex) {
  final parser = _LatexParser(latexSymbols(latex));
  return _linear(parser.sequence(null)).trim().replaceAll(RegExp(' {2,}'), ' ');
}

/// What search finds math by: the keyboard's text for it, and the names
/// of its Greek letters ("omega" finds ω).
String mathSearchText(String latex) {
  final names = <String>{
    for (final m in RegExp(r'\\([A-Za-z]+)').allMatches(latex))
      if (_greek.containsValue(m.group(1))) m.group(1)!.replaceFirst('var', ''),
  };
  return [latexToLinear(latex), ...names].join(' ');
}

// ---------------------------------------------------------------------------
// The tree both directions share.

sealed class _Node {}

/// A symbol: its LaTeX, and how the keyboard writes it.
class _Sym extends _Node {
  _Sym(this.latex, this.text, {this.kind = _Kind.ordinary});

  final String latex;
  final String text;
  final _Kind kind;
}

enum _Kind { ordinary, relation, binary, punct, bigOp, function, space }

class _Seq extends _Node {
  _Seq(this.items);

  final List<_Node> items;
}

/// `( … )`, `[ … ]`, `\{ … \}`.
class _Fence extends _Node {
  _Fence(this.open, this.close, this.body);

  final String open, close;
  final _Seq body;
}

class _Frac extends _Node {
  _Frac(this.num, this.den);

  final _Node num, den;
}

class _Scripts extends _Node {
  _Scripts(this.base, this.sub, this.sup);

  final _Node base;
  final _Node? sub, sup;
}

class _Root extends _Node {
  _Root(this.body, [this.index]);

  final _Node body;
  final _Node? index;
}

/// `\bar{x}`, `\vec{v}`, `\hat{x}`.
class _Accent extends _Node {
  _Accent(this.command, this.body);

  final String command;
  final _Node body;
}

/// Upright text: a unit.
class _Text extends _Node {
  _Text(this.text);

  final String text;
}

class _Matrix extends _Node {
  _Matrix(this.rows);

  final List<List<_Seq>> rows;
}

/// LaTeX passed through untouched.
class _Raw extends _Node {
  _Raw(this.latex);

  final String latex;
}

// ---------------------------------------------------------------------------
// Symbols.

const _greek = {
  'α': 'alpha', 'β': 'beta', 'γ': 'gamma', 'δ': 'delta', 'ε': 'varepsilon', 'ϵ': 'epsilon', 'ζ': 'zeta', //
  'η': 'eta', 'θ': 'theta', 'ϑ': 'vartheta', 'ι': 'iota', 'κ': 'kappa', 'λ': 'lambda', 'μ': 'mu', 'ν': 'nu',
  'ξ': 'xi', 'π': 'pi', 'ρ': 'rho', 'σ': 'sigma', 'ς': 'varsigma', 'τ': 'tau', 'υ': 'upsilon', 'φ': 'varphi',
  'ϕ': 'phi', 'χ': 'chi', 'ψ': 'psi', 'ω': 'omega', 'Γ': 'Gamma', 'Δ': 'Delta', 'Θ': 'Theta', 'Λ': 'Lambda',
  'Ξ': 'Xi', 'Π': 'Pi', 'Σ': 'Sigma', 'Υ': 'Upsilon', 'Φ': 'Phi', 'Ψ': 'Psi', 'Ω': 'Omega',
};

/// Single-character symbols other than Greek letters: LaTeX and kind.
const _symbols = <String, (String, _Kind)>{
  '+': ('+', _Kind.binary), '-': ('-', _Kind.binary), '−': ('-', _Kind.binary), //
  '×': (r'\times', _Kind.binary), '÷': (r'\div', _Kind.binary), '·': (r'\cdot', _Kind.binary),
  '±': (r'\pm', _Kind.binary), '∓': (r'\mp', _Kind.binary), '∪': (r'\cup', _Kind.binary),
  '∩': (r'\cap', _Kind.binary), '*': (r'\ast', _Kind.binary),
  '=': ('=', _Kind.relation), '≠': (r'\neq', _Kind.relation), '≈': (r'\approx', _Kind.relation),
  '≡': (r'\equiv', _Kind.relation), '<': ('<', _Kind.relation), '>': ('>', _Kind.relation),
  '≤': (r'\leq', _Kind.relation), '≥': (r'\geq', _Kind.relation), '∝': (r'\propto', _Kind.relation),
  '→': (r'\rightarrow', _Kind.relation), '⇒': (r'\Rightarrow', _Kind.relation),
  '⇔': (r'\Leftrightarrow', _Kind.relation), '←': (r'\leftarrow', _Kind.relation),
  '∈': (r'\in', _Kind.relation), '∉': (r'\notin', _Kind.relation), '⊂': (r'\subset', _Kind.relation),
  '⊆': (r'\subseteq', _Kind.relation), '⊥': (r'\perp', _Kind.relation), '∥': (r'\parallel', _Kind.relation),
  '~': (r'\sim', _Kind.relation), ':': (':', _Kind.relation),
  ',': (',', _Kind.punct), ';': (';', _Kind.punct),
  '∀': (r'\forall', _Kind.ordinary), '∃': (r'\exists', _Kind.ordinary), '∞': (r'\infty', _Kind.ordinary),
  '∂': (r'\partial', _Kind.ordinary), '∇': (r'\nabla', _Kind.ordinary), '∠': (r'\angle', _Kind.ordinary),
  '∅': (r'\emptyset', _Kind.ordinary), 'ℏ': (r'\hbar', _Kind.ordinary), '…': (r'\ldots', _Kind.ordinary),
  '⋯': (r'\cdots', _Kind.ordinary), '%': (r'\%', _Kind.ordinary), '!': ('!', _Kind.ordinary),
  '|': ('|', _Kind.ordinary), '.': ('.', _Kind.ordinary), "'": ("'", _Kind.ordinary),
  '∫': (r'\int', _Kind.bigOp), '∬': (r'\iint', _Kind.bigOp), '∭': (r'\iiint', _Kind.bigOp),
  '∮': (r'\oint', _Kind.bigOp), '∑': (r'\sum', _Kind.bigOp), '∏': (r'\prod', _Kind.bigOp),
};

const _functions = {
  'sin', 'cos', 'tan', 'sec', 'csc', 'cot', 'sinh', 'cosh', 'tanh', 'arcsin', 'arccos', 'arctan', //
  'log', 'ln', 'lg', 'exp', 'lim', 'max', 'min', 'det', 'gcd', 'deg', 'dim', 'ker', 'arg', 'sup', 'inf',
};

/// Functions whose scripts go under and over them (`lim`, `max`).
const _limits = {'lim', 'max', 'min', 'sup', 'inf'};

const _superscripts = {
  '⁰': '0', '¹': '1', '²': '2', '³': '3', '⁴': '4', '⁵': '5', '⁶': '6', '⁷': '7', '⁸': '8', '⁹': '9', //
  '⁺': '+', '⁻': '-', '⁼': '=', '⁽': '(', '⁾': ')', 'ⁿ': 'n', 'ⁱ': 'i', 'ᵃ': 'a', 'ᵇ': 'b', 'ᶜ': 'c',
  'ᵈ': 'd', 'ᵉ': 'e', 'ᶠ': 'f', 'ᵍ': 'g', 'ʰ': 'h', 'ʲ': 'j', 'ᵏ': 'k', 'ˡ': 'l', 'ᵐ': 'm', 'ᵒ': 'o',
  'ᵖ': 'p', 'ʳ': 'r', 'ˢ': 's', 'ᵗ': 't', 'ᵘ': 'u', 'ᵛ': 'v', 'ʷ': 'w', 'ˣ': 'x', 'ʸ': 'y', 'ᶻ': 'z',
};

const _subscripts = {
  '₀': '0', '₁': '1', '₂': '2', '₃': '3', '₄': '4', '₅': '5', '₆': '6', '₇': '7', '₈': '8', '₉': '9', //
  '₊': '+', '₋': '-', '₌': '=', '₍': '(', '₎': ')', 'ₐ': 'a', 'ₑ': 'e', 'ₒ': 'o', 'ₓ': 'x', 'ₕ': 'h',
  'ₖ': 'k', 'ₗ': 'l', 'ₘ': 'm', 'ₙ': 'n', 'ₚ': 'p', 'ₛ': 's', 'ₜ': 't', 'ᵢ': 'i', 'ⱼ': 'j', 'ᵣ': 'r',
  'ᵤ': 'u', 'ᵥ': 'v',
};

const _accents = {'̄': 'bar', '̅': 'bar', '⃗': 'vec', '̂': 'hat', '̇': 'dot', '̃': 'tilde'};

// ---------------------------------------------------------------------------
// Linear text → tree.

enum _T { space, number, word, sym, sup, sub, text, command, open, close, caret, under, root, accent, slash }

class _Tok {
  _Tok(this.type, this.text);

  final _T type;
  final String text;

  @override
  String toString() => '$type:$text';
}

List<_Tok> _lex(String s) {
  final out = <_Tok>[];
  final chars = s.runes.map(String.fromCharCode).toList();
  var i = 0;
  String run(bool Function(String c) ok) {
    final b = StringBuffer();
    while (i < chars.length && ok(chars[i])) {
      b.write(chars[i++]);
    }
    return b.toString();
  }

  while (i < chars.length) {
    final c = chars[i];
    if (c.trim().isEmpty) {
      run((c) => c.trim().isEmpty);
      out.add(_Tok(_T.space, ' '));
    } else if (_isDigit(c)) {
      // 9.8 is one number.
      final b = StringBuffer(run(_isDigit));
      while (i + 1 < chars.length && chars[i] == '.' && _isDigit(chars[i + 1])) {
        i++;
        b
          ..write('.')
          ..write(run(_isDigit));
      }
      out.add(_Tok(_T.number, b.toString()));
    } else if (_isLetter(c)) {
      out.add(_Tok(_T.word, run(_isLetter)));
    } else if (_superscripts.containsKey(c)) {
      out.add(_Tok(_T.sup, run(_superscripts.containsKey).split('').map((c) => _superscripts[c]).join()));
    } else if (_subscripts.containsKey(c)) {
      out.add(_Tok(_T.sub, run(_subscripts.containsKey).split('').map((c) => _subscripts[c]).join()));
    } else if (c == '"' || c == '“' || c == '”') {
      i++;
      out.add(_Tok(_T.text, run((c) => c != '"' && c != '”' && c != '“')));
      if (i < chars.length) i++;
    } else if (c == r'\') {
      i++;
      // A command, with its {…} and […] arguments, goes through as is.
      final b = StringBuffer(r'\');
      if (i < chars.length) {
        final name = run(_isLetter);
        b.write(name.isEmpty ? chars[i++] : name);
        while (i < chars.length && (chars[i] == '{' || chars[i] == '[')) {
          final open = chars[i], close = open == '{' ? '}' : ']';
          var depth = 0;
          do {
            if (chars[i] == open) depth++;
            if (chars[i] == close) depth--;
            b.write(chars[i++]);
          } while (i < chars.length && depth > 0);
        }
      }
      out.add(_Tok(_T.command, b.toString()));
    } else if (c == '(' || c == '[' || c == '{') {
      i++;
      out.add(_Tok(_T.open, c));
    } else if (c == ')' || c == ']' || c == '}') {
      i++;
      out.add(_Tok(_T.close, c));
    } else if (c == '^') {
      i++;
      out.add(_Tok(_T.caret, c));
    } else if (c == '_') {
      i++;
      out.add(_Tok(_T.under, c));
    } else if (c == '/' || c == '⁄') {
      i++;
      out.add(_Tok(_T.slash, '/'));
    } else if (c == '√' || c == '∛' || c == '∜') {
      i++;
      out.add(_Tok(_T.root, c));
    } else if (_accents.containsKey(c)) {
      i++;
      out.add(_Tok(_T.accent, _accents[c]!));
    } else if (c == '°') {
      i++;
      out.add(_Tok(_T.sup, r'\circ'));
    } else if (c == '′' || c == '″') {
      i++;
      out.add(_Tok(_T.sup, c == '′' ? r'\prime' : r'\prime\prime'));
    } else {
      i++;
      out.add(_Tok(_T.sym, c));
    }
  }
  return out;
}

bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

bool _isLetter(String c) => RegExp(r'^[A-Za-z]$').hasMatch(c);

class _LinearParser {
  _LinearParser(this.toks);

  final List<_Tok> toks;
  var i = 0;

  _Tok? get peek => i < toks.length ? toks[i] : null;

  /// Items until [close] (or the end); runs of units with no space between
  /// them stay together, then `/` makes fractions of the runs beside it.
  _Seq sequence(String? close) {
    final items = <_Node>[];
    for (var t = peek; t != null; t = peek) {
      if (t.type == _T.close) {
        if (t.text == close) break;
        // A stray closing bracket is just a symbol.
        i++;
        items.add(_Sym(_closeLatex(t.text), t.text));
        continue;
      }
      if (t.type == _T.space) {
        i++;
        items.add(_Sym('', ' ', kind: _Kind.space));
        continue;
      }
      if (t.type == _T.slash) {
        i++;
        items.add(_Sym('/', '/', kind: _Kind.binary));
        continue;
      }
      final kind = t.type == _T.sym ? _symbols[t.text]?.$2 : null;
      if (kind != null && kind != _Kind.ordinary && kind != _Kind.bigOp) {
        i++;
        items.add(_Sym(_symbols[t.text]!.$1, t.text, kind: kind));
        continue;
      }
      items.add(_run());
    }
    return _Seq(_fractions(items));
  }

  /// Units written together: `2gh`, `Δθ`, `x²(x+1)`.
  _Node _run() {
    final units = <_Node>[];
    for (var t = peek; t != null && _startsUnit(t); t = peek) {
      units.addAll(_unit());
    }
    if (units.isEmpty) {
      // Something that can't start a unit (a lone ^): keep it as a symbol.
      final t = toks[i++];
      return _Sym(t.text, t.text);
    }
    return units.length == 1 ? units.single : _Seq(units);
  }

  bool _startsUnit(_Tok t) => switch (t.type) {
        _T.space || _T.close || _T.slash => false,
        _T.sym => (_symbols[t.text]?.$2 ?? _Kind.ordinary) == _Kind.ordinary || _symbols[t.text]?.$2 == _Kind.bigOp,
        _ => true,
      };

  /// One unit with its scripts. A word can be several units (`mv`).
  List<_Node> _unit() {
    final t = toks[i];
    final List<_Node> bases;
    switch (t.type) {
      case _T.number:
        i++;
        bases = [_Sym(t.text, t.text)];
      case _T.word:
        i++;
        bases = _word(t.text);
      case _T.text:
        i++;
        bases = [_Text(t.text)];
      case _T.command:
        i++;
        bases = [_Raw(t.text)];
      case _T.open:
        i++;
        final body = sequence(_closing(t.text));
        if (peek?.type == _T.close) i++;
        bases = [_matrixFrom(t.text, body) ?? _Fence(t.text, _closing(t.text), body)];
      case _T.root:
        i++;
        bases = [_Root(_operand(), t.text == '∛' ? _Sym('3', '3') : (t.text == '∜' ? _Sym('4', '4') : null))];
      case _T.sup when toks.length > i + 1 && toks[i + 1].type == _T.root:
        // ⁿ√(x): the superscript is the root's index.
        i += 2;
        bases = [_Root(_operand(), _scriptText(t.text))];
      case _T.sym:
        i++;
        bases = [_symbol(t.text)];
      default:
        // A script or accent with nothing before it.
        i++;
        bases = [_Sym(t.text, t.text)];
    }
    var last = bases.removeLast();
    // Scripts, accents and primes on the last base.
    _Node? sub, sup;
    for (var t = peek; t != null; t = peek) {
      if (t.type == _T.caret || t.type == _T.under) {
        i++;
        final script = _script();
        if (t.type == _T.caret) {
          sup = _join(sup, script);
        } else {
          sub = _join(sub, script);
        }
      } else if (t.type == _T.sup && !(toks.length > i + 1 && toks[i + 1].type == _T.root)) {
        i++;
        sup = _join(sup, _scriptText(t.text));
      } else if (t.type == _T.sub) {
        i++;
        sub = _join(sub, _scriptText(t.text));
      } else if (t.type == _T.accent && sub == null && sup == null) {
        i++;
        last = _Accent(t.text, last);
      } else {
        break;
      }
    }
    if (sub != null || sup != null) last = _Scripts(last, sub, sup);
    return [...bases, last];
  }

  /// A word: a function's name, or letters (`mv`, or `sinx` = sin x).
  List<_Node> _word(String w) {
    if (_functions.contains(w)) return [_Sym('\\$w', w, kind: _Kind.function)];
    for (final f in _functions) {
      if (w.length == f.length + 1 && w.startsWith(f)) {
        return [_Sym('\\$f', f, kind: _Kind.function), _Sym(w[f.length], w[f.length])];
      }
    }
    return [for (final c in w.split('')) _Sym(c, c)];
  }

  _Node _symbol(String c) {
    if (_greek[c] case final name?) return _Sym('\\$name', c);
    if (_symbols[c] case (final latex, final kind)) return _Sym(latex, c, kind: kind);
    return _Sym(c, c);
  }

  /// What a script or root applies to: a bracket group (brackets dropped)
  /// or one unit.
  _Node _operand() {
    final t = peek;
    if (t == null) return _Seq([]);
    if (t.type == _T.open && t.text == '(') {
      i++;
      final body = sequence(')');
      if (peek?.type == _T.close) i++;
      return body;
    }
    if (!_startsUnit(t)) return _Seq([]);
    final u = _unit();
    return u.length == 1 ? u.single : _Seq(u);
  }

  _Node _script() {
    final t = peek;
    // x^2 takes the number, x^ab only the a.
    if (t != null && t.type == _T.word && t.text.length > 1 && !_functions.contains(t.text)) {
      i++;
      toks.insert(i, _Tok(_T.word, t.text.substring(1)));
      return _Sym(t.text[0], t.text[0]);
    }
    return _operand();
  }

  _Node _scriptText(String s) {
    if (s.startsWith(r'\')) return _Raw(s);
    return _LinearParser(_lex(s)).sequence(null);
  }

  _Node _join(_Node? a, _Node b) => a == null ? b : _Seq([a, b]);

  /// [x, y] holding [a, b] lists: a matrix.
  _Matrix? _matrixFrom(String open, _Seq body) {
    if (open != '[') return null;
    final rows = <List<_Seq>>[];
    for (final item in body.items) {
      if (item is _Sym && (item.kind == _Kind.punct || item.kind == _Kind.space)) continue;
      if (item is! _Fence || item.open != '[') return null;
      rows.add(_splitCells(item.body));
    }
    return rows.isEmpty ? null : _Matrix(rows);
  }

  List<_Seq> _splitCells(_Seq row) {
    final cells = <_Seq>[_Seq([])];
    for (final item in row.items) {
      if (item is _Sym && item.text == ',') {
        cells.add(_Seq([]));
      } else {
        cells.last.items.add(item);
      }
    }
    return cells;
  }

  /// `a / b` → a fraction of the runs on each side, left to right.
  List<_Node> _fractions(List<_Node> items) {
    final out = <_Node>[];
    var k = 0;
    while (k < items.length) {
      final item = items[k];
      if (item is _Sym && item.latex == '/' && item.kind == _Kind.binary) {
        // The run before (skipping spaces) and after.
        var l = out.length - 1;
        while (l >= 0 && _isSpace(out[l])) {
          l--;
        }
        var r = k + 1;
        while (r < items.length && _isSpace(items[r])) {
          r++;
        }
        if (l >= 0 && r < items.length && _isOperand(out[l]) && _isOperand(items[r])) {
          final num = out[l];
          out.removeRange(l, out.length);
          out.add(_Frac(_unfence(num), _unfence(items[r])));
          k = r + 1;
          continue;
        }
      }
      out.add(item);
      k++;
    }
    return out;
  }

  bool _isSpace(_Node n) => n is _Sym && n.kind == _Kind.space;

  bool _isOperand(_Node n) => !(n is _Sym && n.kind != _Kind.ordinary && n.kind != _Kind.function && n.kind != _Kind.bigOp);

  /// `(a + b)` over 2: the brackets go.
  _Node _unfence(_Node n) => n is _Fence && n.open == '(' ? n.body : n;
}

String _closing(String open) => switch (open) {
      '(' => ')',
      '[' => ']',
      _ => '}',
    };

String _closeLatex(String c) => c == '}' ? r'\}' : c;

// ---------------------------------------------------------------------------
// Tree → LaTeX.

String _latex(_Node n) {
  final b = _LatexWriter();
  _writeLatex(n, b);
  return b.toString();
}

class _LatexWriter {
  final _b = StringBuffer();
  String _last = '';

  void add(String s) {
    if (s.isEmpty) return;
    // A command name runs on into letters: `\sin x`, not `\sinx`.
    if (RegExp(r'\\[A-Za-z]+$').hasMatch(_last) && RegExp(r'^[A-Za-z0-9]').hasMatch(s)) _b.write(' ');
    _b.write(s);
    _last = s;
  }

  @override
  String toString() => _b.toString();
}

void _writeLatex(_Node n, _LatexWriter b) {
  switch (n) {
    case _Sym s:
      b.add(s.latex);
    case _Seq s:
      for (final item in s.items) {
        _writeLatex(item, b);
      }
    case _Fence f:
      b.add(f.open == '{' ? r'\{' : f.open);
      _writeLatex(f.body, b);
      b.add(f.close == '}' ? r'\}' : f.close);
    case _Frac f:
      b.add(r'\frac{');
      _writeLatex(f.num, b);
      b.add('}{');
      _writeLatex(f.den, b);
      b.add('}');
    case _Scripts s:
      _writeLatex(s.base, b);
      if (s.base case _Sym(kind: _Kind.function, :final text) when _limits.contains(text)) b.add(r'\limits');
      if (s.sub != null) {
        b.add('_{');
        _writeLatex(s.sub!, b);
        b.add('}');
      }
      if (s.sup != null) {
        b.add('^{');
        _writeLatex(s.sup!, b);
        b.add('}');
      }
    case _Root r:
      b.add(r'\sqrt');
      if (r.index != null) {
        b.add('[');
        _writeLatex(r.index!, b);
        b.add(']');
      }
      b.add('{');
      _writeLatex(r.body, b);
      b.add('}');
    case _Accent a:
      b.add('\\${a.command}{');
      _writeLatex(a.body, b);
      b.add('}');
    case _Text t:
      b.add(unitLatex(t.text));
    case _Matrix m:
      b.add(r'\begin{bmatrix}');
      for (final (r, row) in m.rows.indexed) {
        if (r > 0) b.add(r'\\');
        for (final (c, cell) in row.indexed) {
          if (c > 0) b.add('&');
          _writeLatex(cell, b);
        }
      }
      b.add(r'\end{bmatrix}');
    case _Raw r:
      b.add(r.latex);
  }
}

/// A unit as LaTeX: letters upright, after a thin space (`9.8\,\mathrm{m/s^{2}}`).
String unitLatex(String unit) {
  final b = StringBuffer(r'\,');
  final letters = StringBuffer();
  void flush() {
    if (letters.isEmpty) return;
    b.write('\\mathrm{$letters}');
    letters.clear();
  }

  for (final c in unit.runes.map(String.fromCharCode)) {
    if (_isLetter(c) || c == '/' || _isDigit(c)) {
      letters.write(c);
    } else if (_superscripts[c] case final s?) {
      letters.write('^{$s}');
    } else if (c == '°') {
      flush();
      b.write(r'^{\circ}');
    } else if (_greek[c] case final name?) {
      flush();
      b.write('\\$name ');
    } else if (_symbols[c] case (final latex, _)) {
      flush();
      b.write('$latex ');
    } else if (c.trim().isEmpty) {
      flush();
      b.write(r'\ ');
    } else {
      letters.write(c);
    }
  }
  flush();
  return b.toString().trimRight();
}

// ---------------------------------------------------------------------------
// LaTeX → tree.

final _latexSymbols = <String, (String, _Kind)>{
  for (final e in _greek.entries) '\\${e.value}': (e.key, _Kind.ordinary),
  for (final e in _symbols.entries)
    if (e.value.$1.startsWith(r'\') || !e.value.$1.contains(RegExp('[A-Za-z]'))) e.value.$1: (e.key, e.value.$2),
  '-': ('−', _Kind.binary),
  r'\to': ('→', _Kind.relation),
  r'\ne': ('≠', _Kind.relation),
  r'\le': ('≤', _Kind.relation),
  r'\ge': ('≥', _Kind.relation),
  r'\lt': ('<', _Kind.relation),
  r'\gt': ('>', _Kind.relation),
  r'\prime': ('′', _Kind.ordinary),
  r'\{': ('{', _Kind.ordinary),
  r'\}': ('}', _Kind.ordinary),
  r'\phi': ('ϕ', _Kind.ordinary),
  r'\epsilon': ('ϵ', _Kind.ordinary),
  r'\mid': ('|', _Kind.ordinary),
  r'\vert': ('|', _Kind.ordinary),
  r'\dots': ('…', _Kind.ordinary),
};

class _LatexParser {
  _LatexParser(this.toks);

  final List<String> toks;
  var i = 0;

  String? get peek => i < toks.length ? toks[i] : null;

  _Seq sequence(String? close) {
    final items = <_Node>[];
    for (var t = peek; t != null; t = peek) {
      if (t == close) break;
      if (t == '}' || t == '&' || t == r'\\' || t == r'\end') break;
      items.add(_withScripts(_atom()));
    }
    return _Seq(items);
  }

  _Node _group() {
    if (peek == '{') {
      i++;
      final body = sequence('}');
      if (peek == '}') i++;
      return body;
    }
    if (peek == null) return _Seq([]);
    return _atom();
  }

  _Node _withScripts(_Node base) {
    _Node? sub, sup;
    while (peek == '^' || peek == '_' || peek == r'\limits' || peek == "'") {
      final t = toks[i++];
      if (t == r'\limits') continue;
      if (t == "'") {
        sup = sup == null ? _Sym(r'\prime', '′') : _Seq([sup, _Sym(r'\prime', '′')]);
        continue;
      }
      final g = _group();
      if (t == '^') {
        sup = g;
      } else {
        sub = g;
      }
    }
    return sub == null && sup == null ? base : _Scripts(base, sub, sup);
  }

  _Node _atom() {
    final t = toks[i++];
    switch (t) {
      case r'\frac' || r'\dfrac' || r'\tfrac':
        final num = _group();
        return _Frac(num, _group());
      case r'\sqrt':
        _Node? index;
        if (peek == '[') {
          i++;
          index = sequence(']');
          if (peek == ']') i++;
        }
        return _Root(_group(), index);
      case r'\mathrm' || r'\text' || r'\textrm' || r'\mathrm ':
        return _Text(_plain(_group()));
      case r'\left' || r'\right' || r'\,' || r'\;' || r'\ ' || r'\!' || r'\quad':
        if (t == r'\left' || t == r'\right') return _Seq([]);
        return _Sym('', ' ', kind: _Kind.space);
      case r'\bar' || r'\vec' || r'\hat' || r'\dot' || r'\tilde' || r'\overline' || r'\overrightarrow':
        final name = switch (t) {
          r'\overline' => 'bar',
          r'\overrightarrow' => 'vec',
          _ => t.substring(1),
        };
        return _Accent(name, _group());
      case r'\begin':
        final env = _plain(_group());
        if (env.endsWith('matrix')) return _matrix();
        return _Raw('\\begin{$env}');
      case '{':
        final body = sequence('}');
        if (peek == '}') i++;
        return body;
    }
    if (_latexSymbols[t] case (final text, final kind)) return _Sym(t, text, kind: kind);
    if (t.startsWith(r'\') && _functions.contains(t.substring(1))) {
      return _Sym(t, t.substring(1), kind: _Kind.function);
    }
    if (t.startsWith(r'\') && t.length > 2) {
      // Something the keyboard has no key for: kept as LaTeX, with its
      // arguments.
      final b = StringBuffer(t);
      while (peek == '{') {
        b.write('{${_latexText()}}');
      }
      return _Raw(b.toString());
    }
    if (t.startsWith(r'\')) return _Sym(t, t.substring(1));
    // Digits written together (and 9.8) stay one number.
    if (_isDigit(t)) {
      final b = StringBuffer(t);
      while (peek != null && (_isDigit(peek!) || (peek == '.' && i + 1 < toks.length && _isDigit(toks[i + 1])))) {
        b.write(toks[i++]);
      }
      return _Sym(b.toString(), b.toString());
    }
    final kind = _symbols[t]?.$2 ?? _Kind.ordinary;
    return _Sym(t, t == '-' ? '−' : t, kind: kind);
  }

  /// The raw LaTeX of the {…} group at [i].
  String _latexText() {
    final start = ++i;
    var depth = 1;
    while (i < toks.length) {
      if (toks[i] == '{') depth++;
      if (toks[i] == '}' && --depth == 0) break;
      i++;
    }
    final inner = toks.sublist(start, i).join(' ');
    if (i < toks.length) i++;
    return inner;
  }

  _Matrix _matrix() {
    final rows = <List<_Seq>>[[]];
    while (peek != null && peek != r'\end') {
      final cell = sequence(null);
      rows.last.add(cell);
      if (peek == '&') {
        i++;
      } else if (peek == r'\\') {
        i++;
        rows.add([]);
      } else if (peek == '}') {
        i++;
      }
    }
    if (peek == r'\end') {
      i++;
      _group();
    }
    if (rows.last.isEmpty) rows.removeLast();
    return _Matrix(rows);
  }

  String _plain(_Node n) => switch (n) {
        _Sym s => s.latex.startsWith(r'\') ? s.text : s.latex,
        _Seq s => s.items.map(_plain).join(),
        _ => _linear(n),
      };
}

// ---------------------------------------------------------------------------
// Tree → linear text.

String _linear(_Node n) {
  switch (n) {
    case _Sym s:
      return switch (s.kind) {
        _Kind.relation || _Kind.binary => ' ${s.text} ',
        _Kind.punct => '${s.text} ',
        _Kind.function => '${s.text} ',
        _Kind.space => ' ',
        _ => s.text,
      };
    case _Seq s:
      final b = StringBuffer();
      for (final (k, item) in s.items.indexed) {
        final text = _linear(item);
        // A fraction stands apart from what's next to it, or the run would
        // join it: ½mv² is "1/2 mv²".
        if (item is _Frac && k > 0 && !b.toString().endsWith(' ')) b.write(' ');
        // So does a function's name: 2 sin x, not "2sin x".
        final named = _isFunction(item) || (item is _Scripts && _isFunction(item.base));
        if (named && b.isNotEmpty && !b.toString().endsWith(' ') && !b.toString().endsWith('(')) b.write(' ');
        b.write(text);
        if (item is _Frac && k + 1 < s.items.length) b.write(' ');
      }
      return b.toString();
    case _Fence f:
      return '${f.open}${_linear(f.body).trim()}${f.close}';
    case _Frac f:
      return '${_operandText(f.num)} / ${_operandText(f.den)}';
    case _Scripts s:
      var base = _linear(s.base);
      if (_isFunction(s.base)) base = base.trimRight();
      if (s.base is _Frac || s.base is _Seq) base = '(${base.trim()})';
      return '$base${s.sub == null ? '' : _scriptText(s.sub!, _subscripts, '_')}'
          '${s.sup == null ? '' : _scriptText(s.sup!, _superscripts, '^')}${_isFunction(s.base) ? ' ' : ''}';
    case _Root r:
      final body = _linear(r.body).trim();
      final simple = _isSimple(r.body);
      final index = r.index == null ? '' : _unicodeScript(_linear(r.index!).trim(), _superscripts);
      if (r.index != null && index == null) return '\\sqrt[${_latex(r.index!)}]{${_latex(r.body)}}';
      return '${index ?? ''}√${simple ? body : '($body)'}';
    case _Accent a:
      final mark = _accents.entries.firstWhere((e) => e.value == a.command, orElse: () => const MapEntry('', '')).key;
      final body = _linear(a.body).trim();
      if (mark.isNotEmpty && body.runes.length == 1) return '$body$mark';
      return '\\${a.command}{${_latex(a.body)}}';
    case _Text t:
      return '"${t.text}"';
    case _Matrix m:
      return '[${m.rows.map((r) => '[${r.map((c) => _linear(c).trim()).join(', ')}]').join(', ')}]';
    case _Raw r:
      return r.latex;
  }
}

bool _isFunction(_Node n) => n is _Sym && n.kind == _Kind.function;

/// A fraction's top or bottom: as is when it's one run, else in brackets.
String _operandText(_Node n) {
  final text = _linear(n).trim();
  return _isSimple(n) && !text.contains(' ') ? text : '($text)';
}

bool _isSimple(_Node n) {
  final text = _linear(n).trim();
  return text.isNotEmpty && !text.contains(' ') && !RegExp(r'[+\-−=,/]').hasMatch(text);
}

/// x², v₀, x^(n+1), x_i.
String _scriptText(_Node n, Map<String, String> unicode, String mark) {
  var text = _linear(n).trim();
  // A minus sign that starts a script is a sign, not a subtraction: f⁻¹.
  if (text.startsWith('− ')) text = '-${text.substring(2)}';
  if (_unicodeScript(text, unicode) case final u?) return u;
  return _isSimple(n) && text.runes.length == 1 || RegExp(r'^\d+$').hasMatch(text) ? '$mark$text' : '$mark($text)';
}

/// [text] in Unicode super- or subscript letters, if they all have one.
String? _unicodeScript(String text, Map<String, String> table) {
  if (text.isEmpty) return null;
  final back = {for (final e in table.entries) e.value: e.key};
  final b = StringBuffer();
  for (final c in text.runes.map(String.fromCharCode)) {
    final u = back[c];
    if (u == null) return null;
    b.write(u);
  }
  return b.toString();
}
