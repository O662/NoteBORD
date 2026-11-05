import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:endless/audio/platform_audio.dart';
import 'package:endless/audio/recording.dart';
import 'package:endless/audio/speakers.dart';
import 'package:endless/audio/speech_models.dart';
import 'package:endless/audio/transcript_lines.dart';
import 'package:endless/audio/transcription.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

// Stand-ins for the microphone, the player, the Android helpers and the
// speech models, so recording, playing and transcripts can be tested
// anywhere.

/// A 16 kHz mono WAV of [ms] of silence.
Uint8List silentWav(int ms) {
  final n = ms * 16;
  final d = ByteData(44 + n * 2);
  void s(int at, String t) {
    for (final (i, u) in t.codeUnits.indexed) {
      d.setUint8(at + i, u);
    }
  }

  s(0, 'RIFF');
  d.setUint32(4, 36 + n * 2, Endian.little);
  s(8, 'WAVE');
  s(12, 'fmt ');
  d
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, 16000, Endian.little)
    ..setUint32(28, 32000, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  s(36, 'data');
  d.setUint32(40, n * 2, Endian.little);
  return d.buffer.asUint8List();
}

class FakeRecorder implements AudioRecorder {
  FakeRecorder(this.lengthMs, {this.allow = true});

  final int Function() lengthMs;
  final bool allow;
  final _levels = StreamController<double>.broadcast();
  String? path;
  final calls = <String>[];

  @override
  Future<bool> allowed() async => allow;

  @override
  String get extension => 'wav';

  @override
  Future<void> start(String path) async {
    this.path = path;
    calls.add('start');
  }

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Future<void> stop() async {
    calls.add('stop');
    await File(path!).writeAsBytes(silentWav(lengthMs()));
  }

  void level(double v) => _levels.add(v);

  @override
  Stream<double> get levels => _levels.stream;
}

class ManualClock extends RecordingClock {
  int now = 0;

  @override
  int get ms => now;

  @override
  void start() {}

  @override
  void stop() {}
}

class FakeAudioTools implements AudioTools {
  final kept = <(bool, String)>[];

  /// The files read for transcripts.
  final decoded = <String>[];

  @override
  Future<bool> keepGoing(bool on, {String kind = 'record', String title = '', String text = ''}) async {
    kept.add((on, kind));
    return true;
  }

  @override
  Future<(String, int?)> finish(String path) async => (path, wavDurationMs(await File(path).readAsBytes()));

  @override
  Future<int> decode(String path, String to) async {
    decoded.add(path);
    final pcm = wavTo16k(await File(path).readAsBytes());
    await File(to).writeAsBytes(pcm.buffer.asUint8List());
    return pcm.length;
  }
}

class FakePlayer implements AudioPlayer {
  final opened = <int>[];
  final seeks = <int>[];
  final speeds = <double>[];
  bool isPlaying = false;
  final _position = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _ended = StreamController<void>.broadcast();

  @override
  Future<Duration?> open(Uint8List bytes, String extension) async {
    opened.add(bytes.length);
    return extension == 'wav' ? Duration(milliseconds: wavDurationMs(bytes) ?? 0) : null;
  }

  @override
  Future<void> play() async {
    isPlaying = true;
    _playing.add(true);
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
    _playing.add(false);
  }

  @override
  Future<void> seek(Duration to) async {
    seeks.add(to.inMilliseconds);
    _position.add(to);
  }

  @override
  Future<void> setSpeed(double speed) async => speeds.add(speed);

  /// Moves the playhead as if it had played to [ms].
  void reach(int ms) => _position.add(Duration(milliseconds: ms));

  void end() => _ended.add(null);

  @override
  Stream<Duration> get position => _position.stream;

  @override
  Stream<bool> get playing => _playing.stream;

  @override
  Stream<void> get ended => _ended.stream;

  @override
  Future<void> close() async {}
}

/// Hears [parts] (each a list of segments), one part after another.
class FakeSpeechToText implements SpeechToText {
  FakeSpeechToText(this.parts, {this.language = 'en'});

  final List<List<HeardSegment>> parts;
  final String language;
  final asked = <int>[];
  bool _cancelled = false;

  /// Fails after this many parts, as if the app were stopped there.
  int? stopAfter;

  @override
  Stream<HeardPart> hear(String pcmPath, {required int fromMs, String language = 'auto', String prompt = '', void Function(double)? progress}) async* {
    asked.add(fromMs);
    _cancelled = false;
    var n = 0;
    for (final part in parts) {
      final end = part.isEmpty ? fromMs : part.last.t1;
      if (end <= fromMs) continue;
      if (_cancelled) return;
      if (stopAfter != null && n >= stopAfter!) throw const SpeechError('stopped');
      n++;
      progress?.call(0.5);
      yield HeardPart(part, this.language, end);
    }
  }

  @override
  void cancel() => _cancelled = true;
}

/// One voice throughout (everyone is s1), or [who] by time.
class FakeSpeakerModels implements SpeakerModels {
  @override
  Future<Float32List> segment(Float32List window) async {
    final scores = Float32List(frames * 7);
    for (var f = 0; f < frames; f++) {
      scores[f * 7 + 1] = 5;
    }
    return scores;
  }

  @override
  Future<Float32List> voicePrint(Float32List samples) async => Float32List.fromList([1, 0, 0]);
}

/// Overrides for recording, playing and transcripts with the fakes above,
/// files in [dir].
List<Override> audioOverrides({
  required Directory dir,
  required FakeRecorder Function() recorder,
  required ManualClock clock,
  required FakeAudioTools tools,
  required FakePlayer player,
  SpeechToText? words,
  SpeakerModels? speakers,
  bool noModel = false,
}) =>
    [
      recordingDirProvider.overrideWithValue(() async => Directory('${dir.path}/rec')..createSync(recursive: true)),
      transcriptWorkDirProvider.overrideWithValue(() async => Directory('${dir.path}/work')..createSync(recursive: true)),
      audioRecorderProvider.overrideWithValue(recorder),
      recordingClockProvider.overrideWithValue(() => clock),
      audioToolsProvider.overrideWithValue(tools),
      audioPlayerProvider.overrideWithValue(() => player),
      speechEnginesProvider.overrideWithValue(
          () async => noModel ? null : SpeechEngines(words ?? FakeSpeechToText(const []), speakers)),
    ];
