import 'package:endless/board/model.dart';
import 'package:endless/canvas/ink_canvas.dart' show InkCanvas;
import 'package:endless/canvas/gestures.dart' show ScribbleLevel;
import 'package:endless/state/settings.dart';
import 'package:endless/theme/colors.dart';
import 'package:endless/theme/palettes.dart';
import 'package:endless/ui/canvas/canvas_screen.dart';
import 'package:endless/ui/routes.dart';
import 'package:endless/ui/settings/settings_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

Finder _switch(String label) => find.byWidgetPredicate((w) => w is SettingsSwitch && w.label == label);

Finder _option(String group, String option) => find.descendant(
      of: find.byWidgetPredicate((w) => w is SettingsChoice && w.label == group),
      matching: find.text(option),
    );

Future<void> _section(WidgetTester tester, String name) async {
  await tester.tap(find.descendant(of: find.bySemanticsLabel('Settings').first, matching: find.text(name)).first);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('every section is in the side menu, and each opens with its title and intro', (tester) async {
    await pumpApp(tester, location: Routes.settings());
    expect(find.text('How Endless opens, looks and feels day to day.'), findsOneWidget);
    for (final (name, title) in [
      ('Account', 'Account'),
      ('Pen & S Pen', 'Pen & S Pen'),
      ('Handwriting & search', 'Handwriting & search'),
      ('Notebooks & pages', 'Notebooks & pages'),
      ('Sync & backup', 'Sync & backup'),
      ('Themes & dark mode', 'Themes & dark mode'),
      ('Notifications', 'Notifications & reminders'),
      ('Calendar', 'Calendar'),
      ('Storage', 'Storage'),
      ('Privacy & security', 'Privacy & security'),
      ('About', 'About'),
      ('General', 'General'),
    ]) {
      await _section(tester, name);
      expect(find.text(title), findsWidgets, reason: name);
    }
  });

  testWidgets('Pen & S Pen rows change the settings the canvas uses', (tester) async {
    final c = await pumpApp(tester, location: Routes.settings('pen'));
    expect(find.text('WRITING'), findsOneWidget);
    await tester.tap(_switch('Pressure changes thickness'));
    await tester.tap(_switch('Scribble to erase'));
    await tester.pump();
    await tester.tap(_option('How much scribbling counts', 'Firm'));
    await tester.tap(_option('Arrowheads', 'Filled'));
    await tester.pump();
    await tester.ensureVisible(_switch('Swipe up to tuck menus away'));
    await tester.tap(_switch('Swipe up to tuck menus away'));
    await tester.tap(_option('Double-tap the pen tool for', 'Eraser'));
    await tester.pump();
    final s = c.read(settingsProvider);
    expect(s.pressure, isFalse);
    expect(s.scribble, isFalse);
    expect(s.scribbleLevel, ScribbleLevel.firm);
    expect(s.arrowStyle, ArrowStyle.filled);
    expect(s.swipeTuck, isFalse);
    expect(s.penAgainErases, isTrue);
  });

  testWidgets('search finds a setting by its name or description, and says when nothing matches', (tester) async {
    final c = await pumpApp(tester, location: Routes.settings());
    await tester.enterText(find.byType(TextField), 'swipe');
    await tester.pumpAndSettle();
    expect(find.text('Settings that match “swipe”'), findsOneWidget);
    expect(find.text('PEN & S PEN › MENUS'), findsOneWidget);
    expect(_switch('Swipe up to tuck menus away'), findsOneWidget);
    await tester.tap(_switch('Swipe up to tuck menus away'));
    await tester.pump();
    expect(c.read(settingsProvider).swipeTuck, isFalse);

    await tester.enterText(find.byType(TextField), 'dark');
    await tester.pumpAndSettle();
    expect(find.text('THEMES & DARK MODE › MODE'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'zebra');
    await tester.pumpAndSettle();
    expect(find.text('No settings match “zebra”.'), findsOneWidget);

    // Picking a section ends the search.
    await _section(tester, 'Storage');
    expect(find.text('What Endless keeps on this tablet.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
  });

  testWidgets('saved settings that don\'t do anything yet keep their value', (tester) async {
    final store = storeWith(sampleNotebook());
    final c = await pumpApp(tester, store: store, location: Routes.settings());
    await tester.tap(_option('Date format', '25 Sep'));
    await tester.tap(_switch('Left-handed mode'));
    await tester.pump();
    await _section(tester, 'Privacy & security');
    await tester.tap(_switch('Lock the app'));
    await tester.pump(const Duration(seconds: 1));
    final s = c.read(settingsProvider);
    expect(s.pref<int>('dateFormat'), 1);
    expect(s.pref<bool>('leftHanded'), isTrue);
    expect(s.pref<bool>('appLock'), isTrue);
    final again = AppSettings.fromJson(store.settings!);
    expect(again.pref<int>('dateFormat'), 1);
    expect(again.pref<bool>('appLock'), isTrue);
  });

  testWidgets('Themes: a theme and an accent change the whole app; the live preview follows', (tester) async {
    final c = await pumpApp(tester, location: Routes.settings('themes'));
    expect(find.text('PREVIEW'), findsOneWidget);
    expect(find.text('Following your tablet: light by day, dark after sunset'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Sage theme'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).theme, 'sage');
    final ctx = tester.element(find.text('PREVIEW'));
    expect(ctx.colors.bg, swatchOf('sage', Brightness.light).bg);

    await tester.tap(find.bySemanticsLabel('Rose'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).accent, 'rose');
    expect(tester.element(find.text('PREVIEW')).colors.accent, accentOf('sage', 'rose', Brightness.light));

    await tester.tap(find.bySemanticsLabel('Dark'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).themeMode, ThemeMode.dark);
    expect(find.text('Dark mode'), findsOneWidget);
    expect(tester.element(find.text('PREVIEW')).colors.bg, swatchOf('sage', Brightness.dark).bg);

    await tester.tap(find.bySemanticsLabel('Grid paper'));
    await tester.tap(_switch('Keep pages light in dark mode'));
    await tester.pump();
    expect(c.read(settingsProvider).defaultPaper, Paper.grid);
    expect(c.read(settingsProvider).keepPagesLight, isTrue);

    await tester.tap(find.bySemanticsLabel('Theme default'));
    await tester.tap(find.bySemanticsLabel('Make my own theme'));
    await tester.pump();
    expect(find.text('Making your own theme is coming soon'), findsOneWidget);
    expect(c.read(settingsProvider).accent, themeAccent);
  });

  testWidgets('Keep pages light in dark mode: the canvas page is light under dark menus', (tester) async {
    final store = storeWith(sampleNotebook(), settings: AppSettings(themeMode: ThemeMode.dark).withPref('keepPagesLight', true));
    await pumpCanvas(tester, store: store);
    final page = tester.element(find.byType(PageTheme));
    expect(Theme.of(page).brightness, Brightness.dark);
    final canvas = tester.element(find.byType(InkCanvas));
    expect(Theme.of(canvas).brightness, Brightness.light);
    // The menus stay dark.
    expect(Theme.of(tester.element(find.text('Physics — Lecture notes'))).brightness, Brightness.dark);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Account: your name for the Start page; the clouds open Sync & backup', (tester) async {
    final c = await pumpApp(tester, location: Routes.settings('account'));
    expect(find.text('Not signed in to a cloud'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Edit profile'));
    await tester.pumpAndSettle();
    expect(find.text('Your name'), findsWidgets);
    await tester.enterText(find.byType(TextField).last, 'Kieth');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Save'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).userName, 'Kieth');
    expect(find.text('Kieth'), findsWidgets);
    await tester.tap(find.bySemanticsLabel('Connect').first);
    await tester.pumpAndSettle();
    expect(find.text('Notebooks are saved on this tablet first, then copied to your cloud. You can keep writing offline.'), findsOneWidget);
  });

  testWidgets('Open to "Last note I was in" opens that notebook when the app starts', (tester) async {
    final store = storeWith(sampleNotebook(), settings: AppSettings(lastNotebookId: 'nb_sample').withPref('openTo', 1));
    await pumpApp(tester, store: store);
    await tester.pumpAndSettle();
    expect(find.byType(CanvasScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  test('prefs have defaults and round-trip', () {
    final s = AppSettings();
    expect(s.theme, 'paper');
    expect(s.accent, themeAccent);
    expect(s.askNewNote, isTrue);
    expect(s.hoverMenus, isTrue);
    expect(s.defaultPaper, Paper.dots);
    expect(s.toJson().containsKey('prefs'), isFalse);
    final t = AppSettings.fromJson(s.withPref('theme', 'harbor').withPref('defaultFolder', ['School', 'Physics']).toJson());
    expect(t.theme, 'harbor');
    expect(t.defaultFolder, ['School', 'Physics']);
    expect(ProviderContainer, isNotNull);
  });
}
