import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../math/math_pictures.dart' show mathWidget;
import '../../theme/colors.dart';

/// What the preview shows.
enum PreviewState { reading, read, unreadable, unavailable }

/// "PREVIEW" over the selected handwriting typeset, in a dashed box
/// (Math.dc.html): what Convert to math would put on the page.
class MathPreview extends StatelessWidget {
  const MathPreview({super.key, required this.state, this.latex, this.maxWidth = 520});

  final PreviewState state;
  final String? latex;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final Widget body = switch (state) {
      PreviewState.read when latex != null => ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth - 28),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: mathWidget(latex!, size: 30, color: c.text),
          ),
        ),
      PreviewState.reading => _Note('Reading…', c.textMuted),
      PreviewState.unavailable => _Note('Math can’t be read on this device', c.textMuted),
      _ => _Note('Can’t read this as math. Try writing it again', c.textMuted),
    };
    return Semantics(
      container: true,
      liveRegion: true,
      label: state == PreviewState.read ? 'Preview' : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, spacing: 4, children: [
        Text(
          'PREVIEW',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.88, color: c.textMuted),
        ),
        CustomPaint(
          painter: _DashedBox(c.accent),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12)),
            child: body,
          ),
        ),
      ]),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(text, style: TextStyle(fontSize: 14, color: color)));
}

/// A 1.5 px dashed border (6 on, 5 off) round a 12-radius box.
class _DashedBox extends CustomPainter {
  _DashedBox(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(0.75), const Radius.circular(12)));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 11) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 6, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBox old) => old.color != color;
}
