// Update 04b: your shortcuts on the canvas toolbar (§10) and the canvas in
// portrait (§8).
import 'package:endless/state/settings.dart';
import 'package:endless/ui/canvas/left_rail.dart';
import 'package:endless/ui/canvas/shortcuts.dart';
import 'package:endless/ui/canvas/top_bar.dart';
import 'package:endless/ui/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Finder _label(String s) => find.bySemanticsLabel(s);

List<String> _shortcuts(ProviderContainer c) => c.read(settingsProvider).shortcuts;

Rect _railRect(WidgetTester tester) => tester.getRect(find.byType(LeftRail));

void main() {
  setUpAll(loadAppFonts);

  group('the catalog', () {
    test('defaults, ids and search', () {
      expect(AppSettings().shortcuts, ['mic', 'pdf', 'ruler']);
      expect({for (final t in shortcutCatalog) t.id}.length, shortcutCatalog.length);
      expect(shortcutCatalog.length, 27);
      expect(searchShortcuts('website').map((t) => t.id), ['web']);
      expect(searchShortcuts('ruler').map((t) => t.id), ['ruler']);
      expect(searchShortcuts('PDF').map((t) => t.id), contains('pdf'));
      expect(searchShortcuts('zzz'), isEmpty);
      // Every menu item but "Everything else" can be pinned.
      for (final g in railGroups) {
        for (final i in g.items) {
          expect(shortcutForRailItem(i.label) == null, i.label == 'Everything else', reason: i.label);
        }
      }
    });

    test('saved ids that aren’t tools any more are dropped; at most 6', () {
      final s = AppSettings().withPref('shortcuts', ['ruler', 'nope', 'web', 'pdf', 'mic', 'graph', 'chart', 'table']);
      expect(s.shortcuts, ['ruler', 'web', 'pdf', 'mic', 'graph', 'chart']);
      expect(AppSettings().withShortcuts([]).shortcuts, isEmpty);
    });

    test('rail height and placement', () {
      expect(LeftRail.heightWith(0), 2 + 12 + 6 * 44 + 9 + 6 * 2);
      expect(LeftRail.heightWith(3), 2 + 12 + 9 * 44 + 18 + 10 * 2);
      // Centered on 800 dp.
      final h = LeftRail.heightWith(3);
      expect(LeftRail.topFor(800, h), (800 - h) / 2);
      // With All pages open it moves up above the strip.
      final h2 = LeftRail.heightWith(LeftRail.fitting(3, 800, allPages: true));
      expect(LeftRail.topFor(800, h2, allPages: true) + h2, lessThanOrEqualTo(800 - 277));
      // Never under the top bar; what doesn't fit above the strip steps aside.
      expect(LeftRail.topFor(800, LeftRail.heightWith(6), allPages: true), 76);
      expect(LeftRail.fitting(6, 800), 6);
      expect(LeftRail.fitting(6, 800, allPages: true), 2);
      expect(LeftRail.fitting(6, 1280, allPages: true, minTop: 132), 6);
      // Portrait: the taller screen's middle.
      expect(LeftRail.topFor(1280, h, minTop: 132), (1280 - h) / 2);
    });
  });

  testWidgets('the default shortcuts sit between the menus and Search', (tester) async {
    await pumpCanvas(tester);
    await _pump(tester);
    for (final l in ['Record audio', 'PDF', 'Ruler', 'Search', 'Add or edit your shortcuts']) {
      expect(byLabel(l), findsOneWidget, reason: l);
    }
    final insert = tester.getCenter(byLabel('Insert')).dy;
    final mic = tester.getCenter(byLabel('Record audio')).dy;
    final ruler = tester.getCenter(byLabel('Ruler')).dy;
    final search = tester.getCenter(byLabel('Search')).dy;
    expect(insert < mic && mic < ruler && ruler < search, isTrue);
    // Centered on the screen.
    final r = _railRect(tester);
    expect((r.center.dy - 400).abs(), lessThan(2));
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a tool shortcut switches on in place, and off again', (tester) async {
    final c = await pumpCanvas(tester);
    await _pump(tester);
    await tester.tap(byLabel('Ruler'));
    await _pump(tester);
    expect(canvasPane.ruler.visible, isTrue);
    expect(tester.widget<ChromeButton>(byLabel('Ruler')).selected, isTrue);
    await tester.tap(byLabel('Ruler'));
    await _pump(tester);
    expect(canvasPane.ruler.visible, isFalse);

    // Laser: on, then back to the pen.
    c.read(settingsProvider.notifier).toggleShortcut('laser');
    await _pump(tester);
    await tester.tap(byLabel('Laser pointer'));
    await _pump(tester);
    expect(c.read(settingsProvider).tool, CanvasTool.laser);
    await tester.tap(byLabel('Laser pointer'));
    await _pump(tester);
    expect(c.read(settingsProvider).tool, CanvasTool.pen);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a feature shortcut opens it directly', (tester) async {
    final c = await pumpCanvas(tester);
    c.read(settingsProvider.notifier).apply((s) => s.withShortcuts(['history', 'pdf']));
    await _pump(tester);
    await tester.tap(byLabel('Version history'));
    await _pump(tester);
    expect(find.text('Version history'), findsWidgets);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('pin from a toolbar menu; pins grey out when full', (tester) async {
    final c = await pumpCanvas(tester);
    await _pump(tester);
    await tester.tap(byLabel('Insert'));
    await _pump(tester);
    expect(_label('Remove Record audio from your shortcuts'), findsOneWidget);
    await tester.tap(_label('Add Sticky note to your shortcuts'));
    await _pump(tester);
    expect(_shortcuts(c), ['mic', 'pdf', 'ruler', 'sticky']);
    expect(_label('Remove Sticky note from your shortcuts'), findsOneWidget);
    expect(byLabel('Sticky note'), findsOneWidget, reason: 'now on the rail');
    await tester.tap(_label('Remove Sticky note from your shortcuts'));
    await _pump(tester);
    expect(_shortcuts(c), ['mic', 'pdf', 'ruler']);

    c.read(settingsProvider.notifier).apply((s) => s.withShortcuts(['mic', 'pdf', 'ruler', 'web', 'table', 'chart']));
    await _pump(tester);
    expect(_label('Your shortcuts are full (6)'), findsWidgets);
    await tester.tap(_label('Your shortcuts are full (6)').first, warnIfMissed: false);
    await _pump(tester);
    expect(_shortcuts(c).length, 6);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the Your shortcuts panel: reorder, remove, reset, search and add', (tester) async {
    final c = await pumpCanvas(tester);
    await _pump(tester);
    await tester.tap(byLabel('Add or edit your shortcuts'));
    await _pump(tester);
    expect(find.text('Your shortcuts'), findsOneWidget);
    expect(find.text('ON YOUR TOOLBAR · 3 OF 6'), findsOneWidget);
    expect(find.text('Empty spot'), findsNWidgets(3));

    await tester.tap(byLabel('Move Record audio down'));
    await _pump(tester);
    expect(_shortcuts(c), ['pdf', 'mic', 'ruler']);
    await tester.tap(byLabel('Remove Ruler'));
    await _pump(tester);
    expect(_shortcuts(c), ['pdf', 'mic']);
    await tester.tap(find.text('Reset to the default'));
    await _pump(tester);
    expect(_shortcuts(c), ['mic', 'pdf', 'ruler']);

    await tester.enterText(find.byType(TextField), 'website');
    await _pump(tester);
    expect(find.text('Website'), findsOneWidget);
    expect(find.text('Table'), findsNothing);
    await tester.tap(_label('Add Website'));
    await _pump(tester);
    expect(_shortcuts(c), ['mic', 'pdf', 'ruler', 'web']);
    expect(find.text('Added'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'nothing like this');
    await _pump(tester);
    expect(find.textContaining('Nothing matches'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await _pump(tester);
    expect(find.text('Your shortcuts'), findsNothing);
    expect(byLabel('Website'), findsOneWidget);

    // Saved with the settings, on this tablet.
    await tester.pump(const Duration(seconds: 1));
    final store = c.read(boardStoreProvider) as dynamic;
    expect((store.settings['prefs'] as Map)['shortcuts'], ['mic', 'pdf', 'ruler', 'web']);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the toolbar re-centers, moves above All pages, and hides for the page menu', (tester) async {
    final c = await pumpCanvas(tester);
    await _pump(tester);
    final three = _railRect(tester);
    c.read(settingsProvider.notifier).apply((s) => s.withShortcuts(['mic', 'pdf', 'ruler', 'web', 'table', 'chart']));
    await _pump(tester);
    final six = _railRect(tester);
    expect(six.height, greaterThan(three.height));
    expect((six.center.dy - three.center.dy).abs(), lessThan(2), reason: 'still centered');

    await tester.tap(_label('Show all pages'));
    await _pump(tester);
    // Six don't fit above the strip on 800 dp: the last ones step aside.
    expect(_railRect(tester).bottom, lessThanOrEqualTo(800 - 277 + 1));
    expect(byLabel('Record audio'), findsOneWidget);
    expect(byLabel('Chart'), findsNothing);
    await tester.tap(_label('Show all pages'));
    await _pump(tester);

    await tester.tap(_label('Page options'));
    await _pump(tester);
    expect(find.byType(LeftRail), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Settings › Pen & S Pen › Toolbar shortcuts opens the same panel', (tester) async {
    await pumpApp(tester, location: '/settings?s=pen');
    await _pump(tester);
    expect(find.text('Toolbar shortcuts'), findsOneWidget);
    expect(find.text('Record audio · PDF · Ruler'), findsOneWidget);
    await tester.tap(find.text('Edit'));
    await _pump(tester);
    expect(find.text('Your shortcuts'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await _pump(tester);
    expect(find.text('Your shortcuts'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  group('portrait canvas (800×1280)', () {
    testWidgets('two rows on top, the rail centered, the map collapsed, nothing overflowing', (tester) async {
      final c = await pumpCanvas(tester, size: portraitSize);
      await _pump(tester);
      expect(tester.takeException(), isNull);
      final title = tester.getRect(find.byType(TitlePill));
      final tools = tester.getRect(find.byType(ToolPill));
      final share = tester.getCenter(find.text('Share'));
      expect(tools.top, greaterThanOrEqualTo(title.bottom - 2), reason: 'tools on row 2');
      expect((share.dy - title.center.dy).abs(), lessThan(4), reason: 'Share on row 1');
      expect((tools.center.dx - 400).abs(), lessThan(2), reason: 'tools centered');
      expect((_railRect(tester).center.dy - 640).abs(), lessThan(2), reason: 'rail on the taller middle');
      expect(_label('Map: the box shows your view. Tap to move there.'), findsNothing);

      // Opening the map here doesn't change the landscape setting.
      final before = c.read(settingsProvider).mapOpen;
      await tester.tap(_label('Show map'));
      await _pump(tester);
      expect(_label('Map: the box shows your view. Tap to move there.'), findsOneWidget);
      expect(c.read(settingsProvider).mapOpen, before);
      await tester.pump(const Duration(seconds: 5));
    });

    for (final (name, location) in [
      ('Search', '/search'),
      ('Settings', '/settings?s=pen'),
      ('Settings › Sync & backup', '/settings?s=sync'),
      ('Flashcards', '/flashcards'),
    ]) {
      testWidgets('$name has no overflow', (tester) async {
        await pumpApp(tester, location: location, size: portraitSize);
        await _pump(tester);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 5));
      });
    }

    testWidgets('menus, the pen settings and the shortcuts panel fit', (tester) async {
      await pumpCanvas(tester, size: portraitSize);
      await _pump(tester);
      await tester.tap(byLabel('More options'));
      await _pump(tester);
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(400, 900));
      await _pump(tester);
      await tester.tap(byLabel('Add or edit your shortcuts'));
      await _pump(tester);
      expect(tester.takeException(), isNull);
      final panel = tester.getRect(find.byType(ShortcutsPanel));
      expect(panel.width, lessThanOrEqualTo(800 * 0.92 + 0.5));
      expect(panel.left, greaterThanOrEqualTo(0));
      expect(panel.right, lessThanOrEqualTo(800));
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
