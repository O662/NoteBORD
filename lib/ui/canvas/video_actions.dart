import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../audio/transcript_lines.dart' show clockOf;
import '../../audio/transcription.dart';
import '../../board/ids.dart';
import '../../board/model.dart';
import '../../canvas/pane.dart';
import '../../canvas/video_card.dart';
import '../../state/notebook.dart';
import '../../state/settings.dart';
import '../../transfer/files.dart';
import '../../video/media_server.dart';
import '../../video/video_files.dart';
import '../../video/video_playback.dart';
import '../../video/video_tools.dart';
import '../dialogs.dart';
import 'trim_dialog.dart';

// Videos on the page (Video.png): putting one on the page (in the notebook,
// or, when big, kept on the tablet with a link), Note at, Grab frame, Trim,
// Replace and Transcribe.

/// A video's file stored for a page: where it went, what it is, a still.
class _Stored {
  const _Stored({this.asset, this.link, required this.info, this.preview});

  final String? asset;
  final String? link;
  final VideoInfo info;
  final String? preview;
}

class _NotStored implements Exception {
  const _NotStored(this.message);

  final String message;
}

/// Stores [picked] for [pageId]: up to [bigVideo] in the notebook (sealed
/// on a page with a password), bigger on the tablet with a link (not on a
/// page with a password: up to [biggestSealedVideo] is sealed there).
Future<_Stored> _store(WidgetRef ref, Pane pane, String pageId, PickedVideo picked) async {
  final nb = ref.read(notebookProvider(pane.notebookId).notifier);
  final size = await picked.length() ?? 0;
  final sealed = nb.isProtected(pageId);
  var ext = p.extension(picked.name).toLowerCase().replaceFirst('.', '');
  if (ext.isEmpty || ext.length > 5) ext = 'mp4';
  if (sealed && size > biggestSealedVideo) {
    throw const _NotStored('Videos over 200 MB can’t go on a page with a password yet.');
  }
  String? asset, link;
  String source;
  String? served;
  if (!sealed && size > bigVideo) {
    // Big: kept on the tablet, beside the notebooks; the page has a link.
    final dir = await ref.read(videosDirProvider)();
    link = '${newId('vid')}.$ext';
    final file = File(p.join(dir.path, link));
    final part = File('${file.path}.part');
    final sink = part.openWrite();
    await sink.addStream(picked.read());
    await sink.close();
    await part.rename(file.path);
    source = file.path;
  } else {
    final bytes = await picked.readAll();
    asset = await nb.storeMedia(pageId, bytes, ext);
    if (asset == null) throw const _NotStored('This page is locked.');
    source = await nb.assetPath(asset) ?? (served = await ref.read(mediaServerProvider).serve(bytes, videoMime(asset)));
  }
  final tools = ref.read(videoToolsProvider);
  try {
    final info = await tools.info(source) ?? const VideoInfo(durationMs: 0, width: 16, height: 9);
    final still = await tools.frame(source, math.min(1000, info.durationMs ~/ 10), maxWidth: 1280);
    final preview = still == null ? null : await nb.storeMedia(pageId, still, 'jpg');
    return _Stored(asset: asset, link: link, info: info, preview: preview);
  } finally {
    if (served != null) ref.read(mediaServerProvider).release(served);
  }
}

/// Insert → Video: picks a video and puts its card on the page.
Future<void> insertVideo(BuildContext context, WidgetRef ref, Pane pane) async {
  final nb = ref.read(notebookProvider(pane.notebookId));
  final page = nb.pageAt(pane.page);
  if (nb.isSealed(page.id)) return;
  final picked = await ref.read(fileTransferProvider).pickVideo();
  if (picked == null) return;
  pane.showStatus('Adding “${picked.name}”…');
  try {
    final stored = await _store(ref, pane, page.id, picked);
    pane.showStatus(null);
    final now = DateTime.now().toUtc();
    pane.video.place(VideoItem(
      id: newId('it', now: now),
      x: 0,
      y: 0,
      z: page.nextZ,
      createdAt: now,
      asset: stored.asset,
      link: stored.link,
      name: picked.name,
      durationMs: stored.info.durationMs,
      videoW: math.max(1, stored.info.width).toDouble(),
      videoH: math.max(1, stored.info.height).toDouble(),
      preview: stored.preview,
      sound: stored.info.sound,
    ));
  } on _NotStored catch (e) {
    pane.showStatus(null);
    if (context.mounted) await showMessage(context, title: 'Can’t add this video', message: e.message);
  } on FileSystemException catch (e) {
    pane.showStatus(null);
    if (context.mounted) await showMessage(context, title: 'Can’t add this video', message: 'It couldn’t be read (${e.message}).');
  }
}

