import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:endless/board/codec.dart';
import 'package:endless/board/model.dart';
import 'package:endless/canvas/items.dart';
import 'package:endless/canvas/office_cards.dart';
import 'package:endless/office/office_model.dart';
import 'package:endless/office/office_reader.dart';
import 'package:endless/office/office_render.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../office_samples.dart';

final _at = DateTime.utc(2026, 10, 8, 12);

OfficeItem _slides({Map<int, List<StrokeItem>> ink = const {}, int page = 1, double rotation = 0}) => OfficeItem(
      id: 'it_ppt',
      x: 100,
      y: 80,
      rotation: rotation,
      z: 4,
      createdAt: _at,
      w: 495,
      h: 378,
      asset: 'abc.pptx',
      mime: 'pptx',
      name: 'Ch 9 slides.pptx',
      page: page,
      pages: 24,
      pageSize: const Size(960, 540),
      inkByPage: ink,
    );

List<Item> _roundTrip(List<Item> items) => decodePage(encodePage(BoardPage(id: 'pg_1', items: items))).items;

void expectNear(Offset a, Offset b, {double tolerance = 0.2}) {
  expect((a - b).distance, lessThan(tolerance), reason: '$a vs $b');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  group('an Office file on the page', () {
    test('is a `file` item that keeps its page, size, scale and ink per page', () {
      final ink = strokeFrom(const [Offset(10, 10), Offset(60, 30)]);
      final item = _slides(page: 3, ink: {
        3: [ink],
        7: [strokeFrom(const [Offset(5, 5), Offset(9, 9)])],
      });
      final json = jsonDecode(jsonEncode(item.toJson())) as Json;
      expect(json['type'], 'file');
      expect(json['mime'], 'pptx');
      expect(json['asset'], 'abc.pptx');
      expect(json['name'], 'Ch 9 slides.pptx');
      expect(json['page'], 3);
      expect(json['pages'], 24);
      expect(json['pageSize'], [960.0, 540.0]);
      expect(json['unit'], 1.375);
      expect((json['ink'] as Map).keys, ['3', '7']);

      final back = _roundTrip([item]).single as OfficeItem;
      expect(back.toJson(), item.toJson());
      expect(back.ink.single.id, ink.id);
      expect(back.inkByPage[7], hasLength(1));
    });

    test('keeps what a newer app adds, and a PDF page is still a PDF page', () {
      final json = {..._slides().toJson(), 'comments': ['later']};
      final back = decodeItem(jsonDecode(jsonEncode(json)) as Json) as OfficeItem;
      expect(back.toJson()['comments'], ['later']);
      final pdf = decodeItem({
        'id': 'it_pdf', 'type': 'file', 'x': 0, 'y': 0, 'z': 1, 'createdAt': _at.toIso8601String(), //
        'w': 612, 'h': 792, 'asset': 'x.pdf', 'mime': 'pdf', 'page': 2,
      });
      expect(pdf, isA<FileItem>());
    });

    test('ink is written on the page showing, and only shows there', () {
      final card = _slides(page: 2);
      final at = card.toPage(const Offset(200, 150));
      final stroke = strokeFrom([at, at + const Offset(40, 0)]);
      expect(card.takesInkAt(at), isTrue);
      // Not on the header or the footer.
      expect(card.takesInkAt(card.toPage(const Offset(200, 10))), isFalse);
      expect(card.takesInkAt(card.toPage(Offset(200, card.h - 10))), isFalse);

      final written = card.withInk(stroke);
      expect(written.inkByPage.keys, [2]);
      expectNear(written.pageInk.single.pagePoints.first, at);
      expect(written.pageInk.single.width, closeTo(stroke.width, 0.001));

      final elsewhere = written.copyWith(page: 3);
      expect(elsewhere.ink, isEmpty);
      expect(elsewhere.pageInk, isEmpty);
      expect(elsewhere.copyWith(page: 2).pageInk, hasLength(1));

      final gone = written.withoutInk({stroke.id});
      expect(gone.inkByPage, isEmpty);
    });

    test('ink stays on its words when the card is turned, scaled or stretched', () {
      final card = _slides(rotation: 12);
      final local = const Offset(240, 160);
      final written = card.withInk(strokeFrom([card.toPage(local), card.toPage(local + const Offset(30, 10))]));
      // Where the ink is on the slide, in slide points.
      final onSlide = written.ink.single.pagePoints.first;

      final scaled = written.placed(center: written.center, scale: 2) as OfficeItem;
      expect(scaled.unit, closeTo(2.75, 0.001));
      final fit = scaled.contentFit;
      expectNear(scaled.pageInk.single.pagePoints.first, scaled.toPage(fit.origin + onSlide * fit.scale));
      expect(scaled.pageInk.single.width, closeTo(written.pageInk.single.width * 2, 0.01));

      final stretched = stretchBox(written, 1, written.toPage(Offset(written.w + 200, written.h / 2))) as OfficeItem;
      expect(stretched.w, greaterThan(written.w));
      final sfit = stretched.contentFit;
      expectNear(stretched.pageInk.single.pagePoints.first, stretched.toPage(sfit.origin + onSlide * sfit.scale));
      // The slide is still inside the card.
      expect(stretched.previewArea.inflate(0.5).contains(stretched.pageRect.topLeft), isTrue);
      expect(stretched.previewArea.inflate(0.5).contains(stretched.pageRect.bottomRight), isTrue);
    });

    test('a copy has ink of its own', () {
      final card = _slides().withInk(strokeFrom(const [Offset(200, 200), Offset(260, 220)]));
      final copy = card.withBox(id: 'it_copy', x: card.x + 24, y: card.y + 24, w: card.w, h: card.h);
      expect(copy.ink.single.id, isNot(card.ink.single.id));
      expect(copy.ink.single.pagePoints.first, card.ink.single.pagePoints.first);
    });

    test('slides fit the card in the middle, Word pages from the top, sheets at the card’s scale', () {
      final slide = _slides();
      final area = slide.previewArea;
      expect(slide.pageRect.center.dx, closeTo(area.center.dx, 0.01));
      expect(slide.pageRect.center.dy, closeTo(area.center.dy, 0.01));
      expect(slide.pageRect.width / slide.pageRect.height, closeTo(960 / 540, 0.001));

      final doc = OfficeItem(id: 'd', x: 0, y: 0, z: 1, createdAt: _at, w: 440, h: 620, asset: 'a.docx', mime: 'docx', pageSize: const Size(612, 792));
      expect(doc.hasFooter, isFalse);
      expect(doc.pageRect.top, closeTo(doc.previewArea.top + 12 * doc.unit, 0.01));
      final sheet = OfficeItem(id: 's', x: 0, y: 0, z: 1, createdAt: _at, w: 300, h: 300, asset: 'a.xlsx', mime: 'xlsx', pages: 2);
      expect(sheet.hasFooter, isTrue);
      expect(sheet.contentFit.scale, sheet.unit);
    });

    test('its Open button and arrows', () {
      final card = _slides(page: 2);
      final u = card.unit;
      expect(officeButtonAt(card, Offset(card.w - 30 * u, 19 * u)), OfficeButton.open);
      expect(officeButtonAt(card, Offset(card.w - 25 * u, card.h - 18 * u)), OfficeButton.next);
      expect(officeButtonAt(card, Offset(card.w - 60 * u, card.h - 18 * u)), OfficeButton.previous);
      expect(officeButtonAt(card, Offset(card.w / 2, card.h / 2)), isNull);
      expect(officePlace(card), 'Slide 2 of 24');
    });

    test('new cards are sized for their file', () {
      Size sized(OfficeKind kind, OfficeDoc doc, Uint8List bytes) {
        final preview = OfficePreview(doc, bytes, decode: (_) async => throw UnsupportedError('no pictures'));
        final size = officeCardSize(kind, preview);
        preview.dispose();
        return size;
      }

      final pptx = samplePptx(), docx = sampleDocx(), xlsx = sampleXlsx();
      final slides = sized(OfficeKind.pptx, readOffice(pptx, OfficeKind.pptx), pptx);
      expect(slides.width, closeTo(360 * 1.375, 0.01));
      final word = sized(OfficeKind.docx, readOffice(docx, OfficeKind.docx), docx);
      expect(word.height, greaterThan(word.width));
      final excel = sized(OfficeKind.xlsx, readOffice(xlsx, OfficeKind.xlsx), xlsx);
      // As wide as its 4 columns, 64 Excel px each at 0.86.
      expect(excel.width, closeTo(4 * 64 * 0.86 * 1.375, 0.01));
    });
  });
}
