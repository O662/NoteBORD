import 'dart:math' as math;
import 'dart:typed_data';

import 'package:endless/audio/speakers.dart';
import 'package:endless/audio/transcript_lines.dart';
import 'package:endless/board/model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Audio where who speaks is written into the samples: speaker k (1–4) is
/// a steady 0.1·k, silence is 0.
Float32List _audio(List<(double, double, int)> turns, double seconds) {
  final a = Float32List((seconds * sampleRate).round());
  for (final (from, to, k) in turns) {
    for (var i = (from * sampleRate).round(); i < (to * sampleRate).round() && i < a.length; i++) {
      a[i] = 0.1 * k;
    }
  }
  return a;
}

int _who(double v) => (v * 10).round();

/// Stand-in models: segmentation hears each frame's speaker (numbered
/// within the window, as the real one does), and a voice print points one
/// way per speaker, with a little noise.
class _FakeModels implements SpeakerModels {
  final _random = math.Random(4);
  int prints = 0;

  @override
  Future<Float32List> segment(Float32List window) async {
    final scores = Float32List(frames * 7);
    for (var f = 0; f < frames; f++) {
      final k = _who(window[math.min(window.length - 1, f * frameSamples + frameSamples ~/ 2)]);
      // Within a window speakers are 0, 1, 2 in any order: here k-1 mod 3.
      final c = k == 0 ? 0 : 1 + (k - 1) % 3;
      scores[f * 7 + c] = 5;
    }
    return scores;
  }

  @override
  Future<Float32List> voicePrint(Float32List samples) async {
    prints++;
    var sum = 0.0;
    for (final s in samples) {
      sum += s;
    }
    final k = _who(sum / samples.length);
    return Float32List.fromList([
      for (var i = 0; i < 192; i++) (i == k ? 1.0 : 0.0) + (_random.nextDouble() - 0.5) * 0.1,
    ]);
  }
}

Future<SpeakerTimeline> _find(Float32List audio, SpeakerModels models) =>
    findSpeakers(audio.length, (from, count) async => Float32List.sublistView(audio, from, math.min(audio.length, from + count)), models);

void main() {
  test('voice prints pointing the same way are one speaker', () {
    Float32List v(List<double> xs) => Float32List.fromList(xs);
    final groups = groupPrints([
      v([1, 0, 0]),
      v([0.95, 0.1, 0]),
      v([0, 1, 0]),
      v([0.05, 0.9, 0.1]),
      v([0.9, 0, 0.2]),
    ]);
    expect(groups[0], groups[1]);
    expect(groups[0], groups[4]);
    expect(groups[2], groups[3]);
    expect(groups[0], isNot(groups[2]));
    // Far enough apart to stay two, close enough at a looser distance.
    // cos 0.2 (distance 0.8): two; within a looser distance, one.
    expect(groupPrints([v([1, 0]), v([0.2, 0.98])]).toSet(), {0, 1});
    expect(groupPrints([v([1, 0]), v([0.2, 0.98])], distance: 0.85).toSet(), {0});
  });

  test('a lecture with a question: the professor, a student, the professor again', () async {
    final audio = _audio([(0.5, 14, 1), (15, 21, 2), (22, 40, 1), (41, 47, 2), (48, 58, 1)], 60);
    final models = _FakeModels();
    final speakers = await _find(audio, models);
    expect(speakers.count, 2);
    expect(speakers.at(1000, 13000), 's1');
    expect(speakers.at(16000, 20000), 's2');
    expect(speakers.at(23000, 39000), 's1');
    expect(speakers.at(42000, 46000), 's2');
    expect(speakers.at(50000, 57000), 's1');
    // Silence has no one.
    expect(speakers.at(59200, 59800), isNull);
    expect(models.prints, greaterThan(4));
  });

  test('three voices, and one speaker alone', () async {
    final three = await _find(_audio([(0, 9, 1), (10, 19, 2), (20, 29, 3), (30, 39, 1)], 40), _FakeModels());
    expect(three.count, 3);
    expect([three.at(1000, 8000), three.at(11000, 18000), three.at(21000, 28000), three.at(31000, 38000)], ['s1', 's2', 's3', 's1']);

    final one = await _find(_audio([(1, 25, 1)], 30), _FakeModels());
    expect(one.count, 1);
    expect(one.at(2000, 20000), 's1');
  });

  test('a cough heard once is no speaker of its own', () async {
    final speakers = await _find(_audio([(0, 30, 1), (31, 32, 4), (33, 60, 1)], 62), _FakeModels());
    expect(speakers.count, 1);
  });

  test('no one talking: nobody', () async {
    final speakers = await _find(Float32List(5 * sampleRate), _FakeModels());
    expect(speakers.count, 0);
    expect(speakers.at(0, 5000), isNull);
  });

  test('lines get their speakers; a line that changes speaker is split at the word', () async {
    final speakers = await _find(_audio([(0, 10, 1), (10.2, 20, 2)], 22), _FakeModels());
    final heard = [
      const HeardSegment(1000, 8000, ' So momentum is conserved.', [
        (1000, 1500, ' So'),
        (1600, 3000, ' momentum'),
        (3100, 4000, ' is'),
        (4100, 8000, ' conserved.'),
      ]),
      // "Right?" by the professor, then the student answers.
      const HeardSegment(8500, 14000, ' Right? Yes, I think so.', [
        (8500, 9500, ' Right?'),
        (10500, 11000, ' Yes,'),
        (11100, 11500, ' I'),
        (11600, 12000, ' think'),
        (12100, 14000, ' so.'),
      ]),
    ];
    final lines = withSpeakers(linesHeard(heard), speakers, heard: heard);
    expect([for (final l in lines) (l.speaker, l.text)], [
      ('s1', 'So momentum is conserved.'),
      ('s1', 'Right?'),
      ('s2', 'Yes, I think so.'),
    ]);
    expect(lines[2].tMs, 10500);
    expect(lines[1].endMs, 9500);
  });

  test('times, text and languages', () {
    expect(clockOf(0), '0:00');
    expect(clockOf(760000), '12:40');
    expect(clockOf(2900000), '48:20');
    expect(clockOf(3725000), '1:02:05');
    final clip = AudioItem(
      id: 'it_1',
      x: 0,
      y: 0,
      z: 1,
      createdAt: DateTime.utc(2026, 11, 6),
      asset: 'a.m4a',
      name: 'Lecture 3 recording',
      recordedAt: DateTime.utc(2026, 11, 6),
      durationMs: 60000,
      transcript: const [
        TranscriptLine(tMs: 722000, endMs: 740000, speaker: 's1', text: 'Okay, so last time…'),
        TranscriptLine(tMs: 810000, endMs: 830000, speaker: 's2', text: 'What about after?'),
        TranscriptLine(tMs: 842000, endMs: 850000, text: 'Right.'),
      ],
      speakers: const {'s1': 'Professor'},
    );
    expect(transcriptText(clip), '12:02 Professor: Okay, so last time…\n13:30 Speaker 2: What about after?\n14:02 Right.');
    expect(transcriptText(clip, times: false).split('\n').first, 'Professor: Okay, so last time…');
    expect(languageName('en'), 'English');
    expect(languageName('de'), 'German');
    expect(languageName(null), '');
  });
}
