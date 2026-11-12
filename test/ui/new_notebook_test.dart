// Update 04c: the New notebook prompt, Skip for now, Finish setting up and
// "Use these every time" (UPDATE_04 §6).
import 'package:endless/app.dart' show routerProvider;
import 'package:endless/board/codec.dart';
import 'package:endless/board/model.dart';
import 'package:endless/library/library.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:endless/ui/canvas/canvas_screen.dart';
import 'package:endless/ui/library/new_notebook_dialog.dart';
import 'package:endless/ui/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../sample_library.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

Finder _label(String s) => find.bySemanticsLabel(s);

NotebookEntry? _byTitle(ProviderContainer c, String title) =>
    c.read(libraryProvider).notebooks.where((n) => n.title == title).firstOrNull;

void main() {
  setUpAll(loadAppFonts);

  test('notebook.json keeps "setup": "pending", and drops it once set up', () {
    final nb = Notebook(
      id: 'nb_x',
      title: 'Untitled notebook',
      createdAt: DateTime.utc(2026, 11, 11),
      updatedAt: DateTime.utc(2026, 11, 11),
      pageIds: const ['pg_1'],
      setupPending: true,
    );
    final text = encodeNotebook(nb);
    expect(text, contains('"setup": "pending"'));
    expect(decodeNotebook(text).setupPending, isTrue);
    nb.setupPending = false;
    expect(encodeNotebook(nb), isNot(contains('"setup"')));
    expect(decodeNotebook(encodeNotebook(nb)).setupPending, isFalse);
  });

  test('choices map to where a notebook is saved', () {
    final none = NotebookChoices.fromJson({'place': 'device', 'backup': false})!;
    expect(none.toJson()['place'], 'device');
    final backed = NotebookChoices.fromJson({'place': 'device', 'backup': true, 'folder': ['School']})!;
    expect(backed.folder, ['School']);
    expect(backed.backup, isTrue);
    expect(NotebookChoices.fromJson('nope'), isNull);
    expect(AppSettings().notebookDefaults, isNull);
  });

  testWidgets('Start’s New notebook: name, color, folder, no backup, Create', (tester) async {
    final (store, db) = await sampleLibrary();
    final c = await pumpApp(tester, store: store, index: db);
    await _pump(tester);
    await tester.tap(_label('New notebook'));
    await _pump(tester);
    expect(find.text('Three quick choices. In a rush? Skip and start writing.'), findsOneWidget);
    expect(find.text('About 10 seconds'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Biology 101');
    await tester.tap(_label('Green'));
    await tester.tap(_label('School folder'));
    await _pump(tester);
    // This tablet; the switch to No backup shows the warning.
    await tester.tap(_label('This tablet, Works offline'));
    await _pump(tester);
    final sw = find.byType(Switch);
    if (tester.widget<Switch>(sw).value) await tester.tap(sw);
    await _pump(tester);
    expect(find.text('No backup'), findsOneWidget);
    expect(find.textContaining('If the tablet is lost or reset'), findsOneWidget);

    await tester.tap(find.text('Create notebook'));
    await _pump(tester);
    expect(find.byType(CanvasScreen), findsOneWidget);
    final n = _byTitle(c, 'Biology 101')!;
    expect(n.folder, ['School']);
    expect(n.saveTo, 'device');
    expect(n.cover, tokens.coverColors[2]);
    expect(n.setupPending, isFalse);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a cloud that isn’t on is signed in to first; when that fails nothing is made', (tester) async {
    final (store, db) = await sampleLibrary();
    final c = await pumpApp(tester, store: store, index: db, location: Routes.all);
    await _pump(tester);
    final before = c.read(libraryProvider).notebooks.length;
    await tester.tap(find.text('New notebook'));
    await _pump(tester);
    expect(find.text('Sign in first'), findsNWidgets(2));
    await tester.tap(_label('OneDrive, Sign in first'));
    await _pump(tester);
    expect(find.text('Already backed up in OneDrive'), findsOneWidget);
    // The switch is locked on for a cloud.
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    await tester.tap(find.text('Create notebook'));
    await _pump(tester);
    expect(find.textContaining('Can’t connect OneDrive'), findsOneWidget);
    expect(c.read(libraryProvider).notebooks.length, before);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Skip for now → Not set up → Finish setting up', (tester) async {
    final (store, db) = await sampleLibrary();
    final c = await pumpApp(tester, store: store, index: db);
    await _pump(tester);
    await tester.tap(_label('New notebook'));
    await _pump(tester);
    await tester.tap(_label('Skip for now. Set up later from More options'));
    await _pump(tester);
    expect(find.byType(CanvasScreen), findsOneWidget);
    final n = _byTitle(c, 'Untitled notebook')!;
    expect(n.setupPending, isTrue);
    expect(n.saveTo, 'device');
    expect(n.folder, isEmpty);
    expect((await store.loadNotebookMeta(n.id))!.setupPending, isTrue);

    // The canvas ⋯ starts with Finish setting up.
    await tester.tap(byLabel('More options'));
    await _pump(tester);
    expect(find.text('Finish setting up'), findsOneWidget);
    await tester.tapAt(const Offset(640, 600));
    await _pump(tester);

    // The library tags it and its menu leads with Finish setting up.
    c.read(routerProvider).go(Routes.all);
    await _pump(tester);
    expect(find.text('Not set up'), findsOneWidget);
    await tester.longPress(find.text('Untitled notebook'));
    await _pump(tester);
    expect(find.text('Name, folder, save place, backup'), findsOneWidget);
    await tester.tap(find.text('Finish setting up'));
    await _pump(tester);
    expect(find.text('This notebook was made in a hurry. Give it a name, a home and a backup.'), findsOneWidget);
    expect(find.text('Skip for now'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Chemistry lab');
    await tester.tap(_label('Work folder'));
    await _pump(tester);
    await tester.tap(find.text('Save'));
    await _pump(tester);

    final done = c.read(libraryProvider).byId(n.id)!;
    expect(done.title, 'Chemistry lab');
    expect(done.folder, ['Work']);
    expect(done.setupPending, isFalse);
    expect((await store.loadNotebookMeta(n.id))!.setupPending, isFalse);
    c.read(routerProvider).go(Routes.all);
    await _pump(tester);
    expect(find.text('Not set up'), findsNothing);

    // A set-up notebook's menu has no Finish setting up.
    await tester.longPress(find.text('Chemistry lab'));
    await _pump(tester);
    expect(find.text('Finish setting up'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('"Use these every time" stops asking; Settings › New notebooks asks again', (tester) async {
    final (store, db) = await sampleLibrary();
    final c = await pumpApp(tester, store: store, index: db);
    await _pump(tester);
    await tester.tap(_label('New notebook'));
    await _pump(tester);
    await tester.tap(_label('Personal folder'));
    await tester.tap(_label('This tablet, Works offline'));
    await _pump(tester);
    await tester.tap(_label('Use these every time and stop asking'));
    await tester.tap(find.text('Create notebook'));
    await _pump(tester);
    final saved = c.read(settingsProvider).notebookDefaults!;
    expect(saved.folder, ['Personal']);

    // Next time: straight to a new notebook with those choices.
    c.read(routerProvider).go(Routes.start);
    await _pump(tester);
    final count = c.read(libraryProvider).notebooks.length;
    await tester.tap(_label('New notebook'));
    await _pump(tester);
    expect(find.byType(CanvasScreen), findsOneWidget);
    expect(c.read(libraryProvider).notebooks.length, count + 1);

    // Settings › Notebooks & pages › New notebooks.
    c.read(routerProvider).go(Routes.settings('notes'));
    await _pump(tester);
    expect(find.text('NEW NOTEBOOKS'), findsOneWidget);
    expect(find.text('Personal · This tablet, no backup'), findsOneWidget);
    await tester.ensureVisible(find.text('Ask each time'));
    await tester.tap(find.text('Ask each time'));
    await _pump(tester);
    expect(c.read(settingsProvider).notebookDefaults, isNull);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('in portrait the prompt fits, chips wrap and buttons stack if needed', (tester) async {
    final (store, db) = await sampleLibrary();
    await pumpApp(tester, store: store, index: db, size: portraitSize);
    await _pump(tester);
    await tester.tap(_label('New notebook'));
    await _pump(tester);
    expect(tester.takeException(), isNull);
    final r = tester.getRect(find.byType(NewNotebookDialog));
    expect(r.width, lessThanOrEqualTo(680));
    expect(r.left, greaterThanOrEqualTo(16));
    await tester.pump(const Duration(seconds: 5));
  });
}
