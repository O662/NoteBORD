import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';

import '../theme/tokens.g.dart' show FontFamilies;
import 'ids.dart';

/// The `.board` storage model (docs/BOARD_FORMAT.md).
///
/// Known fields are typed; everything else is kept in `extra` (or, for item
/// types this version doesn't know, the whole raw JSON) and written back
/// unchanged, so files from newer apps survive a round trip.
typedef Json = Map<String, dynamic>;

const boardFormat = 'endless.board';
const boardVersion = 1;
const localAuthor = 'user_local';

enum Paper { dots, lines, grid, blank }

Paper paperFromName(String? name) =>
    Paper.values.firstWhere((p) => p.name == name, orElse: () => Paper.dots);

class Notebook {
  Notebook({
    required this.id,
    required this.title,
    this.folderPath = const [],
    this.coverColor,
    required this.createdAt,
    required this.updatedAt,
    required this.pageIds,
    this.defaultPaper = Paper.dots,
    this.theme = 'paper',
    this.locked = false,
    this.pinned = false,
    this.trashedAt,
    Json? extra,
    Json? extraDefaults,
  })  : extra = extra ?? {},
        extraDefaults = extraDefaults ?? {};

  final String id;
  String title;
  List<String> folderPath;
  String? coverColor;
  final DateTime createdAt;
  DateTime updatedAt;
  final List<String> pageIds;
  Paper defaultPaper;
  String theme;

  /// The whole notebook has a password (see lock.json).
  bool locked;

  /// Shown under Pinned on the Start page.
  bool pinned;

  /// In the Trash since then; null when not deleted.
  DateTime? trashedAt;
  final Json extra;
  final Json extraDefaults;
}

class BoardPage {
  BoardPage({
    required this.id,
    this.title = '',
    this.paper = Paper.dots,
    this.template,
    this.locked = false,
    List<Item>? items,
    Json? extra,
  })  : items = items ?? [],
        extra = extra ?? {};

  final String id;
  String title;
  Paper paper;

  /// Built-in template id (e.g. `cornell`) drawn under the ink, or null.
  Object? template;

  /// Has its own password (see lock.json).
  bool locked;

  /// In z-order: later items draw on top.
  final List<Item> items;
  final Json extra;
}

/// One sample of pen input. `x`/`y` are relative to the stroke item's
/// `x`/`y`; `t` is milliseconds since the stroke started.
class InkPoint {
  const InkPoint(this.x, this.y, this.pressure, this.t);

  final double x;
  final double y;
  final double pressure;
  final int t;
}

enum InkTool { pen, marker }

enum PenType { ballpoint, fountain, pencil }

/// Arrowhead drawings (Arrows.dc.html): open chevron, filled triangle, or a
/// chevron with the stroke's own pressure taper.
enum ArrowStyle { open, filled, ink }

/// Arrowheads on a stroke's first and/or last point.
@immutable
class ArrowHeads {
  const ArrowHeads({this.start = false, this.end = false, this.style = ArrowStyle.open});

  final bool start;
  final bool end;
  final ArrowStyle style;

  Json toJson() => {if (start) 'start': true, if (end) 'end': true, 'style': style.name};

  static ArrowHeads? fromJson(Object? json) {
    if (json is! Map) return null;
    final heads = ArrowHeads(
      start: json['start'] == true,
      end: json['end'] == true,
      style: ArrowStyle.values.firstWhere((s) => s.name == json['style'], orElse: () => ArrowStyle.open),
    );
    return heads.start || heads.end ? heads : null;
  }

  @override
  bool operator ==(Object other) =>
      other is ArrowHeads && other.start == start && other.end == end && other.style == style;

  @override
  int get hashCode => Object.hash(start, end, style);
}

/// Everything on a page is an item with a stable id.
sealed class Item {
  Item({
    required this.id,
    required this.x,
    required this.y,
    this.rotation = 0,
    required this.z,
    required this.createdAt,
    this.author = localAuthor,
    this.remember,
    Json? extra,
  }) : extra = extra ?? const {};

  final String id;
  final double x;
  final double y;
  final double rotation;
  final int z;
  final DateTime createdAt;
  final String author;
  final Json? remember;

  /// Unknown fields, written back on save.
  final Json extra;

  String get type;

  /// Page-space bounds of everything the item paints (with any shadow or
  /// label), used for culling and hit testing.
  Rect get bounds;

  /// Page-space bounds of the item itself, used for the selection outline
  /// and "whole board".
  Rect get extent => bounds;

  Json toJson();

  /// Items are immutable, so each one is encoded once and reused by every
  /// later save of its page.
  late final String encoded = jsonEncode(toJson());

  Json baseJson() => {
        ...extra,
        'id': id,
        'type': type,
        'x': round1(x),
        'y': round1(y),
        'rotation': rotation,
        'z': z,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'author': author,
        'remember': remember,
      };
}

