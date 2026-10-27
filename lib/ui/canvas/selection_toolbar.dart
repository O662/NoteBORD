import 'package:flutter/material.dart';

import '../../canvas/items.dart';
import '../../canvas/pens.dart';
import '../../canvas/selection.dart';
import '../../math/math_pictures.dart' show mathFontFallback;
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart' show FontFamilies, stickyColors;
import '../common.dart';
import '../icons.dart';

enum SelectionAction {
  convert,
  // Math mode (Math.png), and math on the page.
  convertMath,
  graphIt,
  copyLatex,
  editMath,
  remember,
  flashcard,
  copy,
  color,
  straighten,
  delete,
  // For text boxes, sticky notes, frames, images, shapes and cards.
  edit,
  editCard,
  open,
  replaceFile,
  makeChart,
  fanOut,
  nextNote,
  stack,
  rename,
  toFront,
  toBack,
}

const _objectLabels = {
  SelectionAction.convert: 'Convert to text',
  SelectionAction.editMath: 'Edit math',
  SelectionAction.copyLatex: 'Copy as LaTeX',
  SelectionAction.graphIt: 'Graph it',
  SelectionAction.edit: 'Edit text',
  SelectionAction.editCard: 'Edit',
  SelectionAction.open: 'Open',
  SelectionAction.replaceFile: 'Replace file',
  SelectionAction.makeChart: 'Make a chart',
  SelectionAction.fanOut: 'Fan out',
  SelectionAction.nextNote: 'Next note',
  SelectionAction.stack: 'Stack',
  SelectionAction.rename: 'Rename',
  SelectionAction.copy: 'Copy',
  SelectionAction.color: 'Color',
  SelectionAction.toFront: 'To front',
  SelectionAction.toBack: 'To back',
  SelectionAction.delete: 'Delete',
};

/// The dark bar over a selection (Convert.dc.html, RememberMark.dc.html and
/// Math.dc.html). For ink it leads with Convert to text, with Remember when
/// the selection started from "Need to remember", or with Convert to math
/// in math mode. For text boxes, sticky notes, frames, images, shapes and
/// math it shows [objectActions] instead.
class SelectionToolbar extends StatelessWidget {
  const SelectionToolbar({
    super.key,
    required this.menu,
    required this.onAction,
    this.colorsOpen = false,
    this.objectActions,
  });

  final SelectionMenu menu;
  final ValueChanged<SelectionAction> onAction;

  /// The Color button's swatches are showing.
  final bool colorsOpen;

  /// What can be done with the selected objects (no ink among them). The
  /// first one is the main action when it's Edit text, Edit, Fan out or Stack.
  final List<SelectionAction>? objectActions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final remember = menu == SelectionMenu.remember;
    final padding = remember ? 11.0 : 12.0;

