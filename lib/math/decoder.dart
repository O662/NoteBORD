import 'dart:math' as math;
import 'dart:typed_data';

import 'ink_image.dart';

// Reading handwritten math: CoMER's beam search, run both ways and each
// answer scored again by the other direction (as in the paper), over any
// [MathModel]. Ported from tool/math_model/step.py, which reaches CoMER's
// published accuracy on CROHME 2014.

/// The model's symbols, by token id (CoMER's CROHME dictionary). 0, 1 and 2
/// are padding, start and end.
const mathVocab = <String>[
  '<pad>', '<sos>', '<eos>', //
  '!', '(', ')', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '<', '=', '>',
  'A', 'B', 'C', 'E', 'F', 'G', 'H', 'I', 'L', 'M', 'N', 'P', 'R', 'S', 'T', 'V', 'X', 'Y', '[',
  r'\Delta', r'\Pi', r'\alpha', r'\beta', r'\cdot', r'\cdots', r'\cos', r'\div', r'\exists', r'\forall',
  r'\frac', r'\gamma', r'\geq', r'\in', r'\infty', r'\int', r'\lambda', r'\ldots', r'\leq', r'\lim',
  r'\limits', r'\log', r'\mu', r'\neq', r'\phi', r'\pi', r'\pm', r'\prime', r'\rightarrow', r'\sigma',
  r'\sin', r'\sqrt', r'\sum', r'\tan', r'\theta', r'\times', r'\{', r'\}', ']', '^', '_', //
  'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't',
  'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}',
];

const _sos = 1, _eos = 2;

/// A math recognition model, step by step. Implementations keep their
/// tensors to themselves (on the device's ONNX Runtime): the beam search
/// only sees scores.
abstract interface class MathModel {
  /// Reads the picture once, for any number of decodes.
  Future<MathMemory> encode(InkImage image);
}

/// What the model saw, ready to decode.
abstract interface class MathMemory {
  /// One hypothesis, before its first token.
  Future<MathCache> start();

  /// One decoding step: hypothesis i continues row [from][i] of [cache]
  /// with [tokens][i] at [position]. Returns each hypothesis's log
  /// probabilities for the next token (`tokens.length` rows of
  /// [mathVocab].length) and the new cache, one row per hypothesis.
  Future<(Float32List, MathCache)> step(MathCache cache, List<int> from, List<int> tokens, int position);

  Future<void> dispose();
}

/// The decoder's memory of earlier steps.
abstract interface class MathCache {
  Future<void> dispose();
}

/// One reading of handwritten math.
class MathHypothesis {
  const MathHypothesis(this.tokens, this.score);

  /// Token ids, without the start and end tokens.
  final List<int> tokens;
  final double score;

  List<String> get symbols => [for (final t in tokens) mathVocab[t]];

  @override
  String toString() => '${symbols.join(' ')} ($score)';
}

/// Reads [image]: the best reading first, then the others (up to
/// 2 × [beamSize]), best to worst.
Future<List<MathHypothesis>> readMath(MathModel model, InkImage image, {int beamSize = 10, int maxLength = 200}) async {
  final memory = await model.encode(image);
  try {
    // Both directions at once: one step of the model serves both.
    final [l2r, backwards] = await beamSearch(memory, const [(_sos, _eos), (_eos, _sos)], beamSize: beamSize, maxLength: maxLength);
    final r2l = [for (final h in backwards) MathHypothesis(h.tokens.reversed.toList(), h.score)];
    // Each answer is also scored by the other direction.
    final back = await rate(memory, [
      for (final h in l2r) (h.tokens.reversed.toList(), _eos, _sos),
      for (final h in r2l) (h.tokens, _sos, _eos),
    ]);
    final all = [
      for (final (i, h) in l2r.indexed) MathHypothesis(h.tokens, h.score + back[i]),
      for (final (i, h) in r2l.indexed) MathHypothesis(h.tokens, h.score + back[l2r.length + i]),
    ]..sort((a, b) => b.score.compareTo(a.score));
    // The same reading from both directions counts once.
    final seen = <String>{};
    return [for (final h in all) if (seen.add(h.tokens.join(','))) h];
  } finally {
    await memory.dispose();
  }
}

/// One beam search's state.
class _Beam {
  _Beam(this.start, this.stop);

  final int start, stop;
  var seqs = <List<int>>[[]];
  var scores = <double>[0];
  late var tokens = <int>[start];
  var from = <int>[0];
  final done = <MathHypothesis>[];
  var finished = false;
}

