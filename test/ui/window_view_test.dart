import 'package:endless/canvas/ink_canvas.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/ui/canvas/window_view.dart';
import 'package:endless/ui/split/split_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

Future<void> _openWindow(WidgetTester tester) async {
  await tester.tap(byLabel('Ruler, laser & view'));
  await tester.pump();
  await tester.tap(find.text('Window view'));
  await tester.pumpAndSettle();
}

Rect _window(WidgetTester tester) => tester.getRect(find.byWidgetPredicate((w) => w is Semantics && (w.properties.label ?? '').startsWith('Window view:')));

InkCanvas _mainCanvas(WidgetTester tester) => tester.widgetList<InkCanvas>(find.byType(InkCanvas)).first;

void main() {
  setUpAll(loadAppFonts);

  testWidgets('Ruler, laser & view → Window view opens a window on the next page; drag, lock, resize', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpCanvas(tester, store: storeWith(sampleNotebook()));
    await _openWindow(tester);
    expect(find.byType(WindowView), findsOneWidget);
    expect(find.text('This notebook · page 2'), findsOneWidget);
    expect(_window(tester), const Rect.fromLTWH(452, 286, 470, 330));

    // Dragging the title bar moves it; it stays on screen.
    await tester.drag(find.text('This notebook · page 2'), const Offset(-100, -50));
    await tester.pumpAndSettle();
    expect(_window(tester).topLeft, const Offset(352, 236));
    // Locked, it doesn't move.
    await tester.tap(byLabel('Lock position'));
    await tester.pump();
    final at = _window(tester).topLeft;
    await tester.drag(find.text('This notebook · page 2'), const Offset(300, 300));
    await tester.pumpAndSettle();
    expect(_window(tester).topLeft, at);
    await tester.tap(byLabel('Unlock position'));
    await tester.pump();

    // The corner resizes it, 340 × 200 to 960 × 700.
    await tester.drag(find.bySemanticsLabel('Resize window'), const Offset(-500, -500));
    await tester.pumpAndSettle();
    expect(_window(tester).size, WindowSpot.minSize);
    await tester.drag(find.bySemanticsLabel('Resize window'), const Offset(2000, 2000));
    await tester.pumpAndSettle();
    expect(_window(tester).size, WindowSpot.maxSize);

    // It stays on screen: at least 120 dp of it.
    await tester.drag(find.text('This notebook · page 2'), const Offset(-2000, -2000));
    await tester.pumpAndSettle();
    expect(_window(tester).left, WindowSpot.keepOnScreen - WindowSpot.maxSize.width);
    expect(_window(tester).top, 0);
    semantics.dispose();
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('opacity, zoom 50–200%, Pen: window, and what it shows', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpCanvas(tester, store: storeWith(sampleNotebook()));
    await _openWindow(tester);
    expect(find.text('88%'), findsOneWidget);
    expect(tester.widget<Opacity>(find.ancestor(of: find.byType(InkCanvas).last, matching: find.byType(Opacity)).first).opacity, 0.88);

    for (var i = 0; i < 6; i++) {
      await tester.tap(byLabel('Zoom in in the window'));
      await tester.pump();
    }
    expect(find.text('200%'), findsOneWidget);
    for (var i = 0; i < 8; i++) {
      await tester.tap(byLabel('Zoom out in the window'));
      await tester.pump();
    }
    expect(find.text('50%'), findsOneWidget);

    // Read-only by default; Pen: window writes there and not on the page.
    expect(_mainCanvas(tester).writable, isTrue);
    expect(tester.widgetList<InkCanvas>(find.byType(InkCanvas)).last.writable, isFalse);
    await tester.tap(find.text('Pen: page'));
    await tester.pump();
    expect(find.text('Pen writes here'), findsOneWidget);
    expect(_mainCanvas(tester).writable, isFalse);
    expect(tester.widgetList<InkCanvas>(find.byType(InkCanvas)).last.writable, isTrue);
    await tester.tap(find.text('Pen: window'));
    await tester.pump();
    expect(_mainCanvas(tester).writable, isTrue);

    // What it shows: another page, or another spot on this one.
    await tester.tap(find.bySemanticsLabel(RegExp('^Show in the window:')));
    await tester.pump();
    expect(find.text('SHOW IN THE WINDOW'), findsOneWidget);
    await tester.tap(find.text('This notebook · page 3'));
    await tester.pumpAndSettle();
    expect(find.text('Lecture 3 — Momentum'), findsWidgets);
    await tester.tap(find.bySemanticsLabel(RegExp('^Show in the window:')));
    await tester.pump();
    await tester.tap(find.text('This page · another spot'));
    await tester.pumpAndSettle();
    expect(find.text('This page · another spot'), findsOneWidget);
    semantics.dispose();
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('swap, shrink to a bubble and back, close; it comes back where you left it', (tester) async {
    final semantics = tester.ensureSemantics();
    final store = storeWith(sampleNotebook());
    final c = await pumpCanvas(tester, store: store);
    await _openWindow(tester);
    await tester.drag(find.text('This notebook · page 2'), const Offset(-200, 0));
    await tester.pumpAndSettle();

    // Swap: page 2 in the main view, page 1 in the window.
    await tester.tap(byLabel('Show this in the main view'));
    await tester.pumpAndSettle();
    expect(canvasPane.page, 1);
    expect(find.text('This notebook · page 1'), findsOneWidget);

    await tester.tap(byLabel('Shrink to a bubble'));
    await tester.pumpAndSettle();
    expect(find.text('This notebook · page 1'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('^Open window:')), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(RegExp('^Open window:')));
    await tester.pumpAndSettle();
    expect(find.text('This notebook · page 1'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    final saved = c.read(settingsProvider).prefs['window:nb_sample'] as Map;
    expect(saved['open'], isTrue);
    expect((saved['rect'] as List).first, 252);
    expect(saved['page'], 0);

    await tester.tap(byLabel('Close window'));
    await tester.pumpAndSettle();
    expect(find.byType(WindowView), findsOneWidget);
    expect(find.text('This notebook · page 1'), findsNothing);
    await _openWindow(tester);
    expect(_window(tester).left, 252);
    semantics.dispose();
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Open as split view: the page and what the window shows, side by side', (tester) async {
    await pumpCanvas(tester, store: storeWith(sampleNotebook()));
    await _openWindow(tester);
    await tester.tap(byLabel('Open as split view'));
    await tester.pumpAndSettle();
    expect(find.byType(SplitScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  test('a saved window is read back; sizes and places are kept in bounds', () {
    const s = WindowSpot(notebookId: 'nb', page: 2, open: true, opacity: 0.5, rect: Rect.fromLTWH(10, 20, 500, 300), pinned: true, penHere: true, scale: 1.5);
    final back = WindowSpot.fromJson(s.toJson(), fallbackNotebook: 'x')!;
    expect(back.rect, s.rect);
    expect(back.opacity, 0.5);
    expect(back.pinned, isTrue);
    expect(back.penHere, isTrue);
    expect(back.scale, 1.5);
    expect(back.page, 2);
    expect(WindowSpot.fit(const Rect.fromLTWH(2000, 900, 100, 5000), const Size(1280, 800)), const Rect.fromLTWH(1160, 754, 340, 700));
  });
}
