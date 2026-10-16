import 'dart:math' as math;
import 'dart:ui' show Rect;

import '../board/model.dart';

// Handwriting is recognized a line at a time (ML Kit reads a line best and
// returns whole-line answers, not words with boxes). This file splits a
// page's ink into lines, the words on each line, and paragraphs, by
// geometry alone, so the words of an answer can be matched to the strokes
// that wrote them.

/// Whether [s] is freehand writing: pen ink, not a highlighter, a shape a
/// hold or Straighten lines made, an arrow or a connector.
bool isHandwriting(StrokeItem s) => s.straightened == null && mayBeWriting(s);

/// Shapes a letter can be straightened into: a line (l, I, 1, a t's stem)
/// or a circle or oval (o, O, 0). Rectangles and triangles are drawings
/// (a checkbox, a diagram).
const letterShapes = {'line', 'circle', 'ellipse'};

/// Whether [s] may be part of the writing: freehand writing, or a letter
/// straightened into a line, circle or oval. [segmentLines] reads such a
/// shape as writing only when it's the size of a letter and sits on a line
/// of freehand writing; [writingIn] gives the strokes it reads.
bool mayBeWriting(StrokeItem s) =>
    s.tool == InkTool.pen &&
    s.arrow == null &&
    !s.isAttached &&
    s.points.isNotEmpty &&
    (s.straightened == null || letterShapes.contains(s.straightened));

/// The strokes of [strokes] that are read as writing (see [segmentLines]),
/// in the order given.
List<StrokeItem> writingIn(Iterable<StrokeItem> strokes) {
  final read = {for (final l in segmentLines(strokes)) ...l.strokes.map((s) => s.id)};
  return [for (final s in strokes) if (read.contains(s.id)) s];
}

/// The page-space box around a stroke's points (without its width).
Rect inkRect(StrokeItem s) {
  var maxX = 0.0, maxY = 0.0;
  for (final p in s.points) {
    if (p.x > maxX) maxX = p.x;
    if (p.y > maxY) maxY = p.y;
  }
  return Rect.fromLTRB(s.x, s.y, s.x + maxX, s.y + maxY);
}

/// One line of handwriting.
class InkLine {
  InkLine(this.strokes, this.words, this.bounds, this.height, {List<StrokeItem>? reading})
      : reading = reading ?? strokes;

  /// In the order they were written.
  final List<StrokeItem> strokes;

  /// The order the recognizer reads them in: as written, except that a
  /// letter or word written later in front of others (a letter erased and
  /// written again, a word squeezed in) goes where it is on the line. Dots,
  /// crosses and commas stay where they were written.
  final List<StrokeItem> reading;

  /// Groups of strokes split by the gaps between them, left to right.
  final List<List<StrokeItem>> words;

  /// Around the points of every stroke.
  final Rect bounds;

  /// The typical height of a stroke on this line.
  final double height;

  /// The paragraph it belongs to, counting from 0 in reading order.
  int block = 0;

  List<String> get strokeIds => [for (final s in strokes) s.id];
}

class _Mark {
  _Mark(this.stroke, this.order) : rect = inkRect(stroke);

  final StrokeItem stroke;

  /// Where it came in the input (pen order breaks ties in time).
  final int order;
  final Rect rect;

  double get cy => rect.center.dy;
  double get h => rect.height;
}

class _Line {
  _Line(_Mark m) {
    add(m);
  }

  final marks = <_Mark>[];
  late Rect rect;
  double cy = 0;
  double h = 0;

  void add(_Mark m) {
    marks.add(m);
    rect = marks.length == 1 ? m.rect : rect.expandToInclude(m.rect);
    // Big strokes say where the line is; dots and commas don't.
    final big = marks.where((x) => x.h >= h * 0.4).toList();
    final use = big.isEmpty ? marks : big;
    cy = _median([for (final x in use) x.cy]);
    h = _median([for (final x in use) x.h]);
  }

  void absorb(_Line other) {
    for (final m in other.marks) {
      add(m);
    }
  }
}

