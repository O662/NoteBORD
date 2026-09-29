// Golden images of the Canvas screen at the tablet size (1280×800).
// Compare with design/screens/Canvas*.png.
//
// Regenerate after an intended visual change:
//   flutter test --update-goldens test/golden
//
// Goldens are rendered on Windows; font rasterization differs slightly on
// other platforms, so run them on the same OS that produced them.
@Tags(['golden'])
library;

import 'package:endless/state/notebook.dart';
import 'package:endless/state/settings.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// flutter_test draws shadows solid by default; goldens should show the
/// real soft shadows the tablet renders. Shadows are baked in when a frame
/// is painted, so this wraps the whole test body.
Future<void> _withShadows(Future<void> Function() body) async {
  debugDisableShadows = false;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400)); // implicit animations finish
}

/// Opens the sample notebook on page 3 ("Page 3 of 4", like the design),
/// applies [setUp], and compares with `canvas_<name>.png`.
void _golden(String name, {ThemeMode mode = ThemeMode.light, Future<void> Function(WidgetTester t)? setUp}) {
  testWidgets(name, (tester) => _withShadows(() async {
        final store = storeWith(sampleNotebook(), settings: AppSettings(themeMode: mode));
        final c = await pumpCanvas(tester, store: store);
        c.read(notebookProvider.notifier).goToPage(2);
        await _settle(tester);
        await setUp?.call(tester);
        await _settle(tester);

        await expectLater(find.byType(MaterialApp), matchesGoldenFile('canvas_$name.png'));
        await tester.pump(const Duration(seconds: 5));
      }));
}

void main() {
  setUpAll(loadAppFonts);

  _golden('light');
  _golden('dark', mode: ThemeMode.dark);
  _golden('pen_popover', setUp: (t) => t.tap(byLabel('Pen')));
  _golden('rail_pinned', setUp: (t) => t.tap(byLabel('Study & math')));
  _golden('rail_hover_insert', setUp: (t) async {
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(600, 500));
    await mouse.moveTo(t.getCenter(byLabel('Insert')));
  });
  _golden('more_menu', setUp: (t) => t.tap(byLabel('More options')));
  _golden('map_hidden', setUp: (t) => t.tap(byLabel('Hide map')));
  _golden('fullscreen', setUp: (t) => t.tap(byLabel('Full screen: hide menus')));
}
