import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui' show PointMode;

import 'package:flutter/foundation.dart' show kDebugMode, setEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/ids.dart';
import '../board/model.dart';
import '../state/notebook.dart';
import '../state/settings.dart';
import '../templates/templates.dart';
import '../theme/colors.dart';
import '../theme/tokens.g.dart';
import '../ui/canvas/ruler_menu.dart';
import '../ui/canvas/selection_toolbar.dart';
import '../ui/common.dart';
import 'canvas_status.dart';
import 'canvas_view.dart';
import 'gesture_overlay.dart';
import 'gestures.dart';
import 'laser.dart';
import 'page_runtime.dart';
import 'pane.dart';
import 'pens.dart';
import 'ruler.dart';
import 'selection.dart';
import 'stroke_geometry.dart';

/// Eraser radius in screen px.
const eraserRadius = 10.0;

/// Touches this soon after the stylus was seen (hovering or writing) are
/// treated as the palm and ignored.
const palmWindow = Duration(milliseconds: 600);

/// The pen counts as held still while it stays within this many screen px.
const holdSlop = 4.0;

/// Held still this long, the ring and a dashed preview of the shape appear…
const holdPreview = Duration(milliseconds: 150);

/// …and this long, the stroke snaps to the shape.
const holdSnap = Duration(milliseconds: 500);

/// How long "Line straightened · Undo" and friends stay up.
const toastDuration = Duration(seconds: 4);

/// Handles on the selection outline are this easy to hit (screen px).
const handleReach = 22.0;

/// What the drawing pointer (pen, mouse, or a drawing finger) is doing.
enum _Drag { none, ink, erase, laser, lasso, marquee, move, resize, rotate, rulerChip, rulerEnd }

/// What the fingers are doing.
enum _Touch { navigate, ruler, selection }

/// The endless page. Routes raw pointers: the stylus draws, fingers pan and
/// zoom, and touches while the stylus is near are rejected as the palm.
/// A mouse draws with the left button and pans with the others, so the app
/// can be tried on a desktop.
///
/// Pen gestures (docs/SPEC.md Phase 3) live here too: hold to straighten,
/// flick back for an arrow, scribble to erase, select and lasso, the ruler
/// and the laser pointer.
class InkCanvas extends ConsumerStatefulWidget {
  const InkCanvas({
    super.key,
    required this.pane,
    this.writable = true,
    this.onActivate,
    this.chrome = const EdgeInsets.fromLTRB(12, 84, 12, 12),
  });

  final Pane pane;

  /// False for the unfocused side of Split view: the pen (or mouse) only
  /// focuses it ([onActivate]); fingers still pan and zoom.
  final bool writable;
  final VoidCallback? onActivate;

  /// How far the floating chrome reaches in from each edge. The selection
  /// toolbar stays inside, going below the selection when the top is taken.
  final EdgeInsets chrome;

  @override
  ConsumerState<InkCanvas> createState() => InkCanvasState();
}

class InkCanvasState extends ConsumerState<InkCanvas> with TickerProviderStateMixin {
  final active = ActiveStroke();
  final _hover = ValueNotifier<Offset?>(null);
  Timer? _hoverTimer;

  /// Repaints the gesture overlay (and the ink layer's hidden items).
  final _overlay = GestureOverlayState();

  final _touches = <int, Offset>{};
  final _ignored = <int>{};
  _Touch _touch = _Touch.navigate;
  Similarity _touchTransform = Similarity.identity;
  int? _drawPointer;
  _Drag _drag = _Drag.none;
  bool _fingerDrawing = false;
  Offset? _lastErase;
  Duration _strokeStart = Duration.zero;
  Duration? _lastStylus;
  bool _stylusDown = false;
  double _panZoomScale = 1;

