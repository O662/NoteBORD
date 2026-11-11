import 'dart:async';
import 'dart:io' show ProcessInfo;

import 'package:flutter/scheduler.dart';

int _lastRss = 0;

/// What the app did lately (see [startStallWatch]).
final _steps = <(DateTime, String)>[];

/// Notes a step, for the stall log.
void diagStep(String step) {
  if (!kDiag) return;
  _steps.add((DateTime.now(), step));
  if (_steps.length > 40) _steps.removeAt(0);
}

/// Times [run], a step that runs on this thread, and notes how long it took.
T diagTime<T>(String step, T Function() run) {
  if (!kDiag) return run();
  final sw = Stopwatch()..start();
  try {
    return run();
  } finally {
    diagStep('$step ${sw.elapsedMilliseconds}ms');
  }
}

/// Times [run], which waits on other work too (only the total is known).
Future<T> diagTimeAsync<T>(String step, Future<T> Function() run) async {
  if (!kDiag) return run();
  final sw = Stopwatch()..start();
  diagStep('$step…');
  try {
    return await run();
  } finally {
    diagStep('$step done ${sw.elapsedMilliseconds}ms');
  }
}

/// Logs when this thread is blocked for over 150 ms, with the steps just
/// before it.
void startStallWatch() {
  if (!kDiag) return;
  var last = DateTime.now();
  Timer.periodic(const Duration(milliseconds: 20), (_) {
    final now = DateTime.now();
    final gap = now.difference(last).inMilliseconds;
    last = now;
    if (gap < 150) return;
    final recent = [
      for (final (at, step) in _steps)
        if (now.difference(at).inMilliseconds < gap + 2000) '-${now.difference(at).inMilliseconds}ms $step',
    ];
    // Memory now and at the last stall: a big drop with no step before
    // the stall points at the garbage collector.
    final rss = ProcessInfo.currentRss ~/ (1024 * 1024);
    diag('STALL ${gap}ms rss ${rss}MB (was ${_lastRss}MB) | ${recent.join(' | ')}');
    _lastRss = rss;
  });
}

/// On-device diagnostics, for chasing pen lag and touch handling on the
/// tablet. Off unless built with `--dart-define=ENDLESS_DIAG=true`; then
/// lines tagged `ENDLESS_DIAG` go to the device log (`adb logcat -s flutter`).
/// Normal builds compile all of it away.
const kDiag = bool.fromEnvironment('ENDLESS_DIAG');

// ignore: avoid_print
void diag(String message) => kDiag ? print('ENDLESS_DIAG $message') : null;

/// Pen samples that reached the canvas this second, and how long each
/// waited for the frame that drew it.
int _penSamples = 0;
Duration? _lastPenSample;
final _waits = <double>[];

/// A pen move reached the canvas (its time is the device's input time).
void diagPenSample(Duration timeStamp) {
  if (!kDiag) return;
  _penSamples++;
  _lastPenSample = timeStamp;
}

/// Starts the once-a-second frame summary.
void startFrameDiag() {
  if (!kDiag) return;
  SchedulerBinding.instance.addPersistentFrameCallback((_) {
    final sample = _lastPenSample;
    if (sample == null) return;
    _lastPenSample = null;
    final vsync = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    _waits.add((vsync - sample).inMicroseconds / 1000);
  });
  final frames = <FrameTiming>[];
  var since = DateTime.now();
  SchedulerBinding.instance.addTimingsCallback((timings) {
    frames.addAll(timings);
    final now = DateTime.now();
    if (now.difference(since) < const Duration(seconds: 1)) return;
    since = now;
    if (frames.isEmpty) return;
    double ms(Duration d) => d.inMicroseconds / 1000;
    final build = [for (final f in frames) ms(f.buildDuration)]..sort();
    final raster = [for (final f in frames) ms(f.rasterDuration)]..sort();
    final total = [for (final f in frames) ms(f.totalSpan)]..sort();
    String stats(List<double> v) =>
        'avg ${(v.reduce((a, b) => a + b) / v.length).toStringAsFixed(1)} max ${v.last.toStringAsFixed(1)}';
    final waits = [..._waits]..sort();
    diag('frames ${frames.length}/s  build ${stats(build)}  raster ${stats(raster)}  total ${stats(total)}'
        '  penSamples $_penSamples'
        '${waits.isEmpty ? '' : '  penToVsync ${stats(waits)}'}');
    frames.clear();
    _waits.clear();
    _penSamples = 0;
  });
}
