import 'package:flutter/material.dart';

import '../../canvas/canvas_view.dart';
import '../../canvas/gesture_overlay.dart' show dashed;
import '../../study/remember.dart';
import '../../theme/colors.dart';
import '../icons.dart';

// What the canvas shows for Need to remember and flashcards (RememberMark.png,
// FlashMake.png): never drawn into the page itself, its thumbnails or
// exports.

/// Room around what's remembered for its yellow wash, in page px.
const washPad = 10.0;

/// The yellow wash under each thing remembered (with Remember, or a drawn
/// star), drawn under the ink.
class RememberWashPainter extends CustomPainter {
  RememberWashPainter(this.vp, this.groups, this.colors) : super(repaint: vp);

  final CanvasView vp;
  final List<RememberGroup> groups;
  final EndlessColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = colors.star.withValues(alpha: 0.16);
    for (final g in groups) {
      final r = g.content.inflate(washPad);
      final screen = Rect.fromPoints(vp.toScreen(r.topLeft), vp.toScreen(r.bottomRight));
      canvas.drawRRect(RRect.fromRectAndRadius(screen, Radius.circular(14 * vp.scale.clamp(0.5, 2))), paint);
    }
  }

  @override
  bool shouldRepaint(RememberWashPainter old) => !identical(old.groups, groups) || old.colors != colors;
}

/// A side of the card being made: its loop (or a box around it), dashed,
/// in [color] with a light fill.
class CardSideOutline {
  const CardSideOutline(this.path, this.color);

  /// Page space.
  final Path path;
  final Color color;
}

class CardOutlinePainter extends CustomPainter {
  CardOutlinePainter(this.vp, this.sides) : super(repaint: vp);

  final CanvasView vp;
  final List<CardSideOutline> sides;

  @override
  void paint(Canvas canvas, Size size) {
    final m = Matrix4.identity()
      ..translateByDouble(vp.translation.dx, vp.translation.dy, 0, 1)
      ..scaleByDouble(vp.scale, vp.scale, 1, 1);
    for (final s in sides) {
      final screen = s.path.transform(m.storage);
      canvas
        ..drawPath(screen, Paint()..color = s.color.withValues(alpha: 0.07))
        ..drawPath(
          dashed(screen, 8, 6),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = s.color,
        );
    }
  }

  @override
  bool shouldRepaint(CardOutlinePainter old) => !identical(old.sides, sides);
}

/// "★ Remembered", "Drawn star · remembered" (RememberMark.dc.html) and the
/// "FRONT" / "BACK" / "Card 2" labels (FlashMake.dc.html). [onTap] makes it
/// a button.
class MarkChip extends StatelessWidget {
  const MarkChip({
    super.key,
    required this.text,
    required this.background,
    required this.foreground,
    this.icon,
    this.iconColor,
    this.onTap,
    this.semantics,
    this.caps = false,
  });

  final String text;
  final Color background;
  final Color foreground;
  final EIconData? icon;
  final Color? iconColor;
  final VoidCallback? onTap;
  final String? semantics;

  /// FRONT / BACK: a little wider, 10 px in.
  final bool caps;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: EdgeInsets.symmetric(horizontal: caps ? 10 : 9, vertical: 3),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, spacing: 5, children: [
        if (icon != null) EIcon(icon!, size: 12, color: iconColor ?? foreground),
        Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1.25, color: foreground)),
      ]),
    );
    if (onTap == null) return ExcludeSemantics(child: chip);
    // A bigger tap area than the chip itself (44 dp tall).
    return Semantics(
      button: true,
      label: semantics ?? text,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4), child: chip),
      ),
    );
  }
}

/// [child] with its top-left corner at [at] (screen), following the view.
class OnPage extends StatelessWidget {
  const OnPage({super.key, required this.at, required this.child, this.anchor = Alignment.topLeft});

  final Offset at;
  final Widget child;

  /// Which point of [child] goes at [at].
  final Alignment anchor;

  @override
  Widget build(BuildContext context) => Positioned(
        left: at.dx,
        top: at.dy,
        child: FractionalTranslation(translation: Offset(-(anchor.x + 1) / 2, -(anchor.y + 1) / 2), child: child),
      );
}
