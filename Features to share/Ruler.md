# Ruler

An on-screen ruler you can move, turn and stretch with fingers, or by dragging either end. The pen snaps to its edge. A chip on the ruler shows the angle and, while you draw along it, the length of the line. Tapping the chip opens a menu where you can type an exact angle or pick a preset one, and choose the unit (cm, mm or inches).

This is a copy for reading. The code lives in the Endless app (Flutter/Dart). Whole files are copied as they are. From the big canvas file (`lib/canvas/ink_canvas.dart`) only the parts this feature uses are copied, with their line numbers, so some of them start or end partway through a method.

## The ruler itself

### `lib/canvas/ruler.dart` (whole file)

The ruler's position, angle and length; how it moves, turns and stretches; snapping to its edges; units; and how it's drawn (ticks, numbers, and the angle and length chip).

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/colors.dart';
import 'canvas_view.dart';

/// What the ruler measures in. Lengths are page lengths: an inch is 160
/// page px (Android's dp), so at 100% the ruler matches a real one.
enum RulerUnit { cm, mm, inch }

extension RulerUnitText on RulerUnit {
  String get label => switch (this) {
        RulerUnit.cm => 'cm',
        RulerUnit.mm => 'mm',
        RulerUnit.inch => 'in',
      };

  /// Page px per centimeter or inch (mm ticks use the centimeter).
  double get pxPerMajor => this == RulerUnit.inch ? 160 : 160 / 2.54;

  /// [px] page px as "4.2 cm", "42 mm" or "1.65 in".
  String format(double px) => switch (this) {
        RulerUnit.cm => '${(px / pxPerMajor).toStringAsFixed(1)} cm',
        RulerUnit.mm => '${(px / pxPerMajor * 10).round()} mm',
        RulerUnit.inch => '${(px / pxPerMajor).toStringAsFixed(2)} in',
      };
}

/// Degrees with up to three decimals and no trailing zeros ("22.5°").
String formatDegrees(double deg) {
  var s = deg.toStringAsFixed(3);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  if (s == '-0') s = '0';
  return '${s.replaceFirst('-', '−')}°';
}

/// One long edge of the ruler: a line through [origin] along [dir], with
/// [normal] pointing away from the ruler.
class RulerEdge {
  const RulerEdge(this.origin, this.dir, this.normal);

  final Offset origin;
  final Offset dir;
  final Offset normal;

  /// [p] moved onto the edge, [gap] px outside it.
  Offset snap(Offset p, double gap) {
    final d = p - origin;
    return origin + dir * (d.dx * dir.dx + d.dy * dir.dy) + normal * gap;
  }
}

/// The on-screen ruler (Tools.dc.html): 72 px tall, 620 long to start. It
/// lives in screen space so it stays put while the page pans. Fingers move,
/// turn and (pinching along it) lengthen it; dragging either end (finger or
/// pen) swings and stretches it about the other end; the pen snaps to
/// whichever long edge it starts near; tapping the angle chip sets an exact
/// angle.
class Ruler extends ChangeNotifier {
  static const thickness = 72.0;
  static const minLength = 240.0;
  static const maxLength = 2400.0;

  /// The pen snaps when it starts this close (screen px) outside an edge.
  static const reach = 28.0;

  /// How far in from each end a drag grabs that end.
  static const endZone = 48.0;

  bool _visible = false;
  Offset _center = Offset.zero;
  double _length = 620;
  double _fingerAngle = 0;
  double _angle = 0;
  double? _measure;

  // An end being dragged: which (−1 left, 1 right), the other end (which
  // stays put), and how far in from the end it was grabbed.
  int _grabSide = 0;
  Offset _anchor = Offset.zero;
  double _grabInset = 0;

  bool get visible => _visible;
  Offset get center => _center;
  double get length => _length;

  /// Rotation in radians (screen convention: positive turns clockwise).
  double get angle => _angle;

  /// The angle shown: degrees counter-clockwise from level, −180 to 180.
  double get degrees {
    var d = -_angle * 180 / math.pi;
    d = (d + 180) % 360 - 180;
    return d <= -180 ? d + 360 : d;
  }

