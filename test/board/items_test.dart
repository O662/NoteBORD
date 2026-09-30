import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:endless/board/codec.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/canvas/items.dart';
import 'package:endless/canvas/new_items.dart';
import 'package:endless/canvas/selection.dart';
import 'package:endless/state/assets.dart';
import 'package:endless/templates/templates.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

final _at = DateTime.utc(2026, 9, 29, 12);

Json _json(Item item) => jsonDecode(jsonEncode(item.toJson())) as Json;

/// Encodes a page with [items] and reads it back.
List<Item> _roundTrip(List<Item> items) => decodePage(encodePage(BoardPage(id: 'pg_1', items: items))).items;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  group('.board items', () {
    test('a text box keeps its text, font, size, color and where it wraps', () {
      final t = TextItem(
        id: 'it_t',
        x: 100,
        y: 200,
        rotation: 15,
        z: 3,
        createdAt: _at,
        wrap: 480,
        text: 'Lab 4 — Collisions\nTrack must be level',
        font: 'serif',
        size: 28,
        color: tokens.inkDefaults[1],
        autoWidth: true,
      );
      expect(_json(t), {
        'id': 'it_t',
        'type': 'text',
        'x': 100.0,
        'y': 200.0,
        'rotation': 15.0,
        'z': 3,
        'createdAt': '2026-09-29T12:00:00.000Z',
        'author': 'user_local',
        'remember': null,
        'w': 480.0,
        'text': 'Lab 4 — Collisions\nTrack must be level',
        'font': 'serif',
        'size': 28.0,
        'color': '#2B5A8C',
        'autoWidth': true,
      });
      final back = _roundTrip([t]).single as TextItem;
      expect(back.text, t.text);
      expect(back.font, 'serif');
      expect(back.size, 28);
      expect(back.color, t.color);
      expect(back.autoWidth, isTrue);
      expect(back.rotation, 15);
      // An auto-width box hugs its text: narrower than where it would wrap, two lines tall.
      expect(back.w, lessThan(480));
      expect(back.h, closeTo(2 * 28 * 1.3, 1));

      // Stretched, it wraps at its width and stops hugging.
      final fixed = _roundTrip([t.withBox(x: 100, y: 200, w: 160, h: t.h)]).single as TextItem;
      expect(fixed.autoWidth, isFalse);
      expect(fixed.w, 160);
      expect(fixed.h, greaterThan(t.h));
      expect(_json(fixed).containsKey('autoWidth'), isFalse);
    });

    test('a sticky note keeps its ink and typed text; a stack keeps the notes under it', () {
      final note = newSticky(const Offset(500, 400), z: 4, now: _at)
          .withText('Ask in office hours', color: tokens.inkDefaults[0], at: _at)
          .withInk(strokeFrom([const Offset(420, 380), const Offset(470, 395), const Offset(520, 380)]));
      final json = _json(note);
      expect(json['type'], 'sticky');
      expect(json['w'], 242.0);
      expect(json['h'], 220.0);
      expect(json['color'], '#F6DE7A');
      expect(json['rotation'], -2.0);
      expect(json.containsKey('stack'), isFalse);
      final nested = json['items'] as List;
      expect(nested.map((i) => (i as Map)['type']), ['text', 'stroke']);
      expect((nested[0] as Map)['text'], 'Ask in office hours');

      final back = _roundTrip([note]).single as StickyItem;
      expect(back.text, 'Ask in office hours');
      expect(back.ink, hasLength(1));
      expect(back.isStack, isFalse);
      // The ink is stored relative to the note, and maps back to where it was written.
      final written = back.pageInk.single.pagePoints.toList();
      expect((written.first - const Offset(420, 380)).distance, lessThan(0.2));
      expect((written.last - const Offset(520, 380)).distance, lessThan(0.2));

      final stack = newStickyStack(const Offset(900, 400), z: 5, now: _at);
      expect(_json(stack)['stack'], {
        'count': 3,
        'notes': [
          {'color': '#F4C9A8', 'items': []},
          {'color': '#C9DFC2', 'items': []},
        ],
      });
      final stackBack = _roundTrip([stack]).single as StickyItem;
      expect(stackBack.count, 3);
      expect(stackBack.under.map((n) => n.color), [tokens.stickyColors[2], tokens.stickyColors[3]]);
      expect(stackBack.color, tokens.stickyColors[1]);
    });

    test('a stack that only says how many notes it has keeps its count', () {
      const source = '{"id":"it_s","type":"sticky","x":10,"y":20,"rotation":0,"z":1,'
          '"createdAt":"2026-09-01T00:00:00.000Z","author":"user_x","remember":null,'
          '"w":200,"h":180,"color":"#F3CBD6","items":[],"stack":{"count":5}}';
      final s = decodeItem(jsonDecode(source) as Json) as StickyItem;
      expect(s.count, 5);
      expect(s.under, isEmpty);
      expect(stackLabel(s.count), '5 notes');
      expect(_json(s)['stack'], {'count': 5});
      expect(_json(s)['author'], 'user_x');
    });

    test('frames, images and shapes round trip; unknown fields on them are kept', () {
      final frame = newFrame(const Offset(400, 100), z: 0, now: _at);
      expect(frame.x, 400 - 280);
      expect(frame.y, 100);
      expect(Size(frame.w, frame.h), FrameItem.a4);
      expect(_json(frame)..removeWhere((k, _) => const {'id', 'createdAt'}.contains(k)), {
        'type': 'frame',
        'x': 120.0,
        'y': 100.0,
        'rotation': 0.0,
        'z': 0,
        'author': 'user_local',
        'remember': null,
        'w': 560.0,
        'h': 792.0,
        'paper': 'lined-a4',
        'title': '',
      });
      expect(frameLabel(frame), 'Frame · Lined A4');
      expect(frameLabel(frame.copyWith(title: 'Lab 4')), 'Frame · Lab 4');

      final cornell = newFrame(const Offset(400, 100), z: 0, now: _at, template: templateById('cornell'));
      expect(cornell.template, 'cornell');
      expect(frameLabel(cornell), 'Frame · Cornell notes');
      final graph = newFrame(const Offset(400, 100), z: 0, now: _at, template: templateById('graph'));
      expect(graph.paper, 'grid-a4');
      expect(graph.template, isNull);

      final image = decodeItem({
        'id': 'it_i', 'type': 'image', 'x': 5, 'y': 6, 'z': 2, 'createdAt': '2026-09-01T00:00:00.000Z', //
        'w': 320, 'h': 240, 'asset': 'abc.png', 'crop': {'l': 0.1, 't': 0, 'r': 1, 'b': 1},
      });
      expect(image, isA<ImageItem>());
      expect(_json(image)['crop'], {'l': 0.1, 't': 0, 'r': 1, 'b': 1});
      expect(_json(image)['asset'], 'abc.png');

      final shape = shapeBetween(ShapeType.arrow, const Offset(100, 100), const Offset(200, 200),
          id: 'it_a', z: 9, now: _at, color: tokens.inkDefaults[2], strokeWidth: 4);
      expect(shape.w, closeTo(math.sqrt2 * 100, 1e-9));
      expect(shape.h, 0);
      expect(shape.rotation, closeTo(45, 1e-9));
      expect((shape.toPage(Offset.zero) - const Offset(100, 100)).distance, lessThan(1e-9));
      expect((shape.toPage(Offset(shape.w, 0)) - const Offset(200, 200)).distance, lessThan(1e-9));

      final back = _roundTrip([frame, cornell, image, shape]);
      expect(back.map((i) => i.runtimeType), [FrameItem, FrameItem, ImageItem, ShapeItem]);
      expect((back[1] as FrameItem).template, 'cornell');
      final arrow = back[3] as ShapeItem;
      expect(arrow.kind, ShapeType.arrow);
      expect(arrow.stroke, tokens.inkDefaults[2]);
      expect(arrow.fill, isNull);
      expect(arrow.strokeWidth, 4);
      expect(arrow.rotation, closeTo(45, 1e-9));
    });

    test('a known type this version can’t read is kept exactly as it was', () {
      final odd = <String, dynamic>{
        'id': 'it_x', 'type': 'sticky', 'x': 1, 'y': 2, 'z': 1, 'createdAt': '2026-09-01T00:00:00.000Z', //
        'color': 'not a color', 'w': 'wide',
      };
      final item = decodeItem(odd);
      expect(item, isA<UnknownItem>());
      expect(item.toJson(), odd);
      final shape = decodeItem({...odd, 'type': 'shape', 'kind': 'star', 'w': 10, 'h': 10, 'stroke': '#000000'});
      expect(shape, isA<UnknownItem>());
    });
  });

  group('boxes', () {
    StickyItem note({double rotation = 0}) => StickyItem(
          id: 'it_n', x: 100, y: 100, rotation: rotation, z: 1, createdAt: _at, w: 200, h: 100, color: tokens.stickyColors[0]);

    test('page and local points map back and forth under rotation', () {
      final n = note(rotation: 90);
      // Turned a quarter turn about its center (200, 150): the top-left corner goes to the top-right.
      expect((n.toPage(Offset.zero) - const Offset(250, 50)).distance, lessThan(1e-9));
      for (final p in [const Offset(0, 0), const Offset(200, 100), const Offset(37, 81)]) {
        expect((n.toLocal(n.toPage(p)) - p).distance, lessThan(1e-9));
      }
      expect(n.contains(const Offset(200, 60)), isTrue); // inside the turned box
      expect(n.contains(const Offset(120, 150)), isFalse); // inside only before the turn
      expect(n.extent, rectMoreOrLessEquals(const Rect.fromLTRB(150, 50, 250, 250), epsilon: 1e-9));
      expect(n.bounds.contains(n.extent.topLeft), isTrue);
    });

    test('scaling a note scales its ink and text with it; a copy gets new ids inside', () {
      final n = note()
          .withText('Exam topics', color: tokens.inkDefaults[0], at: _at)
          .withInk(strokeFrom([const Offset(120, 120), const Offset(160, 140)], width: 3));
      final big = const Similarity(scale: 2).applyToItem(n) as StickyItem;
      expect(Size(big.w, big.h), const Size(400, 200));
      expect(big.center, n.center * 2);
      expect(big.ink.single.width, 6);
      expect(big.ink.single.x, closeTo(n.ink.single.x * 2, 0.11));
      final text = big.items.whereType<TextItem>().single;
      expect(text.size, 40);
      expect(text.x, StickyItem.padding * 2);
      expect(big.ink.single.id, n.ink.single.id);

      final copy = n.withBox(id: 'it_copy', x: 300, y: 300, w: n.w, h: n.h);
      expect(copy.text, 'Exam topics');
      expect(copy.ink.single.id, isNot(n.ink.single.id));
      expect(copy.ink.single.points.length, n.ink.single.points.length);
    });

    test('rotating about a pivot turns the box and moves its center', () {
      final n = note();
      final turned = Similarity.about(const Offset(100, 100), rotation: math.pi / 2).applyToItem(n) as StickyItem;
      expect(turned.rotation, closeTo(90, 1e-9));
      // The center (200, 150) swings a quarter turn about (100, 100) to (50, 200).
      expect((turned.center - const Offset(50, 200)).distance, lessThan(1e-9));
      expect(Size(turned.w, turned.h), const Size(200, 100));
    });

    test('stretching an edge keeps the opposite edge where it is, whatever the rotation', () {
      for (final rotation in [0.0, 30.0, -90.0]) {
        final n = note(rotation: rotation);
        final left = [n.toPage(Offset.zero), n.toPage(const Offset(0, 100))];
        final wider = stretchBox(n, 1, n.toPage(const Offset(260, 50))) as StickyItem;
        expect(wider.w, closeTo(260, 1e-9));
        expect(wider.h, 100);
        expect((wider.toPage(Offset.zero) - left[0]).distance, lessThan(1e-9), reason: '$rotation');
        expect((wider.toPage(const Offset(0, 100)) - left[1]).distance, lessThan(1e-9));

        final right = n.toPage(const Offset(200, 0));
        final fromLeft = stretchBox(n, 3, n.toPage(const Offset(-40, 50))) as StickyItem;
        expect(fromLeft.w, closeTo(240, 1e-9));
        expect((fromLeft.toPage(Offset(fromLeft.w, 0)) - right).distance, lessThan(1e-9));
      }
      // It never gets smaller than the minimum.
      expect(stretchBox(note(), 2, const Offset(150, 90), min: 24).h, 24);
      // Text and lines only stretch sideways; pictures keep their shape.
      expect(stretchSides(TextItem(id: 't', x: 0, y: 0, z: 1, createdAt: _at, wrap: 100, text: 'a', color: Colors.black)), [1, 3]);
      expect(stretchSides(ImageItem(id: 'i', x: 0, y: 0, z: 1, createdAt: _at, w: 10, h: 10, asset: 'a.png')), isEmpty);
    });

    test('a shape without a fill is hit on its outline only; a frame by its name too', () {
      final rect = shapeBetween(ShapeType.rect, const Offset(100, 100), const Offset(400, 300),
          id: 'r', z: 1, now: _at, color: Colors.black, strokeWidth: 2.5);
      expect(boxHit(rect, const Offset(250, 101)), isTrue);
      expect(boxHit(rect, const Offset(398, 200)), isTrue);
      expect(boxHit(rect, const Offset(250, 200)), isFalse); // what's inside stays reachable
      final oval = shapeBetween(ShapeType.ellipse, const Offset(100, 100), const Offset(300, 200),
          id: 'o', z: 1, now: _at, color: Colors.black, strokeWidth: 2.5);
      expect(boxHit(oval, const Offset(100, 150)), isTrue);
      expect(boxHit(oval, const Offset(200, 150)), isFalse);
      expect(boxHit(oval, const Offset(104, 104)), isFalse); // the box's corner is outside the oval
      final line = shapeBetween(ShapeType.line, const Offset(100, 100), const Offset(300, 300),
          id: 'l', z: 1, now: _at, color: Colors.black, strokeWidth: 2.5);
      expect(boxHit(line, const Offset(200, 203)), isTrue);
      expect(boxHit(line, const Offset(200, 240)), isFalse);

      final frame = newFrame(const Offset(400, 100), z: 0, now: _at);
      expect(boxHit(frame, const Offset(400, 500)), isTrue);
      expect(boxHit(frame, const Offset(150, 85)), isTrue); // "Frame · Lined A4"
      expect(boxHit(frame, const Offset(600, 85)), isFalse);

      final on = strokeFrom([const Offset(200, 200), const Offset(300, 200)]);
      expect(topBoxAt([frame, on, rect], const Offset(250, 101)), rect);
      expect(topBoxAt([frame, on, rect], const Offset(250, 200)), frame);
      expect(topBoxAt([on], const Offset(250, 200)), isNull);
    });
  });

  group('image files', () {
    test('are named by their content and type', () {
      final png = fakePng();
      final name = assetNameFor(png);
      expect(name, matches(RegExp(r'^[0-9a-f]{64}\.png$')));
      expect(assetNameFor(fakePng()), name);
      expect(assetNameFor(fakePng(2)), isNot(name));
      expect(imageExtension(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])), 'jpg');
      expect(imageExtension(Uint8List.fromList('GIF89a'.codeUnits)), 'gif');
      expect(imageExtension(Uint8List.fromList('RIFF0000WEBPVP8 '.codeUnits)), 'webp');
      expect(imageExtension(Uint8List.fromList([1, 2, 3])), 'img');
    });

    testWidgets('a real PNG decodes to its picture; other bytes are refused', (tester) async {
      await tester.runAsync(() async {
        final source = testPicture(w: 64, h: 48);
        final png = (await source.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
        source.dispose();
        expect(imageExtension(png), 'png');
        final decoded = await decodeImageBytes(png);
        expect((decoded.width, decoded.height), (64, 48));
        decoded.dispose();
        await expectLater(decodeImageBytes(Uint8List.fromList([1, 2, 3, 4])), throwsException);
      });
    });

    test('are found wherever an item names one', () {
      expect(
        assetRefs({
          'type': 'future',
          'asset': 'a.png',
          'items': [
            {'type': 'image', 'asset': 'b.jpg'},
            {'pages': [{'asset': 'c.pdf'}], 'asset': 7},
          ],
        }),
        ['a.png', 'b.jpg', 'c.pdf'],
      );
    });

    test('live in the package’s assets folder', () async {
      final dir = await Directory.systemTemp.createTemp('endless_assets');
      addTearDown(() => dir.delete(recursive: true));
      final store = FileBoardStore(dir);
      expect(await store.listAssets('nb'), isEmpty);
      expect(await store.loadAsset('nb', 'a.png'), isNull);
      await store.saveAsset('nb', 'a.png', fakePng());
      await store.saveAsset('nb', 'b.png.enc', Uint8List.fromList([1, 2, 3]));
      expect(File('${dir.path}/notebooks/nb.board/assets/a.png').existsSync(), isTrue);
      expect((await store.listAssets('nb'))..sort(), ['a.png', 'b.png.enc']);
      expect(await store.loadAsset('nb', 'a.png'), fakePng());
      // A name can't reach outside the folder.
      await store.saveAsset('nb', '../../escape.png', fakePng());
      expect(File('${dir.path}/notebooks/escape.png').existsSync(), isFalse);
      expect(await store.loadAsset('nb', 'escape.png'), fakePng());
      await store.deleteAsset('nb', 'a.png');
      expect(await store.loadAsset('nb', 'a.png'), isNull);
      await store.deleteNotebook('nb');
      expect(await store.listAssets('nb'), isEmpty);
    });
  });
}
