import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/ids.dart';
import '../board/model.dart';
import '../state/notebook.dart';
import '../state/settings.dart';
import '../theme/colors.dart';
import '../theme/tokens.g.dart';
import 'page_runtime.dart';
import 'pens.dart';
import 'stroke_geometry.dart';
import 'canvas_view.dart';

/// Eraser radius in screen px.
const eraserRadius = 10.0;

/// Touches this soon after the stylus was seen (hovering or writing) are
/// treated as the palm and ignored.
const palmWindow = Duration(milliseconds: 600);

/// The endless page. Routes raw pointers: the stylus draws, fingers pan and
/// zoom, and touches while the stylus is near are rejected as the palm.
/// A mouse draws with the left button and pans with the others, so the app
/// can be tried on a desktop.
class InkCanvas extends ConsumerStatefulWidget {
  const InkCanvas({super.key, required this.view});

  final CanvasView view;

  @override
  ConsumerState<InkCanvas> createState() => InkCanvasState();
}

class InkCanvasState extends ConsumerState<InkCanvas> {
  final active = ActiveStroke();
  final _hover = ValueNotifier<Offset?>(null);
  Timer? _hoverTimer;

  final _touches = <int, Offset>{};
  final _ignored = <int>{};
  int? _drawPointer;
  bool _fingerDrawing = false;
  bool _erasing = false;
  Offset? _lastErase;
  Duration _strokeStart = Duration.zero;
  Duration? _lastStylus;
  bool _stylusDown = false;
  double _panZoomScale = 1;

  CanvasView get _vp => widget.view;

  @override
  void dispose() {
    _hoverTimer?.cancel();
    active.dispose();
    _hover.dispose();
    super.dispose();
  }

  static bool _isStylus(PointerEvent e) =>
      e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus;

  bool _stylusNear(Duration now) =>
      _stylusDown || (_lastStylus != null && now - _lastStylus! < palmWindow);

  static double _pressure(PointerEvent e) {
    if (!_isStylus(e)) return 0.5;
    final range = e.pressureMax - e.pressureMin;
    if (range <= 0) return 0.5;
    return ((e.pressure - e.pressureMin) / range).clamp(0.0, 1.0);
  }

  void _onDown(PointerDownEvent e) {
    final settings = ref.read(settingsProvider);
    if (_isStylus(e)) {
      _lastStylus = e.timeStamp;
      _stylusDown = true;
      _touches.clear(); // the palm often lands before the pen
      if (_drawPointer != null) _cancelInput();
      final sideButton = e.buttons & (kPrimaryStylusButton | kSecondaryStylusButton) != 0;
      final erase = settings.tool == CanvasTool.eraser || e.kind == PointerDeviceKind.invertedStylus || sideButton;
      _startInput(e, erase: erase);
      return;
    }
    if (e.kind == PointerDeviceKind.mouse) {
      if (e.buttons & kPrimaryMouseButton != 0) {
        _startInput(e, erase: settings.tool == CanvasTool.eraser);
      } else {
        _touches[e.pointer] = e.localPosition;
      }
      return;
    }
    if (_stylusNear(e.timeStamp)) {
      _ignored.add(e.pointer);
      return;
    }
    if (_fingerDrawing && _drawPointer != null) {
      // A second finger means navigate, not draw.
      final first = _drawPointer!;
      final at = active.lastScreen ?? e.localPosition;
      _cancelInput();
      _touches[first] = at;
    } else if (settings.fingerDraws && _touches.isEmpty && _drawPointer == null) {
      _fingerDrawing = true;
      _startInput(e, erase: settings.tool == CanvasTool.eraser);
      return;
    }
    _touches[e.pointer] = e.localPosition;
  }

  void _onMove(PointerMoveEvent e) {
    if (_isStylus(e)) _lastStylus = e.timeStamp;
    if (e.pointer == _drawPointer) {
      _addSample(e);
    } else if (_touches.containsKey(e.pointer)) {
      _navigate(e.pointer, e.localPosition);
    }
  }

