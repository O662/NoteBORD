import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/ids.dart';
import '../board/model.dart';
import '../board/store.dart';
import '../recognition/convert.dart' show mainInkColor;
import '../recognition/segment.dart' show strokesRect;
import '../state/settings.dart' show boardStoreProvider;

// "Fix it in my handwriting" (design/screens/Spell.png): the user writes
// each letter once, in a box on guide lines ("Teach Endless your
// handwriting"); a spelling fix is then written in those letters, sized,
// placed and spaced like the word it replaces.

/// The boxes of the sample, step by step. Lower case is needed; capitals
/// and punctuation are optional (capitals fall back to a larger lower-case
/// letter, punctuation to [builtInMarks]).
const sampleSteps = <({String letters, bool required, String title})>[
  (letters: 'abcdefghijklmnopqrstuvwxyz', required: true, title: 'Small letters'),
  (letters: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ.,\'-:;!?', required: false, title: 'Capitals and marks'),
];

/// The guide lines in a sample box, as fractions of its height: the top of
/// tall letters, the top of small ones, and the line letters sit on.
abstract final class SampleGuides {
  static const ascender = 0.18;
  static const xLine = 0.44;
  static const baseline = 0.70;

  /// A small letter's height, as a fraction of the box's.
  static const xHeight = baseline - xLine;
}

/// One letter of the sample, in x-height units: y = 0 on the baseline and
/// grows downwards (tall letters reach about −2, tails about +0.9); x
/// starts at its leftmost ink. `t` is milliseconds since its stroke began.
class HandGlyph {
  const HandGlyph(this.strokes, this.width);

  final List<List<InkPoint>> strokes;
  final double width;

  /// The letter grown by [k] about its baseline.
  HandGlyph scaled(double k) => HandGlyph(
        [
          for (final s in strokes) [for (final p in s) InkPoint(p.x * k, p.y * k, p.pressure, p.t)],
        ],
        width * k,
      );

  /// The letter written in a sample box ([cell], in the same coordinates
  /// as [strokes]), or null if there's no ink.
  static HandGlyph? fromBox(List<List<InkPoint>> strokes, Rect cell) {
    final ink = [for (final s in strokes) if (s.isNotEmpty) s];
    if (ink.isEmpty) return null;
    final xh = cell.height * SampleGuides.xHeight;
    final base = cell.top + cell.height * SampleGuides.baseline;
    final left = ink.expand((s) => s).map((p) => p.x).reduce(math.min);
    final right = ink.expand((s) => s).map((p) => p.x).reduce(math.max);
    return HandGlyph([
      for (final s in ink) [for (final p in s) InkPoint((p.x - left) / xh, (p.y - base) / xh, p.pressure, p.t)],
    ], (right - left) / xh);
  }

  Json toJson() => {
        'w': _r(width),
        's': [
          for (final s in strokes) [for (final p in s) ...[_r(p.x), _r(p.y), _r(p.pressure), p.t]],
        ],
      };

  static HandGlyph? fromJson(Object? j) {
    if (j is! Map || j['w'] is! num || j['s'] is! List) return null;
    final strokes = <List<InkPoint>>[];
    for (final s in j['s'] as List) {
      if (s is! List) return null;
      final v = s.whereType<num>().toList();
      if (v.length != s.length || v.length % 4 != 0) return null;
      strokes.add([
        for (var i = 0; i < v.length; i += 4) InkPoint(v[i].toDouble(), v[i + 1].toDouble(), v[i + 2].toDouble(), v[i + 3].toInt()),
      ]);
    }
    return HandGlyph(strokes, (j['w'] as num).toDouble());
  }

  static double _r(double v) => (v * 1000).roundToDouble() / 1000;
}

/// Punctuation in plain pen strokes, for marks left out of the sample.
final builtInMarks = <String, HandGlyph>{
  '.': _mark([_dot(0.06, -0.06)]),
  ',': _mark([
    [(0.10, -0.10), (0.11, -0.02), (0.08, 0.10), (0.02, 0.24)],
  ]),
  ':': _mark([_dot(0.06, -0.72), _dot(0.06, -0.06)]),
  ';': _mark([
    _dot(0.10, -0.72),
    [(0.10, -0.10), (0.11, -0.02), (0.08, 0.10), (0.02, 0.24)],
  ]),
  "'": _mark([
    [(0.08, -1.75), (0.06, -1.55), (0.02, -1.35)],
  ]),
  '-': _mark([
    [(0.0, -0.48), (0.25, -0.49), (0.5, -0.48)],
  ]),
  '!': _mark([
    [(0.08, -1.75), (0.07, -1.1), (0.06, -0.45)],
    _dot(0.06, -0.06),
  ]),
  '?': _mark([
    [(0.02, -1.45), (0.18, -1.72), (0.45, -1.72), (0.58, -1.45), (0.45, -1.12), (0.28, -0.95), (0.26, -0.5)],
    _dot(0.26, -0.06),
  ]),
};

