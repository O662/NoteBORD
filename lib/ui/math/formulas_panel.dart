import 'package:flutter/material.dart';

import '../../canvas/math_mode.dart';
import '../../math/linear.dart';
import '../../math/math_pictures.dart' show mathFontFallback;
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import 'math_keys.dart';

/// "Formulas & symbols" (MathKit.dc.html's formula library): Math and
/// Physics formulas, and the Symbols keypad, four big keys to a row. A tap
/// adds it to the page, or types it into the math keyboard when that's open.
class FormulasPanel extends StatelessWidget {
  const FormulasPanel({
    super.key,
    required this.math,
    required this.onFormula,
    required this.onSymbol,
  });

  static const width = 420.0;

  final MathMode math;
  final ValueChanged<Formula> onFormula;
  final ValueChanged<SymbolKey> onSymbol;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: math,
      builder: (context, _) {
        final typing = math.draft != null;
        return Semantics(
          container: true,
          label: 'Formula library',
          explicitChildNodes: true,
          child: TextFieldTapRegion(
            child: Container(
              width: width,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [BoxShadow(color: c.shadow, offset: const Offset(0, 20), blurRadius: 40, spreadRadius: -24)],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
                Row(children: [
                  Expanded(
                    child: Text('Formulas & symbols', style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 24, color: c.text)),
                  ),
                  Text(
                    typing ? 'Tap to type it' : 'Tap to add to the page',
                    style: TextStyle(fontSize: 12, color: c.textMuted),
                  ),
                ]),
                _Tabs(selected: math.tab, onPick: (i) => math.tab = i),
                Expanded(
                  child: math.tab == 2
                      ? _Symbols(onPick: onSymbol)
                      : _Formulas(math.tab == 0 ? mathFormulas : physicsFormulas, onPick: onFormula),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.selected, required this.onPick});

  final int selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.side, borderRadius: BorderRadius.circular(12)),
      child: Row(spacing: 2, children: [
        for (final (i, label) in const ['Math', 'Physics', 'Symbols'].indexed)
          Expanded(
            child: Semantics(
              button: true,
              selected: i == selected,
              label: label,
              excludeSemantics: true,
              child: Material(
                color: i == selected ? c.surface : Colors.transparent,
                elevation: 0,
                borderRadius: BorderRadius.circular(9),
                child: InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: () => onPick(i),
                  child: Container(
                    height: 44,
                    alignment: Alignment.center,
                    decoration: i == selected
                        ? BoxDecoration(
                            borderRadius: BorderRadius.circular(9),
                            boxShadow: [BoxShadow(color: c.shadow, offset: const Offset(0, 1), blurRadius: 2)],
                            color: c.surface,
                          )
                        : null,
                    child: Text(
                      label,
                      style: TextStyle(fontSize: 14, fontWeight: i == selected ? FontWeight.w700 : FontWeight.w500, color: c.text),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _Formulas extends StatelessWidget {
  const _Formulas(this.formulas, {required this.onPick});

  final List<Formula> formulas;
  final ValueChanged<Formula> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: formulas.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final f = formulas[i];
        return Semantics(
          button: true,
          label: 'Add ${f.name}',
          excludeSemantics: true,
          child: Material(
            color: c.surfaceSunk,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c.lineSoft)),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onPick(f),
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                      Text(f.name, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.textMuted)),
                      Text(
                        formulaLabel(f.text),
                        style: TextStyle(
                          fontFamily: FontFamilies.serif,
                          fontFamilyFallback: mathFontFallback,
                          fontStyle: FontStyle.italic,
                          fontSize: 20,
                          color: c.text,
                        ),
                      ),
                    ]),
                  ),
                  Text('+', style: TextStyle(fontSize: 18, color: c.accent)),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// How the library writes a formula: ½ for 1/2.
String formulaLabel(String text) => text.replaceAll('1/2 ', '½');

class _Symbols extends StatelessWidget {
  const _Symbols({required this.onPick});

  final ValueChanged<SymbolKey> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 80,
      ),
      itemCount: symbolKeys.length,
      itemBuilder: (context, i) {
        final s = symbolKeys[i];
        final n = s.label.characters.length;
        return Semantics(
          button: true,
          label: 'Insert ${s.name}',
          excludeSemantics: true,
          child: Tooltip(
            message: s.name,
            child: Material(
              color: c.surfaceSunk,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.line)),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onPick(s),
                child: Center(
                  child: Text(
                    s.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: FontFamilies.serif,
                      fontFamilyFallback: mathFontFallback,
                      fontSize: n > 4 ? 22 : (n > 2 ? 26 : 32),
                      height: 1.15,
                      color: c.text,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The math a formula adds to the page.
String formulaLatex(Formula f) => linearToLatex(f.text);
