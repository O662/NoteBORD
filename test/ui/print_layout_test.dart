// Update 04f: Print layout (PrintLayout.png).
import 'dart:convert';

import 'package:endless/board/model.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/transfer/files.dart';
import 'package:endless/transfer/pdf_export.dart';
import 'package:endless/transfer/print_layout.dart';
import 'package:endless/ui/transfer/print_layout_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

StrokeItem _at(double x, double y) => strokeFrom([Offset(x, y), Offset(x + 40, y + 10)]);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(loadAppFonts);

  group('boxes and coverage', () {
    const a4 = PaperSize.a4;

    test('a box keeps the paper’s shape; bigger prints smaller', () {
      const b = PrintBox(0, 0, 595.28);
      expect(b.rect(a4).height, closeTo(841.89, 0.01));
      expect(b.scale(a4), closeTo(1, 0.001));
      expect(b.sized(1190.56, a4).scale(a4), closeTo(0.5, 0.001));
      const l = PrintBox(0, 0, 841.89, landscape: true);
      expect(l.rect(a4).height, closeTo(595.28, 0.01));
      expect(l.scale(a4), closeTo(1, 0.001));
      // Turned, it keeps its scale and its middle.
      final t = b.turned(a4);
      expect(t.landscape, isTrue);
      expect(t.scale(a4), closeTo(1, 0.001));
      expect(t.rect(a4).center.dx, closeTo(b.rect(a4).center.dx, 0.01));
      // Kept to 25%–400%.
      expect(b.sized(10, a4).scale(a4), closeTo(4, 0.001));
    });

    test('what isn’t covered, and Add pages for them', () {
      final page = BoardPage(id: 'p', items: [_at(100, 100), _at(160, 120), _at(2000, 2000)]);
      final layout = PrintLayout(boxes: const [PrintBox(0, 0, 595.28)]);
      expect(layout.notCovered(page).single.bounds.left, closeTo(2000, 5));
      expect(layout.contents(page).single, hasLength(2));
      final more = layout.addingFor(page);
      expect(more.boxes, hasLength(2));
      expect(more.notCovered(page), isEmpty);
    });

    test('Lay out pages for me covers everything, near things on one sheet, at real size', () {
      final page = BoardPage(id: 'p', items: [
        _at(100, 100), _at(100, 160), _at(160, 220), // one group
        _at(3000, 100), // far away
      ]);
      final l = PrintLayout.auto(page);
      expect(l.boxes, hasLength(2));
      expect(l.notCovered(page), isEmpty);
      for (final b in l.boxes) {
        expect(b.scale(l.paper), closeTo(1, 0.001));
      }
      // Something bigger than a sheet: one box, shrunk to fit.
      final big = BoardPage(id: 'p', items: [for (var y = 0.0; y < 3000; y += 50) _at(100, y)]);
      final lb = PrintLayout.auto(big);
      expect(lb.notCovered(big), isEmpty);
      expect(lb.boxes.single.scale(lb.paper), lessThan(1));
    });

    test('round trips; the sheets are the boxes', () {
      final l = PrintLayout(paper: PaperSize.letter, boxes: const [PrintBox(10, 20, 612), PrintBox(700, 20, 792, landscape: true)], numbers: false);
      final back = PrintLayout.fromJson(jsonDecode(jsonEncode(l.toJson())))!;
      expect(back.toJson(), l.toJson());
      final sheets = back.sheets();
      expect(sheets[0].area, const Rect.fromLTWH(10, 20, 612, 792));
      expect(sheets[1].size, const Size(792, 612));
    });
  });

  testWidgets('⋯ → Print…: boxes over the page; a part not on a page; add a page; print; saved with the notebook', (tester) async {
    final nb = sampleNotebook();
    // Something far off the rest.
    nb.pages[2].items.add(_at(4000, 4000));
    final store = storeWith(nb);
    final files = FakeFileTransfer();
    final c = await pumpCanvas(tester, store: store, notebookId: 'nb_sample', extra: [fileTransferProvider.overrideWithValue(files)]);
    canvasPane.goTo(2);
    await _settle(tester);
    await tester.tap(byLabel('More options'));
    await _settle(tester);
    expect(find.text('Drag page boxes over the board'), findsOneWidget);
    await tester.tap(find.text('Print…'));
    await _settle(tester);
    expect(find.byType(PrintLayoutScreen), findsOneWidget);
    expect(find.text('Print layout'), findsOneWidget);
    // Laid out for everything at first.
    expect(find.text('Everything on the board is on a page'), findsOneWidget);
    final pages = c.read(notebookProvider('nb_sample')).notebook.extra['print'] as Map;
    final saved = PrintLayout.fromJson(pages[c.read(notebookProvider('nb_sample')).pageAt(2).id])!;
    final n = saved.boxes.length;
    expect(n, greaterThanOrEqualTo(2));
    expect(find.text('Print $n pages'), findsOneWidget);

    // Remove the far page (the last, in reading order): that part isn't on a page.
    await tester.tap(find.text('Page $n'));
    await _settle(tester);
    await tester.tap(find.bySemanticsLabel('Remove page $n'));
    await _settle(tester);
    expect(find.text('1 part of the board isn’t on a page'), findsOneWidget);
    expect(find.text(n - 1 == 1 ? 'Print 1 page' : 'Print ${n - 1} pages'), findsOneWidget);
    await tester.tap(find.text('Add pages for them'));
    await _settle(tester);
    expect(find.text('Everything on the board is on a page'), findsOneWidget);
    expect(find.text('Print $n pages'), findsOneWidget);

    // The new page is picked: landscape for it; its scale note; US Letter.
    await tester.tap(find.bySemanticsLabel('Landscape'));
    await _settle(tester);
    expect(find.textContaining('of its real size'), findsOneWidget);
    await tester.tap(find.text('US Letter'));
    await _settle(tester);

    await tester.tap(find.text('Print $n pages'));
    await settleReal(tester, () => files.printed.isNotEmpty);
    final pdf = latin1.decode(files.printed.single.bytes);
    expect(pdf, startsWith('%PDF-'));
    expect(RegExp(r'/Type\s*/Page[^s]').allMatches(pdf).length, n);

    // Saved with the notebook: opening it again reuses it.
    await tester.tap(find.bySemanticsLabel('Back'));
    await _settle(tester);
    final again = PrintLayout.fromJson(
        (c.read(notebookProvider('nb_sample')).notebook.extra['print'] as Map)[c.read(notebookProvider('nb_sample')).pageAt(2).id])!;
    expect(again.paper, PaperSize.letter);
    expect(again.boxes, hasLength(n));
    expect(again.boxes.last.landscape, isTrue);
  });

  testWidgets('dragging a box moves it; its corner resizes it', (tester) async {
    final store = storeWith(sampleNotebook());
    final c = await pumpCanvas(tester, store: store, notebookId: 'nb_sample');
    canvasPane.goTo(2);
    await _settle(tester);
    await tester.tap(byLabel('More options'));
    await _settle(tester);
    await tester.tap(find.text('Print…'));
    await _settle(tester);
    PrintBox first() => PrintLayout.fromJson(
            (c.read(notebookProvider('nb_sample')).notebook.extra['print'] as Map)[c.read(notebookProvider('nb_sample')).pageAt(2).id])!
        .boxes
        .first;
    await tester.tap(find.text('Page 1'));
    await _settle(tester);
    final before = first();
    await tester.drag(find.bySemanticsLabel(RegExp(r'^Page 1: ')), const Offset(60, 40));
    await _settle(tester);
    final moved = first();
    expect(moved.left, greaterThan(before.left));
    expect(moved.top, greaterThan(before.top));
    expect(moved.width, before.width);
    await tester.drag(find.bySemanticsLabel('Resize page 1'), const Offset(50, 0));
    await _settle(tester);
    expect(first().width, greaterThan(moved.width));
    expect(tester.takeException(), isNull);
  });

  testWidgets('portrait: the panel goes under the board', (tester) async {
    await pumpCanvas(tester, store: storeWith(sampleNotebook()), notebookId: 'nb_sample', size: portraitSize);
    canvasPane.goTo(2);
    await _settle(tester);
    await tester.tap(byLabel('More options'));
    await _settle(tester);
    await tester.tap(find.text('Print…'));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Save as PDF'), findsOneWidget);
  });
}