    Widget plain(SelectionAction a, String label, {bool expanded = false, double? pad}) => _BarButton(
          label: label,
          padding: pad ?? padding,
          expanded: a == SelectionAction.color ? expanded : null,
          onTap: () => onAction(a),
          child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.onInverse)),
        );

    Widget lead(SelectionAction a, String label, {EIconData? icon, bool sigma = false}) => _BarButton(
          label: label,
          padding: 12,
          background: c.accent,
          onTap: () => onAction(a),
          child: Row(mainAxisSize: MainAxisSize.min, spacing: sigma ? 6 : 8, children: [
            if (icon != null) EIcon(icon, size: 16, color: c.onAccent),
            if (sigma)
              ExcludeSemantics(
                child: Text(
                  '∑',
                  style: TextStyle(fontFamily: FontFamilies.serif, fontFamilyFallback: mathFontFallback, fontSize: 17, color: c.onAccent),
                ),
              ),
            Text(label, style: TextStyle(fontSize: 14, fontWeight: sigma ? FontWeight.w700 : FontWeight.w600, color: c.onAccent)),
          ]),
        );

    const leads = {
      SelectionAction.convert,
      SelectionAction.editMath,
      SelectionAction.edit,
      SelectionAction.editCard,
      SelectionAction.fanOut,
      SelectionAction.stack,
    };
    final objects = objectActions;
    final children = objects != null
        ? [
            for (final (i, a) in objects.indexed)
              if (i == 0 && leads.contains(a))
                lead(a, _objectLabels[a]!, sigma: a == SelectionAction.editMath, icon: switch (a) {
                  SelectionAction.convert || SelectionAction.edit => EIcons.convertText,
                  SelectionAction.editCard => EIcons.edit,
                  _ => null,
                })
              else
                plain(a, _objectLabels[a]!, expanded: colorsOpen),
          ]
        : menu == SelectionMenu.math
            ? [
                lead(SelectionAction.convertMath, 'Convert to math', sigma: true),
                plain(SelectionAction.graphIt, 'Graph it', pad: 11),
                plain(SelectionAction.copyLatex, 'Copy as LaTeX', pad: 11),
              ]
            : remember
            ? [
                _BarButton(
                  label: 'Remember',
                  padding: 12,
                  background: c.star,
                  onTap: () => onAction(SelectionAction.remember),
                  child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                    EIcon(EIcons.starSolid, size: 16, color: c.onStar),
                    Text('Remember', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.onStar)),
                  ]),
                ),
                plain(SelectionAction.convert, 'To text'),
                plain(SelectionAction.flashcard, 'Flashcard'),
                plain(SelectionAction.copy, 'Copy'),
                plain(SelectionAction.delete, 'Delete'),
              ]
            : [
                lead(SelectionAction.convert, 'Convert to text', icon: EIcons.convertText),
                plain(SelectionAction.copy, 'Copy'),
                plain(SelectionAction.color, 'Color', expanded: colorsOpen),
                plain(SelectionAction.straighten, 'Straighten lines'),
                plain(SelectionAction.delete, 'Delete'),
              ];

    return Semantics(
      container: true,
      label: 'Selection actions',
      explicitChildNodes: true,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: c.inverse,
          borderRadius: BorderRadius.circular(12),
          // 0 8px 20px -10px shadow
          boxShadow: [BoxShadow(color: c.shadow, offset: const Offset(0, 8), blurRadius: 20, spreadRadius: -10)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 2, children: children),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.label,
    required this.padding,
    required this.onTap,
    required this.child,
    this.background,
    this.expanded,
  });

  final String label;
  final double padding;
  final VoidCallback onTap;
  final Widget child;
  final Color? background;
  final bool? expanded;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        expanded: expanded,
        excludeSemantics: true,
        child: Material(
          color: background ?? Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: onTap,
            child: Container(
              height: 40,
              padding: EdgeInsets.symmetric(horizontal: padding),
              alignment: Alignment.center,
              child: child,
            ),
          ),
        ),
      );
}

/// Swatches under the toolbar's Color button: ink colors, or the sticky
/// note papers when only sticky notes are selected ([sticky]).
class SelectionColors extends StatelessWidget {
  const SelectionColors({super.key, required this.onPick, this.sticky = false});

  final ValueChanged<Color> onPick;
  final bool sticky;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Semantics(
      container: true,
      label: 'Selection color',
      explicitChildNodes: true,
      child: Pill(
        radius: 12,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (sticky)
            for (final color in stickyColors)
              ChromeButton(
                label: 'Change note to ${stickyColorName(color).toLowerCase()}',
                width: 36,
                onPressed: () => onPick(color),
                child: ColorDot(color: color),
              )
          else
            for (final color in popoverPalette)
              ChromeButton(
                label: 'Change color to ${colorName(color)}',
                width: 36,
                onPressed: () => onPick(color),
                child: ColorDot(color: displayInk(color, brightness)),
              ),
        ]),
      ),
    );
  }
}
