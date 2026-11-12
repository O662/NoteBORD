// Golden images of Update 04's screens. Landscape at the tablet size
// (1280×800), portrait at 800×1280. Compare with design/screens/:
// Start-rail.png, StartCollapsed.png, CalendarRail.png, Main-rail.png,
// StickiesRail.png, StartPortrait.png, StartPortraitMenu.png,
// CanvasShortcuts*.png, Canvas-pin-from-menu.png, Canvas-shortcuts-in-use.png,
// CanvasPortrait*.png, NewNotebook*.png, FinishSetup.png, LibraryUnset*.png,
// Share.png, History.png, History-naming.png, Recovery.png, Conflict.png,
// PrintLayout.png.
//
// Regenerate after an intended visual change:
//   flutter test --update-goldens test/golden
@Tags(['golden'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:endless/app.dart' show routerProvider;
import 'package:endless/board/codec.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/state/changes.dart' show versionStoreProvider;
import 'package:endless/state/notebook.dart';
import 'package:endless/sync/conflicts.dart';
import 'package:endless/sync/versions.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/ui/canvas/shortcuts.dart';
import 'package:endless/ui/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// The sample notebook on page 3, like the design's canvas screens.
void _canvas(
  String name, {
  Size? size,
  List<String>? shortcuts,
  Future<void> Function(WidgetTester t)? setUp,
  Future<void> Function(MemoryBoardStore store, LoadedNotebook nb)? before,
}) {
  testWidgets(name, (tester) => _withShadows(() async {
        var settings = AppSettings();
        if (shortcuts != null) settings = settings.withShortcuts(shortcuts);
        final nb = sampleNotebook();
        final store = storeWith(nb, settings: settings);
        await before?.call(store, nb);
        await pumpCanvas(tester, store: store, size: size);
        canvasPane.goTo(2);
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

  // §10: your shortcuts.
  _canvas('canvas_shortcuts', setUp: (t) => t.tap(byLabel('Add or edit your shortcuts')));
  _canvas('canvas_shortcuts_search', setUp: (t) async {
    await t.tap(byLabel('Add or edit your shortcuts'));
    await _settle(t);
    await t.enterText(find.byType(TextField), 'web');
  });
  _canvas('canvas_pin_from_menu', shortcuts: ['image', 'mic'], setUp: (t) => t.tap(byLabel('Insert')));
  _canvas('canvas_shortcuts_in_use', shortcuts: ['mic', 'pdf', 'ruler', 'image'], setUp: (t) => t.tap(byLabel('Ruler')));

  // §8: the canvas in portrait.
  _canvas('canvas_portrait', size: portraitSize);
  _canvas('canvas_portrait_pen', size: portraitSize, setUp: (t) => t.tap(byLabel('Pen')));
  _canvas('canvas_portrait_more', size: portraitSize, setUp: (t) => t.tap(byLabel('More options')));
  _canvas('canvas_portrait_shortcuts', size: portraitSize, setUp: (t) => t.tap(byLabel('Add or edit your shortcuts')));

  // §6: New notebook, Skip for now and Finish setting up.
  _golden('new_notebook', Routes.start, setUp: (t) async {
    await _tap(t, 'New notebook');
    await t.enterText(find.byType(TextField), 'Biology 101');
    await _tap(t, 'Green');
    await _tap(t, 'School folder');
  });
  _golden('new_notebook_no_backup', Routes.start, setUp: (t) async {
    await _tap(t, 'New notebook');
    await t.enterText(find.byType(TextField), 'Biology 101');
    final sw = find.byType(Switch);
    if (t.widget<Switch>(sw).value) await t.tap(sw);
  });
  _golden('new_notebook_portrait', Routes.start, size: portraitSize, setUp: (t) => _tap(t, 'New notebook'));
  Future<void> skipped(WidgetTester t) async {
    await _tap(t, 'New notebook');
    await _tap(t, 'Skip for now. Set up later from More options');
    await t.pump(const Duration(seconds: 1));
    ProviderScope.containerOf(t.element(find.byType(MaterialApp))).read(routerProvider).go(Routes.all);
    await _settle(t);
    await t.pump(const Duration(seconds: 1));
    await t.pump();
  }
  _golden('library_unset', Routes.start, setUp: (t) async {
    await skipped(t);
    await t.longPress(find.text('Untitled notebook'));
  });
  _golden('library_unset_other_menu', Routes.start, setUp: (t) async {
    await skipped(t);
    await t.longPress(find.text('Calculus II'));
  });
  _golden('finish_setup', Routes.start, setUp: (t) async {
    await skipped(t);
    await t.longPress(find.text('Untitled notebook'));
    await _settle(t);
    await t.tap(find.text('Finish setting up'));
  });

  // §1: Share a copy.
  _canvas('share_copy', setUp: (t) => t.tap(byLabel('Share')));
  _canvas('share_copy_board', setUp: (t) async {
    await t.tap(byLabel('Share'));
    await _settle(t);
    await t.tap(find.text('Board file'));
    await _settle(t);
    await t.tap(find.text('Save to tablet'));
  });

  // §4: Version history, with an earlier version and one from another device.
  Future<void> history(WidgetTester t) async {
    final c = ProviderScope.containerOf(t.element(find.byType(MaterialApp)));
    final nb = c.read(notebookProvider(canvasPane.notebookId));
    final page = nb.pageAt(canvasPane.page).page;
    final store = c.read(versionStoreProvider).store;
    var minutes = -90;
    final versions = VersionStore(store, clock: () => testNow.toUtc().add(Duration(minutes: minutes += 40)));
    Uint8List bytes(BoardPage p) => Uint8List.fromList(utf8.encode(encodePage(p)));
    final half = BoardPage(id: page.id, items: page.items.take(page.items.length ~/ 2).toList());
    await t.runAsync(() async {
      await versions.keep(canvasPane.notebookId, page.id, bytes(half), reason: VersionReason.edit);
      await versions.keep(canvasPane.notebookId, page.id, bytes(page), reason: VersionReason.sync, device: 'Kieth’s phone');
    });
    // Something since erased.
    c.read(notebookProvider(canvasPane.notebookId).notifier).removeItems(page.id, [page.items.first.id]);
    await t.tap(byLabel('More options'));
    await _settle(t);
    await t.tap(find.text('Version history'));
    await _settle(t);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await _settle(t);
    // The version from before the phone's changes: what it added, what's gone since.
    await t.tap(find.textContaining('Before changes from').last);
    await _settle(t);
  }
  _canvas('history', setUp: history);
  _canvas('history_naming', setUp: (t) async {
    await history(t);
    await t.tap(find.text('Name this version'));
  });

  // §3: crash recovery, the strokes the journal had and page 3 didn't.
  _canvas('recovery', before: (store, nb) async {
    final page = nb.pages[2];
    final lines = StringBuffer();
    for (final (x, y) in [(560.0, 620.0), (640.0, 624.0), (720.0, 618.0), (560.0, 680.0), (660.0, 684.0)]) {
      final s = strokeFrom([Offset(x, y), Offset(x + 30, y - 8), Offset(x + 60, y + 4)]);
      lines.writeln(jsonEncode({'t': testNow.toUtc().millisecondsSinceEpoch, 'page': page.id, 'item': jsonDecode(s.encoded)}));
    }
    await store.appendJournal(nb.notebook.id, lines.toString());
  });

  // §2: a page changed on two devices.
  _canvas('conflict', setUp: (t) async {
    final c = ProviderScope.containerOf(t.element(find.byType(MaterialApp)));
    final page = c.read(notebookProvider(canvasPane.notebookId)).pageAt(canvasPane.page).page;
    Uint8List bytes(BoardPage p) => Uint8List.fromList(utf8.encode(encodePage(p)));
    final ours = [for (var i = 0; i < 3; i++) strokeFrom([Offset(120.0 + i * 40, 620), Offset(150.0 + i * 40, 640)])];
    final theirs = [for (var i = 0; i < 2; i++) strokeFrom([Offset(560.0 + i * 60, 640), Offset(600.0 + i * 60, 660)])];
    final versions = c.read(versionStoreProvider);
    final (o, th) = (await t.runAsync(() async {
      final o = await versions.keep(canvasPane.notebookId, page.id, bytes(BoardPage(id: page.id, items: [...page.items, ...ours])),
          reason: VersionReason.sync, device: 'Kieth’s phone');
      final th = await versions.keep(canvasPane.notebookId, page.id,
          bytes(BoardPage(id: page.id, items: [...page.items, ...theirs])),
          reason: VersionReason.remote, device: 'Kieth’s phone');
      return (o, th);
    }))!;
    expect((o, th), isNotNull);
    unawaited(c.read(conflictsProvider.notifier).add(PageConflict(
          notebookId: canvasPane.notebookId,
          pageId: page.id,
          device: 'Kieth’s phone',
          theirsAt: testNow.toUtc().subtract(const Duration(minutes: 30)),
          oursAt: testNow.toUtc().subtract(const Duration(minutes: 10)),
          ours: o!,
          theirs: th!,
        )));
    await _settle(t);
    await t.tap(find.text('1 page to check'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await _settle(t);
  });

  // §7: Print layout, with something no page covers.
  Future<void> printLayout(WidgetTester t, {bool removeLast = true}) async {
    await t.tap(byLabel('More options'));
    await _settle(t);
    await t.tap(find.text('Print…'));
    await _settle(t);
    if (!removeLast) return;
    final last = find.textContaining(RegExp(r'^Page \d+$')).last;
    await t.tap(last);
    await _settle(t);
    await t.tap(find.bySemanticsLabel(RegExp(r'^Remove page')));
  }
  _canvas('print_layout',
      before: (store, nb) async {
        nb.pages[2].items.add(strokeFrom([const Offset(1100, 900), const Offset(1300, 940)]));
        await store.savePage(nb.notebook.id, nb.pages[2]);
      },
      setUp: printLayout);
  _canvas('print_layout_covered', setUp: (t) => printLayout(t, removeLast: false));
  _canvas('print_layout_portrait', size: portraitSize, setUp: (t) => printLayout(t, removeLast: false));
}
