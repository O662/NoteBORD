import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui' show Brightness;

import 'package:flutter/painting.dart';

import '../board/model.dart';
import '../templates/templates.dart';
import '../theme/colors.dart';
import '../theme/tokens.g.dart';
import 'cards.dart';
import 'page_runtime.dart' show paintStroke;
import 'stroke_geometry.dart' show segmentDistance;

// Text boxes, sticky notes, paper frames, images and shapes: how they are
// drawn, hit and stretched (design/source/Board.dc.html).

/// A decoded image for an `assets/` file name, or null while it loads.
typedef ImageLookup = ui.Image? Function(String asset);

const framePaperNames = {
  'lined-a4': 'Lined A4',
  'grid-a4': 'Grid A4',
  'dots-a4': 'Dot grid A4',
  'blank-a4': 'Blank A4',
};

/// The name above a frame: "Frame · Lined A4".
String frameLabel(FrameItem f) {
  if (f.title.isNotEmpty) return 'Frame · ${f.title}';
  return 'Frame · ${templateById(f.template)?.name ?? framePaperNames[f.paper] ?? 'Paper'}';
}

const stickyColorNames = ['Yellow', 'Pink', 'Peach', 'Green'];

String stickyColorName(Color c) {
  final i = stickyColors.indexWhere((s) => s.toARGB32() == c.toARGB32());
  return i < 0 ? colorToHex(c) : stickyColorNames[i];
}

/// A sticky note's parts scale with it; the design's note is 176 wide.
double _stickyUnit(StickyItem s) => s.w / 176;

String stackLabel(int count) => count == 1 ? '1 note' : '$count notes';

