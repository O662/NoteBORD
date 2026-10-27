// Golden images of charts and live items at the tablet size (1280×800).
// Compare with design/screens/Charts.png and LiveItems.png.
//
// Regenerate after an intended visual change:
//   flutter test --update-goldens test/golden/phase7b_golden_test.dart
@Tags(['golden'])
library;

import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/canvas/live_items.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/state/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../live_samples.dart';

Future<void> _withShadows(Future<void> Function() body) async {
  debugDisableShadows = false;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
  }
}

/// Charts.png has no color tray, pages rail or map open.
MemoryBoardStore _plain(MemoryBoardStore store, {bool dark = false}) => store
  ..settings = AppSettings(themeMode: dark ? ThemeMode.dark : ThemeMode.light, trayOpen: false, pagesOpen: false, mapOpen: false)
      .toJson();

/// Selects the momentum chart with Select (the Chart selected bar).
Future<void> _selectChart(WidgetTester tester, ProviderContainer c) async {
  c.read(settingsProvider.notifier).apply((s) => s.copyWith(tool: CanvasTool.select));
  await tester.pump();
  canvasPane.selection.select(['it_momentum']);
  await tester.pump();
  await tester.pump();
}

/// The Live items bar from Insert → Clock & date, with its hint.
Future<void> _liveItems(WidgetTester tester) async {
  await tester.tap(byLabel('Insert'));
  await tester.pump();
  await tester.tap(find.text('Everything else'));
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsLabel('Clock & date'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() {
    liveNow = () => liveSampleNow;
    deviceTimeZone = 'America/Chicago';
  });
  tearDown(() {
    liveNow = DateTime.now;
    deviceTimeZone = null;
  });

  for (final (name, dark) in [('charts', false), ('charts_dark', true)]) {
    testWidgets(name, (tester) => _withShadows(() async {
          final c = await pumpCanvas(tester, store: _plain(chartsStore(), dark: dark));
          await _selectChart(tester, c);
          await expectLater(find.byType(MaterialApp), matchesGoldenFile('$name.png'));
        }));
  }

  testWidgets('charts_types', (tester) => _withShadows(() async {
        final c = await pumpCanvas(tester, store: _plain(chartsStore()));
        final page = shownPage(c);
        final notebook = c.read(notebookProvider(canvasPane.notebookId).notifier);
        notebook.replaceItems(page.id, [
          (page['it_momentum']! as ChartItem).copyWith(chartType: ChartType.scatter),
          (page['it_week']! as ChartItem).copyWith(chartType: ChartType.area),
        ]);
        // Saved.
        await tester.pump(const Duration(seconds: 1));
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('charts_types.png'));
      }));

  for (final (name, dark) in [('live_items', false), ('live_items_dark', true)]) {
    testWidgets(name, (tester) => _withShadows(() async {
          final store = storeWith(liveSample());
          if (dark) store.settings = AppSettings(themeMode: ThemeMode.dark).toJson();
          await pumpCanvas(tester, store: store);
          await _liveItems(tester);
          await expectLater(find.byType(MaterialApp), matchesGoldenFile('$name.png'));
        }));
  }
}