class StrokeItem extends Item {
  StrokeItem({
    required super.id,
    required super.x,
    required super.y,
    super.rotation,
    required super.z,
    required super.createdAt,
    super.author,
    super.remember,
    super.extra,
    required this.tool,
    this.penType = PenType.ballpoint,
    required this.color,
    required this.width,
    required this.points,
    this.usePressure = true,
    this.arrow,
    this.straightened,
    this.startItemId,
    this.endItemId,
  });

  /// Builds a stroke from page-space points, storing them relative to the
  /// top-left of their bounds.
  factory StrokeItem.fromPagePoints({
    required String id,
    required int z,
    required DateTime createdAt,
    required InkTool tool,
    required PenType penType,
    required Color color,
    required double width,
    required bool usePressure,
    required List<InkPoint> pagePoints,
    ArrowHeads? arrow,
    String? straightened,
    String? startItemId,
    String? endItemId,
  }) {
    final (ox, oy, points) = _relative(pagePoints);
    return StrokeItem(
      startItemId: startItemId,
      endItemId: endItemId,
      id: id,
      x: ox,
      y: oy,
      z: z,
      createdAt: createdAt,
      tool: tool,
      penType: penType,
      color: color,
      width: width,
      usePressure: usePressure,
      arrow: arrow,
      straightened: straightened,
      points: points,
    );
  }

  static (double, double, List<InkPoint>) _relative(List<InkPoint> pagePoints) {
    var minX = double.infinity, minY = double.infinity;
    for (final p in pagePoints) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
    }
    final ox = round1(minX), oy = round1(minY);
    return (
      ox,
      oy,
      [for (final p in pagePoints) InkPoint(round1(p.x - ox), round1(p.y - oy), round3(p.pressure), p.t)],
    );
  }

  /// The same stroke (same id, z and metadata) with changes. [pagePoints]
  /// replaces the points (page space); [shape] sets or clears `straightened`.
  StrokeItem copyWith({
    String? id,
    List<InkPoint>? pagePoints,
    Color? color,
    double? width,
    ArrowHeads? Function()? arrow,
    String? Function()? shape,
    String? Function()? startItemId,
    String? Function()? endItemId,
  }) {
    final (ox, oy, pts) = pagePoints == null ? (x, y, points) : _relative(pagePoints);
    return StrokeItem(
      id: id ?? this.id,
      x: ox,
      y: oy,
      rotation: rotation,
      z: z,
      createdAt: createdAt,
      author: author,
      remember: remember,
      extra: extra,
      tool: tool,
      penType: penType,
      color: color ?? this.color,
      width: width ?? this.width,
      points: pts,
      usePressure: usePressure,
      arrow: arrow == null ? this.arrow : arrow(),
      straightened: shape == null ? straightened : shape(),
      startItemId: startItemId == null ? this.startItemId : startItemId(),
      endItemId: endItemId == null ? this.endItemId : endItemId(),
    );
  }

  /// Points in page space, with pressure and time.
  List<InkPoint> get pageInk => [for (final p in points) InkPoint(x + p.x, y + p.y, p.pressure, p.t)];

  /// The same stroke with every point moved by [f] and its width multiplied
  /// by [widthScale]. Used to put ink on a sticky note and take it off.
  StrokeItem mapped(Offset Function(Offset p) f, {double widthScale = 1, String? id}) {
    InkPoint move(InkPoint p) {
      final q = f(Offset(p.x, p.y));
      return InkPoint(q.dx, q.dy, p.pressure, p.t);
    }

    return copyWith(id: id, pagePoints: [for (final p in pageInk) move(p)], width: width * widthScale);
  }

  final InkTool tool;
  final PenType penType;
  final Color color;

  /// Nominal width in page px at medium pressure.
  final double width;
  final List<InkPoint> points;
  final bool usePressure;

  /// Arrowheads made by a flick back at either end, or null.
  final ArrowHeads? arrow;

  /// The shape a hold turned this stroke into (`line`, `circle`, `ellipse`,
  /// `rect`, `triangle`), or null for freehand ink.
  final String? straightened;

  /// The items a connector's first and last points are attached to (on
  /// their edge), or null. The stroke follows them when they move.
  final String? startItemId;
  final String? endItemId;

  /// An arrow or a straight line: what can join two things on the page.
  bool get isConnector => arrow != null || straightened == 'line';

  bool get isAttached => startItemId != null || endItemId != null;

  /// How big the dot at an attached end is (Arrows.dc.html: 5 for 3.5).
  double get attachDotRadius => math.max(3.5, width * 1.43);

  @override
  String get type => 'stroke';

  /// Points in page space.
  Iterable<Offset> get pagePoints => points.map((p) => Offset(x + p.x, y + p.y));

  /// Widest the stroke can render, used to pad bounds and hit tests.
  double get maxWidth => width * 1.8;

  @override
  late final Rect bounds = () {
    var maxX = 0.0, maxY = 0.0;
    for (final p in points) {
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    // Arrowheads reach up to their length past the end points, and the dot
    // at an attached end past the line's width.
    var pad = arrow == null ? maxWidth / 2 + 1 : arrowHeadLength(width) + maxWidth / 2 + 1;
    if (isAttached) pad = math.max(pad, attachDotRadius + 1);
    return Rect.fromLTRB(x, y, x + maxX, y + maxY).inflate(pad);
  }();

  @override
  Json toJson() => {
        ...baseJson(),
        'tool': tool.name,
        'penType': penType.name,
        'color': colorToHex(color),
        'width': width,
        'usePressure': usePressure,
        if (arrow != null) 'arrow': arrow!.toJson(),
        if (straightened != null) 'straightened': straightened,
        if (startItemId != null) 'startItemId': startItemId,
        if (endItemId != null) 'endItemId': endItemId,
        'points': [
          for (final p in points) [p.x, p.y, p.pressure, p.t],
        ],
      };
}