/// Up to [k] of [marks] nearest [rect] sideways, within [reach].
List<_Mark> _nearest(Iterable<_Mark> marks, Rect rect, {double reach = double.infinity, int k = 4}) {
  final near = [
    for (final m in marks)
      if (_gapX(m.rect, rect) <= reach) m,
  ]..sort((a, b) {
      final g = _gapX(a.rect, rect).compareTo(_gapX(b.rect, rect));
      return g != 0 ? g : (a.rect.center.dx - rect.center.dx).abs().compareTo((b.rect.center.dx - rect.center.dx).abs());
    });
  return near.take(k).toList();
}

/// Where a line is around [near]: the middle and height of its writing
/// there. Lines that rise or fall are followed where they are, not by
/// their average.
(double, double) _band(List<_Mark> near) => (_median([for (final m in near) m.cy]), _median([for (final m in near) m.h]));

int _byTime(_Mark a, _Mark b) {
  final t = a.stroke.createdAt.compareTo(b.stroke.createdAt);
  return t != 0 ? t : a.order.compareTo(b.order);
}

/// Groups [marks] into lines.
///
/// 1. Strokes of a fair size, in the order they were written, each join
///    the line they're level with *where they are* (the few strokes of the
///    line nearest them sideways), so writing that rises or falls stays one
///    line. Following straight on from the stroke before, more leeway
///    (tails and tall letters as they're written).
/// 2. Pieces of a line side by side at the same height are joined: a word
///    written far along, or a letter written again later.
/// 3. Dots, crosses and commas join the line they sit on.
List<_Line> _groupLines(List<_Mark> marks, double typical) {
  bool small(_Mark m) => m.h < typical * 0.4;
  final byTime = [...marks]..sort(_byTime);
  final lines = <_Line>[];
  final lineOf = <_Mark, _Line>{};
  _Mark? before;
  for (final m in byTime.where((m) => !small(m))) {
    _Line? best;
    var bestScore = double.infinity;
    for (final line in lines) {
      if (_gapY(line.rect, m.rect) > 3 * typical) continue;
      final near = _nearest(line.marks.where((x) => !small(x)), m.rect, reach: 3 * typical);
      if (near.isEmpty) continue;
      final (cy, bh) = _band(near);
      var tol = 0.6 * math.max(bh, math.min(m.h, 1.6 * bh));
      if (before != null && lineOf[before] == line && _gapX(before.rect, m.rect) <= 1.5 * typical) tol *= 1.8;
      final dy = (m.cy - cy).abs();
      if (dy > tol) continue;
      if (dy / tol < bestScore) {
        bestScore = dy / tol;
        best = line;
      }
    }
    if (best == null) {
      lines.add(best = _Line(m));
    } else {
      best.add(m);
    }
    lineOf[m] = best;
    before = m;
  }

  // Pieces of one line, side by side or overlapping, at the same height
  // where they meet: the nearest pair first. (Lines above and below each
  // other overlap too, but aren't at the same height.)
  while (true) {
    (_Line, _Line)? pick;
    var pickGap = double.infinity;
    for (final (i, a) in lines.indexed) {
      for (final b in lines.skip(i + 1)) {
        final gap = _gapX(a.rect, b.rect);
        if (gap > 4 * typical || gap >= pickGap || _gapY(a.rect, b.rect) > math.max(a.h, b.h)) continue;
        final (ca, ha) = _band(_nearest(a.marks, b.rect, k: 3));
        final (cb, hb) = _band(_nearest(b.marks, a.rect, k: 3));
        if ((ca - cb).abs() > 0.9 * math.max(ha, hb)) continue;
        pick = (a, b);
        pickGap = gap;
      }
    }
    if (pick == null) break;
    pick.$1.absorb(pick.$2);
    lines.remove(pick.$2);
  }

  // Dots, crosses and commas: measured against the letters near them
  // (an i's dot sits about a letter's height above their middle).
  for (final m in byTime.where(small)) {
    _Line? best;
    var bestScore = double.infinity;
    for (final line in lines) {
      final letters = line.marks.where((x) => !small(x));
      final near = _nearest(letters.isEmpty ? line.marks : letters, m.rect, reach: 2 * typical, k: 3);
      if (near.isEmpty) continue;
      final (cy, bh) = _band(near);
      final tol = math.max(1.3 * bh, 0.8 * typical);
      final dy = (m.cy - cy).abs();
      if (dy <= tol && dy / tol < bestScore) {
        bestScore = dy / tol;
        best = line;
      }
    }
    if (best == null) {
      lines.add(_Line(m));
    } else {
      best.add(m);
    }
  }
  return lines;
}

