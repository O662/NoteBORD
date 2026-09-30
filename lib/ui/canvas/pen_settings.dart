import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../board/model.dart';
import '../../canvas/gestures.dart';
import '../../state/settings.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart' show Radii;

// "Settings › Pen & S Pen" (Arrows.dc.html and Scribble.dc.html). Shown in
// the stand-in Settings dialog until the Settings screen exists.

String arrowStyleLabel(ArrowStyle s) => switch (s) {
  ArrowStyle.open => 'Open',
  ArrowStyle.filled => 'Filled',
  ArrowStyle.ink => 'Like my ink',
};

/// Quick arrows: the on/off switch and the three arrowhead cards.
class QuickArrowSettings extends ConsumerWidget {
  const QuickArrowSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final s = ref.watch(settingsProvider);
    final settings = ref.read(settingsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        _SwitchRow(
          title: 'Flick back at the end of a line to make an arrow',
          subtitle: 'Keeps your line’s color, thickness and shape',
          value: s.arrows,
          onChanged: (v) => settings.apply((st) => st.copyWith(arrows: v)),
        ),
        Text(
          'Arrowhead',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.text),
        ),
        Semantics(
          container: true,
          label: 'Arrowhead style',
          explicitChildNodes: true,
          child: Row(
            spacing: 8,
            children: [
              for (final style in ArrowStyle.values)
                Expanded(
                  child: _ArrowCard(
                    style: style,
                    selected: s.arrowStyle == style,
                    onTap: () => settings.apply((st) => st.copyWith(arrowStyle: style)),
                  ),
                ),
            ],
          ),
        ),
        Text(
          'A short flick is all it takes. Longer strokes back along the line stay as ink, '
          'so zig-zags and check marks aren’t affected.',
          style: TextStyle(fontSize: 13, height: 1.45, color: c.textMuted),
        ),
      ],
    );
  }
}

class _ArrowCard extends StatelessWidget {
  const _ArrowCard({required this.style, required this.selected, required this.onTap});

  final ArrowStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = arrowStyleLabel(style);
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? c.accentWash : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.button),
          side: BorderSide(color: selected ? c.accent : c.line, width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.button),
          onTap: onTap,
          child: SizedBox(
            height: 64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 4,
              children: [
                CustomPaint(size: const Size(60, 22), painter: _ArrowIconPainter(style, c.text)),
                Text(
                  label,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The little arrows on the cards (Arrows.dc.html `defs`).
class _ArrowIconPainter extends CustomPainter {
  _ArrowIconPainter(this.style, this.color);

  final ArrowStyle style;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    canvas.drawLine(const Offset(4, 11), const Offset(52, 11), stroke);
    final head = switch (style) {
      ArrowStyle.open =>
        Path()
          ..moveTo(42, 3)
          ..lineTo(54, 11)
          ..lineTo(42, 19),
      ArrowStyle.filled =>
        Path()
          ..moveTo(42, 3)
          ..lineTo(54, 11)
          ..lineTo(42, 19)
          ..close(),
      ArrowStyle.ink =>
        Path()
          ..moveTo(43, 4)
          ..cubicTo(47, 7, 50, 9, 54, 11)
          ..cubicTo(50, 13, 46, 16, 42, 19),
    };
    if (style == ArrowStyle.filled) canvas.drawPath(head, Paint()..color = color);
    canvas.drawPath(head, stroke);
  }

  @override
  bool shouldRepaint(_ArrowIconPainter old) => old.style != style || old.color != color;
}

/// Scribble to erase: the switch and how much scribbling counts.
class ScribbleSettings extends ConsumerWidget {
  const ScribbleSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final s = ref.watch(settingsProvider);
    final settings = ref.read(settingsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        _SwitchRow(
          title: 'Scribble over ink to erase it',
          subtitle: 'Works with the pen and marker, no need to switch tools',
          value: s.scribble,
          onChanged: (v) => settings.apply((st) => st.copyWith(scribble: v)),
        ),
        Text(
          'How much scribbling counts',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.text),
        ),
        Semantics(
          container: true,
          label: 'Scribble sensitivity',
          explicitChildNodes: true,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: c.side, borderRadius: BorderRadius.circular(Radii.button)),
            child: Row(
              spacing: 2,
              children: [
                for (final level in ScribbleLevel.values)
                  Expanded(
                    child: SettingsSegment(
                      label: scribbleLevelLabel(level),
                      selected: s.scribbleLevel == level,
                      onTap: () => settings.apply((st) => st.copyWith(scribbleLevel: level)),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Text(scribbleLevelHelp(s.scribbleLevel), style: TextStyle(fontSize: 13, color: c.textMuted)),
      ],
    );
  }
}

/// One choice in a sunk segmented control (Scribble.dc.html sensitivity).
class SettingsSegment extends StatelessWidget {
  const SettingsSegment({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.semanticLabel,
  });

  final String label;

  /// Read out instead of [label] (for short labels like "in").
  final String? semanticLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: selected
                ? [BoxShadow(color: c.shadow.withValues(alpha: 0.2), offset: const Offset(0, 1), blurRadius: 2)]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: c.text),
          ),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.title, required this.subtitle, required this.value, required this.onChanged});

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.text),
      ),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 13, color: c.textMuted)),
      value: value,
      onChanged: onChanged,
    );
  }
}
