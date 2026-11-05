import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:endless/audio/transcript_lines.dart';
import 'package:endless/audio/transcription.dart';
import 'package:endless/board/ids.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/canvas/live_items.dart' show liveNow;
import 'package:endless/canvas/video_card.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/transfer/files.dart';
import 'package:endless/ui/canvas/video_full_screen.dart';
import 'package:endless/video/video_playback.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../audio/fakes.dart';
import '../helpers.dart';
import '../video/fakes.dart';

// Phase 8b (Video.png): a video on the page, playing, its speed and
// timeline, notes pinned to moments, Grab frame, Trim, Replace, Transcribe,
// full screen, and big videos kept on the tablet with a link.

List<Item> _items(ProviderContainer c) => shownPage(c).items;

VideoItem? _video(ProviderContainer c) => _items(c).whereType<VideoItem>().firstOrNull;

MemoryBoardStore _store() {
  final now = DateTime.utc(2026, 11, 6, 9);
  final page = BoardPage(id: newId('pg'), title: 'Lab 4');
  final nb = Notebook(id: newId('nb'), title: 'Lab journal', createdAt: now, updatedAt: now, pageIds: [page.id]);
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
  final f = await tester.createGesture(kind: PointerDeviceKind.touch, pointer: 71);
  await f.down(at, timeStamp: later);
  await f.up(timeStamp: later);
  await tester.pump();
}

/// A tap on [part] of the card.
Future<void> _on(WidgetTester tester, VideoItem v, VideoPart part, {bool finger = false}) async {
  final at = Offset(v.x, v.y) + videoPartRect(part).center * v.unit;
  finger ? await _fingerTap(tester, at) : await _pen(tester, [at]);
  await tester.pump();
}

const _said = [
  [
    HeardSegment(2000, 9000, ' The carts touch here.', []),
    HeardSegment(12000, 20000, ' Cart B speeds up and cart A almost stops.', []),
  ],
];

