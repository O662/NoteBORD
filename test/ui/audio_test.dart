import 'dart:convert';
import 'dart:io';

import 'package:endless/audio/playback.dart';
import 'package:endless/audio/recording.dart';
import 'package:endless/audio/transcript_lines.dart';
import 'package:endless/audio/transcription.dart';
import 'package:endless/board/ids.dart';
import 'package:endless/canvas/audio_card.dart';
import 'package:endless/canvas/live_items.dart' show liveNow;
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/transfer/files.dart';
import 'package:endless/ui/canvas/transcript_panel.dart';
import 'package:endless/ui/dialogs.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../audio/fakes.dart';
import '../helpers.dart';

// Phase 8a (Audio.png): recording from the Insert menu and the rail, the
// pill, ink time-stamped while recording, the card and its buttons, ink
// lighting up and a finger on ink playing from then, and the Transcript
// panel.

List<Item> _items(ProviderContainer c) => shownPage(c).items;

AudioItem? _clip(ProviderContainer c) => _items(c).whereType<AudioItem>().firstOrNull;

MemoryBoardStore _store({String title = ''}) {
  final now = DateTime.utc(2026, 11, 6, 9);
  final page = BoardPage(id: newId('pg'), title: title);
  final nb = Notebook(id: newId('nb'), title: 'Physics — Lecture notes', createdAt: now, updatedAt: now, pageIds: [page.id]);
  return storeWith(LoadedNotebook(nb, [page]));
}

Future<void> _pen(WidgetTester tester, List<Offset> points) async {
  final g = await tester.createGesture(kind: PointerDeviceKind.stylus);
  var t = const Duration(seconds: 20);
  await g.down(points.first, timeStamp: t);
  for (final p in points.skip(1)) {
    t += const Duration(milliseconds: 8);
    await g.moveTo(p, timeStamp: t);
  }
  await g.up(timeStamp: t);
  await tester.pump();
}

Future<void> _fingerTap(WidgetTester tester, Offset at) async {
  const later = Duration(minutes: 5);
  final f = await tester.createGesture(kind: PointerDeviceKind.touch, pointer: 61);
  await f.down(at, timeStamp: later);
  await f.up(timeStamp: later);
  await tester.pump();
}

List<Offset> _line(Offset a, Offset b, {int n = 16}) => [for (var i = 0; i <= n; i++) Offset.lerp(a, b, i / n)!];

Future<void> _rail(WidgetTester tester, String group, String item) async {
  await tester.tap(byLabel(group));
  await tester.pump();
  await tester.tap(find.text(item));
  await tester.pump();
}

/// The middle of [part] on the card, from its top-left.
Offset _part(AudioPart part, {double speed = 1}) => audioPartRect(part, speed: speed).center;

