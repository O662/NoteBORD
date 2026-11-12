import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:endless/board/codec.dart';
import 'package:endless/board/lock.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/library/library.dart';
import 'package:endless/sync/cloud.dart';
import 'package:endless/transfer/board_file.dart';
import 'package:endless/transfer/files.dart';
import 'package:endless/transfer/incoming.dart';
import 'package:endless/transfer/share.dart';
import 'package:endless/transfer/transfer.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/transfer/pdf_import.dart';
import 'package:endless/ui/canvas/canvas_screen.dart';
import 'package:endless/ui/dialogs.dart';
import 'package:endless/ui/routes.dart';
import 'package:endless/ui/transfer/transfer_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:endless/study/study_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../sync/sync_app_helpers.dart';
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
Future<(ProviderContainer, FakeFileTransfer, MemoryBoardStore)> _canvas(WidgetTester t,
    {MemoryBoardStore? store, List<Override> extra = const []}) async {
  final files = FakeFileTransfer();
  final s = store ?? storeWith(sampleNotebook());
  final c = await pumpCanvas(t, store: s, notebookId: 'nb_sample', extra: [
    fileTransferProvider.overrideWithValue(files),
    pdfReaderProvider.overrideWithValue(FakePdfReader()),
    decodeAs(testPicture()),
    ...extra,
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
    /// The sample with page 4 sealed under its own password.
    Future<MemoryBoardStore> lockedStore() async {
      final store = storeWith(sampleNotebook());
      final (entry, key) = await testCrypto.create('secret');
      await store.saveSealedPage('nb_sample', 'pg_04', await testCrypto.seal(key, encodePage(BoardPage(id: 'pg_04'))));
      await store.saveLock('nb_sample', LockFile(pages: {'pg_04': entry}).toJson());
      return store;
    }

    testWidgets('Share a copy: the board file leaves out the page with a password and says so', (tester) async {
      final (_, files, _) = await _canvas(tester, store: await lockedStore());
      await tester.tap(byLabel('Share'));
      await tester.pumpAndSettle();
      expect(find.text('Share a copy'), findsOneWidget);
      expect(find.text('Coming later'), findsOneWidget);
      expect(find.text('Invite people and write together'), findsOneWidget);
      for (final t in ['This page', 'Notebook', 'Folder', 'Board file', 'Image', 'Share sheet', 'Google Drive', 'OneDrive', 'Save to tablet']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.text('PDF'), findsNWidgets(2), reason: 'the badge and the name');
      // Notebook (the default): page 4 has a password.
      expect(find.text('Page 4 is locked, so it won’t be included.'), findsOneWidget);
      expect(find.textContaining('Physics — Lecture notes · 3 pages · about'), findsOneWidget);
      await tester.tap(find.text('Board file'));
      await tester.pump();
      expect(find.text('Include audio and video'), findsOneWidget);
      await tester.tap(find.text('Share…'));
      await settleReal(tester, () => files.shared.isNotEmpty);
      final board = _zipNames(files.shared.single.bytes);
      expect(board, containsAll(['pages/pg_01.json', 'pages/pg_03.json']));
      expect(board.where((n) => n.contains('pg_04')), isEmpty);
      expect(board, isNot(contains('lock.json')));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 page with a password was left out'), findsOneWidget);
    });

    testWidgets('a PDF of the notebook; an image only for This page', (tester) async {
      final (_, files, _) = await _canvas(tester);
      await tester.tap(byLabel('Share'));
      await tester.pumpAndSettle();
      // PDF is picked to begin with, with its two options on.
      expect(find.text('Make handwriting searchable'), findsOneWidget);
      expect(find.text('Recommended'), findsOneWidget);
      expect(find.text('Include the dot paper background'), findsOneWidget);
      // Image is greyed out for a notebook.
      await tester.tap(find.text('Image'));
      await tester.pump();
      expect(find.text('Make handwriting searchable'), findsOneWidget, reason: 'still the PDF');
      await tester.tap(find.text('Share…'));
      await settleReal(tester, () => files.shared.isNotEmpty);
      expect(files.shared.single.name, 'Physics — Lecture notes.pdf');
      expect(utf8.decode(files.shared.single.bytes.sublist(0, 5)), '%PDF-');
      await tester.pumpAndSettle();

      await tester.tap(byLabel('Share'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('This page'));
      await tester.pump();
      await tester.tap(find.text('Image'));
      await tester.pump();
      await tester.tap(find.text('Share…'));
      await settleReal(tester, () => files.shared.length == 2);
      expect(files.shared.last.name, 'Physics — Lecture notes — page 3.png');
      expect(files.shared.last.bytes.sublist(1, 4), 'PNG'.codeUnits);
      // Back to Notebook: the image isn't kept.
      await tester.pumpAndSettle();
    });

    testWidgets('Save to tablet goes through the file picker', (tester) async {
      final (_, files, _) = await _canvas(tester);
      await tester.tap(byLabel('Share'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save to tablet'));
      await tester.pump();
      expect(find.text('You pick where on the tablet, such as Downloads.'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await settleReal(tester, () => files.saved.isNotEmpty);
      expect(files.saved.single.name, 'Physics — Lecture notes.pdf');
      expect(files.shared, isEmpty);
    });

    testWidgets('Google Drive: the copy goes to Shared copies in Endless’s folder', (tester) async {
      final cloud = MemoryCloud();
      final store = storeWith(sampleNotebook());
      syncingWithGoogle(store);
      final (_, files, _) = await _canvas(tester, store: store, extra: syncOverrides(cloud));
      await tester.tap(byLabel('Share'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Google Drive'));
      await tester.pump();
      await tester.tap(find.text('Board file'));
      await tester.pump();
      await tester.tap(find.text('Save to Drive'));
      await settleReal(tester, () => cloud.files.containsKey('Shared copies/Physics — Lecture notes.board'));
      expect(files.shared, isEmpty);
      await tester.pumpAndSettle();
      expect(find.textContaining('Saved Physics — Lecture notes.board to Google Drive › Shared copies'), findsOneWidget);
    });

    testWidgets('without “Include audio and video” a board file leaves recordings out', (tester) async {
      final nb = sampleNotebook();
      nb.pages[2].items.add(AudioItem(id: 'au_1', x: 10, y: 10, z: 99, createdAt: DateTime.utc(2026, 9, 25), asset: 'rec.m4a', name: 'Lecture', recordedAt: DateTime.utc(2026, 9, 25), durationMs: 1000));
      final store = storeWith(nb);
      await store.saveAsset('nb_sample', 'rec.m4a', Uint8List.fromList(List.filled(64, 7)));
      final (_, files, _) = await _canvas(tester, store: store);
      await tester.tap(byLabel('Share'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Board file'));
      await tester.pump();
      await tester.tap(find.text('Share…'));
      await settleReal(tester, () => files.shared.isNotEmpty);
      expect(_zipNames(files.shared.single.bytes), isNot(contains('assets/rec.m4a')));
      await tester.pumpAndSettle();

      await tester.tap(byLabel('Share'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Board file'));
      await tester.pump();
      await tester.tap(find.text('Include audio and video'));
      await tester.pump();
      await tester.tap(find.text('Share…'));
      await settleReal(tester, () => files.shared.length == 2);
      expect(_zipNames(files.shared.last.bytes), contains('assets/rec.m4a'));
    });

    testWidgets('This page, on a page with a password: nothing can be sent', (tester) async {
      // Share isn't shown on a locked page (only its unlock card is), and the
      // copies refuse it anyway.
      final (c, _, _) = await _canvas(tester, store: await lockedStore());
      final error = await tester.runAsync(() async {
        try {
          await c.read(transfersProvider).shareCopies('nb_sample', ShareScope.page, ExportFormat.pdf, current: 3);
          return null;
        } on ExportProblem catch (e) {
          return e.message;
        }
      });
      expect(error, 'This page has a password, so it can’t be shared.');
    });

    testWidgets('a page with a password stays out even while it\'s unlocked', (tester) async {
      final (c, _, _) = await _canvas(tester, store: await lockedStore());
      final nb = c.read(notebookProvider('nb_sample').notifier);
      expect(await tester.runAsync(() => nb.unlock('pg_04', 'secret')), isTrue);
      await tester.pump();
      final state = c.read(notebookProvider('nb_sample'));
      expect(state.isSealed('pg_04'), isFalse);
      expect(shareablePageIds(state), {'pg_01', 'pg_02', 'pg_03'});
    });

    testWidgets('Folder: a copy of each notebook in it', (tester) async {
      final store = storeWith(sampleNotebook());
      final other = Notebook(
        id: 'nb_other',
        title: 'Lab journal',
        folderPath: ['School', 'Physics'],
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 2),
        pageIds: ['pg_x'],
      );
      await store.savePage('nb_other', BoardPage(id: 'pg_x'));
      await store.saveNotebook(other);
      final (_, files, _) = await _canvas(tester, store: store);
      await tester.tap(byLabel('Share'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Folder'));
      await tester.pump();
      expect(find.textContaining('School › Physics · 2 notebooks'), findsOneWidget);
      await tester.tap(find.text('Board file'));
      await tester.pump();
      await tester.tap(find.text('Share…'));
      await settleReal(tester, () => files.shared.length >= 2);
      expect({for (final f in files.shared) f.name}, {'Physics — Lecture notes.board', 'Lab journal.board'});
    });
  });

  testWidgets('a board file opened with Endless from another app is imported and opened', (tester) async {
    final source = storeWith(sampleNotebook());
    final bytes = await tester.runAsync(() => exportBoardFile(source, 'nb_sample'));
    final incoming = _FakeIncoming([PickedFile('Lecture notes', bytes!)]);
    final store = MemoryBoardStore();
    await pumpApp(tester, store: store, extra: [incomingFilesProvider.overrideWithValue(incoming)]);
    await tester.pumpAndSettle();
    expect(store.notebooks, contains('nb_sample'));
    expect(find.byType(CanvasScreen), findsOneWidget);
    expect(find.text('Imported “Physics — Lecture notes”'), findsOneWidget);

    // The same one again (sent back with changes): Replace or Keep both.
    incoming.files.add(PickedFile('Lecture notes.board', bytes));
    incoming.arrived!();
    await tester.pumpAndSettle();
    expect(find.text('Replace'), findsOneWidget);
    await tester.tap(find.text('Keep both'));
    await tester.pumpAndSettle();
    expect(store.notebooks.length, 2);
  });

  testWidgets('a file that isn\'t a board file says so', (tester) async {
    final incoming = _FakeIncoming([PickedFile('notes.txt', Uint8List.fromList(utf8.encode('hello')))]);
    await pumpApp(tester, extra: [incomingFilesProvider.overrideWithValue(incoming)]);
    await tester.pumpAndSettle();
    expect(find.text('Can’t open this file'), findsOneWidget);
  });

  test('a board file whose name lost its ending is still a board file', () async {
    final bytes = await exportBoardFile(storeWith(sampleNotebook()), 'nb_sample');
    expect(importKindOf(PickedFile('Attachment', bytes)), ImportKind.board);
    expect(importKindOf(PickedFile('Attachment', Uint8List.fromList([0x50, 0x4B, 3, 4, 0, 0]))), ImportKind.unknown);
  });

  testWidgets('⋯ → Print… lays the page out, and Print sends it to the print dialog', (tester) async {
    final (_, files, _) = await _canvas(tester);
    await tester.tap(byLabel('More options'));
    await tester.pump();
    await tester.tap(find.text('Print…'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.textContaining(RegExp(r'^Print \d+ pages?$')));
    await tester.pump();
    await settleReal(tester, () => files.printed.isNotEmpty);
    expect(files.printed.single.name, 'Physics — Lecture notes — page 3.pdf');
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
      expect(find.text('Choose a PDF, image, Office or .board file'), findsOneWidget);
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

      // Owner, 2026-10-27: an imported notebook's flashcards and what's
      // remembered show straight away, not after a restart.
      c.listen(studyProvider, (_, _) {});
      await settleReal(tester, () => c.read(studyProvider)?.cards.isNotEmpty ?? false);
      final study = c.read(studyProvider)!;
      expect(study.cards.single.id, 'fc_1');
      expect(study.cards.single.notebookId, entry.id);
      expect(study.remembered.single.id, 'rm_1');
    });

    // Owner, 2026-10-27: importing a notebook that's already here asks
    // whether to replace it, instead of always making a copy.
    group('a notebook already here', () {
      /// The sample notebook, pinned, with a picture; and a board file of
      /// it with a page fewer and a new title.
      Future<(MemoryBoardStore, Uint8List)> setUp() async {
        final store = storeWith(sampleNotebook());
        final nb = (await store.loadNotebook('nb_sample'))!.notebook..pinned = true;
        await store.saveNotebook(nb);
        await store.saveAsset('nb_sample', 'old.png', Uint8List.fromList([1]));
        final other = storeWith(sampleNotebook());
        await other.saveNotebook(Notebook(
          id: 'nb_sample',
          title: 'Physics — backup',
          folderPath: const ['Elsewhere'],
          createdAt: nb.createdAt,
          updatedAt: nb.updatedAt,
          pageIds: nb.pageIds.take(3).toList(),
        ));
        return (store, await exportBoardFile(other, 'nb_sample'));
      }

      Future<ProviderContainer> importIt(WidgetTester tester, MemoryBoardStore store, Uint8List bytes) async {
        final files = FakeFileTransfer()..toPick = [PickedFile('Physics.board', bytes)];
        final c = await pumpApp(tester, store: store, location: Routes.library(const ['School', 'Physics']), extra: [
          fileTransferProvider.overrideWithValue(files),
          decodeAs(testPicture()),
        ]);
        await tester.tap(find.widgetWithText(SecondaryButton, 'Import'));
        await tester.pumpAndSettle();
        await tester.tap(_primary('Browse files'));
        await tester.pump();
        await tester.tap(_primary('Import'));
        await settleReal(tester, () => find.text('“Physics — Lecture notes” is already here').evaluate().isNotEmpty);
        return c;
      }

      testWidgets('Replace puts the file in its place, where it was', (tester) async {
        final (store, bytes) = await setUp();
        final c = await importIt(tester, store, bytes);
        await tester.tap(_primary('Replace'));
        await settleReal(tester, () => find.byType(CanvasScreen).evaluate().isNotEmpty);

        final entry = c.read(libraryProvider).notebooks.single;
        expect(entry.id, 'nb_sample');
        expect(entry.title, 'Physics — backup');
        expect(entry.folder, ['School', 'Physics'], reason: 'it stays where it was');
        expect(entry.pinned, isTrue);
        expect(entry.pageCount, 3);
        expect(await store.listAssets('nb_sample'), isNot(contains('old.png')));
        expect(find.text('Replaced “Physics — backup”'), findsWidgets);
      });

      testWidgets('replacing the notebook that’s open shows what came in', (tester) async {
        final (store, bytes) = await setUp();
        final (c, files, _) = await _canvas(tester, store: store);
        await _more(tester, 'Import');
        files.toPick = [PickedFile('Physics.board', bytes)];
        await tester.tap(_primary('Browse files'));
        await tester.pump();
        await tester.tap(_primary('Import'));
        await settleReal(tester, () => find.text('Replace').evaluate().isNotEmpty);
        await tester.tap(_primary('Replace'));
        await settleReal(tester, () => find.byType(CanvasScreen).evaluate().isNotEmpty && find.text('Browse files').evaluate().isEmpty);
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();

        expect(shownNotebook(c).pages, hasLength(3));
        expect(shownNotebook(c).notebook.title, 'Physics — backup');
        final saved = (await store.loadNotebook('nb_sample'))!;
        expect(saved.notebook.pageIds, hasLength(3), reason: 'the open copy didn’t write the old pages back');
        expect(c.read(libraryProvider).notebooks, hasLength(1));
      });

      testWidgets('Cancel imports nothing; Keep both makes a copy', (tester) async {
        final (store, bytes) = await setUp();
        final c = await importIt(tester, store, bytes);
        await tester.tap(find.widgetWithText(SecondaryButton, 'Cancel').last);
        await tester.pumpAndSettle();
        expect(find.text('Nothing was imported'), findsOneWidget);
        expect(c.read(libraryProvider).notebooks, hasLength(1));
        expect((await store.loadNotebook('nb_sample'))!.notebook.pageIds, hasLength(4));

        await tester.tap(find.widgetWithText(SecondaryButton, 'Import'));
        await tester.pumpAndSettle();
        await tester.tap(_primary('Browse files'));
        await tester.pump();
        await tester.tap(_primary('Import'));
        await settleReal(tester, () => find.text('Keep both').evaluate().isNotEmpty);
        await tester.tap(find.widgetWithText(SecondaryButton, 'Keep both'));
        await settleReal(tester, () => find.byType(CanvasScreen).evaluate().isNotEmpty);
        final ids = {for (final n in c.read(libraryProvider).notebooks) n.id};
        expect(ids, hasLength(2));
        expect(ids, contains('nb_sample'));
        expect((await store.loadNotebook('nb_sample'))!.notebook.pageIds, hasLength(4), reason: 'the one here is untouched');
      });
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
      expect(find.text('“notes.txt” isn’t a PDF, a picture, an Office file or a board file.'), findsOneWidget);

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
      expect(find.text('PDF pages after this page, pictures and Office files on it'), findsOneWidget);
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

/// Files "opened with Endless", handed over as Android would.
class _FakeIncoming implements IncomingFiles {
  _FakeIncoming(List<PickedFile> files) : files = [...files];

  final List<PickedFile> files;
  void Function()? arrived;

  @override
  Future<List<PickedFile>> take() async {
    final out = [...files];
    files.clear();
    return out;
  }

  @override
  void listen(void Function() onArrived) => arrived = onArrived;
}
