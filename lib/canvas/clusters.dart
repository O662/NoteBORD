import 'dart:ui';

import '../board/model.dart';

// Highlights over a page (Update 04: History's "Show changes", the conflict
// screen's "only here", Recovery's "Brought back"): the items in question
// grouped into the boxes a person would draw around them.

/// [rects] merged where they overlap or are within [gap] of each other.
List<Rect> clusterRects(Iterable<Rect> rects, {double gap = 24}) {
  final out = <Rect>[for (final r in rects) if (!r.isEmpty || r.width > 0 || r.height > 0) r];
  var merged = true;
  while (merged) {
    merged = false;
    for (var i = 0; i < out.length && !merged; i++) {
      for (var j = i + 1; j < out.length; j++) {
        if (out[i].inflate(gap / 2).overlaps(out[j].inflate(gap / 2))) {
          out[i] = out[i].expandToInclude(out[j]);
          out.removeAt(j);
          merged = true;
          break;
        }
      }
    }
  }
  return out;
}

/// The boxes around [items].
List<Rect> clustersOf(Iterable<Item> items, {double gap = 24}) => clusterRects([for (final i in items) i.bounds], gap: gap);

/// What [page] has that [before] doesn't (by item id), and what it lost.
({List<Item> added, List<Item> removed}) itemChanges(BoardPage? before, BoardPage page) {
  final had = {for (final i in before?.items ?? const <Item>[]) i.id};
  final has = {for (final i in page.items) i.id};
  return (
    added: [for (final i in page.items) if (!had.contains(i.id)) i],
    removed: [for (final i in before?.items ?? const <Item>[]) if (!has.contains(i.id)) i],
  );
}

/// "strokes", "sticky notes"… for [n] items like [item].
String itemKind(Item item, int n) {
  final (one, many) = switch (item) {
    StrokeItem() => ('stroke', 'strokes'),
    StickyItem() => ('sticky note', 'sticky notes'),
    ImageItem() => ('image', 'images'),
    ShapeItem() => ('shape', 'shapes'),
    TextItem() => ('text box', 'text boxes'),
    AudioItem() => ('recording', 'recordings'),
    VideoItem() => ('video', 'videos'),
    _ => ('item', 'items'),
  };
  return n == 1 ? one : many;
}

/// "+12 strokes · 1 image", "−3 strokes", or null when nothing was added
/// or taken away.
String? changeSummary(List<Item> added, List<Item> removed) {
  String? group(List<Item> items, String sign) {
    if (items.isEmpty) return null;
    final byKind = <String, (Item, int)>{};
    for (final i in items) {
      final k = itemKind(i, 2);
      final was = byKind[k];
      byKind[k] = (i, (was?.$2 ?? 0) + 1);
    }
    final kinds = byKind.values.toList()..sort((a, b) => b.$2.compareTo(a.$2));
    return [
      for (final (i, (item, n)) in kinds.take(2).indexed) '${i == 0 ? sign : ''}$n ${itemKind(item, n)}',
    ].join(' · ');
  }

  final parts = [?group(added, '+'), ?group(removed, '−')];
  return parts.isEmpty ? null : parts.join(' · ');
}
