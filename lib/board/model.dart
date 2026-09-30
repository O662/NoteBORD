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
  }) {
    final (ox, oy, points) = _relative(pagePoints);
    return StrokeItem(
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
    // Arrowheads reach up to their length past the end points.
    final pad = arrow == null ? maxWidth / 2 + 1 : arrowHeadLength(width) + maxWidth / 2 + 1;
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