/// An item with a box. `x`/`y` is the top-left corner before rotation, and
/// `rotation` (degrees, clockwise) turns the box about its center.
sealed class BoxItem extends Item {
  BoxItem({
    required super.id,
    required super.x,
    required super.y,
    super.rotation,
    required super.z,
    required super.createdAt,
    super.author,
    super.remember,
    super.extra,
  });

  double get w;
  double get h;

  Offset get center => Offset(x + w / 2, y + h / 2);

  /// Rotation in radians.
  double get angle => rotation * math.pi / 180;

  /// What's painted, relative to the top-left corner before rotation: the
  /// box plus any shadow, label or badge around it.
  Rect get paintRect => Offset.zero & Size(w, h);

  /// The page point for [local], a point relative to the top-left corner.
  Offset toPage(Offset local) => center + _turn(local - Offset(w / 2, h / 2), angle);

  /// [page] relative to the top-left corner, with the rotation taken out.
  Offset toLocal(Offset page) => _turn(page - center, -angle) + Offset(w / 2, h / 2);

  /// Whether [page] is on the box (within [slop]).
  bool contains(Offset page, {double slop = 0}) => (Offset.zero & Size(w, h)).inflate(slop).contains(toLocal(page));

  /// Top-left, top-right, bottom-right and bottom-left, in page space.
  List<Offset> get corners => [toPage(Offset.zero), toPage(Offset(w, 0)), toPage(Offset(w, h)), toPage(Offset(0, h))];

  @override
  late final Rect extent = _around(Offset.zero & Size(w, h));

  @override
  late final Rect bounds = _around(paintRect);

  Rect _around(Rect local) {
    final pts = [local.topLeft, local.topRight, local.bottomRight, local.bottomLeft].map(toPage).toList();
    var r = Rect.fromPoints(pts[0], pts[1]);
    for (final p in pts.skip(2)) {
      r = r.expandToInclude(Rect.fromPoints(p, p));
    }
    return r;
  }

  /// The same item in a new box. [scale] also scales what's inside (text
  /// size, ink on a sticky note, line widths). A new [id] makes it a copy.
  BoxItem withBox({
    String? id,
    int? z,
    DateTime? createdAt,
    required double x,
    required double y,
    required double w,
    required double h,
    double? rotation,
    double scale = 1,
  });

  /// Centered on [center], scaled by [scale] and turned to [rotation].
  BoxItem placed({
    required Offset center,
    double? rotation,
    double scale = 1,
    String? id,
    int? z,
    DateTime? createdAt,
  }) =>
      withBox(
        id: id,
        z: z,
        createdAt: createdAt,
        x: center.dx - w * scale / 2,
        y: center.dy - h * scale / 2,
        w: w * scale,
        h: h * scale,
        rotation: rotation,
        scale: scale,
      );

  Json boxJson() => {...baseJson(), 'w': round1(w), 'h': round1(h)};
}

Offset _turn(Offset p, double a) {
  if (a == 0) return p;
  final c = math.cos(a), s = math.sin(a);
  return Offset(c * p.dx - s * p.dy, s * p.dx + c * p.dy);
}

/// The fonts a text box can use (`font` in the file).
const textFonts = {'ui': FontFamilies.ui, 'serif': FontFamilies.serif, 'hand': FontFamilies.handwritingSample};

/// A text box wraps here until it's stretched to a width.
const textAutoWrap = 480.0;

TextStyle textStyleFor(String font, double size, {Color? color}) => TextStyle(
      fontFamily: textFonts[font] ?? FontFamilies.ui,
      fontSize: size,
      height: 1.3,
      fontWeight: FontWeight.w400,
      color: color,
    );

/// [text] laid out the way a text box shows it, wrapped at [wrap].
TextPainter layoutText(String text, String font, double size, double wrap, {Color? color}) => TextPainter(
      text: TextSpan(text: text.isEmpty ? ' ' : text, style: textStyleFor(font, size, color: color)),
      textDirection: TextDirection.ltr,
      textWidthBasis: TextWidthBasis.longestLine,
    )..layout(maxWidth: math.max(wrap, size));

