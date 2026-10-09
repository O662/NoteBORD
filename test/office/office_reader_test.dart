import 'dart:typed_data';

import 'package:endless/office/office_model.dart';
import 'package:endless/office/office_reader.dart';
import 'package:endless/office/pptx_reader.dart' show autoNumber, roman;
import 'package:endless/office/xlsx_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../office_samples.dart';

void main() {
  group('telling the files apart', () {
    test('by what is inside the zip, whatever the name', () {
      expect(officeKindOf(sampleDocx()), OfficeKind.docx);
      expect(officeKindOf(samplePptx()), OfficeKind.pptx);
      expect(officeKindOf(sampleXlsx()), OfficeKind.xlsx);
      expect(officeKindOf(Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 1, 2, 3])), isNull);
      expect(officeKindOf(Uint8List.fromList([0x50, 0x4B, 3, 4, 0, 0])), isNull);
    });

    test('a file that is not one says so', () {
      expect(() => readOffice(Uint8List.fromList([1, 2, 3, 4, 5]), OfficeKind.docx), throwsA(isA<OfficeReadError>()));
      expect(() => readOffice(sampleXlsx(), OfficeKind.pptx), throwsA(isA<OfficeReadError>()));
    });
  });

  group('Excel', () {
    test('cells as Excel shows them, with the header row found', () {
      final book = readOffice(sampleXlsx(), OfficeKind.xlsx) as Workbook;
      expect(book.sheets.map((s) => s.name), ['Sheet1', 'Dates']);
      final s = book.sheets.first;
      expect(s.header, isTrue);
      expect(s.cells, [
        ['Trial', 'm', 'v', 'p'],
        ['1', '0.50', '2.0', '1.00'],
        ['2', '0.50', '1.6', '0.80'],
        ['3', '1.00', '1.0', '1.00'],
      ]);
      expect(s.columns, 4);
      final dates = book.sheets[1];
      expect(dates.cells[1], ['9/30/2026', 'Lab report', '25%']);
      expect(dates.cells[2], ['10/14/2026', 'Midterm', '40%']);
      // Column B was made wider.
      expect(dates.columnWidths[1], greaterThan(dates.columnWidths[0]));
    });

    test('a real Excel file from disk', () {
      final book = readOffice(fixture('Lab data.xlsx'), OfficeKind.xlsx) as Workbook;
      expect(book.sheets.first.cells[2], ['2', '0.50', '1.6', '0.80']);
      // openpyxl gives dates the format yyyy-mm-dd.
      expect(book.sheets[1].cells[1].first, '2026-09-30');
    });

    test('number formats', () {
      expect(formatNumber(0.5, 'General'), '0.5');
      expect(formatNumber(12, 'General'), '12');
      expect(formatNumber(1 / 3, 'General'), '0.3333333333');
      expect(formatNumber(1234567.891, '#,##0.00'), '1,234,567.89');
      expect(formatNumber(-3.5, '0.0'), '-3.5');
      expect(formatNumber(-3.5, '#,##0.00;(#,##0.00)'), '(3.50)');
      expect(formatNumber(0.256, '0.0%'), '25.6%');
      expect(formatNumber(12.5, r'[$€-407]#,##0.00'), '€12.50');
      expect(formatNumber(12.5, r'"$"#,##0.00'), r'$12.50');
      expect(formatNumber(12345, '0.00E+00'), '1.23E+04');
      expect(formatNumber(46295, 'd-mmm-yy'), '30-Sep-26');
      expect(formatNumber(46295, 'mmmm d, yyyy'), 'September 30, 2026');
      expect(formatNumber(46295.75, 'h:mm AM/PM'), '6:00 PM');
      expect(formatNumber(46295.5104166667, 'hh:mm:ss'), '12:15:00');
      expect(formatNumber(1.5, '[h]:mm'), '36:00');
    });

    test('cell references', () {
      expect(cellRef('A1'), (0, 0));
      expect(cellRef('B12'), (11, 1));
      expect(cellRef('AA3'), (2, 26));
      expect(cellRef('12'), isNull);
    });
  });

  group('PowerPoint', () {
    test('slides with placeholders filled in from their layout and master', () {
      final deck = readOffice(fixture('Ch 9 slides.pptx'), OfficeKind.pptx) as Deck;
      expect(deck.slides, hasLength(3));
      expect(deck.width, closeTo(960, 0.1));
      expect(deck.height, closeTo(540, 0.1));
      final title = deck.slides.first.nodes.whereType<SlideShape>().first;
      expect(title.text!.text, 'Chapter 9: Momentum');
      // The title placeholder's place and size come from the layout.
      expect(title.frame.w, greaterThan(400));
      expect(title.text!.paragraphs.first.runs.first.size, 44);
      expect(title.text!.paragraphs.first.align, 'ctr');

      final body = deck.slides[1].nodes.whereType<SlideShape>().firstWhere((s) => s.text!.text.contains('Impulse ='));
      final paras = body.text!.paragraphs;
      expect(paras.map((p) => p.bullet), ['•', '–', '•']);
      expect(paras[1].indent, greaterThan(paras[0].indent));
      expect(paras.first.runs.first.size, 32);
      expect(deck.slides[1].text, contains('Same as the change in momentum'));
    });

    test('shapes, a picture and a table', () {
      final deck = readOffice(fixture('Ch 9 slides.pptx'), OfficeKind.pptx) as Deck;
      final nodes = deck.slides[2].nodes;
      final shapes = nodes.whereType<SlideShape>().toList();
      final rounded = shapes.firstWhere((s) => s.geometry == 'roundRect');
      expect(rounded.text!.text, 'Elastic: kinetic energy kept');
      // Its fill comes from the shape's style: the theme's first accent
      // (python-pptx's template has the Office 2007 theme).
      expect(rounded.fill!.color, 0xFF4F81BD);
      // Its text is white, from the style's font reference.
      expect(rounded.text!.paragraphs.first.runs.first.color, 0xFFFFFFFF);
      final oval = shapes.firstWhere((s) => s.geometry == 'ellipse');
      expect(oval.fill!.color, 0xFFF6E1D6);
      expect(oval.text!.paragraphs.first.runs.first.color, 0xFF8E4220);
      expect(nodes.whereType<SlidePicture>().single.media, startsWith('ppt/media/'));
      final table = nodes.whereType<SlideTable>().single;
      expect(table.rows, hasLength(3));
      expect(table.rows.first.cells.map((c) => c.text.text), ['Trial', 'v1', 'v2']);
      expect(table.rows.first.cells.first.fill, 0xFF4F81BD);
    });

    test('numbering', () {
      expect(autoNumber('arabicPeriod', 3), '3.');
      expect(autoNumber('alphaLcParenR', 2), 'b)');
      expect(autoNumber('romanUcPeriod', 4), 'IV.');
      expect(autoNumber('arabicParenBoth', 1), '(1)');
      expect(roman(1994), 'MCMXCIV');
    });

    test('a slide made by hand, with a group and a slide number', () {
      final deck = readOffice(samplePptx(), OfficeKind.pptx) as Deck;
      expect(deck.slides, hasLength(3));
      final s = deck.slides[2];
      final texts = s.nodes.whereType<SlideShape>().map((n) => n.text?.text).toList();
      expect(texts, contains('Slide 3'));
      // The grouped box lands where the group puts it.
      final grouped = s.nodes.whereType<SlideShape>().firstWhere((n) => n.text?.text == 'In a group');
      expect(grouped.frame.x, closeTo(100 + 50 * 0.5, 0.01));
      expect(grouped.frame.w, closeTo(100 * 0.5, 0.01));
      expect(s.background!.color, 0xFF2E3440);
    });
  });

  group('Word', () {
    test('paragraphs, headings, lists, a table and a picture', () {
      final doc = readOffice(fixture('Lab 4 report.docx'), OfficeKind.docx) as WordDoc;
      expect(doc.pageWidth, closeTo(612, 0.1));
      expect(doc.pageHeight, closeTo(792, 0.1));
      final paras = doc.blocks.whereType<WordParagraph>().map((p) => p.para).toList();
      final title = paras.first;
      expect(title.text, 'Lab 4 — Collisions');
      expect(title.runs.first.size, 26);
      final carts = paras.firstWhere((p) => p.text.startsWith('Carts'));
      expect(carts.runs.first.bold, isTrue);
      expect(carts.runs.last.bold, isFalse);
      final steps = paras.where((p) => p.bullet != null && p.bullet!.endsWith('.')).toList();
      expect(steps.map((p) => p.bullet), ['1.', '2.', '3.', '4.']);
      expect(paras.firstWhere((p) => p.text.startsWith('Friction')).bullet, '•');
      final table = doc.blocks.whereType<WordTable>().single;
      expect(table.rows[2].cells.map((c) => c.paragraphs.single.text), ['2', '0.50', '1.6', '0.80']);
      final picture = doc.blocks.whereType<WordPicture>().single;
      expect(picture.width, closeTo(144, 0.5));
    });

    test('a document made by hand: fields, page breaks, hidden and deleted text', () {
      final doc = readOffice(sampleDocx(), OfficeKind.docx) as WordDoc;
      final texts = doc.blocks.whereType<WordParagraph>().map((p) => p.para.text).toList();
      expect(texts, contains('Page 7 of the report'));
      expect(texts.join(), isNot(contains('PAGE')));
      expect(texts.join(), isNot(contains('deleted')));
      expect(texts.join(), isNot(contains('hidden')));
      expect(doc.blocks.whereType<WordPageBreak>(), hasLength(1));
      expect(doc.pageWidth, closeTo(595.3, 0.1)); // A4
    });
  });
}

Uint8List fixture(String name) => officeFixture(name);
