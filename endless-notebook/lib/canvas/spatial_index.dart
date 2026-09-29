import 'dart:ui';

/// Uniform grid over the unbounded page, for culling and hit testing.
/// Cells are 512 page px; an item is listed in every cell its bounds touch.
class SpatialIndex {
  static const cell = 512.0;

  final _cells = <(int, int), Set<String>>{};
  final _rects = <String, Rect>{};

  int get length => _rects.length;

  Iterable<(int, int)> _cellsFor(Rect r) sync* {
    final x0 = (r.left / cell).floor(), x1 = (r.right / cell).floor();
    final y0 = (r.top / cell).floor(), y1 = (r.bottom / cell).floor();
    for (var x = x0; x <= x1; x++) {
      for (var y = y0; y <= y1; y++) {
        yield (x, y);
      }
    }
  }

  void insert(String id, Rect bounds) {
    remove(id);
    _rects[id] = bounds;
    for (final c in _cellsFor(bounds)) {
      (_cells[c] ??= <String>{}).add(id);
    }
  }

  void remove(String id) {
    final r = _rects.remove(id);
    if (r == null) return;
    for (final c in _cellsFor(r)) {
      final set = _cells[c];
      set?.remove(id);
      if (set != null && set.isEmpty) _cells.remove(c);
    }
  }

  /// Ids whose bounds overlap [area].
  Set<String> query(Rect area) {
    final out = <String>{};
    for (final c in _cellsFor(area)) {
      final set = _cells[c];
      if (set == null) continue;
      for (final id in set) {
        if (_rects[id]!.overlaps(area)) out.add(id);
      }
    }
    return out;
  }
}
