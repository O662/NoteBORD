import 'dart:convert';
import 'dart:io';

import 'package:endless/math/decoder.dart';
import 'package:endless/math/ink_image.dart';
import 'package:endless/math/onnx_math.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// The bundled math model, run for real through ONNX Runtime:
//   flutter test integration_test/math_model_test.dart -d windows
// It must read the pen strokes in test/fixtures/math as the Python
// reference does (tool/math_model/make_fixtures.py).

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the math model reads handwriting as the reference does', (tester) async {
    final samples = (jsonDecode(File('test/fixtures/math/ink_samples.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    await tester.runAsync(() async {
      final model = await OnnxMathModel.load();
      try {
        for (final s in samples) {
          final strokes = [
            for (final stroke in s['strokes'] as List)
              [for (final p in stroke as List) Offset((p[0] as num).toDouble(), (p[1] as num).toDouble())],
          ];
          final watch = Stopwatch()..start();
          final best = (await readMath(model, renderInk(strokes)!)).first;
          debugPrint('${s['label']}: ${best.symbols.join(' ')} in ${watch.elapsedMilliseconds} ms');
          expect(best.symbols, (s['read'] as List).cast<String>(), reason: s['label'] as String);
          expect(best.score, closeTo((s['score'] as num).toDouble(), 0.05));
        }
      } finally {
        await model.close();
      }
    });
  });
}