  /// Length (page px) of the line being drawn along the ruler, or null.
  double? get measure => _measure;
  set measure(double? v) {
    if (v == _measure) return;
    _measure = v;
    notifyListeners();
  }

  Offset get _u => Offset(math.cos(_angle), math.sin(_angle));
  Offset get _v => Offset(-math.sin(_angle), math.cos(_angle));

  /// Shows the ruler level, across the lower middle of a [view]-sized canvas.
  void show(Size view) {
    _visible = true;
    _center = Offset(view.width / 2, view.height * 0.62);
    _fingerAngle = _angle = 0;
    _measure = null;
    notifyListeners();
  }

  void hide() {
    if (!_visible) return;
    _visible = false;
    notifyListeners();
  }

  void moveBy(Offset delta) {
    _center += delta;
    _measure = null;
    notifyListeners();
  }

  /// Turns by [radians] about [focal] (screen), as fingers do: the angle
  /// settles on whole degrees, and on multiples of 45° within 2°.
  void rotateAbout(Offset focal, double radians) {
    _fingerAngle += radians;
    _turnTo(_settle(_fingerAngle), focal);
  }

  /// Whole degrees, and multiples of 45° within 2° (radians in and out).
  static double _settle(double radians) {
    var deg = radians * 180 / math.pi;
    final nearest = (deg / 45).round() * 45.0;
    deg = (deg - nearest).abs() < 2 ? nearest : deg.roundToDouble();
    return deg * math.pi / 180;
  }

  /// Which end [p] grabs: −1 the left, 1 the right, or null.
  int? endAt(Offset p) {
    if (!contains(p)) return null;
    final (pu, _) = _local(p);
    if (pu > _length / 2 - endZone) return 1;
    if (pu < -_length / 2 + endZone) return -1;
    return null;
  }

  /// Starts dragging the end [side] (see [endAt]), grabbed at [p].
  void grabEnd(int side, Offset p) {
    final (pu, _) = _local(p);
    _grabSide = side;
    _grabInset = _length / 2 - side * pu;
    _anchor = _center - _u * (side * _length / 2);
  }

  /// Moves the grabbed end to follow [p]: the other end stays put, and the
  /// ruler swings (settling like [rotateAbout]) and stretches to reach it.
  void dragEnd(Offset p) {
    if (_grabSide == 0) return;
    final d = (p - _anchor) * _grabSide.toDouble(); // pointing left to right
    if (d.distance < 20) return; // too close to the pinned end to aim
    final a = _settle(math.atan2(d.dy, d.dx));
    final u = Offset(math.cos(a), math.sin(a));
    final reach = (p - _anchor).dx * u.dx * _grabSide + (p - _anchor).dy * u.dy * _grabSide;
    _length = (reach + _grabInset).clamp(minLength, maxLength);
    _angle = _fingerAngle = a;
    _center = _anchor + u * (_grabSide * _length / 2);
    _measure = null;
    notifyListeners();
  }

  void releaseEnd() => _grabSide = 0;

  /// Sets the angle exactly: [deg] counter-clockwise from level.
  void setDegrees(double deg) {
    final a = -deg * math.pi / 180;
    _turnTo(a, _center);
    _fingerAngle = a;
  }

  void _turnTo(double a, Offset focal) {
    final delta = a - _angle;
    final d = _center - focal;
    final c = math.cos(delta), s = math.sin(delta);
    _center = focal + Offset(c * d.dx - s * d.dy, s * d.dx + c * d.dy);
    _angle = a;
    _measure = null;
    notifyListeners();
  }

  /// Lengthens (or shortens) it by [factor], about its center.
  void resizeBy(double factor) {
    _length = (_length * factor).clamp(minLength, maxLength);
    _measure = null;
    notifyListeners();
  }

  (double, double) _local(Offset p) {
    final d = p - _center;
    return (d.dx * _u.dx + d.dy * _u.dy, d.dx * _v.dx + d.dy * _v.dy);
  }

