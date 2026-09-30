// Golden images of the Phase 3a pen gestures at 1280×800. Compare with
// design/screens/Convert.png, RememberMark.png, Tools.png, Arrows.png and
// Scribble.png.
//
// Regenerate after an intended visual change:
//   flutter test --update-goldens test/golden
@Tags(['golden'])
library;

import 'dart:math' as math;

import 'package:endless/board/model.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:flutter/gestures.dart';
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

List<Offset> _loop(Offset c, double rx, double ry) => [
      for (var i = 0; i <= 60; i++) c + Offset(math.cos(i / 60 * 2 * math.pi) * rx, math.sin(i / 60 * 2 * math.pi) * ry),
    ];

List<Offset> _shaky(Offset a, Offset b) => [
      for (var i = 0; i <= 40; i++) Offset.lerp(a, b, i / 40)! + Offset(0, math.sin(i / 40 * math.pi * 3) * 5),
    ];

/// Draws with the S Pen; leaves it down when [lift] is false.
Future<TestGesture> _pen(WidgetTester t, List<Offset> pts, {bool lift = true}) async {
  final g = await t.createGesture(kind: PointerDeviceKind.stylus);
  var ts = const Duration(seconds: 20);
  await g.down(pts.first, timeStamp: ts);
  for (final p in pts.skip(1)) {
    ts += const Duration(milliseconds: 8);
    await g.moveTo(p, timeStamp: ts);
  }
  if (lift) await g.up(timeStamp: ts);
  await t.pump();
  return g;
}

/// The sample notebook's page 3 (Lecture 3 — Momentum), then [setUp], then
/// compares with `gestures_<name>.png`. [after] runs once the image is taken.
void _golden(
  String name, {
  AppSettings? settings,
  required Future<Object?> Function(WidgetTester t, ProviderContainer c) setUp,
  Future<void> Function(WidgetTester t, Object? state)? after,
}) {
  testWidgets(name, (tester) => _withShadows(() async {
        final store = storeWith(sampleNotebook(), settings: settings);
        final c = await pumpCanvas(tester, store: store);
        canvasPane.goTo(2);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400)); // the page rail settles
        final state = await setUp(tester, c);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('gestures_$name.png'));
        await after?.call(tester, state);
        await tester.pump(const Duration(seconds: 5));
      }));
}

