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
import '../ui/canvas/text_editor.dart';
import '../ui/common.dart';
import '../ui/dialogs.dart';
import 'canvas_view.dart';
import 'gesture_overlay.dart';
import 'gestures.dart';
import 'items.dart';
import 'laser.dart';
import 'new_items.dart';
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

/// Handles on the selection outline are this easy to hit (screen px).
const handleReach = 22.0;

/// What the drawing pointer (pen, mouse, or a drawing finger) is doing.
enum _Drag {
  none,
  ink,
  erase,
  laser,
  lasso,
  marquee,
  move,
  resize,
  rotate,
  rulerChip,
  rulerEnd,
  // A tap that drops something (text, sticky note, frame) or, on the whole
  // board, zooms in.
  tap,
  // Dragging out a shape, and dragging one edge of a box.
  shape,
  stretch,
}

/// What the fingers are doing.
enum _Touch { navigate, ruler, selection }

/// The endless page. Routes raw pointers: the stylus draws, fingers pan and
/// zoom, and touches while the stylus is near are rejected as the palm.
/// A mouse draws with the left button and pans with the others, so the app
/// can be tried on a desktop.
///
/// Pen gestures (docs/SPEC.md Phase 3) live here too: hold to straighten,
/// flick back for an arrow, scribble to erase, select and lasso, the ruler
/// and the laser pointer. So do the things that sit on the page: text
/// boxes, sticky notes, paper frames, images and shapes.
class InkCanvas extends ConsumerStatefulWidget {
  const InkCanvas({
    super.key,
    required this.pane,
    this.writable = true,
    this.onActivate,
    this.onBoardTap,
    this.chrome = const EdgeInsets.fromLTRB(12, 84, 12, 12),
  });

  final Pane pane;

  /// False for the unfocused side of Split view: the pen (or mouse) only
  /// focuses it ([onActivate]); fingers still pan and zoom.
  final bool writable;
  final VoidCallback? onActivate;

  /// Set while the whole board is showing: nothing can be written, and a
  /// tap (pen or finger) on the page calls this with the page point.
  final ValueChanged<Offset>? onBoardTap;

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

  /// What a selection drag moves: the selection plus what's written on its
  /// frames. The same instance for the whole drag (the ink layer caches on it).
  Set<String> _moving = const {};

  /// The edge being dragged (0 top, 1 right, 2 bottom, 3 left), its box,
  /// and where the middle of that edge was when the drag began.
  int _stretchSide = 0;
  BoxItem? _stretching;
  Offset _stretchEdge = Offset.zero;

  /// A tap with a "drop one here" tool, or on the whole board: by the pen
  /// (or mouse), or by this finger.
  Offset _tapDown = Offset.zero;
  bool _tapMoved = false;
  int? _tapFinger;

  /// The sticky note the stroke being drawn started on: it's written on the
  /// note and moves with it.
  String? _inkTarget;

  /// Every stroke the scribble in progress would erase.
  Set<String> _scribbleIds = const {};

  /// The shape being dragged out keeps one id.
  String _shapeId = '';

  /// Typing in a text box or on a sticky note.
  TextEditSession? _edit;
  Set<String> _editHidden = const {};

  final _laser = LaserTrail();
  late final Ticker _laserTicker = createTicker((elapsed) {
    _laser.tick(elapsed);
    if (_laser.isEmpty && !_laser.down) _laserTicker.stop();
  });

  Pane get pane => widget.pane;
  CanvasView get _vp => pane.view;
  Selection get _selection => pane.selection;

  /// Page px per screen px.
  double get _unit => 1 / _vp.scale;

  NotebookNotifier get _notebook => ref.read(notebookProvider(pane.notebookId).notifier);

  NotebookState get _nb => ref.read(notebookProvider(pane.notebookId));

  PageRuntime get _page => _nb.pageAt(pane.page);

  /// The whole board is showing: look, pan, zoom and tap to go somewhere.
  bool get _board => widget.onBoardTap != null;

  /// Ink can go on the page: it is writable and not locked.
  bool get _canInk => widget.writable && !_board && !_nb.isSealed(_page.id);

  @override
  void initState() {
    super.initState();
    pane.addListener(_paneChanged);
    pane.status.addListener(_statusChanged);
    _selection.addListener(_overlay.ping);
  }

