import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../board/model.dart';
import '../state/notebook.dart';
import '../video/video_files.dart' show videosDirProvider;
import 'platform_audio.dart';
import 'speakers.dart';
import 'speech_models.dart';
import 'transcript_lines.dart';

// Making transcripts (Audio.png's Transcript panel), on the device, one
// recording at a time, in the background. The words come a part (about
// 4 minutes) at a time and are saved as they come, so a transcript that
// was stopped (the app closed) carries on from where it got to; the
// speakers are found once all the words are in. Saving a transcript isn't
// an undo step.

/// The engines: speech to text, and the speaker models when this build has
/// them. Null when this build has no speech model.
class SpeechEngines {
  const SpeechEngines(this.words, this.speakers);

  final SpeechToText words;
  final SpeakerModels? speakers;
}

final speechEnginesProvider = Provider<Future<SpeechEngines?> Function()>((ref) {
  Future<SpeechEngines?>? loading;
  return () => loading ??= () async {
        final paths = await bundledSpeechModels();
        if (paths == null) return null;
        SpeakerModels? speakers;
        if (paths.segmentation != null && paths.speakers != null) {
          try {
            speakers = await OnnxSpeakerModels.load(paths.segmentation!, paths.speakers!);
          } on Object {
            // Transcripts still come, without speakers.
            speakers = null;
          }
        }
        return SpeechEngines(WhisperSpeechToText(paths.whisper), speakers);
      }();
});

/// Where recordings are unpacked while they're transcribed (deleted after).
final transcriptWorkDirProvider = Provider<Future<Directory> Function()>((ref) => () async {
      final dir = Directory(p.join((await getTemporaryDirectory()).path, 'transcribing'));
      await dir.create(recursive: true);
      return dir;
    });

/// How a transcript being made is going.
@immutable
class TranscriptProgress {
  const TranscriptProgress(this.share, {this.speakers = false});

  /// 0–1.
  final double share;

  /// Finding the speakers (the words are all in).
  final bool speakers;

  int get percent => (share * 100).floor().clamp(0, 99);
}

final transcriptionProvider = NotifierProvider<TranscriptionQueue, Map<String, TranscriptProgress>>(TranscriptionQueue.new);

/// Why the last transcript couldn't be made, by recording id.
final transcriptErrorsProvider = NotifierProvider<TranscriptErrors, Map<String, String>>(TranscriptErrors.new);

class TranscriptErrors extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => const {};

  void set(String itemId, String? message) {
    final next = {...state}..remove(itemId);
    if (message != null) next[itemId] = message;
    state = next;
  }
}

class TranscriptionQueue extends Notifier<Map<String, TranscriptProgress>> {
  final _queue = <(String, String)>[];
  bool _running = false;
  String? _current;
  bool _cancelled = false;
  SpeechEngines? _engines;

  @override
  Map<String, TranscriptProgress> build() => const {};

  /// Makes the transcript of recording [itemId] in [notebookId] (after any
  /// already waiting).
  void add(String notebookId, String itemId) {
    if (_current == itemId || _queue.any((j) => j.$2 == itemId)) return;
    _queue.add((notebookId, itemId));
    state = {...state, itemId: const TranscriptProgress(0)};
    unawaited(_run());
  }

  /// Carries on with the transcripts of [notebookId]'s recordings that
  /// aren't finished (the app was closed while they were made).
  void resume(String notebookId) {
    if (!ref.read(loadedNotebookProvider(notebookId)).hasValue) return;
    final nb = ref.read(notebookProvider(notebookId).notifier);
    for (final (_, clip) in nb.mediaClips) {
      if (clip.state == TranscriptState.waiting || clip.state == TranscriptState.working) add(notebookId, clip.id);
    }
  }

