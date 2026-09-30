import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/model.dart';
import '../board/store.dart';
import '../canvas/gestures.dart' show ScribbleLevel;
import '../canvas/ruler.dart' show RulerUnit;
import '../canvas/pens.dart';
import '../theme/tokens.g.dart' as tokens;

enum CanvasTool {
  pen,
  marker,
  eraser,
  select,
  lasso,
  laser,
  text,
  sticky,
  stack,
  frame,
  shape;

  /// The pen or marker: tools that put ink down.
  bool get inks => this == pen || this == marker;

  /// Select and lasso.
  bool get selects => this == select || this == lasso;

  /// Tools that put something on the page where you tap: a text box, a
  /// sticky note, a stack of notes, a paper frame or a shape.
  bool get places => this == text || this == sticky || this == stack || this == frame || this == shape;

  /// Tools for a moment (the laser, and the ones that drop something): the
  /// app reopens on the pen instead.
  bool get momentary => this == laser || places;
}

enum LibraryView { grid, list }

/// How the library orders notebooks.
enum LibrarySort { edited, title, created }

/// Tool and chrome preferences. Saved to settings.json.
@immutable
class AppSettings {
  AppSettings({
    this.tool = CanvasTool.pen,
    Color? penColor,
    Color? markerColor,
    this.penSize = 1,
    this.markerSize = 1,
    this.penType = PenType.ballpoint,
    this.pressure = true,
    this.snap = true,
    this.scribble = true,
    this.arrows = true,
    this.arrowStyle = ArrowStyle.open,
    this.scribbleLevel = ScribbleLevel.normal,
    this.laserColor = 0,
    this.rulerUnit = RulerUnit.cm,
    this.shapeKind = ShapeType.rect,
    List<Color>? extraColors,
    this.trayOpen = true,
    this.pagesOpen = true,
    this.mapOpen = true,
    this.fingerDraws = false,
    this.themeMode = ThemeMode.system,
    this.lastNotebookId,
    this.userName,
    this.libraryView = LibraryView.grid,
    this.librarySort = LibrarySort.edited,
  })  : penColor = penColor ?? tokens.inkDefaults[1],
        markerColor = markerColor ?? tokens.extraInkDefaults[3],
        extraColors = List.unmodifiable(extraColors ?? tokens.extraInkDefaults);

  final CanvasTool tool;
  final Color penColor;
  final Color markerColor;
  final int penSize;
  final int markerSize;
  final PenType penType;
  final bool pressure;

  /// Hold at the end of a stroke to straighten it.
  final bool snap;

  /// Scribble over ink to erase it.
  final bool scribble;

  /// Flick back at the end of a line to make an arrow.
  final bool arrows;
  final ArrowStyle arrowStyle;
  final ScribbleLevel scribbleLevel;

  /// Laser pointer color: 0 red, 1 green, 2 blue.
  final int laserColor;

  /// What the ruler's ticks measure.
  final RulerUnit rulerUnit;

  /// The shape the Shapes tool draws.
  final ShapeType shapeKind;

  /// The "More colors" tray, up to [tokens.extraInkMax].
  final List<Color> extraColors;
  final bool trayOpen;
  final bool pagesOpen;
  final bool mapOpen;

  /// Off by default: the pen draws and fingers navigate. Useful without a stylus.
  final bool fingerDraws;
  final ThemeMode themeMode;
  final String? lastNotebookId;

  /// For the Start page greeting ("Welcome back, …").
  final String? userName;
  final LibraryView libraryView;
  final LibrarySort librarySort;

  InkTool get inkTool => tool == CanvasTool.marker ? InkTool.marker : InkTool.pen;

  /// Color of the pen or marker (the eraser shows the pen's).
  Color get color => tool == CanvasTool.marker ? markerColor : penColor;

  int get sizeIndex => tool == CanvasTool.marker ? markerSize : penSize;

  double get strokeWidth => strokeWidthFor(inkTool, sizeIndex);

