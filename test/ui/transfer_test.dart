import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:endless/board/codec.dart';
import 'package:endless/board/lock.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/library/library.dart';
import 'package:endless/transfer/board_file.dart';
import 'package:endless/transfer/files.dart';
import 'package:endless/transfer/pdf_import.dart';
import 'package:endless/ui/canvas/canvas_screen.dart';
import 'package:endless/ui/dialogs.dart';
import 'package:endless/ui/routes.dart';
import 'package:endless/ui/transfer/transfer_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../transfer/everything.dart';

Finder _primary(String label) => find.widgetWithText(PrimaryButton, label);

bool _enabled(WidgetTester t, String label) => t.widget<PrimaryButton>(_primary(label)).onPressed != null;

Future<void> _more(WidgetTester t, String item) async {
  await t.tap(byLabel('More options'));
  await t.pump();
  await t.tap(find.text(item));
  await t.pumpAndSettle();
}

/// The sample notebook (4 pages, ink on page 3) open on page 3, with fake
/// files.
Future<(ProviderContainer, FakeFileTransfer, MemoryBoardStore)> _canvas(WidgetTester t, {MemoryBoardStore? store}) async {
  final files = FakeFileTransfer();
  final s = store ?? storeWith(sampleNotebook());
  final c = await pumpCanvas(t, store: s, notebookId: 'nb_sample', extra: [
    fileTransferProvider.overrideWithValue(files),
    pdfReaderProvider.overrideWithValue(FakePdfReader()),
    decodeAs(testPicture()),
  ]);
  canvasPane.goTo(2);
  await t.pump();
  return (c, files, s);
}

Set<String> _zipNames(Uint8List bytes) => {for (final f in ZipDecoder().decodeBytes(bytes).files) f.name};

