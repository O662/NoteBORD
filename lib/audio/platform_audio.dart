import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:record/record.dart' as rec;

// The device's side of audio: the microphone, playing, and (on Android) a
// foreground service so recording carries on with the screen off or another
// app in front. Each is an interface, so tests can stand in for them.

/// Records to a file and says how loud it is, 0–1, as it goes.
abstract interface class AudioRecorder {
  /// Asks for the microphone if it hasn't been allowed yet.
  Future<bool> allowed();

  /// The file extension it records to (`aac` on Android: ADTS frames, which
  /// stay readable if the app is stopped mid-recording; `wav` elsewhere).
  String get extension;

  Future<void> start(String path);
  Future<void> pause();
  Future<void> resume();

  /// Stops and closes the file.
  Future<void> stop();
  Stream<double> get levels;
}

/// Finishing and reading recordings, and keeping the app going.
abstract interface class AudioTools {
  /// Keeps recording ([kind] `record`) or transcribing (`transcribe`) in the
  /// background, with a notification. False if the device wouldn't.
  Future<bool> keepGoing(bool on, {String kind = 'record', String title = '', String text = ''});

  /// Turns a finished recording into the file kept in the notebook: an
  /// .m4a from ADTS frames (Android), or the file as it is. Returns the new
  /// path and its length in ms (null if it can't tell).
  Future<(String, int?)> finish(String path);

  /// Writes [path]'s audio as 16 kHz mono float32 (little-endian) to [to].
  /// Returns the number of samples.
  Future<int> decode(String path, String to);
}

/// Plays one recording at a time.
abstract interface class AudioPlayer {
  /// Loads [bytes] (an .m4a or .wav). Returns its length.
  Future<Duration?> open(Uint8List bytes, String extension);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration to);
  Future<void> setSpeed(double speed);
  Stream<Duration> get position;
  Stream<bool> get playing;

  /// Fires when it plays to the end.
  Stream<void> get ended;
  Future<void> close();
}

final audioRecorderProvider = Provider<AudioRecorder Function()>((ref) => _RecordRecorder.new);
final audioToolsProvider = Provider<AudioTools>((ref) => PlatformAudioTools());
final audioPlayerProvider = Provider<AudioPlayer Function()>((ref) => _JustAudioPlayer.new);

/// The microphone through the `record` package (MIT; Android, iOS,
/// Windows, macOS, Linux, web).
class _RecordRecorder implements AudioRecorder {
  final _rec = rec.AudioRecorder();
  final _levels = StreamController<double>.broadcast();
  StreamSubscription<Uint8List>? _stream;
  StreamSubscription<rec.Amplitude>? _amp;
  IOSink? _sink;

  @override
  String get extension => Platform.isAndroid ? 'aac' : 'wav';

  @override
  Future<bool> allowed() => _rec.hasPermission();

  rec.RecordConfig _config(rec.AudioEncoder encoder) => rec.RecordConfig(
        encoder: encoder,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 32000,
        // Lectures are far from the microphone: let it even out the level.
        autoGain: true,
        // A notification or a call doesn't stop a lecture's recording.
        audioInterruption: rec.AudioInterruptionMode.none,
      );

  @override
  Future<void> start(String path) async {
    if (Platform.isAndroid) {
      // AAC frames as a stream, appended to the file as they come.
      final sink = _sink = File(path).openWrite();
      final stream = await _rec.startStream(_config(rec.AudioEncoder.aacLc));
      _stream = stream.listen(sink.add);
    } else {
      await _rec.start(_config(rec.AudioEncoder.wav), path: path);
    }
    _amp = _rec.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((a) {
      // dBFS: −50 dB and below is quiet.
      _levels.add(((a.current + 50) / 50).clamp(0.0, 1.0));
    });
  }

  @override
  Future<void> pause() => _rec.pause();

  @override
  Future<void> resume() => _rec.resume();

  @override
  Future<void> stop() async {
    await _rec.stop();
    await _amp?.cancel();
    await _stream?.cancel();
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
    await _rec.dispose();
    await _levels.close();
  }

  @override
  Stream<double> get levels => _levels.stream;
}

/// `endless/audio` on Android (AudioTools.kt); elsewhere WAV files need no
/// finishing and are read here.
class PlatformAudioTools implements AudioTools {
  static const _channel = MethodChannel('endless/audio');

  /// What needs the app kept going (a recording, a transcript), and what
  /// its notification says. One service serves both: it stops when
  /// neither needs it, and says "Recording" while a recording does.
  final _needs = <String, (String, String)>{};

