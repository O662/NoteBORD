import 'dart:ui' as ui;
import 'dart:ui' show Brightness, Canvas, Paint, PaintingStyle, Radius, Rect, RRect;

import '../board/model.dart';
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
  }

  Rect? _bounds;
  int _boundsRevision = -1;

  /// Union of all item bounds, or null for an empty page.
  Rect? get contentBounds {
    if (_boundsRevision != revision) {
      _boundsRevision = revision;
      Rect? r;
      for (final i in page.items) {
        r = r == null ? i.bounds : r.expandToInclude(i.bounds);
      }
      _bounds = r;
    }
    return _bounds;
  }

  ui.Picture? _full;
  Brightness? _fullBrightness;

  /// Every item, for the map and page thumbnails.
  ui.Picture fullPicture(Brightness brightness, EndlessColors colors) {
    if (_full == null || _fullBrightness != brightness) {
      _full?.dispose();
      _full = _record(page.items, brightness, colors);
      _fullBrightness = brightness;
    }
    return _full!;
  }

  _RegionPicture? _region;

  /// Items near [visible] (page coords). The region is padded by half a
  /// screen each way so small pans reuse the same picture.
  ui.Picture regionPicture(Rect visible, Brightness brightness, EndlessColors colors) {
    final r = _region;
    if (r != null && r.brightness == brightness && r.area.contains(visible.topLeft) &&
        r.area.contains(visible.bottomRight)) {
      return r.picture;
    }
    r?.picture.dispose();
    final area = visible.inflate(visible.longestSide / 2);
    final ids = index.query(area);
    final items = [for (final i in page.items) if (ids.contains(i.id)) i];
    _region = _RegionPicture(area, brightness, _record(items, brightness, colors));
    return _region!.picture;
  }

  ui.Picture _record(List<Item> items, Brightness brightness, EndlessColors colors) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (final item in items) {
      paintItem(canvas, item, brightness, colors);
    }
    return recorder.endRecording();
  }

  void dispose() {
    _full?.dispose();
    _region?.picture.dispose();
  }
}

class _RegionPicture {
  _RegionPicture(this.area, this.brightness, this.picture);

  final Rect area;
  final Brightness brightness;
  final ui.Picture picture;
}

void paintItem(Canvas canvas, Item item, Brightness brightness, EndlessColors colors) {
  switch (item) {
    case StrokeItem s:
      final color = displayInk(s.color, brightness);
      canvas.drawPath(
        cachedOutline(s),
        Paint()
          ..color = color.withValues(alpha: inkOpacity(s.tool, s.penType))
          ..isAntiAlias = true,
      );
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