  void _onUp(PointerUpEvent e) {
    if (_isStylus(e)) {
      _stylusDown = false;
      _lastStylus = e.timeStamp;
    }
    if (e.pointer == _drawPointer) _finishInput();
    _touches.remove(e.pointer);
    _ignored.remove(e.pointer);
  }

  void _onCancel(PointerCancelEvent e) {
    if (_isStylus(e)) _stylusDown = false;
    if (e.pointer == _drawPointer) _cancelInput();
    _touches.remove(e.pointer);
    _ignored.remove(e.pointer);
  }

  void _onHover(PointerHoverEvent e) {
    if (_isStylus(e)) _lastStylus = e.timeStamp;
    if (_isStylus(e) || e.kind == PointerDeviceKind.mouse) {
      _hover.value = e.localPosition;
      _hoverTimer?.cancel();
      _hoverTimer = Timer(const Duration(milliseconds: 800), () => _hover.value = null);
    }
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      if (HardwareKeyboard.instance.isControlPressed) {
        _vp.zoomAt(e.localPosition, math.exp(-e.scrollDelta.dy / 300));
      } else {
        _vp.panBy(-e.scrollDelta);
      }
    } else if (e is PointerScaleEvent) {
      _vp.zoomAt(e.localPosition, e.scale);
    }
  }

  // Two-finger pan and pinch zoom (one finger pans too).
  void _navigate(int pointer, Offset to) {
    final before = _centroidAndSpread();
    _touches[pointer] = to;
    final after = _centroidAndSpread();
    final factor = before.$2 > 0 && after.$2 > 0 ? after.$2 / before.$2 : 1.0;
    _vp.transform(fromFocal: before.$1, toFocal: after.$1, factor: factor);
  }

  (Offset, double) _centroidAndSpread() {
    var sum = Offset.zero;
    for (final p in _touches.values) {
      sum += p;
    }
    final c = sum / _touches.length.toDouble();
    if (_touches.length < 2) return (c, 0);
    var spread = 0.0;
    for (final p in _touches.values) {
      spread += (p - c).distance;
    }
    return (c, spread / _touches.length);
  }

  void _startInput(PointerDownEvent e, {required bool erase}) {
    final settings = ref.read(settingsProvider);
    _drawPointer = e.pointer;
    _strokeStart = e.timeStamp;
    _hover.value = null;
    final page = _vp.toPage(e.localPosition);
    if (erase) {
      _erasing = true;
      _lastErase = page;
      ref.read(notebookProvider.notifier).beginErase();
      _eraseTo(page);
    } else {
      active.begin(
        tool: settings.inkTool,
        penType: settings.penType,
        color: settings.color,
        width: settings.strokeWidth,
        usePressure: settings.pressure,
      );
      active.add(page, e.localPosition, _pressure(e), 0);
    }
  }

  void _addSample(PointerEvent e) {
    final page = _vp.toPage(e.localPosition);
    if (_erasing) {
      _eraseTo(page);
    } else {
      active.add(page, e.localPosition, _pressure(e), (e.timeStamp - _strokeStart).inMilliseconds);
    }
  }

  void _eraseTo(Offset page) {
    final from = _lastErase ?? page;
    _lastErase = page;
    final r = eraserRadius / _vp.scale;
    final runtime = ref.read(notebookProvider).page;
    final area = Rect.fromPoints(from, page).inflate(r + 30);
    final hits = [
      for (final id in runtime.index.query(area))
        if (runtime[id] case final StrokeItem s when strokeHit(s, from, page, r)) id,
    ];
    if (hits.isNotEmpty) ref.read(notebookProvider.notifier).erase(hits);
  }

  void _finishInput() {
    final notifier = ref.read(notebookProvider.notifier);
    if (_erasing) {
      notifier.endErase();
    } else if (active.isActive) {
      final page = ref.read(notebookProvider).page;
      notifier.addStroke(active.toItem(z: page.nextZ));
      active.clear();
    }
    _resetInput();
  }

  void _cancelInput() {
    if (_erasing) {
      ref.read(notebookProvider.notifier).endErase();
    }
    active.clear();
    _resetInput();
  }

  void _resetInput() {
    _drawPointer = null;
    _erasing = false;
    _lastErase = null;
    _fingerDrawing = false;
  }

  @override
  Widget build(BuildContext context) {
    final notebook = ref.watch(notebookProvider);
    final settings = ref.watch(settingsProvider);
    final colors = context.colors;
    final brightness = Theme.of(context).brightness;
    final page = notebook.page;

    return LayoutBuilder(builder: (context, constraints) {
      _vp.size = constraints.biggest;
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: _onUp,
        onPointerCancel: _onCancel,
        onPointerHover: _onHover,
        onPointerSignal: _onSignal,
        onPointerPanZoomStart: (_) => _panZoomScale = 1,
        onPointerPanZoomUpdate: (e) {
          _vp.zoomAt(e.localPosition, e.scale / _panZoomScale);
          _panZoomScale = e.scale;
          _vp.panBy(e.panDelta);
        },
        child: Stack(fit: StackFit.expand, children: [
          RepaintBoundary(
            child: CustomPaint(painter: PaperPainter(_vp, page.page.paper, colors)),
          ),
          RepaintBoundary(
            child: CustomPaint(
              painter: InkLayerPainter(_vp, page, notebook.revision, brightness, colors),
            ),
          ),
          RepaintBoundary(
            child: CustomPaint(painter: ActiveStrokePainter(active, _vp, brightness)),
          ),
          IgnorePointer(
            child: CustomPaint(
              painter: HoverRingPainter(
                _hover,
                settings.tool == CanvasTool.eraser
                    ? (eraserRadius * 2, colors.textMuted)
                    : ((settings.strokeWidth * 2 + 8).roundToDouble(), displayInk(settings.color, brightness)),
              ),
            ),
          ),
        ]),
      );
    });
  }
}

