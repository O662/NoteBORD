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
          if (s.swipeTuck)
            SwipeHandle(
              label: 'Tuck colors away (or swipe up)',
              up: true,
              onSwipe: () => settings.apply((st) => st.copyWith(trayOpen: false)),
              child: SizedBox(
                width: 36,
                height: 44,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, spacing: 3, children: [
                  EIcon(EIcons.tuckUp, size: 14, color: c.textFaint),
                  Container(width: 18, height: 3, decoration: BoxDecoration(color: c.lineStrong, borderRadius: BorderRadius.circular(2))),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Tapped, or swiped [up] (or down), it calls [onSwipe]: the handles that
/// tuck the colors tray and the pen settings away, and the pull tab.
class SwipeHandle extends StatefulWidget {
  const SwipeHandle({super.key, required this.label, required this.up, required this.onSwipe, required this.child});

  final String label;
  final bool up;
  final VoidCallback onSwipe;
  final Widget child;

  @override
  State<SwipeHandle> createState() => _SwipeHandleState();
}

class _SwipeHandleState extends State<SwipeHandle> {
  double _dy = 0;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: widget.label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onSwipe,
          onVerticalDragStart: (_) => _dy = 0,
          onVerticalDragUpdate: (d) => _dy += d.delta.dy,
          onVerticalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            // The way it points, or a flick that way.
            if (widget.up ? (_dy < -8 || v < -200) : (_dy > 8 || v > 200)) widget.onSwipe();
          },
          child: MouseRegion(cursor: SystemMouseCursors.click, child: widget.child),
        ),
      );
}

/// Hangs under the tool bar while the colors tray is tucked away
/// (Canvas-colors-tucked.png): three of its colors and a chevron. Pull it
/// down, or tap it, to bring the tray back.
class TrayPullTab extends ConsumerWidget {
  const TrayPullTab({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final brightness = Theme.of(context).brightness;
    final colors = ref.watch(settingsProvider.select((s) => s.extraColors));
    final shown = [...colors.take(3), ...tokens.extraInkDefaults].take(3);
    return SwipeHandle(
      label: 'Pull down for more colors',
      up: false,
      onSwipe: onOpen,
      child: Container(
        width: 72,
        height: 22,
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(left: BorderSide(color: c.line), right: BorderSide(color: c.line), bottom: BorderSide(color: c.line)),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
          boxShadow: [BoxShadow(color: c.shadow, offset: const Offset(0, 6), blurRadius: 12, spreadRadius: -10)],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 3, children: [
          for (final col in shown)
            Container(width: 7, height: 7, decoration: BoxDecoration(color: displayInk(col, brightness), shape: BoxShape.circle)),
          EIcon(EIcons.trayChevron, size: 12, color: c.textMuted),
        ]),
      ),
    );
  }
}
