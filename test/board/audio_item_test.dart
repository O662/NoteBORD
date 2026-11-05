import 'dart:typed_data';

import 'package:endless/audio/platform_audio.dart';
import 'package:endless/audio/recording.dart' show waveBars;
import 'package:endless/board/codec.dart';
import 'package:endless/board/model.dart';
import 'package:endless/canvas/audio_card.dart';
import 'package:endless/state/assets.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

AudioItem _clip({TranscriptState state = TranscriptState.done}) => AudioItem(
      id: 'it_01',
      x: 110,
      y: 520,
      z: 4,
      createdAt: DateTime.utc(2026, 11, 6, 13),
      asset: 'abc.m4a',
      name: 'Lecture 3 recording',
      recordedAt: DateTime.utc(2026, 11, 6, 12, 10),
      durationMs: 2900000,
      wave: const [0, 40, 90, 100],
      inkTimeline: const [InkMoment('it_s1', 760000), InkMoment('it_s2', 762500)],
      transcript: const [
        TranscriptLine(tMs: 722000, endMs: 744000, speaker: 's1', text: 'Okay, so last time we defined momentum.'),
        TranscriptLine(tMs: 810000, endMs: 832000, speaker: 's2', text: 'What about after?'),
      ],
      speakers: const {'s1': 'Professor'},
      language: 'en',
      state: state,
    );