/// The stroke being drawn. Only this layer repaints while the pen moves.
class ActiveStroke extends ChangeNotifier {
  final points = <Offset>[];
  final pressures = <double>[];
  final times = <int>[];
  InkTool tool = InkTool.pen;
  PenType penType = PenType.ballpoint;
  Color color = const Color(0xFF000000);
  double width = 2;
  bool usePressure = true;
  Offset? lastScreen;
  DateTime? _startedAt;
  Path? _path;

  bool get isActive => points.isNotEmpty;

  void begin({
    required InkTool tool,
    required PenType penType,
    required Color color,
    required double width,
    required bool usePressure,
  }) {
    this.tool = tool;
    this.penType = penType;
    this.color = color;
    this.width = width;
    this.usePressure = usePressure;
    _startedAt = DateTime.now().toUtc();
    points.clear();
    pressures.clear();
    times.clear();
    _path = null;
  }

  void add(Offset page, Offset screen, double pressure, int tMs) {
    points.add(page);
    pressures.add(pressure);
    times.add(tMs);
    lastScreen = screen;
    _path = null;
    notifyListeners();
  }

  Path get path => _path ??= strokeOutline(
        points: points,
        pressures: pressures,
        width: width,
        penType: tool == InkTool.marker ? PenType.ballpoint : penType,
        usePressure: usePressure && tool == InkTool.pen,
      );

  StrokeItem toItem({required int z}) => StrokeItem.fromPagePoints(
        id: newId('it'),
        z: z,
        createdAt: _startedAt ?? DateTime.now().toUtc(),
        tool: tool,
        penType: penType,
        color: color,
        width: width,
        usePressure: usePressure,
        pagePoints: [
          for (var i = 0; i < points.length; i++) InkPoint(points[i].dx, points[i].dy, pressures[i], times[i]),
        ],
      );

  void clear() {
    points.clear();
    pressures.clear();
    times.clear();
    lastScreen = null;
    _path = null;
    notifyListeners();
  }
}

