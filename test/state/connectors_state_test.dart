import 'package:endless/board/codec.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/canvas/connectors.dart';
import 'package:endless/canvas/selection.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

final _at = DateTime.utc(2026, 10, 1, 12);

ShapeItem _box(String id, Rect r) => ShapeItem(
      id: id, x: r.left, y: r.top, z: 1, createdAt: _at, kind: ShapeType.rect, //
      w: r.width, h: r.height, stroke: tokens.inkDefaults[0],
    );

final _a = _box('it_a', const Rect.fromLTWH(100, 100, 120, 80));
final _b = _box('it_b', const Rect.fromLTWH(400, 200, 120, 80));
final _link = attachEnds(
  strokeFrom([for (var i = 0; i <= 40; i++) Offset.lerp(const Offset(160, 140), const Offset(460, 240), i / 40)!], width: 3.5)
      .copyWith(arrow: () => const ArrowHeads(end: true)),
  [_a, _b],
  slop: 16,
);

/// The notebook open, with [_a], [_b] and the arrow joining them on its page.
Future<(ProviderContainer, NotebookNotifier, String)> _open(MemoryBoardStore store) async {
  _notebook = '';
  final id = addUntitled(store);
  final c = ProviderContainer(overrides: await testOverrides(store));
  addTearDown(c.dispose);
  c.listen(loadedNotebookProvider(id), (_, _) {});
  await c.read(loadedNotebookProvider(id).future);
  c.listen(notebookProvider(id), (_, _) {});
  final n = c.read(notebookProvider(id).notifier);
  final pageId = c.read(notebookProvider(id)).pages.first.id;
  n.insertItems(pageId, [_a, _b, _link]);
  _notebook = id;
  return (c, n, pageId);
}

void main() {
  late ProviderContainer c;
  late NotebookNotifier n;
  late String pageId;
  StrokeItem link() => c.read(notebookProvider(_notebook)).pages.first[_link.id]! as StrokeItem;

  testWidgets('moving or resizing a box takes the arrow’s end along, in the same undo step', (tester) async {
    (c, n, pageId) = await _open(MemoryBoardStore());
    expect((_link.startItemId, _link.endItemId), ('it_a', 'it_b'));

    n.replaceItems(pageId, [_b.withBox(x: 450, y: 300, w: _b.w, h: _b.h)]);
    expect(link().pagePoints.last, offsetMoreOrLessEquals(_link.pagePoints.last + const Offset(50, 100), epsilon: 0.15));
    expect(link().pagePoints.first, offsetMoreOrLessEquals(_link.pagePoints.first, epsilon: 0.15));
    n.undo(pageId);
    expect(link().pagePoints.last, offsetMoreOrLessEquals(_link.pagePoints.last, epsilon: 0.15));
    n.redo(pageId);
    expect(link().pagePoints.last.dy, closeTo(_link.pagePoints.last.dy + 100, 0.15));
    n.undo(pageId);

    // Resized from its left edge: the end stays on that edge.
    n.replaceItems(pageId, [_b.withBox(x: 300, y: 200, w: 220, h: 80)]);
    expect(link().pagePoints.last.dx, closeTo(300, 0.15));
    expect(link().endItemId, 'it_b');

    // Both boxes moved together (as a selection): the whole arrow goes along.
    n.undo(pageId);
    const t = Similarity.translate(Offset(30, 40));
    n.replaceItems(pageId, [t.applyToItem(_a), t.applyToItem(_b)]);
    expect(link().pagePoints.first, offsetMoreOrLessEquals(_link.pagePoints.first + const Offset(30, 40), epsilon: 0.15));
    expect(link().pagePoints.last, offsetMoreOrLessEquals(_link.pagePoints.last + const Offset(30, 40), epsilon: 0.15));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a box and its arrow moved together stay joined; the arrow moved alone lets go', (tester) async {
    (c, n, pageId) = await _open(MemoryBoardStore());
    const t = Similarity.translate(Offset(0, 60));
    n.replaceItems(pageId, [t.applyToItem(_b), t.applyToItem(_link)]);
    expect((link().startItemId, link().endItemId), ('it_a', 'it_b')); // A's end bent back onto A
    expect(distanceToOutline(_a, link().pagePoints.first), lessThan(0.2));
    n.undo(pageId);

    // (Far enough that its end is off B: 60 px down would land on B's corner.)
    n.replaceItems(pageId, [const Similarity.translate(Offset(0, 120)).applyToItem(_link)]);
    expect((link().startItemId, link().endItemId), (null, null));
    n.undo(pageId);
    expect((link().startItemId, link().endItemId), ('it_a', 'it_b'));

    // Recoloring isn't moving: it stays joined.
    n.replaceItems(pageId, [link().copyWith(color: tokens.inkDefaults[2])]);
    expect((link().startItemId, link().endItemId), ('it_a', 'it_b'));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('deleting a box lets the arrow go; Undo joins them again', (tester) async {
    final store = MemoryBoardStore();
    (c, n, pageId) = await _open(store);
    n.removeItems(pageId, ['it_b']);
    expect((link().startItemId, link().endItemId), ('it_a', null));
    expect(link().pagePoints.last, _link.pagePoints.last); // the ink stays where it was
    n.undo(pageId);
    expect(link().endItemId, 'it_b');

    // Deleted together: nothing is left to fix.
    n.removeItems(pageId, ['it_b', _link.id]);
    n.undo(pageId);
    expect(link().endItemId, 'it_b');

    await tester.pump(const Duration(seconds: 1));
    final saved = decodePage(store.pages.values.single.values.single).items.whereType<StrokeItem>().single;
    expect((saved.startItemId, saved.endItemId), ('it_a', 'it_b'));
  });
}

/// The notebook [_open] opened.
var _notebook = '';