TextPainter _badgeText(StickyItem s, Color color) => TextPainter(
      text: TextSpan(
        text: stackLabel(s.count),
        style: TextStyle(
          fontFamily: FontFamilies.ui,
          fontSize: 12 * _stickyUnit(s),
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

final _badges = Expando<Rect>('stackBadge');

/// Where a stack's "5 notes" badge sits, relative to the note's top-left
/// corner: hanging off its top-right corner.
Rect stackBadgeRect(StickyItem s) => _badges[s] ??= () {
      final k = _stickyUnit(s);
      final text = _badgeText(s, const Color(0xFF000000));
      final width = text.width + 20 * k;
      text.dispose();
      return Rect.fromLTWH(s.w + 14 * k - width, -14 * k, width, 30 * k);
    }();

/// Draws a box item in page space.
void paintBoxItem(Canvas canvas, BoxItem item, Brightness brightness, EndlessColors c, {ImageLookup? images}) {
  canvas
    ..save()
    ..translate(item.center.dx, item.center.dy);
  if (item.rotation != 0) canvas.rotate(item.angle);
  canvas.translate(-item.w / 2, -item.h / 2);
  switch (item) {
    case TextItem t:
      final painter = layoutText(t.text, t.font, t.size, t.wrap, color: displayInk(t.color, brightness));
      painter.paint(canvas, Offset.zero);
      painter.dispose();
    case StickyItem s:
      _paintSticky(canvas, s, c);
    case FrameItem f:
      _paintFrame(canvas, f, c);
    case ImageItem i:
      _paintImage(canvas, i, c, images);
    case CardItem card:
      paintCard(canvas, card, c);
    case ShapeItem s:
      final path = shapePath(s);
      if (s.fill != null) canvas.drawPath(path, Paint()..color = displayInk(s.fill!, brightness));
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s.strokeWidth
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..color = displayInk(s.stroke, brightness),
      );
  }
  canvas.restore();
}

/// A CSS box shadow under [rect]: `0 dy blur spread color`.
void _shadow(Canvas canvas, Rect rect, Color color, {required double dy, required double blur, double spread = 0}) {
  final r = rect.inflate(spread).shift(Offset(0, dy));
  if (r.width <= 0 || r.height <= 0) return;
  canvas.drawRect(
    r,
    Paint()
      ..color = color
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur / 2),
  );
}

void _paintSticky(Canvas canvas, StickyItem s, EndlessColors c) {
  final k = _stickyUnit(s);
  final rect = Offset.zero & Size(s.w, s.h);

  // The notes underneath, fanned out: up to two show.
  for (var i = math.min(s.count - 1, 2); i >= 1; i--) {
    canvas
      ..save()
      ..translate(s.w / 2 + 5 * i * k, s.h / 2 + 5 * i * k)
      ..rotate(2 * i * math.pi / 180);
    final card = Rect.fromCenter(center: Offset.zero, width: s.w, height: s.h);
    _shadow(canvas, card, c.shadow, dy: 6 * k, blur: 12 * k, spread: -10 * k);
    canvas
      ..drawRect(card, Paint()..color = i - 1 < s.under.length ? s.under[i - 1].color : s.color)
      ..restore();
  }

  _shadow(canvas, rect, c.shadow, dy: 10 * k, blur: 18 * k, spread: -12 * k);
  canvas
    ..drawRect(rect, Paint()..color = s.color)
    ..save()
    ..clipRect(rect);
  // Paper stays paper in dark mode, so what's on it keeps its own colors.
  for (final item in s.items) {
    switch (item) {
      case StrokeItem ink:
        paintStroke(canvas, ink, ink.color);
      case BoxItem box:
        paintBoxItem(canvas, box, Brightness.light, c);
      case UnknownItem _:
        break;
    }
  }
  canvas.restore();

  if (s.isStack) {
    final badge = stackBadgeRect(s);
    final pill = RRect.fromRectAndRadius(badge, Radius.circular(badge.height / 2));
    canvas
      ..drawRRect(pill.inflate(2 * k), Paint()..color = c.bg)
      ..drawRRect(pill, Paint()..color = c.inverse);
    final text = _badgeText(s, c.onInverse);
    text.paint(canvas, badge.center - Offset(text.width / 2, text.height / 2));
    text.dispose();
  }
}

void _paintFrame(Canvas canvas, FrameItem f, EndlessColors c) {
  final rect = Offset.zero & Size(f.w, f.h);
  final label = TextPainter(
    text: TextSpan(
      text: frameLabel(f),
      style: TextStyle(fontFamily: FontFamilies.ui, fontSize: 16, fontWeight: FontWeight.w600, color: c.textMuted),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: math.max(f.w, 60));
  label.paint(canvas, Offset(0, -8 - label.height));
  label.dispose();

  // 0 1px 2px shadow/10%, 0 12px 24px -16px shadow/35%
  _shadow(canvas, rect, c.shadow.withValues(alpha: c.shadow.a * 0.25), dy: 1, blur: 2);
  _shadow(canvas, rect, c.shadow.withValues(alpha: c.shadow.a * 0.8), dy: 12, blur: 24, spread: -16);
  canvas
    ..drawRect(rect, Paint()..color = c.surface)
    ..save()
    ..clipRect(rect);
  final u = f.unit;
  final template = templateById(f.template);
  if (template != null) {
    // The layout, scaled to the sheet's width inside a margin.
    final layout = layoutBounds(template.id);
    final pad = 24 * u;
    final scale = layout == null ? u : (f.w - 2 * pad) / layout.width;
    _rules(canvas, rect, template.paper, 32 * scale, c, offset: pad);
    final picture = layoutPicture(template.id, c);
    if (picture != null && layout != null) {
      canvas
        ..translate(pad - layout.left * scale, pad - layout.top * scale)
        ..scale(scale)
        ..drawPicture(picture);
    }
  } else {
    switch (f.paper) {
      case 'lined-a4':
        final line = Paint()
          ..color = c.paperLine
          ..strokeWidth = 1.4 * u;
        for (var y = 96 * u; y < f.h; y += 40 * u) {
          canvas.drawLine(Offset(0, y), Offset(f.w, y), line);
        }
        canvas.drawLine(
          Offset(80 * u, 0),
          Offset(80 * u, f.h),
          Paint()
            ..color = c.paperMargin
            ..strokeWidth = 2 * u,
        );
      case 'grid-a4':
        _rules(canvas, rect, Paper.grid, 32 * u, c);
      case 'dots-a4':
        _rules(canvas, rect, Paper.dots, Sizes.paperDotSpacing * u, c);
    }
  }
  canvas.restore();
}

/// Page paper (lines, grid or dots) inside a frame.
void _rules(Canvas canvas, Rect rect, Paper paper, double step, EndlessColors c, {double offset = 0}) {
  if (step < 2) return;
  switch (paper) {
    case Paper.lines || Paper.grid:
      final line = Paint()
        ..color = paper == Paper.lines ? c.paperLine : c.paperGrid
        ..strokeWidth = math.max(1, step / 32);
      for (var y = offset + step; y < rect.bottom; y += step) {
        canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), line);
      }
      if (paper == Paper.grid) {
        for (var x = offset + step; x < rect.right; x += step) {
          canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), line);
        }
      }
    case Paper.dots:
      final dot = Paint()..color = c.dot;
      final r = Sizes.paperDotRadius * step / Sizes.paperDotSpacing;
      for (var y = offset + step / 2; y < rect.bottom; y += step) {
        for (var x = offset + step / 2; x < rect.right; x += step) {
          canvas.drawCircle(Offset(x, y), r, dot);
        }
      }
    case Paper.blank:
      break;
  }
}

void _paintImage(Canvas canvas, ImageItem i, EndlessColors c, ImageLookup? images) {
  final rect = Offset.zero & Size(i.w, i.h);
  final image = images?.call(i.asset);
  if (image == null) {
    // Still loading, or the file is missing: show where it goes.
    canvas
      ..drawRect(rect, Paint()..color = c.menuTile)
      ..drawRect(
        rect.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = c.line,
      );
    return;
  }
  canvas.drawImageRect(
    image,
    Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
    rect,
    Paint()..filterQuality = FilterQuality.medium,
  );
}

