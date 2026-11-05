// Runs whisper.cpp for real when the built library and a model are given:
//   ENDLESS_SPEECH_LIB=…/endless_speech.dll ENDLESS_SPEECH_MODEL=…/ggml-base-q5_1.bin
//   ENDLESS_SPEECH_WAV=…/jfk.wav flutter test test/whisper_native_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:endless_speech/endless_speech.dart';
import 'package:flutter_test/flutter_test.dart';

Float32List _wav16k(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  var at = 12;
  while (at + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(at, at + 4));
    final size = data.getUint32(at + 4, Endian.little);
    if (id == 'data') {
      final n = size ~/ 2;
      final out = Float32List(n);
      for (var i = 0; i < n; i++) {
        out[i] = data.getInt16(at + 8 + i * 2, Endian.little) / 32768;
      }
      return out;
    }
    at += 8 + size;
  }
  throw StateError('no data');
}

void main() {
  final lib = Platform.environment['ENDLESS_SPEECH_LIB'];
  final model = Platform.environment['ENDLESS_SPEECH_MODEL'];
  final wav = Platform.environment['ENDLESS_SPEECH_WAV'];
  test('transcribes a recording on this computer', () {
    useSpeechLibrary(lib!);
    final m = SpeechModel.open(model!, threads: 4)!;
    final watch = SpeechWatch();
    final sw = Stopwatch()..start();
    final r = m.transcribe(_wav16k(File(wav!).readAsBytesSync()), offsetMs: 1000, watch: watch)!;
    sw.stop();
    for (final s in r.segments) {
      // ignore: avoid_print
      print('${s.t0}-${s.t1} ${s.text} | ${s.words.map((w) => '${w.text}@${w.t0}').join(' ')}');
    }
    // ignore: avoid_print
    print('${SpeechModel.version} · ${r.language} · ${sw.elapsedMilliseconds} ms · progress ${watch.progress}');
    expect(r.language, 'en');
    expect(r.segments.map((s) => s.text).join(' ').toLowerCase(), contains('ask not what your country can do for you'));
    expect(r.segments.first.t0, greaterThanOrEqualTo(1000));
    m.close();
    watch.dispose();
  }, skip: lib == null || model == null || wav == null ? 'needs ENDLESS_SPEECH_LIB, _MODEL and _WAV' : false);
}