/// Typed text. `w` in the file is where it wraps; with `autoWidth` the box
/// hugs the text (a new box, until it's stretched).
class TextItem extends BoxItem {
  TextItem({
    required super.id,
    required super.x,
    required super.y,
    super.rotation,
    required super.z,
    required super.createdAt,
    super.author,
    super.remember,
    super.extra,
    required this.wrap,
    required this.text,
    this.font = 'ui',
    this.size = 22,
    required this.color,
    this.autoWidth = false,
  });

  final double wrap;
  final String text;

  /// `ui`, `serif` or `hand`.
  final String font;
  final double size;
  final Color color;
  final bool autoWidth;

  late final Size _size = () {
    final painter = layoutText(text, font, size, wrap);
    final box = Size(autoWidth ? painter.width.ceilToDouble() + 1 : wrap, painter.height);
    painter.dispose();
    return box;
  }();

  @override
  double get w => _size.width;

  @override
  double get h => _size.height;

  @override
  String get type => 'text';

  TextItem copyWith({String? text, String? font, double? size, Color? color, double? x, double? y}) => TextItem(
        id: id,
        x: x ?? this.x,
        y: y ?? this.y,
        rotation: rotation,
        z: z,
        createdAt: createdAt,
        author: author,
        remember: remember,
        extra: extra,
        wrap: wrap,
        text: text ?? this.text,
        font: font ?? this.font,
        size: size ?? this.size,
        color: color ?? this.color,
        autoWidth: autoWidth,
      );

  @override
  TextItem withBox({
    String? id,
    int? z,
    DateTime? createdAt,
    required double x,
    required double y,
    required double w,
    required double h,
    double? rotation,
    double scale = 1,
  }) {
    // Stretched to a width (not just scaled or moved): it wraps there now.
    final stretched = scale == 1 && (w - this.w).abs() > 0.01;
    return TextItem(
      id: id ?? this.id,
      x: x,
      y: y,
      rotation: rotation ?? this.rotation,
      z: z ?? this.z,
      createdAt: createdAt ?? this.createdAt,
      author: author,
      remember: remember,
      extra: extra,
      wrap: stretched ? w : wrap * scale,
      text: text,
      font: font,
      size: size * scale,
      color: color,
      autoWidth: autoWidth && !stretched,
    );
  }

  @override
  Json toJson() => {
        ...baseJson(),
        'w': round1(wrap),
        'text': text,
        'font': font,
        'size': round1(size),
        'color': colorToHex(color),
        if (autoWidth) 'autoWidth': true,
      };
}

/// A note under the top one in a stack.
@immutable
class StickyNote {
  const StickyNote({required this.color, this.items = const []});

  final Color color;
  final List<Item> items;

  Json toJson() => {
        'color': colorToHex(color),
        'items': [for (final i in items) i.toJson()],
      };
}

/// A sticky note. Its `items` (ink and typed text) are relative to its
/// top-left corner and move with it. A stack keeps the notes under the top
/// one in `stack.notes`.
class StickyItem extends BoxItem {
  StickyItem({
    required super.id,
    required super.x,
    required super.y,
    super.rotation,
    required super.z,
    required super.createdAt,
    super.author,
    super.remember,
    super.extra,
    required this.w,
    required this.h,
    required this.color,
    this.items = const [],
    this.under = const [],
    int? count,
  }) : count = math.max(count ?? 1, 1 + under.length);

  /// A new note at 100%.
  static const defaultSize = Size(242, 220);

  /// Typed text starts this far in from the note's edges.
  static const padding = 16.0;

  /// Where typed text starts, relative to the top-left corner.
  static const textOrigin = Offset(padding, padding - 2);

  /// Where typed text wraps.
  double get textWrap => math.max(w - 2 * padding, 40);

  @override
  final double w;
  @override
  final double h;
  final Color color;

  /// Ink and typed text on the (top) note.
  final List<Item> items;

  /// The other notes of a stack, from just under the top one down.
  final List<StickyNote> under;

  /// How many notes: 1, or more for a stack.
  final int count;

  bool get isStack => count > 1;

  @override
  Rect get paintRect => (Offset.zero & Size(w, h)).inflate(isStack ? 34 : 24);

  /// The typed text on the note ('' if none).
  String get text => items.whereType<TextItem>().firstOrNull?.text ?? '';

  Iterable<StrokeItem> get ink => items.whereType<StrokeItem>();

  /// The ink in page space, with the ids it has on the note.
  late final List<StrokeItem> pageInk = [for (final s in ink) s.mapped(toPage)];

  @override
  String get type => 'sticky';