void main() {
  setUpAll(loadAppFonts);

  group('Export', () {
    testWidgets('⋯ → Export: this page as a PDF, saved to the tablet', (tester) async {
      final (_, files, _) = await _canvas(tester);
      await _more(tester, 'Export');
      for (final text in ['WHAT TO EXPORT', 'This page', 'Page 3', 'Some pages', 'Pick pages', 'Whole notebook', '4 pages', 'PDF document', 'Board file (.board)', 'Fit page to its ink', 'Make handwriting searchable inside the PDF', 'Include the dot-grid background', 'This tablet', 'Google Drive', 'OneDrive', 'Share…']) {
        expect(find.text(text), findsOneWidget, reason: text);
      }

      // Cancelled in the Save dialog: nothing happens and it stays open.
      files.saveAnswer = false;
      await tester.tap(_primary('Export PDF'));
      await settleReal(tester, () => _enabled(tester, 'Export PDF'));
      expect(files.saved, isEmpty);
      expect(find.text('WHAT TO EXPORT'), findsOneWidget);

      files.saveAnswer = true;
      await tester.tap(_primary('Export PDF'));
      await settleReal(tester, () => files.saved.isNotEmpty && find.text('WHAT TO EXPORT').evaluate().isEmpty);
      final pdf = files.saved.single;
      expect(pdf.name, 'Physics — Lecture notes — page 3.pdf');
      expect(pdf.mime, 'application/pdf');
      expect(latin1.decode(pdf.bytes.sublist(0, 5)), '%PDF-');
      expect(find.text('Saved Physics — Lecture notes — page 3.pdf'), findsOneWidget);
    });

    testWidgets('the whole notebook as a board file, through the share sheet', (tester) async {
      final (_, files, _) = await _canvas(tester);
      await _more(tester, 'Export');
      await tester.tap(find.text('Whole notebook'));
      await tester.tap(find.text('Board file (.board)'));
      await tester.pump();
      expect(find.text('Include images and attached PDFs'), findsOneWidget);
      expect(find.text('Fit page to its ink'), findsNothing);
      await tester.tap(find.text('Share…'));
      await tester.tap(_primary('Export board file'));
      await settleReal(tester, () => files.shared.isNotEmpty);
      final board = files.shared.single;
      expect(board.name, 'Physics — Lecture notes.board');
      expect(_zipNames(board.bytes), containsAll(['notebook.json', 'pages/pg_01.json', 'pages/pg_03.json', 'pages/pg_04.json']));
    });

    testWidgets('some pages: pick them, and only they go', (tester) async {
      final (_, files, _) = await _canvas(tester);
      await _more(tester, 'Export');
      await tester.tap(find.text('Some pages'));
      await tester.pumpAndSettle();
      expect(find.text('Pick pages'), findsWidgets);
      expect(find.text('1 page'), findsOneWidget, reason: 'the page you are on is picked');
      final picker = find.byWidgetPredicate((w) => w is DialogFrame && w.title == 'Pick pages');
      await tester.tap(find.descendant(of: picker, matching: find.text('1')));
      await tester.tap(find.descendant(of: picker, matching: find.text('2')));
      await tester.pump();
      expect(find.text('3 pages'), findsOneWidget);
      await tester.tap(find.descendant(of: picker, matching: find.text('Done')));
      await tester.pumpAndSettle();
      expect(find.text('Pages 1–3'), findsOneWidget);

      await tester.tap(find.text('Board file (.board)'));
      await tester.pump();
      await tester.tap(_primary('Export board file'));
      await settleReal(tester, () => files.saved.isNotEmpty);
      expect(files.saved.single.name, 'Physics — Lecture notes — 3 pages.board');
      final names = _zipNames(files.saved.single.bytes);
      expect(names, containsAll(['pages/pg_01.json', 'pages/pg_02.json', 'pages/pg_03.json']));
      expect(names, isNot(contains('pages/pg_04.json')));
    });

    testWidgets('a locked page can’t go out as a PDF, but can as a board file; Drive says when it comes', (tester) async {
      final store = storeWith(sampleNotebook());
      final (entry, key) = await testCrypto.create('secret');
      await store.saveSealedPage('nb_sample', 'pg_04', await testCrypto.seal(key, encodePage(BoardPage(id: 'pg_04'))));
      await store.saveLock('nb_sample', LockFile(pages: {'pg_04': entry}).toJson());
      final (_, files, _) = await _canvas(tester, store: store);
      // A locked page shows only its unlock card, so pick it from page 3.
      await _more(tester, 'Export');
      await tester.tap(find.text('Some pages'));
      await tester.pumpAndSettle();
      final picker = find.byWidgetPredicate((w) => w is DialogFrame && w.title == 'Pick pages');
      await tester.tap(find.descendant(of: picker, matching: find.text('3')));
      await tester.tap(find.descendant(of: picker, matching: find.text('4')));
      await tester.pump();
      await tester.tap(find.descendant(of: picker, matching: find.text('Done')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Page 4 is locked'), findsOneWidget);
      expect(_enabled(tester, 'Export PDF'), isFalse);
      await tester.tap(find.text('Board file (.board)'));
      await tester.pump();
      expect(_enabled(tester, 'Export board file'), isTrue);

      await tester.tap(find.text('Google Drive'));
      await tester.pump();
      expect(find.textContaining('Google Drive comes with cloud sync'), findsOneWidget);

      await tester.tap(_primary('Export board file'));
      await settleReal(tester, () => files.saved.isNotEmpty);
      expect(_zipNames(files.saved.single.bytes), containsAll(['pages/pg_04.json.enc', 'lock.json']));
    });
  });

  group('Share', () {
    testWidgets('Share sends a copy: PDF and Board file open Export ready to go', (tester) async {
      await _canvas(tester);
      await tester.tap(byLabel('Share'));
      await tester.pumpAndSettle();
      expect(find.text('Export a copy'), findsOneWidget);
      expect(find.textContaining('Save or send it as a file', findRichText: true), findsOneWidget);
      expect(find.textContaining('come with cloud sync'), findsOneWidget);
      await tester.tap(find.text('Board file'));
      await tester.pumpAndSettle();
      expect(find.text('Export a copy'), findsNothing);
      expect(_primary('Export board file'), findsOneWidget);
      expect(find.text('Include images and attached PDFs'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();

      await tester.tap(byLabel('Share'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PDF'));
      await tester.pumpAndSettle();
      expect(_primary('Export PDF'), findsOneWidget);
    });

    testWidgets('Image saves this page as a picture', (tester) async {
      final (_, files, _) = await _canvas(tester);
      await tester.tap(byLabel('Share'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Image'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save to this tablet'));
      await settleReal(tester, () => files.saved.isNotEmpty);
      final png = files.saved.single;
      expect(png.name, 'Physics — Lecture notes — page 3.png');
      expect(png.bytes.sublist(1, 4), 'PNG'.codeUnits);
      await tester.pumpAndSettle();
      expect(find.text('Export a copy'), findsNothing);
      expect(find.text('Saved Physics — Lecture notes — page 3.png'), findsOneWidget);
    });
  });

  testWidgets('⋯ → Print sends the notebook to the print dialog', (tester) async {
    final (_, files, _) = await _canvas(tester);
    await tester.tap(byLabel('More options'));
    await tester.pump();
    await tester.tap(find.text('Print'));
    await tester.pump();
    await settleReal(tester, () => files.printed.isNotEmpty);
    expect(files.printed.single.name, 'Physics — Lecture notes.pdf');
    final text = latin1.decode(files.printed.single.bytes);
    expect(text, startsWith('%PDF-'));
  });

  group('Import', () {
    testWidgets('Start → Import PDF or file: a PDF becomes a notebook, a page per PDF page', (tester) async {
      final files = FakeFileTransfer();
      final store = MemoryBoardStore();
      final c = await pumpApp(tester, store: store, extra: [
        fileTransferProvider.overrideWithValue(files),
        pdfReaderProvider.overrideWithValue(FakePdfReader(pages: const [Size(612, 792), Size(595, 842), Size(792, 612)])),
      ]);
      await tester.tap(find.text('Import PDF or file'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a PDF, image or .board file'), findsOneWidget);
      expect(find.text('From this tablet, Google Drive or OneDrive'), findsOneWidget);
      expect(find.descendant(of: find.byType(TransferDialog), matching: find.text('All notebooks')), findsOneWidget);
      expect(find.text('Export'), findsNothing, reason: 'nothing to export from the library');
      expect(_enabled(tester, 'Import'), isFalse);

      files.toPick = [PickedFile('Lecture 3.pdf', fakePdfBytes())];
      await tester.tap(_primary('Browse files'));
      await tester.pump();
      expect(find.text('Lecture 3.pdf'), findsOneWidget);
      expect(find.textContaining('PDF ·'), findsOneWidget);
      await tester.tap(_primary('Import'));
      await settleReal(tester, () => find.byType(CanvasScreen).evaluate().isNotEmpty);

      final entry = c.read(libraryProvider).notebooks.single;
      expect(entry.title, 'Lecture 3');
      final loaded = (await store.loadNotebook(entry.id))!;
      expect(loaded.pages, hasLength(3));
      final first = loaded.pages.first.items.single as FileItem;
      expect((first.w, first.h, first.page, first.mime, first.text, first.name), (612.0, 792.0, 1, 'pdf', 'Page 1', 'Lecture 3.pdf'));
      expect((loaded.pages.last.items.single as FileItem).w, 792);
      // The PDF once, and a picture of each page.
      expect(await store.listAssets(entry.id), hasLength(4));
      expect(await store.loadAsset(entry.id, first.asset), fakePdfBytes());
      // On the Start page and the notebook while one slides over the other.
      expect(find.text('Imported “Lecture 3”'), findsWidgets);
    });

    testWidgets('⋯ → Import into this notebook: PDF pages after this page, pictures on it', (tester) async {
      final (c, files, store) = await _canvas(tester);
      await _more(tester, 'Import');
      expect(find.text('This notebook'), findsOneWidget);
      files.toPick = [PickedFile('Handout.pdf', fakePdfBytes()), PickedFile('photo.png', fakePng(3))];
      await tester.tap(_primary('Browse files'));
      await tester.pump();
      expect(find.text('2 files'), findsOneWidget);
      await tester.tap(_primary('Import'));
      await settleReal(tester, () => find.text('WHAT TO EXPORT').evaluate().isEmpty && find.text('Browse files').evaluate().isEmpty && find.textContaining('Added').evaluate().isNotEmpty);

      final nb = shownNotebook(c);
      expect(nb.pages, hasLength(6));
      expect(canvasPane.page, 3, reason: 'the first new page, right after page 3');
      expect(nb.pages[3].items.single, isA<FileItem>());
      expect(nb.pages[4].items.single, isA<FileItem>());
      expect(nb.pages[2].items.whereType<ImageItem>(), hasLength(1), reason: 'the picture went on page 3');
      expect(find.text('Added 2 pages · Added 1 picture'), findsOneWidget);
      // Saved within a second.
      await tester.pump(const Duration(seconds: 1));
      final saved = (await store.loadNotebook('nb_sample'))!;
      expect(saved.notebook.pageIds, hasLength(6));
    });

    testWidgets('Library → Import: a board file comes back whole, into the folder shown', (tester) async {
      final (source, _) = await everythingNotebook();
      final bytes = await exportBoardFile(source, 'nb_board');
      final files = FakeFileTransfer()..toPick = [PickedFile('Physics — Lab 4.board', bytes)];
      final store = MemoryBoardStore();
      final c = await pumpApp(tester, store: store, location: Routes.library(const ['School', 'Physics']), extra: [
        fileTransferProvider.overrideWithValue(files),
        decodeAs(testPicture()),
      ]);
      // An empty folder still shows: it holds the notebook below.
      await c.read(libraryProvider.notifier).createFolder(const [], 'School');
      await c.read(libraryProvider.notifier).createFolder(const ['School'], 'Physics');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SecondaryButton, 'Import'));
      await tester.pumpAndSettle();
      expect(find.text('School › Physics'), findsOneWidget);
      await tester.tap(_primary('Browse files'));
      await tester.pump();
      await tester.tap(_primary('Import'));
      await settleReal(tester, () => find.byType(CanvasScreen).evaluate().isNotEmpty);

      final entry = c.read(libraryProvider).notebooks.single;
      expect(entry.title, 'Physics — Lab 4');
      expect(entry.folder, ['School', 'Physics']);
      final before = (await source.loadNotebook('nb_board'))!;
      final after = (await store.loadNotebook(entry.id))!;
      for (final (i, page) in before.pages.indexed) {
        if (before.sealed.containsKey(page.id)) {
          expect(after.sealed[page.id], before.sealed[page.id]);
        } else {
          expect(encodePage(after.pages[i]), encodePage(page));
        }
      }
      expect((await store.listAssets(entry.id)).toSet(), (await source.listAssets('nb_board')).toSet());
    });

    testWidgets('a file it can’t import, or a PDF with a password, says so and stays open', (tester) async {
      final files = FakeFileTransfer()..toPick = [PickedFile('notes.txt', Uint8List.fromList(utf8.encode('hello')))];
      await pumpApp(tester, extra: [
        fileTransferProvider.overrideWithValue(files),
        pdfReaderProvider.overrideWithValue(FakePdfReader(password: true)),
      ]);
      await tester.tap(find.text('Import PDF or file'));
      await tester.pumpAndSettle();
      await tester.tap(_primary('Browse files'));
      await tester.pump();
      expect(find.textContaining('Can’t import'), findsOneWidget);
      await tester.tap(_primary('Import'));
      await settleReal(tester, () => find.textContaining('isn’t a PDF').evaluate().isNotEmpty);
      expect(find.text('“notes.txt” isn’t a PDF, a picture or a board file.'), findsOneWidget);

      files.toPick = [PickedFile('locked.pdf', fakePdfBytes())];
      await tester.tap(_primary('Choose other files'));
      await tester.pump();
      await tester.tap(_primary('Import'));
      await settleReal(tester, () => find.textContaining('password').evaluate().isNotEmpty);
      expect(find.text('Choose other files'), findsOneWidget);
    });

    testWidgets('Import into: this notebook, all notebooks or a folder', (tester) async {
      final (c, files, store) = await _canvas(tester);
      await c.read(libraryProvider.notifier).createFolder(const [], 'Archive');
      await _more(tester, 'Import');
      await tester.tap(find.bySemanticsLabel('Import into This notebook'));
      await tester.pumpAndSettle();
      expect(find.text('PDF pages after this page, pictures on it'), findsOneWidget);
      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();
      expect(find.text('Archive'), findsOneWidget);

      files.toPick = [PickedFile('Scan.pdf', fakePdfBytes(4))];
      await tester.tap(_primary('Browse files'));
      await tester.pump();
      await tester.tap(_primary('Import'));
      await settleReal(tester, () => c.read(libraryProvider).notebooks.length == 2);
      final made = c.read(libraryProvider).notebooks.firstWhere((n) => n.id != 'nb_sample');
      expect(made.title, 'Scan');
      expect(made.folder, ['Archive']);
      expect((await store.loadNotebook(made.id))!.pages, hasLength(2));
    });
  });
}