List<(double, double)> _dot(double x, double y) => [(x - 0.03, y), (x, y - 0.03), (x + 0.03, y), (x, y + 0.03), (x - 0.03, y)];

HandGlyph _mark(List<List<(double, double)>> strokes) {
  final pts = [
    for (final s in strokes) [for (final (i, (x, y)) in s.indexed) InkPoint(x, y, 0.5, i * 12)],
  ];
  final xs = pts.expand((s) => s).map((p) => p.x);
  final left = xs.reduce(math.min);
  return HandGlyph([
    for (final s in pts) [for (final p in s) InkPoint(p.x - left, p.y, p.pressure, p.t)],
  ], xs.reduce(math.max) - left);
}

/// How much bigger a capital is than its small letter, when only the small
/// one was written.
const capitalFromSmall = 1.45;

/// The user's handwriting sample.
class MyHandwriting {
  const MyHandwriting({required this.glyphs, required this.createdAt});

  /// By the letter or mark written.
  final Map<String, HandGlyph> glyphs;
  final DateTime createdAt;

  /// The letter or mark [ch] in this hand: as written in the sample, else a
  /// capital from its small letter, a curly quote from a straight one, or a
  /// built-in mark. Null if there's none.
  HandGlyph? glyphFor(String ch) {
    if (glyphs[ch] case final own?) return own;
    switch (ch) {
      case '’' || '‘':
        return glyphFor("'");
      case '"' || '“' || '”':
        final q = glyphFor("'");
        if (q == null) return null;
        final gap = q.width + 0.15;
        return HandGlyph([...q.strokes, for (final s in q.strokes) [for (final p in s) InkPoint(p.x + gap, p.y, p.pressure, p.t)]],
            gap + q.width);
      case '—' || '–':
        return glyphFor('-');
    }
    final lower = ch.toLowerCase();
    if (lower != ch && glyphs[lower] != null) return glyphs[lower]!.scaled(capitalFromSmall);
    return builtInMarks[ch];
  }

  /// Whether every letter of [text] can be written in this hand.
  bool canWrite(String text) => text.characters.every((c) => c == ' ' || glyphFor(c) != null);

  Json toJson() => {
        'version': 1,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'glyphs': {for (final e in glyphs.entries) e.key: e.value.toJson()},
      };

  static MyHandwriting? fromJson(Json? j) {
    final raw = j?['glyphs'];
    if (j == null || raw is! Map) return null;
    final glyphs = <String, HandGlyph>{
      for (final e in raw.entries)
        if (e.key is String) e.key as String: ?HandGlyph.fromJson(e.value),
    };
    if (glyphs.isEmpty) return null;
    return MyHandwriting(
      glyphs: glyphs,
      createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '')?.toUtc() ?? DateTime.utc(2026),
    );
  }
}

/// Text laid out in a hand, in x-height units (see [HandGlyph]).
class HandLine {
  const HandLine(this.strokes, this.width, this.top, this.bottom);

  final List<List<InkPoint>> strokes;

  /// From the first letter's left edge to the last one's right edge.
  final double width;

  /// The highest and lowest ink.
  final double top, bottom;
}

/// The space between letters when nothing says otherwise, in x-heights.
const defaultLetterGap = 0.18;

bool _isMark(String ch) => '.,:;!?\'’‘"“”'.contains(ch);

