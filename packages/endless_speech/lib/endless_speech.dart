/// Speech to text on the device with whisper.cpp (vendored in `src/`).
///
/// Everything runs offline: the model is a file on the device and nothing
/// here opens a network connection.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// The native library, loaded once per isolate.
final DynamicLibrary _lib = () {
  if (Platform.isAndroid || Platform.isLinux) return DynamicLibrary.open('libendless_speech.so');
  if (Platform.isWindows) return DynamicLibrary.open(_windowsPath ?? 'endless_speech.dll');
  if (Platform.isMacOS || Platform.isIOS) return DynamicLibrary.process();
  throw UnsupportedError('Speech to text isn’t available on ${Platform.operatingSystem}.');
}();

String? _windowsPath;

/// For tests on a desktop: where the built library is.
void useSpeechLibrary(String path) => _windowsPath = path;

typedef _OpenC = Pointer<Void> Function(Pointer<Utf8>, Int32);
typedef _OpenD = Pointer<Void> Function(Pointer<Utf8>, int);
typedef _CloseC = Void Function(Pointer<Void>);
typedef _CloseD = void Function(Pointer<Void>);
typedef _TranscribeC = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Float>, Int32, Pointer<Utf8>, Pointer<Utf8>, Int64, Pointer<Int32>, Pointer<Int32>);
typedef _TranscribeD = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Float>, int, Pointer<Utf8>, Pointer<Utf8>, int, Pointer<Int32>, Pointer<Int32>);
typedef _FreeC = Void Function(Pointer<Utf8>);
typedef _FreeD = void Function(Pointer<Utf8>);
typedef _VersionC = Pointer<Utf8> Function();

final _open = _lib.lookupFunction<_OpenC, _OpenD>('es_open');
final _close = _lib.lookupFunction<_CloseC, _CloseD>('es_close');
final _transcribe = _lib.lookupFunction<_TranscribeC, _TranscribeD>('es_transcribe');
final _free = _lib.lookupFunction<_FreeC, _FreeD>('es_free_string');
final _version = _lib.lookupFunction<_VersionC, _VersionC>('es_version');

/// A word and when it was said, in milliseconds.
class SpeechWord {
  const SpeechWord(this.t0, this.t1, this.text);

  final int t0;
  final int t1;
  final String text;
}

/// A stretch of speech: when, what was said, and its words.
class SpeechSegment {
  const SpeechSegment(this.t0, this.t1, this.text, this.words);

  final int t0;
  final int t1;
  final String text;
  final List<SpeechWord> words;
}

class SpeechResult {
  const SpeechResult(this.language, this.segments);

  /// The language heard (a code such as `en`).
  final String language;
  final List<SpeechSegment> segments;

  static SpeechResult parse(String json) {
    final m = jsonDecode(json) as Map<String, Object?>;
    return SpeechResult(m['language'] as String? ?? '', [
      for (final s in (m['segments'] as List? ?? const []).cast<Map<String, Object?>>())
        SpeechSegment(
          (s['t0'] as num).toInt(),
          (s['t1'] as num).toInt(),
          (s['text'] as String? ?? '').trim(),
          [
            for (final w in (s['words'] as List? ?? const []).cast<List<Object?>>())
              SpeechWord((w[0] as num).toInt(), (w[1] as num).toInt(), w[2] as String? ?? ''),
          ],
        ),
    ]);
  }
}

/// A loaded whisper.cpp model. Use it from one isolate at a time; a
/// transcription blocks that isolate until it's done.
class SpeechModel {
  SpeechModel._(this._ctx);

  /// Loads the model at [path]; null if it can't be read.
  static SpeechModel? open(String path, {int threads = 4}) {
    final p = path.toNativeUtf8();
    try {
      final ctx = _open(p, threads);
      return ctx == nullptr ? null : SpeechModel._(ctx);
    } finally {
      malloc.free(p);
    }
  }

  static String get version => _version().toDartString();

  Pointer<Void> _ctx;

  /// [cancel] and [progress] are native ints another isolate may read or
  /// set (see [SpeechWatch]).
  SpeechResult? transcribe(
    Float32List samples, {
    String language = 'auto',
    String prompt = '',
    int offsetMs = 0,
    SpeechWatch? watch,
  }) {
    if (_ctx == nullptr) throw StateError('closed');
    final pcm = malloc<Float>(samples.length);
    final lang = language.toNativeUtf8();
    final pr = prompt.toNativeUtf8();
    try {
      pcm.asTypedList(samples.length).setAll(0, samples);
      final out = _transcribe(_ctx, pcm, samples.length, lang, pr, offsetMs, watch?._cancel ?? nullptr, watch?._progress ?? nullptr);
      if (out == nullptr) return null;
      try {
        // Tokens can split a character; anything left malformed is dropped.
        final bytes = out.cast<Uint8>();
        var n = 0;
        while (bytes[n] != 0) {
          n++;
        }
        return SpeechResult.parse(utf8.decode(bytes.asTypedList(n), allowMalformed: true));
      } finally {
        _free(out);
      }
    } finally {
      malloc
        ..free(pcm)
        ..free(lang)
        ..free(pr);
    }
  }

  void close() {
    if (_ctx == nullptr) return;
    _close(_ctx);
    _ctx = nullptr;
  }
}

/// Two native ints shared between isolates: set [cancel] to stop a
/// transcription; [progress] is 0–100 within the current part.
class SpeechWatch {
  SpeechWatch() : this._(calloc<Int32>(), calloc<Int32>());

  SpeechWatch._(this._cancel, this._progress);

  /// The same ints, in another isolate.
  SpeechWatch.at(int cancel, int progress) : this._(Pointer.fromAddress(cancel), Pointer.fromAddress(progress));

  final Pointer<Int32> _cancel;
  final Pointer<Int32> _progress;

  int get cancelAddress => _cancel.address;
  int get progressAddress => _progress.address;

  void cancel() => _cancel.value = 1;
  bool get cancelled => _cancel.value != 0;
  int get progress => _progress.value;

  void reset() {
    _cancel.value = 0;
    _progress.value = 0;
  }

  /// Only by the isolate that made it.
  void dispose() {
    calloc
      ..free(_cancel)
      ..free(_progress);
  }
}