/// A tap on the card at a spot of Audio.dc.html's 560 × 152 layout.
Future<void> _onCard(WidgetTester tester, AudioItem clip, Offset local, {bool finger = false}) async {
  final at = Offset(clip.x, clip.y) + local;
  if (finger) {
    await _fingerTap(tester, at);
  } else {
    await _pen(tester, [at]);
  }
  await tester.pump();
}

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
  setUpAll(loadAppFonts);
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('endless_audio_ui');
    // "Fri · 0:30": the day it was recorded, as the app's clock says.
    liveNow = () => testNow;
  });
  tearDown(() {
    liveNow = DateTime.now;
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Still held for a moment on Windows.
    }
  });

  testWidgets('record from the Insert flyout, write, pause, stop: the card goes on the page with its ink time-stamped',
      (tester) async {
    final clock = ManualClock();
    final tools = FakeAudioTools();
    final player = FakePlayer();
    final store = _store(title: 'Lecture 3');
    final c = await pumpCanvas(tester, store: store, extra: audioOverrides(
      dir: dir,
      recorder: () => FakeRecorder(() => clock.now),
      clock: clock,
      tools: tools,
      player: player,
      words: FakeSpeechToText(_said),
      speakers: FakeSpeakerModels(),
    ));
    await _rail(tester, 'Insert', 'Record audio');
    await settleReal(tester, () => c.read(recordingProvider) != null);
    expect(find.text('Recording · 0:00'), findsOneWidget);
    expect(byLabel('Pause recording'), findsOneWidget);
    expect(byLabel('Stop recording'), findsOneWidget);
    expect(tools.kept.first, (true, 'record'));

    clock.now = 12000;
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Recording · 0:12'), findsOneWidget);
    await _pen(tester, _line(const Offset(300, 300), const Offset(520, 310)));
    final first = _items(c).whereType<StrokeItem>().single;

    await tester.tap(byLabel('Pause recording'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Paused · 0:12'), findsOneWidget);
    await _pen(tester, _line(const Offset(300, 360), const Offset(520, 370)));
    await tester.tap(byLabel('Resume recording'));
    await tester.pump();
    clock.now = 25000;
    await _pen(tester, _line(const Offset(300, 420), const Offset(520, 430)));
    final third = _items(c).whereType<StrokeItem>().last;
    clock.now = 30000;

    // Insert → Record audio again says it's already recording.
    await _rail(tester, 'Insert', 'Record audio');
    expect(find.text('Already recording · Stop is at the top'), findsOneWidget);

    await tester.tap(byLabel('Stop recording'));
    await settleReal(tester, () => _clip(c) != null);
    expect(c.read(recordingProvider), isNull);
    expect(find.text('Recording · 0:30'), findsNothing);
    final clip = _clip(c)!;
    expect(clip.name, 'Lecture 3 recording');
    expect(clip.durationMs, 30000);
    expect([for (final m in clip.inkTimeline) (m.strokeId, m.tMs)], [(first.id, 12000), (third.id, 25000)]);
    expect(find.text('Added the recording · its transcript is being made on this tablet'), findsOneWidget);
    // Whole on screen, clear of the chrome.
    expect(clip.extent.left, greaterThanOrEqualTo(80));
    expect(clip.extent.bottom, lessThanOrEqualTo(800));
    // Stored in the notebook as a file of its own.
    expect(store.assets.values.any((m) => m.containsKey(clip.asset)), isTrue);

    // The transcript is made on the "tablet".
    await settleReal(tester, () => _clip(c)!.state == TranscriptState.done && c.read(transcriptionProvider).isEmpty);
    expect(_clip(c)!.transcript.map((l) => (l.speaker, l.text)), [
      ('s1', 'Okay, so momentum is mass times velocity.'),
      ('s1', 'In a closed system it is conserved.'),
      ('s1', 'Write that down.'),
    ]);
    expect(tools.kept.map((k) => k.$1), [true, false, true, false]);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the card plays and pauses, seeks on the waveform, ±10 s and speed; ink lights up; a finger on ink plays from then',
      (tester) async {
    final clock = ManualClock();
    final player = FakePlayer();
    late FakeRecorder recorder;
    final c = await pumpCanvas(tester, store: _store(), extra: audioOverrides(
      dir: dir,
      recorder: () => recorder = FakeRecorder(() => clock.now),
      clock: clock,
      tools: FakeAudioTools(),
      player: player,
      words: FakeSpeechToText(_said),
      speakers: FakeSpeakerModels(),
    ));
    await tester.tap(byLabel('Insert'));
    await tester.pump();
    await tester.tap(find.text('Everything else'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Audio'));
    await tester.pump(const Duration(milliseconds: 500));
    await settleReal(tester, () => c.read(recordingProvider) != null);
    await tester.pumpAndSettle();
    // How loud it is as it goes, for the waveform.
    for (var i = 0; i < 300; i++) {
      recorder.level(0.15 + 0.7 * ((i * 37) % 100) / 100 * (i % 7 == 0 ? 0.3 : 1));
    }
    await tester.pump();
    clock.now = 12000;
    await _pen(tester, _line(const Offset(300, 200), const Offset(520, 210)));
    final ink = _items(c).whereType<StrokeItem>().single;
    clock.now = 30000;
    await tester.tap(byLabel('Stop recording'));
    await settleReal(tester, () => _clip(c)?.state == TranscriptState.done && c.read(transcriptionProvider).isEmpty);
    await tester.pump(const Duration(seconds: 5)); // the toast goes
    final clip = _clip(c)!;
    expect(clip.name, 'Recording');
    expect(clip.wave.where((v) => v > 0), isNotEmpty);

    // Play.
    await _onCard(tester, clip, _part(AudioPart.play));
    await settleReal(tester, () => c.read(playbackProvider)?.playing ?? false);
    expect(player.isPlaying, isTrue);
    expect(c.read(playbackProvider)!.durationMs, 30000);
    // Pause.
    await _onCard(tester, clip, _part(AudioPart.play), finger: true);
    await tester.pump();
    expect(player.isPlaying, isFalse);
    // Halfway along the waveform: 15 s, playing.
    await _onCard(tester, clip, const Offset(72 + 165, 64));
    await tester.pump();
    expect(player.seeks.last, 15000);
    expect(player.isPlaying, isTrue);
    // +10 s and −10 s.
    await _onCard(tester, clip, _part(AudioPart.forward));
    expect(player.seeks.last, 25000);
    await _onCard(tester, clip, _part(AudioPart.back));
    await _onCard(tester, clip, _part(AudioPart.back));
    expect(player.seeks.last, 5000);
    // Speed: 1× → 1.25× → 1.5×.
    await _onCard(tester, clip, _part(AudioPart.speed));
    await _onCard(tester, clip, _part(AudioPart.speed, speed: 1.25));
    expect(player.speeds, [1.25, 1.5]);
    expect(c.read(playbackProvider)!.speed, 1.5);

    // Playing at 12.5 s: the ink written at 12 s is lit, "written at 0:12".
    player.reach(12500);
    await tester.pump();
    await tester.pump();
    expect(c.read(playbackProvider)!.positionMs, 12500);
    await expectLater(find.byType(ProviderScope), matchesGoldenFile('../golden/audio_playing.png'));

    // A finger on the ink plays from just before it was written.
    await _onCard(tester, clip, const Offset(-1000, -1000)); // nothing (off the card)
    await _fingerTap(tester, ink.bounds.center);
    await tester.pump();
    expect(player.seeks.last, 10000);
    // The pen on ink writes, as always.
    final before = _items(c).whereType<StrokeItem>().length;
    await _pen(tester, _line(ink.bounds.center, ink.bounds.center + const Offset(40, 30)));
    expect(_items(c).whereType<StrokeItem>().length, before + 1);
    expect(player.seeks.last, 10000);

    // The grip moves the card (one undo step), with its transcript.
    final grab = Offset(clip.x, clip.y) + _part(AudioPart.grip);
    final g = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await g.down(grab, timeStamp: const Duration(seconds: 50));
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(grab + Offset(0, -12.0 * i), timeStamp: Duration(seconds: 50, milliseconds: 8 * i));
    }
    await g.up(timeStamp: const Duration(seconds: 51));
    await tester.pump();
    expect(_clip(c)!.y, closeTo(clip.y - 120, 0.5));
    c.read(notebookProvider(canvasPane.notebookId).notifier).undo(shownPage(c).id);
    await tester.pump();
    expect(_clip(c)!.y, clip.y);
    expect(_clip(c)!.transcript, hasLength(3));

    // Deleting the card stops it playing.
    c.read(notebookProvider(canvasPane.notebookId).notifier).removeItems(shownPage(c).id, [clip.id]);
    await tester.pump();
    await tester.pump();
    expect(c.read(playbackProvider), isNull);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the Transcript panel: lines with times and speakers, tap to play, name a speaker, search, add, copy, export',
      (tester) async {
    final clock = ManualClock();
    final player = FakePlayer();
    final transfer = FakeFileTransfer();
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    final c = await pumpCanvas(tester, store: _store(), extra: [
      ...audioOverrides(
        dir: dir,
        recorder: () => FakeRecorder(() => clock.now),
        clock: clock,
        tools: FakeAudioTools(),
        player: player,
        words: FakeSpeechToText(_said),
        speakers: FakeSpeakerModels(),
      ),
      fileTransferProvider.overrideWithValue(transfer),
    ]);
    await _rail(tester, 'Insert', 'Record audio');
    await settleReal(tester, () => c.read(recordingProvider) != null);
    clock.now = 30000;
    await tester.tap(byLabel('Stop recording'));
    await settleReal(tester, () => _clip(c)?.state == TranscriptState.done && c.read(transcriptionProvider).isEmpty);
    await tester.pump(const Duration(seconds: 5)); // the toast goes
    final clip = _clip(c)!;

    // The card's Transcript button opens the panel.
    await _onCard(tester, clip, _part(AudioPart.transcript));
    await tester.pump();
    expect(find.text('Transcript'), findsOneWidget);
    expect(find.text('Recording · English · made on this tablet'), findsOneWidget);
    expect(find.text('Okay, so momentum is mass times velocity.'), findsOneWidget);
    expect(find.text('0:12'), findsOneWidget);
    expect(find.text('Speaker 1'), findsNWidgets(3));
    await expectLater(find.byType(ProviderScope), matchesGoldenFile('../golden/audio_transcript.png'));

    // A line plays from its time, and is the one highlighted.
    await tester.tap(find.text('In a closed system it is conserved.'));
    await settleReal(tester, () => c.read(playbackProvider)?.playing ?? false);
    expect(player.seeks.last, 12000);

    // Naming a speaker names every line of theirs (one undo step).
    await tester.tap(find.text('Speaker 1').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byType(DialogFrame), matching: find.byType(EditableText)), 'Professor');
    // Done on the keyboard names them.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Professor'), findsNWidgets(3));
    expect(_clip(c)!.speakers, {'s1': 'Professor'});

    // Search in the transcript.
    await tester.tap(byLabel('Search transcript'));
    await tester.pump();
    final search = find.descendant(of: find.byType(TranscriptPanel), matching: find.byType(TextField));
    await tester.enterText(search, 'closed');
    await tester.pump();
    expect(find.text('Okay, so momentum is mass times velocity.'), findsNothing);
    expect(find.textContaining('closed', findRichText: true), findsWidgets);
    await tester.enterText(search, 'gravity');
    await tester.pump();
    expect(find.text('Nothing in the transcript says “gravity”.'), findsOneWidget);
    await tester.tap(byLabel('Search transcript'));
    await tester.pump();

    // Copy and Export.
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(copied.single, transcriptText(_clip(c)!));
    expect(copied.single.split('\n').first, '0:01 Professor: Okay, so momentum is mass times velocity.');
    await tester.tap(find.text('Export'));
    await settleReal(tester, () => transfer.saved.isNotEmpty);
    expect(transfer.saved.single.name, 'Recording transcript.txt');
    expect(utf8.decode(transfer.saved.single.bytes), contains('0:22 Professor: Write that down.'));

    // Add to page as text: under the card, one undo step.
    await tester.tap(find.text('Add to page as text'));
    await tester.pump();
    final text = _items(c).whereType<TextItem>().single;
    expect(text.text, transcriptText(_clip(c)!));
    expect(text.y, greaterThan(clip.y + clip.h));
    expect(text.x, clip.x);

    // Close.
    await tester.tap(byLabel('Close transcript'));
    await tester.pump();
    expect(find.text('Okay, so momentum is mass times velocity.'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('no microphone: it says so, and nothing records', (tester) async {
    final c = await pumpCanvas(tester, store: _store(), extra: audioOverrides(
      dir: dir,
      recorder: () => FakeRecorder(() => 0, allow: false),
      clock: ManualClock(),
      tools: FakeAudioTools(),
      player: FakePlayer(),
    ));
    await _rail(tester, 'Insert', 'Record audio');
    await settleReal(tester, () => find.text('Can’t record').evaluate().isNotEmpty);
    expect(find.textContaining('needs the microphone'), findsOneWidget);
    expect(c.read(recordingProvider), isNull);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  });

  testWidgets('a recording cut off is put back on its page when the notebook opens', (tester) async {
    final store = _store();
    final nbId = store.notebooks.keys.first;
    final pageId = store.pages[nbId]!.keys.first;
    final rec = Directory('${dir.path}/rec')..createSync(recursive: true);
    File('${rec.path}/it_cut.wav').writeAsBytesSync(silentWav(9000));
    File('${rec.path}/it_cut.json').writeAsStringSync(jsonEncode({
      'notebookId': nbId,
      'pageId': pageId,
      'audioId': 'it_cut',
      'startedAt': '2026-11-06T12:00:00.000Z',
      'elapsedMs': 9000,
      'file': 'it_cut.wav',
      'ink': [],
      'loudness': [10, 50, 90],
    }));
    final c = await pumpCanvas(tester, store: store, extra: audioOverrides(
      dir: dir,
      recorder: () => FakeRecorder(() => 0),
      clock: ManualClock(),
      tools: FakeAudioTools(),
      player: FakePlayer(),
      words: FakeSpeechToText(const []),
    ));
    await settleReal(tester, () => _clip(c) != null);
    expect(_clip(c)!.id, 'it_cut');
    expect(_clip(c)!.name, 'Recording (cut off)');
    expect(_clip(c)!.durationMs, 9000);
    expect(find.text('Found a recording that was cut off · it’s on page 1'), findsOneWidget);
    await settleReal(tester, () => !File('${rec.path}/it_cut.json').existsSync());
    await tester.pump(const Duration(seconds: 5));
  });
}