/// [text] in [hand], [gap] apart (marks sit closer). With [seed], each
/// letter is a touch bigger or smaller, higher or lower, so repeated
/// letters aren't stamped copies. Null if a letter can't be written.
HandLine? layOutInHand(MyHandwriting hand, String text, {double gap = defaultLetterGap, int? seed}) {
  final rnd = seed == null ? null : math.Random(seed);
  final strokes = <List<InkPoint>>[];
  var x = 0.0, right = 0.0;
  var top = double.infinity, bottom = double.negativeInfinity;
  final chars = text.characters.toList();
  for (final (i, ch) in chars.indexed) {
    if (ch == ' ') {
      x += 0.8;
      continue;
    }
    final g = hand.glyphFor(ch);
    if (g == null) return null;
    if (i > 0 && (_isMark(ch) || _isMark(chars[i - 1]))) x -= gap * 0.6;
    final k = rnd == null ? 1.0 : 1 + (rnd.nextDouble() - 0.5) * 0.06;
    final dy = rnd == null ? 0.0 : (rnd.nextDouble() - 0.5) * 0.05;
    for (final s in g.strokes) {
      final placed = [for (final p in s) InkPoint(x + p.x * k, p.y * k + dy, p.pressure, p.t)];
      for (final p in placed) {
        top = math.min(top, p.y);
        bottom = math.max(bottom, p.y);
      }
      strokes.add(placed);
    }
    right = x + g.width * k;
    x = right + gap;
  }
  if (strokes.isEmpty) return null;
  return HandLine(strokes, right, top, bottom);
}

/// A word written in the user's hand, ready to replace one on the page.
class HandWritten {
  const HandWritten(this.strokes, this.widthChange);

  final List<StrokeItem> strokes;

  /// How much wider (or, below 0, narrower) it is than the word it
  /// replaces: the rest of the line moves by this much.
  final double widthChange;
}

/// [text] in [hand], in place of the ink [original], which reads [wrote].
///
/// [wrote] laid out in the sample's letters says how the original was
/// written: its size (fitting its height to the ink's), where its baseline
/// is, and how far apart its letters are. [text] is then written the same
/// way, from the same left edge, with the original's pen, color and
/// thickness. Null if [text] has a letter the sample can't write.
HandWritten? writeInHand(
  MyHandwriting hand, {
  required String text,
  required String wrote,
  required List<StrokeItem> original,
  required int z,
  required DateTime now,
}) {
  if (original.isEmpty || !hand.canWrite(text)) return null;
  final box = strokesRect(original)!;
  final known = [for (final c in wrote.characters) if (c != ' ' && hand.glyphFor(c) != null) c].join();
  final model = layOutInHand(hand, known.isEmpty ? text : known, gap: 0)!;
  final n = (known.isEmpty ? text : known).characters.length;

  // Size: the sample's letters fitted to the height of the ink; the width
  // has a say when the two disagree a lot (letters misread).
  final byHeight = box.height / math.max(model.bottom - model.top, 0.2);
  final byWidth = box.width / math.max(model.width + (n - 1) * defaultLetterGap, 0.2);
  final s = byHeight > 2 * byWidth || byHeight < byWidth / 2 ? math.sqrt(byHeight * byWidth) : byHeight;
  // Spacing: as tight or loose as the original.
  final gap = n > 1 ? ((box.width / s - model.width) / (n - 1)).clamp(0.0, 0.8) : defaultLetterGap;
  final baseline = box.top - s * model.top;

  final seed = text.codeUnits.fold<int>(17, (h, c) => (h * 31 + c) & 0x7fffffff);
  final line = layOutInHand(hand, text, gap: gap, seed: seed)!;
  final main = original.reduce((a, b) => b.points.length > a.points.length ? b : a);
  final widths = [for (final o in original) o.width]..sort();
  final color = mainInkColor(original);
  final strokes = [
    for (final (i, pts) in line.strokes.indexed)
      StrokeItem.fromPagePoints(
        id: newId('it', now: now),
        z: z + i,
        createdAt: now,
        tool: InkTool.pen,
        penType: main.penType,
        color: color,
        width: widths[widths.length ~/ 2],
        usePressure: main.usePressure,
        pagePoints: [for (final p in pts) InkPoint(box.left + p.x * s, baseline + p.y * s, p.pressure, p.t)],
      ),
  ];
  return HandWritten(strokes, line.width * s - box.width);
}

final initialHandwritingProvider = Provider<MyHandwriting?>((ref) => null);

/// The user's handwriting sample, or null before they've written one.
final myHandwritingProvider = NotifierProvider<MyHandwritingNotifier, MyHandwriting?>(MyHandwritingNotifier.new);

class MyHandwritingNotifier extends Notifier<MyHandwriting?> {
  late BoardStore _store;

  @override
  MyHandwriting? build() {
    _store = ref.read(boardStoreProvider);
    return ref.read(initialHandwritingProvider);
  }

  Future<void> save(MyHandwriting hand) {
    state = hand;
    return _store.saveHandwriting(hand.toJson());
  }

  /// Deletes the sample from this device.
  Future<void> forget() {
    state = null;
    return _store.saveHandwriting(null);
  }
}
