import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart' show Alignment;

import '../board/model.dart';
import '../canvas/pens.dart';
import '../theme/colors.dart';

/// A small vector copy of a page's ink for notebook covers. Stored in the
/// library index so the library draws covers without reading page files.
/// Colors are the stored ink colors, so dark mode brightens them on display.
class InkThumb {
  const InkThumb(this.bounds, this.strokes);

  /// Page-space bounds of the strokes.
  final Rect bounds;
  final List<InkThumbStroke> strokes;

  /// At most this many points in total.
  static const pointBudget = 1500;
  static const strokeBudget = 400;

  /// Simplifies a page's strokes, or returns null for a page without ink.
  static InkThumb? fromPage(BoardPage page) {
    final strokes = page.items.whereType<StrokeItem>().take(strokeBudget).toList();
    if (strokes.isEmpty) return null;
    var bounds = strokes.first.bounds;
    for (final s in strokes.skip(1)) {
      bounds = bounds.expandToInclude(s.bounds);
    }
    // Drop points closer than minGap to the last kept one, widening the gap
    // until everything fits the budget.
    var minGap = math.max(bounds.width, bounds.height) / 400;
    while (true) {
      var total = 0;
      final out = <InkThumbStroke>[];
      for (final s in strokes) {
        final kept = <Offset>[];
        for (final p in s.pagePoints) {
          if (kept.isEmpty || (p - kept.last).distance >= minGap) kept.add(p);
        }
        final last = s.pagePoints.last;
        if (kept.last != last) kept.add(last);
        total += kept.length;
        out.add(InkThumbStroke(s.color, s.width, s.tool == InkTool.marker, kept));
      }
      if (total <= pointBudget) return InkThumb(bounds, out);
      minGap *= 1.6;
    }
  }

  String encode() => jsonEncode({
        'b': [bounds.left, bounds.top, bounds.right, bounds.bottom].map((v) => v.roundToDouble()).toList(),
        's': [
          for (final s in strokes)
            [
              colorToHex(s.color),
              round1(s.width),
              s.marker ? 1 : 0,
              [for (final p in s.points) ...[p.dx.roundToDouble(), p.dy.roundToDouble()]],
            ],
        ],
      });

  static InkThumb? decode(String? source) {
    if (source == null || source.isEmpty) return null;
    try {
      final j = jsonDecode(source) as Map<String, dynamic>;
      final b = (j['b'] as List).cast<num>();
      return InkThumb(Rect.fromLTRB(b[0].toDouble(), b[1].toDouble(), b[2].toDouble(), b[3].toDouble()), [
        for (final s in j['s'] as List)
          InkThumbStroke(
            colorFromHex(s[0] as String),
            (s[1] as num).toDouble(),
            s[2] == 1,
            [
              for (var i = 0; i + 1 < (s[3] as List).length; i += 2)
                Offset(((s[3] as List)[i] as num).toDouble(), ((s[3] as List)[i + 1] as num).toDouble()),
            ],
          ),
      ]);
    } on Object {
      return null;
    }
  }

  /// Draws the ink into [area], scaled down to fit (never up past [maxScale])
  /// and aligned by [alignment].
  void paint(
    Canvas canvas,
    Rect area,
    Brightness brightness, {
    double maxScale = 0.6,
    Alignment alignment = Alignment.topLeft,
  }) {
    final scale = math.min(
      maxScale,
      math.min(area.width / math.max(bounds.width, 1), area.height / math.max(bounds.height, 1)),
    );
    final size = bounds.size * scale;
    final free = Offset(area.width - size.width, area.height - size.height);
    final origin = area.topLeft + Offset(free.dx * (alignment.x + 1) / 2, free.dy * (alignment.y + 1) / 2);
    canvas
      ..save()
      ..clipRect(area)
      ..translate(origin.dx - bounds.left * scale, origin.dy - bounds.top * scale)
      ..scale(scale);
    for (final s in strokes) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true
        // Keep strokes visible when the page is scaled way down.
        ..strokeWidth = math.max(s.width, 1.2 / scale)
        ..color = displayInk(s.color, brightness)
            .withValues(alpha: inkOpacity(s.marker ? InkTool.marker : InkTool.pen, PenType.ballpoint));
      if (s.points.length == 1) {
        canvas.drawCircle(s.points.first, paint.strokeWidth / 2, paint..style = PaintingStyle.fill);
        continue;
      }
      final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
      for (final p in s.points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }
}

class InkThumbStroke {
  const InkThumbStroke(this.color, this.width, this.marker, this.points);

  final Color color;
  final double width;
  final bool marker;
  final List<Offset> points;
}
