import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../audio/playback.dart';
import '../../audio/recording.dart';
import '../../audio/transcript_lines.dart';
import '../../audio/transcription.dart';
import '../../board/ids.dart';
import '../../board/model.dart';
import '../../canvas/pane.dart';
import '../../library/library.dart' show libraryProvider;
import '../../state/notebook.dart';
import '../../transfer/files.dart';
import '../dialogs.dart';

// Recording from the Insert menu and the rail (Audio.png), and what the
// Transcript panel does: Add to page as text, Copy, Export, and naming a
// speaker.

/// Starts recording in [pane]'s notebook, on the page it shows.
Future<void> startRecording(BuildContext context, WidgetRef ref, Pane pane) async {
  final rec = ref.read(recordingProvider.notifier);
  if (rec.isRecording) {
    pane.toast('Already recording · Stop is at the top');
    return;
  }
  final nb = ref.read(notebookProvider(pane.notebookId));
  final page = nb.pageAt(pane.page);
  if (nb.isSealed(page.id)) return;
  // Not while something plays: the microphone would hear it.
  await ref.read(playbackProvider.notifier).pause();
  try {
    await rec.start(
      notebookId: pane.notebookId,
      pageId: page.id,
      title: ref.read(libraryProvider).byId(pane.notebookId)?.title ?? '',
    );
    pane.toast('Recording · what you write now lights up when it plays back');
  } on RecordingError catch (e) {
    if (context.mounted) await showMessage(context, title: 'Can’t record', message: e.message);
  }
}

/// Stops the recording and puts its card on the page [pane] shows (in its
/// own notebook). A recording from another notebook goes on its page there
/// the next time that notebook opens.
Future<void> stopRecording(WidgetRef ref, Pane pane) async {
  final r = await ref.read(recordingProvider.notifier).stop();
  if (r == null) return;
  if (r.notebookId == pane.notebookId) {
    pane.audio.place(r);
  } else {
    final title = ref.read(libraryProvider).byId(r.notebookId)?.title ?? 'its notebook';
    pane.toast('Saved · it goes on its page when you open “$title”');
  }
}

/// A recording's name: "Lecture 3 recording" after its page's title, or
/// "Recording 2".
String recordingName(BoardPage page, int others) {
  final title = page.title.trim();
  if (title.isNotEmpty) return '$title recording';
  return others == 0 ? 'Recording' : 'Recording ${others + 1}';
}

/// "Add to page as text": the transcript as a text box under its card
/// (one undo step).
void addTranscriptAsText(WidgetRef ref, Pane pane, AudioItem clip, {required Color color}) {
  final nb = ref.read(notebookProvider(pane.notebookId).notifier);
  final found = nb.audioClip(clip.id);
  if (found == null || clip.transcript.isEmpty) return;
  final (pageId, card) = found;
  final page = ref.read(notebookProvider(pane.notebookId)).pages.firstWhere((p) => p.id == pageId);
  final now = DateTime.now().toUtc();
  final text = TextItem(
    id: newId('it', now: now),
    x: card.x,
    y: card.y + card.h + 24 * card.unit,
    z: page.nextZ,
    createdAt: now,
    wrap: card.w,
    text: transcriptText(clip),
    size: 18,
    color: color,
  );
  nb.insertItems(pageId, [text]);
  pane.toast('Added the transcript to the page under the recording', undoPageId: pageId);
}

void copyTranscript(Pane pane, AudioItem clip) {
  Clipboard.setData(ClipboardData(text: transcriptText(clip)));
  pane.toast('Copied the transcript');
}

