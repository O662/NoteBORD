import 'package:flutter/widgets.dart';

import 'canvas_view.dart';

/// The laser pointer's trail (Tools.dc.html). Points live in page space so
/// the trail stays on what it points at; each fades out a second after it
/// was drawn. Nothing here is ever saved.
class LaserTrail extends ChangeNotifier {
  static const fade = Duration(seconds: 1);

  final _segments = <List<(Offset, Duration)>>[];

  /// Clock, advanced by the canvas's ticker.
  Duration now = Duration.zero;

  /// The pen is down: the pointer dot shows at the end of the trail.
  bool down = false;

  bool get isEmpty => _segments.isEmpty;

  Iterable<List<(Offset, Duration)>> get segments => _segments;

  void start(Offset page) {
    _segments.add([(page, now)]);
    down = true;
    notifyListeners();
  }

  void add(Offset page) {
    if (_segments.isEmpty) return start(page);
    _segments.last.add((page, now));
    notifyListeners();
  }

  void end() {
    down = false;
    notifyListeners();
  }

  /// Advances the clock and drops points older than [fade].
  void tick(Duration t) {
    now = t;
    for (final s in _segments) {
      s.removeWhere((p) => now - p.$2 > fade);
    }
    _segments.removeWhere((s) => s.isEmpty && !(down && identical(s, _segments.last)));
    notifyListeners();
  }

  void clear() {
    _segments.clear();
    down = false;
    notifyListeners();
  }
}

class LaserPainter extends CustomPainter {
  LaserPainter(this.trail, this.vp, this.color) : super(repaint: Listenable.merge([trail, vp]));

  final LaserTrail trail;
  final CanvasView vp;
  final Color color;

  double _life(Duration t) => 1 - ((trail.now - t).inMilliseconds / LaserTrail.fade.inMilliseconds).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    for (final seg in trail.segments) {
      for (var i = 1; i < seg.length; i++) {
        final life = _life(seg[i].$2);
        canvas.drawLine(
          vp.toScreen(seg[i - 1].$1),
          vp.toScreen(seg[i].$1),
          Paint()
            ..color = color.withValues(alpha: 0.85 * life)
            ..strokeWidth = 5 + life
            ..strokeCap = StrokeCap.round,
        );
      }
    }
    final last = trail.segments.lastOrNull?.lastOrNull;
    if (trail.down && last != null) {
      final at = vp.toScreen(last.$1);
      canvas
        ..drawCircle(at, 16, Paint()..color = color.withValues(alpha: 0.22))
        ..drawCircle(at, 7, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(LaserPainter old) => old.trail != trail || old.color != color || old.vp != vp;
}