  bool contains(Offset p) {
    if (!_visible) return false;
    final (pu, pv) = _local(p);
    return pu.abs() <= _length / 2 && pv.abs() <= thickness / 2;
  }

  /// Whether [p] is on the angle chip (a 120 × 44 target around it).
  bool chipContains(Offset p) {
    if (!_visible) return false;
    final (pu, pv) = _local(p);
    return pu.abs() <= 60 && (pv - chipCenter.dy).abs() <= 22;
  }

  /// The chip's center in the ruler's own coordinates.
  static const chipCenter = Offset(0, 12);

  /// The edge the pen snaps to when it lands at [p], or null.
  RulerEdge? edgeNear(Offset p) {
    if (!_visible) return null;
    final (pu, pv) = _local(p);
    if (pu.abs() > _length / 2 + reach || pv.abs() > thickness / 2 + reach) return null;
    final top = pv < 0;
    final normal = top ? -_v : _v;
    return RulerEdge(_center + normal * (thickness / 2), _u, normal);
  }
}

/// Draws the ruler: a translucent strip with unit ticks along its top edge
/// (they follow the page's zoom), numbers under the whole units, and the
/// angle (and, while drawing along it, the line's length) in a dark chip.
class RulerPainter extends CustomPainter {
  RulerPainter(this.ruler, this.vp, this.unit, this.colors) : super(repaint: Listenable.merge([ruler, vp]));