/// Beam searches, one for each (start, stop) in [searches], run side by
/// side so each step of the model serves them all. Scores are the summed
/// log probabilities (the stop token's included) over (length + 1)^[alpha].
Future<List<List<MathHypothesis>>> beamSearch(
  MathMemory memory,
  List<(int, int)> searches, {
  int beamSize = 10,
  int maxLength = 200,
  double alpha = 1,
}) async {
  final beams = [for (final (start, stop) in searches) _Beam(start, stop)];
  var cache = await memory.start();
  try {
    for (var t = 0; t < maxLength && beams.any((b) => !b.finished); t++) {
      final live = [for (final b in beams) if (!b.finished) b];
      final (logp, next) = await memory.step(
        cache,
        [for (final b in live) ...b.from],
        [for (final b in live) ...b.tokens],
        t,
      );
      await cache.dispose();
      cache = next;
      final v = logp.length ~/ live.fold(0, (n, b) => n + b.tokens.length);
      var row = 0;
      for (final b in live) {
        final rows = b.tokens.length;
        final offset = row;
        row += rows;
        // The best 2 × beam continuations of this search's hypotheses.
        final order = _topK(logp, v, offset, b.scores, 2 * beamSize);
        final keepFrom = <int>[], keepToken = <int>[], keepScore = <double>[];
        for (final (rank, (h, token, score)) in order.indexed) {
          if (token == b.stop) {
            if (rank < beamSize) b.done.add(MathHypothesis(b.seqs[h], score / math.pow(b.seqs[h].length + 1, alpha)));
          } else {
            keepFrom.add(h);
            keepToken.add(token);
            keepScore.add(score);
          }
          if (keepFrom.length == beamSize) break;
        }
        b.done.sort((x, y) => y.score.compareTo(x.score));
        if (b.done.length > beamSize) b.done.removeRange(beamSize, b.done.length);
        // Enough are finished, and no live one can beat the worst of them.
        if (keepFrom.isEmpty ||
            (b.done.length >= beamSize && keepScore.reduce(math.max) / math.pow(t + 1, alpha) <= b.done.last.score)) {
          b.finished = true;
          continue;
        }
        b.seqs = [for (final (i, h) in keepFrom.indexed) [...b.seqs[h], keepToken[i]]];
        b.scores = keepScore;
        b.tokens = keepToken;
        // Rows of the cache just made.
        b.from = [for (final h in keepFrom) offset + h];
      }
    }
  } finally {
    await cache.dispose();
  }
  for (final b in beams) {
    if (b.done.isEmpty) {
      for (final (i, s) in b.seqs.indexed) {
        b.done.add(MathHypothesis(s, b.scores[i] / math.pow(s.length + 1, alpha)));
      }
    }
    b.done.sort((x, y) => y.score.compareTo(x.score));
  }
  return [for (final b in beams) b.done];
}

/// Scores each (tokens, start, stop) of [seqs] as [beamSearch] would, all
/// in the same steps.
Future<List<double>> rate(MathMemory memory, List<(List<int>, int, int)> seqs, {double alpha = 1}) async {
  if (seqs.isEmpty) return const [];
  final n = seqs.length;
  final length = seqs.map((s) => s.$1.length).reduce(math.max) + 1;
  var cache = await memory.start();
  final total = List<double>.filled(n, 0);
  var tokens = [for (final s in seqs) s.$2];
  var from = List<int>.filled(n, 0); // every one starts from the one empty cache
  try {
    for (var t = 0; t < length; t++) {
      final (logp, next) = await memory.step(cache, from, tokens, t);
      await cache.dispose();
      cache = next;
      final v = logp.length ~/ n;
      from = List<int>.generate(n, (i) => i);
      tokens = [
        for (final (s, _, stop) in seqs)
          if (t < s.length) s[t] else if (t == s.length) stop else 0,
      ];
      for (final (b, (s, _, _)) in seqs.indexed) {
        if (t <= s.length) total[b] += logp[b * v + tokens[b]];
      }
    }
  } finally {
    await cache.dispose();
  }
  return [for (final (b, (s, _, _)) in seqs.indexed) total[b] / math.pow(s.length + 1, alpha)];
}

/// The [k] best (hypothesis, token, score) by score, best first; ties keep
/// the lower index, as a stable sort does.
List<(int, int, double)> _topK(Float32List logp, int v, int offset, List<double> scores, int k) {
  final best = <(int, int, double)>[];
  for (var b = 0; b < scores.length; b++) {
    for (var t = 0; t < v; t++) {
      final s = scores[b] + logp[(offset + b) * v + t];
      if (best.length == k && s <= best.last.$3) continue;
      var at = best.length;
      while (at > 0 && best[at - 1].$3 < s) {
        at--;
      }
      best.insert(at, (b, t, s));
      if (best.length > k) best.removeLast();
    }
  }
  return best;
}