  StickyItem copyWith({Color? color, List<Item>? items, List<StickyNote>? under, int? count, double? rotation}) =>
      StickyItem(
        id: id,
        x: x,
        y: y,
        rotation: rotation ?? this.rotation,
        z: z,
        createdAt: createdAt,
        author: author,
        remember: remember,
        extra: extra,
        w: w,
        h: h,
        color: color ?? this.color,
        items: items ?? this.items,
        under: under ?? this.under,
        count: count ?? (under == null ? this.count : 1 + under.length),
      );

  /// With [text] typed on the note (or without typed text, for '').
  StickyItem withText(String text, {required Color color, required DateTime at, String? font, double? size}) {
    final rest = [for (final i in items) if (i is! TextItem) i];
    if (text.isEmpty) return copyWith(items: rest);
    final typed = items.whereType<TextItem>().firstOrNull?.copyWith(text: text, font: font, size: size) ??
        TextItem(
          id: newId('it'),
          x: textOrigin.dx,
          y: textOrigin.dy,
          z: 0,
          createdAt: at,
          wrap: textWrap,
          text: text,
          font: font ?? 'ui',
          size: size ?? 20,
          color: color,
        );
    return copyWith(items: [typed, ...rest]);
  }

  /// With [stroke] (in page space) written on the note.
  StickyItem withInk(StrokeItem stroke) => copyWith(items: [...items, stroke.mapped(toLocal)]);

  /// With the ink [before] swapped for [after] (in page space).
  StickyItem replaceInk(String before, StrokeItem after) => copyWith(
        items: [for (final i in items) i.id == before ? after.mapped(toLocal, id: before) : i],
      );

  StickyItem withoutInk(Set<String> ids) => copyWith(items: [for (final i in items) if (!ids.contains(i.id)) i]);

  @override
  StickyItem withBox({
    String? id,
    int? z,
    DateTime? createdAt,
    required double x,
    required double y,
    required double w,
    required double h,
    double? rotation,
    double scale = 1,
  }) {
    final copy = id != null && id != this.id;
    List<Item> inside(List<Item> list) => [
          for (final i in list)
            switch (i) {
              StrokeItem s when scale != 1 || copy =>
                s.mapped((p) => p * scale, widthScale: scale, id: copy ? newId('it') : null),
              TextItem t => t.withBox(
                  id: copy ? newId('it') : null,
                  x: t.x * scale,
                  y: t.y * scale,
                  // Typed text wraps at the note's edge.
                  w: scale == 1 ? math.max(w - 2 * padding, 40) : t.wrap * scale,
                  h: t.h * scale,
                  scale: scale,
                ),
              _ => i,
            },
        ];
    return StickyItem(
      id: id ?? this.id,
      x: x,
      y: y,
      rotation: rotation ?? this.rotation,
      z: z ?? this.z,
      createdAt: createdAt ?? this.createdAt,
      author: author,
      remember: remember,
      extra: extra,
      w: w,
      h: h,
      color: color,
      items: inside(items),
      under: [for (final n in under) StickyNote(color: n.color, items: inside(n.items))],
      count: count,
    );
  }

  @override
  Json toJson() => {
        ...boxJson(),
        'color': colorToHex(color),
        'items': [for (final i in items) i.toJson()],
        if (isStack)
          'stack': {
            'count': count,
            if (under.isNotEmpty) 'notes': [for (final n in under) n.toJson()],
          },
      };
}

/// A sheet of paper on the endless page (`lined-a4`, `grid-a4`, `dots-a4`
/// or `blank-a4`), or a template's layout. Ink on it is ordinary page ink.
class FrameItem extends BoxItem {
  FrameItem({
    required super.id,
    required super.x,
    required super.y,
    super.rotation,
    required super.z,
    required super.createdAt,
    super.author,
    super.remember,
    super.extra,
    required this.w,
    required this.h,
    this.paper = 'lined-a4',
    this.title = '',
    this.template,
    this.unit = 1,
  });

  /// A new A4 sheet at 100%: 560 × 792 page px, ruled every 40.
  static const a4 = Size(560, 792);

  @override
  final double w;
  @override
  final double h;
  final String paper;

  /// The name shown above it; '' shows the paper's name.
  final String title;

  /// A built-in template layout drawn on the sheet, or null.
  final String? template;

  /// How much the sheet has been scaled: its rules are 40 × [unit] apart.
  final double unit;

  @override
  Rect get paintRect => Rect.fromLTRB(-24, -30, w + 24, h + 32);

  @override
  String get type => 'frame';

  FrameItem copyWith({String? title}) => FrameItem(
        id: id,
        x: x,
        y: y,
        rotation: rotation,
        z: z,
        createdAt: createdAt,
        author: author,
        remember: remember,
        extra: extra,
        w: w,
        h: h,
        paper: paper,
        title: title ?? this.title,
        template: template,
        unit: unit,
      );

