import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:endless_speech/endless_speech.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'speakers.dart';
import 'transcript_lines.dart';

// The speech models bundled with the app (assets/speech, fetched and
// checked by tool/speech_model/fetch.dart), and running them: whisper.cpp
// in a background isolate for the words, ONNX Runtime for the speakers.
// All on the device; nothing is sent anywhere.

/// Bump when the model files change, so the copies on the device are
/// replaced.
const speechModelVersion = 'speech-1';

const whisperFile = 'whisper-base-q5_1.bin';
const segmentationFile = 'segmentation-3.0.onnx';
const speakersFile = 'speakers-ecapa.onnx';

/// Where the models are on the device once copied out of the app.
class SpeechModelPaths {
  const SpeechModelPaths({required this.whisper, this.segmentation, this.speakers});

  final String whisper;

  /// Null when the speaker models aren't in this build: transcripts come
  /// without speakers.
  final String? segmentation;
  final String? speakers;
}

/// Copies the bundled models out of the app once (whole, or not at all).
/// Null if this build has no speech model.
Future<SpeechModelPaths?> bundledSpeechModels() async {
  final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'speech', speechModelVersion));
  Future<String?> extract(String name) async {
    final file = File(p.join(dir.path, name));
    if (await file.exists()) return file.path;
    final ByteData data;
    try {
      data = await rootBundle.load('assets/speech/$name');
    } on Object {
      return null;
    }
    await dir.create(recursive: true);
    final part = File('${file.path}.part');
    await part.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
    await part.rename(file.path);
    return file.path;
  }

  final whisper = await extract(whisperFile);
  if (whisper == null) return null;
  final seg = await extract(segmentationFile);
  final spk = await extract(speakersFile);
  return SpeechModelPaths(whisper: whisper, segmentation: spk == null ? null : seg, speakers: seg == null ? null : spk);
}

/// One part of the recording, heard.
class HeardPart {
  const HeardPart(this.segments, this.language, this.upToMs);

  final List<HeardSegment> segments;
  final String language;

  /// How far into the recording it has got.
  final int upToMs;
}

/// Speech to text, behind an interface so tests can stand in for it.
abstract interface class SpeechToText {
  /// Hears the 16 kHz float32 file [pcmPath] from [fromMs], a part at a
  /// time. [language] is a code or `auto`; [prompt] the text heard just
  /// before [fromMs]. [progress] gets 0–1 for the whole file.
  Stream<HeardPart> hear(
    String pcmPath, {
    required int fromMs,
    String language = 'auto',
    String prompt = '',
    void Function(double)? progress,
  });

  /// Stops [hear] at the next chance.
  void cancel();
}

/// whisper.cpp (vendored in packages/endless_speech) in its own isolate,
/// which reads the file a part at a time.
class WhisperSpeechToText implements SpeechToText {
  WhisperSpeechToText(this.modelPath);

  final String modelPath;
  SpeechWatch? _watch;

  /// Parts are about this long, cut where it's quietest near the end.
  static const partMs = 4 * 60 * 1000;

  @override
  Stream<HeardPart> hear(
    String pcmPath, {
    required int fromMs,
    String language = 'auto',
    String prompt = '',
    void Function(double)? progress,
  }) async* {
    final watch = _watch = SpeechWatch();
    final total = (await File(pcmPath).length()) ~/ 4 * 1000 ~/ sampleRate;
    final port = ReceivePort();
    final threads = math.max(1, math.min(4, Platform.numberOfProcessors ~/ 2));
    final isolate = await Isolate.spawn(
      _hearInIsolate,
      _Job(port.sendPort, modelPath, pcmPath, fromMs, language, prompt, threads, watch.cancelAddress, watch.progressAddress),
      onError: port.sendPort,
      onExit: port.sendPort,
    );
    // The share of the current part done, for progress between parts.
    var partFrom = fromMs, partTo = math.min(total, fromMs + partMs);
    final tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (total == 0) return;
      progress?.call((partFrom + (partTo - partFrom) * watch.progress / 100) / total);
    });
    try {
      await for (final m in port) {
        if (m is HeardPart) {
          partFrom = m.upToMs;
          partTo = math.min(total, m.upToMs + partMs);
          progress?.call(total == 0 ? 1 : m.upToMs / total);
          yield m;
        } else if (m is (int, int)) {
          partFrom = m.$1;
          partTo = m.$2;
        } else if (m is String) {
          throw SpeechError(m);
        } else if (m is List) {
          // An uncaught error in the isolate.
          throw SpeechError('${m.first}');
        } else {
          break;
        }
      }
    } finally {
      tick.cancel();
      port.close();
      isolate.kill();
      _watch = null;
      watch.dispose();
    }
  }

  @override
  void cancel() => _watch?.cancel();
}

class SpeechError implements Exception {
  const SpeechError(this.message);

  final String message;

  @override
  String toString() => message;
}

class _Job {
  const _Job(this.port, this.model, this.pcm, this.fromMs, this.language, this.prompt, this.threads, this.cancel, this.progress);

