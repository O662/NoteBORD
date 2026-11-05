import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'platform_audio.dart';

// Playing a recording (Audio.png): one at a time, with its speed, ±10 s,
// and where it is, which the card, the transcript and the ink follow.

/// The speeds the card's speed button steps through.
const playbackSpeeds = [1.0, 1.25, 1.5, 2.0, 0.75];

String speedLabel(double speed) {
  final s = speed == speed.roundToDouble() ? speed.toStringAsFixed(0) : '$speed'.replaceFirst(RegExp(r'0+$'), '');
  return '$s×';
}

@immutable
class PlaybackState {
  const PlaybackState({
    required this.notebookId,
    required this.itemId,
    required this.positionMs,
    required this.durationMs,
    required this.playing,
    required this.speed,
  });

  final String notebookId;

  /// The recording's item id.
  final String itemId;
  final int positionMs;
  final int durationMs;
  final bool playing;
  final double speed;

  bool isOf(String notebookId, String itemId) => this.notebookId == notebookId && this.itemId == itemId;

  PlaybackState copyWith({int? positionMs, int? durationMs, bool? playing, double? speed}) => PlaybackState(
        notebookId: notebookId,
        itemId: itemId,
        positionMs: positionMs ?? this.positionMs,
        durationMs: durationMs ?? this.durationMs,
        playing: playing ?? this.playing,
        speed: speed ?? this.speed,
      );
}

final playbackProvider = NotifierProvider<PlaybackController, PlaybackState?>(PlaybackController.new);

class PlaybackController extends Notifier<PlaybackState?> {
  AudioPlayer? _player;
  final _subs = <StreamSubscription<Object?>>[];

  /// Each recording plays at the speed it was last set to.
  final _speeds = <String, double>{};

  @override
  PlaybackState? build() {
    ref.onDispose(_close);
    return null;
  }

  Future<void> _close() async {
    final subs = [..._subs];
    _subs.clear();
    final p = _player;
    _player = null;
    for (final s in subs) {
      await s.cancel();
    }
    await p?.close();
  }

  /// Makes [itemId] the recording loaded, from [load] (its bytes and file
  /// extension) unless it already is. Returns false if it couldn't be read.
  Future<bool> _ensure(String notebookId, String itemId, int durationMs, Future<(Uint8List, String)?> Function() load) async {
    if (state?.isOf(notebookId, itemId) ?? false) return true;
    await _close();
    final got = await load();
    if (got == null || !ref.mounted) return false;
    final player = ref.read(audioPlayerProvider)();
    final Duration? length;
    try {
      length = await player.open(got.$1, got.$2);
    } on Object {
      // Not a file it can play, or no player on this device.
      await player.close();
      return false;
    }
    if (!ref.mounted) {
      await player.close();
      return false;
    }
    _player = player;
    final speed = _speeds[itemId] ?? 1.0;
    if (speed != 1) await player.setSpeed(speed);
    state = PlaybackState(
      notebookId: notebookId,
      itemId: itemId,
      positionMs: 0,
      durationMs: length?.inMilliseconds ?? durationMs,
      playing: false,
      speed: speed,
    );
    _subs
      ..add(player.position.listen((d) {
        final s = state;
        if (s != null && _player == player) state = s.copyWith(positionMs: d.inMilliseconds.clamp(0, s.durationMs));
      }))
      ..add(player.playing.listen((on) {
        final s = state;
        if (s != null && _player == player && s.playing != on) state = s.copyWith(playing: on);
      }))
      ..add(player.ended.listen((_) async {
        final s = state;
        if (s == null || _player != player) return;
        // Back to the start, ready to play again.
        await player.pause();
        await player.seek(Duration.zero);
        state = s.copyWith(playing: false, positionMs: 0);
      }));
    return true;
  }

  /// Plays or pauses recording [itemId].
  Future<bool> toggle(String notebookId, String itemId, int durationMs, Future<(Uint8List, String)?> Function() load) async {
    if (!await _ensure(notebookId, itemId, durationMs, load)) return false;
    final s = state!;
    if (s.playing) {
      await _player!.pause();
      state = state!.copyWith(playing: false);
    } else {
      await _player!.play();
      state = state!.copyWith(playing: true);
    }
    return true;
  }

  /// Goes to [ms] in recording [itemId] and plays from there (or stays
  /// paused when [play] is false).
  Future<bool> seek(String notebookId, String itemId, int durationMs, int ms, Future<(Uint8List, String)?> Function() load,
      {bool play = true}) async {
    if (!await _ensure(notebookId, itemId, durationMs, load)) return false;
    final to = ms.clamp(0, state!.durationMs);
    await _player!.seek(Duration(milliseconds: to));
    state = state!.copyWith(positionMs: to);
    if (play && !state!.playing) {
      await _player!.play();
      state = state!.copyWith(playing: true);
    }
    return true;
  }

  /// Back or on [deltaMs] in the recording loaded.
  Future<void> skip(int deltaMs) async {
    final s = state;
    if (s == null || _player == null) return;
    final to = (s.positionMs + deltaMs).clamp(0, s.durationMs);
    await _player!.seek(Duration(milliseconds: to));
    state = s.copyWith(positionMs: to);
  }

  /// The next speed for recording [itemId] (it needn't be playing).
  Future<double> nextSpeed(String itemId) async {
    final now = state?.itemId == itemId ? state!.speed : (_speeds[itemId] ?? 1.0);
    final i = playbackSpeeds.indexOf(now);
    final next = playbackSpeeds[(i + 1) % playbackSpeeds.length];
    _speeds[itemId] = next;
    if (state?.itemId == itemId) {
      await _player?.setSpeed(next);
      state = state!.copyWith(speed: next);
    }
    return next;
  }

  double speedOf(String itemId) => state?.itemId == itemId ? state!.speed : (_speeds[itemId] ?? 1.0);

  Future<void> pause() async {
    if (state?.playing ?? false) {
      await _player?.pause();
      state = state!.copyWith(playing: false);
    }
  }

  /// Stops if what's playing is from [notebookId] (it was closed).
  void stopFor(String notebookId) {
    if (state?.notebookId == notebookId) unawaited(stop());
  }

  /// Stops and lets go of the recording (its card was removed, or its
  /// notebook closed).
  Future<void> stop() async {
    state = null;
    await _close();
  }
}