  @override
  FrameItem withBox({
    String? id,
    int? z,
    DateTime? createdAt,
    required double x,
    required double y,
    required double w,
    required double h,
    double? rotation,
    double scale = 1,
  }) =>
      FrameItem(
        id: id ?? this.id,
        x: x,
        y: y,
        rotation: rotation ?? this.rotation,
        z: z ?? this.z,
        createdAt: createdAt ?? this.createdAt,
        author: author,
        remember: remember,
        extra: extra,
        w: w,
        h: h,
        paper: paper,
        title: title,
        template: template,
        unit: unit * scale,
      );

  @override
  Json toJson() => {
        ...boxJson(),
        'paper': paper,
        'title': title,
        if (template != null) 'template': template,
        if (unit != 1) 'unit': round3(unit),
      };
}

/// A picture. `asset` names its file in the package's `assets/` folder.
class ImageItem extends BoxItem {
  ImageItem({
    required super.id,
    required super.x,
    required super.y,
    super.rotation,
    required super.z,
    required super.createdAt,
    super.author,
    super.remember,
    super.extra,
    required this.w,
    required this.h,
    required this.asset,
  });

  @override
  final double w;
  @override
  final double h;
  final String asset;

  /// The `assets/` file that is drawn.
  String get picture => asset;

  @override
  String get type => 'image';

  @override
  ImageItem withBox({
    String? id,
    int? z,
    DateTime? createdAt,
    required double x,
    required double y,
    required double w,
    required double h,
    double? rotation,
    double scale = 1,
  }) =>
      ImageItem(
        id: id ?? this.id,
        x: x,
        y: y,
        rotation: rotation ?? this.rotation,
        z: z ?? this.z,
        createdAt: createdAt ?? this.createdAt,
        author: author,
        remember: remember,
        extra: extra,
        w: w,
        h: h,
        asset: asset,
      );

  @override
  Json toJson() => {...boxJson(), 'asset': asset};
}

/// One page of a file on the board, written on like a picture: an imported
/// PDF page. `asset` is the file itself, [preview] a picture of [page] made
/// from it when it was imported, and [text] the page's own text, kept so it
/// stays searchable.
class FileItem extends ImageItem {
  FileItem({
    required super.id,
    required super.x,
    required super.y,
    super.rotation,
    required super.z,
    required super.createdAt,
    super.author,
    super.remember,
    super.extra,
    required super.w,
    required super.h,
    required super.asset,
    required this.mime,
    this.page,
    this.preview,
    this.name = '',
    this.text = '',
  });

  /// `pdf` (later `docx`, `pptx`, `xlsx`).
  final String mime;

  /// Which page of the file, from 1.
  final int? page;

  /// The picture of the page in `assets/`, or null if there is none.
  final String? preview;

  /// The file's name when it was imported ("Lecture 3.pdf").
  final String name;
  final String text;

  @override
  String get picture => preview ?? '';

  @override
  String get type => 'file';

  @override
  FileItem withBox({
    String? id,
    int? z,
    DateTime? createdAt,
    required double x,
    required double y,
    required double w,
    required double h,
    double? rotation,
    double scale = 1,
  }) =>
      FileItem(
        id: id ?? this.id,
        x: x,
        y: y,
        rotation: rotation ?? this.rotation,
        z: z ?? this.z,
        createdAt: createdAt ?? this.createdAt,
        author: author,
        remember: remember,
        extra: extra,
        w: w,
        h: h,
        asset: asset,
        mime: mime,
        page: page,
        preview: preview,
        name: name,
        text: text,
      );

  @override
  Json toJson() => {
        ...boxJson(),
        'asset': asset,
        'mime': mime,
        if (page != null) 'page': page,
        if (preview != null) 'preview': preview,
        if (name.isNotEmpty) 'name': name,
        if (text.isNotEmpty) 'text': text,
      };
}

enum ShapeType { rect, ellipse, triangle, line, arrow }

/// A drawn shape. Lines and arrows run along the middle of the box from
/// its left edge to its right, so their direction is the rotation.
class ShapeItem extends BoxItem {
  ShapeItem({
    required super.id,
    required super.x,
    required super.y,
    super.rotation,
    required super.z,
    required super.createdAt,
    super.author,
    super.remember,
    super.extra,
    required this.kind,
    required this.w,
    required this.h,
    required this.stroke,
    this.fill,
    this.strokeWidth = 2.5,
  });

  final ShapeType kind;
  @override
  final double w;
  @override
  final double h;
  final Color stroke;
  final Color? fill;
  final double strokeWidth;

  /// Lines and arrows have a length but no height.
  bool get isLine => kind == ShapeType.line || kind == ShapeType.arrow;

  @override
  Rect get paintRect => (Offset.zero & Size(w, h))
      .inflate(strokeWidth / 2 + (kind == ShapeType.arrow ? arrowHeadLength(strokeWidth) : 1));

  @override
  String get type => 'shape';

