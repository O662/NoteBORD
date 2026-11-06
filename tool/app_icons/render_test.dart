// Renders the launcher icons Android 7 (API 24–25) uses, from the Endless
// mark (design/logo/endless-icon-paper.svg: ink on paper, rounded):
//
//   flutter test tool/app_icons/render_test.dart
//
// Android 8+ uses the adaptive icon in res/mipmap-anydpi-v26 (vector
// drawables, no PNGs). Run this again if the mark changes.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:endless/theme/tokens.g.dart' show LogoColors;
import 'package:endless/ui/logo.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Launcher icon sizes by density (48 dp).
const _sizes = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};

Future<List<int>> _icon(int px) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final s = px / 120;
  // endless-icon-paper.svg: rect 0.5, 0.5, 119 × 119, corners 28; the mark at full size.
  canvas.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTWH(0.5 * s, 0.5 * s, 119 * s, 119 * s), Radius.circular(28 * s)),
    Paint()..color = LogoColors.paper,
  );
  paintLogoMark(canvas, Offset.zero & Size(px.toDouble(), px.toDouble()), LogoColors.ink, box: const Rect.fromLTWH(0, 0, 120, 120));
  final image = await recorder.endRecording().toImage(px, px);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  return png!.buffer.asUint8List();
}

void main() {
  test('launcher icons', () async {
    for (final e in _sizes.entries) {
      final file = File('android/app/src/main/res/mipmap-${e.key}/ic_launcher.png');
      await file.writeAsBytes(await _icon(e.value));
      expect(file.lengthSync(), greaterThan(100));
    }
  });
}
