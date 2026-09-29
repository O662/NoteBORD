import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../canvas/pens.dart';
import '../../state/settings.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart' as tokens;
import '../common.dart';
import '../icons.dart';

/// The slim "More colors" row under the tool pill: up to 10 extra colors,
/// a + button, an n/10 counter and edit. Kept small; it sits on writing space.
class ColorTray extends ConsumerStatefulWidget {
  const ColorTray({super.key});

  @override
  ConsumerState<ColorTray> createState() => _ColorTrayState();
}

class _ColorTrayState extends ConsumerState<ColorTray> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = ref.watch(settingsProvider);
    final settings = ref.read(settingsProvider.notifier);
    final brightness = Theme.of(context).brightness;
    final count = s.extraColors.length;

    return Semantics(
      container: true,
      label: 'More colors, $count of ${tokens.extraInkMax}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(tokens.Radii.card),
          boxShadow: [BoxShadow(color: c.shadow, offset: const Offset(0, 8), blurRadius: 18, spreadRadius: -12)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final color in s.extraColors)
            ChromeButton(
              label: _editing ? 'Remove color: ${colorName(color)}' : 'Color: ${colorName(color)}',
              width: 40,
              radius: tokens.Radii.key,
              onPressed: () => _editing ? settings.removeExtraColor(color) : settings.pickColor(color),
              child: Stack(clipBehavior: Clip.none, children: [
                ColorDot(
                  color: displayInk(color, brightness),
                  selected: !_editing && s.tool != CanvasTool.eraser && s.color == color,
                ),
                if (_editing)
                  Positioned(
                    right: -5,
                    top: -5,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(color: c.inverse, shape: BoxShape.circle),
                      child: Center(child: EIcon(EIcons.close, size: 10, color: c.onInverse)),
                    ),
                  ),
              ]),
            ),
          if (count < tokens.extraInkMax)
            ChromeButton(
              label: 'Add a color',
              width: 40,
              radius: tokens.Radii.key,
              onPressed: settings.addExtraColor,
              child: DashedBorder(
                color: c.textFaint,
                radius: 11,
                child: SizedBox.square(
                  dimension: 22,
                  child: Center(child: EIcon(EIcons.plusBold, size: 12, color: c.textMuted)),
                ),
              ),
            ),
          Container(width: 1, height: 22, margin: const EdgeInsets.symmetric(horizontal: 6), color: c.line),
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: ExcludeSemantics(
              child: Text(
                '$count/${tokens.extraInkMax}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: c.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          ChromeButton(
            label: _editing ? 'Done editing colors' : 'Edit colors: change or remove',
            width: 40,
            radius: tokens.Radii.key,
            selected: _editing,
            iconSize: 16,
            icon: _editing ? EIcons.check : EIcons.edit,
            foreground: c.textMuted,
            onPressed: () => setState(() => _editing = !_editing),
          ),
        ]),
      ),
    );
  }
}