void main() {
  late Directory dir;
  late ui.Image picture;
  late Uint8List png;
  setUpAll(() async {
    await loadAppFonts();
    picture = testPicture(w: 640, h: 360);
    png = (await picture.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  });
  tearDownAll(() => picture.dispose());
  setUp(() {
    dir = Directory.systemTemp.createTempSync('endless_video_ui');
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

  Future<(ProviderContainer, MemoryBoardStore, FakeFileTransfer, List<FakeVideoHandle>, FakeVideoTools)> open(
    WidgetTester tester, {
    FakeSpeechToText? words,
  }) async {
    final store = _store();
    final transfer = FakeFileTransfer();
    final handles = <FakeVideoHandle>[];
    final tools = FakeVideoTools(png: png);
    final c = await pumpCanvas(tester, store: store, extra: [
      ...videoOverrides(dir: dir, tools: tools, handles: handles),
      ...audioOverrides(
        dir: dir,
        recorder: () => FakeRecorder(() => 0),
        clock: ManualClock(),
        tools: FakeAudioTools(),
        player: FakePlayer(),
        words: words ?? FakeSpeechToText(_said),
        speakers: FakeSpeakerModels(),
      ),
      fileTransferProvider.overrideWithValue(transfer),
      decodeAs(picture),
    ]);
    return (c, store, transfer, handles, tools);
  }

  Future<VideoItem> insert(WidgetTester tester, ProviderContainer c, FakeFileTransfer transfer, {PickedVideo? video}) async {
    transfer.toPickVideo = video ?? PickedVideo.bytes('cart-collision.mp4', silentWav(30000));
    await tester.tap(byLabel('Insert'));
    await tester.pump();
    await tester.tap(find.text('Everything else'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Video'));
    await tester.pump(const Duration(milliseconds: 500));
    await settleReal(tester, () => _video(c) != null);
    await tester.pump(const Duration(seconds: 5)); // the toast goes
    return _video(c)!;
  }

  testWidgets('Insert → Video: the card on the page, selected, with its still; play, speed, the timeline', (tester) async {
    final (c, store, transfer, handles, tools) = await open(tester);
    final v = await insert(tester, c, transfer);
    expect(v.name, 'cart-collision.mp4');
    expect(v.durationMs, 65000);
    expect((v.videoW, v.videoH), (1920.0, 1080.0));
    expect(v.link, isNull);
    expect(store.assets.values.single.keys, containsAll([v.asset, v.preview]));
    expect(tools.frames, [1000]);
    expect(find.text('Video selected'), findsOneWidget);
    expect(Rect.fromLTWH(v.x, v.y, v.w, v.h), isNot(Rect.zero));

    // Play: the picture's play button.
    await _on(tester, v, VideoPart.play);
    await settleReal(tester, () => c.read(videoPlaybackProvider)?.playing ?? false);
    final h = handles.single;
    expect(h.isPlaying, isTrue);
    expect(h.opened, startsWith('http://127.0.0.1'));
    h.reach(18000);
    await tester.pump();
    expect(c.read(videoPlaybackProvider)!.positionMs, 18000);
    // Pause with a finger on the small button.
    await _on(tester, v, VideoPart.playSmall, finger: true);
    expect(h.isPlaying, isFalse);
    // Speed: 1× → 0.5× (slow motion) → 0.25×.
    await _on(tester, v, VideoPart.speed);
    await _on(tester, v, VideoPart.speed);
    expect(h.speeds, [0.5, 0.25]);
    expect(c.read(videoPlaybackProvider)!.speed, 0.25);
    // A quarter along the timeline.
    final quarter = Offset(v.x + 12 + 676 / 4, v.y + 405);
    await _pen(tester, [quarter]);
    expect(h.seeks.last, 16250);

    // Full screen: the same player; leaving goes back.
    await _on(tester, v, VideoPart.fullScreen);
    await tester.pumpAndSettle();
    expect(find.byType(VideoFullScreen), findsOneWidget);
    expect(handles, hasLength(1));
    await tester.tap(byLabel('Leave full screen'));
    await tester.pumpAndSettle();
    expect(find.byType(VideoFullScreen), findsNothing);
    // Done: the bar goes.
    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(find.text('Video selected'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Note at pins a note to the moment; dots and chips jump there; Grab frame; Trim (one undo step)', (tester) async {
    final (c, _, transfer, handles, _) = await open(tester);
    final v = await insert(tester, c, transfer);
    await _on(tester, v, VideoPart.play);
    await settleReal(tester, () => c.read(videoPlaybackProvider)?.playing ?? false);
    final h = handles.single;
    h.reach(18400);
    await tester.pump();
    await _on(tester, v, VideoPart.playSmall);

    // Note at 0:18: a chip beside the video, the pen ready to write the note.
    c.read(settingsProvider.notifier).apply((s) => s.copyWith(tool: CanvasTool.marker));
    await _on(tester, v, VideoPart.note);
    final chip = _items(c).whereType<VideoPinItem>().single;
    expect((chip.video, chip.tMs), (v.id, 18000));
    expect(chip.x, greaterThan(v.extent.right));
    expect(c.read(settingsProvider).tool, CanvasTool.pen);
    expect(find.text('Pinned a note to 0:18 · write it beside the chip'), findsOneWidget);
    // Not twice at the same second.
    await _on(tester, v, VideoPart.note);
    expect(_items(c).whereType<VideoPinItem>(), hasLength(1));
    h.reach(40200);
    await tester.pump();
    await _on(tester, v, VideoPart.note);
    final chips = _items(c).whereType<VideoPinItem>().toList();
    expect(chips.map((p) => p.tMs), [18000, 40000]);
    expect(chips[1].y, greaterThan(chips[0].extent.bottom));

    // The dot for 0:18 on the timeline, and the chip, jump there and play.
    await _pen(tester, [Offset(v.x + 12 + 676 * 18000 / 65000, v.y + 405)]);
    expect(h.seeks.last, 18000);
    expect(h.isPlaying, isTrue);
    h.reach(30000);
    await tester.pump();
    await _fingerTap(tester, chips[0].center);
    expect(h.seeks.last, 18000);

    // The page shows it: playing, pinned notes, selected.
    h.reach(18300);
    await tester.pump();
    await tester.pump();
    await expectLater(find.byType(ProviderScope), matchesGoldenFile('../golden/video_playing.png'));

    // Grab frame: the picture at this moment beside the video, captioned.
    await _on(tester, v, VideoPart.grab);
    await settleReal(tester, () => _items(c).whereType<ImageItem>().isNotEmpty);
    final frame = _items(c).whereType<ImageItem>().single;
    expect(frame.caption, 'Grabbed frame · from video');
    expect(frame.x, greaterThan(v.extent.right));
    expect(frame.h / frame.w, closeTo(1080 / 1920, 0.01));

    // Trim: from 0:05 to 0:40, one undo step; it plays within it.
    await tester.tap(find.text('Trim'));
    await settleReal(tester, () => find.text('Starts 0:00 · Stops 1:05 · Plays 1:05').evaluate().isNotEmpty);
    await tester.pump(const Duration(milliseconds: 400));
    await settleReal(tester, () => find.byType(Image).evaluate().length >= 9);
    await tester.runAsync(() async {
      for (final e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
    });
    await tester.pump();
    await expectLater(find.byType(ProviderScope), matchesGoldenFile('../golden/video_trim.png'));
    tester.widget<RangeSlider>(find.byType(RangeSlider)).onChanged!(const RangeValues(5000, 40000));
    await tester.pump();
    expect(find.text('Starts 0:05 · Stops 0:40 · Plays 0:35'), findsOneWidget);
    await tester.tap(find.text('Trim').last);
    await tester.pumpAndSettle();
    expect((_video(c)!.from, _video(c)!.to), (5000, 40000));
    expect(find.text('Plays 0:05–0:40'), findsOneWidget);
    // Trim paused it; playing past the end goes back to its start, paused.
    await _on(tester, _video(c)!, VideoPart.playSmall);
    expect(h.isPlaying, isTrue);
    h.reach(41000);
    await tester.pump();
    expect(h.isPlaying, isFalse);
    expect(h.seeks.last, 5000);
    c.read(notebookProvider(canvasPane.notebookId).notifier).undo(shownPage(c).id);
    await tester.pump();
    expect(_video(c)!.trimmed, isFalse);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Transcribe: the transcript panel, made on the tablet; a line jumps the video there', (tester) async {
    final (c, _, transfer, handles, _) = await open(tester);
    final v = await insert(tester, c, transfer);
    expect(find.text('Transcribe'), findsOneWidget);
    await tester.tap(find.text('Transcribe'));
    await tester.pump();
    expect(find.text('Transcript'), findsWidgets);
    await settleReal(tester, () => _video(c)!.state == TranscriptState.done && c.read(transcriptionProvider).isEmpty);
    expect(_video(c)!.transcript.map((l) => l.text), ['The carts touch here.', 'Cart B speeds up and cart A almost stops.']);
    expect(find.text('Cart B speeds up and cart A almost stops.'), findsOneWidget);
    expect(find.text('cart-collision.mp4 · English · made on this tablet'), findsOneWidget);
    await tester.tap(find.text('Cart B speeds up and cart A almost stops.'));
    await settleReal(tester, () => handles.isNotEmpty && handles.single.isPlaying);
    expect(handles.single.seeks.last, 12000);
    // The bar now says Transcript.
    expect(find.text('Transcribe'), findsNothing);
    expect(transcriptText(_video(c)!).split('\n').first, '0:02 Speaker 1: The carts touch here.');
    await tester.pump(const Duration(seconds: 5));
    expect(v.id, _video(c)!.id);
  });

  testWidgets('Replace keeps the pinned notes; a big video stays on the tablet with a link', (tester) async {
    final (c, store, transfer, _, _) = await open(tester);
    final v = await insert(tester, c, transfer);
    await _on(tester, v, VideoPart.note);
    expect(_items(c).whereType<VideoPinItem>(), hasLength(1));
    final nb = c.read(notebookProvider(canvasPane.notebookId).notifier);
    nb.replaceItems(shownPage(c).id, [_video(c)!.copyWith(trimFrom: () => 2000)]);

    // Replace with a big one: kept on the tablet, the page has a link.
    final bytes = silentWav(2000);
    transfer.toPickVideo = PickedVideo('lab-trial-2.mov', () async => 150 * 1000 * 1000, () => Stream.value(bytes));
    await tester.tap(find.text('Replace'));
    await settleReal(tester, () => _video(c)!.name == 'lab-trial-2.mov');
    final now = _video(c)!;
    expect(now.asset, isNull);
    expect(now.link, endsWith('.mov'));
    expect(File('${dir.path}/videos/${now.link}').readAsBytesSync(), bytes);
    expect(now.trimmed, isFalse);
    expect(now.state, TranscriptState.none);
    expect(_items(c).whereType<VideoPinItem>(), hasLength(1));
    expect(find.text('Replaced the video · its notes stay pinned'), findsOneWidget);
    // Undo brings the first back.
    nb.undo(shownPage(c).id);
    await tester.pump();
    expect(_video(c)!.name, 'cart-collision.mp4');
    expect(store.assets.values.single.containsKey(_video(c)!.asset), isTrue);
    await tester.pump(const Duration(seconds: 5));
  });
}
