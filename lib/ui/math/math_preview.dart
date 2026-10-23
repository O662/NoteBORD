import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../math/linear.dart' show latexToLinear;
import '../../math/math_pictures.dart' show mathWidget;
import '../../theme/colors.dart';

/// What the preview shows.
enum PreviewState { reading, read, unreadable, unavailable }

/// "PREVIEW" over the selected handwriting typeset, in a dashed box
/// (Math.dc.html): what Convert to math would put on the page. When the
/// model had other readings, they're chips beside it ("Not sure? Try", as
/// Convert to text offers other words); a tap picks one.
class MathPreview extends StatelessWidget {
  const MathPreview({super.key, required this.state, this.latex, this.options = const [], this.onPick, this.maxWidth = 520});

  final PreviewState state;

  /// The reading shown (the one picked).
  final String? latex;

  /// The readings to choose from, best first (none when there's only one).
  final List<String> options;
  final ValueChanged<String>? onPick;
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
      explicitChildNodes: true,
      // The preview itself lets the pen through to the page; the other
      // readings sit beside it, on its line, so it stays clear of the
      // toolbar under the selection.
      child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, spacing: 12, children: [
        IgnorePointer(
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
        ),
        if (state == PreviewState.read && options.length > 1 && onPick != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, spacing: 4, children: [
              Text('NOT SURE? TRY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.88, color: c.textMuted)),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final option in options)
                  _Reading(latex: option, selected: option == latex, onTap: () => onPick!(option)),
              ]),
            ]),
          ),
      ]),
    );
  }
}

/// A reading as the keyboard writes it, on a chip like Convert to text's.
class _Reading extends StatelessWidget {
  const _Reading({required this.latex, required this.selected, required this.onTap});

  final String latex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = latexToLinear(latex).trim();
    return Semantics(
      button: true,
      selected: selected,
      label: 'Read it as $text',
      excludeSemantics: true,
      child: Material(
        color: selected ? c.inverse : c.surface,
        shape: StadiumBorder(side: BorderSide(color: selected ? c.inverse : c.lineStrong)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              widthFactor: 1,
              // Typeset, like the preview: every symbol has a glyph.
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 28, maxWidth: 220),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: mathWidget(latex, size: 17, color: selected ? c.onInverse : c.text),
                ),
              ),
            ),
          ),
        ),
      ),
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
