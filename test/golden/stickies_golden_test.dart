// Golden images of Update 02c at the tablet size (1280×800). Compare with
// design/screens/Stickies.png and Stickies-stack.png.
//
// Regenerate after an intended visual change:
//   flutter test --update-goldens test/golden/stickies_golden_test.dart
@Tags(['golden'])
library;

import 'package:endless/app.dart';
import 'package:endless/board/ids.dart';
import 'package:endless/board/model.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/study/study_rows.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:endless/ui/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../sample_stickies.dart';

Future<void> _withShadows(Future<void> Function() body) async {
  debugDisableShadows = false;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
  }
}

void _golden(String name, {bool dark = false, Future<void> Function(WidgetTester t)? setUp}) {
  testWidgets(name, (tester) => _withShadows(() async {
        final (store, db) = await stickyLibrary();
        // A note written by hand.
        final inked = StickyItem(
          id: newId('it'),
          x: 700,
          y: 100,
          z: 2,
          createdAt: stickyAt.add(const Duration(days: 5)),
          w: 242,
          h: 220,
          color: tokens.stickyColors[2],
          items: [noteInk(50), noteInk(95, length: 140), noteInk(140, length: 160)],
        );
        final page = BoardPage(id: 'pg_ink', title: 'Lab 4', items: [inked]);
        final nb = (await store.loadNotebookMeta('nb_lab'))!..pageIds.add(page.id);
        await store.saveNotebook(nb);
        await store.savePage('nb_lab', page);
        await db.replacePageStudy('nb_lab', page.id, studyRowsFor('nb_lab', page, null));
        if (dark) store.settings = AppSettings(themeMode: ThemeMode.dark).toJson();
        tester.view.physicalSize = tokens.Sizes.tabletFrame;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final overrides = await testOverrides(store, index: db, location: Routes.stickies);
        await tester.pumpWidget(ProviderScope(overrides: overrides, child: const EndlessApp()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump();
        await setUp?.call(tester);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('$name.png'));
      }));
}

void main() {
  setUpAll(loadAppFonts);

  _golden('stickies');
  _golden('stickies_dark', dark: true);
  _golden('stickies_stack', setUp: (t) async {
    await t.tap(find.text('Stack · 3'));
  });
}
