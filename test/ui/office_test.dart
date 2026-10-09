import 'dart:convert';
import 'dart:typed_data';

import 'package:endless/board/ids.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/canvas/office_cards.dart';
import 'package:endless/office/office_model.dart';
import 'package:endless/office/office_reader.dart';
import 'package:endless/office/office_render.dart';
import 'package:endless/state/assets.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/state/office_docs.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/transfer/files.dart';
import 'package:endless/transfer/pdf_export.dart';
import 'package:endless/ui/dialogs.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../office_samples.dart';

final _at = DateTime.utc(2026, 10, 8, 9);

List<Item> _items(ProviderContainer c) => shownPage(c).items;

OfficeItem _card(ProviderContainer c) => _items(c).whereType<OfficeItem>().single;

/// A card for [bytes] centered on the screen (page coords = screen coords).
OfficeItem _cardFor(Uint8List bytes, String name, {Offset center = const Offset(640, 420)}) {
  final kind = officeKindOf(bytes)!;
  final preview = OfficePreview(readOffice(bytes, kind), bytes, decode: (_) async => throw UnsupportedError('none'));
  final card = newOfficeCard(kind, preview, asset: assetNameFor(bytes, ext: kind.name), name: name, center: center, z: 1, now: _at);
  preview.dispose();
  return card;
}

/// A notebook with one page holding [card], its file stored.
MemoryBoardStore _storeWith(OfficeItem card, Uint8List bytes) {
  final page = BoardPage(id: newId('pg'), items: [card]);
  final nb = Notebook(id: newId('nb'), title: 'Physics', createdAt: _at, updatedAt: _at, pageIds: [page.id]);
  final store = storeWith(LoadedNotebook(nb, [page]));
  store.saveAsset(nb.id, card.asset, bytes);
  return store;
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
  final f = await tester.createGesture(kind: PointerDeviceKind.touch, pointer: 60);
  await f.down(at, timeStamp: later);
  await f.up(timeStamp: later);
  await tester.pump();
}

List<Offset> _line(Offset a, Offset b, {int n = 20}) => [for (var i = 0; i <= n; i++) Offset.lerp(a, b, i / n)!];

/// The middle of a card's button, on screen.
Offset _button(OfficeItem f, OfficeButton b) {
  final u = f.unit;
  final local = switch (b) {
    OfficeButton.open => Offset(f.w - 30 * u, 19 * u),
    OfficeButton.next => Offset(f.w - 25 * u, f.h - 18 * u),
    OfficeButton.previous => Offset(f.w - 61 * u, f.h - 18 * u),
  };
  expect(officeButtonAt(f, local), b);
  return f.toPage(local);
}

Future<(ProviderContainer, FakeFileTransfer, FakeFileOpener)> _open(WidgetTester tester, MemoryBoardStore store) async {
  final files = FakeFileTransfer();
  final opener = FakeFileOpener();
  final c = await pumpCanvas(tester, store: store, extra: [
    fileTransferProvider.overrideWithValue(files),
    fileOpenerProvider.overrideWithValue(opener),
    decodeAs(testPicture()),
  ]);
  // The file is read for its card.
  await tester.pump();
  await tester.pump();
  return (c, files, opener);
}