/// Replace: another video in the same card, its pinned notes kept (the
/// trim and the transcript go with the old video). One undo step.
Future<void> replaceVideo(BuildContext context, WidgetRef ref, Pane pane, VideoItem v) async {
  final nb = ref.read(notebookProvider(pane.notebookId).notifier);
  final found = nb.videoClip(v.id);
  if (found == null) return;
  final picked = await ref.read(fileTransferProvider).pickVideo();
  if (picked == null) return;
  pane.showStatus('Adding “${picked.name}”…');
  try {
    final stored = await _store(ref, pane, found.$1, picked);
    pane.showStatus(null);
    final now = nb.videoClip(v.id);
    if (now == null) return;
    await ref.read(videoPlaybackProvider.notifier).stop();
    ref.read(transcriptionProvider.notifier).cancel(v.id);
    nb.replaceItems(now.$1, [
      now.$2.copyWith(
        asset: () => stored.asset,
        link: () => stored.link,
        name: picked.name,
        durationMs: stored.info.durationMs,
        videoW: math.max(1, stored.info.width).toDouble(),
        videoH: math.max(1, stored.info.height).toDouble(),
        preview: () => stored.preview,
        sound: stored.info.sound,
        trimFrom: () => null,
        trimTo: () => null,
        transcript: const [],
        speakers: const {},
        language: () => null,
        state: TranscriptState.none,
        upToMs: 0,
      ),
    ]);
    pane.toast('Replaced the video · its notes stay pinned', undoPageId: now.$1);
  } on _NotStored catch (e) {
    pane.showStatus(null);
    if (context.mounted) await showMessage(context, title: 'Can’t use this video', message: e.message);
  }
}

/// Where [v] is playing now (or its start).
int _now(WidgetRef ref, String notebookId, VideoItem v) {
  final s = ref.read(videoPlaybackProvider);
  return s != null && s.isOf(notebookId, v.id) ? s.positionMs : v.from;
}

/// The pin chips of [v] on [page].
List<VideoPinItem> pinsOf(Iterable<Item> page, String videoId) => [
      for (final i in page)
        if (i is VideoPinItem && i.video == videoId) i,
    ];

/// "Note at 0:18": a "▶ 0:18" chip in the column beside the video, under
/// the last one, to write the note beside (one undo step).
void pinNote(WidgetRef ref, Pane pane, VideoItem v) {
  final nb = ref.read(notebookProvider(pane.notebookId).notifier);
  final found = nb.videoClip(v.id);
  if (found == null) return;
  final (pageId, video) = found;
  final page = ref.read(notebookProvider(pane.notebookId)).pages.firstWhere((p) => p.id == pageId);
  final ms = (_now(ref, pane.notebookId, video) ~/ 1000) * 1000;
  final chips = pinsOf(page.items, video.id);
  if (chips.any((c) => (c.tMs ~/ 1000) == ms ~/ 1000)) {
    pane.toast('There’s a note at ${clockOf(ms)} already');
    return;
  }
  final k = video.unit;
  final size = videoPinSize(ms) * k;
  final box = video.extent;
  final below = chips.isEmpty ? box.top + 24 * k : chips.map((c) => c.extent.bottom).reduce(math.max) + 14 * k;
  final now = DateTime.now().toUtc();
  final chip = VideoPinItem(
    id: newId('it', now: now),
    x: box.right + 40 * k,
    y: below,
    z: page.nextZ,
    createdAt: now,
    w: size.width,
    h: size.height,
    video: video.id,
    tMs: ms,
  );
  nb.insertItems(pageId, [chip]);
  // Ready to write the note beside it.
  ref.read(settingsProvider.notifier).apply((s) => s.copyWith(tool: CanvasTool.pen));
  pane.toast('Pinned a note to ${clockOf(ms)} · write it beside the chip', undoPageId: pageId);
}

