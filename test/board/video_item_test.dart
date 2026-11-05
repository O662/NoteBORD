import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:endless/board/codec.dart';
import 'package:endless/board/model.dart';
import 'package:endless/canvas/video_card.dart';
import 'package:endless/state/assets.dart';
import 'package:endless/video/media_server.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

VideoItem _video({String? asset = 'v.mp4', String? link, int? from, int? to}) => VideoItem(
      id: 'it_v',
      x: 110,
      y: 156,
      z: 3,
      createdAt: DateTime.utc(2026, 11, 6, 13),
      asset: asset,
      link: link,
      name: 'cart-collision.mp4',
      durationMs: 65000,
      videoW: 1920,
      videoH: 1080,
      preview: 'still.jpg',
      trimFrom: from,
      trimTo: to,
    );

void main() {
  test('a video goes through the file as it was; never transcribed has no state', () {
    final v = _video();
    final json = v.toJson();
    expect(json['type'], 'video');
    expect(json.containsKey('transcribe'), isFalse);
    expect(json.containsKey('link'), isFalse);
    final back = decodeItem({...json, 'future': true}) as VideoItem;
    expect(back.asset, 'v.mp4');
    expect(back.name, 'cart-collision.mp4');
    expect(back.state, TranscriptState.none);
    expect(back.preview, 'still.jpg');
    expect(back.sound, isTrue);
    expect(back.toJson()['future'], isTrue);
    // The file and its still are the notebook's assets.
    expect(assetRefs(json).toSet(), {'v.mp4', 'still.jpg'});

    // Transcribed, even with nothing heard, says so.
    final done = v.withTranscript(state: TranscriptState.done);
    expect((decodeItem(done.toJson()) as VideoItem).state, TranscriptState.done);
    final working = v.withTranscript(state: TranscriptState.working, upToMs: 4000);
    expect((decodeItem(working.toJson()) as VideoItem).upToMs, 4000);
  });

  test('a big video is a link, not an asset; trimming keeps the file and says where it plays', () {
    final linked = _video(asset: null, link: 'vid_01.mp4');
    final json = linked.toJson();
    expect(json['link'], 'vid_01.mp4');
    expect(assetRefs(json).toSet(), {'still.jpg'});
    expect((decodeItem(json) as VideoItem).link, 'vid_01.mp4');

    final t = _video(from: 5000, to: 58000);
    expect(t.trimmed, isTrue);
    expect((t.from, t.to), (5000, 58000));
    final back = decodeItem(t.toJson()) as VideoItem;
    expect((back.from, back.to), (5000, 58000));
    expect(_video().trimmed, isFalse);
    expect(_video(from: 70000).from, 65000);
    expect(t.copyWith(trimFrom: () => null, trimTo: () => null).trimmed, isFalse);
  });

  test('a pin chip, the card’s parts and a grabbed frame’s caption', () {
    final pin = VideoPinItem(id: 'it_p', x: 850, y: 180, z: 4, createdAt: DateTime.utc(2026), w: 72, h: 36, video: 'it_v', tMs: 12000);
    final back = decodeItem(pin.toJson()) as VideoPinItem;
    expect((back.video, back.tMs, back.w), ('it_v', 12000, 72.0));
    expect(videoPinLabel(12000), '▶ 0:12');
    expect(pinNear([12000, 31000], 12400), 12000);
    expect(pinNear([12000, 31000], 20000), isNull);

    final v = _video(from: 5000, to: 58000);
    for (final part in [VideoPart.play, VideoPart.playSmall, VideoPart.speed, VideoPart.note, VideoPart.grab, VideoPart.popOut, VideoPart.fullScreen]) {
      expect(videoHitAt(v, videoPartRect(part).center)?.part, part, reason: '$part');
    }
    expect(videoHitAt(v, const Offset(100, 100))?.part, VideoPart.screen);
    // The timeline is the part that plays: halfway is 31.5 s.
    final mid = videoHitAt(v, const Offset((12 + 688) / 2, 405));
    expect(mid?.part, VideoPart.timeline);
    expect(mid!.share, closeTo(0.5, 0.01));
    // A pin's dot comes before the timeline under it; a pin outside the trim has none.
    final x31 = 12 + 676 * (31000 - 5000) / 53000;
    expect(videoHitAt(v, Offset(x31 + 4, 405), pins: [31000, 2000])?.pinMs, 31000);
    expect(videoHitAt(v, const Offset(12, 405), pins: [2000])?.part, VideoPart.timeline);

    final frame = ImageItem(id: 'it_f', x: 0, y: 0, z: 1, createdAt: DateTime.utc(2026), w: 200, h: 112.5, asset: 'f.jpg', extra: const {'caption': 'Grabbed frame · from video'});
    expect(frame.caption, 'Grabbed frame · from video');
    expect(frame.paintRect, const Rect.fromLTRB(-6, -6, 206, 138.5));
    expect((decodeItem(frame.toJson()) as ImageItem).caption, 'Grabbed frame · from video');
  });

  test('the media server serves a sealed video from memory, in ranges, on this device only', () async {
    final server = MediaServer();
    addTearDown(server.close);
    final bytes = Uint8List.fromList(List.generate(1000, (i) => i % 256));
    final url = await server.serve(bytes, 'video/mp4');
    final uri = Uri.parse(url);
    expect(uri.host, '127.0.0.1');
    final client = HttpClient();
    addTearDown(client.close);
    Future<(int, List<int>, String?)> get(String? range) async {
      final req = await client.getUrl(uri);
      if (range != null) req.headers.set(HttpHeaders.rangeHeader, range);
      final res = await req.close();
      final body = await res.fold<List<int>>([], (a, b) => a..addAll(b));
      return (res.statusCode, body, res.headers.value(HttpHeaders.contentRangeHeader));
    }

    final whole = await get(null);
    expect(whole.$1, 200);
    expect(whole.$2, bytes);
    final part = await get('bytes=100-199');
    expect(part.$1, 206);
    expect(part.$2, bytes.sublist(100, 200));
    expect(part.$3, 'bytes 100-199/1000');
    expect((await get('bytes=990-')).$2, bytes.sublist(990));
    expect((await get('bytes=-10')).$2, bytes.sublist(990));
    expect((await get('bytes=2000-')).$1, 416);
    // Someone guessing the address, or after it's let go: nothing.
    final other = await client.getUrl(uri.replace(path: '/abc'));
    expect((await other.close()).statusCode, 404);
    server.release(url);
    expect((await get(null)).$1, 404);
    expect(utf8.decode(utf8.encode('ok')), 'ok');
  });
}