class PaperPainter extends CustomPainter {
  PaperPainter(this.vp, this.paper, this.colors) : super(repaint: vp);

  final CanvasView vp;
  final Paper paper;
  final EndlessColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.bg);
    if (paper == Paper.blank) return;
    final s = vp.scale;
    final t = vp.translation;
    var spacing = paper == Paper.lines ? 32.0 : Sizes.paperDotSpacing;
    // Keep the pattern from getting too dense when zoomed out.
    while (spacing * s < 12) {
      spacing *= 2;
    }
    final step = spacing * s;
    // Dots sit at 13 + 26k page px, like the design's background-position.
    final origin = Offset(Sizes.paperDotSpacing / 2 * s + t.dx, Sizes.paperDotSpacing / 2 * s + t.dy);
    final startX = origin.dx - (origin.dx / step).floor() * step;
    final startY = origin.dy - (origin.dy / step).floor() * step;

    switch (paper) {
      case Paper.dots:
        final r = Sizes.paperDotRadius * s.clamp(0.7, 1.6);
        final pts = <Offset>[
          for (var y = startY; y < size.height + step; y += step)
            for (var x = startX; x < size.width + step; x += step) Offset(x, y),
        ];
        canvas.drawPoints(
          PointMode.points,
          pts,
          Paint()
            ..color = colors.dot
            ..strokeWidth = r * 2
            ..strokeCap = StrokeCap.round,
        );
      case Paper.lines || Paper.grid:
        final paint = Paint()
          ..color = colors.lineSoft
          ..strokeWidth = 1;
        for (var y = startY; y < size.height; y += step) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
        if (paper == Paper.grid) {
          for (var x = startX; x < size.width; x += step) {
            canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
          }
        }
      case Paper.blank:
        break;
    }
  }

  @override
  bool shouldRepaint(PaperPainter old) => old.paper != paper || old.colors != colors || old.vp != vp;
}

/// Committed ink. Records the items near the view into a picture once, then
/// replays it at the current pan and zoom.
class InkLayerPainter extends CustomPainter {
  InkLayerPainter(this.vp, this.page, this.revision, this.brightness, this.colors) : super(repaint: vp);

  final CanvasView vp;
  final PageRuntime page;
  final int revision;
  final Brightness brightness;
  final EndlessColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (page.isEmpty) return;
    final picture = page.regionPicture(vp.visiblePage, brightness, colors);
    canvas
      ..save()
      ..translate(vp.translation.dx, vp.translation.dy)
      ..scale(vp.scale)
      ..drawPicture(picture)
      ..restore();
  }

  @override
  bool shouldRepaint(InkLayerPainter old) =>
      old.page != page || old.revision != revision || old.brightness != brightness || old.colors != colors;
}

class ActiveStrokePainter extends CustomPainter {
  ActiveStrokePainter(this.stroke, this.vp, this.brightness) : super(repaint: Listenable.merge([stroke, vp]));

  final ActiveStroke stroke;
  final CanvasView vp;
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    if (!stroke.isActive) return;
    canvas
      ..save()
      ..translate(vp.translation.dx, vp.translation.dy)
      ..scale(vp.scale)
      ..drawPath(
        stroke.path,
        Paint()..color = displayInk(stroke.color, brightness).withValues(alpha: inkOpacity(stroke.tool, stroke.penType)),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(ActiveStrokePainter old) => old.stroke != stroke || old.brightness != brightness;
}

/// The ring under a hovering S Pen (or mouse) showing where ink will land.
class HoverRingPainter extends CustomPainter {
  HoverRingPainter(this.hover, this.ring) : super(repaint: hover);

  final ValueNotifier<Offset?> hover;
  final (double, Color) ring;

  @override
  void paint(Canvas canvas, Size size) {
    final at = hover.value;
    if (at == null) return;
    canvas.drawCircle(
      at,
      ring.$1 / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = ring.$2,
    );
  }

  @override
  bool shouldRepaint(HoverRingPainter old) => old.ring != ring || old.hover != hover;
}