  AppSettings copyWith({
    CanvasTool? tool,
    Color? penColor,
    Color? markerColor,
    int? penSize,
    int? markerSize,
    PenType? penType,
    bool? pressure,
    bool? snap,
    bool? scribble,
    bool? arrows,
    ArrowStyle? arrowStyle,
    ScribbleLevel? scribbleLevel,
    int? laserColor,
    RulerUnit? rulerUnit,
    ShapeType? shapeKind,
    List<Color>? extraColors,
    bool? trayOpen,
    bool? pagesOpen,
    bool? mapOpen,
    bool? fingerDraws,
    ThemeMode? themeMode,
    String? lastNotebookId,
    String? Function()? userName,
    LibraryView? libraryView,
    LibrarySort? librarySort,
  }) =>
      AppSettings(
        tool: tool ?? this.tool,
        penColor: penColor ?? this.penColor,
        markerColor: markerColor ?? this.markerColor,
        penSize: penSize ?? this.penSize,
        markerSize: markerSize ?? this.markerSize,
        penType: penType ?? this.penType,
        pressure: pressure ?? this.pressure,
        snap: snap ?? this.snap,
        scribble: scribble ?? this.scribble,
        arrows: arrows ?? this.arrows,
        arrowStyle: arrowStyle ?? this.arrowStyle,
        scribbleLevel: scribbleLevel ?? this.scribbleLevel,
        laserColor: laserColor ?? this.laserColor,
        rulerUnit: rulerUnit ?? this.rulerUnit,
        shapeKind: shapeKind ?? this.shapeKind,
        extraColors: extraColors ?? this.extraColors,
        trayOpen: trayOpen ?? this.trayOpen,
        pagesOpen: pagesOpen ?? this.pagesOpen,
        mapOpen: mapOpen ?? this.mapOpen,
        fingerDraws: fingerDraws ?? this.fingerDraws,
        themeMode: themeMode ?? this.themeMode,
        lastNotebookId: lastNotebookId ?? this.lastNotebookId,
        userName: userName == null ? this.userName : userName(),
        libraryView: libraryView ?? this.libraryView,
        librarySort: librarySort ?? this.librarySort,
      );

  Json toJson() => {
        'tool': tool.name,
        'penColor': colorToHex(penColor),
        'markerColor': colorToHex(markerColor),
        'penSize': penSize,
        'markerSize': markerSize,
        'penType': penType.name,
        'pressure': pressure,
        'snap': snap,
        'scribble': scribble,
        'arrows': arrows,
        'arrowStyle': arrowStyle.name,
        'scribbleLevel': scribbleLevel.name,
        'laserColor': laserColor,
        'rulerUnit': rulerUnit.name,
        'shapeKind': shapeKind.name,
        'extraColors': [for (final c in extraColors) colorToHex(c)],
        'trayOpen': trayOpen,
        'pagesOpen': pagesOpen,
        'mapOpen': mapOpen,
        'fingerDraws': fingerDraws,
        'themeMode': themeMode.name,
        'lastNotebookId': lastNotebookId,
        'userName': userName,
        'libraryView': libraryView.name,
        'librarySort': librarySort.name,
      };