  @override
  Future<bool> keepGoing(bool on, {String kind = 'record', String title = '', String text = ''}) async {
    if (!Platform.isAndroid) return true;
    if (on) {
      _needs[kind] = (title, text);
    } else {
      _needs.remove(kind);
    }
    final now = _needs.containsKey('record') ? 'record' : _needs.keys.firstOrNull;
    try {
      if (now == null) return await _channel.invokeMethod<bool>('keepGoing', {'on': false}) ?? false;
      final (t, x) = _needs[now]!;
      return await _channel.invokeMethod<bool>('keepGoing', {'on': true, 'kind': now, 'title': t, 'text': x}) ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<(String, int?)> finish(String path) async {
    if (!path.endsWith('.aac')) return (path, wavDurationMs(await File(path).readAsBytes()));
    final to = '${path.substring(0, path.length - 4)}.m4a';
    final ms = await _channel.invokeMethod<int>('finish', {'from': path, 'to': to});
    return (to, ms);
  }

  @override
  Future<int> decode(String path, String to) async {
    if (path.endsWith('.wav')) {
      final pcm = wavTo16k(await File(path).readAsBytes());
      await File(to).writeAsBytes(pcm.buffer.asUint8List(pcm.offsetInBytes, pcm.lengthInBytes), flush: true);
      return pcm.length;
    }
    return await _channel.invokeMethod<int>('decode', {'from': path, 'to': to}) ?? 0;
  }
}

/// A WAV file's length in ms, or null if it isn't one this reads.
int? wavDurationMs(Uint8List bytes) {
  final f = _wavFormat(bytes);
  if (f == null) return null;
  return f.dataLength * 1000 ~/ (f.rate * f.channels * 2);
}

typedef _Wav = ({int rate, int channels, int dataAt, int dataLength});

_Wav? _wavFormat(Uint8List bytes) {
  if (bytes.length < 44 || String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF') return null;
  final d = ByteData.sublistView(bytes);
  int? rate, channels, bits;
  var at = 12;
  while (at + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(at, at + 4));
    var size = d.getUint32(at + 4, Endian.little);
    if (id == 'fmt ') {
      channels = d.getUint16(at + 10, Endian.little);
      rate = d.getUint32(at + 12, Endian.little);
      bits = d.getUint16(at + 22, Endian.little);
    } else if (id == 'data') {
      // A recording cut off before its header was finished says 0 (or too
      // much): the data runs to the end of the file.
      if (size == 0 || at + 8 + size > bytes.length) size = bytes.length - at - 8;
      if (rate == null || channels == null || bits != 16) return null;
      return (rate: rate, channels: channels, dataAt: at + 8, dataLength: size - size % (2 * channels));
    }
    at += 8 + size + (size & 1);
  }
  return null;
}

/// 16-bit PCM WAV → 16 kHz mono floats (mixed down, resampled linearly).
Float32List wavTo16k(Uint8List bytes) {
  final f = _wavFormat(bytes);
  if (f == null) throw const FormatException('Not a 16-bit WAV file');
  final d = ByteData.sublistView(bytes);
  final n = f.dataLength ~/ (2 * f.channels);
  final mono = Float32List(n);
  for (var i = 0; i < n; i++) {
    var sum = 0.0;
    for (var c = 0; c < f.channels; c++) {
      sum += d.getInt16(f.dataAt + (i * f.channels + c) * 2, Endian.little) / 32768;
    }
    mono[i] = sum / f.channels;
  }
  if (f.rate == 16000) return mono;
  final out = Float32List((n * 16000 / f.rate).floor());
  final step = f.rate / 16000;
  for (var i = 0; i < out.length; i++) {
    final p = i * step;
    final a = p.floor();
    final b = math.min(n - 1, a + 1);
    out[i] = mono[a] + (mono[b] - mono[a]) * (p - a);
  }
  return out;
}

/// Plays with `just_audio` (MIT; Android, iOS, macOS, web). The recording
/// is handed over from memory, so a locked page's audio is never written
/// out in the clear.
class _JustAudioPlayer implements AudioPlayer {
  final _player = ja.AudioPlayer();
  final _ended = StreamController<void>.broadcast();
  StreamSubscription<ja.PlayerState>? _state;

  @override
  Future<Duration?> open(Uint8List bytes, String extension) async {
    _state ??= _player.playerStateStream.listen((s) {
      if (s.processingState == ja.ProcessingState.completed) _ended.add(null);
    });
    return _player.setAudioSource(_BytesSource(bytes, extension == 'wav' ? 'audio/wav' : 'audio/mp4'));
  }

  @override
  Future<void> play() async {
    // play() completes when playing stops; don't wait for that.
    unawaited(_player.play());
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration to) => _player.seek(to);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Stream<Duration> get position => _player.createPositionStream(
        minPeriod: const Duration(milliseconds: 100),
        maxPeriod: const Duration(milliseconds: 200),
      );

  @override
  Stream<bool> get playing => _player.playingStream;

  @override
  Stream<void> get ended => _ended.stream;

  @override
  Future<void> close() async {
    await _state?.cancel();
    await _ended.close();
    await _player.dispose();
  }
}

class _BytesSource extends ja.StreamAudioSource {
  _BytesSource(this._bytes, this._type);

  final Uint8List _bytes;
  final String _type;

  @override
  Future<ja.StreamAudioResponse> request([int? start, int? end]) async {
    final s = start ?? 0, e = end ?? _bytes.length;
    return ja.StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: e - s,
      offset: s,
      stream: Stream.value(Uint8List.sublistView(_bytes, s, e)),
      contentType: _type,
    );
  }
}
