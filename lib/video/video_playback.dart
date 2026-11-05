import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart' as vp;

import '../audio/playback.dart';
import '../board/model.dart';
import '../state/notebook.dart';
import 'video_files.dart';

// Playing a video on the page (Video.png): one at a time, within its trim,
// at its speed. The card, the timeline and the pinned notes follow it.

/// The player for one video, behind an interface so tests can stand in.
abstract interface class VideoHandle {
  /// Opens [source] (a file path or a 127.0.0.1 address). Its length.
  Future<Duration> open(String source);
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration to);
  Future<void> setSpeed(double speed);
  Duration get position;
  bool get isPlaying;

  /// Fires as it plays (position) and when it starts or stops.
  Listenable get changes;

  /// The picture, filling its box (the card letterboxes it).
  Widget view();

  /// Its shape (width / height), once open.
  double get aspect;
  Future<void> dispose();
}

final videoHandleProvider = Provider<VideoHandle Function()>((ref) => _PlayerHandle.new);

/// `video_player` (the Flutter team): ExoPlayer on Android.
class _PlayerHandle implements VideoHandle {
  vp.VideoPlayerController? _c;
  final _changes = _Ping();

  @override
  Future<Duration> open(String source) async {
    final c = _c = source.startsWith('http')
        ? vp.VideoPlayerController.networkUrl(Uri.parse(source))
        : vp.VideoPlayerController.file(File(source));
    await c.initialize();
    c.addListener(_changes.ping);
    return c.value.duration;
  }

  @override
  Future<void> play() => _c!.play();

  @override
  Future<void> pause() => _c!.pause();

  @override
  Future<void> seekTo(Duration to) => _c!.seekTo(to);

  @override
  Future<void> setSpeed(double speed) => _c!.setPlaybackSpeed(speed);

  @override
  Duration get position => _c?.value.position ?? Duration.zero;

  @override
  bool get isPlaying => _c?.value.isPlaying ?? false;

  @override
  Listenable get changes => _changes;

  @override
  double get aspect => _c?.value.aspectRatio ?? 16 / 9;

  @override
  Widget view() => _c == null ? const SizedBox.shrink() : vp.VideoPlayer(_c!);

  @override
  Future<void> dispose() async {
    await _c?.dispose();
    _c = null;
    _changes.dispose();
  }
}

class _Ping extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// The speeds the video's speed button steps through (Video.dc.html).
const videoSpeeds = [1.0, 0.5, 0.25, 2.0];

@immutable
class VideoPlayState {
  const VideoPlayState({
    required this.notebookId,
    required this.itemId,
    required this.positionMs,
    required this.playing,
    required this.speed,
    this.loading = false,
  });

  final String notebookId;
  final String itemId;
  final int positionMs;
  final bool playing;
  final double speed;

  /// Its file is being opened.
  final bool loading;

  bool isOf(String notebookId, String itemId) => this.notebookId == notebookId && this.itemId == itemId;

  VideoPlayState copyWith({int? positionMs, bool? playing, double? speed, bool? loading}) => VideoPlayState(
        notebookId: notebookId,
        itemId: itemId,
        positionMs: positionMs ?? this.positionMs,
        playing: playing ?? this.playing,
        speed: speed ?? this.speed,
        loading: loading ?? this.loading,
      );
}

final videoPlaybackProvider = NotifierProvider<VideoPlayback, VideoPlayState?>(VideoPlayback.new);

class VideoPlayback extends Notifier<VideoPlayState?> {
  VideoHandle? _handle;
  VideoSource? _source;
  int _from = 0;
  int _to = 0;

  /// Each video plays at the speed it was last set to.
  final _speeds = <String, double>{};

  @override
  VideoPlayState? build() {
    ref.onDispose(() => unawaited(_close()));
    return null;
  }

  /// The player of the video loaded, for its picture.
  VideoHandle? get handle => _handle;

  Future<void> _close() async {
    final h = _handle;
    _handle = null;
    releaseVideoSource(ref, _source);
    _source = null;
    await h?.dispose();
  }

  /// [v]'s file, to read frames from: the one playing, or found now.
  Future<VideoSource?> sourceFor(String notebookId, VideoItem v) async {
    if (state?.isOf(notebookId, v.id) ?? false) return _source;
    return videoSourceOf(ref, ref.read(notebookProvider(notebookId).notifier), v);
  }

