// Golden images of Update 02b at the tablet size (1280×800). Compare with
// design/screens/Settings*.png, Themes.png and NewNote.png.
//
// Regenerate after an intended visual change:
//   flutter test --update-goldens test/golden/settings_golden_test.dart
@Tags(['golden'])
library;

import 'package:endless/app.dart';
import 'package:endless/board/store.dart';
import 'package:endless/library/index_db.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/sync/cloud.dart';
import 'package:endless/sync/cloud_auth.dart';
import 'package:endless/sync/sync_state.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:endless/ui/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../sample_library.dart';
import '../sync/sync_app_helpers.dart';

Future<void> _withShadows(Future<void> Function() body) async {
  debugDisableShadows = false;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
  }
}

void _golden(
  String name, {
  String location = Routes.start,
  AppSettings? settings,
  bool dark = false,
  Future<void> Function(WidgetTester t)? setUp,
}) {
  testWidgets(name, (tester) => _withShadows(() async {
        final (MemoryBoardStore store, IndexDb db) = await sampleLibrary();
        if (settings != null) store.settings = settings.toJson();
        store.saveSyncFile(
          'settings',
          SyncSettings(
            device: 'dv_golden',
            google: CloudSetting(on: true, account: const CloudAccount('kim@example.com'), lastSync: testNow.toUtc()),
            synced: {for (final id in store.notebooks.keys) id: DateTime.utc(2030)},
          ).toJson(),
        );
        tester.view.physicalSize = tokens.Sizes.tabletFrame;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.platformBrightnessTestValue = dark ? Brightness.dark : Brightness.light;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final overrides = await testOverrides(store, index: db, location: location);
        await tester.pumpWidget(ProviderScope(overrides: [...overrides, ...syncOverrides(MemoryCloud())], child: const EndlessApp()));
        await tester.pump();
        await tester.pump();
        await setUp?.call(tester);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('$name.png'));
      }));
}

void main() {
  setUpAll(loadAppFonts);

  _golden('settings_general', location: Routes.settings(), settings: AppSettings(userName: 'Kieth'));
  _golden('settings_pen', location: Routes.settings('pen'));
  _golden('settings_notebooks', location: Routes.settings('notes'));
  _golden('settings_search', location: Routes.settings(), setUp: (t) async {
    await t.enterText(find.byType(TextField), 'swipe');
  });
  _golden('settings_account', location: Routes.settings('account'), settings: AppSettings(userName: 'Kieth'));
  _golden('settings_dark', location: Routes.settings('pen'), dark: true);
  // Update 03: the wordmark and tagline (Logo.png).
  _golden('settings_about', location: Routes.settings('about'));
  _golden('themes', location: Routes.settings('themes'), settings: AppSettings(themeMode: ThemeMode.light));
  _golden('themes_dark', location: Routes.settings('themes'), settings: AppSettings(themeMode: ThemeMode.dark));
  _golden('themes_sage_rose', location: Routes.settings('themes'),
      settings: AppSettings(themeMode: ThemeMode.light).withPref('theme', 'sage').withPref('accent', 'rose'));
  _golden('themes_midnight_dark', location: Routes.settings('themes'),
      settings: AppSettings(themeMode: ThemeMode.dark).withPref('theme', 'midnight').withPref('keepPagesLight', true));
  _golden('library_contrast', location: Routes.library(['School']),
      settings: AppSettings(themeMode: ThemeMode.light).withPref('theme', 'contrast'));
  _golden('new_note', setUp: (t) async {
    await t.tap(find.text('New note').first);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.enterText(find.byType(TextField).first, 'Momentum review');
    await t.pump();
    await t.tap(find.text('Physics'));
  });
  _golden('new_note_dark', dark: true, settings: AppSettings(themeMode: ThemeMode.dark), setUp: (t) async {
    await t.tap(find.text('New note').first);
  });
}
