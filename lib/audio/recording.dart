import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../board/ids.dart';
import '../board/model.dart';
import '../library/library.dart' show clockProvider;
import 'ink_moments.dart';
import 'platform_audio.dart';

// Recording (Audio.png's "Recording · 0:42" pill): the microphone, a clock
// that stops while paused, and the ink written meanwhile. The recording is
// written to a file as it goes, with a note beside it every few seconds
// (which notebook and page, when each stroke was written, how loud it
// was), so if the app is stopped mid-recording it is put on its page the
// next time the notebook opens.

/// Where recordings are written while they're made.
final recordingDirProvider = Provider<Future<Directory> Function()>((ref) => () async {
      final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'recordings'));
      await dir.create(recursive: true);
      return dir;
    });

/// How long it has recorded, not counting pauses.
class RecordingClock {
  final _watch = Stopwatch();

  int get ms => _watch.elapsedMilliseconds;
  void start() => _watch.start();
  void stop() => _watch.stop();
}

final recordingClockProvider = Provider<RecordingClock Function()>((ref) => RecordingClock.new);

@immutable
class RecordingState {
  const RecordingState({
    required this.notebookId,
    required this.pageId,
    required this.audioId,
    required this.startedAt,
    required this.elapsedMs,
    required this.paused,
    required this.recent,
    this.stopping = false,
  });

  final String notebookId;
  final String pageId;
  final String audioId;
  final DateTime startedAt;
  final int elapsedMs;
  final bool paused;

  /// The last dozen loudness readings, 0–1, for the pill's waveform.
  final List<double> recent;

  /// Stop was pressed: the recording is being finished.
  final bool stopping;

  RecordingState copyWith({int? elapsedMs, bool? paused, List<double>? recent, bool? stopping}) => RecordingState(
        notebookId: notebookId,
        pageId: pageId,
        audioId: audioId,
        startedAt: startedAt,
        elapsedMs: elapsedMs ?? this.elapsedMs,
        paused: paused ?? this.paused,
        recent: recent ?? this.recent,
        stopping: stopping ?? this.stopping,
      );
}

/// A recording that's done, ready to go on its page.
class FinishedRecording {
  const FinishedRecording({
    required this.notebookId,
    required this.pageId,
    required this.audioId,
    required this.recordedAt,
    required this.bytes,
    required this.extension,
    required this.durationMs,
    required this.wave,
    required this.ink,
    required this.files,
    this.recovered = false,
  });

  final String notebookId;
  final String pageId;
  final String audioId;
  final DateTime recordedAt;
  final Uint8List bytes;
  final String extension;
  final int durationMs;
  final List<int> wave;
  final List<InkMoment> ink;

  /// Its files while it was made: deleted once it's in the notebook.
  final List<String> files;

  /// It was cut off (the app was stopped) and found again.
  final bool recovered;
}

class RecordingError implements Exception {
  const RecordingError(this.message);

  final String message;

  @override
  String toString() => message;
}

final recordingProvider = NotifierProvider<RecordingController, RecordingState?>(RecordingController.new);

class RecordingController extends Notifier<RecordingState?> {
  AudioRecorder? _recorder;
  RecordingClock? _clock;
  StreamSubscription<double>? _levels;
  Timer? _tick;
  Timer? _note;
  final _loudness = <int>[];
  final _ink = <InkMoment>[];
  String? _path;

  /// Recordings already handed back by [recover] (two views of a notebook
  /// both ask), until they're stored.
  final _recovered = <String>{};

  @override
  RecordingState? build() {
    ref.onDispose(() {
      _tick?.cancel();
      _note?.cancel();
      _levels?.cancel();
    });
    return null;
  }

  bool get isRecording => state != null;