/// Grab frame: the picture at this moment, on the page beside the video as
/// "Grabbed frame · from video" (one undo step).
Future<void> grabFrame(WidgetRef ref, Pane pane, VideoItem v) async {
  final nb = ref.read(notebookProvider(pane.notebookId).notifier);
  final found = nb.videoClip(v.id);
  if (found == null) return;
  final (pageId, video) = found;
  final playback = ref.read(videoPlaybackProvider.notifier);
  final ms = _now(ref, pane.notebookId, video);
  final loaded = ref.read(videoPlaybackProvider)?.isOf(pane.notebookId, video.id) ?? false;
  final source = await playback.sourceFor(pane.notebookId, video);
  if (source == null) {
    pane.toast('This video can’t be read here');
    return;
  }
  Uint8List? frame;
  try {
    frame = await ref.read(videoToolsProvider).frame(source.source, ms, maxWidth: 1280);
  } finally {
    if (!loaded && source.served) ref.read(mediaServerProvider).release(source.source);
  }
  if (frame == null) {
    pane.toast('The frame couldn’t be read');
    return;
  }
  final asset = await nb.storeMedia(pageId, frame, 'jpg');
  if (asset == null) return;
  final page = ref.read(notebookProvider(pane.notebookId)).pages.firstWhere((p) => p.id == pageId);
  final k = video.unit;
  final w = 200 * k, h = w * video.videoH / video.videoW;
  final box = video.extent;
  // Beside the video, at its bottom; under anything already there.
  var at = Rect.fromLTWH(box.right + 40 * k, box.bottom - h - 26 * k, w, h);
  for (var tries = 0; tries < 20; tries++) {
    final hit = page.items.where((i) => i.bounds.overlaps(at.inflate(8 * k))).map((i) => i.bounds.bottom).fold<double?>(null, (a, b) => a == null ? b : math.max(a, b));
    if (hit == null) break;
    at = at.translate(0, hit + 40 * k - at.top);
  }
  final now = DateTime.now().toUtc();
  nb.insertItems(pageId, [
    ImageItem(
      id: newId('it', now: now),
      x: at.left,
      y: at.top,
      z: page.nextZ,
      createdAt: now,
      w: w,
      h: h,
      asset: asset,
      extra: const {'caption': 'Grabbed frame · from video'},
    ),
  ]);
  pane.toast('Grabbed the frame at ${clockOf(ms)}', undoPageId: pageId);
}

/// Transcribe: makes the video's transcript (as for recordings) and opens
/// its panel.
void transcribeVideo(WidgetRef ref, Pane pane, VideoItem v) {
  if (!v.sound) {
    pane.toast('This video has no sound to transcribe');
    return;
  }
  if (v.state == TranscriptState.none || v.state == TranscriptState.failed) {
    ref.read(notebookProvider(pane.notebookId).notifier).setTranscript(v.withTranscript(state: TranscriptState.waiting));
    ref.read(transcriptionProvider.notifier).add(pane.notebookId, v.id);
  }
  pane.audio.showTranscript(v.id);
}

/// Trim: where the video starts and stops playing (the file isn't cut).
/// One undo step.
Future<void> trimVideo(BuildContext context, WidgetRef ref, Pane pane, VideoItem v) async {
  final playback = ref.read(videoPlaybackProvider.notifier);
  await playback.pause();
  final source = await playback.sourceFor(pane.notebookId, v);
  final loaded = ref.read(videoPlaybackProvider)?.isOf(pane.notebookId, v.id) ?? false;
  final tools = ref.read(videoToolsProvider);
  if (!context.mounted) return;
  final range = await showTrimDialog(
    context,
    durationMs: v.durationMs,
    from: v.from,
    to: v.to,
    strip: source == null ? null : () => tools.strip(source.source, fromMs: 0, toMs: v.durationMs),
    frame: source == null ? null : (ms) => tools.frame(source.source, ms, maxWidth: 640),
  );
  if (!loaded && source != null && source.served) ref.read(mediaServerProvider).release(source.source);
  if (range == null) return;
  final nb = ref.read(notebookProvider(pane.notebookId).notifier);
  final found = nb.videoClip(v.id);
  if (found == null) return;
  final (from, to) = range;
  final updated = found.$2.copyWith(
    trimFrom: () => from <= 0 ? null : from,
    trimTo: () => to >= v.durationMs ? null : to,
  );
  if (updated.from == found.$2.from && updated.to == found.$2.to) return;
  nb.replaceItems(found.$1, [updated]);
  playback.trimmed(updated);
  pane.toast(
    updated.trimmed ? 'Plays ${clockOf(updated.from)}–${clockOf(updated.to)}' : 'Plays the whole video',
    undoPageId: found.$1,
  );
}
