// Golden images of Phase 4b at 1280×800: Word, PowerPoint and Excel files
// on the board (the DOCX, PPTX and XLSX cards on design/screens/Board.png),
// with ink on a slide, selected with Open in the toolbar, and in dark mode.
//
// Regenerate after an intended visual change:
//   flutter test --update-goldens test/golden
@Tags(['golden'])
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/canvas/office_cards.dart';
import 'package:endless/office/office_reader.dart';
import 'package:endless/office/office_render.dart';
import 'package:endless/state/assets.dart';
import 'package:endless/state/settings.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../office_samples.dart';

final _at = DateTime.utc(2026, 10, 8, 9);

Future<void> _withShadows(Future<void> Function() body) async {
  debugDisableShadows = false;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
  }
}

OfficeItem _card(Uint8List bytes, String name, Offset center, {int z = 1}) {
  final kind = officeKindOf(bytes)!;
  final preview = OfficePreview(readOffice(bytes, kind), bytes, decode: (_) async => throw UnsupportedError('none'));
  final card = newOfficeCard(kind, preview, asset: assetNameFor(bytes, ext: kind.name), name: name, center: center, z: z, now: _at);
  preview.dispose();
  return card;
}

/// The three files from Board.png, at 100%: the report on the left, the
/// slides (on slide 3, circled in orange like the design) and the data.
(MemoryBoardStore, String) _board(ThemeMode mode) {
  final docx = officeFixture('Lab 4 report.docx');
  final pptx = officeFixture('Ch 9 slides.pptx');
  final xlsx = officeFixture('Lab data.xlsx');
  final report = _card(docx, 'Lab 4 report.docx', const Offset(300, 470));
  var slides = _card(pptx, 'Ch 9 slides.pptx', const Offset(790, 316), z: 2).copyWith(page: 3);
  // A loop around the slide's title, in the design's orange.
  final c = slides.toPage(slides.pageRect.topLeft + Offset(slides.pageRect.width * 0.36, slides.pageRect.height * 0.17));
  slides = slides.withInk(strokeFrom([
    for (var i = 0; i <= 60; i++)
      c + Offset(150 * math.cos((i / 60 * 1.08 - 0.3) * 2 * math.pi), 30 * math.sin((i / 60 * 1.08 - 0.3) * 2 * math.pi)),
  ], color: const Color(0xFFF0A36E), width: 3));
  final data = _card(xlsx, 'Lab data.xlsx', const Offset(750, 668), z: 3);
  final page = BoardPage(id: 'pg_office', items: [report, slides, data]);
  final nb = Notebook(id: 'nb_office', title: 'Physics — Lab 4', createdAt: _at, updatedAt: _at, pageIds: [page.id]);
  final store = storeWith(LoadedNotebook(nb, [page]), settings: AppSettings(themeMode: mode));
  store.saveAsset(nb.id, report.asset, docx);
  store.saveAsset(nb.id, slides.asset, pptx);
  store.saveAsset(nb.id, data.asset, xlsx);
  return (store, slides.id);
}

void _golden(String name, {ThemeMode mode = ThemeMode.light, Future<void> Function(WidgetTester t, ProviderContainer c, String slides)? setUp}) {
  testWidgets(name, (tester) => _withShadows(() async {
        final (store, slides) = _board(mode);
        final picture = testPicture(w: 128, h: 80);
        addTearDown(picture.dispose);
        final c = await pumpCanvas(tester, store: store, extra: [decodeAs(picture)]);
        // The files are read, then the pictures inside them.
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await setUp?.call(tester, c, slides);
        await tester.pump(const Duration(seconds: 5)); // hints time out
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('$name.png'));
      }));
}

void main() {
  setUpAll(loadAppFonts);

  _golden('office');

  _golden('office_dark', mode: ThemeMode.dark);

  // The slides selected: Open in the toolbar.
  _golden('office_selected', setUp: (t, c, slides) async {
    await t.tap(byLabel('Select'));
    await t.pump();
    final card = shownPage(c)[slides]! as OfficeItem;
    final g = await t.createGesture(kind: PointerDeviceKind.stylus);
    await g.down(card.toPage(Offset(card.w / 2, card.h / 2)), timeStamp: const Duration(seconds: 20));
    await g.up(timeStamp: const Duration(seconds: 20));
    await t.pump();
  });
}
