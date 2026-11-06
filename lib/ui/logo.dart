import 'package:flutter/material.dart';

import '../theme/tokens.g.dart' show LogoColors;
import 'icons.dart' show parseSvgPath;

// The Endless mark (design/logo/, UPDATE_03.md): an infinity symbol drawn as
// one ink stroke that never closes. It starts just inside the right loop,
// goes all the way around, and the rising center line comes back out past
// its start as an arrow, up and to the right.

/// The mark's strokes in the logo's 120 × 120 box (before its 4-unit shift
/// down): path data and stroke width.
const logoStrokes = [
  ('M100.84 53.92 C 102.98 57.43, 104 60, 104 64 C 104 74, 97 81, 87 81 C 77 81, 68 73, 60 60', 10.0),
  ('M60 60 C 52 47, 43 41, 33 41 C 22 41, 15 50, 15 60 C 15 70, 22 79, 33 79 C 43 79, 52 73, 60 60', 8.0),
  ('M60 60 C 67 47, 77 38, 92 34', 9.5),
  ('M87.7 27.5 L99.0 31.6 L92.3 41.6', 9.5),
];

final _paths = [for (final (d, w) in logoStrokes) (parseSvgPath(d), w)];

/// The part of the logo box the mark fills (Start.dc.html's sidebar
/// `viewBox="8 28 104 72"`).
const logoMarkBox = Rect.fromLTWH(8, 28, 104, 72);

/// Draws the mark in [color], with the logo box's [box] fitted into [area].
void paintLogoMark(Canvas canvas, Rect area, Color color, {Rect box = logoMarkBox}) {
  final scale = area.width / box.width < area.height / box.height ? area.width / box.width : area.height / box.height;
  final drawn = Size(box.width * scale, box.height * scale);
  final at = Alignment.center.inscribe(drawn, area).topLeft;
  canvas
    ..save()
    ..translate(at.dx, at.dy)
    ..scale(scale)
    ..translate(-box.left, -box.top + 4);
  for (final (path, width) in _paths) {
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }
  canvas.restore();
}

/// The mark, [width] wide: ink on light screens, the night ink on dark ones.
class EndlessMark extends StatelessWidget {
  const EndlessMark({super.key, this.width = 40, this.color});

  final double width;

  /// Its one color (default: ink, or the night ink in dark mode).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? (Theme.of(context).brightness == Brightness.dark ? LogoColors.nightInk : LogoColors.ink);
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size(width, width * logoMarkBox.height / logoMarkBox.width),
        painter: _MarkPainter(c),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) => paintLogoMark(canvas, Offset.zero & size, color);

  @override
  bool shouldRepaint(_MarkPainter old) => old.color != color;
}
