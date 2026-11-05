import 'dart:io';
import 'dart:typed_data';

import 'package:endless/video/media_server.dart';
import 'package:endless/video/video_files.dart';
import 'package:endless/video/video_playback.dart';
import 'package:endless/video/video_tools.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../helpers.dart';

// Stand-ins for the video player and Android's frame reader.

class FakeVideoTools implements VideoTools {
  FakeVideoTools({this.durationMs = 65000, this.width = 1920, this.height = 1080, this.sound = true, this.png});

  final int durationMs;
  final int width;
  final int height;
  final bool sound;

  /// A real PNG for frames (widgets decode them); else stand-in bytes.
  final Uint8List? png;
  final sources = <String>[];
  final frames = <int>[];

  @override
  Future<VideoInfo?> info(String source) async {
    sources.add(source);
    return VideoInfo(durationMs: durationMs, width: width, height: height, sound: sound);
  }

  @override
  Future<Uint8List?> frame(String source, int ms, {int maxWidth = 1280}) async {
    frames.add(ms);
    return png ?? fakePng(ms % 7 + 1);
  }

  @override
  Future<List<Uint8List>> strip(String source, {int count = 8, int maxWidth = 160, required int fromMs, required int toMs}) async =>
      [for (var i = 0; i < count; i++) png ?? fakePng(i + 1)];
}

class _Ping extends ChangeNotifier {
  void ping() => notifyListeners();
}

class FakeVideoHandle implements VideoHandle {
  FakeVideoHandle(this.durationMs);

  final int durationMs;
  String? opened;
  Duration _position = Duration.zero;
  bool _playing = false;
  final speeds = <double>[];
  final seeks = <int>[];
  bool disposed = false;
  final _changes = _Ping();

  void notifyListeners() => _changes.ping();

  @override
  Future<Duration> open(String source) async {
    opened = source;
    return Duration(milliseconds: durationMs);
  }

  @override
  Future<void> play() async {
    _playing = true;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    _playing = false;
    notifyListeners();
  }

  @override
  Future<void> seekTo(Duration to) async {
    seeks.add(to.inMilliseconds);
    _position = to;
    notifyListeners();
  }

  @override
  Future<void> setSpeed(double speed) async => speeds.add(speed);

  /// As if it had played to [ms].
  void reach(int ms) {
    _position = Duration(milliseconds: ms);
    notifyListeners();
  }

  @override
  Duration get position => _position;

  @override
  bool get isPlaying => _playing;

  @override
  Listenable get changes => _changes;

  @override
  double get aspect => 16 / 9;

  @override
  Widget view() => const ColoredBox(color: Color(0xFF3A6EA5));

  @override
  Future<void> dispose() async => disposed = true;
}

List<Override> videoOverrides({
  required Directory dir,
  required FakeVideoTools tools,
  required List<FakeVideoHandle> handles,
  int durationMs = 65000,
}) =>
    [
      videoToolsProvider.overrideWithValue(tools),
      videoHandleProvider.overrideWithValue(() {
        final h = FakeVideoHandle(durationMs);
        handles.add(h);
        return h;
      }),
      videosDirProvider.overrideWithValue(() async => Directory('${dir.path}/videos')..createSync(recursive: true)),
      mediaServerProvider.overrideWithValue(FakeMediaServer()),
    ];

/// Serves nothing: hands out addresses (the fake player and tools take any).
class FakeMediaServer extends MediaServer {
  final served = <String>[];
  final released = <String>[];

  @override
  Future<String> serve(Uint8List bytes, String type) async {
    final url = 'http://127.0.0.1:1/${served.length}';
    served.add(url);
    return url;
  }

  @override
  void release(String url) => released.add(url);

  @override
  Future<void> close() async {}
}
