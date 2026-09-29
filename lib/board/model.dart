import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart' show immutable;

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

  /// Page-space bounds, used for culling and hit testing.
  Rect get bounds;

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
    List<InkPoint>? pagePoints,
    Color? color,
    double? width,
    ArrowHeads? Function()? arrow,
    String? Function()? shape,
  }) {
    final (ox, oy, pts) = pagePoints == null ? (x, y, points) : _relative(pagePoints);
    return StrokeItem(
      id: id,
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