/// A shape's outline, relative to its top-left corner.
Path shapePath(ShapeItem s) {
  final rect = Offset.zero & Size(s.w, s.h);
  final path = Path();
  switch (s.kind) {
    case ShapeType.rect:
      path.addRect(rect);
    case ShapeType.ellipse:
      path.addOval(rect);
    case ShapeType.triangle:
      path.addPolygon([Offset(s.w / 2, 0), Offset(s.w, s.h), Offset(0, s.h)], true);
    case ShapeType.line || ShapeType.arrow:
      final y = s.h / 2;
      path
        ..moveTo(0, y)
        ..lineTo(s.w, y);
      if (s.kind == ShapeType.arrow) {
        // An open head, its sides 30° off the line.
        final len = math.min(arrowHeadLength(s.strokeWidth), s.w);
        final dx = len * math.cos(math.pi / 6), dy = len * math.sin(math.pi / 6);
        path
          ..moveTo(s.w - dx, y - dy)
          ..lineTo(s.w, y)
          ..lineTo(s.w - dx, y + dy);
      }
  }
  return path;
}

/// Whether [page] is on [item], within [slop] page px. A shape without a
/// fill is hit on its outline only, so what's inside it stays reachable; a
/// frame is hit on its name too.
bool boxHit(BoxItem item, Offset page, {double slop = 0}) {
  final p = item.toLocal(page);
  final rect = Offset.zero & Size(item.w, item.h);
  switch (item) {
    case ShapeItem s when s.fill == null || s.isLine:
      final reach = slop + s.strokeWidth / 2 + 6;
      double toSide(Offset a, Offset b) => segmentDistance(p, p, a, b);
      switch (s.kind) {
        case ShapeType.line || ShapeType.arrow:
          return toSide(Offset(0, s.h / 2), Offset(s.w, s.h / 2)) <= reach;
        case ShapeType.rect:
          final inner = rect.deflate(reach);
          return rect.inflate(reach).contains(p) && !(inner.width > 0 && inner.height > 0 && inner.contains(p));
        case ShapeType.ellipse:
          final rx = s.w / 2, ry = s.h / 2;
          if (rx <= 0 || ry <= 0) return false;
          final d = math.sqrt(math.pow((p.dx - rx) / rx, 2) + math.pow((p.dy - ry) / ry, 2));
          return (d - 1).abs() * math.min(rx, ry) <= reach;
        case ShapeType.triangle:
          final a = Offset(s.w / 2, 0), b = Offset(s.w, s.h), c = Offset(0, s.h);
          return math.min(toSide(a, b), math.min(toSide(b, c), toSide(c, a))) <= reach;
      }
    case FrameItem _:
      return rect.inflate(slop).contains(p) || Rect.fromLTRB(0, -30, math.min(item.w, 220), 0).contains(p);
    default:
      return rect.inflate(slop).contains(p);
  }
}

/// The topmost box item under [page] (ink is skipped), or null.
BoxItem? topBoxAt(List<Item> inZOrder, Offset page, {double slop = 0}) {
  for (final item in inZOrder.reversed) {
    if (item is BoxItem && boxHit(item, page, slop: slop)) return item;
  }
  return null;
}

/// The edges of [item] that can be dragged to stretch it: 0 top, 1 right,
/// 2 bottom, 3 left. Text and lines only get wider; images keep their shape.
List<int> stretchSides(BoxItem item) => switch (item) {
      TextItem _ => const [1, 3],
      ShapeItem s when s.isLine => const [1, 3],
      ImageItem _ => const [],
      _ => const [0, 1, 2, 3],
    };

/// [item] with its [side] edge dragged to [page]. The opposite edge stays
/// where it is, whatever the rotation.
BoxItem stretchBox(BoxItem item, int side, Offset page, {double min = 24}) {
  final p = item.toLocal(page);
  var w = item.w, h = item.h;
  // A card keeps room for its columns and at least its header.
  final minW = item is CardItem ? cardMinWidth(item.data) * item.unit : min;
  final minH = item is CardItem ? 80 * item.unit : min;
  // The corner that doesn't move, as a fraction of the box.
  var anchor = Offset.zero;
  switch (side) {
    case 0:
      h = math.max(minH, item.h - p.dy);
      anchor = const Offset(0, 1);
    case 1:
      w = math.max(minW, p.dx);
    case 2:
      h = math.max(minH, p.dy);
    case 3:
      w = math.max(minW, item.w - p.dx);
      anchor = const Offset(1, 0);
  }
  final fixed = item.toPage(Offset(anchor.dx * item.w, anchor.dy * item.h));
  final out = item.withBox(x: item.x, y: item.y, w: w, h: h);
  final drift = fixed - out.toPage(Offset(anchor.dx * out.w, anchor.dy * out.h));
  return out.withBox(x: out.x + drift.dx, y: out.y + drift.dy, w: out.w, h: out.h);
}
