import 'package:flutter/material.dart';

import '../../canvas/math_mode.dart';
import '../../math/math_pictures.dart' show mathFontFallback;
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import 'math_keys.dart' show symbolsTab;

/// Math mode's dark bar in place of the tool pill (Math.dc.html's toolbar):
/// "∑ Math mode · Handwriting converts as you go", Lasso, Formulas & tools,
/// Add a graph, Done. Lasso isn't in the design: with the tool pill gone,
/// it's how to circle math that was written before.
class MathBar extends StatelessWidget {
  const MathBar({
    super.key,
    required this.math,
    required this.onFormulas,
    required this.onAddGraph,
    required this.onDone,
    this.compact = false,
  });

  final MathMode math;
  final VoidCallback onFormulas;
  final VoidCallback onAddGraph;
  final VoidCallback onDone;

  /// Too narrow for the subtitle.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: math,
      builder: (context, _) => Semantics(
        container: true,
        label: 'Math mode',
        explicitChildNodes: true,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
          decoration: BoxDecoration(
            color: c.inverse,
            borderRadius: BorderRadius.circular(Radii.pill),
            boxShadow: c.pillShadow,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
            ExcludeSemantics(
              child: Text(
                '∑',
                style: TextStyle(fontFamily: FontFamilies.serif, fontFamilyFallback: mathFontFallback, fontSize: 20, color: c.onInverse),
              ),
            ),
            Text('Math mode', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.onInverse)),
            if (!compact)
              Text('Handwriting converts as you go', style: TextStyle(fontSize: 13, color: c.onInverseMuted)),
            MathBarButton(
              label: 'Lasso',
              selected: math.lasso,
              onTap: () => math.lasso = !math.lasso,
            ),
            MathBarButton(
              label: 'Formulas & tools',
              selected: math.draft != null && math.tab >= symbolsTab,
              onTap: onFormulas,
            ),
            MathBarButton(label: 'Add a graph', onTap: onAddGraph),
            MathBarButton(label: 'Done', done: true, onTap: onDone),
          ]),
        ),
      ),
    );
  }
}

class MathBarButton extends StatelessWidget {
  const MathBarButton({super.key, required this.label, required this.onTap, this.done = false, this.selected = false});

  final String label;
  final VoidCallback onTap;
  final bool done;

  /// A toggle that's on.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final light = done || selected;
    return Semantics(
      button: true,
      toggled: label == 'Lasso' ? selected : null,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: light ? c.surface : c.inverseRaised,
        borderRadius: BorderRadius.circular(Radii.button),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.button),
          onTap: onTap,
          child: Container(
            height: 44,
            padding: EdgeInsets.symmetric(horizontal: done ? 16 : 14),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(fontSize: 14, fontWeight: done ? FontWeight.w700 : FontWeight.w600, color: light ? c.text : c.onInverse),
            ),
          ),
        ),
      ),
    );
  }
}
