import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/model.dart';
import '../board/store.dart';
import '../canvas/pens.dart';
import '../theme/tokens.g.dart' as tokens;

enum CanvasTool { pen, marker, eraser }

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
    List<Color>? extraColors,
    this.trayOpen = true,
    this.pagesOpen = true,
    this.mapOpen = true,
    this.fingerDraws = false,
    this.themeMode = ThemeMode.system,
    this.lastNotebookId,
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

  // Stored now; the features behind them arrive in Phase 3.
  final bool snap;
  final bool scribble;
  final bool arrows;

  /// The "More colors" tray, up to [tokens.extraInkMax].
  final List<Color> extraColors;
  final bool trayOpen;
  final bool pagesOpen;
  final bool mapOpen;

  /// Off by default: the pen draws and fingers navigate. Useful without a stylus.
  final bool fingerDraws;
  final ThemeMode themeMode;
  final String? lastNotebookId;

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
    List<Color>? extraColors,
    bool? trayOpen,
    bool? pagesOpen,
    bool? mapOpen,
    bool? fingerDraws,
    ThemeMode? themeMode,
    String? lastNotebookId,
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
        extraColors: extraColors ?? this.extraColors,
        trayOpen: trayOpen ?? this.trayOpen,
        pagesOpen: pagesOpen ?? this.pagesOpen,
        mapOpen: mapOpen ?? this.mapOpen,
        fingerDraws: fingerDraws ?? this.fingerDraws,
        themeMode: themeMode ?? this.themeMode,
        lastNotebookId: lastNotebookId ?? this.lastNotebookId,
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
        'extraColors': [for (final c in extraColors) colorToHex(c)],
        'trayOpen': trayOpen,
        'pagesOpen': pagesOpen,
        'mapOpen': mapOpen,
        'fingerDraws': fingerDraws,
        'themeMode': themeMode.name,
        'lastNotebookId': lastNotebookId,
      };

  factory AppSettings.fromJson(Json j) {
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.firstWhere((v) => v.name == name, orElse: () => fallback);
    int size(Object? v) => ((v as num?)?.toInt() ?? 1).clamp(0, penSizes.length - 1);
    return AppSettings(
      tool: pick(CanvasTool.values, j['tool'], CanvasTool.pen),
      penColor: j['penColor'] is String ? colorFromHex(j['penColor'] as String) : null,
      markerColor: j['markerColor'] is String ? colorFromHex(j['markerColor'] as String) : null,
      penSize: size(j['penSize']),
      markerSize: size(j['markerSize']),
      penType: pick(PenType.values, j['penType'], PenType.ballpoint),
      pressure: j['pressure'] as bool? ?? true,
      snap: j['snap'] as bool? ?? true,
      scribble: j['scribble'] as bool? ?? true,
      arrows: j['arrows'] as bool? ?? true,
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
    );
  }
}

final boardStoreProvider = Provider<BoardStore>((ref) => throw UnimplementedError('Override in bootstrap'));

final initialSettingsProvider = Provider<AppSettings>((ref) => AppSettings());

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class SettingsNotifier extends Notifier<AppSettings> {
  Timer? _saveTimer;

  @override
  AppSettings build() {
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

  void _save() => ref.read(boardStoreProvider).saveSettings(state.toJson());

  /// Picks a color for the pen or marker; from the eraser it switches to the pen.
  void pickColor(Color c) => apply((s) => switch (s.tool) {
        CanvasTool.marker => s.copyWith(markerColor: c),
        CanvasTool.pen => s.copyWith(penColor: c),
        CanvasTool.eraser => s.copyWith(penColor: c, tool: CanvasTool.pen),
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
