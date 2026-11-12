import 'package:endless/board/codec.dart';
import 'package:endless/board/model.dart';
import 'package:endless/library/library.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/sync/cloud.dart';
import 'package:endless/sync/sync_state.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:endless/ui/canvas/canvas_screen.dart';
import 'package:endless/ui/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../sample_library.dart';
import '../sync/sync_app_helpers.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(find.bySemanticsLabel(label).hitTestable().first);
  await _pump(tester);
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('no name: the button is Skip for now; a name makes it Create note', (tester) async {
    final (store, db) = await sampleLibrary();
    final c = await pumpApp(tester, store: store, index: db);
    await tester.tap(find.text('New note').first);
    await _pump(tester);
    expect(find.text('Skip for now'), findsOneWidget);
    expect(find.text('Create note'), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'Lab 4');
    await tester.pump();
    expect(find.text('Create note'), findsOneWidget);
    expect(find.text('Skip for now'), findsNothing);
    // Only spaces count as no name.
    await tester.enterText(find.byType(TextField).first, '   ');
    await tester.pump();
    expect(find.text('Skip for now'), findsOneWidget);

    // Skip: "Untitled note" on this tablet, on the paper picked, Not set up.
    await _tap(tester, 'Grid paper');
    await _tap(tester, 'Skip for now');
    expect(find.byType(CanvasScreen), findsOneWidget);
    expect(find.textContaining('Finish setting up'), findsOneWidget);
    final made = c.read(libraryProvider).active.firstWhere((n) => n.title == 'Untitled note');
    expect(made.setupPending, isTrue);
    expect(made.saveTo, 'device');
    expect(decodeNotebook(store.notebooks[made.id]!).defaultPaper, Paper.grid);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('New note: a name, a nested new folder, This tablet only, Grid paper, a cover; "Will be saved as"', (tester) async {
    final (store, db) = await sampleLibrary();
    final c = await pumpApp(tester, store: store, index: db);
    await tester.tap(find.text('New note').first);
    await _pump(tester);
    expect(find.text('Write it with the S Pen or type. You can rename it any time.'), findsOneWidget);
    expect(find.text('This tablet › Untitled note'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Momentum review');
    await _tap(tester, 'Folder School');
    expect(find.text('This tablet › School › Momentum review'), findsOneWidget);
    await _tap(tester, 'New folder');
    expect(find.textContaining('New folder in School'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Optics');
    await tester.pump();
    await tester.tap(find.text('Add'));
    await _pump(tester);
    expect(find.text('This tablet › School › Optics › Momentum review'), findsOneWidget);
    expect(c.read(libraryProvider).folders.any((f) => f.path.join('/') == 'School/Optics'), isTrue);

    await _tap(tester, 'Grid paper');
    await _tap(tester, 'Plum cover');
    await _tap(tester, 'Create note');
    expect(find.byType(CanvasScreen), findsOneWidget);
    final made = c.read(libraryProvider).active.firstWhere((n) => n.title == 'Momentum review');
    expect(made.folder, ['School', 'Optics']);
    expect(made.saveTo, 'device');
    expect(made.cover, tokens.noteCovers[3]);
    final nb = decodeNotebook(store.notebooks[made.id]!);
    expect(nb.saveTo, 'device');
    expect(nb.defaultPaper, Paper.grid);
    // Not remembered.
    expect(c.read(settingsProvider).saveNewTo, isNull);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('"Make these my defaults", then "Use my defaults" skips the dialog', (tester) async {
    final (store, db) = await sampleLibrary();
    final c = await pumpApp(tester, store: store, index: db);
    await tester.tap(find.text('New note').first);
    await _pump(tester);
    await _tap(tester, 'Folder Work');
    await _tap(tester, 'Lines paper');
    await _tap(tester, 'Make these my defaults');
    await tester.enterText(find.byType(TextField).first, 'Standup');
    await tester.pump();
    await _tap(tester, 'Create note');
    final s = c.read(settingsProvider);
    expect(s.defaultFolder, ['Work']);
    expect(s.defaultPaper, Paper.lines);
    expect(s.saveNewTo, 'device');

    c.read(settingsProvider.notifier).apply((s) => s.withPref('newNoteAsk', 1));
    await tester.tap(byLabel('Back to library'));
    await _pump(tester);
    final before = c.read(libraryProvider).active.length;
    await tester.tap(find.text('New note').first);
    await _pump(tester);
    expect(find.text('Will be saved as'), findsNothing);
    expect(find.byType(CanvasScreen), findsOneWidget);
    final all = c.read(libraryProvider).active;
    expect(all.length, before + 1);
    final made = all.where((n) => n.title == 'Untitled note' && n.folder.join() == 'Work').toList();
    expect(made, isNotEmpty);
    expect(made.last.saveTo, 'device');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('OneDrive not connected: Create note signs in first, then it\'s saved there', (tester) async {
    final (store, db) = await sampleLibrary();
    final cloud = MemoryCloud();
    final c = await pumpApp(tester, store: store, index: db, extra: syncOverrides(cloud));
    await tester.tap(find.text('New note').first);
    await _pump(tester);
    expect(find.text('Not connected · you’ll sign in first'), findsNWidgets(2));
    await _tap(tester, 'OneDrive. Not connected · you’ll sign in first');
    expect(find.text('OneDrive › Endless Notebooks › Untitled note'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Optics lab');
    await tester.pump();
    await _tap(tester, 'Create note');
    await tester.pumpAndSettle();
    final sync = c.read(syncProvider).settings;
    expect(sync.onedrive.active, isTrue);
    expect(sync.google.active, isFalse);
    final made = c.read(libraryProvider).active.firstWhere((n) => n.title == 'Optics lab');
    expect(made.saveTo, 'onedrive');
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('a cloud that can\'t be signed in to says why, and the dialog stays', (tester) async {
    final (store, db) = await sampleLibrary();
    await pumpApp(tester, store: store, index: db, extra: syncOverrides(MemoryCloud(), notReady: 'OneDrive sign-in isn’t set up in this version of Endless yet.'));
    await tester.tap(find.text('New note').first);
    await _pump(tester);
    await _tap(tester, 'OneDrive. Not connected · you’ll sign in first');
    await tester.enterText(find.byType(TextField).first, 'Optics lab');
    await tester.pump();
    await _tap(tester, 'Create note');
    await tester.pumpAndSettle();
    expect(find.text('Can’t connect OneDrive'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Will be saved as'), findsOneWidget);
  });

  testWidgets('the library menu\'s Save to… changes where a notebook goes', (tester) async {
    final (store, db) = await sampleLibrary();
    final cloud = MemoryCloud();
    final c = await pumpApp(tester, store: store, index: db, location: Routes.library(['School']), extra: syncOverrides(cloud));
    await tester.longPress(find.text('Calculus II').first);
    await _pump(tester);
    await tester.tap(find.text('Save to…'));
    await _pump(tester);
    expect(find.textContaining('Now it goes to every cloud that’s on'), findsOneWidget);
    await _tap(tester, 'Google Drive. Not connected · you’ll sign in first');
    await _tap(tester, 'Save here');
    await tester.pumpAndSettle();
    final entry = c.read(libraryProvider).active.firstWhere((n) => n.title == 'Calculus II');
    expect(entry.saveTo, 'google');
    expect(c.read(syncProvider).settings.google.active, isTrue);
    expect(decodeNotebook(store.notebooks[entry.id]!).saveTo, 'google');
    expect(CloudKind.google.name, 'google');
    await tester.pump(const Duration(seconds: 10));
  });
}