  // Hold to straighten.
  Timer? _holdTimer;
  Offset _holdAnchor = Offset.zero;
  late final AnimationController _hold = AnimationController(vsync: this, duration: holdSnap)
    ..addListener(_overlay.ping)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _snap();
    });

  /// A stroke started on the ruler's edge follows it.
  RulerEdge? _rulerEdge;

  /// Two fingers on the ruler: how much they've spread since they landed,
  /// and whether that's become a resize (past a dead zone, so turning it
  /// doesn't change its length by accident).
  double _rulerPinch = 1;
  bool _rulerSizing = false;

  /// A tap on the ruler's angle chip (by the pen, or by this finger).
  Offset _chipDown = Offset.zero;
  bool _chipMoved = false;
  int? _chipFinger;
  int _samples = 0;

  /// Where the drawing pointer is on screen.
  Offset? _drawAt;

  // Selection drags, in page coordinates.
  Offset _dragFrom = Offset.zero;
  Offset _dragPivot = Offset.zero;
  bool _colorsOpen = false;

  final _laser = LaserTrail();
  late final Ticker _laserTicker = createTicker((elapsed) {
    _laser.tick(elapsed);
    if (_laser.isEmpty && !_laser.down) _laserTicker.stop();
  });

  Timer? _statusTimer;

  Pane get pane => widget.pane;
  CanvasView get _vp => pane.view;
  Selection get _selection => pane.selection;

  /// Page px per screen px.
  double get _unit => 1 / _vp.scale;

  NotebookNotifier get _notebook => ref.read(notebookProvider(pane.notebookId).notifier);

  NotebookState get _nb => ref.read(notebookProvider(pane.notebookId));

  PageRuntime get _page => _nb.pageAt(pane.page);

  /// Ink can go on the page: it is writable and not locked.
  bool get _canInk => widget.writable && !_nb.isSealed(_page.id);

  @override
  void initState() {
    super.initState();
    pane.addListener(_paneChanged);
    _selection.addListener(_overlay.ping);
  }

  @override
  void didUpdateWidget(InkCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pane != widget.pane) {
      oldWidget.pane.removeListener(_paneChanged);
      oldWidget.pane.selection.removeListener(_overlay.ping);
      widget.pane.addListener(_paneChanged);
      widget.pane.selection.addListener(_overlay.ping);
    }
  }

  void _paneChanged() {
    if (_drawPointer != null) _cancelInput();
    _laser.clear();
    setState(() {});
  }

  @override
  void dispose() {
    pane.removeListener(_paneChanged);
    _selection.removeListener(_overlay.ping);
    _hoverTimer?.cancel();
    _holdTimer?.cancel();
    _statusTimer?.cancel();
    _hold.dispose();
    _laserTicker.dispose();
    _laser.dispose();
    active.dispose();
    _hover.dispose();
    _overlay.dispose();
    super.dispose();
  }

  // Status and "… · Undo" messages.

  void _status(String? text) {
    _statusTimer?.cancel();
    pane.status.value = text == null ? null : CanvasStatus(text);
  }

  void _toast(String text, {bool undo = true}) {
    _statusTimer?.cancel();
    final s = CanvasStatus(text, undoPageId: undo ? _page.id : null);
    pane.status.value = s;
    _statusTimer = Timer(toastDuration, () {
      if (pane.status.value == s) pane.status.value = null;
      _overlay.glow = null;
    });
  }

  /// A new edit makes an old "Undo" mean something else, so it goes.
  void _dismissToast() {
    if (pane.status.value == null) return;
    _statusTimer?.cancel();
    pane.status.value = null;
    _overlay.glow = null;
  }

  // Raw pointers.

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
    final inks = _isStylus(e) || (e.kind == PointerDeviceKind.mouse && e.buttons & kPrimaryMouseButton != 0);
    if (inks && !_canInk) {
      if (_isStylus(e)) _lastStylus = e.timeStamp;
      if (!widget.writable) widget.onActivate?.call();
      return;
    }
    if (_isStylus(e)) {
      _lastStylus = e.timeStamp;
      _stylusDown = true;
      _endTouches(); // the palm often lands before the pen
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
        _touch = _Touch.navigate;
        _touches[e.pointer] = e.localPosition;
      }
      return;
    }
    if (_stylusNear(e.timeStamp)) {
      _ignored.add(e.pointer);
      return;
    }
    if (_fingerDrawing && _drawPointer != null) {
      // A second finger means navigate, not draw (or, on a ruler end, that
      // both fingers now move the ruler).
      final first = _drawPointer!;
      final at = _drawAt ?? e.localPosition;
      final onRuler = _drag == _Drag.rulerEnd;
      _cancelInput();
      _touch = onRuler ? _Touch.ruler : _Touch.navigate;
      _touches[first] = at;
    } else if (_touches.isEmpty && _drawPointer == null) {
      // The first finger decides what the fingers move.
      final page = _vp.toPage(e.localPosition);
      if (pane.ruler.endAt(e.localPosition) case final side?) {
        // A finger on either end of the ruler swings and stretches it.
        _startRulerEnd(e, side);
        _fingerDrawing = true;
        return;
      } else if (pane.ruler.contains(e.localPosition)) {
        _touch = _Touch.ruler;
        if (pane.ruler.chipContains(e.localPosition)) {
          _chipFinger = e.pointer;
          _chipDown = e.localPosition;
        }
      } else if (_canInk && _grabHandle(e.localPosition, page)) {
        // A finger on a corner or the rotate knob drags it, like the pen.
        _drawPointer = e.pointer;
        _fingerDrawing = true;
        _strokeStart = e.timeStamp;
        _dismissToast();
        return;
      } else if (_canInk && _selection.isNotEmpty && _inSelection(page)) {
        _touch = _Touch.selection;
        _touchTransform = Similarity.identity;
      } else if (settings.fingerDraws && _canInk) {
        _fingerDrawing = true;
        _startInput(e, erase: settings.tool == CanvasTool.eraser);
        return;
      } else {
        _touch = _Touch.navigate;
      }
    } else {
      _chipFinger = null; // a second finger: not a tap
    }
    _touches[e.pointer] = e.localPosition;
    _rulerPinch = 1;
    _rulerSizing = false;
  }

  void _onMove(PointerMoveEvent e) {
    if (_isStylus(e)) _lastStylus = e.timeStamp;
    if (e.pointer == _drawPointer) {
      _addSample(e);
    } else if (_touches.containsKey(e.pointer)) {
      _moveTouch(e.pointer, e.localPosition);
    }
  }

  void _onUp(PointerUpEvent e) {
    if (_isStylus(e)) {
      _stylusDown = false;
      _lastStylus = e.timeStamp;
    }
    if (e.pointer == _drawPointer) _finishInput();
    _liftTouch(e.pointer);
    _ignored.remove(e.pointer);
  }

  void _onCancel(PointerCancelEvent e) {
    if (_isStylus(e)) _stylusDown = false;
    if (e.pointer == _drawPointer) _cancelInput();
    _liftTouch(e.pointer);
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

  // Fingers: pan and pinch the page (one finger pans too), or move and
  // rotate the ruler, or move, pinch and turn the selection.

  void _moveTouch(int pointer, Offset to) {
    final before = _touchFrame();
    _touches[pointer] = to;
    final after = _touchFrame();
    final factor = before.$2 > 0 && after.$2 > 0 ? after.$2 / before.$2 : 1.0;
    final turn = _touches.length >= 2 ? _wrap(after.$3 - before.$3) : 0.0;
    switch (_touch) {
      case _Touch.navigate:
        _vp.transform(fromFocal: before.$1, toFocal: after.$1, factor: factor);
      case _Touch.ruler:
        if (pointer == _chipFinger) {
          if ((to - _chipDown).distance <= 10) return; // still a tap
          _chipFinger = null;
        }
        pane.ruler.moveBy(after.$1 - before.$1);
        if (_touches.length >= 2) {
          _rulerPinch *= factor;
          if (_rulerSizing) {
            pane.ruler.resizeBy(factor);
          } else if (_rulerPinch > 1.12 || _rulerPinch < 1 / 1.12) {
            _rulerSizing = true;
            pane.ruler.resizeBy(_rulerPinch);
          }
        }
        if (turn != 0) pane.ruler.rotateAbout(after.$1, turn);
      case _Touch.selection:
        final from = _vp.toPage(before.$1), to = _vp.toPage(after.$1);
        final step = Similarity.about(from, scale: factor, rotation: turn).then(Similarity.translate(to - from));
        _touchTransform = _touchTransform.then(step);
        _selection.live = _touchTransform;
    }
  }

  void _liftTouch(int pointer) {
    if (_touches.remove(pointer) == null) return;
    _rulerPinch = 1;
    _rulerSizing = false;
    if (pointer == _chipFinger) {
      _chipFinger = null;
      _openRulerMenu();
    }
    if (_touches.isEmpty && _touch == _Touch.selection) {
      _land(_touchTransform);
      _touchTransform = Similarity.identity;
    }
    if (_touches.isEmpty) _touch = _Touch.navigate;
  }

  /// Drops every finger (the pen came down), landing a selection pinch.
  void _endTouches() {
    if (_touch == _Touch.selection && _touches.isNotEmpty) _land(_touchTransform);
    _touches.clear();
    _touch = _Touch.navigate;
    _touchTransform = Similarity.identity;
  }

  static double _wrap(double a) => math.atan2(math.sin(a), math.cos(a));

  /// Centroid, mean spread and the angle between the first two touches.
  (Offset, double, double) _touchFrame() {
    var sum = Offset.zero;
    for (final p in _touches.values) {
      sum += p;
    }
    final c = sum / _touches.length.toDouble();
    if (_touches.length < 2) return (c, 0, 0);
    var spread = 0.0;
    for (final p in _touches.values) {
      spread += (p - c).distance;
    }
    final two = _touches.values.take(2).toList();
    final d = two[1] - two[0];
    return (c, spread / _touches.length, math.atan2(d.dy, d.dx));
  }

  // The drawing pointer.

  void _startInput(PointerDownEvent e, {required bool erase}) {
    final settings = ref.read(settingsProvider);
    _drawPointer = e.pointer;
    _drawAt = e.localPosition;
    _strokeStart = e.timeStamp;
    _hover.value = null;
    _dismissToast();
    final page = _vp.toPage(e.localPosition);
    if (erase) {
      _drag = _Drag.erase;
      _lastErase = page;
      _notebook.beginErase(_page.id);
      _eraseTo(page);
      return;
    }
    if (pane.ruler.endAt(e.localPosition) case final side?) {
      _startRulerEnd(e, side);
      return;
    }
    if (pane.ruler.chipContains(e.localPosition)) {
      // Tapping the angle chip opens the ruler's menu.
      _drag = _Drag.rulerChip;
      _chipDown = e.localPosition;
      _chipMoved = false;
      return;
    }
    switch (settings.tool) {
      case CanvasTool.laser:
        _drag = _Drag.laser;
        if (!_laserTicker.isActive) {
          _laser.now = Duration.zero;
          _laserTicker.start();
        }
        _laser.start(page);
      case CanvasTool.select || CanvasTool.lasso:
        _startSelectionDrag(e.localPosition, page, lasso: settings.tool == CanvasTool.lasso);
      case CanvasTool.pen || CanvasTool.marker || CanvasTool.eraser:
        _selection.clear();
        _drag = _Drag.ink;
        _samples = 0;
        _rulerEdge = pane.ruler.edgeNear(e.localPosition);
        pane.ruler.measure = null;
        active.begin(
          tool: settings.inkTool,
          penType: settings.penType,
          color: settings.color,
          width: settings.strokeWidth,
          usePressure: settings.pressure,
        );
        active.add(_inkPoint(e.localPosition), e.localPosition, _pressure(e), 0);
        _holdAnchor = e.localPosition;
        _restartHold();
    }
  }

  /// Drags the ruler's [side] end (−1 left, 1 right) with this pointer.
  void _startRulerEnd(PointerDownEvent e, int side) {
    _drawPointer = e.pointer;
    _drawAt = e.localPosition;
    _hover.value = null;
    _drag = _Drag.rulerEnd;
    pane.ruler.grabEnd(side, e.localPosition);
  }

  void _addSample(PointerEvent e) {
    _drawAt = e.localPosition;
    final page = _vp.toPage(e.localPosition);
    switch (_drag) {
      case _Drag.erase:
        _eraseTo(page);
      case _Drag.laser:
        _laser.add(page);
      case _Drag.ink:
        _inkSample(e);
      case _Drag.lasso:
        if ((page - _overlay.lasso.last).distance > 2 * _unit) {
          _overlay.lasso.add(page);
          _overlay.ping();
        }
      case _Drag.marquee:
        _overlay.marquee = Rect.fromPoints(_dragFrom, page);
      case _Drag.move:
        _selection.live = Similarity.translate(page - _dragFrom);
      case _Drag.resize:
        final from = (_dragFrom - _dragPivot).distance;
        if (from > 0) {
          final s = ((page - _dragPivot).distance / from).clamp(0.05, 20.0);
          _selection.live = Similarity.about(_dragPivot, scale: s);
        }
      case _Drag.rotate:
        var a = _wrap(_angle(page - _dragPivot) - _angle(_dragFrom - _dragPivot));
        final quarter = (a / (math.pi / 2)).round() * (math.pi / 2);
        if ((a - quarter).abs() < 4 * math.pi / 180) a = quarter;
        _selection.live = Similarity.about(_dragPivot, rotation: a);
      case _Drag.rulerChip:
        if ((e.localPosition - _chipDown).distance > 10) _chipMoved = true;
      case _Drag.rulerEnd:
        pane.ruler.dragEnd(e.localPosition);
      case _Drag.none:
        break;
    }
  }

  static double _angle(Offset d) => math.atan2(d.dy, d.dx);

  void _eraseTo(Offset page) {
    final from = _lastErase ?? page;
    _lastErase = page;
    final r = eraserRadius / _vp.scale;
    final runtime = _page;
    final area = Rect.fromPoints(from, page).inflate(r + 30);
    final hits = [
      for (final id in runtime.index.query(area))
        if (runtime[id] case final StrokeItem s when strokeHit(s, from, page, r)) id,
    ];
    if (hits.isNotEmpty) _notebook.erase(hits);
  }

  void _finishInput() {
    switch (_drag) {
      case _Drag.erase:
        _notebook.endErase();
      case _Drag.laser:
        _laser.end();
      case _Drag.ink:
        _finishInk();
      case _Drag.lasso:
        _finishLasso();
      case _Drag.marquee:
        _finishMarquee();
      case _Drag.move || _Drag.resize || _Drag.rotate:
        _land(_selection.live);
      case _Drag.rulerChip:
        if (!_chipMoved) _openRulerMenu();
      case _Drag.rulerEnd:
        pane.ruler.releaseEnd();
      case _Drag.none:
        break;
    }
    _resetInput();
  }

  void _openRulerMenu() {
    _hover.value = null;
    showRulerMenu(context, pane.ruler);
  }

  void _cancelInput() {
    switch (_drag) {
      case _Drag.erase:
        _notebook.endErase();
      case _Drag.laser:
        _laser.end();
      case _Drag.move || _Drag.resize || _Drag.rotate:
        _selection.live = null;
      default:
        break;
    }
    active.clear();
    if (pane.status.value?.undoPageId == null) _status(null);
    _resetInput();
  }

  void _resetInput() {
    if (_drag == _Drag.rulerEnd) pane.ruler.releaseEnd();
    _drawPointer = null;
    _drawAt = null;
    _drag = _Drag.none;
    _lastErase = null;
    _fingerDrawing = false;
    _rulerEdge = null;
    _holdTimer?.cancel();
    _hold.reset();
    _overlay
      ..holdFit = null
      ..snapped = null
      ..scribble = const {}
      ..lasso = []
      ..marquee = null;
  }

  // Ink and its gestures.

  /// Where ink lands for a pen at [screen]: on the ruler's edge if the
  /// stroke started there.
  Offset _inkPoint(Offset screen) {
    final edge = _rulerEdge;
    if (edge == null) return _vp.toPage(screen);
    final gap = active.width * _vp.scale / 2 + 1;
    return _vp.toPage(edge.snap(screen, gap));
  }

  void _inkSample(PointerEvent e) {
    final snapped = _overlay.snapped;
    if (snapped != null) {
      // After the snap, a line's end follows the pen; other shapes stay put.
      if (snapped.kind == ShapeKind.line) {
        final start = snapped.points.first;
        final end = snapLineEnd(start, _vp.toPage(e.localPosition));
        final fit = ShapeFit(ShapeKind.line, linePoints(start, end), angle: lineAngle(start, end).round());
        _overlay.snapped = fit;
        active.shape = fit.points;
      }
      return;
    }
    active.add(_inkPoint(e.localPosition), e.localPosition, _pressure(e), (e.timeStamp - _strokeStart).inMilliseconds);
    _samples++;
    if (_rulerEdge != null) {
      // The chip shows how long the line along the ruler is.
      pane.ruler.measure = (active.points.last - active.points.first).distance;
      return;
    }
    if ((e.localPosition - _holdAnchor).distance > holdSlop) {
      _holdAnchor = e.localPosition;
      _restartHold();
    }
    if (_samples % 3 == 0) _checkScribble();
  }

  /// The pen moved: start timing a new hold.
  void _restartHold() {
    _holdTimer?.cancel();
    if (_hold.value > 0 || _overlay.holdFit != null) {
      _hold.reset();
      _overlay.holdFit = null;
      active.opacity = 1;
      _status(null);
    }
    if (!ref.read(settingsProvider).snap || _rulerEdge != null) return;
    _holdTimer = Timer(holdPreview, _holdBegan);
  }

  void _holdBegan() {
    if (_drag != _Drag.ink || _overlay.scribble.isNotEmpty) return;
    final fit = fitShape(active.points, unit: _unit);
    if (fit == null) return;
    _overlay.holdFit = fit;
    active.opacity = 0.45;
    _status('Hold to straighten…');
    _hold.forward(from: holdPreview.inMilliseconds / holdSnap.inMilliseconds);
  }

  void _snap() {
    final fit = _overlay.holdFit;
    if (_drag != _Drag.ink || fit == null) return;
    _overlay
      ..snapped = fit
      ..holdFit = null;
    active
      ..shape = fit.points
      ..opacity = 1;
    _status(null);
    HapticFeedback.selectionClick();
  }

  void _checkScribble() {
    final settings = ref.read(settingsProvider);
    // A scribble is quick and compact; a long line of writing isn't one, and
    // re-checking it every few samples would get slow.
    if (!settings.scribble || active.points.length < 8 || active.points.length > 1500) return;
    var ids = const <String>{};
    if (looksLikeScribble(active.points, settings.scribbleLevel, unit: _unit)) {
      final page = _page;
      final area = _boundsOf(active.points).inflate(8 * _unit);
      final candidates = [
        for (final id in page.index.query(area))
          if (page[id] case final StrokeItem s) s,
      ];
      ids = {for (final s in scribbleTargets(active.points, candidates, unit: _unit)) s.id};
    }
    if (setEquals(ids, _overlay.scribble)) return;
    _overlay.scribble = ids;
    active.opacity = ids.isEmpty ? 1 : 0.25;
    if (ids.isNotEmpty) {
      _holdTimer?.cancel();
      _hold.reset();
      _overlay.holdFit = null;
    }
    _status(ids.isEmpty ? null : 'Lift the pen to erase ${_strokes(ids.length)}');
  }

  static String _strokes(int n) => n == 1 ? '1 stroke' : '$n strokes';

  static Rect _boundsOf(List<Offset> pts) {
    var r = Rect.fromPoints(pts.first, pts.first);
    for (final p in pts) {
      r = r.expandToInclude(Rect.fromPoints(p, p));
    }
    return r;
  }

  void _finishInk() {
    if (!active.isActive) return;
    final settings = ref.read(settingsProvider);
    final notifier = _notebook;
    final page = _page;
    final snapped = _overlay.snapped;
    final scribble = _overlay.scribble;
    _status(null);

    if (scribble.isNotEmpty) {
      // The scribble itself is never kept.
      notifier.removeItems(page.id, scribble);
      _toast('Erased ${_strokes(scribble.length)}');
    } else if (snapped != null) {
      // Two steps: the ink as drawn, then the shape. Undo gives the ink back.
      final raw = active.toItem(z: page.nextZ);
      notifier.addStroke(page.id, raw);
      notifier.replaceItems(page.id, [raw.copyWith(pagePoints: active.snappedInk(), shape: () => snapped.kind.name)]);
      _toast('${_shapeName(snapped.kind)} straightened');
      if (snapped.kind == ShapeKind.line) _overlay.glow = snapped;
    } else {
      final raw = active.toItem(z: page.nextZ);
      notifier.addStroke(page.id, raw);
      final flicks = settings.arrows && _rulerEdge == null
          ? detectFlicks(
              active.points,
              times: active.times,
              unit: _unit,
              // In debug builds (`flutter logs`), why a hook didn't count.
              why: kDebugMode ? (w) => debugPrint('No arrow: $w') : null,
            )
          : null;
      if (flicks != null) {
        final heads = ArrowHeads(start: flicks.start, end: flicks.end, style: settings.arrowStyle);
        notifier.replaceItems(page.id, [
          raw.copyWith(pagePoints: raw.pageInk.sublist(flicks.from, flicks.to + 1), arrow: () => heads),
        ]);
        _toast('Made an arrow');
      }
    }
    active.clear();
  }

  static String _shapeName(ShapeKind k) => switch (k) {
        ShapeKind.line => 'Line',
        ShapeKind.circle => 'Circle',
        ShapeKind.ellipse => 'Oval',
        ShapeKind.rect => 'Rectangle',
        ShapeKind.triangle => 'Triangle',
      };

  // Select and lasso.

  List<StrokeItem> get _selected => [
        for (final id in _selection.ids)
          if (_page[id] case final StrokeItem s) s,
      ];

  /// The selection's outline in page space: the lasso loop while it still
  /// fits, otherwise a rounded box around the items.
  Path? _outline() {
    final items = _selected;
    if (items.isEmpty) return null;
    final loop = _selection.outlineAt(_nb.revision);
    if (loop != null) return loop;
    var r = items.first.bounds;
    for (final s in items) {
      r = r.expandToInclude(s.bounds);
    }
    return Path()..addRRect(RRect.fromRectAndRadius(r.inflate(8 * _unit), Radius.circular(10 * _unit)));
  }

  bool _inSelection(Offset page) => _outline()?.getBounds().inflate(4 * _unit).contains(page) ?? false;

  /// The outline's box on screen.
  Rect? _screenBox() {
    final b = _outline()?.getBounds();
    return b == null ? null : Rect.fromPoints(_vp.toScreen(b.topLeft), _vp.toScreen(b.bottomRight));
  }

  /// Starts dragging a corner handle or the rotate knob under [screen], if
  /// there is one.
  bool _grabHandle(Offset screen, Offset page) {
    final box = _selection.isEmpty ? null : _screenBox();
    if (box == null) return false;
    _dragFrom = page;
    final corners = [box.topLeft, box.topRight, box.bottomRight, box.bottomLeft];
    for (var i = 0; i < 4; i++) {
      if ((screen - corners[i]).distance <= handleReach) {
        _drag = _Drag.resize;
        _dragPivot = _vp.toPage(corners[(i + 2) % 4]);
        return true;
      }
    }
    if ((screen - rotateHandle(box)).distance <= handleReach) {
      _drag = _Drag.rotate;
      _dragPivot = _vp.toPage(box.center);
      return true;
    }
    return false;
  }

  void _startSelectionDrag(Offset screen, Offset page, {required bool lasso}) {
    _dragFrom = page;
    if (_grabHandle(screen, page)) return;
    if (_selection.isNotEmpty && _inSelection(page)) {
      _drag = _Drag.move;
      return;
    }
    _selection.clear();
    _colorsOpen = false;
    if (lasso) {
      _drag = _Drag.lasso;
      _overlay.lasso = [page];
    } else {
      _drag = _Drag.marquee;
      _overlay.marquee = Rect.fromPoints(page, page);
    }
  }

  void _finishLasso() {
    final loop = _overlay.lasso;
    if (loop.length < 3 || pathLength(loop) < 20 * _unit) return;
    final page = _page;
    final area = _boundsOf(loop);
    final near = [
      for (final id in page.index.query(area))
        if (page[id] case final StrokeItem s) s,
    ];
    final picked = itemsInPolygon(loop, near);
    if (picked.isEmpty) return;
    _selection.select(
      [for (final i in picked) i.id],
      outline: Path()..addPolygon(loop, true),
      revision: _nb.revision,
    );
  }

  void _finishMarquee() {
    final rect = _overlay.marquee;
    if (rect == null) return;
    final page = _page;
    if (rect.longestSide < 6 * _unit) {
      // A tap: the topmost stroke under the pen.
      final at = rect.center;
      final r = 10 * _unit;
      final ids = page.index.query(Rect.fromCircle(center: at, radius: r));
      for (final item in page.items.reversed) {
        if (ids.contains(item.id) && item is StrokeItem && strokeHit(item, at, at, r)) {
          _selection.select([item.id]);
          return;
        }
      }
      return;
    }
    final near = [
      for (final id in page.index.query(rect))
        if (page[id] case final StrokeItem s) s,
    ];
    final picked = itemsInPolygon([rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft], near);
    if (picked.isNotEmpty) _selection.select([for (final i in picked) i.id]);
  }

  /// Puts a dragged move, resize or rotation onto the page (one undo step).
  void _land(Similarity? t) {
    if (t == null || t.isIdentity || _selected.isEmpty) {
      _selection.live = null;
      return;
    }
    _notebook.replaceItems(_page.id, [for (final s in _selected) t.applyTo(s)]);
    _selection.landed(t, _nb.revision);
  }

  void _onAction(SelectionAction action) {
    final pageId = _page.id;
    final items = _selected;
    switch (action) {
      case SelectionAction.convert:
        showComingSoon(context, 'Convert to text');
      case SelectionAction.remember:
        showComingSoon(context, 'Need to remember');
      case SelectionAction.flashcard:
        showComingSoon(context, 'Flashcards');
      case SelectionAction.color:
        setState(() => _colorsOpen = !_colorsOpen);
      case SelectionAction.copy:
        // A copy lands just below and right of the original, selected.
        final t = Similarity.translate(Offset(24, 24) * _unit);
        final z = _page.nextZ;
        final now = DateTime.now().toUtc();
        final copies = [
          for (final (i, s) in items.indexed)
            StrokeItem.fromPagePoints(
              id: newId('it'),
              z: z + i,
              createdAt: now,
              tool: s.tool,
              penType: s.penType,
              color: s.color,
              width: s.width,
              usePressure: s.usePressure,
              pagePoints: t.applyTo(s).pageInk,
              arrow: s.arrow,
              straightened: s.straightened,
            ),
        ];
        final loop = _selection.outlineAt(_nb.revision)?.transform(t.matrix.storage);
        _notebook.insertItems(pageId, copies);
        _selection.select([for (final c in copies) c.id], outline: loop, revision: _nb.revision);
      case SelectionAction.straighten:
        final unit = _unit;
        final straightened = [
          for (final s in items)
            if (s.straightened == null)
              if (fitShape(s.pagePoints.toList(), unit: unit) case final fit?)
                s.copyWith(
                  pagePoints: shapeInk(fit.points, [for (final p in s.points) p.pressure], s.points.last.t),
                  shape: () => fit.kind.name,
                  arrow: () => null,
                ),
        ];
        if (straightened.isEmpty) {
          _toast('Nothing here to straighten', undo: false);
          return;
        }
        final loop = _selection.outlineAt(_nb.revision);
        _notebook.replaceItems(pageId, straightened);
        _selection.select(_selection.ids, outline: loop, revision: _nb.revision);
        _toast(straightened.length == 1 ? 'Straightened 1 stroke' : 'Straightened ${straightened.length} strokes');
      case SelectionAction.delete:
        _notebook.removeItems(pageId, [for (final s in items) s.id]);
        _selection.clear();
        _colorsOpen = false;
    }
  }

  void _recolor(Color color) {
    final loop = _selection.outlineAt(_nb.revision);
    _notebook.replaceItems(_page.id, [for (final s in _selected) s.copyWith(color: color)]);
    _selection.select(_selection.ids, outline: loop, revision: _nb.revision);
    setState(() => _colorsOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final notebook = ref.watch(notebookProvider(pane.notebookId));
    final settings = ref.watch(settingsProvider);
    final colors = context.colors;
    final brightness = Theme.of(context).brightness;
    final page = notebook.pageAt(pane.page);
    final layout = layoutPicture(page.page.template, colors);

    // Leaving select and lasso (or an undo removing items) updates the selection.
    if (_selection.isNotEmpty) {
      final keep = settings.tool.selects && widget.writable;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!keep) {
          _selection.clear();
          _colorsOpen = false;
        } else {
          _selection.retain((id) => _page[id] != null);
        }
      });
    }
    if (settings.tool != CanvasTool.laser && !_laser.isEmpty && _drag != _Drag.laser) _laser.clear();

    final hoverRing = switch (settings.tool) {
      CanvasTool.eraser => (eraserRadius * 2, colors.textMuted),
      CanvasTool.pen || CanvasTool.marker =>
        ((settings.strokeWidth * 2 + 8).roundToDouble(), displayInk(settings.color, brightness)),
      _ => null,
    };
    final laserColor = [colors.laserRed, colors.laserGreen, colors.laserBlue][settings.laserColor];

    return LayoutBuilder(builder: (context, constraints) {
      _vp.size = constraints.biggest;
      return Stack(fit: StackFit.expand, children: [
        Listener(
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
            if (layout != null) RepaintBoundary(child: CustomPaint(painter: LayoutPainter(_vp, layout))),
            RepaintBoundary(
              child: CustomPaint(
                painter: InkLayerPainter(_vp, page, notebook.revision, brightness, colors, hidden: _hidden, repaint: _overlay),
              ),
            ),
            RepaintBoundary(
              child: CustomPaint(
                painter: GestureOverlayPainter(
                  overlay: _overlay,
                  vp: _vp,
                  page: page,
                  selection: _selection,
                  outline: _outline,
                  hold: _hold,
                  holdAt: () => active.lastScreen,
                  inkColor: displayInk(active.isActive ? active.color : settings.color, brightness),
                  brightness: brightness,
                  colors: colors,
                ),
              ),
            ),
            RepaintBoundary(
              child: CustomPaint(painter: ActiveStrokePainter(active, _vp, brightness)),
            ),
            if (settings.tool == CanvasTool.laser || !_laser.isEmpty)
              IgnorePointer(child: CustomPaint(painter: LaserPainter(_laser, _vp, laserColor))),
            IgnorePointer(child: CustomPaint(painter: RulerPainter(pane.ruler, _vp, settings.rulerUnit, colors))),
            if (_canInk && hoverRing != null)
              IgnorePointer(child: CustomPaint(painter: HoverRingPainter(_hover, hoverRing))),
          ]),
        ),
        if (_canInk) _toolbar(),
      ]);
    });
  }

  /// Items drawn by the overlay instead of the ink layer: a selection being
  /// dragged, or strokes a scribble is about to erase.
  Set<String> _hidden() {
    if (_selection.live != null) return _selection.ids;
    return _overlay.scribble;
  }

  Widget _toolbar() => ListenableBuilder(
        listenable: Listenable.merge([_selection, _vp]),
        builder: (context, _) {
          final box = _selection.isEmpty || _selection.live != null ? null : _screenBox();
          if (box == null) return const SizedBox.shrink();
          return CustomSingleChildLayout(
            delegate: _ToolbarLayout(box, widget.chrome),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                SelectionToolbar(menu: _selection.menu, colorsOpen: _colorsOpen, onAction: _onAction),
                if (_colorsOpen) SelectionColors(onPick: _recolor),
              ],
            ),
          );
        },
      );
}

