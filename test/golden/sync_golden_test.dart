// Golden images of Phase 9a at the tablet size (1280×800). Compare with
// design/screens/Sync.png (Settings › Sync & backup) and Main.png's sidebar
// card ("Synced · Google Drive").
//
// Regenerate after an intended visual change:
//   flutter test --update-goldens test/golden/sync_golden_test.dart
@Tags(['golden'])
library;

import 'package:endless/app.dart';
import 'package:endless/board/store.dart';
import 'package:endless/library/index_db.dart';
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

/// Google Drive connected and synced two minutes ago; OneDrive not.
void _synced(MemoryBoardStore store) {
  final now = testNow.toUtc();
  store.saveSyncFile(
    'settings',
    SyncSettings(
      device: 'dv_golden',
      google: CloudSetting(on: true, account: const CloudAccount('kim@example.com'), lastSync: now.subtract(const Duration(minutes: 2))),
      synced: {for (final id in store.notebooks.keys) id: DateTime.utc(2030)},
    ).toJson(),
  );
}

Future<void> _pump(WidgetTester tester, (MemoryBoardStore, IndexDb) lib, String location, {bool dark = false}) async {
  final (store, db) = lib;
  tester.view.physicalSize = tokens.Sizes.tabletFrame;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.platformBrightnessTestValue = dark ? Brightness.dark : Brightness.light;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  final overrides = await testOverrides(store, index: db, location: location);
  await tester.pumpWidget(ProviderScope(overrides: [...overrides, ...syncOverrides(MemoryCloud())], child: const EndlessApp()));
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('sync_settings', (tester) => _withShadows(() async {
        final lib = await sampleLibrary();
        _synced(lib.$1);
        await _pump(tester, lib, Routes.settings('sync'));
        await expectLater(find.byType(EndlessApp), matchesGoldenFile('sync_settings.png'));
      }));

  testWidgets('sync_settings_dark', (tester) => _withShadows(() async {
        final lib = await sampleLibrary();
        _synced(lib.$1);
        await _pump(tester, lib, Routes.settings('sync'), dark: true);
        await expectLater(find.byType(EndlessApp), matchesGoldenFile('sync_settings_dark.png'));
      }));

  testWidgets('sync_library', (tester) => _withShadows(() async {
        final lib = await sampleLibrary();
        final store = lib.$1;
        _synced(store);
        // One notebook changed since: its cover waits to sync.
        final first = store.notebooks.keys.first;
        final s = SyncSettings.fromJson(await store.loadSyncFile('settings'));
        await store.saveSyncFile('settings', s.copyWith(synced: {...s.synced}..remove(first)).toJson());
        await _pump(tester, lib, Routes.library());
        await expectLater(find.byType(EndlessApp), matchesGoldenFile('sync_library.png'));
      }));

  // Unused here, kept so the kind labels stay checked against the design.
  test('cloud names', () {
    expect(CloudKind.google.label, 'Google Drive');
    expect(CloudKind.onedrive.label, 'OneDrive');
  });
}
