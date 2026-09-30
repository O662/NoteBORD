import 'dart:math' as math;
import 'dart:ui';

import '../board/ids.dart';
import '../board/model.dart';
import '../templates/templates.dart';
import '../theme/tokens.g.dart' as tokens;

// New things for the page, as they are when first dropped.

/// A yellow sticky note centered on [center], tilted a little like the
/// design's (Board.dc.html).
StickyItem newSticky(Offset center, {required int z, required DateTime now, Color? color}) => StickyItem(
      id: newId('it'),
      x: center.dx - StickyItem.defaultSize.width / 2,
      y: center.dy - StickyItem.defaultSize.height / 2,
      rotation: -2,
      z: z,
      createdAt: now,
      w: StickyItem.defaultSize.width,
      h: StickyItem.defaultSize.height,
      color: color ?? tokens.stickyColors[0],
    );

/// A stack of three blank notes: pink on top, then peach and green.
StickyItem newStickyStack(Offset center, {required int z, required DateTime now}) => StickyItem(
      id: newId('it'),
      x: center.dx - StickyItem.defaultSize.width / 2,
      y: center.dy - StickyItem.defaultSize.height / 2,
      z: z,
      createdAt: now,
      w: StickyItem.defaultSize.width,
      h: StickyItem.defaultSize.height,
      color: tokens.stickyColors[1],
      under: [StickyNote(color: tokens.stickyColors[2]), StickyNote(color: tokens.stickyColors[3])],
    );

/// A sheet of paper with the middle of its top edge at [top]: lined A4, or
/// a template (its paper, or its layout scaled to the sheet's width).
FrameItem newFrame(Offset top, {required int z, required DateTime now, TemplateDef? template}) {
  var size = FrameItem.a4;
  var paper = 'lined-a4';
  String? layout;
  if (template != null) {
    final bounds = template.layout ? layoutBounds(template.id) : null;
    if (bounds != null) {
      layout = template.id;
      const pad = 24.0;
      size = Size(size.width, (size.width - 2 * pad) / bounds.width * bounds.height + 2 * pad);
    } else {
      paper = switch (template.paper) {
        Paper.lines => 'lined-a4',
        Paper.grid => 'grid-a4',
        Paper.dots => 'dots-a4',
        Paper.blank => 'blank-a4',
      };
    }
  }
  return FrameItem(
    id: newId('it'),
    x: top.dx - size.width / 2,
    y: top.dy,
    z: z,
    createdAt: now,
    w: size.width,
    h: size.height.roundToDouble(),
    paper: paper,
    template: layout,
  );
}

/// A shape dragged out from [a] to [b]: a box between them, or a line or
/// arrow from one to the other.
ShapeItem shapeBetween(
  ShapeType kind,
  Offset a,
  Offset b, {
  required String id,
  required int z,
  required DateTime now,
  required Color color,
  required double strokeWidth,
}) {
  if (kind == ShapeType.line || kind == ShapeType.arrow) {
    final d = b - a, mid = (a + b) / 2;
    return ShapeItem(
      id: id,
      x: mid.dx - d.distance / 2,
      y: mid.dy,
      rotation: math.atan2(d.dy, d.dx) * 180 / math.pi,
      z: z,
      createdAt: now,
      kind: kind,
      w: d.distance,
      h: 0,
      stroke: color,
      strokeWidth: strokeWidth,
    );
  }
  final r = Rect.fromPoints(a, b);
  return ShapeItem(
    id: id,
    x: r.left,
    y: r.top,
    z: z,
    createdAt: now,
    kind: kind,
    w: r.width,
    h: r.height,
    stroke: color,
    strokeWidth: strokeWidth,
  );
}

/// The shape a tap drops, centered on [center].
ShapeItem shapeAt(
  ShapeType kind,
  Offset center, {
  required int z,
  required DateTime now,
  required Color color,
  required double strokeWidth,
}) {
  final half = switch (kind) {
    ShapeType.rect => const Offset(90, 60),
    ShapeType.ellipse => const Offset(80, 80),
    ShapeType.triangle => const Offset(80, 70),
    ShapeType.line || ShapeType.arrow => const Offset(100, 0),
  };
  return shapeBetween(kind, center - half, center + half,
      id: newId('it'), z: z, now: now, color: color, strokeWidth: strokeWidth);
}

String shapeName(ShapeType k) => switch (k) {
      ShapeType.rect => 'Rectangle',
      ShapeType.ellipse => 'Oval',
      ShapeType.triangle => 'Triangle',
      ShapeType.line => 'Line',
      ShapeType.arrow => 'Arrow',
    };
