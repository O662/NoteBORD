import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../board/model.dart';
import '../state/notebook.dart';
import '../sync/sync_state.dart';
import 'media_server.dart';

// Where a video's file is (Phase 8b). Up to [bigVideo] it's in the
// notebook's assets, like a picture (sealed on a page with a password);
// bigger, it stays on the tablet in Endless's own videos folder and the page
// keeps a link (`link`), until Phase 9 moves big videos to Google Drive.

/// Videos bigger than this stay on the tablet, with a link on the page.
const bigVideo = 100 * 1000 * 1000;

/// A page with a password seals its videos, which are opened in memory to
/// play: no bigger than this.
const biggestSealedVideo = 200 * 1000 * 1000;

/// The tablet's own videos folder (not part of any notebook's package).
final videosDirProvider = Provider<Future<Directory> Function()>((ref) => () async {
      final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'videos'));
      await dir.create(recursive: true);
      return dir;
    });

/// What a video file's extension says it is.
String videoMime(String name) => switch (p.extension(name).toLowerCase()) {
      '.mov' => 'video/quicktime',
      '.webm' => 'video/webm',
      '.mkv' => 'video/x-matroska',
      '.3gp' => 'video/3gpp',
      _ => 'video/mp4',
    };

/// A video's file to play or read: a path, or an address the media server
/// serves it from (sealed, or a store without files). [release] lets go of
/// a served one.
class VideoSource {
  const VideoSource(this.source, {this.served = false});

  final String source;
  final bool served;

  bool get isFile => !served;
}

/// Finds [v]'s file in [nb]: the linked file, the asset's file, or the
/// asset opened (with the key held) and served from memory. Null when it's
/// missing or locked.
Future<VideoSource?> videoSourceOf(Ref ref, NotebookNotifier nb, VideoItem v) async {
  if (v.link case final link?) {
    final f = File(p.join((await ref.read(videosDirProvider)()).path, link));
    if (await f.exists()) return VideoSource(f.path);
    if (v.cloud == null) return null;
    // Moved to the cloud: the copy fetched before, else played from there.
    final sync = ref.read(syncProvider.notifier);
    final cached = await sync.cachedVideo(link);
    if (await cached.exists()) return VideoSource(cached.path);
    final stream = await sync.streamVideo(v);
    if (stream == null) return null;
    final (uri, headers) = stream;
    if (uri.scheme == 'file') return VideoSource(uri.toFilePath());
    return VideoSource(await ref.read(mediaServerProvider).proxy(uri, headers, videoMime(link)), served: true);
  }
  final asset = v.asset!;
  final path = await nb.assetPath(asset);
  if (path != null) return VideoSource(path);
  final bytes = await nb.readAsset(asset);
  if (bytes == null) return null;
  return VideoSource(await ref.read(mediaServerProvider).serve(bytes, videoMime(asset)), served: true);
}

/// A big video's file on this device, fetched from the cloud first if it
/// was moved there (to grab frames, trim or transcribe); null if it can't
/// be had.
Future<File?> videoFileOf(Ref ref, VideoItem v, {void Function(double)? progress}) async {
  final link = v.link;
  if (link == null) return null;
  final f = File(p.join((await ref.read(videosDirProvider)()).path, link));
  if (await f.exists()) return f;
  try {
    return await ref.read(syncProvider.notifier).fetchVideo(v, progress: progress);
  } on Object {
    return null;
  }
}

/// Lets go of a served [source].
void releaseVideoSource(Ref ref, VideoSource? source) {
  if (source != null && source.served) ref.read(mediaServerProvider).release(source.source);
}
