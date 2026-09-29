import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_parsing/path_parsing.dart';

import '../theme/colors.dart';

/// Which palette color a part of an icon uses.
enum IconTint { current, danger, star, gold }

/// One SVG element of an icon: a path (rects and circles are converted).
class IconPart {
  const IconPart(this.d, {this.stroke = true, this.fill = false, this.tint = IconTint.current, this.fillTint, this.dash});

  final String d;
  final bool stroke;
  final bool fill;
  final IconTint tint;
  final IconTint? fillTint;
  final List<double>? dash;
}

/// A line icon, drawn from the same SVG path data as design/source/*.dc.html.
class EIconData {
  const EIconData(this.parts, {this.strokeWidth = 1.8, this.viewBox = 24});

  final List<IconPart> parts;
  final double strokeWidth;
  final double viewBox;
}

IconPart _p(String d, {IconTint tint = IconTint.current}) => IconPart(d, tint: tint);

String _rect(double x, double y, double w, double h, [double rx = 0]) {
  if (rx == 0) return 'M$x ${y}H${x + w}V${y + h}H${x}Z';
  return 'M${x + rx} ${y}H${x + w - rx}A$rx $rx 0 0 1 ${x + w} ${y + rx}V${y + h - rx}'
      'A$rx $rx 0 0 1 ${x + w - rx} ${y + h}H${x + rx}A$rx $rx 0 0 1 $x ${y + h - rx}'
      'V${y + rx}A$rx $rx 0 0 1 ${x + rx} ${y}Z';
}

String _circle(double cx, double cy, double r) => 'M${cx - r} ${cy}a$r $r 0 1 0 ${2 * r} 0a$r $r 0 1 0 ${-2 * r} 0Z';

