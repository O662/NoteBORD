import 'package:endless/board/ids.dart';
import 'package:endless/board/model.dart';
import 'package:endless/spelling/my_handwriting.dart';
import 'package:flutter/painting.dart' show Color;

const _tall = 'bdfhklt';
const _tails = 'gjpqy';
const lowercase = 'abcdefghijklmnopqrstuvwxyz';

/// A zig-zag the height of [ch] (small letters 1 x-height, tall ones 2,
/// tails 0.9 below the baseline), 0.6 wide.
HandGlyph zigzagGlyph(String ch) {
  final top = _tall.contains(ch) ? -2.0 : -1.0;
  final bottom = _tails.contains(ch) ? 0.9 : 0.0;
  return HandGlyph([
    [for (var k = 0; k <= 6; k++) InkPoint(0.1 * k, k.isEven ? bottom : top, 0.3 + 0.1 * (k % 3), k * 10)],
  ], 0.6);
}

/// A sample with every small letter (and [extra] letters or marks).
MyHandwriting testHand({String extra = ''}) => MyHandwriting(
      glyphs: {for (final ch in (lowercase + extra).split('')) ch: zigzagGlyph(ch)},
      createdAt: DateTime.utc(2026, 10, 15),
    );

/// [text] written in [hand] on the page, [scale] px to an x-height, its
/// baseline at [baseline], one stroke per letter.
List<StrokeItem> inkInHand(
  MyHandwriting hand,
  String text, {
  double left = 100,
  double baseline = 200,
  double scale = 30,
  double gap = 0.3,
  Color color = const Color(0xFF2B5A8C),
  double width = 2.5,
}) {
  final line = layOutInHand(hand, text, gap: gap)!;
  return [
    for (final (i, pts) in line.strokes.indexed)
      StrokeItem.fromPagePoints(
        id: newId('it'),
        z: i,
        createdAt: DateTime.utc(2026, 10, 15),
        tool: InkTool.pen,
        penType: PenType.fountain,
        color: color,
        width: width,
        usePressure: true,
        pagePoints: [for (final p in pts) InkPoint(left + p.x * scale, baseline + p.y * scale, p.pressure, p.t)],
      ),
  ];
}
