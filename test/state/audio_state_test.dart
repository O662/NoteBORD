import 'dart:io';

import 'package:endless/audio/ink_moments.dart';
import 'package:endless/audio/recording.dart';
import 'package:endless/audio/transcript_lines.dart';
import 'package:endless/audio/transcription.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/library/library.dart';
import 'package:endless/recognition/handwriting_index.dart' show rowsFor;
import 'package:endless/search/search_text.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/state/settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../audio/fakes.dart';
import '../helpers.dart';

Future<ProviderContainer> _open(MemoryBoardStore store, String id, List<Override> extra) async {
  final c = ProviderContainer(overrides: [...await testOverrides(store), ...extra]);
  addTearDown(c.dispose);
  c.listen(loadedNotebookProvider(id).future, (_, _) {});
  await c.read(loadedNotebookProvider(id).future);
  c.listen(notebookProvider(id), (_, _) {});
  c.listen(settingsProvider, (_, _) {});
  c.listen(libraryProvider, (_, _) {});
  return c;
}

AudioItem _clip({String id = 'it_rec', String asset = 'a.wav', int ms = 30000}) => AudioItem(
      id: id,
      x: 100,
      y: 500,
      z: 3,
      createdAt: DateTime.utc(2026, 11, 6, 13),
      asset: asset,
      name: 'Recording',
      recordedAt: DateTime.utc(2026, 11, 6, 12),
      durationMs: ms,
    );