  /// Starts recording for [pageId] of [notebookId]. Throws [RecordingError]
  /// when it can't (no microphone, or not allowed).
  Future<void> start({required String notebookId, required String pageId, String title = ''}) async {
    if (state != null) return;
    final recorder = ref.read(audioRecorderProvider)();
    if (!await recorder.allowed()) {
      throw const RecordingError('Endless needs the microphone to record. Allow it in the tablet’s settings for Endless.');
    }
    final dir = await ref.read(recordingDirProvider)();
    final id = newId('it');
    final path = p.join(dir.path, '$id.${recorder.extension}');
    final tools = ref.read(audioToolsProvider);
    // Keeps the microphone going with the screen off or another app in
    // front (a notification shows while it records).
    await tools.keepGoing(true, kind: 'record', title: 'Recording', text: title);
    try {
      await recorder.start(path);
    } on Object catch (e) {
      await tools.keepGoing(false);
      throw RecordingError('The recording couldn’t start ($e).');
    }
    _recorder = recorder;
    _path = path;
    _loudness.clear();
    _ink.clear();
    final clock = _clock = ref.read(recordingClockProvider)()..start();
    final started = ref.read(clockProvider)().toUtc();
    state = RecordingState(
      notebookId: notebookId,
      pageId: pageId,
      audioId: id,
      startedAt: started,
      elapsedMs: 0,
      paused: false,
      recent: const [],
    );
    _levels = recorder.levels.listen((v) {
      final s = state;
      if (s == null || s.paused) return;
      _loudness.add((v * 100).round());
      state = s.copyWith(recent: [...s.recent.skip(math.max(0, s.recent.length - 11)), v]);
    });
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final s = state;
      if (s != null && s.elapsedMs != clock.ms) state = s.copyWith(elapsedMs: clock.ms);
    });
    _note = Timer.periodic(const Duration(seconds: 5), (_) => _writeNote());
    ref.read(inkMomentsProvider).listener = (nb, strokes) {
      final s = state;
      if (s == null || s.paused || nb != s.notebookId) return;
      final t = clock.ms;
      _ink.addAll([for (final st in strokes) InkMoment(st.id, t)]);
    };
    await _writeNote();
  }

  Future<void> pause() async {
    final s = state;
    if (s == null || s.paused || s.stopping) return;
    await _recorder?.pause();
    _clock?.stop();
    state = s.copyWith(paused: true, elapsedMs: _clock?.ms);
    await _writeNote();
  }

  Future<void> resume() async {
    final s = state;
    if (s == null || !s.paused || s.stopping) return;
    await _recorder?.resume();
    _clock?.start();
    state = s.copyWith(paused: false);
  }

  /// Stops and finishes the recording. Null if nothing was recording.
  Future<FinishedRecording?> stop() async {
    final s = state;
    final recorder = _recorder;
    if (s == null || recorder == null || s.stopping) return null;
    state = s.copyWith(stopping: true);
    ref.read(inkMomentsProvider).listener = null;
    _tick?.cancel();
    _note?.cancel();
    _clock?.stop();
    final elapsed = _clock?.ms ?? s.elapsedMs;
    final tools = ref.read(audioToolsProvider);
    try {
      await recorder.stop();
      await _levels?.cancel();
      await _writeNote(elapsed: elapsed);
      final (path, ms) = await tools.finish(_path!);
      return FinishedRecording(
        notebookId: s.notebookId,
        pageId: s.pageId,
        audioId: s.audioId,
        recordedAt: s.startedAt,
        bytes: await File(path).readAsBytes(),
        extension: p.extension(path).replaceFirst('.', ''),
        durationMs: ms ?? elapsed,
        wave: waveBars(_loudness, AudioItem.waveBars),
        ink: [..._ink],
        files: {_path!, path, _notePath(_path!)}.toList(),
      );
    } finally {
      await tools.keepGoing(false);
      _recorder = null;
      _levels = null;
      _clock = null;
      state = null;
    }
  }

  /// The recording is in its notebook: its files can go.
  Future<void> stored(FinishedRecording r) async {
    for (final f in r.files) {
      try {
        await File(f).delete();
      } on FileSystemException {
        // Already gone.
      }
    }
  }

  static String _notePath(String audioPath) => p.setExtension(audioPath, '.json');

  /// Writes the note beside the recording: what it would take to put it
  /// on its page if the app were stopped now. Writes go one after another;
  /// one that fails is skipped (the next one tries again).
  Future<void> _writeNote({int? elapsed}) {
    final s = state;
    final path = _path;
    if (s == null || path == null) return _notes;
    final note = jsonEncode({
      'notebookId': s.notebookId,
      'pageId': s.pageId,
      'audioId': s.audioId,
      'startedAt': s.startedAt.toIso8601String(),
      'elapsedMs': elapsed ?? _clock?.ms ?? s.elapsedMs,
      'file': p.basename(path),
      'ink': [for (final m in _ink) m.toJson()],
      'loudness': [..._loudness],
    });
    return _notes = _notes.then((_) async {
      try {
        final f = File(_notePath(path));
        final part = File('${f.path}.part');
        await part.writeAsString(note, flush: true);
        await part.rename(f.path);
      } on FileSystemException catch (e) {
        debugPrint('Recording note not written: $e');
      }
    });
  }

  Future<void> _notes = Future.value();

  /// Recordings for [notebookId] that were cut off (the app was stopped
  /// while recording), finished now. The one recording now is left alone.
  Future<List<FinishedRecording>> recover(String notebookId) async {
    final Directory dir;
    try {
      dir = await ref.read(recordingDirProvider)();
    } on Object {
      // No place for recordings on this device (or in a test).
      return const [];
    }
    final found = <FinishedRecording>[];
    final tools = ref.read(audioToolsProvider);
    await for (final e in dir.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      try {
        final note = jsonDecode(await e.readAsString()) as Map<String, dynamic>;
        if (note['notebookId'] != notebookId || note['audioId'] == state?.audioId) continue;
        if (!_recovered.add(note['audioId'] as String)) continue;
        final audio = File(p.join(dir.path, note['file'] as String));
        final finished = File(p.setExtension(audio.path, '.m4a'));
        String path;
        int? ms;
        if (await finished.exists() && finished.path != audio.path) {
          path = finished.path;
        } else if (await audio.exists() && await audio.length() > 0) {
          (path, ms) = await tools.finish(audio.path);
        } else {
          await e.delete();
          continue;
        }
        final loudness = [for (final v in (note['loudness'] as List? ?? const [])) (v as num).toInt()];
        found.add(FinishedRecording(
          notebookId: notebookId,
          pageId: note['pageId'] as String,
          audioId: note['audioId'] as String,
          recordedAt: DateTime.parse(note['startedAt'] as String),
          bytes: await File(path).readAsBytes(),
          extension: p.extension(path).replaceFirst('.', ''),
          durationMs: ms ?? (note['elapsedMs'] as num).toInt(),
          wave: waveBars(loudness, AudioItem.waveBars),
          ink: [
            for (final m in (note['ink'] as List? ?? const []).cast<Map<String, dynamic>>())
              InkMoment(m['strokeId'] as String, (m['tMs'] as num).toInt()),
          ],
          files: {audio.path, path, e.path}.toList(),
          recovered: true,
        ));
      } on Object {
        // A note that can't be read, or audio that can't be finished:
        // left for another try.
        continue;
      }
    }
    return found;
  }
}

/// [count] bars from loudness readings (0–100): the loudest in each stretch.
List<int> waveBars(List<int> loudness, int count) {
  if (loudness.isEmpty) return List.filled(count, 0);
  return [
    for (var i = 0; i < count; i++)
      () {
        final a = i * loudness.length ~/ count;
        final b = math.max(a + 1, (i + 1) * loudness.length ~/ count);
        var m = 0;
        for (var k = a; k < b && k < loudness.length; k++) {
          m = math.max(m, loudness[k]);
        }
        return m;
      }(),
  ];
}