  /// Stops making recording [itemId]'s transcript (it was deleted).
  void cancel(String itemId) {
    _queue.removeWhere((j) => j.$2 == itemId);
    if (_current == itemId) {
      _cancelled = true;
      _engines?.words.cancel();
    }
    state = {...state}..remove(itemId);
  }

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty) {
        final (nbId, itemId) = _queue.removeAt(0);
        _current = itemId;
        _cancelled = false;
        try {
          await _make(nbId, itemId);
          ref.read(transcriptErrorsProvider.notifier).set(itemId, null);
        } on Object catch (e) {
          if (!ref.mounted) return;
          ref.read(transcriptErrorsProvider.notifier).set(itemId, _say(e));
        } finally {
          _current = null;
          if (ref.mounted) state = {...state}..remove(itemId);
        }
      }
    } finally {
      _running = false;
    }
  }

  static String _say(Object e) => switch (e) {
        SpeechError(:final message) => message,
        FileSystemException() => 'The recording couldn’t be read.',
        _ => 'Something went wrong ($e).',
      };

  void _progress(String itemId, double share, {bool speakers = false}) {
    if (!ref.mounted || _current != itemId) return;
    state = {...state, itemId: TranscriptProgress(share, speakers: speakers)};
  }

  Future<void> _make(String nbId, String itemId) async {
    // Keeps the notebook open while its transcript is made, even if it's
    // closed on screen.
    final keep = ref.listen(notebookProvider(nbId), (_, _) {});
    final tools = ref.read(audioToolsProvider);
    final files = <File>[];
    var kept = false;
    try {
      final nb = ref.read(notebookProvider(nbId).notifier);
      Transcribed? clip = nb.mediaClip(itemId)?.$2;
      if (clip == null || clip.state == TranscriptState.done) return;
      final engines = _engines ??= await ref.read(speechEnginesProvider)();
      if (engines == null) {
        nb.setTranscript(clip.withTranscript(state: TranscriptState.failed));
        throw const SpeechError('This build of Endless has no speech model (see tool/speech_model/README.md).');
      }
      final dir = await ref.read(transcriptWorkDirProvider)();
      final pcm = File(p.join(dir.path, '$itemId.f32'));
      files.add(pcm);
      // The recording's (or video's) file: read where it's kept when it's
      // there in the clear; else opened and written out to read.
      String? source;
      if (clip case VideoItem(link: final link?)) {
        final f = File(p.join((await ref.read(videosDirProvider)()).path, link));
        if (!await f.exists()) throw const SpeechError('The video isn’t on this tablet any more.');
        source = f.path;
      } else {
        final asset = switch (clip) {
          VideoItem(:final asset) => asset!,
          AudioItem(:final asset) => asset,
          _ => throw StateError('not a recording or video'),
        };
        source = await nb.assetPath(asset);
        if (source == null) {
          final bytes = await nb.readAsset(asset);
          // A locked page: its transcript waits until it's unlocked.
          if (bytes == null) return;
          final copy = File(p.join(dir.path, '$itemId${p.extension(asset)}'));
          files.add(copy);
          await copy.writeAsBytes(bytes, flush: true);
          source = copy.path;
        }
      }
      kept = await tools.keepGoing(true, kind: 'transcribe', title: 'Making a transcript', text: clip.name);
      final samples = await tools.decode(source, pcm.path);
      for (final f in files) {
        if (f != pcm && f.existsSync()) await f.delete();
      }
      if (_cancelled) return;

      final heard = <HeardSegment>[];
      var lines = [...clip.transcript];
      // The lines on the page now: they may have been edited meanwhile.
      List<TranscriptLine> onPage() => nb.mediaClip(itemId)?.$2.transcript ?? lines;
      final durationMs = math.max(1, samples * 1000 ~/ sampleRate);
      final wordsShare = engines.speakers == null ? 1.0 : 0.85;
      if (clip.state != TranscriptState.working || clip.upToMs < durationMs) {
        clip = clip.withTranscript(state: TranscriptState.working);
        nb.setTranscript(clip);
        final prompt = lines.map((l) => l.text).join(' ');
        await for (final part in engines.words.hear(
          pcm.path,
          fromMs: clip.upToMs,
          language: clip.language ?? 'auto',
          prompt: prompt.length > 220 ? prompt.substring(prompt.length - 220) : prompt,
          progress: (share) => _progress(itemId, share * wordsShare),
        )) {
          if (_cancelled || !ref.mounted) return;
          heard.addAll(part.segments);
          lines = [...onPage(), ...linesHeard(part.segments)];
          clip = clip!.withTranscript(transcript: lines, upToMs: part.upToMs, language: part.language.isEmpty ? null : part.language);
          if (!nb.setTranscript(clip)) {
            // The recording was deleted (or its page locked): it carries on
            // from here if it comes back.
            engines.words.cancel();
            return;
          }
        }
        if (_cancelled) return;
      }
      lines = onPage();
      if (engines.speakers case final models? when lines.isNotEmpty) {
        _progress(itemId, wordsShare, speakers: true);
        final timeline = await findSpeakers(
          samples,
          (from, count) => readPcm(pcm.path, from: from, count: count),
          models,
          progress: (share) => _progress(itemId, wordsShare + (1 - wordsShare) * share, speakers: true),
          cancelled: () => _cancelled,
        );
        if (_cancelled) return;
        lines = withSpeakers(lines, timeline, heard: heard);
      }
      nb.setTranscript(clip!.withTranscript(transcript: lines, state: TranscriptState.done, upToMs: 0));
    } finally {
      keep.close();
      for (final f in files) {
        try {
          if (f.existsSync()) await f.delete();
        } on FileSystemException {
          // Cleared with the cache.
        }
      }
      if (kept) await tools.keepGoing(false, kind: 'transcribe');
    }
  }
}