const _said = [
  [
    HeardSegment(1000, 9000, ' Okay, so momentum is mass times velocity.', []),
    HeardSegment(12000, 20000, ' In a closed system it is conserved.', []),
  ],
  [
    HeardSegment(22000, 29000, ' Write that down.', []),
  ],
];

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('endless_audio'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows may still hold a file for a moment.
    }
  });

  List<Override> fakes({FakeSpeechToText? words, bool noModel = false, ManualClock? clock, FakeAudioTools? tools}) => audioOverrides(
        dir: dir,
        recorder: () => FakeRecorder(() => clock?.now ?? 30000),
        clock: clock ?? ManualClock(),
        tools: tools ?? FakeAudioTools(),
        player: FakePlayer(),
        words: words ?? FakeSpeechToText(_said),
        speakers: FakeSpeakerModels(),
        noModel: noModel,
      );

  test('a transcript isn’t an undo step, and Undo never takes it away', () async {
    final store = MemoryBoardStore();
    final id = addUntitled(store);
    final c = await _open(store, id, fakes());
    final n = c.read(notebookProvider(id).notifier);
    final pageId = c.read(notebookProvider(id)).pages[0].id;
    AudioItem now() => n.audioClip('it_rec')!.$2;

    n.insertItems(pageId, [_clip()]);
    // Moved (an undo step) while its transcript is being made.
    n.replaceItems(pageId, [now().withBox(x: 300, y: 500, w: now().w, h: now().h)]);
    expect(n.setTranscript(now().copyWith(
      transcript: const [TranscriptLine(tMs: 1000, endMs: 9000, text: 'Okay.')],
      state: TranscriptState.done,
    )), isTrue);
    expect(n.canUndo(pageId), isTrue);

    // Undo puts it back where it was, with its transcript.
    n.undo(pageId);
    expect(now().x, 100);
    expect(now().transcript.single.text, 'Okay.');
    expect(now().state, TranscriptState.done);
    // Undo again removes it; Redo brings it back, transcript and all.
    n.undo(pageId);
    expect(n.audioClip('it_rec'), isNull);
    expect(n.setTranscript(_clip()), isFalse);
    n.redo(pageId);
    expect(now().transcript, hasLength(1));
    n.redo(pageId);
    expect(now().x, 300);
    expect(now().state, TranscriptState.done);

    // Naming a speaker is an undo step of its own.
    n.replaceItems(pageId, [now().copyWith(speakers: {'s1': 'Professor'})]);
    n.undo(pageId);
    expect(now().speakers, isEmpty);
    expect(now().transcript, hasLength(1));
  });

  test('ink written while recording is time-stamped; paused, it isn’t', () async {
    final store = MemoryBoardStore();
    final id = addUntitled(store);
    final clock = ManualClock();
    final tools = FakeAudioTools();
    final c = await _open(store, id, fakes(clock: clock, tools: tools));
    final n = c.read(notebookProvider(id).notifier);
    final pageId = c.read(notebookProvider(id)).pages[0].id;
    final rec = c.read(recordingProvider.notifier);
    c.listen(recordingProvider, (_, _) {});

    await rec.start(notebookId: id, pageId: pageId, title: 'Physics');
    expect(c.read(recordingProvider)!.notebookId, id);
    expect(tools.kept.single, (true, 'record'));
    final a = strokeFrom(const [Offset(0, 0), Offset(40, 0)]);
    clock.now = 12000;
    n.addStroke(pageId, a);
    await rec.pause();
    final b = strokeFrom(const [Offset(0, 40), Offset(40, 40)]);
    n.addStroke(pageId, b);
    await rec.resume();
    clock.now = 25000;
    final d = strokeFrom(const [Offset(0, 80), Offset(40, 80)]);
    n.insertItems(pageId, [d]);
    // Another notebook's ink isn't this recording's.
    c.read(inkMomentsProvider).wrote('nb_other', [strokeFrom(const [Offset(1, 1), Offset(2, 2)])]);

    clock.now = 30000;
    final done = await rec.stop();
    expect(c.read(recordingProvider), isNull);
    expect(done!.durationMs, 30000);
    expect(done.extension, 'wav');
    expect([for (final m in done.ink) (m.strokeId, m.tMs)], [(a.id, 12000), (d.id, 25000)]);
    expect(done.wave, hasLength(AudioItem.waveBars));
    expect(tools.kept.last, (false, 'record'));
    // Ink isn't stamped once it has stopped.
    n.addStroke(pageId, strokeFrom(const [Offset(0, 120), Offset(40, 120)]));
    expect(done.ink, hasLength(2));
    await rec.stored(done);
    for (final f in done.files) {
      expect(File(f).existsSync(), isFalse);
    }
  });

  test('a recording cut off (the app stopped) is found again', () async {
    final store = MemoryBoardStore();
    final id = addUntitled(store);
    final clock = ManualClock();
    final c = await _open(store, id, fakes(clock: clock));
    final pageId = c.read(notebookProvider(id)).pages[0].id;
    final rec = c.read(recordingProvider.notifier);
    c.listen(recordingProvider, (_, _) {});
    await rec.start(notebookId: id, pageId: pageId);
    clock.now = 7000;
    c.read(notebookProvider(id).notifier).addStroke(pageId, strokeFrom(const [Offset(0, 0), Offset(40, 0)]));
    // The app is stopped here: the file is as far as it got, and the note
    // beside it as last written.
    await File('${dir.path}/rec/${c.read(recordingProvider)!.audioId}.wav').writeAsBytes(silentWav(7000));
    await rec.pause(); // writes the note
    final cut = c.read(recordingProvider)!.audioId;

    // Another start of the app: the same files.
    final c2 = await _open(store, id, fakes());
    final found = await c2.read(recordingProvider.notifier).recover(id);
    expect(found, hasLength(1));
    expect(found.single.audioId, cut);
    expect(found.single.recovered, isTrue);
    expect(found.single.pageId, pageId);
    expect(found.single.durationMs, 7000);
    expect(found.single.ink.single.tMs, 7000);
    // Not for another notebook.
    expect(await c2.read(recordingProvider.notifier).recover('nb_other'), isEmpty);
  });

  test('a transcript is made a part at a time, carries on where it stopped, and gets its speakers', () async {
    final store = MemoryBoardStore();
    final id = addUntitled(store);
    final words = FakeSpeechToText(_said)..stopAfter = 1;
    final tools = FakeAudioTools();
    final c = await _open(store, id, fakes(words: words, tools: tools));
    c.listen(transcriptionProvider, (_, _) {});
    final n = c.read(notebookProvider(id).notifier);
    final pageId = c.read(notebookProvider(id)).pages[0].id;
    final asset = await n.storeAudio(pageId, silentWav(30000), 'wav');
    n.insertItems(pageId, [_clip(asset: asset!)]);
    AudioItem now() => n.audioClip('it_rec')!.$2;

    // The first part, then the app is stopped.
    c.listen(transcriptErrorsProvider, (_, _) {});
    c.read(transcriptionProvider.notifier).add(id, 'it_rec');
    await _until(() => c.read(transcriptErrorsProvider).isNotEmpty);
    expect(now().state, TranscriptState.working);
    expect(now().upToMs, 20000);
    expect(now().transcript.map((l) => l.text), ['Okay, so momentum is mass times velocity.', 'In a closed system it is conserved.']);
    expect(now().language, 'en');
    expect(now().transcript.every((l) => l.speaker == null), isTrue);

    // Opened again: it carries on from 20 s.
    words.stopAfter = null;
    c.read(transcriptionProvider.notifier).resume(id);
    await _until(() => now().state == TranscriptState.done && c.read(transcriptionProvider).isEmpty);
    expect(words.asked, [0, 20000]);
    expect(c.read(transcriptErrorsProvider), isEmpty);
    expect(now().transcript.map((l) => l.text), [
      'Okay, so momentum is mass times velocity.',
      'In a closed system it is conserved.',
      'Write that down.',
    ]);
    expect(now().transcript.map((l) => l.speaker).toSet(), {'s1'});
    expect(now().upToMs, 0);
    expect(tools.kept.where((k) => k.$2 == 'transcribe').map((k) => k.$1), [true, false, true, false]);
    // Its working files are gone.
    expect(Directory('${dir.path}/work').listSync(), isEmpty);

    // Search finds what was said, with when and who.
    final rows = rowsFor(id, c.read(notebookProvider(id)).pages[0].page, null).where((r) => r.kind == SearchKind.audio).toList();
    expect(rows.map((r) => r.text), contains('In a closed system it is conserved.'));
    final row = rows.firstWhere((r) => r.text.startsWith('In a closed'));
    expect(row.context, '0:12 · Speaker 1 · In a closed system it is conserved.');
    expect(row.data['tMs'], 12000);
    expect(row.rect, now().extent);
    expect(transcriptText(now()).split('\n').last, '0:22 Speaker 1: Write that down.');
  });

  test('lines edited while the transcript is being made stay edited; Undo and Redo of an edit work', () async {
    final store = MemoryBoardStore();
    final id = addUntitled(store);
    final words = FakeSpeechToText([
      [
        const HeardSegment(1000, 9000, ' So I momentum is conserved', [
          (1000, 1500, ' So'),
          (1600, 1700, ' I'),
          (1800, 3000, ' momentum'),
          (3100, 4000, ' is'),
          (4100, 8000, ' conserved'),
        ]),
      ],
      _said[1],
    ])..stopAfter = 1;
    final c = await _open(store, id, fakes(words: words));
    c.listen(transcriptionProvider, (_, _) {});
    c.listen(transcriptErrorsProvider, (_, _) {});
    final n = c.read(notebookProvider(id).notifier);
    final pageId = c.read(notebookProvider(id)).pages[0].id;
    final asset = await n.storeAudio(pageId, silentWav(30000), 'wav');
    n.insertItems(pageId, [_clip(asset: asset!)]);
    AudioItem now() => n.audioClip('it_rec')!.$2;
    c.read(transcriptionProvider.notifier).add(id, 'it_rec');
    await _until(() => c.read(transcriptErrorsProvider).isNotEmpty);
    expect(now().transcript.single.text, 'So I momentum is conserved');

    // Fixed while the rest is still to come (an undo step of its own).
    n.replaceItems(pageId, [now().copyWith(transcript: [now().transcript.single.copyWith(text: 'So, momentum is conserved.')])]);
    words.stopAfter = null;
    c.read(transcriptionProvider.notifier).resume(id);
    await _until(() => now().state == TranscriptState.done && c.read(transcriptionProvider).isEmpty);
    expect(now().transcript.map((l) => l.text), ['So, momentum is conserved.', 'Write that down.']);
    // The edited line keeps its text when the speakers are found.
    expect(now().transcript.first.speaker, 's1');

    // Undo the fix: the line as it was heard, and the rest of the transcript kept.
    n.undo(pageId);
    expect(now().transcript.map((l) => l.text), ['So I momentum is conserved', 'Write that down.']);
    n.redo(pageId);
    expect(now().transcript.first.text, 'So, momentum is conserved.');

    // Once it's done, removing a line, Undo and Redo do just that.
    n.replaceItems(pageId, [now().copyWith(transcript: [now().transcript.first])]);
    n.undo(pageId);
    expect(now().transcript, hasLength(2));
    n.redo(pageId);
    expect(now().transcript, hasLength(1));
  });

  test('without a speech model it says so, and Try again works once there is one', () async {
    final store = MemoryBoardStore();
    final id = addUntitled(store);
    final c = await _open(store, id, fakes(noModel: true));
    c.listen(transcriptionProvider, (_, _) {});
    c.listen(transcriptErrorsProvider, (_, _) {});
    final n = c.read(notebookProvider(id).notifier);
    final pageId = c.read(notebookProvider(id)).pages[0].id;
    final asset = await n.storeAudio(pageId, silentWav(30000), 'wav');
    n.insertItems(pageId, [_clip(asset: asset!)]);
    c.read(transcriptionProvider.notifier).add(id, 'it_rec');
    await _until(() => c.read(transcriptErrorsProvider).isNotEmpty);
    expect(c.read(transcriptErrorsProvider)['it_rec'], contains('no speech model'));
    expect(n.audioClip('it_rec')!.$2.state, TranscriptState.failed);
  });
}

Future<void> _until(bool Function() done) async {
  final end = DateTime.now().add(const Duration(seconds: 20));
  while (!done()) {
    if (DateTime.now().isAfter(end)) throw TestFailure('Timed out');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