  @override
  void didUpdateWidget(InkCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pane != widget.pane) {
      oldWidget.pane.removeListener(_paneChanged);
      oldWidget.pane.status.removeListener(_statusChanged);
      oldWidget.pane.selection.removeListener(_overlay.ping);
      widget.pane.addListener(_paneChanged);
      widget.pane.status.addListener(_statusChanged);
      widget.pane.selection.addListener(_overlay.ping);
    }
  }

  void _paneChanged() {
    if (_drawPointer != null) _cancelInput();
    _commitEdit();
    _laser.clear();
    setState(() {});
  }

  /// A straightened line's marks go when its "Undo" message does.
  void _statusChanged() {
    if (pane.status.value == null) _overlay.glow = null;
  }

  @override
  void dispose() {
    pane.removeListener(_paneChanged);
    pane.status.removeListener(_statusChanged);
    _selection.removeListener(_overlay.ping);
    _edit?.dispose();
    _hoverTimer?.cancel();
    _holdTimer?.cancel();
    _hold.dispose();
    _laserTicker.dispose();
    _laser.dispose();
    active.dispose();
    _hover.dispose();
    _overlay.dispose();
    super.dispose();
  }

  // Status and "… · Undo" messages.

  void _status(String? text) => pane.showStatus(text);

  void _toast(String text, {bool undo = true}) => pane.toast(text, undoPageId: undo ? _page.id : null);

  /// A new edit makes an old "Undo" mean something else, so it goes.
  void _dismissToast() {
    if (pane.status.value != null) pane.showStatus(null);
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
    if (_edit != null) {
      // A tap outside the text being typed finishes it, and does no more.
      if (_isStylus(e)) {
        _lastStylus = e.timeStamp;
        _stylusDown = true;
      }
      _commitEdit();
      _ignored.add(e.pointer);
      return;
    }
    if (inks && _board) {
      // On the whole board the pen (or mouse) taps to zoom in there.
      if (_isStylus(e)) {
        _lastStylus = e.timeStamp;
        _stylusDown = true;
        _endTouches();
      }
      _startTap(e);
      return;
    }
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
      if (_board) {
        _touch = _Touch.navigate;
        _tapFinger = e.pointer;
        _tapDown = e.localPosition;
      } else if (pane.ruler.endAt(e.localPosition) case final side?) {
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
        _beginMoving();
      } else if (settings.fingerDraws && _canInk) {
        _fingerDrawing = true;
        _startInput(e, erase: settings.tool == CanvasTool.eraser);
        return;
      } else {
        _touch = _Touch.navigate;
        if (settings.tool.places && _canInk) {
          // A finger tap drops one too; a drag still pans.
          _tapFinger = e.pointer;
          _tapDown = e.localPosition;
        }
      }
    } else {
      // A second finger: not a tap.
      _chipFinger = null;
      _tapFinger = null;
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
    if (pointer == _tapFinger && (to - _tapDown).distance > 10) _tapFinger = null;
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
    if (pointer == _tapFinger) {
      _tapFinger = null;
      _tapped(_tapDown);
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
    _tapFinger = null;
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
      case CanvasTool.text || CanvasTool.sticky || CanvasTool.stack || CanvasTool.frame:
        _selection.clear();
        _drag = _Drag.tap;
        _tapDown = e.localPosition;
        _tapMoved = false;
      case CanvasTool.shape:
        _selection.clear();
        _drag = _Drag.shape;
        _dragFrom = page;
        _shapeId = newId('it');
      case CanvasTool.pen || CanvasTool.marker || CanvasTool.eraser:
        _selection.clear();
        _drag = _Drag.ink;
        _samples = 0;
        // Ink that starts on a sticky note is written on the note.
        _inkTarget = switch (topBoxAt(_page.items, page)) {
          final StickyItem s => s.id,
          _ => null,
        };
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

  /// The pen (or mouse) is down for a tap on the whole board.
  void _startTap(PointerDownEvent e) {
    _drawPointer = e.pointer;
    _drawAt = e.localPosition;
    _hover.value = null;
    _drag = _Drag.tap;
    _tapDown = e.localPosition;
    _tapMoved = false;
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
        // A single box settles upright (or on its side), whatever tilt it had.
        final tilt = _singleBox?.angle ?? 0;
        var a = _wrap(_angle(page - _dragPivot) - _angle(_dragFrom - _dragPivot));
        final quarter = ((tilt + a) / (math.pi / 2)).round() * (math.pi / 2);
        if ((tilt + a - quarter).abs() < 4 * math.pi / 180) a = quarter - tilt;
        _selection.live = Similarity.about(_dragPivot, rotation: a);
      case _Drag.tap:
        if ((e.localPosition - _tapDown).distance > 12) _tapMoved = true;
      case _Drag.shape:
        _overlay.ghost = _shapeTo(page);
      case _Drag.stretch:
        if (_stretching case final box?) {
          // The edge moves as far as the pen has (the handle sits a little outside it).
          _overlay.ghost = stretchBox(box, _stretchSide, _stretchEdge + (page - _dragFrom), min: 24 * _unit);
        }
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
    final near = runtime.index.query(area);
    final hits = [
      for (final id in near)
        if (runtime[id] case final StrokeItem s when strokeHit(s, from, page, r)) id,
    ];
    if (hits.isNotEmpty) _notebook.erase(hits);
    // Ink on a sticky note rubs off the note; the note itself stays.
    for (final id in near) {
      if (runtime[id] case final StickyItem note when note.ink.isNotEmpty) {
        final rubbed = {
          for (final ink in note.pageInk)
            if (strokeHit(ink, from, page, r)) ink.id,
        };
        if (rubbed.isNotEmpty) _notebook.eraseInk(note.id, rubbed);
      }
    }
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
      case _Drag.tap:
        final at = _tapDown;
        final tapped = !_tapMoved;
        _resetInput();
        if (tapped) _tapped(at);
        return;
      case _Drag.shape:
        _finishShape();
      case _Drag.stretch:
        _finishStretch();
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
        _moving = const {};
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
    _inkTarget = null;
    _stretching = null;
    if (_selection.live == null) _moving = const {};
    _scribbleIds = const {};
    _holdTimer?.cancel();
    _hold.reset();
    _overlay
      ..holdFit = null
      ..snapped = null
      ..scribble = const {}
      ..scribbleInk = const []
      ..lasso = []
      ..marquee = null;
    // While typing on a sticky note, the ghost is the note without its text.
    if (_edit == null) _overlay.ghost = null;
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
    if (_drag != _Drag.ink || _scribbleIds.isNotEmpty) return;
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
    var targets = const <StrokeItem>[];
    final note = _targetNote;
    if (looksLikeScribble(active.points, settings.scribbleLevel, unit: _unit)) {
      final page = _page;
      final area = _boundsOf(active.points).inflate(8 * _unit);
      // A scribble on a sticky note erases ink on that note only.
      final candidates = note != null
          ? note.pageInk
          : [
              for (final id in page.index.query(area))
                if (page[id] case final StrokeItem s) s,
            ];
      targets = scribbleTargets(active.points, candidates, unit: _unit);
    }
    final ids = {for (final s in targets) s.id};
    if (setEquals(ids, _scribbleIds)) return;
    _scribbleIds = ids;
    _overlay
      ..scribble = note == null ? ids : const {}
      ..scribbleInk = targets;
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
    final scribble = _scribbleIds;
    _status(null);

    if (scribble.isNotEmpty) {
      // The scribble itself is never kept.
      if (_targetNote case final note?) {
        notifier.replaceItems(page.id, [note.withoutInk(scribble)]);
      } else {
        notifier.removeItems(page.id, scribble);
      }
      _toast('Erased ${_strokes(scribble.length)}');
    } else if (snapped != null) {
      // Two steps: the ink as drawn, then the shape. Undo gives the ink back.
      final raw = active.toItem(z: page.nextZ);
      _putStroke(raw);
      _swapStroke(raw.copyWith(pagePoints: active.snappedInk(), shape: () => snapped.kind.name));
      _toast('${_shapeName(snapped.kind)} straightened');
      if (snapped.kind == ShapeKind.line) _overlay.glow = snapped;
    } else {
      final raw = active.toItem(z: page.nextZ);
      _putStroke(raw);
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
        _swapStroke(raw.copyWith(pagePoints: raw.pageInk.sublist(flicks.from, flicks.to + 1), arrow: () => heads));
        _toast('Made an arrow');
      }
    }
    active.clear();
  }

  /// The sticky note the stroke being drawn is written on, if any.
  StickyItem? get _targetNote => switch (_inkTarget == null ? null : _page[_inkTarget!]) {
        final StickyItem s => s,
        _ => null,
      };

  /// Puts a finished stroke on the page, or on the sticky note it started on.
  void _putStroke(StrokeItem stroke) {
    if (_targetNote case final note?) {
      _notebook.replaceItems(_page.id, [note.withInk(stroke)]);
    } else {
      _notebook.addStroke(_page.id, stroke);
    }
  }

  /// Swaps a stroke just put down for [after] (same id), as its own undo step.
  void _swapStroke(StrokeItem after) {
    if (_targetNote case final note?) {
      _notebook.replaceItems(_page.id, [note.replaceInk(after.id, after)]);
    } else {
      _notebook.replaceItems(_page.id, [after]);
    }
  }

  static String _shapeName(ShapeKind k) => switch (k) {
        ShapeKind.line => 'Line',
        ShapeKind.circle => 'Circle',
        ShapeKind.ellipse => 'Oval',
        ShapeKind.rect => 'Rectangle',
        ShapeKind.triangle => 'Triangle',
      };

  // Select and lasso.

  /// What's selected, in no particular order.
  List<Item> get _selected => [
        for (final id in _selection.ids)
          if (_page[id] case final Item i when i is! UnknownItem) i,
      ];

  /// The one box selected on its own (not lassoed): its outline follows its
  /// rotation and its edges can be dragged.
  BoxItem? get _singleBox {
    if (_selection.ids.length != 1 || _selection.outlineAt(_nb.revision) != null) return null;
    return switch (_page[_selection.ids.single]) {
      final BoxItem b => b,
      _ => null,
    };
  }

  bool get _onlyStickies {
    final items = _selected;
    return items.isNotEmpty && items.every((i) => i is StickyItem);
  }

  /// What's written on the selected frames and pictures (above them, with
  /// its middle on them): it goes where they go.
  List<Item> _riders() {
    final frames = [
      for (final i in _selected)
        if (i is FrameItem || i is ImageItem) i as BoxItem,
    ];
    if (frames.isEmpty) return const [];
    final page = _page;
    final order = {for (final (i, item) in page.items.indexed) item.id: i};
    final out = <String, Item>{};
    for (final f in frames) {
      for (final id in page.index.query(f.extent)) {
        final item = page[id];
        if (item == null || item is UnknownItem || _selection.ids.contains(id)) continue;
        if (order[id]! > order[f.id]! && f.contains(item.extent.center)) out[id] = item;
      }
    }
    return out.values.toList();
  }

  /// Fixes what the drag that's starting will move.
  void _beginMoving() => _moving = Set.unmodifiable({..._selection.ids, for (final r in _riders()) r.id});

  /// The selection's box in page space.
  SelectionFrame? _frame() {
    final u = _unit;
    final stretched = _drag == _Drag.stretch ? _overlay.ghost : null;
    if ((stretched ?? _singleBox) case final BoxItem b) {
      return SelectionFrame(b.center, Size(b.w + 16 * u, b.h + 16 * u), b.angle);
    }
    final items = _selected;
    if (items.isEmpty) return null;
    final loop = _selection.outlineAt(_nb.revision);
    if (loop != null) return SelectionFrame.around(loop.getBounds());
    var r = items.first.extent;
    for (final i in items) {
      r = r.expandToInclude(i.extent);
    }
    return SelectionFrame.around(r.inflate(8 * u));
  }

  /// The selection's outline in page space: the lasso loop while it still
  /// fits, otherwise a rounded box around the items.
  Path? _outline() {
    if (_selection.isEmpty) return null;
    if (_drag != _Drag.stretch) {
      final loop = _selection.outlineAt(_nb.revision);
      if (loop != null && _selected.isNotEmpty) return loop;
    }
    return _frame()?.path(10 * _unit);
  }

  bool _inSelection(Offset page) => _outline()?.getBounds().inflate(4 * _unit).contains(page) ?? false;

  /// The outline's box on screen.
  Rect? _screenBox() {
    final b = _outline()?.getBounds();
    return b == null ? null : Rect.fromPoints(_vp.toScreen(b.topLeft), _vp.toScreen(b.bottomRight));
  }

  /// Where the handles are on screen (none while the selection is dragged).
  SelectionHandles? _handles() {
    if (_selection.isEmpty || _selection.live != null || _drag == _Drag.stretch || !_canInk) return null;
    final f = _frame();
    if (f == null) return null;
    final stem = _vp.toScreen(f.sides[2]);
    final box = _singleBox;
    return SelectionHandles(
      corners: [for (final p in f.corners) _vp.toScreen(p)],
      sides: [
        if (box != null)
          for (final s in stretchSides(box)) _vp.toScreen(f.sides[s]),
      ],
      stem: stem,
      knob: stem + f.down * 30,
    );
  }

  /// Starts dragging a corner handle, the rotate knob or an edge handle
  /// under [screen], if there is one.
  bool _grabHandle(Offset screen, Offset page) {
    final f = _selection.isEmpty ? null : _frame();
    if (f == null) return false;
    _dragFrom = page;
    final corners = f.corners;
    for (var i = 0; i < 4; i++) {
      if ((screen - _vp.toScreen(corners[i])).distance <= handleReach) {
        _drag = _Drag.resize;
        _dragPivot = corners[(i + 2) % 4];
        _beginMoving();
        return true;
      }
    }
    if ((screen - (_vp.toScreen(f.sides[2]) + f.down * 30)).distance <= handleReach) {
      _drag = _Drag.rotate;
      _dragPivot = f.center;
      _beginMoving();
      return true;
    }
    if (_singleBox case final box?) {
      for (final side in stretchSides(box)) {
        if ((screen - _vp.toScreen(f.sides[side])).distance <= handleReach) {
          _drag = _Drag.stretch;
          _stretchSide = side;
          _stretching = box;
          _stretchEdge = box.toPage(
            [Offset(box.w / 2, 0), Offset(box.w, box.h / 2), Offset(box.w / 2, box.h), Offset(0, box.h / 2)][side],
          );
          _moving = Set.unmodifiable({box.id});
          _overlay.ghost = box;
          return true;
        }
      }
    }
    return false;
  }

  void _startSelectionDrag(Offset screen, Offset page, {required bool lasso}) {
    _dragFrom = page;
    if (_grabHandle(screen, page)) return;
    if (_selection.isNotEmpty && _inSelection(page)) {
      _drag = _Drag.move;
      _beginMoving();
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

  /// Everything near [area] that can be selected.
  List<Item> _selectable(Rect area) {
    final page = _page;
    return [
      for (final id in page.index.query(area))
        if (page[id] case final Item i when i is! UnknownItem) i,
    ];
  }

  void _finishLasso() {
    final loop = _overlay.lasso;
    if (loop.length < 3 || pathLength(loop) < 20 * _unit) return;
    final picked = itemsInPolygon(loop, _selectable(_boundsOf(loop)));
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
      // A tap: the topmost thing under the pen.
      final at = rect.center;
      final r = 10 * _unit;
      final ids = page.index.query(Rect.fromCircle(center: at, radius: r));
      for (final item in page.items.reversed) {
        if (!ids.contains(item.id)) continue;
        switch (item) {
          case StrokeItem s when strokeHit(s, at, at, r):
            _selection.select([s.id]);
            return;
          case StickyItem s when s.isStack && stackBadgeRect(s).contains(s.toLocal(at)):
            // Tapping a stack's "5 notes" badge fans it out.
            _fanOut(s);
            return;
          case BoxItem b when boxHit(b, at, slop: 4 * _unit):
            _selection.select([b.id]);
            return;
          default:
            continue;
        }
      }
      return;
    }
    final picked = itemsInPolygon([rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft], _selectable(rect));
    if (picked.isNotEmpty) _selection.select([for (final i in picked) i.id]);
  }

  /// Puts a dragged move, resize or rotation onto the page (one undo step).
  void _land(Similarity? t) {
    final moving = _moving;
    _moving = const {};
    if (t == null || t.isIdentity || _selected.isEmpty) {
      _selection.live = null;
      return;
    }
    final page = _page;
    _notebook.replaceItems(page.id, [
      for (final id in moving.isEmpty ? _selection.ids : moving)
        if (page[id] case final item?) t.applyToItem(item),
    ]);
    _selection.landed(t, _nb.revision);
  }

  void _finishStretch() {
    final box = _stretching;
    final ghost = _overlay.ghost;
    _moving = const {};
    if (box == null || ghost is! BoxItem || _page[box.id] == null) return;
    if (ghost.w != box.w || ghost.h != box.h) _notebook.replaceItems(_page.id, [ghost]);
  }

  /// The toolbar for text boxes, sticky notes, frames, images and shapes
  /// (null when ink is selected: that gets Convert to text or Remember).
  List<SelectionAction>? _objectActions() {
    final items = _selected;
    if (items.isEmpty || items.any((i) => i is StrokeItem)) return null;
    final one = items.length == 1 ? items.single : null;
    return [
      if (one is TextItem || (one is StickyItem && !one.isStack)) SelectionAction.edit,
      if (one is StickyItem && one.isStack) ...[SelectionAction.fanOut, SelectionAction.nextNote],
      if (one == null && _onlyStickies) SelectionAction.stack,
      if (one is FrameItem) SelectionAction.rename,
      SelectionAction.copy,
      if (items.any((i) => i is TextItem || i is StickyItem || i is ShapeItem)) SelectionAction.color,
      SelectionAction.toFront,
      SelectionAction.toBack,
      SelectionAction.delete,
    ];
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
        // A copy lands just below and right of the original, selected. What's
        // written on a frame is copied with it.
        final shift = const Offset(24, 24) * _unit;
        final t = Similarity.translate(shift);
        final riders = {for (final r in _riders()) r.id};
        final now = DateTime.now().toUtc();
        var z = _page.nextZ;
        final copies = <Item>[];
        final picked = <String>[];
        for (final item in _page.items) {
          final chosen = _selection.ids.contains(item.id);
          if (!chosen && !riders.contains(item.id)) continue;
          final Item? copy = switch (item) {
            StrokeItem s => StrokeItem.fromPagePoints(
                id: newId('it'),
                z: z,
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
            BoxItem b => b.withBox(
                id: newId('it'),
                z: z,
                createdAt: now,
                x: b.x + shift.dx,
                y: b.y + shift.dy,
                w: b.w,
                h: b.h,
              ),
            UnknownItem _ => null,
          };
          if (copy == null) continue;
          z++;
          copies.add(copy);
          if (chosen) picked.add(copy.id);
        }
        final loop = _selection.outlineAt(_nb.revision)?.transform(t.matrix.storage);
        _notebook.insertItems(pageId, copies);
        _selection.select(picked, outline: loop, revision: _nb.revision);
      case SelectionAction.straighten:
        final unit = _unit;
        final straightened = [
          for (final s in items.whereType<StrokeItem>())
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
        // A frame takes what's written on it along.
        _notebook.removeItems(pageId, [..._selection.ids, for (final r in _riders()) r.id]);
        _selection.clear();
        _colorsOpen = false;
      case SelectionAction.edit:
        if (items.singleOrNull case final BoxItem b) _beginEdit(b);
      case SelectionAction.fanOut:
        if (items.singleOrNull case final StickyItem s) _fanOut(s);
      case SelectionAction.nextNote:
        if (items.singleOrNull case final StickyItem s) _nextNote(s);
      case SelectionAction.stack:
        _stackSelected();
      case SelectionAction.rename:
        if (items.singleOrNull case final FrameItem f) _renameFrame(f);
      case SelectionAction.toFront || SelectionAction.toBack:
        final loop = _selection.outlineAt(_nb.revision);
        _notebook.reorder(pageId, _selection.ids, toFront: action == SelectionAction.toFront);
        _selection.select(_selection.ids, outline: loop, revision: _nb.revision);
    }
  }

  void _recolor(Color color) {
    final loop = _selection.outlineAt(_nb.revision);
    // The swatches are paper colors when only sticky notes are selected,
    // and ink colors otherwise.
    final paper = _onlyStickies;
    _notebook.replaceItems(_page.id, [
      for (final item in _selected)
        ?switch (item) {
          StickyItem s when paper => s.copyWith(color: color),
          StrokeItem s when !paper => s.copyWith(color: color),
          TextItem t when !paper => t.copyWith(color: color),
          ShapeItem s when !paper => s.copyWith(stroke: color),
          _ => null,
        },
    ]);
    _selection.select(_selection.ids, outline: loop, revision: _nb.revision);
    setState(() => _colorsOpen = false);
  }

  // Sticky stacks.

  /// The notes under a stack's top one. A stack from another app may only
  /// say how many there are: those are blank.
  static List<StickyNote> _notesUnder(StickyItem s) => [
        ...s.under,
        for (var i = s.under.length; i < s.count - 1; i++) StickyNote(color: s.color),
      ];

  /// Spreads a stack into separate notes, side by side (one undo step).
  void _fanOut(StickyItem stack) {
    final page = _page;
    final now = DateTime.now().toUtc();
    final top = stack.copyWith(under: const [], count: 1);
    final rest = [
      for (final (i, n) in _notesUnder(stack).indexed)
        StickyItem(
          id: newId('it'),
          x: stack.x + (i + 1) * stack.w * 1.08,
          y: stack.y,
          z: stack.z,
          createdAt: now,
          w: stack.w,
          h: stack.h,
          color: n.color,
          items: n.items,
        ),
    ];
    _notebook.edit(page.id, replace: [top], insert: rest, insertAt: page.items.indexOf(stack) + 1);
    _selection.select([top.id, for (final r in rest) r.id]);
    _colorsOpen = false;
    _toast('Fanned out ${stackLabel(stack.count)}');
  }

  /// Brings the next note of a stack to the top; the top one goes to the bottom.
  void _nextNote(StickyItem stack) {
    final notes = _notesUnder(stack);
    if (notes.isEmpty) return;
    _notebook.replaceItems(_page.id, [
      stack.copyWith(
        color: notes.first.color,
        items: notes.first.items,
        under: [...notes.skip(1), StickyNote(color: stack.color, items: stack.items)],
      ),
    ]);
  }

  /// Gathers the selected sticky notes into one stack, where the topmost
  /// of them is (one undo step).
  void _stackSelected() {
    final notes = [
      for (final i in _page.items)
        if (i is StickyItem && _selection.ids.contains(i.id)) i,
    ];
    if (notes.length < 2) return;
    final top = notes.last;
    final under = <StickyNote>[..._notesUnder(top)];
    for (final n in notes.reversed.skip(1)) {
      // A note of another size is scaled to the top one, with its ink.
      final fitted = n.withBox(x: 0, y: 0, w: top.w, h: top.h, scale: top.w / n.w);
      under
        ..add(StickyNote(color: fitted.color, items: fitted.items))
        ..addAll(_notesUnder(fitted));
    }
    final stacked = top.copyWith(under: under, rotation: 0);
    _notebook.edit(_page.id, replace: [stacked], remove: [for (final n in notes.take(notes.length - 1)) n.id]);
    _selection.select([top.id]);
    _colorsOpen = false;
    _toast('Stacked ${stackLabel(stacked.count)}');
  }

  Future<void> _renameFrame(FrameItem frame) async {
    final pageId = _page.id;
    final name = await showNamePrompt(context, title: 'Name this frame', initial: frame.title, action: 'Rename');
    if (name == null || !mounted) return;
    if (_page.id == pageId && _page[frame.id] is FrameItem) {
      _notebook.replaceItems(pageId, [(_page[frame.id]! as FrameItem).copyWith(title: name)]);
    }
  }

  // Things dropped on the page with a tap.

  /// A tap on the page: by the pen, or by a finger.
  void _tapped(Offset screen) {
    final at = _vp.toPage(screen);
    if (widget.onBoardTap case final zoomIn?) {
      zoomIn(at);
      return;
    }
    if (!_canInk) return;
    final page = _page;
    final now = DateTime.now().toUtc();
    final settings = ref.read(settingsProvider);
    switch (settings.tool) {
      case CanvasTool.text:
        _textTap(at);
      case CanvasTool.sticky:
        _drop(newSticky(at, z: page.nextZ, now: now), 'Added a sticky note to the page');
      case CanvasTool.stack:
        _drop(newStickyStack(at, z: page.nextZ, now: now), 'Added a stack of notes to the page');
      case CanvasTool.frame:
        // Paper goes under what's already written there.
        final z = page.isEmpty ? 1 : page.items.first.z - 1;
        _drop(newFrame(at, z: z, now: now), 'Added a paper frame to the page', at: 0);
      case CanvasTool.shape:
        _addShape(_shapeAt(at));
      default:
        break;
    }
  }

  /// Puts [item] on the page and goes back to the pen, so it can be written on.
  void _drop(Item item, String message, {int? at}) {
    _dismissToast();
    _notebook.insertItems(_page.id, [item], at: at);
    ref.read(settingsProvider.notifier).apply((s) => s.copyWith(tool: CanvasTool.pen));
    _toast(message);
  }

  /// The shape being dragged out, or null while it's still too small.
  ShapeItem? _shapeTo(Offset to) {
    if ((to - _dragFrom).distance < 6 * _unit) return null;
    final s = ref.read(settingsProvider);
    return shapeBetween(
      s.shapeKind,
      _dragFrom,
      to,
      id: _shapeId,
      z: _page.nextZ,
      now: DateTime.now().toUtc(),
      color: s.penColor,
      strokeWidth: penSizes[s.penSize].width,
    );
  }

  ShapeItem _shapeAt(Offset center) {
    final s = ref.read(settingsProvider);
    return shapeAt(
      s.shapeKind,
      center,
      z: _page.nextZ,
      now: DateTime.now().toUtc(),
      color: s.penColor,
      strokeWidth: penSizes[s.penSize].width,
    );
  }

  void _finishShape() => _addShape(switch (_overlay.ghost) {
        final ShapeItem dragged => dragged,
        _ => _shapeAt(_dragFrom), // a tap drops one at its usual size
      });

  /// Puts a new shape on the page, selected so it can be adjusted.
  void _addShape(ShapeItem shape) {
    _dismissToast();
    _notebook.insertItems(_page.id, [shape]);
    ref.read(settingsProvider.notifier).apply((s) => s.copyWith(tool: CanvasTool.select));
    _selection
      ..menu = SelectionMenu.convert
      ..select([shape.id]);
    final name = shapeName(shape.kind).toLowerCase();
    _toast('Added ${'aeiou'.contains(name[0]) ? 'an' : 'a'} $name to the page');
  }

  // Typing: text boxes, and the text on sticky notes.

  /// The Text tool tapped the page: edit the text box or sticky note there,
  /// or start a new text box.
  void _textTap(Offset at) {
    switch (topBoxAt(_page.items, at, slop: 4 * _unit)) {
      case final TextItem t:
        _beginEdit(t);
      case final StickyItem s:
        _beginEdit(s);
      default:
        // The tap is the middle of the first line.
        _beginEdit(null, at: at - const Offset(0, 22 * 1.3 / 2));
    }
  }

  void _beginEdit(BoxItem? target, {Offset at = Offset.zero}) {
    _commitEdit();
    _selection.clear();
    _colorsOpen = false;
    _dismissToast();
    final pageId = _page.id;
    final TextEditSession session;
    switch (target) {
      case final TextItem t:
        session = TextEditSession(
          pageId: pageId,
          target: t,
          origin: t.toPage(Offset.zero),
          angle: t.angle,
          wrap: t.wrap,
          autoWidth: t.autoWidth,
          font: t.font,
          size: t.size,
          color: t.color,
          text: t.text,
        );
      case final StickyItem note:
        final typed = note.items.whereType<TextItem>().firstOrNull;
        session = TextEditSession(
          pageId: pageId,
          target: note,
          origin: note.toPage(typed == null ? StickyItem.textOrigin : Offset(typed.x, typed.y)),
          angle: note.angle,
          wrap: typed?.wrap ?? note.textWrap,
          autoWidth: false,
          font: typed?.font ?? 'ui',
          size: typed?.size ?? 20,
          color: typed?.color ?? inkDefaults[0],
          text: note.text,
          onPaper: true,
        );
        // The note shows without its typed text while the field is over it.
        _overlay.ghost = note.withText('', color: session.color, at: note.createdAt);
      default:
        session = TextEditSession(
          pageId: pageId,
          origin: at,
          wrap: textAutoWrap,
          autoWidth: true,
          font: 'ui',
          size: 22,
          color: ref.read(settingsProvider).penColor,
        );
    }
    _editHidden = target == null ? const {} : Set.unmodifiable({target.id});
    setState(() => _edit = session);
  }

  /// Puts what was typed on the page (one undo step) and closes the field.
  void _commitEdit() {
    final e = _edit;
    if (e == null) return;
    _edit = null;
    _editHidden = const {};
    _overlay.ghost = null;
    final text = e.controller.text.trimRight();
    final blank = text.trim().isEmpty;
    final nb = _nb;
    final page = nb.pages.where((p) => p.id == e.pageId).firstOrNull;
    if (page != null && !nb.isSealed(page.id)) {
      final now = DateTime.now().toUtc();
      switch (e.target == null ? null : page[e.target!.id]) {
        case final TextItem t:
          if (blank) {
            _notebook.removeItems(page.id, [t.id]);
          } else if (text != t.text || e.font != t.font || e.size != t.size) {
            _notebook.replaceItems(page.id, [_typed(e, text, id: t.id, z: t.z, createdAt: t.createdAt, was: t)]);
          }
        case final StickyItem note:
          final typed = note.items.whereType<TextItem>().firstOrNull;
          if (text != note.text || (typed != null && (typed.font != e.font || typed.size != e.size))) {
            _notebook.replaceItems(page.id, [
              note.withText(blank ? '' : text, color: e.color, at: now, font: e.font, size: e.size),
            ]);
          }
        default:
          if (e.target == null && !blank) {
            _notebook.insertItems(page.id, [_typed(e, text, id: newId('it'), z: page.nextZ, createdAt: now)]);
          }
      }
    }
    // The field is still on screen for the rest of this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => e.dispose());
    if (mounted) setState(() {});
  }

  /// The text box for what was typed, its top-left corner where the field's was.
  TextItem _typed(
    TextEditSession e,
    String text, {
    required String id,
    required int z,
    required DateTime createdAt,
    TextItem? was,
  }) {
    final flat = TextItem(
      id: id,
      x: 0,
      y: 0,
      rotation: was?.rotation ?? 0,
      z: z,
      createdAt: createdAt,
      author: was?.author ?? localAuthor,
      remember: was?.remember,
      extra: was?.extra,
      wrap: e.wrap,
      text: text,
      font: e.font,
      size: e.size,
      color: e.color,
      autoWidth: e.autoWidth,
    );
    final corner = flat.toPage(Offset.zero);
    return flat.copyWith(x: e.origin.dx - corner.dx, y: e.origin.dy - corner.dy);
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
      final keep = settings.tool.selects && widget.writable && !_board;
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
                  handles: _handles,
                  moving: () => _moving,
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
            if (!_board)
              IgnorePointer(child: CustomPaint(painter: RulerPainter(pane.ruler, _vp, settings.rulerUnit, colors))),
            if (_canInk && hoverRing != null)
              IgnorePointer(child: CustomPaint(painter: HoverRingPainter(_hover, hoverRing))),
          ]),
        ),
        if (_edit case final session?)
          TextEditor(
            key: ObjectKey(session),
            session: session,
            view: _vp,
            onDone: _commitEdit,
            onStyle: () => setState(() {}),
            chrome: widget.chrome,
          )
        else if (_canInk)
          _toolbar(),
      ]);
    });
  }

  /// Items drawn by the overlay instead of the ink layer: a selection being
  /// dragged, a box being stretched, text being typed, or strokes a
  /// scribble is about to erase.
  Set<String> _hidden() {
    if (_selection.live != null || _drag == _Drag.stretch) return _moving;
    if (_edit != null) return _editHidden;
    return _overlay.scribble;
  }

  Widget _toolbar() => ListenableBuilder(
        listenable: Listenable.merge([_selection, _vp, _overlay]),
        builder: (context, _) {
          final handles = _handles();
          final box = handles == null ? null : _screenBox();
          if (handles == null || box == null) return const SizedBox.shrink();
          return CustomSingleChildLayout(
            delegate: _ToolbarLayout(box, widget.chrome, math.max(box.bottom, handles.bounds.bottom)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                SelectionToolbar(
                  menu: _selection.menu,
                  colorsOpen: _colorsOpen,
                  onAction: _onAction,
                  objectActions: _objectActions(),
                ),
                if (_colorsOpen) SelectionColors(onPick: _recolor, sticky: _onlyStickies),
              ],
            ),
          );
        },
      );
}

/// Puts the selection toolbar 12 px above the selection, left-aligned with
/// it (Convert.dc.html), or below it (RememberMark.dc.html) when the top
/// chrome is in the way.
class _ToolbarLayout extends SingleChildLayoutDelegate {
  _ToolbarLayout(this.box, this.chrome, this.handlesBottom);

  final Rect box;
  final EdgeInsets chrome;

  /// Where the handles (with the rotate knob) end, on screen.
  final double handlesBottom;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size child) {
    final left = box.left.clamp(chrome.left, math.max(chrome.left, size.width - child.width - chrome.right)).toDouble();
    // The bar itself is 46 px; the color swatches hang below it.
    var top = box.top - 12 - 46;
    if (top < chrome.top) {
      // Below, clear of the rotate handle.
      top = math.min(handlesBottom + handleReach - 11 + 12, size.height - child.height - chrome.bottom);
    }
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_ToolbarLayout old) =>
      old.box != box || old.chrome != chrome || old.handlesBottom != handlesBottom;
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
