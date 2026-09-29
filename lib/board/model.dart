import 'dart:convert';
import 'dart:ui';

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
  bool locked;
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
  Object? template;
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
  }) {
    var minX = double.infinity, minY = double.infinity;
    for (final p in pagePoints) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
    }
    final ox = round1(minX), oy = round1(minY);
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
      points: [
        for (final p in pagePoints) InkPoint(round1(p.x - ox), round1(p.y - oy), round3(p.pressure), p.t),
      ],
    );
  }

  final InkTool tool;
  final PenType penType;
  final Color color;

  /// Nominal width in page px at medium pressure.
  final double width;
  final List<InkPoint> points;
  final bool usePressure;

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
    return Rect.fromLTRB(x, y, x + maxX, y + maxY).inflate(maxWidth / 2 + 1);
  }();

  @override
  Json toJson() => {
        ...baseJson(),
        'tool': tool.name,
        'penType': penType.name,
        'color': colorToHex(color),
        'width': width,
        'usePressure': usePressure,
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