  /// Makes [v] the video loaded. False if its file can't be opened.
  Future<bool> _ensure(String notebookId, VideoItem v) async {
    _from = v.from;
    _to = v.to;
    if ((state?.isOf(notebookId, v.id) ?? false) && _handle != null) return true;
    await _close();
    final speed = _speeds[v.id] ?? 1.0;
    state = VideoPlayState(notebookId: notebookId, itemId: v.id, positionMs: _from, playing: false, speed: speed, loading: true);
    final source = await videoSourceOf(ref, ref.read(notebookProvider(notebookId).notifier), v);
    if (source == null || !ref.mounted) {
      if (ref.mounted) state = null;
      return false;
    }
    final handle = ref.read(videoHandleProvider)();
    try {
      await handle.open(source.source);
    } on Object {
      await handle.dispose();
      releaseVideoSource(ref, source);
      if (ref.mounted) state = null;
      return false;
    }
    if (!ref.mounted || !(state?.isOf(notebookId, v.id) ?? false)) {
      await handle.dispose();
      releaseVideoSource(ref, source);
      return false;
    }
    _handle = handle;
    _source = source;
    if (speed != 1) await handle.setSpeed(speed);
    if (_from > 0) await handle.seekTo(Duration(milliseconds: _from));
    handle.changes.addListener(() => _changed(handle));
    state = state!.copyWith(loading: false, positionMs: _from);
    return true;
  }

  void _changed(VideoHandle h) {
    final s = state;
    if (s == null || h != _handle || !ref.mounted) return;
    var ms = h.position.inMilliseconds;
    if (h.isPlaying && ms >= _to) {
      // The end of the trim: back to its start, paused.
      unawaited(h.pause());
      unawaited(h.seekTo(Duration(milliseconds: _from)));
      state = s.copyWith(playing: false, positionMs: _from);
      return;
    }
    ms = ms.clamp(_from, _to);
    if (ms != s.positionMs || h.isPlaying != s.playing) state = s.copyWith(positionMs: ms, playing: h.isPlaying);
  }

  /// Plays or pauses [v].
  Future<bool> toggle(String notebookId, VideoItem v) async {
    if (!await _ensure(notebookId, v)) return false;
    final h = _handle!;
    if (h.isPlaying) {
      await h.pause();
      state = state!.copyWith(playing: false);
    } else {
      await ref.read(playbackProvider.notifier).pause();
      if (state!.positionMs >= _to - 50) await h.seekTo(Duration(milliseconds: _from));
      await h.play();
      state = state!.copyWith(playing: true);
    }
    return true;
  }

  /// Goes to [ms] in [v] (within its trim), playing unless [play] is false.
  Future<bool> seek(String notebookId, VideoItem v, int ms, {bool play = true}) async {
    if (!await _ensure(notebookId, v)) return false;
    final h = _handle!;
    final to = ms.clamp(_from, _to);
    await h.seekTo(Duration(milliseconds: to));
    state = state!.copyWith(positionMs: to);
    if (play && !h.isPlaying) {
      await ref.read(playbackProvider.notifier).pause();
      await h.play();
      state = state!.copyWith(playing: true);
    }
    return true;
  }

  /// The next speed for [itemId].
  Future<double> nextSpeed(String itemId) async {
    final now = speedOf(itemId);
    final next = videoSpeeds[(videoSpeeds.indexOf(now) + 1) % videoSpeeds.length];
    _speeds[itemId] = next;
    if (state?.itemId == itemId) {
      await _handle?.setSpeed(next);
      state = state!.copyWith(speed: next);
    }
    return next;
  }

  double speedOf(String itemId) => state?.itemId == itemId ? state!.speed : (_speeds[itemId] ?? 1.0);

  /// The trim changed (or the file): it plays within the new one.
  void trimmed(VideoItem v) {
    if (state?.itemId != v.id) return;
    _from = v.from;
    _to = v.to;
    final s = state!;
    if (s.positionMs < _from || s.positionMs > _to) unawaited(seek(s.notebookId, v, _from, play: false));
  }

  Future<void> pause() async {
    if (state?.playing ?? false) {
      await _handle?.pause();
      state = state!.copyWith(playing: false);
    }
  }

  /// Stops if what's playing is from [notebookId] (it was closed).
  void stopFor(String notebookId) {
    if (state?.notebookId == notebookId) unawaited(stop());
  }

  Future<void> stop() async {
    state = null;
    await _close();
  }
}
