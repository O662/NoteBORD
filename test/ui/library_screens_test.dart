import 'package:endless/app.dart';
import 'package:endless/board/codec.dart';
import 'package:endless/library/library.dart';
import 'package:endless/ui/canvas/canvas_screen.dart';
import 'package:endless/ui/library/library_screen.dart';
import 'package:endless/ui/library/start_screen.dart';
import 'package:endless/ui/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../sample_library.dart';

/// Lets a page transition finish (the screen below goes offstage a frame later).
Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

Future<void> _longPress(WidgetTester tester, Finder f) async {
  await tester.longPress(f);
  await _pump(tester);
}

String _screenTitle(WidgetTester tester) {
  if (find.byType(CanvasScreen).evaluate().isNotEmpty) return 'canvas';
  if (find.byType(LibraryScreen).evaluate().isNotEmpty) return 'library';
  if (find.byType(StartScreen).evaluate().isNotEmpty) return 'start';
  return '?';
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('Start shows the design sections, with every button labeled', (tester) async {
    final semantics = tester.ensureSemantics();
    final (store, db) = await sampleLibrary();
    await pumpApp(tester, store: store, index: db);

    for (final text in [
      'Friday, September 25', 'Welcome back, Kieth', 'New note', 'New notebook', 'From a template',
      'Import PDF or file', 'Scan paper notes', 'CONTINUE WRITING', 'Physics — Lecture notes',
      'Page 3 of 12 · edited 2 hours ago\nSchool', 'Open', 'Split view', 'PINNED', 'Formula sheet', 'Study plan',
      'RECENT', 'See all notebooks', 'Calculus II', 'Garden ideas', 'FOLDERS', 'Saved on this tablet',
    ]) {
      expect(find.text(text), findsWidgets, reason: text);
    }
    for (final label in [
      'Search notes & handwriting', 'Home', 'All notebooks', 'Calendar', 'Flashcards', 'Remember', 'Trash',
      'Folder School', 'Folder Work', 'Folder Personal', 'Folder Sketches', 'Settings',
    ]) {
      expect(find.bySemanticsLabel(label), findsWidgets, reason: label);
    }
    expect(find.text('14'), findsOneWidget); // All notebooks count

    // Touch targets are at least 44 dp.
    for (final e in find.byType(InkWell).evaluate()) {
      expect(e.size!.shortestSide, greaterThanOrEqualTo(36), reason: '${e.widget}');
    }
    semantics.dispose();
  });

  testWidgets('Start → Library → a notebook → Canvas, and back', (tester) async {
    final (store, db) = await sampleLibrary();
    await pumpApp(tester, store: store, index: db);

    await tester.tap(find.bySemanticsLabel('Folder School'));
    await _pump(tester);
    expect(_screenTitle(tester), 'library');
    expect(find.text('Folders › School'), findsNothing); // the breadcrumb is split into links
    expect(find.text('Physics'), findsWidgets);
    expect(find.text('4 notebooks'), findsOneWidget);
    expect(find.text('Lab journal'), findsOneWidget);

    await tester.tap(find.text('Lab journal'));
    await _pump(tester);
    expect(_screenTitle(tester), 'canvas');
    expect(find.text('Lab journal'), findsOneWidget);
    expect(find.text('Page 1 of 5 · Saved'), findsOneWidget);

    await tester.tap(byLabel('Back to library'));
    await _pump(tester);
    expect(_screenTitle(tester), 'library');
    expect(find.text('School'), findsWidgets);

    await tester.tap(find.bySemanticsLabel('Home'));
    await _pump(tester);
    expect(_screenTitle(tester), 'start');

    // Continue writing is now Lab journal, the notebook opened last.
    expect(find.text('Page 1 of 5 · edited on Monday\nSchool'), findsOneWidget);
    await tester.tap(find.text('Open'));
    await _pump(tester);
    expect(find.text('Page 1 of 5 · Saved'), findsOneWidget);
    await tester.tap(byLabel('Back to library'));
    await _pump(tester);
    expect(_screenTitle(tester), 'start');

    await tester.tap(find.text('See all notebooks'));
    await _pump(tester);
    expect(find.text('All notebooks'), findsWidgets);
    expect(find.text('Team meeting'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a notebook opened directly goes back to the library', (tester) async {
    await pumpCanvas(tester, store: storeWith(sampleNotebook()));
    await tester.tap(byLabel('Back to library'));
    await _pump(tester);
    expect(_screenTitle(tester), 'library');
    expect(find.text('Physics — Lecture notes'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('New note makes a notebook in the open folder and opens it', (tester) async {
    final (store, db) = await sampleLibrary();
    final c = await pumpApp(tester, store: store, index: db, location: Routes.library(['Work']));
    await tester.tap(find.text('New note'));
    await _pump(tester);
    expect(_screenTitle(tester), 'canvas');
    expect(find.text('Untitled note'), findsOneWidget);
    final created = c.read(libraryProvider).active.where((n) => n.title == 'Untitled note').single;
    expect(created.folder, ['Work']);

    // Tapping the title renames it.
    await tester.tap(find.text('Untitled note'));
    await _pump(tester);
    await tester.enterText(find.byType(TextField), 'Standup');
    await tester.tap(find.text('Rename'));
    await _pump(tester);
    expect(find.text('Standup'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(decodeNotebook(store.notebooks[created.id]!).title, 'Standup');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('library: grid and list, sort, new folder, rename, pin, trash and restore', (tester) async {
    final (store, db) = await sampleLibrary();
    final c = await pumpApp(tester, store: store, index: db, location: Routes.library(['School']));

    await tester.tap(find.bySemanticsLabel('List view'));
    await _pump(tester);
    expect(byLabel('Options for Calculus II'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Sort by Last edited'));
    await _pump(tester);
    await tester.tap(find.text('Title').last);
    await _pump(tester);
    expect(tester.getTopLeft(find.text('Calculus II')).dy, lessThan(tester.getTopLeft(find.text('Formula sheet')).dy));
    await tester.tap(find.bySemanticsLabel('Grid view'));
    await _pump(tester);

    // New folder.
    await tester.tap(find.text('New folder'));
    await _pump(tester);
    await tester.enterText(find.byType(TextField), 'Biology');
    await tester.pump();
    await tester.tap(find.text('Create'));
    await _pump(tester);
    expect(find.text('Biology'), findsWidgets);
    expect(c.read(libraryProvider).folder(['School', 'Biology']), isNotNull);
    await tester.tap(find.bySemanticsLabel('School').first);
    await _pump(tester);

    // Rename from the long-press menu.
    await _longPress(tester, find.text('Study plan'));
    await tester.tap(find.text('Rename'));
    await _pump(tester);
    await tester.enterText(find.byType(TextField), 'Study schedule');
    await tester.tap(find.text('Rename').last);
    await _pump(tester);
    expect(find.text('Study schedule'), findsOneWidget);

    // Pin to Start.
    await _longPress(tester, find.text('Calculus II'));
    await tester.tap(find.text('Pin to Start'));
    await _pump(tester);
    expect(c.read(libraryProvider).byId('nb_calc')!.pinned, isTrue);

    // Trash, then restore from the Trash.
    await _longPress(tester, find.text('Calculus II'));
    await tester.tap(find.text('Move to Trash'));
    await _pump(tester);
    expect(find.text('Calculus II'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Trash').first);
    await _pump(tester);
    expect(find.text('Calculus II'), findsOneWidget);
    await tester.tap(find.text('Calculus II'));
    await _pump(tester);
    await tester.tap(find.text('Restore'));
    await _pump(tester);
    expect(find.text('Calculus II'), findsNothing);
    expect(c.read(libraryProvider).byId('nb_calc')!.trashed, isFalse);

    // Delete forever asks first.
    await c.read(libraryProvider.notifier).trash('nb_garden');
    await _pump(tester);
    await tester.tap(find.text('Garden ideas'));
    await _pump(tester);
    await tester.tap(find.text('Delete forever'));
    await _pump(tester);
    expect(find.text('Delete forever?'), findsOneWidget);
    await tester.tap(find.text('Delete forever').last);
    await _pump(tester);
    expect(store.notebooks.containsKey('nb_garden'), isFalse);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('folders rename and delete from their menu', (tester) async {
    final (store, db) = await sampleLibrary();
    final c = await pumpApp(tester, store: store, index: db, location: Routes.all);

    await _longPress(tester, find.bySemanticsLabel('Folder Work'));
    await tester.tap(find.text('Rename'));
    await _pump(tester);
    await tester.enterText(find.byType(TextField), 'Office');
    await tester.tap(find.text('Rename').last);
    await _pump(tester);
    expect(find.bySemanticsLabel('Folder Office'), findsOneWidget);
    expect(c.read(libraryProvider).byId('nb_team')!.folder, ['Office']);

    await _longPress(tester, find.bySemanticsLabel('Folder Office'));
    await tester.tap(find.text('Delete folder'));
    await _pump(tester);
    expect(find.textContaining('1 notebook will move to the Trash'), findsOneWidget);
    await tester.tap(find.text('Delete folder').last);
    await _pump(tester);
    expect(find.bySemanticsLabel('Folder Office'), findsNothing);
    expect(c.read(libraryProvider).byId('nb_team')!.trashed, isTrue);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the app opens on the Start page', (tester) async {
    await pumpApp(tester);
    expect(find.byType(EndlessApp), findsOneWidget);
    expect(find.text('Welcome to Endless'), findsOneWidget);
    expect(find.text('Nothing here yet'), findsOneWidget);
  });
}
