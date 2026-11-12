// Golden images of Update 04's screens. Landscape at the tablet size
// (1280×800), portrait at 800×1280. Compare with design/screens/:
// Start-rail.png, StartCollapsed.png, CalendarRail.png, Main-rail.png,
// StickiesRail.png, StartPortrait.png, StartPortraitMenu.png.
//
// Regenerate after an intended visual change:
//   flutter test --update-goldens test/golden
@Tags(['golden'])
library;

import 'package:endless/ui/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../sample_library.dart';

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
  await tester.pump(const Duration(milliseconds: 400));
}

void _golden(String name, String location, {Size? size, Future<void> Function(WidgetTester t)? setUp}) {
  testWidgets(name, (tester) => _withShadows(() async {
        final (store, db) = await sampleLibrary();
        await pumpApp(tester, store: store, index: db, location: location, size: size);
        await _settle(tester);
        await setUp?.call(tester);
        await _settle(tester);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('$name.png'));
        await tester.pump(const Duration(seconds: 5));
      }));
}

Future<void> _tap(WidgetTester t, String label) async {
  await t.tap(find.bySemanticsLabel(label));
  await _settle(t);
}

void main() {
  setUpAll(loadAppFonts);

  // §9: the sidebar folded to its rail.
  _golden('start_rail', Routes.start, setUp: (t) => _tap(t, 'Collapse the sidebar'));
  _golden('calendar_rail', Routes.calendar, setUp: (t) => _tap(t, 'Collapse the sidebar'));
  _golden('library_rail', Routes.library(['School']), setUp: (t) => _tap(t, 'Collapse the sidebar'));
  _golden('stickies_rail', Routes.stickies, setUp: (t) => _tap(t, 'Collapse the sidebar'));
  _golden('planner_rail', Routes.planner, setUp: (t) => _tap(t, 'Collapse the sidebar'));
  _golden('remember_rail', Routes.remember, setUp: (t) => _tap(t, 'Collapse the sidebar'));

  // §5: the Start header folded into the slim bar.
  _golden('start_collapsed', Routes.start, setUp: (t) => _tap(t, 'Collapse the header'));

  // §8: portrait.
  _golden('start_portrait', Routes.start, size: portraitSize);
  _golden('start_portrait_menu', Routes.start, size: portraitSize, setUp: (t) => _tap(t, 'Open menu'));
  _golden('start_portrait_collapsed', Routes.start, size: portraitSize, setUp: (t) => _tap(t, 'Collapse the header'));
  _golden('library_portrait', Routes.library(['School']), size: portraitSize);
  _golden('calendar_portrait', Routes.calendar, size: portraitSize);
}
