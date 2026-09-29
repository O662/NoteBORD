import 'package:flutter/widgets.dart';

/// Pan and zoom of the endless page: `screen = page × scale + translation`.
class CanvasView extends ChangeNotifier {
  static const minScale = 0.1;
  static const maxScale = 8.0;

  /// Zoom steps used by the + and − buttons.
  static const steps = [0.1, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0];

  CanvasView({this.home = Offset.zero}) : _translation = home;

  /// Where page (0, 0) sits on screen at 100% ("reset" returns here).
  final Offset home;

  double _scale = 1;
  Offset _translation;
  Size size = Size.zero;

  double get scale => _scale;
  Offset get translation => _translation;

  Offset toPage(Offset screen) => (screen - _translation) / _scale;
  Offset toScreen(Offset page) => page * _scale + _translation;

  /// The visible part of the page, in page coordinates.
  Rect get visiblePage => Rect.fromPoints(toPage(Offset.zero), toPage(size.bottomRight(Offset.zero)));

  Matrix4 get matrix => Matrix4.identity()
    ..translateByDouble(_translation.dx, _translation.dy, 0, 1)
    ..scaleByDouble(_scale, _scale, 1, 1);

  void panBy(Offset delta) {
    if (delta == Offset.zero) return;
    _translation += delta;
    notifyListeners();
  }

  /// Zooms by [factor], keeping the page point under [focal] (screen) fixed.
  void zoomAt(Offset focal, double factor) => setScale(_scale * factor, focal: focal);

  void setScale(double scale, {Offset? focal}) {
    final s = scale.clamp(minScale, maxScale);
    final f = focal ?? size.center(Offset.zero);
    final page = toPage(f);
    _scale = s;
    _translation = f - page * s;
    notifyListeners();
  }

  /// Moves and zooms at once: the page point that was under [fromFocal]
  /// ends up under [toFocal], with the scale multiplied by [factor].
  void transform({required Offset fromFocal, required Offset toFocal, required double factor}) {
    final page = toPage(fromFocal);
    _scale = (_scale * factor).clamp(minScale, maxScale);
    _translation = toFocal - page * _scale;
    notifyListeners();
  }

  void zoomStep(int direction) {
    final next = direction > 0
        ? steps.firstWhere((s) => s > _scale + 0.001, orElse: () => maxScale)
        : steps.lastWhere((s) => s < _scale - 0.001, orElse: () => minScale);
    setScale(next);
  }

  /// Centers [page] on screen.
  void centerOn(Offset page) {
    _translation = size.center(Offset.zero) - page * _scale;
    notifyListeners();
  }

  /// Fits [content] (page coords) inside [area] (screen coords).
  void fit(Rect content, Rect area) {
    if (content.isEmpty || area.isEmpty) return;
    final s = (area.width / content.width).clamp(minScale, 1.0).toDouble();
    final s2 = (area.height / content.height).clamp(minScale, 1.0).toDouble();
    _scale = s < s2 ? s : s2;
    _translation = area.center - content.center * _scale;
    notifyListeners();
  }

  void reset() {
    _scale = 1;
    _translation = home;
    notifyListeners();
  }
}