  final SendPort port;
  final String model;
  final String pcm;
  final int fromMs;
  final String language;
  final String prompt;
  final int threads;
  final int cancel;
  final int progress;
}

Future<void> _hearInIsolate(_Job job) async {
  final model = SpeechModel.open(job.model, threads: job.threads);
  if (model == null) {
    job.port.send('The speech model couldn’t be read.');
    return;
  }
  final watch = SpeechWatch.at(job.cancel, job.progress);
  final file = await File(job.pcm).open();
  try {
    final total = await file.length() ~/ 4;
    var from = job.fromMs * sampleRate ~/ 1000;
    var language = job.language;
    var prompt = job.prompt;
    while (from < total && !watch.cancelled) {
      final to = await _cutNear(file, from, total);
      job.port.send((from * 1000 ~/ sampleRate, to * 1000 ~/ sampleRate));
      await file.setPosition(from * 4);
      final bytes = await file.read((to - from) * 4);
      final samples = bytes.buffer.asFloat32List(bytes.offsetInBytes, bytes.length ~/ 4);
      final heard = model.transcribe(
        Float32List.fromList(samples),
        language: language,
        prompt: prompt,
        offsetMs: from * 1000 ~/ sampleRate,
        watch: watch,
      );
      if (watch.cancelled) break;
      if (heard == null) {
        job.port.send('The recording couldn’t be transcribed.');
        return;
      }
      // The rest is heard in the language the first part was in.
      if (language == 'auto' && heard.language.isNotEmpty && heard.segments.isNotEmpty) language = heard.language;
      final segments = [
        for (final s in heard.segments)
          HeardSegment(s.t0, s.t1, s.text, [for (final w in s.words) (w.t0, w.t1, w.text)]),
      ];
      final text = segments.map((s) => s.text).join(' ');
      prompt = text.length > 220 ? text.substring(text.length - 220) : text;
      from = to;
      job.port.send(HeardPart(segments, language == 'auto' ? heard.language : language, from * 1000 ~/ sampleRate));
    }
  } finally {
    await file.close();
    model.close();
  }
  job.port.send(null);
}

/// Where the part starting at [from] ends: about [WhisperSpeechToText.partMs]
/// on, at the quietest 0.2 s within 20 s of that.
Future<int> _cutNear(RandomAccessFile file, int from, int total) async {
  final target = from + WhisperSpeechToText.partMs * sampleRate ~/ 1000;
  // A short last part is read with the rest.
  if (target + 30 * sampleRate >= total) return total;
  const span = 20 * sampleRate, block = sampleRate ~/ 5;
  final a = target - span;
  await file.setPosition(a * 4);
  final bytes = await file.read(2 * span * 4);
  final s = bytes.buffer.asFloat32List(bytes.offsetInBytes, bytes.length ~/ 4);
  var best = target;
  var quietest = double.infinity;
  for (var b = 0; b + block <= s.length; b += block) {
    var e = 0.0;
    for (var i = b; i < b + block; i++) {
      e += s[i] * s[i];
    }
    if (e < quietest) {
      quietest = e;
      best = a + b + block ~/ 2;
    }
  }
  return best;
}

/// The speaker models on ONNX Runtime (Microsoft, MIT), as math mode uses.
class OnnxSpeakerModels implements SpeakerModels {
  OnnxSpeakerModels._(this._segmentation, this._speakers);

  final OrtSession _segmentation;
  final OrtSession _speakers;

  static Future<OnnxSpeakerModels> load(String segmentation, String speakers) async {
    final runtime = OnnxRuntime();
    return OnnxSpeakerModels._(await runtime.createSession(segmentation), await runtime.createSession(speakers));
  }

  @override
  Future<Float32List> segment(Float32List window) async {
    final input = await OrtValue.fromList(window, [1, 1, window.length]);
    try {
      final out = await _segmentation.run({'input_values': input});
      final logits = out['logits']!;
      final list = await logits.asFlattenedList();
      unawaited(logits.dispose());
      return Float32List.fromList([for (final v in list) (v as num).toDouble()]);
    } finally {
      unawaited(input.dispose());
    }
  }

  @override
  Future<Float32List> voicePrint(Float32List samples) async {
    final input = await OrtValue.fromList(samples, [1, samples.length]);
    try {
      final out = await _speakers.run({'audio': input});
      final e = out['embedding']!;
      final list = await e.asFlattenedList();
      unawaited(e.dispose());
      return Float32List.fromList([for (final v in list) (v as num).toDouble()]);
    } finally {
      unawaited(input.dispose());
    }
  }

  Future<void> close() async {
    await _segmentation.close();
    await _speakers.close();
  }
}

/// [samples] of the 16 kHz float32 file at [path], from [from].
Future<Float32List> readPcm(String path, {int from = 0, int? count}) async {
  final file = await File(path).open();
  try {
    final total = await file.length() ~/ 4;
    final n = math.max(0, math.min(count ?? total, total - from));
    await file.setPosition(from * 4);
    final bytes = await file.read(n * 4);
    return Float32List.fromList(bytes.buffer.asFloat32List(bytes.offsetInBytes, bytes.length ~/ 4));
  } finally {
    await file.close();
  }
}