void main() {
  setUpAll(loadAppFonts);

  // Convert.png: a lasso around a line of writing, toolbar above it.
  _golden('lasso', setUp: (t, c) async {
    await t.tap(byLabel('Lasso select'));
    await t.pump();
    await _pen(t, _loop(const Offset(900, 300), 200, 42));
    await t.pump(const Duration(seconds: 5)); // the tool hint times out
    return null;
  });

  // RememberMark.png: the Remember toolbar, below a selection near the top.
  _golden('remember', setUp: (t, c) async {
    await t.tap(byLabel('Study & math'));
    await t.pump();
    await t.tap(find.text('Need to remember'));
    await t.pump();
    await _pen(t, _loop(const Offset(920, 160), 210, 40));
    await t.pump(const Duration(seconds: 5));
    return null;
  });

  // Tools.png step 2: holding; the ring fills and the line shows dashed.
  _golden('hold', setUp: (t, c) async {
    final g = await _pen(t, _shaky(const Offset(200, 470), const Offset(560, 330)), lift: false);
    await t.pump(const Duration(milliseconds: 200));
    await t.pump(const Duration(milliseconds: 150));
    return g;
  }, after: (t, g) async {
    await (g! as TestGesture).up();
    await t.pump();
  });

  // Tools.png step 3: straightened, with its angle and Undo.
  _golden('straightened', setUp: (t, c) async {
    final g = await _pen(t, _shaky(const Offset(200, 470), const Offset(560, 330)), lift: false);
    await t.pump(const Duration(milliseconds: 200));
    await t.pump(const Duration(milliseconds: 400));
    await g.up();
    await t.pump();
    return null;
  });

  // Scribble.png step 2: what will go shows faded red.
  _golden('scribble', setUp: (t, c) async {
    final zig = [
      for (var i = 0; i < 12; i++)
        for (var s = 0; s < 6; s++)
          Offset.lerp(Offset(160 + i * 12.0, i.isEven ? 600 : 552), Offset(160 + (i + 1) * 12.0, i.isEven ? 552 : 600), s / 6)!,
    ];
    return _pen(t, zig, lift: false);
  }, after: (t, g) async {
    await (g! as TestGesture).up();
    await t.pump();
  });

  // Arrows.png: open, filled and "like my ink" heads, a curve and both ends.
  _golden('arrows', settings: AppSettings(penColor: tokens.inkDefaults[1]), setUp: (t, c) async {
    Future<void> arrow(List<Offset> line, Offset hook, ArrowStyle style, {Offset? startHook}) async {
      c.read(settingsProvider.notifier).apply((s) => s.copyWith(arrowStyle: style));
      await _pen(t, [
        if (startHook != null) ...[for (var i = 0; i < 5; i++) Offset.lerp(startHook, line.first, i / 5)!],
        ...line,
        for (var i = 1; i <= 5; i++) Offset.lerp(line.last, hook, i / 5)!,
      ]);
    }

    List<Offset> straight(Offset a, Offset b) => [for (var i = 0; i <= 40; i++) Offset.lerp(a, b, i / 40)!];
    await arrow(straight(const Offset(160, 300), const Offset(440, 190)), const Offset(416, 208), ArrowStyle.open);
    await arrow(straight(const Offset(160, 400), const Offset(440, 330)), const Offset(416, 344), ArrowStyle.filled);
    await arrow(straight(const Offset(160, 500), const Offset(440, 460)), const Offset(416, 472), ArrowStyle.ink);
    final curve = [
      for (var i = 0; i <= 50; i++) Offset(520 + 90 - 90 * math.cos(i / 50 * math.pi * 0.8), 700 - 170 * math.sin(i / 50 * math.pi * 0.8)),
    ];
    final end = curve.last, back = (curve[curve.length - 4] - end) / (curve[curve.length - 4] - end).distance;
    await arrow(curve, end + Offset(back.dx * 0.9 - back.dy * 0.4, back.dy * 0.9 + back.dx * 0.4) * 22, ArrowStyle.open);
    await arrow(straight(const Offset(250, 640), const Offset(470, 640)), const Offset(450, 654), ArrowStyle.open,
        startHook: const Offset(270, 626));
    await t.pump(const Duration(seconds: 5));
    return null;
  });

  // Tools.png: the ruler at 8° with a line along its edge, and the laser.
  _golden('ruler_laser', setUp: (t, c) async {
    await t.tap(byLabel('Ruler, laser & view'));
    await t.pump();
    await t.tap(find.text('Ruler'));
    await t.pump();
    canvasPane.ruler.rotateAbout(canvasPane.ruler.center, -8 * math.pi / 180);
    final c = canvasPane.ruler.center;
    final u = Offset(math.cos(-8 * math.pi / 180), math.sin(-8 * math.pi / 180));
    final v = Offset(-u.dy, u.dx);
    await _pen(t, [for (var i = 0; i <= 30; i++) c - v * 44 + u * (-250 + i * 12.0) + Offset(0, math.sin(i / 3) * 3)]);
    await t.tap(byLabel('Ruler, laser & view'));
    await t.pump();
    await t.tap(find.text('Laser pointer'));
    await t.pump();
    final g = await _pen(t, [
      for (var i = 0; i <= 60; i++) Offset(700 + i * 6.0, 420 + 30 * math.sin(i / 8)),
    ], lift: false);
    return g;
  }, after: (t, g) async {
    await (g! as TestGesture).up();
    await t.pump();
  });

  // Tapping the ruler's angle: presets, a number pad and units.
  _golden('ruler_menu', setUp: (t, c) async {
    await t.tap(byLabel('Ruler, laser & view'));
    await t.pump();
    await t.tap(find.text('Ruler'));
    await t.pump();
    canvasPane.ruler.setDegrees(30);
    await _pen(t, [canvasPane.ruler.center + const Offset(0, 12)]);
    await t.pumpAndSettle();
    for (final k in ['2', '2', 'Decimal point', '5']) {
      await t.tap(find.bySemanticsLabel(k));
      await t.pump();
    }
    await t.pump(const Duration(seconds: 5));
    return null;
  });

  // Arrows.png and Scribble.png settings panels (in the stand-in Settings).
  _golden('settings', setUp: (t, c) async {
    await t.tap(byLabel('More options'));
    await t.pump();
    await t.tap(find.text('Settings'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    return null;
  });
}
