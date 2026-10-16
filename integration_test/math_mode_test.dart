import 'dart:convert';
import 'dart:io';

import 'package:endless/board/model.dart';
import 'package:endless/canvas/selection.dart';
import 'package:endless/math/decoder.dart' show mathVocab;
import 'package:endless/math/latex.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers.dart';

// Math mode in the app, for real: pen strokes picked up when the pen rests,
// read by the bundled model, previewed and converted to typeset math.
//   flutter test integration_test/math_mode_test.dart -d windows

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('write, pause, Convert to math', (tester) async {
    final sample = (jsonDecode(File('test/fixtures/math/ink_samples.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((s) => s['label'] == r'2^{k}t_{0}');
    final c = await pumpCanvas(tester);
    canvasPane.math.start();
    await tester.pump();

    // The sample's strokes, 70 px tall, written with the pen at (300, 300).
    final strokes = [
      for (final s in sample['strokes'] as List)
        [for (final p in s as List) Offset((p[0] as num).toDouble(), (p[1] as num).toDouble())],
    ];
    final all = strokes.expand((s) => s).toList();
    final left = all.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
    final top = all.map((p) => p.dy).reduce((a, b) => a < b ? a : b);
    final bottom = all.map((p) => p.dy).reduce((a, b) => a > b ? a : b);
    final k = 70 / (bottom - top);
    for (final s in strokes) {
      final g = await tester.createGesture(kind: PointerDeviceKind.stylus);
      final pts = [for (final p in s) Offset(300 + (p.dx - left) * k, 300 + (p.dy - top) * k)];
      await g.down(pts.first);
      for (final p in pts.skip(1)) {
        await g.moveTo(p);
      }
      await g.up();
      await tester.pump();
    }

    // Picked up once the pen rests, read, and previewed.
    await settleReal(tester, () => canvasPane.selection.isNotEmpty, timeout: const Duration(seconds: 10));
    expect(canvasPane.selection.menu, SelectionMenu.math);
    await settleReal(tester, () => find.text('Reading…').evaluate().isEmpty, timeout: const Duration(seconds: 60));
    expect(find.text('PREVIEW'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Convert to math'));
    await settleReal(tester, () => shownPage(c).items.any((i) => i is MathItem), timeout: const Duration(seconds: 30));
    final m = shownPage(c).items.whereType<MathItem>().single;
    final want = latexFromSymbols((sample['read'] as List).cast<String>());
    debugPrint('Converted: ${m.latex} (${m.w.round()}×${m.h.round()})');
    expect(m.latex, want);
    expect(shownPage(c).items.whereType<StrokeItem>(), isEmpty);
    expect(mathVocab, isNotEmpty);
  });
}
