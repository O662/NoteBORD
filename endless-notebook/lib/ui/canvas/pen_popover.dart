import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../board/model.dart';
import '../../canvas/pens.dart';
import '../../state/settings.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart' as tokens;
import '../../theme/tokens.g.dart' show Radii, TypeScale;
import '../common.dart';
import '../icons.dart';

/// Pen / Marker settings, opened by tapping the active pen again.
class PenPopover extends ConsumerWidget {
  const PenPopover({super.key, required this.onClose, required this.onComingSoon, required this.caretLeft});

  static const width = 340.0;

  final VoidCallback onClose;
  final ValueChanged<String> onComingSoon;

  /// Caret x, so it points at the pen or marker button.
  final double caretLeft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final s = ref.watch(settingsProvider);
    final settings = ref.read(settingsProvider.notifier);
    final brightness = Theme.of(context).brightness;
    final marker = s.tool == CanvasTool.marker;
    final title = marker ? 'Marker' : 'Pen';
    final size = penSizes[s.sizeIndex];
    final extras = tokens.extraInkDefaults;

    Widget section(String label, {Widget? trailing}) => Row(children: [
          Expanded(child: Text(label.toUpperCase(), style: TypeScale.sectionLabel.copyWith(color: c.textMuted))),
          ?trailing,
        ]);

    Widget check(String label, bool value, AppSettings Function(AppSettings, bool) set) => Semantics(
          checked: value,
          label: label,
          excludeSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.small),
            onTap: () => settings.apply((st) => set(st, !value)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(children: [
                SizedBox.square(
                  dimension: 20,
                  child: Checkbox(
                    value: value,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    onChanged: (v) => settings.apply((st) => set(st, v ?? false)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(label, style: TextStyle(fontSize: 14, color: c.text))),
              ]),
            ),
          ),
        );

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 14,
      children: [
        Row(children: [
          Expanded(child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.text))),
          Transform.translate(
            offset: const Offset(10, 0),
            child: SizedBox(
              width: 44,
              height: 24,
              child: OverflowBox(
                maxHeight: 44,
                minHeight: 44,
                child: ChromeButton(label: 'Close', icon: EIcons.close, iconSize: 18, foreground: c.textMuted, onPressed: onClose),
              ),
            ),
          ),
        ]),
        if (!marker)
          Semantics(
            container: true,
            label: 'Pen type',
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: c.side, borderRadius: BorderRadius.circular(Radii.button)),
              child: Row(spacing: 2, children: [
                for (final t in PenType.values)
                  Expanded(
                    child: _Segment(
                      label: penTypeLabel(t),
                      selected: s.penType == t,
                      onTap: () => settings.apply((st) => st.copyWith(penType: t)),
                    ),
                  ),
              ]),
            ),
          ),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          section('Color'),
          _Grid(children: [
            for (final color in popoverPalette)
              ChromeButton(
                label: colorName(color),
                height: 48,
                selected: false,
                onPressed: () => settings.pickColor(color),
                child: ColorDot(color: displayInk(color, brightness), size: 32, selected: s.color == color),
              ),
            ChromeButton(
              label: 'Custom color',
              height: 48,
              onPressed: () => onComingSoon('Custom colors'),
              child: ColorDot(
                color: extras[1],
                size: 32,
                gradient: SweepGradient(colors: [
                  for (final i in [1, 3, 0, 4, 2, 1]) displayInk(extras[i], brightness),
                ]),
              ),
            ),
          ]),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          section('Thickness',
              trailing: Text(size.label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text))),
          _Grid(children: [
            for (final (i, z) in penSizes.indexed)
              Semantics(
                button: true,
                selected: s.sizeIndex == i,
                label: 'Thickness ${z.label}',
                excludeSemantics: true,
                child: Material(
                  color: s.sizeIndex == i ? c.accentTint : c.bg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.button),
                    side: BorderSide(color: s.sizeIndex == i ? c.accent : Colors.transparent, width: 2),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Radii.button),
                    onTap: () => settings.pickSize(i),
                    child: SizedBox(
                      height: 48,
                      child: Center(
                        child: Container(
                          width: z.dotPx,
                          height: z.dotPx,
                          decoration: BoxDecoration(color: c.text, shape: BoxShape.circle),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ]),
        Semantics(
          label: 'Stroke preview',
          child: Container(
            height: 56,
            decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(Radii.button)),
            child: CustomPaint(
              painter: _PreviewPainter(
                displayInk(s.color, brightness).withValues(alpha: inkOpacity(s.inkTool, s.penType)),
                s.strokeWidth,
              ),
            ),
          ),
        ),
        Column(children: [
          check('Pressure changes thickness', s.pressure, (st, v) => st.copyWith(pressure: v)),
          check('Hold at the end of a stroke to straighten lines and snap shapes', s.snap,
              (st, v) => st.copyWith(snap: v)),
          check('Scribble over ink to erase it', s.scribble, (st, v) => st.copyWith(scribble: v)),
          check('Flick back at the end of a line to make an arrow', s.arrows, (st, v) => st.copyWith(arrows: v)),
        ]),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: c.side, borderRadius: BorderRadius.circular(Radii.button)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: EIcon(EIcons.pen, size: 18, color: c.inverseRaised)),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'S Pen button:', style: TextStyle(fontWeight: FontWeight.w600)),
                  const TextSpan(text: ' hold while writing to erase. Fingers pan and zoom; only the pen draws.'),
                ]),
                style: TextStyle(fontSize: 13, height: 1.4, color: c.inverseRaised),
              ),
            ),
          ]),
        ),
      ],
    );

    return Semantics(
      container: true,
      label: '$title settings',
      explicitChildNodes: true,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: width,
          constraints: BoxConstraints(maxHeight: math.max(200, MediaQuery.sizeOf(context).height - 96)),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(Radii.dialog),
            boxShadow: c.dialogShadow,
          ),
          child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: body),
        ),
        Positioned(
          left: caretLeft,
          top: -6,
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: c.surface,
                border: Border(left: BorderSide(color: c.line), top: BorderSide(color: c.line)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 5) {
      rows.add(Row(spacing: 6, children: [
        for (var j = i; j < i + 5; j++) Expanded(child: j < children.length ? children[j] : const SizedBox()),
      ]));
    }
    return Column(spacing: 6, children: rows);
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? c.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        elevation: 0,
        shadowColor: c.shadow,
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: selected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: [BoxShadow(color: c.text.withValues(alpha: 0.15), offset: const Offset(0, 1), blurRadius: 2)],
                    color: c.surface,
                  )
                : null,
            child: Text(
              label,
              style: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: c.text),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.color, this.width);

  static final _path = parseSvgPath('M14 38 C 52 6, 82 52, 122 28 S 196 8, 234 30 S 282 42, 292 20');

  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate((size.width - 306) / 2, 0);
    canvas.drawPath(
      _path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => old.color != color || old.width != width;
}