  factory AppSettings.fromJson(Json j) {
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.firstWhere((v) => v.name == name, orElse: () => fallback);
    int size(Object? v) => ((v as num?)?.toInt() ?? 1).clamp(0, penSizes.length - 1);
    return AppSettings(
      // The laser and the "tap to drop one" tools are for a moment; the app
      // always reopens on a real tool.
      tool: switch (pick(CanvasTool.values, j['tool'], CanvasTool.pen)) {
        final t when t.momentary => CanvasTool.pen,
        final t => t,
      },
      penColor: j['penColor'] is String ? colorFromHex(j['penColor'] as String) : null,
      markerColor: j['markerColor'] is String ? colorFromHex(j['markerColor'] as String) : null,
      penSize: size(j['penSize']),
      markerSize: size(j['markerSize']),
      penType: pick(PenType.values, j['penType'], PenType.ballpoint),
      pressure: j['pressure'] as bool? ?? true,
      snap: j['snap'] as bool? ?? true,
      scribble: j['scribble'] as bool? ?? true,
      arrows: j['arrows'] as bool? ?? true,
      arrowStyle: pick(ArrowStyle.values, j['arrowStyle'], ArrowStyle.open),
      scribbleLevel: pick(ScribbleLevel.values, j['scribbleLevel'], ScribbleLevel.normal),
      laserColor: ((j['laserColor'] as num?)?.toInt() ?? 0).clamp(0, 2),
      rulerUnit: pick(RulerUnit.values, j['rulerUnit'], RulerUnit.cm),
      shapeKind: pick(ShapeType.values, j['shapeKind'], ShapeType.rect),
      extraColors: (j['extraColors'] as List?)
          ?.whereType<String>()
          .map(colorFromHex)
          .take(tokens.extraInkMax)
          .toList(),
      trayOpen: j['trayOpen'] as bool? ?? true,
      pagesOpen: j['pagesOpen'] as bool? ?? true,
      mapOpen: j['mapOpen'] as bool? ?? true,
      fingerDraws: j['fingerDraws'] as bool? ?? false,
      themeMode: pick(ThemeMode.values, j['themeMode'], ThemeMode.system),
      lastNotebookId: j['lastNotebookId'] as String?,
      userName: j['userName'] as String?,
      libraryView: pick(LibraryView.values, j['libraryView'], LibraryView.grid),
      librarySort: pick(LibrarySort.values, j['librarySort'], LibrarySort.edited),
    );
  }
}

final boardStoreProvider = Provider<BoardStore>((ref) => throw UnimplementedError('Override in bootstrap'));

final initialSettingsProvider = Provider<AppSettings>((ref) => AppSettings());

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class SettingsNotifier extends Notifier<AppSettings> {
  Timer? _saveTimer;
  late BoardStore _store;

  @override
  AppSettings build() {
    // Read now: a save still pending at dispose can't use ref any more.
    _store = ref.read(boardStoreProvider);
    ref.onDispose(() {
      if (_saveTimer?.isActive ?? false) {
        _saveTimer!.cancel();
        _save();
      }
    });
    return ref.read(initialSettingsProvider);
  }

  void apply(AppSettings Function(AppSettings s) change) {
    state = change(state);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _save);
  }

  void _save() => _store.saveSettings(state.toJson());

  /// Picks a color for the pen or marker; from any other tool it switches
  /// to the pen.
  void pickColor(Color c) => apply((s) => switch (s.tool) {
        CanvasTool.marker => s.copyWith(markerColor: c),
        CanvasTool.pen => s.copyWith(penColor: c),
        // Text and shapes take the pen's color, so picking one keeps the tool.
        CanvasTool.text || CanvasTool.shape => s.copyWith(penColor: c),
        _ => s.copyWith(penColor: c, tool: CanvasTool.pen),
      });

  void pickSize(int i) => apply((s) => s.tool == CanvasTool.marker ? s.copyWith(markerSize: i) : s.copyWith(penSize: i));

  /// Adds the next unused color to the tray and selects it.
  void addExtraColor() => apply((s) {
        if (s.extraColors.length >= tokens.extraInkMax) return s;
        final pool = [...tokens.extraInkAddable, ...tokens.extraInkDefaults];
        final next = pool.where((c) => !s.extraColors.contains(c)).firstOrNull;
        if (next == null) return s;
        final updated = s.copyWith(extraColors: [...s.extraColors, next]);
        return switch (s.tool) {
          CanvasTool.marker => updated.copyWith(markerColor: next),
          _ => updated.copyWith(penColor: next, tool: CanvasTool.pen),
        };
      });

  void removeExtraColor(Color c) => apply((s) => s.copyWith(extraColors: [...s.extraColors]..remove(c)));
}