  ShapeItem copyWith({Color? stroke}) => ShapeItem(
        id: id,
        x: x,
        y: y,
        rotation: rotation,
        z: z,
        createdAt: createdAt,
        author: author,
        remember: remember,
        extra: extra,
        kind: kind,
        w: w,
        h: h,
        stroke: stroke ?? this.stroke,
        fill: fill,
        strokeWidth: strokeWidth,
      );

  @override
  ShapeItem withBox({
    String? id,
    int? z,
    DateTime? createdAt,
    required double x,
    required double y,
    required double w,
    required double h,
    double? rotation,
    double scale = 1,
  }) =>
      ShapeItem(
        id: id ?? this.id,
        x: x,
        y: y,
        rotation: rotation ?? this.rotation,
        z: z ?? this.z,
        createdAt: createdAt ?? this.createdAt,
        author: author,
        remember: remember,
        extra: extra,
        kind: kind,
        w: w,
        h: isLine ? 0 : h,
        stroke: stroke,
        fill: fill,
        strokeWidth: strokeWidth * scale,
      );

  @override
  Json toJson() => {
        ...boxJson(),
        'kind': kind.name,
        'stroke': colorToHex(stroke),
        'fill': fill == null ? null : colorToHex(fill!),
        'strokeWidth': round1(strokeWidth),
      };
}

/// What a card built on the board holds: a Kanban board, a timeline, a
/// diagram, a table or a website. Each is an item type of its own in the
/// file (`kanban`, `timeline`, `diagram`, `table`, `embed`).
sealed class CardData {
  const CardData();

  /// The item's `type`.
  String get type;

  /// The fields of this type, for the item's JSON.
  Json toJson();

  /// The type-specific fields, to tell them from unknown ones.
  Set<String> get keys;
}

/// A card on a Kanban board. Fields this version doesn't know are kept.
@immutable
class KanbanCard {
  const KanbanCard(this.text, {this.extra = const {}});

  final String text;
  final Json extra;

  Json toJson() => {...extra, 'text': text};
}

@immutable
class KanbanColumn {
  const KanbanColumn(this.title, [this.cards = const [], this.extra = const {}]);

  final String title;
  final List<KanbanCard> cards;
  final Json extra;

  Json toJson() => {...extra, 'title': title, 'cards': [for (final c in cards) c.toJson()]};
}

/// Columns of cards. Cards in the last column are done (struck through);
/// those between the first and the last are in progress.
class KanbanData extends CardData {
  const KanbanData(this.columns);

  final List<KanbanColumn> columns;

  @override
  String get type => 'kanban';

  @override
  Set<String> get keys => const {'columns'};

  @override
  Json toJson() => {'columns': [for (final c in columns) c.toJson()]};
}

/// Where a timeline's event stands: behind you, up next, or still to come.
enum EventState { done, now, later }

@immutable
class TimelineEvent {
  const TimelineEvent({required this.date, required this.label, this.state = EventState.later, this.extra = const {}});

  /// When, as shown ("Sep 30").
  final String date;
  final String label;
  final EventState state;
  final Json extra;

  Json toJson() => {...extra, 'date': date, 'label': label, 'state': state.name};
}

class TimelineData extends CardData {
  const TimelineData(this.events);

  final List<TimelineEvent> events;

  @override
  String get type => 'timeline';

  @override
  Set<String> get keys => const {'events'};

  @override
  Json toJson() => {'events': [for (final e in events) e.toJson()]};
}

/// A step's outline: a box, a pill (start and end), or a decision diamond.
enum NodeShape { box, pill, diamond }

/// A step's color, by palette role so it follows the theme and dark mode.
enum NodeColor { blue, clay, green, plum }

@immutable
class DiagramNode {
  const DiagramNode({
    required this.id,
    required this.text,
    this.shape = NodeShape.box,
    this.color = NodeColor.blue,
    this.extra = const {},
  });

  final String id;
  final String text;
  final NodeShape shape;
  final NodeColor color;
  final Json extra;

  Json toJson() => {...extra, 'id': id, 'text': text, 'shape': shape.name, 'color': color.name};
}

/// Steps and the arrows between them. The steps are laid out in order, left
/// to right; `edges` name the steps each arrow joins.
class DiagramData extends CardData {
  const DiagramData(this.nodes, this.edges);

  /// Steps joined one after the other.
  factory DiagramData.flow(List<DiagramNode> nodes) =>
      DiagramData(nodes, [for (var i = 0; i + 1 < nodes.length; i++) (nodes[i].id, nodes[i + 1].id)]);

  final List<DiagramNode> nodes;
  final List<(String, String)> edges;

  @override
  String get type => 'diagram';

  @override
  Set<String> get keys => const {'nodes', 'edges'};

  @override
  Json toJson() => {
        'nodes': [for (final n in nodes) n.toJson()],
        'edges': [
          for (final (from, to) in edges) {'from': from, 'to': to},
        ],
      };
}

/// Rows of cells. With [header], the first row is the column names.
class TableData extends CardData {
  const TableData(this.cells, {this.header = true});

