import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/tokens.g.dart';
import 'icons.dart';

/// Shows the "coming soon" snackbar for a feature that isn't built yet.
void showComingSoon(BuildContext context, String feature) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text('$feature is coming soon', textAlign: TextAlign.center),
      width: 360,
      duration: const Duration(seconds: 2),
    ),
  );
}

/// A floating chrome surface: the title pill, tool pill, rails and trays.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(4),
    this.radius = Radii.pill,
    this.shadow = true,
    this.opacity = 1,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool shadow;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: opacity),
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow ? c.pillShadow : null,
      ),
      child: child,
    );
  }
}

/// A square icon button with a semantic label. Toolbar buttons are 44×44.
class ChromeButton extends StatelessWidget {
  const ChromeButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.child,
    this.width = Sizes.touchTarget,
    this.height = Sizes.touchTarget,
    this.padding = 0,
    this.selected = false,
    this.background,
    this.foreground,
    this.radius = Radii.button,
    this.iconSize = 20,
    this.enabled = true,
    this.expanded,
  });

  final String label;
  final VoidCallback? onPressed;
  final EIconData? icon;
  final Widget? child;
  /// Null sizes the button to its content plus [padding].
  final double? width;
  final double height;
  final double padding;

  /// Active tool: inverse colors, like the design's pressed state.
  final bool selected;
  final Color? background;
  final Color? foreground;
  final double radius;
  final double iconSize;
  final bool enabled;
  final bool? expanded;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = selected ? c.inverse : background ?? Colors.transparent;
    var fg = selected ? c.onInverse : foreground ?? c.text;
    if (!enabled) fg = fg.withValues(alpha: 0.35);
    final content = child ?? EIcon(icon!, size: iconSize, color: fg);
    // No tooltips: S Pen hover would pop them up over the page, and the
    // labels are already announced through semantics.
    return Semantics(
      button: true,
      label: label,
      selected: selected,
      enabled: enabled,
      expanded: expanded,
      excludeSemantics: true,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: enabled ? onPressed : null,
          child: Container(
            width: width,
            height: height,
            padding: EdgeInsets.symmetric(horizontal: padding),
            alignment: Alignment.center,
            child: IconTheme.merge(data: IconThemeData(color: fg), child: content),
          ),
        ),
      ),
    );
  }
}

/// 1×28 vertical divider between tool groups.
class PillDivider extends StatelessWidget {
  const PillDivider({super.key, this.vertical = true});

  final bool vertical;

  @override
  Widget build(BuildContext context) => Container(
        width: vertical ? 1 : 28,
        height: vertical ? 28 : 1,
        margin: vertical ? const EdgeInsets.symmetric(horizontal: 4) : const EdgeInsets.symmetric(vertical: 4),
        color: context.colors.line,
      );
}

/// A color dot with the selected ring: `0 0 0 3px surface, 0 0 0 5px color`.
class ColorDot extends StatelessWidget {
  const ColorDot({super.key, required this.color, this.size = 22, this.selected = false, this.gradient});

  final Color color;
  final double size;
  final bool selected;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: gradient == null ? color : null,
        gradient: gradient,
        border: selected ? null : Border.all(color: c.text.withValues(alpha: 0.12)),
        boxShadow: selected
            ? [
                BoxShadow(color: c.surface, spreadRadius: 3),
                BoxShadow(color: color, spreadRadius: 5),
              ].reversed.toList()
            : null,
      ),
    );
  }
}

/// Paints a dashed rounded-rect border (used by "Add page" and "add color").
class DashedBorder extends StatelessWidget {
  const DashedBorder({super.key, required this.child, required this.color, this.radius = 8, this.width = 1.5});

  final Widget child;
  final Color color;
  final double radius;
  final double width;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _DashedPainter(color, radius, width), child: child);
}

class _DashedPainter extends CustomPainter {
  _DashedPainter(this.color, this.radius, this.width);

  final Color color;
  final double radius;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(width / 2);
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 7) {
        canvas.drawPath(m.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) => old.color != color || old.radius != radius || old.width != width;
}
