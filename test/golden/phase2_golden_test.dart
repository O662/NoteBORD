// Golden images of the Phase 2 screens at the tablet size (1280×800).
// Compare with design/screens/Start.png, Main.png, Templates.png, Lock.png
// and Split.png.
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

void _golden(String name, String location, {Future<void> Function(WidgetTester t)? setUp}) {
  testWidgets(name, (tester) => _withShadows(() async {
        final (store, db) = await sampleLibrary();
        await pumpApp(tester, store: store, index: db, location: location);
        await _settle(tester);
        await setUp?.call(tester);
        await _settle(tester);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('$name.png'));
        // Let hints and autosave timers finish.
        await tester.pump(const Duration(seconds: 5));
      }));
}

void main() {
  setUpAll(loadAppFonts);

  _golden('start', Routes.start);
  _golden('library', Routes.library(['School']));
  _golden('library_list', Routes.library(['School']), setUp: (t) => t.tap(find.bySemanticsLabel('List view')));
  _golden('templates', Routes.notebook('nb_physics', page: 2), setUp: (t) async {
    await t.tap(byLabel('Insert'));
    await t.pump();
    await t.tap(find.text('Templates'));
  });
  _golden('lock', Routes.notebook('nb_physics', page: 2), setUp: (t) async {
    await t.tap(byLabel('More options'));
    await t.pump();
    await t.tap(find.text('Password protect'));
    await _settle(t);
    await t.enterText(find.byType(TextField).at(1), 'momentum42');
    await t.enterText(find.byType(TextField).at(0), 'momentum42');
    await t.pump();
  });
  _golden('lock_locked', Routes.notebook('nb_thesis'));
  _golden('split', Routes.split(('nb_physics', 2), ('nb_lab', 0)));
}
