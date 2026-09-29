import 'dart:ui' as ui;
import 'dart:ui' show Brightness, Canvas, Color, Paint, PaintingStyle, Path, Radius, Rect, RRect;

import '../board/model.dart';
import '../templates/templates.dart';
import '../theme/colors.dart';
import 'pens.dart';
import 'spatial_index.dart';
import 'stroke_geometry.dart';

/// A page open in the editor: its items plus the indexes and caches the
/// canvas needs. Mutated only by the notebook notifier's commands.
class PageRuntime {
  PageRuntime(this.page) {
    for (final item in page.items) {
      _byId[item.id] = item;
      index.insert(item.id, item.bounds);
    }
  }

  final BoardPage page;
  final index = SpatialIndex();
  final _byId = <String, Item>{};

  /// Bumped on every change; caches key on it.
  int revision = 0;

  String get id => page.id;
  List<Item> get items => page.items;
  Item? operator [](String id) => _byId[id];
  bool get isEmpty => page.items.isEmpty;

  int get nextZ => page.items.isEmpty ? 1 : page.items.last.z + 1;

  void insert(Item item, [int? at]) {
    if (at == null || at >= page.items.length) {
      page.items.add(item);
    } else {
      page.items.insert(at, item);
    }
    _byId[item.id] = item;
    index.insert(item.id, item.bounds);
    _changed();
  }

  /// Swaps in a new version of an item (same id), keeping its place in the
  /// z-order. Returns the old version, or null if it wasn't here.
  Item? replace(Item item) {
    final old = _byId[item.id];
    if (old == null) return null;
    page.items[page.items.indexOf(old)] = item;
    _byId[item.id] = item;
    index.insert(item.id, item.bounds);
    _changed();
    return old;
  }

  /// Removes the item and returns where it was, or null if it wasn't here.
  (int, Item)? remove(String id) {
    final item = _byId.remove(id);
    if (item == null) return null;
    final at = page.items.indexOf(item);
    page.items.removeAt(at);
    index.remove(id);
    _changed();
    return (at, item);
  }

  void _changed() {
    revision++;
    _full?.dispose();
    _full = null;
    _region?.picture.dispose();
    _region = null;
    _partial?.picture.dispose();
    _partial = null;
  }

  Rect? _bounds;
  int _boundsRevision = -1;

  /// Union of all item bounds and the template layout, or null for an
  /// empty page.
  Rect? get contentBounds {
    if (_boundsRevision != revision) {
      _boundsRevision = revision;
      Rect? r = layoutBounds(page.template);
      for (final i in page.items) {
        r = r == null ? i.bounds : r.expandToInclude(i.bounds);
      }
      _bounds = r;
    }
    return _bounds;
  }

  ui.Picture? _full;
  Brightness? _fullBrightness;

  /// Every item over the template layout, for the map and page thumbnails.
  ui.Picture fullPicture(Brightness brightness, EndlessColors colors) {
    if (_full == null || _fullBrightness != brightness) {
      _full?.dispose();
      _full = _record(page.items, brightness, colors, layout: layoutPicture(page.template, colors));
      _fullBrightness = brightness;
    }
    return _full!;
  }

  _RegionPicture? _region;
  _RegionPicture? _partial;

  /// Items near [visible] (page coords), leaving out [hidden] (items being
  /// moved, or about to be scribbled away, are drawn by an overlay). The
  /// region is padded by half a screen each way so small pans reuse the
  /// same picture. Pass the same [hidden] set while it stays the same.
  ui.Picture regionPicture(Rect visible, Brightness brightness, EndlessColors colors, {Set<String> hidden = const {}}) {
    final partial = hidden.isNotEmpty;
    final r = partial ? _partial : _region;
    if (r != null &&
        r.brightness == brightness &&
        identical(r.hidden, hidden) &&
        r.area.contains(visible.topLeft) &&
        r.area.contains(visible.bottomRight)) {
      return r.picture;
    }
    r?.picture.dispose();
    final area = visible.inflate(visible.longestSide / 2);
    final ids = index.query(area)..removeAll(hidden);
    final items = [for (final i in page.items) if (ids.contains(i.id)) i];
    final fresh = _RegionPicture(area, brightness, hidden, _record(items, brightness, colors));
    if (partial) {
      _partial = fresh;
    } else {
      _region = fresh;
    }
    return fresh.picture;
  }

  ui.Picture _record(List<Item> items, Brightness brightness, EndlessColors colors, {ui.Picture? layout}) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (layout != null) canvas.drawPicture(layout);
    for (final item in items) {
      paintItem(canvas, item, brightness, colors);
    }
    return recorder.endRecording();
  }

  void dispose() {
    _full?.dispose();
    _region?.picture.dispose();
    _partial?.picture.dispose();
  }
}

class _RegionPicture {
  _RegionPicture(this.area, this.brightness, this.hidden, this.picture);

  final Rect area;
  final Brightness brightness;
  final Set<String> hidden;
  final ui.Picture picture;
}

void paintItem(Canvas canvas, Item item, Brightness brightness, EndlessColors colors) {
  switch (item) {
    case StrokeItem s:
      paintStroke(canvas, s, displayInk(s.color, brightness));
    case UnknownItem u:
      // Kept and saved, but not drawable by this version: show its footprint.
      canvas.drawRRect(
        RRect.fromRectAndRadius(u.bounds, const Radius.circular(8)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = colors.lineStrong,
      );
  }
}

/// Draws a stroke (and its arrowheads) in [color] at the pen's opacity
/// times [opacity].
void paintStroke(Canvas canvas, StrokeItem s, Color color, {double opacity = 1}) {
  final alpha = inkOpacity(s.tool, s.penType) * opacity;
  final heads = s.arrow == null ? const <Path>[] : cachedArrowHeads(s);
  // Translucent ink with a head is drawn opaque in a layer, so the head
  // doesn't darken where it overlaps the line.
  final layered = heads.isNotEmpty && alpha < 1;
  if (layered) canvas.saveLayer(s.bounds, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
  final paint = Paint()
    ..color = layered ? color : color.withValues(alpha: alpha)
    ..isAntiAlias = true;
  canvas.drawPath(cachedOutline(s), paint);
  for (final h in heads) {
    canvas.drawPath(h, paint);
  }
  if (layered) canvas.restore();
}