/// Splits a line's marks (left to right) into words at the gaps between
/// them. How wide a gap between words is depends on the writer: the gaps
/// on the line fall into letter gaps and word gaps, split between the two
/// (Otsu's method), at least 0.45 and at most 1 line height.
List<List<StrokeItem>> _words(List<_Mark> byX, double h) {
  final groups = <List<_Mark>>[];
  final gaps = <double>[];
  var right = double.negativeInfinity;
  for (final m in byX) {
    if (groups.isEmpty || m.rect.left > right) {
      if (groups.isNotEmpty) gaps.add(m.rect.left - right);
      groups.add([m]);
      right = m.rect.right;
    } else {
      groups.last.add(m);
      right = math.max(right, m.rect.right);
    }
  }
  var t = 0.45 * h;
  final sorted = [...gaps]..sort();
  if (sorted.length >= 3 && sorted.last >= 2 * math.max(sorted.first, 1)) {
    t = _otsu(sorted).clamp(0.45 * h, h);
  }
  final words = <List<StrokeItem>>[];
  for (final (i, g) in groups.indexed) {
    if (i == 0 || gaps[i - 1] > t) {
      words.add([]);
    }
    words.last.addAll(g.map((m) => m.stroke));
  }
  return words;
}

/// Where sorted [v] splits best into two groups.
double _otsu(List<double> v) {
  var best = -1.0, at = v.first;
  for (var i = 1; i < v.length; i++) {
    final a = v.sublist(0, i), b = v.sublist(i);
    final ma = a.reduce((x, y) => x + y) / a.length, mb = b.reduce((x, y) => x + y) / b.length;
    final score = a.length * b.length * (mb - ma) * (mb - ma);
    if (score > best) {
      best = score;
      at = (v[i - 1] + v[i]) / 2;
    }
  }
  return at;
}

/// [inTime] in the order to read: each stroke of a fair size goes after
/// the last one before it that's not clearly to its right on the line.
List<StrokeItem> _readingOrder(List<_Mark> inTime, double h, double typical) {
  final out = <_Mark>[];
  for (final m in inTime) {
    var at = out.length;
    if (m.h >= typical * 0.4) {
      final x = m.rect.center.dx + 0.5 * h;
      while (at > 0 && out[at - 1].rect.center.dx > x) {
        at--;
      }
    }
    out.insert(at, m);
  }
  return [for (final m in out) m.stroke];
}

