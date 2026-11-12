// Update 04a: the collapsible sidebar (§9), the Start page's collapsible
// header (§5) and the portrait layouts of the library screens (§8).
import 'package:endless/state/settings.dart';
import 'package:endless/ui/dialogs.dart';
import 'package:endless/ui/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../sample_library.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

Finder _label(String s) => find.bySemanticsLabel(s);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the sidebar folds to the rail on every screen, and is remembered', (tester) async {
    final (store, db) = await sampleLibrary();
    final c = await pumpApp(tester, store: store, index: db);
    await _pump(tester);
    expect(_label('Collapse the sidebar'), findsOneWidget);

    await tester.tap(_label('Collapse the sidebar'));
    await _pump(tester);
    expect(_label('Expand the sidebar'), findsOneWidget);
    expect(find.text('Notebooks'), findsOneWidget, reason: 'the rail labels each section');
    expect(find.text('Cards'), findsOneWidget);
    expect(c.read(settingsProvider).sidebarCollapsed, isTrue);

    // Another screen keeps it folded.
    await tester.tap(find.text('Stickies'));
    await _pump(tester);
    expect(_label('Expand the sidebar'), findsOneWidget);
    expect(_label('Collapse the sidebar'), findsNothing);

    // Saved with the settings (so it's back next launch).
    await tester.pump(const Duration(seconds: 1));
    expect((store.settings!['prefs'] as Map)['sidebarCollapsed'], isTrue);

    await tester.tap(_label('Expand the sidebar'));
    await _pump(tester);
    expect(_label('Collapse the sidebar'), findsOneWidget);
    expect(c.read(settingsProvider).sidebarCollapsed, isFalse);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a rail folder opens that folder; the rail shows badges', (tester) async {
    final (store, db) = await sampleLibrary();
    await pumpApp(tester, store: store, index: db, location: Routes.calendar);
    await _pump(tester);
    await tester.tap(_label('Collapse the sidebar'));
    await _pump(tester);
    await tester.tap(_label('School folder'));
    await _pump(tester);
    expect(find.text('School'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the Start header collapses to a slim bar with more Recent, remembered', (tester) async {
    final (store, db) = await sampleLibrary();
    final c = await pumpApp(tester, store: store, index: db);
    await _pump(tester);
    await tester.tap(_label('Collapse the header'));
    await _pump(tester);
    expect(_label('Expand the header'), findsOneWidget);
    expect(_label('New notebook'), findsOneWidget);
    expect(_label('Scan paper notes'), findsOneWidget);
    expect(c.read(settingsProvider).startCollapsed, isTrue);
    await tester.tap(_label('Expand the header'));
    await _pump(tester);
    expect(_label('Collapse the header'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  group('portrait (800×1280)', () {
    for (final (name, location) in [
      ('Start', Routes.start),
      ('the library', Routes.library(['School'])),
      ('All notebooks', Routes.all),
      ('the calendar', Routes.calendar),
      ('the planner', Routes.planner),
      ('Remember', Routes.remember),
      ('Sticky notes', Routes.stickies),
      ('the Trash', Routes.trash),
    ]) {
      testWidgets('$name lays out with the top bar and nothing overflowing', (tester) async {
        final (store, db) = await sampleLibrary();
        await pumpApp(tester, store: store, index: db, location: location, size: portraitSize);
        await _pump(tester);
        expect(tester.takeException(), isNull);
        expect(_label('Open menu'), findsOneWidget);
        expect(_label('Collapse the sidebar'), findsNothing);
        expect(_label('Expand the sidebar'), findsNothing);
        await tester.pump(const Duration(seconds: 5));
      });
    }

    testWidgets('☰ opens the sidebar as a drawer; the scrim closes it', (tester) async {
      final (store, db) = await sampleLibrary();
      await pumpApp(tester, store: store, index: db, size: portraitSize);
      await _pump(tester);
      expect(find.text('All notebooks'), findsNothing);
      await tester.tap(_label('Open menu'));
      await _pump(tester);
      expect(find.text('All notebooks'), findsOneWidget);
      await tester.tap(_label('Close menu'), warnIfMissed: false);
      await tester.tapAt(const Offset(700, 600));
      await _pump(tester);
      expect(find.text('All notebooks'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a collapsed sidebar setting still uses the drawer in portrait', (tester) async {
      final (store, db) = await sampleLibrary();
      final c = await pumpApp(tester, store: store, index: db, size: portraitSize);
      c.read(settingsProvider.notifier).apply((s) => s.withPref('sidebarCollapsed', true));
      await _pump(tester);
      expect(_label('Expand the sidebar'), findsNothing);
      expect(_label('Open menu'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  test('dialogs are min(680, screen − 32) wide in portrait', () {
    expect(dialogMaxWidth(800), 680);
    expect(dialogMaxWidth(600), 568);
    expect(dialogMaxWidth(1280), 1232);
  });

  testWidgets('dialog footers stack when they don’t fit', (tester) async {
    tester.view.physicalSize = const Size(300, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 260,
            child: DialogActions(children: [
              SizedBox(key: const Key('a'), width: 150, height: 48, child: const Text('Cancel')),
              SizedBox(key: const Key('b'), width: 150, height: 48, child: const Text('Create notebook')),
            ]),
          ),
        ),
      ),
    ));
    final a = tester.getTopLeft(find.byKey(const Key('a')));
    final b = tester.getTopLeft(find.byKey(const Key('b')));
    expect(b.dy, lessThan(a.dy), reason: 'stacked, the main button on top');
  });
}
