// Golden images of Phase 4a at 1280×800: Import and export (compare
// `export.png` with design/screens/Export.png) and the Share dialog's
// "Export a copy" (design/screens/Share.png).
//
// Regenerate after an intended visual change:
//   flutter test --update-goldens test/golden
@Tags(['golden'])
library;

import 'package:endless/state/settings.dart';
import 'package:endless/transfer/files.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

Future<void> _withShadows(Future<void> Function() body) async {
  debugDisableShadows = false;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
  }
}

/// Opens the sample notebook on page 3, runs [setUp], and compares with
/// `<name>.png`.
void _golden(
  String name, {
  ThemeMode mode = ThemeMode.light,
  required Future<void> Function(WidgetTester t, ProviderContainer c, FakeFileTransfer files) setUp,
}) {
  testWidgets(name, (tester) => _withShadows(() async {
        final files = FakeFileTransfer();
        final store = storeWith(sampleNotebook(), settings: AppSettings(themeMode: mode));
        final c = await pumpCanvas(tester, store: store, notebookId: 'nb_sample', extra: [fileTransferProvider.overrideWithValue(files)]);
        canvasPane.goTo(2);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await setUp(tester, c, files);
        await tester.pumpAndSettle();
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('$name.png'));
        await tester.pump(const Duration(seconds: 5));
      }));
}

Future<void> _more(WidgetTester t, String item) async {
  await t.tap(byLabel('More options'));
  await t.pump();
  await t.tap(find.text(item));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  // Export.png: this page, as a PDF.
  _golden('export', setUp: (t, c, files) => _more(t, 'Export'));

  _golden('export_dark', mode: ThemeMode.dark, setUp: (t, c, files) => _more(t, 'Export'));

  // The board file's options, and Split into A4 / Letter's paper row.
  _golden('export_board', setUp: (t, c, files) async {
    await _more(t, 'Export');
    await t.tap(find.text('Whole notebook'));
    await t.tap(find.text('Board file (.board)'));
    await t.tap(find.text('Share…'));
  });

  _golden('export_split', setUp: (t, c, files) async {
    await _more(t, 'Export');
    await t.tap(find.textContaining('Split into'));
    await t.tap(find.text('Include the dot-grid background'));
  });

  // The Import tab (Export.dc.html, isImport), with a PDF picked.
  _golden('import', setUp: (t, c, files) async {
    await _more(t, 'Import');
    files.toPick = [PickedFile('Lecture 4 slides.pdf', fakePdfBytes())];
    await t.tap(find.text('Browse files'));
  });

  // Share.png's "Export a copy" row, until sharing with people (Phase 9).
  _golden('share', setUp: (t, c, files) async {
    await t.tap(byLabel('Share'));
  });
}