void main() {
  test('an audio item goes through the file as it was, unknown fields too', () {
    final clip = _clip();
    final json = clip.toJson();
    expect(json['type'], 'audio');
    expect(json['asset'], 'abc.m4a');
    expect(json['inkTimeline'], [
      {'strokeId': 'it_s1', 'tMs': 760000},
      {'strokeId': 'it_s2', 'tMs': 762500},
    ]);
    expect(json['transcript'][0], {'tMs': 722000, 'endMs': 744000, 'speaker': 's1', 'text': 'Okay, so last time we defined momentum.'});
    // A finished transcript has no "transcribe" state in the file.
    expect(json.containsKey('transcribe'), isFalse);

    final back = decodeItem({...json, 'future': 1, 'transcript': [...json['transcript'] as List, {'tMs': 1, 'text': 'x', 'conf': 0.9}]}) as AudioItem;
    expect(back.name, 'Lecture 3 recording');
    expect(back.durationMs, 2900000);
    expect(back.wave, [0, 40, 90, 100]);
    expect(back.momentOf('it_s2'), 762500);
    expect(back.speakerName('s1'), 'Professor');
    expect(back.speakerName('s2'), 'Speaker 2');
    expect(back.language, 'en');
    expect(back.state, TranscriptState.done);
    expect(back.toJson()['future'], 1);
    expect((back.toJson()['transcript'] as List).last, {'conf': 0.9, 'tMs': 1, 'endMs': 1, 'text': 'x'});
    expect(assetRefs(back.toJson()), ['abc.m4a']);
  });

  test('a transcript being made says how far it got', () {
    final clip = _clip(state: TranscriptState.working).copyWith(upToMs: 240000);
    expect(clip.toJson()['transcribe'], {'state': 'working', 'upToMs': 240000});
    final back = decodeItem(clip.toJson()) as AudioItem;
    expect(back.state, TranscriptState.working);
    expect(back.upToMs, 240000);
    expect((decodeItem({...clip.toJson(), 'transcribe': {'state': 'later'}}) as AudioItem).state, TranscriptState.waiting);
  });

  test('a card scales by its unit; a copy isn’t linked to the ink', () {
    final clip = _clip();
    expect(Size(clip.w, clip.h), AudioItem.size);
    final big = clip.withBox(x: 0, y: 0, w: 1120, h: 304, scale: 2);
    expect(big.unit, 2);
    expect(big.w, 1120);
    expect(big.inkTimeline, hasLength(2));
    final copy = clip.withBox(id: 'it_02', x: 0, y: 0, w: clip.w, h: clip.h);
    expect(copy.inkTimeline, isEmpty);
    expect(copy.transcript, hasLength(2));
  });

  test('the card’s buttons are where Audio.dc.html puts them', () {
    final clip = _clip();
    expect(audioHitAt(clip, const Offset(38, 64))?.part, AudioPart.play);
    final wave = audioHitAt(clip, const Offset(72 + 165, 64));
    expect(wave?.part, AudioPart.wave);
    expect(wave!.share, closeTo(0.5, 0.01));
    for (final part in AudioPart.values) {
      expect(audioHitAt(clip, audioPartRect(part).center)?.part, part, reason: '$part');
    }
    // The pills sit in a row at the bottom, left to right, Transcript at the right.
    expect(audioPartRect(AudioPart.speed).center.dy, 118);
    expect(audioPartRect(AudioPart.back).left, greaterThan(audioPartRect(AudioPart.speed).right));
    expect(audioPartRect(AudioPart.forward).left, greaterThan(audioPartRect(AudioPart.back).right));
    expect(audioPartRect(AudioPart.transcript).right, 546);
    // A wider speed label moves −10 s along.
    expect(audioPartRect(AudioPart.back, speed: 1.25).left, greaterThan(audioPartRect(AudioPart.back).left));
    expect(audioHitAt(clip, const Offset(300, 20)), isNull);
    expect(audioHitAt(clip, const Offset(600, 20)), isNull);
    // At twice the size, twice as far.
    final big = clip.withBox(x: 0, y: 0, w: 1120, h: 304, scale: 2);
    expect(audioHitAt(big, const Offset(76, 128))?.part, AudioPart.play);
    expect(audioWhen(clip, now: DateTime(2026, 11, 7)), 'Fri · 48:20');
    expect(audioWhen(clip, now: DateTime(2026, 12, 7)), 'Nov 6 · 48:20');
    expect(audioText(clip), 'Lecture 3 recording\nOkay, so last time we defined momentum.\nWhat about after?');
  });

  test('WAV files: length, and 16 kHz mono for speech to text', () {
    Uint8List wav(int rate, int channels, List<int> samples, {bool cutOff = false}) {
      final data = ByteData(44 + samples.length * 2);
      void s(int at, String t) {
        for (final (i, u) in t.codeUnits.indexed) {
          data.setUint8(at + i, u);
        }
      }

      s(0, 'RIFF');
      data.setUint32(4, 36 + samples.length * 2, Endian.little);
      s(8, 'WAVE');
      s(12, 'fmt ');
      data.setUint32(16, 16, Endian.little);
      data.setUint16(20, 1, Endian.little);
      data.setUint16(22, channels, Endian.little);
      data.setUint32(24, rate, Endian.little);
      data.setUint32(28, rate * channels * 2, Endian.little);
      data.setUint16(32, channels * 2, Endian.little);
      data.setUint16(34, 16, Endian.little);
      s(36, 'data');
      data.setUint32(40, cutOff ? 0 : samples.length * 2, Endian.little);
      for (final (i, v) in samples.indexed) {
        data.setInt16(44 + i * 2, v, Endian.little);
      }
      return data.buffer.asUint8List();
    }

    expect(wavDurationMs(wav(16000, 1, List.filled(16000, 0))), 1000);
    // A recording cut off before its header was finished still reads.
    expect(wavDurationMs(wav(16000, 1, List.filled(8000, 0), cutOff: true)), 500);
    final stereo = wavTo16k(wav(16000, 2, [16384, 0, 16384, 16384]));
    expect(stereo, [0.25, 0.5]);
    final fast = wavTo16k(wav(32000, 1, List.generate(64, (i) => i * 100)));
    expect(fast.length, 32);
    expect(fast[1], closeTo(200 / 32768, 1e-6));
    expect(() => wavTo16k(Uint8List(10)), throwsFormatException);
  });

  test('the waveform keeps the loudest moment of each stretch', () {
    expect(waveBars([], 4), [0, 0, 0, 0]);
    expect(waveBars([10, 80, 20, 30, 0, 0, 100, 5], 4), [80, 30, 0, 100]);
    expect(waveBars([50], 3), [50, 50, 50]);
  });
}