/// Where the rotate handle sits under a selection's screen box.
Offset rotateHandle(Rect box) => box.bottomCenter + const Offset(0, 30);

/// Puts the selection toolbar 12 px above the selection, left-aligned with
/// it (Convert.dc.html), or below it (RememberMark.dc.html) when the top
/// chrome is in the way.
class _ToolbarLayout extends SingleChildLayoutDelegate {
  _ToolbarLayout(this.box, this.chrome);

  final Rect box;
  final EdgeInsets chrome;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size child) {
    final left = box.left.clamp(chrome.left, math.max(chrome.left, size.width - child.width - chrome.right)).toDouble();
    // The bar itself is 46 px; the color swatches hang below it.
    var top = box.top - 12 - 46;
    if (top < chrome.top) {
      // Below, clear of the rotate handle.
      top = math.min(rotateHandle(box).dy + handleReach + 12, size.height - child.height - chrome.bottom);
    }
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_ToolbarLayout old) => old.box != box || old.chrome != chrome;
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
  List<Offset>? _shape;
  double _opacity = 1;

  /// After hold to straighten: the shape shown (and kept) instead of the ink.
  List<Offset>? get shape => _shape;
  set shape(List<Offset>? v) {
    _shape = v;
    _path = null;
    notifyListeners();
  }

  /// Faded while a scribble is about to erase.
  double get opacity => _opacity;
  set opacity(double v) {
    if (v == _opacity) return;
    _opacity = v;
    notifyListeners();
  }

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
    _shape = null;
    _opacity = 1;
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
        points: _shape ?? points,
        pressures: _shape == null ? pressures : List.filled(_shape!.length, 0.5),
        width: width,
        penType: tool == InkTool.marker ? PenType.ballpoint : penType,
        usePressure: usePressure && tool == InkTool.pen && _shape == null,
      );

  /// The snapped [shape] as ink points.
  List<InkPoint> snappedInk() => shapeInk(_shape ?? points, pressures, times.isEmpty ? 0 : times.last);

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
    _shape = null;
    _opacity = 1;
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
          ..color = paper == Paper.lines ? colors.paperLine : colors.paperGrid
          ..strokeWidth = 1;
        for (var y = startY; y < size.height; y += step) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
        if (paper == Paper.grid) {
          for (var x = startX; x < size.width; x += step) {
            canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
          }
        } else {
          // Lined paper's margin rule, at page x = 80.
          final x = 80 * s + t.dx;
          canvas.drawLine(
            Offset(x, 0),
            Offset(x, size.height),
            Paint()
              ..color = colors.paperMargin
              ..strokeWidth = 1.5,
          );
        }
      case Paper.blank:
        break;
    }
  }

  @override
  bool shouldRepaint(PaperPainter old) => old.paper != paper || old.colors != colors || old.vp != vp;
}