/// Lets reading the file from the notebook finish.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Future<void> _insert(WidgetTester tester, String tile) async {
  await tester.tap(byLabel('Insert'));
  await tester.pump();
  await tester.tap(find.text('Everything else'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(tile));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  group('adding a file', () {
    testWidgets('PowerPoint from the Insert menu: a card with its first slide, selected', (tester) async {
      final store = MemoryBoardStore();
      final (c, files, _) = await _open(tester, store);
      final bytes = officeFixture('Ch 9 slides.pptx');
      files.toPickOne = PickedFile('Ch 9 slides.pptx', bytes);
      await _insert(tester, 'PowerPoint');
      expect(find.text('Coming soon'), findsNothing);
      expect(files.askedFor, [
        ['pptx'],
      ]);
      final card = _card(c);
      expect(card.mime, 'pptx');
      expect(card.name, 'Ch 9 slides.pptx');
      expect((card.page, card.pages), (1, 3));
      // 13.333 × 7.5 inches.
      expect(card.pageSize!.width, closeTo(960, 0.1));
      expect(card.pageSize!.height, closeTo(540, 0.1));
      expect(card.center, const Offset(640, 400), reason: 'in the middle of the view');
      expect(card.asset, assetNameFor(bytes, ext: 'pptx'));
      expect(find.text('Added “Ch 9 slides.pptx” to the page'), findsOneWidget);
      expect(c.read(settingsProvider).tool, CanvasTool.select);
      expect(find.bySemanticsLabel('Open'), findsOneWidget, reason: 'selected, with Open in its toolbar');
      // The file itself is in the package, byte for byte.
      await tester.pump(const Duration(seconds: 1));
      expect(await store.loadAsset(canvasPane.notebookId, card.asset), bytes);
      // One undo step takes it off again.
      await tester.tap(byLabel('Undo'));
      await tester.pump();
      expect(_items(c), isEmpty);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('Word and Excel from their tiles; Excel with two sheets gets arrows', (tester) async {
      final (c, files, _) = await _open(tester, MemoryBoardStore());
      files.toPickOne = PickedFile('Lab 4 report.docx', officeFixture('Lab 4 report.docx'));
      await _insert(tester, 'Word document');
      final word = _card(c);
      expect(word.mime, 'docx');
      expect(word.pages, greaterThan(1), reason: 'the report runs over a page');
      expect(word.pageSize!.width, closeTo(612, 0.1));
      expect(word.h, greaterThan(word.w));

      files.toPickOne = PickedFile('Lab data.xlsx', officeFixture('Lab data.xlsx'));
      await _insert(tester, 'Excel sheet');
      final sheet = _items(c).whereType<OfficeItem>().last;
      expect(sheet.mime, 'xlsx');
      expect((sheet.pages, sheet.hasFooter, sheet.pageSize), (2, true, null));
      expect(files.askedFor.last, ['xlsx']);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a file that isn’t one says so; backing out does nothing', (tester) async {
      final (c, files, _) = await _open(tester, MemoryBoardStore());
      files.toPickOne = null;
      await _insert(tester, 'Excel sheet');
      expect(_items(c), isEmpty);
      files.toPickOne = PickedFile('notes.docx', Uint8List.fromList(utf8.encode('just some text')));
      await _insert(tester, 'Word document');
      expect(_items(c), isEmpty);
      expect(find.text('This file isn’t a Word, PowerPoint or Excel file.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('⋯ → Import puts a card on this page; into a folder it makes a notebook', (tester) async {
      final (c, files, _) = await _open(tester, MemoryBoardStore());
      await tester.tap(byLabel('More options'));
      await tester.pump();
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      files.toPick = [PickedFile('Lab data.xlsx', officeFixture('Lab data.xlsx'))];
      await tester.tap(find.widgetWithText(PrimaryButton, 'Browse files'));
      await tester.pump();
      expect(find.textContaining('Office file · '), findsOneWidget);
      await tester.tap(find.widgetWithText(PrimaryButton, 'Import'));
      await settleReal(tester, () => find.textContaining('Added 1 file').evaluate().isNotEmpty);
      expect(_card(c).name, 'Lab data.xlsx');
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('on the board', () {
    testWidgets('the arrows step through the slides, by finger or pen, with no undo steps', (tester) async {
      final bytes = officeFixture('Ch 9 slides.pptx');
      final (c, _, _) = await _open(tester, _storeWith(_cardFor(bytes, 'Ch 9 slides.pptx'), bytes));
      final notifier = c.read(notebookProvider(canvasPane.notebookId).notifier);
      final pageId = shownPage(c).id;
      expect(_card(c).page, 1);

      await _fingerTap(tester, _button(_card(c), OfficeButton.next));
      expect(_card(c).page, 2);
      await _pen(tester, [_button(_card(c), OfficeButton.next)]);
      expect(_card(c).page, 3);
      expect(_card(c).ink, isEmpty, reason: 'a pen tap on an arrow leaves no dot');
      await _fingerTap(tester, _button(_card(c), OfficeButton.next));
      expect(_card(c).page, 3, reason: 'the last slide');
      await _fingerTap(tester, _button(_card(c), OfficeButton.previous));
      expect(_card(c).page, 2);
      expect(notifier.canUndo(pageId), isFalse);

      // Where you are is saved.
      await tester.pump(const Duration(seconds: 1));
      await notifier.flush();
      expect(shownNotebook(c).pageAt(0).items.single, isA<OfficeItem>().having((f) => f.page, 'page', 2));
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('ink is written on the slide showing and stays with it', (tester) async {
      final bytes = officeFixture('Ch 9 slides.pptx');
      final store = _storeWith(_cardFor(bytes, 'Ch 9 slides.pptx'), bytes);
      final (c, _, _) = await _open(tester, store);
      final card = _card(c);
      final mid = card.toPage(Offset(card.w / 2, card.h / 2));

      // On slide 1: the ink goes on the card, not the page.
      await _pen(tester, _line(mid - const Offset(60, 0), mid + const Offset(60, 10)));
      expect(_items(c), hasLength(1));
      expect(_card(c).inkByPage.keys, [1]);
      expect((_card(c).pageInk.single.pagePoints.first - (mid - const Offset(60, 0))).distance, lessThan(0.3));

      // Slide 2 has none; ink written there is its own.
      await _fingerTap(tester, _button(_card(c), OfficeButton.next));
      expect(_card(c).ink, isEmpty);
      await _pen(tester, _line(mid + const Offset(-40, 40), mid + const Offset(40, 40)));
      expect(_card(c).inkByPage.keys.toSet(), {1, 2});
      await _fingerTap(tester, _button(_card(c), OfficeButton.previous));
      expect(_card(c).ink.single.id, isNot(_card(c).inkByPage[2]!.single.id));

      // Ink beside the card is ordinary page ink.
      await _pen(tester, _line(const Offset(80, 700), const Offset(160, 700)));
      expect(_items(c).whereType<StrokeItem>(), hasLength(1));

      // Undo takes back the page ink, then the slide 2 ink, showing slide 2.
      await tester.tap(byLabel('Undo'));
      await tester.pump();
      await tester.tap(byLabel('Undo'));
      await tester.pump();
      expect(_card(c).page, 2);
      expect(_card(c).inkByPage.keys, [1]);

      // The eraser rubs ink off slide 1.
      await _fingerTap(tester, _button(_card(c), OfficeButton.previous));
      c.read(settingsProvider.notifier).apply((s) => s.copyWith(tool: CanvasTool.eraser));
      await tester.pump();
      await _pen(tester, _line(mid + const Offset(0, -30), mid + const Offset(0, 40)));
      expect(_card(c).inkByPage, isEmpty);
      expect(_items(c), hasLength(1), reason: 'the card itself stays');

      // Saved and read back.
      await tester.tap(byLabel('Undo'));
      await tester.pump(const Duration(seconds: 1));
      final saved = (await store.loadNotebook(canvasPane.notebookId))!.pages.single.items.single as OfficeItem;
      expect(saved.inkByPage[1], hasLength(1));
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('moving the card takes its ink along', (tester) async {
      final bytes = officeFixture('Lab data.xlsx');
      final (c, _, _) = await _open(tester, _storeWith(_cardFor(bytes, 'Lab data.xlsx'), bytes));
      final card = _card(c);
      final mid = card.toPage(Offset(card.w / 2, card.h / 2));
      await _pen(tester, _line(mid, mid + const Offset(50, 0)));
      final before = _card(c).pageInk.single.pagePoints.first;
      c.read(settingsProvider.notifier).apply((s) => s.copyWith(tool: CanvasTool.select));
      await tester.pump();
      await _pen(tester, [card.toPage(Offset(card.w / 2, 60))]);
      await _pen(tester, _line(card.toPage(Offset(card.w / 2, 60)), card.toPage(Offset(card.w / 2, 60)) + const Offset(100, 40), n: 10));
      expect((_card(c).center - card.center - const Offset(100, 40)).distance, lessThan(0.3));
      expect((_card(c).pageInk.single.pagePoints.first - before - const Offset(100, 40)).distance, lessThan(0.3));
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('Open hands the file to its own app, and says so when there is none', (tester) async {
      final bytes = officeFixture('Lab 4 report.docx');
      // Low enough that its header is clear of the floating chrome.
      final card = _cardFor(bytes, 'Lab 4 report.docx', center: const Offset(640, 520));
      final (c, _, opener) = await _open(tester, _storeWith(card, bytes));
      await _fingerTap(tester, _button(_card(c), OfficeButton.open));
      await _settle(tester);
      expect(opener.opened, [('Lab 4 report.docx', OfficeKind.docx.mimeType)]);

      // From the selection toolbar, with no app for it.
      opener.works = false;
      c.read(settingsProvider.notifier).apply((s) => s.copyWith(tool: CanvasTool.select));
      await tester.pump();
      await _pen(tester, [_card(c).center]);
      await tester.tap(find.bySemanticsLabel('Open'));
      await _settle(tester);
      expect(opener.opened, hasLength(2));
      expect(find.text('No app on this tablet opens Word files. Install one, then try again.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a missing file shows a card that says so, and still opens nothing', (tester) async {
      final bytes = officeFixture('Ch 9 slides.pptx');
      final card = _cardFor(bytes, 'Ch 9 slides.pptx');
      final page = BoardPage(id: newId('pg'), items: [card]);
      final nb = Notebook(id: newId('nb'), title: 'Physics', createdAt: _at, updatedAt: _at, pageIds: [page.id]);
      final (c, _, opener) = await _open(tester, storeWith(LoadedNotebook(nb, [page])));
      expect(c.read(notebookProvider(canvasPane.notebookId).notifier).docs.unreadable(card.asset), isTrue);
      await _fingerTap(tester, _button(_card(c), OfficeButton.open));
      await _settle(tester);
      expect(opener.opened, isEmpty);
      expect(find.text('This file can’t be found in the notebook'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  testWidgets('a PDF of the page has the card, its ink as vectors, and the slide’s words', (tester) async {
    final bytes = samplePptx();
    final card = _cardFor(bytes, 'Ch 9 slides.pptx').withInk(strokeFrom(const [Offset(600, 420), Offset(700, 430)]));
    final pdf = (await tester.runAsync(() => buildPdf(
          title: 'Office',
          pages: [BoardPage(id: 'pg', items: [card])],
          readAsset: (_) async => null,
          loadOffice: (asset, k) async => OfficePreview(readOffice(bytes, k), bytes, decode: decodeImageBytes),
          compress: false,
        )))!;
    final s = latin1.decode(pdf);
    expect(s, startsWith('%PDF-'));
    // The slide's words and the file's name are in the invisible text layer.
    expect(s, contains('3 Tr'));
    await tester.pump();
  });
}