double _median(List<double> v) {
  if (v.isEmpty) return 0;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

double _gapY(Rect a, Rect b) => math.max(0, math.max(a.top, b.top) - math.min(a.bottom, b.bottom));

double _gapX(Rect a, Rect b) => math.max(0, math.max(a.left, b.left) - math.min(a.right, b.right));

/// Splits [strokes] (in pen order) into lines of handwriting, in reading
/// order, each split into words and numbered by paragraph. Strokes that
/// aren't writing ([mayBeWriting]) are left out, and so are straightened
/// shapes bigger than a letter or not on a line of freehand writing.
List<InkLine> segmentLines(Iterable<StrokeItem> strokes) {
  final candidates = [
    for (final (i, s) in strokes.where(mayBeWriting).indexed) _Mark(s, i),
  ];
  final hand = [for (final m in candidates) if (m.stroke.straightened == null) m];
  if (hand.isEmpty) return const [];
  // How tall writing is on this page, so the rules scale with it: the
  // letters', not the dots' and crosses'.
  final all = _median([for (final m in hand) m.h]);
  final typical = math.max(6.0, _median([for (final m in hand) if (m.h >= all * 0.5) m.h]));
  // A straightened letter is about a letter's size; a long underline or a
  // circle around a word isn't one.
  final marks = [
    for (final m in candidates)
      if (m.stroke.straightened == null || math.max(m.rect.width, m.h) <= 2 * typical) m,
  ];

  final out = <InkLine>[];
  for (final line in _groupLines(marks, typical)) {
    // Straightened shapes on their own are drawings.
    if (line.marks.every((m) => m.stroke.straightened != null)) continue;
    final byX = [...line.marks]..sort((a, b) => a.rect.left.compareTo(b.rect.left));
    final h = math.max(line.h, typical * 0.6);
    final inOrder = [...line.marks]..sort(_byTime);
    out.add(InkLine(
      [for (final m in inOrder) m.stroke],
      _words(byX, h),
      line.rect,
      h,
      reading: _readingOrder(inOrder, h, typical),
    ));
  }

  // Paragraphs: lines close under each other and overlapping sideways.
  out.sort((a, b) => a.bounds.top.compareTo(b.bounds.top));
  final blocks = <List<InkLine>>[];
  for (final line in out) {
    List<InkLine>? joined;
    for (final b in blocks.reversed) {
      final last = b.last;
      final gap = line.bounds.top - last.bounds.bottom;
      final h = math.max(last.height, line.height);
      final side = _gapX(line.bounds, Rect.fromLTRB(b.first.bounds.left, 0, last.bounds.right, 1)) <= h &&
          (line.bounds.left - b.first.bounds.left).abs() < math.max(4 * h, b.first.bounds.width * 0.6);
      if (gap < 0.9 * h && side) {
        joined = b;
        break;
      }
      if (gap > 3 * h) break;
    }
    if (joined == null) {
      blocks.add([line]);
    } else {
      joined.add(line);
    }
  }
  blocks.sort((a, b) {
    final dy = a.first.bounds.top - b.first.bounds.top;
    // Side by side (columns): left first.
    if (dy.abs() < a.first.height) return a.first.bounds.left.compareTo(b.first.bounds.left);
    return dy.sign.toInt();
  });
  return [
    for (final (i, b) in blocks.indexed)
      for (final line in b) line..block = i,
  ];
}

/// A stable name for a line's strokes and their shapes: the same ink in the
/// same place relative to itself gets the same key, wherever it has been
/// moved on the page. Used to reuse what a line was recognized as.
String lineKey(List<StrokeItem> strokes, String language) {
  if (strokes.isEmpty) return '';
  final o = inkRect(strokes.first).topLeft;
  final b = StringBuffer(language);
  for (final s in strokes) {
    final r = inkRect(s);
    final d = r.topLeft - o;
    b.write('|${s.id}:${s.points.length}:${(r.width / 2).round()}:${(r.height / 2).round()}'
        ':${(d.dx / 4).round()}:${(d.dy / 4).round()}');
  }
  return fnv64(b.toString());
}

/// FNV-1a, 64-bit, as hex: stable across runs and platforms (unlike
/// `String.hashCode`).
String fnv64(String s) {
  // Two 32-bit halves, since web numbers can't hold 64-bit products.
  var hi = 0xcbf29ce4, lo = 0x84222325;
  for (final unit in s.codeUnits) {
    lo ^= unit;
    // × 0x100000001b3 = × (2^40 + 0x1b3)
    final loMul = lo * 0x1b3;
    final hiMul = hi * 0x1b3 + (lo << 8) + (loMul ~/ 0x100000000);
    lo = loMul & 0xffffffff;
    hi = hiMul & 0xffffffff;
  }
  return hi.toRadixString(16).padLeft(8, '0') + lo.toRadixString(16).padLeft(8, '0');
}

/// The box around [strokes]' points, or null when there are none.
Rect? strokesRect(Iterable<StrokeItem> strokes) {
  Rect? r;
  for (final s in strokes) {
    final b = inkRect(s);
    r = r == null ? b : r.expandToInclude(b);
  }
  return r;
}

/// The point to sort a stroke by along its line.
double strokeMidX(StrokeItem s) => inkRect(s).center.dx;