/// A template's starting layout (Cornell rules, planner boxes…), under the ink.
class LayoutPainter extends CustomPainter {
  LayoutPainter(this.vp, this.picture) : super(repaint: vp);

  final CanvasView vp;
  final ui.Picture picture;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..translate(vp.translation.dx, vp.translation.dy)
      ..scale(vp.scale)
      ..drawPicture(picture)
      ..restore();
  }

  @override
  bool shouldRepaint(LayoutPainter old) => old.picture != picture || old.vp != vp;
}

/// Committed ink. Records the items near the view into a picture once, then
/// replays it at the current pan and zoom.
class InkLayerPainter extends CustomPainter {
  InkLayerPainter(
    this.vp,
    this.page,
    this.revision,
    this.brightness,
    this.colors, {
    Set<String> Function()? hidden,
    Listenable? repaint,
  })  : hidden = hidden ?? _none,
        super(repaint: repaint == null ? vp : Listenable.merge([vp, repaint]));

  final CanvasView vp;
  final PageRuntime page;
  final int revision;
  final Brightness brightness;
  final EndlessColors colors;

  /// Items an overlay draws instead (being dragged, or about to be erased).
  final Set<String> Function() hidden;

  static Set<String> _none() => const {};

  @override
  void paint(Canvas canvas, Size size) {
    if (page.isEmpty) return;
    final picture = page.regionPicture(vp.visiblePage, brightness, colors, hidden: hidden());
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
        Paint()
          ..color = displayInk(stroke.color, brightness)
              .withValues(alpha: inkOpacity(stroke.tool, stroke.penType) * stroke.opacity),
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