abstract final class EIcons {
  static final back = EIconData([_p('M15 6l-6 6 6 6')], strokeWidth: 2);
  static final undo = EIconData([_p('M9 14L4 9l5-5'), _p('M4 9h10a6 6 0 0 1 0 12h-3')]);
  static final redo = EIconData([_p('M15 14l5-5-5-5'), _p('M20 9H10a6 6 0 0 0 0 12h3')]);
  static final select = EIconData([_p('M6 3l12 8-5.5 1.2L10 18z')]);
  static final lasso = EIconData([
    const IconPart('M12 4c5 0 8 2.4 8 5.4S16.5 15 12 15s-8-2.6-8-5.6S7 4 12 4z', dash: [3, 2.6]),
    _p('M7.5 13.5c-1 2.2.2 4.5 2.5 5.5'),
  ]);
  static final pen = EIconData([_p('M4 20l1-4L16 5l3 3L8 19z'), _p('M14 7l3 3')]);
  static final marker = EIconData([_p('M9 15l-4 4h5l2-2'), _p('M9 15l8-10 3 3-10 8z'), _p('M13 21h8')]);
  static final eraser = EIconData([_p('M3 16l9-9 6 6-6 6H7z'), _p('M13 19h8')]);
  static final shapes = EIconData([_p(_rect(3, 11, 9, 9, 1)), _p(_circle(16, 8, 5))]);
  static final text = EIconData([_p('M5 7V4h14v3M12 4v16M9 20h6')]);
  static final spell = EIconData([
    _p('M3 14l3.5-9 3.5 9M4.3 11h4.4'),
    _p('M13 13l3 3 6-7'),
    _p('M3 19c1.5-1.2 3-1.2 4.5 0s3 1.2 4.5 0 3-1.2 4.5 0', tint: IconTint.danger),
  ]);
  static final share = EIconData([_p(_circle(9, 8, 3.5)), _p('M3 20c.8-3.4 3.2-5 6-5s5.2 1.6 6 5M18 8v6M15 11h6')],
      strokeWidth: 1.9);
  static final export = EIconData([_p('M12 15V4M7 9l5-5 5 5'), _p('M5 14v5a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-5')],
      strokeWidth: 1.9);
  static final more = EIconData([
    for (final x in [5.0, 12.0, 19.0]) IconPart(_circle(x, 12, 1.6), stroke: false, fill: true),
  ]);
  static final insert = EIconData([_p('M12 5v14M5 12h14')], strokeWidth: 2.2);
  static final plus = EIconData([_p('M12 5v14M5 12h14')], strokeWidth: 2);
  static final plusBold = EIconData([_p('M12 5v14M5 12h14')], strokeWidth: 3);
  static final minus = EIconData([_p('M5 12h14')], strokeWidth: 2);
  static final sticky = EIconData([_p('M4 4h16v10l-6 6H4z'), _p('M14 20v-6h6')]);
  static final frame = EIconData([_p(_rect(5, 3, 14, 18, 1.5)), _p('M8 8h8M8 12h8M8 16h5')]);
  static final image = EIconData([_p(_rect(3, 5, 18, 14, 2)), _p(_circle(9, 10, 1.8)), _p('M21 16l-5-5-8 8')]);
  static final templates = EIconData([_p(_rect(4, 4, 16, 16, 2)), _p('M4 9h16M9 9v11')]);
  static final star = EIconData([
    const IconPart('M12 4l2.4 5 5.4.6-4 3.7 1.1 5.4L12 16l-4.9 2.7 1.1-5.4-4-3.7 5.4-.6z',
        fill: true, fillTint: IconTint.star, tint: IconTint.gold),
  ], strokeWidth: 1.6);
  /// ∑, drawn so it doesn't depend on the serif font having the glyph.
  static final sigma = EIconData([_p('M17 5H7l6 7-6 7h10')]);
  static final cap = EIconData([_p('M2 9l10-5 10 5-10 5z M6 11v5c3 2.5 9 2.5 12 0v-5 M22 9v6')]);
  static final spellPlain = EIconData([_p('M3 14l3.5-9 3.5 9M4.3 11h4.4 M13 13l3 3 6-7')]);
  static final book = EIconData([_p('M4 5a2 2 0 0 1 2-2h13v16H6a2 2 0 0 0-2 2z M4 19V5 M8 7h7M8 11h5')]);
  static final mathTools = EIconData([_p('M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18z M3 12h18M12 3v18 M12 12l5.5-5.5')]);
  static final grid = EIconData([_p('M4 4h6v6H4z M14 4h6v6h-6z M4 14h6v6H4z M14 14h6v6h-6z')]);
  static final import = EIconData([_p('M12 4v11M7 10l5 5 5-5 M5 14v5a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-5')]);
  static final exportRow = EIconData([_p('M12 15V4M7 9l5-5 5 5 M5 14v5a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-5')]);
  static final print = EIconData([_p('M7 9V3h10v6 M6 18H4v-7a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v7h-2 M7 14h10v7H7z')]);
  static final lockRow =
      EIconData([_p('M7 11h10a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2z M8 11V8a4 4 0 0 1 8 0v3')]);
  static final pagePaper = EIconData([
    _p('M6.5 3h11A1.5 1.5 0 0 1 19 4.5v15a1.5 1.5 0 0 1-1.5 1.5h-11A1.5 1.5 0 0 1 5 19.5v-15A1.5 1.5 0 0 1 6.5 3z '
        'M8.5 8h.01M12 8h.01M15.5 8h.01M8.5 12h.01M12 12h.01M15.5 12h.01'),
  ]);
  static final history = EIconData([_p('M3 12a9 9 0 1 0 3-6.7 M3 4v5h5 M12 7v5l3 2')]);
  static final settings = EIconData([
    _p('M12 9a3 3 0 1 0 0 6a3 3 0 1 0 0-6z M19.4 13a7.5 7.5 0 0 0 0-2l2-1.6-2-3.4-2.4 1a7.5 7.5 0 0 0-1.7-1L15 3.5h-4'
        'l-.3 2.5a7.5 7.5 0 0 0-1.7 1l-2.4-1-2 3.4 2 1.6a7.5 7.5 0 0 0 0 2l-2 1.6 2 3.4 2.4-1a7.5 7.5 0 0 0 1.7 1l.3 2.5h4'
        'l.3-2.5a7.5 7.5 0 0 0 1.7-1l2.4 1 2-3.4z'),
  ]);
  static final board = EIconData([_p(_rect(3, 5, 18, 14, 2)), _p(_rect(7, 9, 6, 4, 1))]);
  static final fullScreen = EIconData([_p('M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5')], strokeWidth: 1.9);
  static final exitFullScreen = EIconData([_p('M9 4v5H4M15 4v5h5M9 20v-5H4M15 20v-5h5')], strokeWidth: 1.9);
  static final flashcards = EIconData([_p(_rect(3, 8, 14, 12, 2)), _p('M7 5h12a2 2 0 0 1 2 2v9')]);
  static final mic = EIconData([_p(_rect(9, 3, 6, 11, 3)), _p('M5 11a7 7 0 0 0 14 0M12 18v3')], strokeWidth: 1.9);
  static final ruler = EIconData([_p('M3 16L16 3l5 5L8 21z'), _p('M7 12l2 2M10 9l2 2M13 6l2 2')]);
  static final laser = EIconData([
    _p(_circle(17, 7, 2.5)),
    _p('M4 20l9.5-9.5'),
    _p('M17 1.5v2M17 10.5v2M11.5 7h2M20.5 7h2'),
  ]);
  static final split = EIconData([_p(_rect(3, 4, 18, 16, 2)), _p('M12 4v16')]);
  static final search = EIconData([_p(_circle(11, 11, 7)), _p('M20 20l-3.5-3.5')]);
  static final lock = EIconData([_p(_rect(5, 11, 14, 9, 2)), _p('M8 11V8a4 4 0 0 1 8 0v3')]);
  static final close = EIconData([_p('M6 6l12 12M18 6L6 18')], strokeWidth: 2);
  static final chevronRight = EIconData([_p('M9 6l6 6-6 6')], strokeWidth: 2.2);
  static final chevronDown = EIconData([_p('M6 9l6 6 6-6')], strokeWidth: 2.2);
  static final trayChevron = EIconData([_p('M2 2l4 4 4-4')], strokeWidth: 2, viewBox: 12);
  static final fit = EIconData([_p('M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5')]);
  static final pages = EIconData([_p(_rect(7, 3, 13, 16, 1.5)), _p('M4 7v12.5A1.5 1.5 0 0 0 5.5 21H16')]);
  static final map = EIconData([_p('M3 6l6-2 6 2 6-2v14l-6 2-6-2-6 2z'), _p('M9 4v14M15 6v14')]);
  static final edit = EIconData([_p('M4 20l1-4L16 5l3 3L8 19z')], strokeWidth: 2);
  static final check = EIconData([_p('M5 12l5 5 9-10')], strokeWidth: 2);
}

