import 'dart:math' as math;
import 'dart:typed_data';

// Telling speakers apart (Audio.png's "Professor" and "Student"), on the
// device. Two small models do the listening (lib/audio/speech_models.dart):
//
// - pyannote segmentation 3.0 hears who speaks when inside 10 s windows:
//   up to 3 voices per window, numbered only within it.
// - an ECAPA speaker model (SpeechBrain) turns a few seconds of one voice
//   into a voice print, 192 numbers; prints of the same voice point the
//   same way.
//
// The windows overlap. Each voice in each window gets a print from where it
// speaks alone; prints are grouped (agglomerative, by cosine distance) into
// the speakers of the whole recording; and every word is given the speaker
// heard most at its time. Speakers are numbered in the order they first
// speak: s1, s2, …

/// The models, behind an interface so tests can stand in for them.
abstract interface class SpeakerModels {
  /// Segmentation of one 10 s window ([windowSamples] samples at 16 kHz):
  /// [frames] × 7 scores (powerset classes), row by row.
  Future<Float32List> segment(Float32List window);

  /// A voice print of [samples] (16 kHz mono).
  Future<Float32List> voicePrint(Float32List samples);
}

const sampleRate = 16000;
const windowSamples = 10 * sampleRate;

/// Samples per segmentation frame (589 frames per window).
const frameSamples = 270;
const frames = 589;

/// The window moves on this far each time.
const windowStep = 4 * sampleRate;

/// Each of the 7 classes the segmentation picks per frame: who speaks.
const _powerset = [<int>[], [0], [1], [2], [0, 1], [0, 2], [1, 2]];

/// Prints further apart than this (1 − cosine) are different speakers.
const speakerDistance = 0.65;

/// A voice needs this much speech alone in a window to get a print.
const _minAlone = sampleRate;

/// One voice heard in one window.
class _Voice {
  _Voice(this.start, this.active, this.print);

  /// The window's first sample.
  final int start;

  /// Frames it speaks in.
  final List<bool> active;
  final Float32List? print;
}

/// Who speaks when: for each speaker (s1, s2, …), sample ranges.
class SpeakerTimeline {
  SpeakerTimeline(this.turns);

  /// Speaker → [start, end) sample ranges, sorted.
  final Map<String, List<(int, int)>> turns;

  int get count => turns.length;

  /// The speaker heard most between [t0Ms] and [t1Ms], or null if no one.
  String? at(int t0Ms, int t1Ms) {
    final a = t0Ms * sampleRate ~/ 1000, b = math.max(a + 1, t1Ms * sampleRate ~/ 1000);
    String? best;
    var most = 0;
    for (final e in turns.entries) {
      var heard = 0;
      for (final (s, t) in e.value) {
        if (t <= a) continue;
        if (s >= b) break;
        heard += math.min(b, t) - math.max(a, s);
      }
      if (heard > most) {
        most = heard;
        best = e.key;
      }
    }
    return best;
  }
}

/// Finds who speaks when in [length] samples of 16 kHz mono audio, which
/// [read] gives a window at a time. [progress] gets 0–1. [cancelled] is
/// checked between windows.
Future<SpeakerTimeline> findSpeakers(
  int length,
  Future<Float32List> Function(int from, int count) read,
  SpeakerModels models, {
  void Function(double)? progress,
  bool Function()? cancelled,
}) async {
  final voices = <_Voice>[];
  final starts = <int>[for (var s = 0; s == 0 || s + windowSamples - windowStep < length; s += windowStep) s];
  for (final (n, start) in starts.indexed) {
    if (cancelled?.call() ?? false) break;
    final window = Float32List(windowSamples);
    final got = await read(start, math.min(windowSamples, length - start));
    window.setRange(0, math.min(windowSamples, got.length), got);
    final scores = await models.segment(window);
    final active = List.generate(3, (_) => List.filled(frames, false));
    for (var f = 0; f < frames; f++) {
      var best = 0;
      for (var c = 1; c < 7; c++) {
        if (scores[f * 7 + c] > scores[f * 7 + best]) best = c;
      }
      for (final k in _powerset[best]) {
        active[k][f] = true;
      }
    }
    for (var k = 0; k < 3; k++) {
      if (active[k].where((a) => a).length < 20) continue;
      // Where it speaks alone.
      final alone = <int>[
        for (var f = 0; f < frames; f++)
          if (active[k][f] && !active[(k + 1) % 3][f] && !active[(k + 2) % 3][f]) f,
      ];
      Float32List? print;
      if (alone.length * frameSamples >= _minAlone) {
        final samples = Float32List(alone.length * frameSamples);
        for (final (i, f) in alone.indexed) {
          samples.setRange(i * frameSamples, (i + 1) * frameSamples, window, f * frameSamples);
        }
        print = _unit(await models.voicePrint(samples));
      }
      voices.add(_Voice(start, active[k], print));
    }
    progress?.call((n + 1) / starts.length);
  }
  return _timeline(voices, length);
}

Float32List _unit(Float32List v) {
  var n = 0.0;
  for (final x in v) {
    n += x * x;
  }
  n = math.sqrt(n);
  if (n == 0) return v;
  return Float32List.fromList([for (final x in v) x / n]);
}

double _dot(Float32List a, Float32List b) {
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += a[i] * b[i];
  }
  return s;
}

