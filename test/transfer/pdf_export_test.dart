import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color, Locale, Offset, Rect, Size;

import 'package:endless/board/model.dart';
import 'package:endless/canvas/new_items.dart';
import 'package:endless/transfer/pdf_export.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../sample_board.dart';

/// The uncompressed PDF as text, to look for drawing operators.
String _text(Uint8List pdf) => latin1.decode(pdf);

int _count(String haystack, Pattern needle) => needle.allMatches(haystack).length;

/// Each page's MediaBox as [width, height].
List<List<double>> _pageSizes(String pdf) => [
      for (final m in RegExp(r'/MediaBox\s*\[\s*([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s*\]').allMatches(pdf))
        [double.parse(m[3]!) - double.parse(m[1]!), double.parse(m[4]!) - double.parse(m[2]!)],
    ];

class _FakeHandwriting extends HandwritingText {
  const _FakeHandwriting();

  @override
  List<TextRun> runsFor(BoardPage page) => [const TextRun('momentum impulse', Rect.fromLTWH(100, 100, 300, 40))];
}

Future<Uint8List> _pdf(WidgetTester tester, List<BoardPage> pages, {PdfOptions options = const PdfOptions(), HandwritingText? handwriting}) async =>
    (await tester.runAsync(() => buildPdf(
          title: 'Test',
          pages: pages,
          readAsset: (_) async => null,
          options: options,
          handwriting: handwriting ?? const NoHandwritingText(),
          compress: false,
        )))!;

