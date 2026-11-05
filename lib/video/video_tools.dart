import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What a video is: its length and shape, and whether it has sound.
class VideoInfo {
  const VideoInfo({required this.durationMs, required this.width, required this.height, this.sound = true});

  final int durationMs;
  final int width;
  final int height;
  final bool sound;
}

/// Reading videos (Android's MediaMetadataRetriever, VideoTools.kt), behind
/// an interface so tests can stand in. [source] is a file path or an
/// http://127.0.0.1 address (lib/video/media_server.dart).
abstract interface class VideoTools {
  Future<VideoInfo?> info(String source);

  /// The frame at [ms], as a JPEG.
  Future<Uint8List?> frame(String source, int ms, {int maxWidth = 1280});

  /// [count] small frames evenly from [fromMs] to [toMs] (the Trim strip).
  Future<List<Uint8List>> strip(String source, {int count = 8, int maxWidth = 160, required int fromMs, required int toMs});
}

final videoToolsProvider = Provider<VideoTools>((ref) => const PlatformVideoTools());

class PlatformVideoTools implements VideoTools {
  const PlatformVideoTools();

  static const _channel = MethodChannel('endless/video');

  @override
  Future<VideoInfo?> info(String source) async {
    if (!Platform.isAndroid) return null;
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('info', {'source': source});
      if (m == null) return null;
      return VideoInfo(
        durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
        width: (m['width'] as num?)?.toInt() ?? 0,
        height: (m['height'] as num?)?.toInt() ?? 0,
        sound: m['audio'] != false,
      );
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<Uint8List?> frame(String source, int ms, {int maxWidth = 1280}) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<Uint8List>('frame', {'source': source, 'ms': ms, 'maxWidth': maxWidth});
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<List<Uint8List>> strip(String source, {int count = 8, int maxWidth = 160, required int fromMs, required int toMs}) async {
    if (!Platform.isAndroid) return const [];
    try {
      final list = await _channel.invokeListMethod<Uint8List>(
        'strip',
        {'source': source, 'count': count, 'maxWidth': maxWidth, 'fromMs': fromMs, 'toMs': toMs},
      );
      return list ?? const [];
    } on PlatformException {
      return const [];
    }
  }
}
