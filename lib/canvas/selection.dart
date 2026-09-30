import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../board/model.dart';

/// Move, uniform scale and rotation: `p' = scale · R(rotation) · p + offset`.
@immutable
class Similarity {
  const Similarity({this.scale = 1, this.rotation = 0, this.offset = Offset.zero});

  const Similarity.translate(this.offset)
      : scale = 1,
        rotation = 0;

  /// Scales and rotates about [pivot], which stays put.
  factory Similarity.about(Offset pivot, {double scale = 1, double rotation = 0}) {
    final r = Similarity(scale: scale, rotation: rotation);
    return Similarity(scale: scale, rotation: rotation, offset: pivot - r.apply(pivot));
  }

  static const identity = Similarity();

  final double scale;
  final double rotation;
  final Offset offset;

  bool get isIdentity => scale == 1 && rotation == 0 && offset == Offset.zero;

  Offset apply(Offset p) {
    final c = math.cos(rotation) * scale, s = math.sin(rotation) * scale;
    return Offset(c * p.dx - s * p.dy + offset.dx, s * p.dx + c * p.dy + offset.dy);
  }

  /// This transform, then [next].
  Similarity then(Similarity next) =>
      Similarity(scale: scale * next.scale, rotation: rotation + next.rotation, offset: next.apply(offset));

  Matrix4 get matrix => Matrix4.identity()
    ..translateByDouble(offset.dx, offset.dy, 0, 1)
    ..rotateZ(rotation)
    ..scaleByDouble(scale, scale, 1, 1);

  /// A stroke moved by this transform (its width scales too).
  StrokeItem applyTo(StrokeItem s) {
    InkPoint move(InkPoint p) {
      final q = apply(Offset(p.x, p.y));
      return InkPoint(q.dx, q.dy, p.pressure, p.t);
    }

    return s.copyWith(pagePoints: [for (final p in s.pageInk) move(p)], width: s.width * scale);
  }

  /// Any item moved by this transform: a box turns and scales about its
  /// center, and what's inside it scales with it.
  Item applyToItem(Item item) => switch (item) {
        StrokeItem s => applyTo(s),
        BoxItem b => b.placed(center: apply(b.center), rotation: b.rotation + rotation * 180 / math.pi, scale: scale),
        UnknownItem u => u,
      };
}

/// Which primary action the selection toolbar leads with: Convert.png or
/// RememberMark.png.
enum SelectionMenu { convert, remember }

/// The selection's box in page space: around one box item it follows the
/// item's rotation; otherwise it is upright.
@immutable
class SelectionFrame {
  const SelectionFrame(this.center, this.size, [this.angle = 0]);

  factory SelectionFrame.around(Rect r) => SelectionFrame(r.center, r.size);

  final Offset center;
  final Size size;
  final double angle;

  Offset _at(double fx, double fy) {
    final d = Offset(fx * size.width, fy * size.height);
    final c = math.cos(angle), s = math.sin(angle);
    return center + Offset(c * d.dx - s * d.dy, s * d.dx + c * d.dy);
  }

  /// Top-left, top-right, bottom-right, bottom-left.
  List<Offset> get corners => [_at(-.5, -.5), _at(.5, -.5), _at(.5, .5), _at(-.5, .5)];

  /// Middle of the top, right, bottom and left edges.
  List<Offset> get sides => [_at(0, -.5), _at(.5, 0), _at(0, .5), _at(-.5, 0)];

  /// Which way is down along the box (a unit vector).
  Offset get down => Offset(-math.sin(angle), math.cos(angle));

  Path path(double radius) {
    final rect = Rect.fromCenter(center: Offset.zero, width: size.width, height: size.height);
    final m = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..rotateZ(angle);
    return (Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)))).transform(m.storage);
  }
}

/// What's selected in a pane, its dashed outline, and any move, resize or
/// rotation being dragged right now.
class Selection extends ChangeNotifier {
  Set<String> _ids = const {};
  Path? _outline;
  int? _outlineRevision;
  Similarity? _live;

  /// Set by the rail's "Need to remember" and "Convert to text".
  SelectionMenu menu = SelectionMenu.convert;

  Set<String> get ids => _ids;
  bool get isEmpty => _ids.isEmpty;
  bool get isNotEmpty => _ids.isNotEmpty;

  /// The transform being dragged, not yet applied to the page.
  Similarity? get live => _live;

  /// Selects [ids]. [outline] is the lasso loop (page space), drawn while
  /// the page is still at [revision]; without one the outline is a box.
  void select(Iterable<String> ids, {Path? outline, int? revision}) {
    _ids = Set.unmodifiable(ids);
    _outline = outline;
    _outlineRevision = revision;
    _live = null;
    notifyListeners();
  }

  void clear() {
    if (_ids.isEmpty && _live == null) return;
    _ids = const {};
    _outline = null;
    _live = null;
    notifyListeners();
  }

  set live(Similarity? t) {
    _live = t;
    notifyListeners();
  }

  /// After a drag lands on the page (now at [revision]), the lasso loop
  /// follows it.
  void landed(Similarity t, int revision) {
    _outline = _outline?.transform(t.matrix.storage);
    _outlineRevision = revision;
    _live = null;
    notifyListeners();
  }

  /// Keeps only ids still on the page (after an undo, say).
  void retain(bool Function(String id) exists) {
    if (_ids.every(exists)) return;
    _ids = Set.unmodifiable(_ids.where(exists));
    _outline = null;
    notifyListeners();
  }

  /// The lasso loop, if it still matches the page at [revision].
  Path? outlineAt(int revision) => revision == _outlineRevision ? _outline : null;
}