  final List<List<String>> cells;
  final bool header;

  int get rows => cells.length;
  int get columns => cells.isEmpty ? 0 : cells.map((r) => r.length).reduce(math.max);

  @override
  String get type => 'table';

  @override
  Set<String> get keys => const {'cells', 'header'};

  @override
  Json toJson() => {'cells': cells, 'header': header};
}

/// A website on the board.
class EmbedData extends CardData {
  const EmbedData(this.url);

  final String url;

  /// The address as a link that may be opened: http or https only.
  Uri? get link {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty || (uri.scheme != 'http' && uri.scheme != 'https')) return null;
    return uri;
  }

  /// The site's name as shown on the card: "example.com".
  String get host {
    final h = link?.host ?? url.trim();
    return h.startsWith('www.') ? h.substring(4) : h;
  }

  /// [typed] as a web address: "example.com/lab" becomes
  /// "https://example.com/lab". Null if it isn't one.
  static String? normalize(String typed) {
    final t = typed.trim();
    if (t.isEmpty || t.contains(' ')) return null;
    final withScheme = t.contains('://') ? t : 'https://$t';
    final data = EmbedData(withScheme);
    final uri = data.link;
    return uri == null || !uri.host.contains('.') ? null : uri.toString();
  }

  @override
  String get type => 'embed';

  @override
  Set<String> get keys => const {'url'};

  @override
  Json toJson() => {'url': url};
}

/// A card built on the board (Board.dc.html): a header with its name, and
/// its [data] drawn underneath. `unit` is how much the card is scaled: its
/// text and spacing are the design's sizes times `unit`.
class CardItem extends BoxItem {
  CardItem({
    required super.id,
    required super.x,
    required super.y,
    super.rotation,
    required super.z,
    required super.createdAt,
    super.author,
    super.remember,
    super.extra,
    required this.w,
    required this.h,
    required this.data,
    this.title = '',
    this.unit = defaultUnit,
  });

  /// New cards are drawn at this scale, so they read well and their parts
  /// are big enough to touch at 100%.
  static const defaultUnit = 1.375;

  @override
  final double w;
  @override
  final double h;
  final CardData data;
  final String title;
  final double unit;

  @override
  Rect get paintRect => (Offset.zero & Size(w, h)).inflate(30 * unit);

  @override
  String get type => data.type;

  CardItem copyWith({CardData? data, String? title, double? h}) => CardItem(
        id: id,
        x: x,
        y: y,
        rotation: rotation,
        z: z,
        createdAt: createdAt,
        author: author,
        remember: remember,
        extra: extra,
        w: w,
        h: h ?? this.h,
        data: data ?? this.data,
        title: title ?? this.title,
        unit: unit,
      );

  @override
  CardItem withBox({
    String? id,
    int? z,
    DateTime? createdAt,
    required double x,
    required double y,
    required double w,
    required double h,
    double? rotation,
    double scale = 1,
  }) =>
      CardItem(
        id: id ?? this.id,
        x: x,
        y: y,
        rotation: rotation ?? this.rotation,
        z: z ?? this.z,
        createdAt: createdAt ?? this.createdAt,
        author: author,
        remember: remember,
        extra: extra,
        w: w,
        h: h,
        data: data,
        title: title,
        unit: unit * scale,
      );

  @override
  Json toJson() => {...boxJson(), 'title': title, 'unit': round3(unit), ...data.toJson()};
}

/// An item type this version can't show yet. Kept verbatim.
class UnknownItem extends Item {
  UnknownItem(this.raw)
      : super(
          id: raw['id'] as String? ?? '',
          x: (raw['x'] as num?)?.toDouble() ?? 0,
          y: (raw['y'] as num?)?.toDouble() ?? 0,
          z: (raw['z'] as num?)?.toInt() ?? 0,
          createdAt: DateTime.tryParse(raw['createdAt'] as String? ?? '') ?? DateTime.utc(1970),
        );

  final Json raw;

  @override
  String get type => raw['type'] as String? ?? 'unknown';

  @override
  Rect get bounds => Rect.fromLTWH(
        x,
        y,
        (raw['w'] as num?)?.toDouble() ?? 1,
        (raw['h'] as num?)?.toDouble() ?? 1,
      );

  @override
  Json toJson() => raw;
}

/// Length of an arrowhead's sides for a stroke of [width].
double arrowHeadLength(double width) => (10 + width * 4).clamp(14, 48).toDouble();

double round1(double v) => (v * 10).roundToDouble() / 10;

double round3(double v) => (v * 1000).roundToDouble() / 1000;

String colorToHex(Color c) {
  final argb = c.toARGB32();
  final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
  final a = argb >>> 24;
  return a == 0xFF ? '#$rgb' : '#${a.toRadixString(16).padLeft(2, '0').toUpperCase()}$rgb';
}

Color colorFromHex(String hex) {
  var h = hex.replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  return Color(int.parse(h, radix: 16));
}
