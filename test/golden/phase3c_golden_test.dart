// Golden images of Phase 3c at 1280×800: the Kanban board, table, timeline,
// website and diagram cards on the whole board, and their editors. Compare
// `cards_board.png` with design/screens/Board.png.
//
// Regenerate after an intended visual change:
//   flutter test --update-goldens test/golden
@Tags(['golden'])
library;

import 'package:endless/state/settings.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../sample_board.dart';

Future<void> _withShadows(Future<void> Function() body) async {
  debugDisableShadows = false;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
  }
}

Future<void> _penTap(WidgetTester t, Offset at) async {
  final g = await t.createGesture(kind: PointerDeviceKind.stylus);
  await g.down(at, timeStamp: const Duration(seconds: 20));
  await g.up(timeStamp: const Duration(seconds: 20));
  await t.pump();
}

/// Opens the sample board, runs [setUp], and compares with `<name>.png`.
void _golden(
  String name, {
  ThemeMode mode = ThemeMode.light,
  required Future<void> Function(WidgetTester t, ProviderContainer c) setUp,
}) {
  testWidgets(name, (tester) => _withShadows(() async {
        final store = storeWith(sampleBoard(), settings: AppSettings(themeMode: mode));
        final c = await pumpCanvas(tester, store: store);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await setUp(tester, c);
        await tester.pump();
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('$name.png'));
        await tester.pump(const Duration(seconds: 5));
      }));
}

Future<void> _wholeBoard(WidgetTester t) async {
  await t.tap(byLabel('Zoom out to the whole board'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
  await t.pump(const Duration(seconds: 5)); // the hint times out, like Board.png
}

/// Selects the card under [page] (a page point) and opens its editor.
Future<void> _edit(WidgetTester t, Offset page) async {
  canvasPane.view.centerOn(page);
  await t.tap(byLabel('Select'));
  await t.pump();
  await _penTap(t, canvasPane.view.toScreen(page));
  await t.tap(find.bySemanticsLabel('Edit'));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  // Board.png: the whole board, no menus.
  _golden('cards_board', setUp: (t, c) => _wholeBoard(t));

  _golden('cards_board_dark', mode: ThemeMode.dark, setUp: (t, c) => _wholeBoard(t));

  // At 100%, where the Kanban board, the table and the timeline are, with
  // the Kanban board selected: Edit leads its toolbar.
  _golden('cards_selected', setUp: (t, c) async {
    canvasPane.view.panBy(const Offset(-700, -60));
    await t.tap(byLabel('Select'));
    await t.pump();
    await _penTap(t, canvasPane.view.toScreen(sampleKanban.center));
    await t.pump(const Duration(seconds: 5));
  });

  // The bottom row at 100%: the website and the diagram.
  _golden('cards_bottom', setUp: (t, c) async {
    canvasPane.view.panBy(const Offset(-900, -640));
    await t.pump(const Duration(seconds: 5));
  });

  _golden('editor_kanban', setUp: (t, c) => _edit(t, sampleKanban.center));
  _golden('editor_timeline', setUp: (t, c) => _edit(t, sampleTimeline.center));
  _golden('editor_diagram', setUp: (t, c) => _edit(t, sampleDiagram.center));
  _golden('editor_table', setUp: (t, c) => _edit(t, sampleTable.center));
  _golden('editor_website', setUp: (t, c) => _edit(t, sampleWebsite.center));
  _golden('editor_kanban_dark', mode: ThemeMode.dark, setUp: (t, c) => _edit(t, sampleKanban.center));
}