/// Exports the transcript as a text file (with times and speakers), saved
/// where the user picks.
Future<void> exportTranscript(WidgetRef ref, Pane pane, AudioItem clip) async {
  final name = '${_fileName(clip.name.isEmpty ? 'Recording' : clip.name)} transcript.txt';
  final header = [
    clip.name.isEmpty ? 'Recording' : clip.name,
    [clip.recordedAt.toLocal().toString().substring(0, 16), clockOf(clip.durationMs), if (clip.language != null) languageName(clip.language)].join(' · '),
    '',
  ].join('\n');
  final bytes = Uint8List.fromList(utf8.encode('$header${transcriptText(clip)}\n'));
  if (await ref.read(fileTransferProvider).save(name, bytes, 'text/plain')) pane.toast('Saved “$name”');
}

String _fileName(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-').trim();

/// Names speaker [key] of [clip] (one undo step): every line of theirs
/// shows the name.
Future<void> nameSpeaker(BuildContext context, WidgetRef ref, Pane pane, AudioItem clip, String key) async {
  final name = await showNamePrompt(
    context,
    title: 'Name this speaker',
    initial: clip.speakers[key] ?? '',
    label: 'Name',
    action: 'Save',
    hint: 'Professor',
  );
  if (name == null) return;
  final nb = ref.read(notebookProvider(pane.notebookId).notifier);
  final found = nb.audioClip(clip.id);
  if (found == null) return;
  final (pageId, now) = found;
  final speakers = {...now.speakers};
  if (name.trim().isEmpty) {
    speakers.remove(key);
  } else {
    speakers[key] = name.trim();
  }
  nb.replaceItems(pageId, [now.copyWith(speakers: speakers)]);
}

/// Applies edits to [clip]'s transcript (the line starting at each key's
/// time gets the new text; an empty one is removed), as one undo step.
/// Returns how many lines changed.
int editTranscript(WidgetRef ref, Pane pane, String clipId, Map<int, String> edits) {
  final nb = ref.read(notebookProvider(pane.notebookId).notifier);
  final found = nb.audioClip(clipId);
  if (found == null || edits.isEmpty) return 0;
  final (pageId, now) = found;
  var changed = 0;
  final lines = <TranscriptLine>[];
  for (final l in now.transcript) {
    final text = edits[l.tMs]?.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text == null || text == l.text) {
      lines.add(l);
      continue;
    }
    changed++;
    if (text.isNotEmpty) lines.add(l.copyWith(text: text));
  }
  if (changed == 0) return 0;
  nb.replaceItems(pageId, [now.copyWith(transcript: lines)]);
  pane.toast(changed == 1 ? 'Edited a line of the transcript' : 'Edited $changed lines of the transcript', undoPageId: pageId);
  return changed;
}

/// Reads [clip]'s recording from its notebook (opened with the key held,
/// on a page with a password), for playing.
Future<(Uint8List, String)?> Function() audioLoader(WidgetRef ref, String notebookId, AudioItem clip) => () async {
      final bytes = await ref.read(notebookProvider(notebookId).notifier).readAsset(clip.asset);
      return bytes == null ? null : (bytes, p.extension(clip.asset).replaceFirst('.', ''));
    };

/// Plays [clip] from [ms]. False if it can't be played here.
Future<bool> playClipAt(WidgetRef ref, String notebookId, AudioItem clip, int ms) =>
    ref.read(playbackProvider.notifier).seek(notebookId, clip.id, clip.durationMs, ms, audioLoader(ref, notebookId, clip));

/// Plays or pauses [clip]. False if it can't be played here.
Future<bool> toggleClip(WidgetRef ref, String notebookId, AudioItem clip) =>
    ref.read(playbackProvider.notifier).toggle(notebookId, clip.id, clip.durationMs, audioLoader(ref, notebookId, clip));

/// Said when a recording can't be played (locked, missing, or no player on
/// this device).
const cantPlay = 'This recording can’t be played here';

/// Makes [clip]'s transcript again after it failed.
void retryTranscript(WidgetRef ref, String notebookId, AudioItem clip) {
  ref.read(notebookProvider(notebookId).notifier).setTranscript(clip.copyWith(state: TranscriptState.waiting));
  ref.read(transcriptionProvider.notifier).add(notebookId, clip.id);
}
