import 'package:flutter_math_fork/flutter_math.dart' show ParseException;
import 'package:flutter_math_fork/tex.dart' show TexParser, TexParserSettings;

// LaTeX for math on the page: written compactly from the recognizer's
// symbols, and checked against the typesetter so whatever goes on the page
// can be drawn.

/// The recognizer's symbols as LaTeX, with no more spaces than needed:
/// `\frac{1}{2}`, `\sin x`, `x^{2}`.
String latexFromSymbols(List<String> symbols) {
  final out = StringBuffer();
  String? prev;
  for (final s in balanceBraces(symbols)) {
    // A command name runs on into letters, so they need a space after it.
    if (prev != null && _isCommandWord(prev) && RegExp(r'^[A-Za-z0-9]').hasMatch(s)) out.write(' ');
    out.write(s);
    prev = s;
  }
  return out.toString();
}

bool _isCommandWord(String s) => s.length > 1 && s.startsWith(r'\') && RegExp(r'^\\[A-Za-z]+$').hasMatch(s);

/// [symbols] with every `{` closed and no `}` without its `{`. The model
/// almost always balances them; when it doesn't, this keeps the page
/// drawable.
List<String> balanceBraces(List<String> symbols) {
  final out = <String>[];
  var open = 0;
  for (final s in symbols) {
    if (s == '{') open++;
    if (s == '}') {
      if (open == 0) continue;
      open--;
    }
    out.add(s);
  }
  return [...out, for (var i = 0; i < open; i++) '}'];
}

/// Splits LaTeX into symbols: commands, single characters and braces.
List<String> latexSymbols(String latex) =>
    [for (final m in RegExp(r'\\[A-Za-z]+|\\.|[^\s]').allMatches(latex)) m.group(0)!];

/// Whether the typesetter can draw [latex].
bool isDrawable(String latex) {
  if (latex.trim().isEmpty) return false;
  try {
    TexParser(latex, const TexParserSettings()).parse();
    return true;
  } on ParseException {
    return false;
  } on Object {
    return false;
  }
}