void main() {
  setUpAll(loadAppFonts);

  testWidgets('ink goes out as vector fills, typed text as real text', (tester) async {
    final board = sampleBoard();
    final page = board.pages.first;
    final pdf = await _pdf(tester, [page]);
    // ENDLESS_PDF_OUT=<file> saves it, to look at.
    final out = Platform.environment['ENDLESS_PDF_OUT'];
    if (out != null) {
      final packed = await tester.runAsync(() => buildPdf(title: 'Board', pages: [page], readAsset: (_) async => null));
      File(out).writeAsBytesSync(packed!);
    }
    final s = _text(pdf);
    expect(s, startsWith('%PDF-'));
    final strokes = page.items.whereType<StrokeItem>().length;
    expect(strokes, greaterThan(0));
    // One fill per stroke at least, built from many line segments.
    expect(_count(s, RegExp(r'\sf\s')), greaterThanOrEqualTo(strokes));
    expect(_count(s, RegExp(r'\sl\s')), greaterThan(strokes * 20));
    // Cards are pictures; the ink is not.
    final cards = page.items.whereType<CardItem>().length;
    expect(_count(s, '/Subtype /Image'), lessThanOrEqualTo(cards * 2));
  });

  testWidgets('a searchable text layer: handwriting runs and card text, drawn invisibly', (tester) async {
    final page = sampleBoard().pages.first;
    final s = _text(await _pdf(tester, [page], handwriting: const _FakeHandwriting()));
    // Text render mode 3 is invisible.
    expect(s, contains('3 Tr'));
    final off = _text(await _pdf(tester, [page], handwriting: const _FakeHandwriting(), options: const PdfOptions(searchable: false)));
    expect(off, isNot(contains('3 Tr')));
  });

  testWidgets('fit page to its ink: one sheet around everything', (tester) async {
    final page = BoardPage(id: 'p', items: [
      strokeFrom([const Offset(100, 100), const Offset(700, 400)]),
    ]);
    final sheet = pdfSheets(page, const PdfOptions()).single;
    expect(sheet.area, page.items.single.bounds.inflate(fitMargin));
    expect(sheet.size, sheet.area.size, reason: 'one page px is one point');
    final sizes = _pageSizes(_text(await _pdf(tester, [page])));
    expect(sizes.single[0], closeTo(sheet.size.width, 0.01));
  });

  // What the tablet did (2026-10-01): a lined A4 frame came out as four
  // quarters of a 2 × 2 grid, the writing where they met.
  testWidgets('split: a lined A4 sheet with writing is one page, from the top', (tester) async {
    final frame = newFrame(const Offset(400, 300), z: 1, now: testNow);
    final page = BoardPage(id: 'p', items: [
      frame,
      for (var i = 0; i < 4; i++)
        strokeFrom([for (var x = 0; x <= 20; x++) Offset(frame.x + 120 + x * 8.0, frame.y + 130 + i * 40 + (x.isEven ? 0 : 8))], z: 2 + i),
    ]);
    for (final paper in PaperSize.values) {
      final all = pdfSheets(page, PdfOptions(pages: EndlessPages.split, paper: paper));
      expect(all, hasLength(1), reason: '$paper');
      final sheet = all.single;
      expect(sheet.size, paper.size);
      final ink = pageContent(page)!;
      expect(sheet.clip.expandToInclude(ink), sheet.clip, reason: 'nothing is cut off');
      // The ink starts half an inch from the top, centered across.
      expect((ink.top - sheet.area.top) * sheet.scale, closeTo(paperMargin, 0.01));
      expect((ink.center.dx - sheet.area.left) * sheet.scale, closeTo(paper.size.width / 2, 0.01));
    }
  });

  testWidgets('split: long pages go onto several sheets, cut between lines of writing', (tester) async {
    final lines = [
      for (var i = 0; i < 40; i++)
        strokeFrom([for (var x = 0; x <= 30; x++) Offset(x * 15.0, i * 44.0 + (x.isEven ? 0 : 14))], z: i + 1),
    ];
    final page = BoardPage(id: 'p', items: lines);
    final sheets = pdfSheets(page, const PdfOptions(pages: EndlessPages.split));
    expect(sheets.length, greaterThan(1));
    for (final (i, s) in sheets.indexed) {
      expect(s.size, PaperSize.a4.size);
      expect(s.scale, 1, reason: 'narrower than the paper: kept at its size');
      if (i > 0) expect(s.clip.top, sheets[i - 1].clip.bottom, reason: 'nothing skipped or repeated');
      for (final l in lines) {
        expect(l.bounds.top < s.clip.bottom && l.bounds.bottom > s.clip.bottom && s != sheets.last, isFalse, reason: 'no line cut in half');
      }
    }
    expect(sheets.last.clip.bottom, pageContent(page)!.bottom);
  });

  testWidgets('split: wide ink turns the paper sideways and shrinks to fit, down to half size', (tester) async {
    final wide = BoardPage(id: 'p', items: [strokeFrom([const Offset(0, 0), const Offset(1200, 300)])]);
    final sheet = pdfSheets(wide, const PdfOptions(pages: EndlessPages.split)).single;
    expect(sheet.size, Size(PaperSize.a4.size.height, PaperSize.a4.size.width));
    expect(sheet.scale, lessThan(1));
    expect(sheet.clip.width * sheet.scale, closeTo(sheet.size.width - 2 * paperMargin, 0.01));

    final huge = BoardPage(id: 'p', items: [strokeFrom([const Offset(0, 0), const Offset(4000, 300)])]);
    final sheets = pdfSheets(huge, const PdfOptions(pages: EndlessPages.split));
    expect(sheets.length, 3, reason: 'side by side at half size');
    for (final s in sheets) {
      expect(s.scale, closeTo(minPaperScale, 1e-9));
    }
  });

  testWidgets('split into Letter: empty stretches are left out', (tester) async {
    final page = BoardPage(id: 'p', items: [
      strokeFrom([const Offset(0, 0), const Offset(500, 40)]),
      strokeFrom([const Offset(0, 1500), const Offset(500, 1540)]),
    ]);
    final letter = _pageSizes(_text(await _pdf(tester, [page], options: const PdfOptions(pages: EndlessPages.split, paper: PaperSize.letter))));
    expect(letter, [
      [612, 792],
      [612, 792],
    ]);
  });

  testWidgets('an empty page is one blank sheet', (tester) async {
    final sheet = pdfSheets(BoardPage(id: 'p'), const PdfOptions()).single;
    expect((sheet.area, sheet.size), (Offset.zero & PaperSize.a4.size, PaperSize.a4.size));
  });

  testWidgets('an imported PDF page with writing inside it goes out at its own size', (tester) async {
    final file = FileItem(id: 'f', x: 0, y: 0, z: 1, createdAt: testNow, w: 612, h: 792, asset: 'a.pdf', mime: 'pdf', page: 1, preview: 'a.png');
    final page = BoardPage(id: 'p', items: [file, strokeFrom([const Offset(100, 100), const Offset(200, 120)], z: 2)]);
    final sheet = pdfSheets(page, const PdfOptions()).single;
    expect((sheet.area, sheet.size), (const Rect.fromLTWH(0, 0, 612, 792), const Size(612, 792)));
  });

  testWidgets('the dot background is optional', (tester) async {
    final page = BoardPage(id: 'p', items: [strokeFrom([const Offset(0, 0), const Offset(300, 200)])]);
    final plain = _text(await _pdf(tester, [page]));
    final dots = _text(await _pdf(tester, [page], options: const PdfOptions(background: true)));
    // Each dot is an ellipse of four curves.
    expect(_count(dots, RegExp(r'\sc\s')) - _count(plain, RegExp(r'\sc\s')), greaterThan(4 * 50));
  });

  test('paper follows the locale', () {
    expect(paperForLocale(const Locale('en', 'US')), PaperSize.letter);
    expect(paperForLocale(const Locale('en', 'GB')), PaperSize.a4);
    expect(paperForLocale(const Locale('de')), PaperSize.a4);
  });

  test('card text for search', () {
    expect(cardText(sampleKanban), contains(sampleKanban.title));
  });

  testWidgets('typed text keeps its line breaks', (tester) async {
    final t = TextItem(id: 't', x: 0, y: 0, z: 1, createdAt: testNow, wrap: 120, text: 'one two three four five six\nseven', font: 'ui', size: 20, color: const Color(0xFF000000));
    final painter = layoutText(t.text, t.font, t.size, t.wrap);
    final lines = textLines(painter, t.text);
    expect(lines.length, greaterThanOrEqualTo(3));
    expect(lines.map((l) => l.text).join(' '), 'one two three four five six seven');
    expect(lines.last.text, 'seven');
    expect(lines.first.baseline, lessThan(lines.last.baseline));
    expect(Size(painter.width, painter.height), isNot(Size.zero));
  });
}