/// Groups voice prints whose average directions are closer than
/// [speakerDistance] (average linkage on the group centres). Returns the
/// group of each print.
List<int> groupPrints(List<Float32List> prints, {double distance = speakerDistance}) {
  final groups = [
    for (var i = 0; i < prints.length; i++) [i],
  ];
  final sums = [for (final p in prints) Float32List.fromList(p)];
  double closeness(int a, int b) => _dot(_unit(sums[a]), _unit(sums[b]));
  while (groups.length > 1) {
    var best = -2.0;
    var bi = 0, bj = 0;
    for (var i = 0; i < groups.length; i++) {
      for (var j = i + 1; j < groups.length; j++) {
        final c = closeness(i, j);
        if (c > best) {
          best = c;
          bi = i;
          bj = j;
        }
      }
    }
    if (1 - best > distance) break;
    groups[bi].addAll(groups.removeAt(bj));
    final s = sums.removeAt(bj);
    for (var k = 0; k < s.length; k++) {
      sums[bi][k] += s[k];
    }
  }
  final of = List.filled(prints.length, 0);
  for (final (g, members) in groups.indexed) {
    for (final m in members) {
      of[m] = g;
    }
  }
  return of;
}

SpeakerTimeline _timeline(List<_Voice> voices, int length) {
  final printed = [for (final v in voices) if (v.print != null) v];
  if (printed.isEmpty) {
    // No one spoke long enough alone to tell: one speaker, wherever anyone
    // was heard.
    return SpeakerTimeline(voices.isEmpty ? {} : {'s1': _ranges(voices, length)});
  }
  var group = groupPrints([for (final v in printed) v.print!]);
  // A speaker heard in only one window, for under 3 s, is more likely a
  // cough or a door than a person: it joins the closest one.
  group = _dropStrays(printed, group);

  // Votes per 0.1 s block: each window's voice votes for its speaker
  // wherever it is active.
  const block = sampleRate ~/ 10;
  final blocks = (length + block - 1) ~/ block;
  final count = group.isEmpty ? 0 : group.reduce(math.max) + 1;
  final votes = List.generate(count, (_) => Int32List(blocks));
  for (final (i, v) in printed.indexed) {
    for (var f = 0; f < frames; f++) {
      if (!v.active[f]) continue;
      final b = (v.start + f * frameSamples + frameSamples ~/ 2) ~/ block;
      if (b < blocks) votes[group[i]][b]++;
    }
  }
  // Turns: blocks where a speaker has a vote, as ranges.
  final turns = <int, List<(int, int)>>{};
  final first = <int, int>{};
  for (var g = 0; g < count; g++) {
    int? from;
    for (var b = 0; b <= blocks; b++) {
      final on = b < blocks && votes[g][b] > 0;
      if (on && from == null) from = b;
      if (!on && from != null) {
        (turns[g] ??= []).add((from * block, math.min(length, b * block)));
        first[g] ??= from;
        from = null;
      }
    }
  }
  final order = turns.keys.toList()..sort((a, b) => first[a]!.compareTo(first[b]!));
  return SpeakerTimeline({for (final (i, g) in order.indexed) 's${i + 1}': turns[g]!});
}

List<(int, int)> _ranges(List<_Voice> voices, int length) {
  final on = <(int, int)>[];
  for (final v in voices) {
    for (var f = 0; f < frames; f++) {
      if (v.active[f]) on.add((v.start + f * frameSamples, math.min(length, v.start + (f + 1) * frameSamples)));
    }
  }
  on.sort((a, b) => a.$1.compareTo(b.$1));
  final merged = <(int, int)>[];
  for (final r in on) {
    if (merged.isNotEmpty && r.$1 <= merged.last.$2) {
      merged.last = (merged.last.$1, math.max(merged.last.$2, r.$2));
    } else {
      merged.add(r);
    }
  }
  return merged;
}

List<int> _dropStrays(List<_Voice> printed, List<int> group) {
  final count = group.isEmpty ? 0 : group.reduce(math.max) + 1;
  if (count < 2) return group;
  final windows = List.generate(count, (_) => <int>{});
  final speech = List.filled(count, 0);
  for (final (i, v) in printed.indexed) {
    windows[group[i]].add(v.start);
    speech[group[i]] += v.active.where((a) => a).length * frameSamples;
  }
  final stray = {
    for (var g = 0; g < count; g++)
      if (windows[g].length == 1 && speech[g] < 3 * sampleRate) g,
  };
  if (stray.isEmpty || stray.length == count) return group;
  // Centres of the speakers that stay.
  final centres = <int, Float32List>{};
  for (final (i, v) in printed.indexed) {
    final g = group[i];
    if (stray.contains(g)) continue;
    final c = centres[g] ??= Float32List(v.print!.length);
    for (var k = 0; k < c.length; k++) {
      c[k] += v.print![k];
    }
  }
  final out = [...group];
  for (final (i, v) in printed.indexed) {
    if (!stray.contains(group[i])) continue;
    var best = -2.0;
    for (final e in centres.entries) {
      final c = _dot(_unit(e.value), v.print!);
      if (c > best) {
        best = c;
        out[i] = e.key;
      }
    }
  }
  // Number the groups 0, 1, … again.
  final renumber = <int, int>{};
  return [for (final g in out) renumber[g] ??= renumber.length];
}