class _PathBuilder extends PathProxy {
  final path = Path();

  @override
  void moveTo(double x, double y) => path.moveTo(x, y);

  @override
  void lineTo(double x, double y) => path.lineTo(x, y);

  @override
  void cubicTo(double x1, double y1, double x2, double y2, double x3, double y3) =>
      path.cubicTo(x1, y1, x2, y2, x3, y3);

  @override
  void close() => path.close();
}

/// Parses SVG path data (as in the design markup) into a [Path].
Path parseSvgPath(String d) {
  final b = _PathBuilder();
  writeSvgPathDataToPath(d, b);
  return b.path;
}

final _paths = Expando<Path>('iconPath');

Path _pathFor(IconPart part) => _paths[part] ??= () {
      final path = parseSvgPath(part.d);
      if (part.dash == null) return path;
      final dashed = Path();
      for (final m in path.computeMetrics()) {
        var d = 0.0;
        var on = true;
        var i = 0;
        while (d < m.length) {
          final len = part.dash![i % part.dash!.length];
          if (on) dashed.addPath(m.extractPath(d, d + len), Offset.zero);
          d += len;
          on = !on;
          i++;
        }
      }
      return dashed;
    }();

class EIcon extends StatelessWidget {
  const EIcon(this.data, {super.key, this.size = 20, this.color});

  final EIconData data;
  final double size;

  /// Defaults to the ambient [IconTheme] color.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final current = color ?? IconTheme.of(context).color ?? context.colors.text;
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _EIconPainter(data, current, context.colors),
      ),
    );
  }
}

class _EIconPainter extends CustomPainter {
  _EIconPainter(this.data, this.current, this.colors);

  final EIconData data;
  final Color current;
  final EndlessColors colors;

  Color _tint(IconTint t) => switch (t) {
        IconTint.current => current,
        IconTint.danger => colors.danger,
        IconTint.star => colors.star,
        IconTint.gold => colors.gold,
      };

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / data.viewBox);
    for (final part in data.parts) {
      final path = _pathFor(part);
      if (part.fill) {
        canvas.drawPath(path, Paint()..color = _tint(part.fillTint ?? part.tint));
      }
      if (part.stroke) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = data.strokeWidth
            ..strokeCap = ui.StrokeCap.round
            ..strokeJoin = ui.StrokeJoin.round
            ..color = _tint(part.tint),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_EIconPainter old) => old.data != data || old.current != current || old.colors != colors;
}
