import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../board/ids.dart';
import '../../board/model.dart';
import '../../canvas/page_runtime.dart' show paintStroke;
import '../../canvas/pens.dart';
import '../../state/settings.dart';
import '../../theme/colors.dart';

// A place to write with the pen outside a page: the planner's top 3, notes
// for today, week goals and "write a task…". It writes with the pen's color,
// size and type from the canvas; the S Pen's button (or its eraser end)
// rubs out whole strokes. Fingers don't write unless "Draw with finger" is
// on, so they can still scroll and tap; a finger tap goes to [onTap].

class InkPad extends ConsumerStatefulWidget {
  const InkPad({
    super.key,
    required this.strokes,
    required this.onChanged,
    this.onTap,
    this.onPause,
    this.pause = const Duration(milliseconds: 1200),
    this.faded = false,
    this.label,
    this.child,
  });

  /// What's written, at 100% from the pad's top-left.
  final List<StrokeItem> strokes;

  /// After each stroke and each rub-out.
  final ValueChanged<List<StrokeItem>> onChanged;

  /// A tap that didn't write (a finger, or the pen without moving).
  final VoidCallback? onTap;

  /// The pen has been away for [pause] since the last stroke.
  final VoidCallback? onPause;
  final Duration pause;

  /// Done things are written in a faint ink.
  final bool faded;

  /// For screen readers.
  final String? label;

  /// Drawn under the ink (rules, a hint).
  final Widget? child;

  @override
  ConsumerState<InkPad> createState() => _InkPadState();
}

class _InkPadState extends ConsumerState<InkPad> {
  int? _pointer;
  bool _erasing = false;
  final _points = <InkPoint>[];
  Duration _t0 = Duration.zero;
  Offset? _down;
  bool _moved = false;
  Timer? _pauseTimer;

  /// Rubbed out during this eraser drag (one change when it lifts).
  List<StrokeItem>? _left;

  @override
  void dispose() {
    _pauseTimer?.cancel();
    super.dispose();
  }

  static bool _isStylus(PointerEvent e) => e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus;

  static double _pressure(PointerEvent e) {
    if (!_isStylus(e)) return 0.5;
    final range = e.pressureMax - e.pressureMin;
    if (range <= 0) return 0.5;
    return ((e.pressure - e.pressureMin) / range).clamp(0.0, 1.0);
  }

  bool _writes(PointerEvent e) => _isStylus(e) || e.kind == PointerDeviceKind.mouse || ref.read(settingsProvider).fingerDraws;

  void _onDown(PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    _down = e.localPosition;
    _moved = false;
    if (!_writes(e)) return;
    _pauseTimer?.cancel();
    final side = e.buttons & (kPrimaryStylusButton | kSecondaryStylusButton) != 0;
    _erasing = e.kind == PointerDeviceKind.invertedStylus || side;
    if (_erasing) {
      _left = [...widget.strokes];
      _erase(e.localPosition);
      return;
    }
    _t0 = e.timeStamp;
    setState(
      () => _points
        ..clear()
        ..add(InkPoint(e.localPosition.dx, e.localPosition.dy, _pressure(e), 0)),
    );
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    if (!_moved && (e.localPosition - _down!).distance > 4) _moved = true;
    if (!_writes(e)) return;
    if (_erasing) return _erase(e.localPosition);
    setState(() => _points.add(InkPoint(e.localPosition.dx, e.localPosition.dy, _pressure(e), (e.timeStamp - _t0).inMilliseconds)));
  }

  void _onUp(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    final tapped = !_moved;
    if (_erasing) {
      _erasing = false;
      final left = _left;
      _left = null;
      if (left != null && left.length != widget.strokes.length) widget.onChanged(left);
    } else if (_points.isNotEmpty && !tapped) {
      final settings = ref.read(settingsProvider);
      final now = DateTime.now().toUtc();
      final stroke = StrokeItem.fromPagePoints(
        id: newId('st', now: now),
        z: (widget.strokes.lastOrNull?.z ?? 0) + 1,
        createdAt: now,
        tool: InkTool.pen,
        penType: settings.penType,
        color: settings.penColor,
        width: strokeWidthFor(InkTool.pen, settings.penSize),
        usePressure: settings.pressure,
        pagePoints: [..._points],
      );
      setState(_points.clear);
      widget.onChanged([...widget.strokes, stroke]);
    } else {
      setState(_points.clear);
    }
    if (tapped) widget.onTap?.call();
    if (widget.onPause != null && !tapped) {
      _pauseTimer?.cancel();
      _pauseTimer = Timer(widget.pause, () {
        if (mounted && _pointer == null) widget.onPause!();
      });
    }
  }

  void _onCancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _erasing = false;
    _left = null;
    setState(_points.clear);
  }

  void _erase(Offset at) {
    final hit = Rect.fromCircle(center: at, radius: 10);
    final left = _left!;
    final before = left.length;
    left.removeWhere((s) => s.bounds.overlaps(hit) && s.pagePoints.any((p) => (p - at).distance < 10 + s.width));
    if (left.length != before) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final c = context.colors;
    final shown = _left ?? widget.strokes;
    final settings = ref.watch(settingsProvider);
    final live = _points.length < 2
        ? null
        : StrokeItem.fromPagePoints(
            id: 'live',
            z: 0,
            createdAt: DateTime.utc(2026),
            tool: InkTool.pen,
            penType: settings.penType,
            color: settings.penColor,
            width: strokeWidthFor(InkTool.pen, settings.penSize),
            usePressure: settings.pressure,
            pagePoints: _points,
          );
    return Semantics(
      label: widget.label,
      container: widget.label != null,
      // The rules or hint under the ink aren't read out.
      excludeSemantics: widget.label != null,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: _onUp,
        onPointerCancel: _onCancel,
        child: CustomPaint(
          foregroundPainter: _InkPainter([...shown, ?live], brightness, widget.faded ? c.textFaint : null),
          child: widget.child ?? const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _InkPainter extends CustomPainter {
  _InkPainter(this.strokes, this.brightness, this.color);

  final List<StrokeItem> strokes;
  final Brightness brightness;
  final Color? color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final s in strokes) {
      paintStroke(canvas, s, color ?? displayInk(s.color, brightness));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_InkPainter old) => true;
}

/// Ink drawn small to fit (the 3-day view's notes, the widgets).
class InkPreview extends StatelessWidget {
  const InkPreview({super.key, required this.strokes, this.scale = 1, this.faded = false});

  final List<StrokeItem> strokes;
  final double scale;
  final bool faded;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.infinite, painter: _ScaledInk(strokes, scale, Theme.of(context).brightness, faded ? context.colors.textFaint : null));
}

class _ScaledInk extends CustomPainter {
  _ScaledInk(this.strokes, this.scale, this.brightness, this.color);

  final List<StrokeItem> strokes;
  final double scale;
  final Brightness brightness;
  final Color? color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..scale(scale);
    for (final s in strokes) {
      paintStroke(canvas, s, color ?? displayInk(s.color, brightness));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScaledInk old) => old.strokes != strokes || old.scale != scale || old.color != color;
}
