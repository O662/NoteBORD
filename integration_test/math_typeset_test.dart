import 'dart:io';
import 'dart:ui' as ui;

import 'package:endless/math/math_pictures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Typesetting off screen, with real fonts and SVG pieces:
//   flutter test integration_test/math_typeset_test.dart -d windows
// MATH_PNG_DIR, if set, gets a picture of each formula to look at.

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('math is typeset off screen, √ and all', (tester) async {
    const formulas = [
      r'v=\sqrt{v_{0}^{2}+2gh}',
      r'\omega=\frac{\Delta\theta}{\Delta t}',
      r'J=\int_{t_{0}}^{t_{1}}Fdt=\Delta p',
      r'\left(\frac{a}{b}\right)^{2}',
    ];
    await tester.runAsync(() async {
      for (final (i, latex) in formulas.indexed) {
        final watch = Stopwatch()..start();
        final m = await typesetOffscreen(latex);
        expect(m, isNotNull, reason: latex);
        debugPrint('$latex: ${m!.size} in ${watch.elapsedMilliseconds} ms');
        final image = await m.picture.toImage(m.size.width.ceil(), m.size.height.ceil());
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Platform.environment['MATH_PNG_DIR'];
        if (dir != null) File('$dir/typeset_$i.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        // The √ sign (an SVG piece, with the bar over what's under it) is drawn.
        if (i == 0) {
          final raw = (await image.toByteData())!;
          var ink = 0;
          for (var y = 0; y < image.height ~/ 10; y++) {
            for (var x = (image.width * 0.4).round(); x < (image.width * 0.9).round(); x++) {
              if (raw.getUint8((y * image.width + x) * 4 + 3) > 128) ink++;
            }
          }
          expect(ink, greaterThan(0), reason: 'no √ sign');
        }
      }
    });
  });
}