  final Ruler ruler;
  final CanvasView vp;
  final RulerUnit unit;
  final EndlessColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (!ruler.visible) return;
    canvas
      ..save()
      ..translate(ruler.center.dx, ruler.center.dy)
      ..rotate(ruler.angle);
    final rect = Rect.fromCenter(center: Offset.zero, width: ruler.length, height: Ruler.thickness);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    // box-shadow: 0 12px 24px -14px shadow. Like CSS, only outside the
    // ruler: the face is see-through.
    canvas
      ..save()
      ..clipPath(Path.combine(
        PathOperation.difference,
        Path()..addRect(rect.inflate(60)),
        Path()..addRRect(rrect),
      ))
      ..drawRRect(
        rrect.shift(const Offset(0, 12)).deflate(14),
        Paint()
          ..color = colors.shadow
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      )
      ..restore();
    canvas.drawRRect(rrect, Paint()..color = colors.surface.withValues(alpha: 0.82));
    canvas
      ..save()
      ..clipRRect(rrect);
    _ticks(canvas, rect);
    canvas.restore();
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = colors.text.withValues(alpha: 0.35),
    );
    // Grips at both ends: drag one to swing and stretch the ruler.
    final grip = Paint()
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..color = colors.textFaint;
    for (final side in [-1.0, 1.0]) {
      final x = side * (ruler.length / 2 - 16);
      for (final dx in [-4.0, 0.0, 4.0]) {
        canvas.drawLine(Offset(x + dx, 10), Offset(x + dx, 28), grip);
      }
    }

    final measure = ruler.measure;
    final text = measure == null ? formatDegrees(ruler.degrees) : '${formatDegrees(ruler.degrees)} · ${unit.format(measure)}';
    final label = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontFamily: 'Figtree', fontSize: 14, fontWeight: FontWeight.w600, color: colors.onInverse),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final chip = Rect.fromCenter(center: Ruler.chipCenter, width: label.width + 20, height: label.height + 8);
    canvas.drawRRect(RRect.fromRectAndRadius(chip, const Radius.circular(999)), Paint()..color = colors.inverse);
    label.paint(canvas, chip.topLeft + const Offset(10, 4));
    canvas.restore();
  }

  /// Ticks from a zero 12 px in from the left end. Each level is drawn only
  /// while its ticks stay at least 5 px apart; numbers need 28 px.
  void _ticks(Canvas canvas, Rect rect) {
    // Tick levels as (fraction of the major unit, tick height).
    final levels = unit == RulerUnit.inch
        ? const [(16, 22.0), (8, 17.0), (4, 13.0), (2, 10.0), (1, 7.0)] // in sixteenths
        : const [(10, 22.0), (5, 17.0), (1, 12.0)]; // in millimeters
    final per = levels.first.$1; // finest ticks per major unit
    final major = unit.pxPerMajor * vp.scale;
    final fine = major / per;
    var finest = per; // zoomed far out: whole units only
    for (final (n, _) in levels.reversed) {
      if (fine * n >= 5) {
        finest = n;
        break;
      }
    }
    var labelEvery = 1;
    while (major * labelEvery < 28) {
      labelEvery *= 2;
    }
    final paint = Paint()..color = colors.text;
    final x0 = rect.left + 12;
    final count = ((rect.right - 4 - x0) / fine).floor();
    for (var k = 0; k <= count; k += finest) {
      final level = levels.firstWhere((l) => k % l.$1 == 0);
      final majorTick = k % per == 0;
      final x = x0 + k * fine;
      canvas.drawRect(Rect.fromLTWH(x, rect.top, majorTick ? 1.5 : 1, level.$2), paint);
      final n = k ~/ per;
      if (majorTick && n % labelEvery == 0) {
        final number = TextPainter(
          text: TextSpan(
            text: '${unit == RulerUnit.mm ? n * 10 : n}',
            style: TextStyle(fontFamily: 'Figtree', fontSize: 10, color: colors.textMuted),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        number.paint(canvas, Offset(x - number.width / 2, rect.top + 24));
      }
    }
  }

  @override
  bool shouldRepaint(RulerPainter old) =>
      old.ruler != ruler || old.colors != colors || old.unit != unit || old.vp != vp;
}
```

## The ruler's menu (angle, length, units)

### `lib/ui/canvas/ruler_menu.dart` (whole file)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../canvas/ruler.dart';
import '../../state/settings.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart' show Radii, TypeScale;
import '../common.dart';
import '../icons.dart';
import 'pen_settings.dart';

/// The number pad's delete key.
const backspace = '⌫';

/// Angles offered as one tap.
const rulerPresets = [0, 15, 30, 45, 60, 75, 90, 120, 135, 150, 180];

/// Opened by tapping the ruler's angle chip: a number pad for an exact
/// angle (up to three decimals, counter-clockwise positive), preset angles,
/// and the ruler's unit.
Future<void> showRulerMenu(BuildContext context, Ruler ruler) => showDialog<void>(
  context: context,
  builder: (_) => RulerMenu(ruler: ruler),
);

class RulerMenu extends ConsumerStatefulWidget {
  const RulerMenu({super.key, required this.ruler});

  final Ruler ruler;

  @override
  ConsumerState<RulerMenu> createState() => _RulerMenuState();
}

class _RulerMenuState extends ConsumerState<RulerMenu> {
  /// What's been typed ("" shows the current angle).
  String _typed = '';

  double? get _value => double.tryParse(_typed.replaceAll(RegExp(r'\.$'), ''));

  void _key(String k) {
    var next = _typed;
    switch (k) {
      case backspace:
        if (next.isNotEmpty) next = next.substring(0, next.length - 1);
      case '±':
        next = next.startsWith('-') ? next.substring(1) : '-$next';
      case '.':
        if (!next.contains('.')) next = '$next.';
      default:
        final dot = next.indexOf('.');
        if (dot >= 0 && next.length - dot > 3) return; // three decimals at most
        next = '$next$k';
    }
    final v = double.tryParse(next.replaceAll(RegExp(r'\.$'), ''));
    if (v != null && v.abs() > 180) return;
    setState(() => _typed = next);
  }

  void _set(double deg) {
    widget.ruler.setDegrees(deg);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final unit = ref.watch(settingsProvider.select((s) => s.rulerUnit));
    final value = _value;
    final shown = _typed.isEmpty ? formatDegrees(widget.ruler.degrees) : '${_typed.replaceFirst('-', '−')}°';

    Widget key(String k, {String? label}) => Expanded(
      child: Semantics(
        button: true,
        label: label ?? k,
        excludeSemantics: true,
        child: Material(
          color: c.surfaceSunk,
          borderRadius: BorderRadius.circular(Radii.key),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.key),
            onTap: () => _key(k),
            child: SizedBox(
              height: 48,
              child: Center(
                child: k == backspace
                    ? EIcon(EIcons.backspace, size: 22, color: c.text)
                    : Text(
                        k,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: c.text),
                      ),
              ),
            ),
          ),
        ),
      ),
    );

    final pad = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Semantics(
          liveRegion: true,
          label: 'Angle $shown',
          excludeSemantics: true,
          child: Container(
            height: 56,
            margin: const EdgeInsets.only(bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.centerRight,
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: _typed.isEmpty ? c.lineStrong : c.accent, width: 1.5),
              borderRadius: BorderRadius.circular(Radii.button),
            ),
            child: Text(
              shown,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: _typed.isEmpty ? c.textMuted : c.text),
            ),
          ),
        ),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['±', '0', '.'],
        ])
          Row(
            spacing: 6,
            children: [
              for (final k in row)
                key(
                  k,
                  label: switch (k) {
                    '±' => 'Plus or minus',
                    '.' => 'Decimal point',
                    _ => null,
                  },
                ),
            ],
          ),
        Row(
          spacing: 6,
          children: [
            key(backspace, label: 'Delete digit'),
            Expanded(
              flex: 2,
              child: Semantics(
                button: true,
                enabled: value != null,
                label: 'Set angle',
                excludeSemantics: true,
                child: Material(
                  color: value == null ? c.side : c.inverse,
                  borderRadius: BorderRadius.circular(Radii.key),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Radii.key),
                    onTap: value == null ? null : () => _set(value),
                    child: SizedBox(
                      height: 48,
                      child: Center(
                        child: Text(
                          'Set angle',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: value == null ? c.textFaint : c.onInverse,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );

    final presets = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final p in rulerPresets)
          Semantics(
            button: true,
            label: 'Set $p°',
            excludeSemantics: true,
            child: Material(
              color: widget.ruler.degrees == p ? c.inverse : Colors.transparent,
              shape: StadiumBorder(side: BorderSide(color: widget.ruler.degrees == p ? c.inverse : c.lineStrong)),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => _set(p.toDouble()),
                child: Container(
                  height: 44,
                  constraints: const BoxConstraints(minWidth: 56),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      '$p°',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: widget.ruler.degrees == p ? c.onInverse : c.text,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    final units = Semantics(
      container: true,
      label: 'Ruler units',
      explicitChildNodes: true,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: c.side, borderRadius: BorderRadius.circular(Radii.button)),
        child: Row(
          spacing: 2,
          children: [
            for (final (u, label) in const [
              (RulerUnit.cm, 'Centimeters'),
              (RulerUnit.mm, 'Millimeters'),
              (RulerUnit.inch, 'Inches'),
            ])
              Expanded(
                child: SettingsSegment(
                  label: u.label,
                  semanticLabel: label,
                  selected: unit == u,
                  onTap: () => ref.read(settingsProvider.notifier).apply((s) => s.copyWith(rulerUnit: u)),
                ),
              ),
          ],
        ),
      ),
    );

    Widget section(String text) => Text(text.toUpperCase(), style: TypeScale.sectionLabel.copyWith(color: c.textMuted));

    return Dialog(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.dialog),
        side: BorderSide(color: c.line),
      ),
      child: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Ruler', style: TypeScale.panelTitle.copyWith(color: c.text)),
                  ),
                  ChromeButton(
                    label: 'Close',
                    icon: EIcons.close,
                    foreground: c.textMuted,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 24,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 10,
                      children: [section('Angle'), pad],
                    ),
                  ),
                  SizedBox(
                    width: 260,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 10,
                      children: [
                        section('Presets'),
                        presets,
                        const SizedBox(height: 4),
                        section('Units'),
                        units,
                        Text(
                          'Counter-clockwise is positive. Pinch along the ruler to make it longer or shorter. '
                          'It measures the page: at 100% it matches a real ruler.',
                          style: TextStyle(fontSize: 13, height: 1.4, color: c.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

## How the canvas uses it

### `lib/canvas/ink_canvas.dart`, lines 250–262

The canvas's ruler state.

```dart
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
```

### `lib/canvas/ink_canvas.dart`, lines 636–662

A finger landing on the ruler: on an end, it swings and stretches it; elsewhere, fingers move it; on the chip, a tap.

```dart
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
      if (_viewOnly) {
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
```

### `lib/canvas/ink_canvas.dart`, lines 851–914

Fingers moving: move, pinch to lengthen, and turn the ruler. Lifting a finger after a tap on the chip opens the menu.

```dart

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
      case _Touch.graph:
        if (pointer == _tapFinger) return; // still a tap
        _touchGraph(before.$1, after.$1, factor);
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
    if (_touches.isEmpty) {
      if (_touch == _Touch.graph) _graphId = null;
      _touch = _Touch.navigate;
    }
  }

  /// Drops every finger (the pen came down), landing a selection pinch.
```

### `lib/canvas/ink_canvas.dart`, lines 966–976

The pen on a ruler end or on the chip.

```dart
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
```

### `lib/canvas/ink_canvas.dart`, lines 1045–1049

A stroke that starts near an edge follows it.

```dart
        // written on it.
        _inkTarget = top != null && top is InkHolder && (top as InkHolder).takesInkAt(page) ? top.id : null;
        _rulerEdge = pane.ruler.edgeNear(e.localPosition);
        pane.ruler.measure = null;
        active.begin(
```

### `lib/canvas/ink_canvas.dart`, lines 1072–1079

```dart
  /// Drags the ruler's [side] end (−1 left, 1 right) with this pointer.
  void _startRulerEnd(PointerDownEvent e, int side) {
    _drawPointer = e.pointer;
    _drawAt = e.localPosition;
    _hover.value = null;
    _drag = _Drag.rulerEnd;
    pane.ruler.grabEnd(side, e.localPosition);
  }
```

### `lib/canvas/ink_canvas.dart`, lines 1137–1140

```dart
      case _Drag.rulerChip:
        if ((e.localPosition - _chipDown).distance > 10) _chipMoved = true;
      case _Drag.rulerEnd:
        pane.ruler.dragEnd(e.localPosition);
```

### `lib/canvas/ink_canvas.dart`, lines 1195–1198

```dart
      case _Drag.rulerChip:
        if (!_chipMoved) _openRulerMenu();
      case _Drag.rulerEnd:
        pane.ruler.releaseEnd();
```

### `lib/canvas/ink_canvas.dart`, lines 1229–1232

```dart
  void _openRulerMenu() {
    _hover.value = null;
    showRulerMenu(context, pane.ruler);
  }
```

### `lib/canvas/ink_canvas.dart`, lines 1296–1323

Ink drawn along the ruler lands on its edge, and the chip shows the line's length as it's drawn.

```dart
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
```

### `lib/canvas/ink_canvas.dart`, lines 2737–2737

Where the ruler is painted over the page.

```dart
              IgnorePointer(child: CustomPaint(painter: RulerPainter(pane.ruler, _vp, settings.rulerUnit, colors))),
```

## Turning it on, and the unit setting

### `lib/ui/canvas/canvas_screen.dart`, lines 76–76

```dart
const rulerHint = 'Two fingers rotate the ruler · the pen snaps to its edge';
```

### `lib/ui/canvas/canvas_screen.dart`, lines 140–148

```dart
    case 'Ruler':
      // Picking it again puts it away.
      if (pane.ruler.visible) {
        pane.ruler.hide();
        return;
      }
      pane.ruler.show(pane.view.size);
      if (!ref.read(settingsProvider).tool.inks) useTool(CanvasTool.pen);
      hint?.call(rulerHint);
```

### `lib/ui/canvas/left_rail.dart`, lines 69–70

```dart
  RailGroup('tools', 'Ruler, laser & view', EIcons.ruler, [
    RailItem('Ruler', 'Two fingers rotate · pen snaps', EIcons.ruler, 'The ruler', isTool: true),
```

### `lib/state/settings.dart`, lines 113–114

```dart
  /// What the ruler's ticks measure.
  final RulerUnit rulerUnit;
```

