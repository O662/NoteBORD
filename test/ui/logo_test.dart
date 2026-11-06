import 'dart:io';

import 'package:endless/theme/tokens.g.dart' show LogoColors;
import 'package:endless/ui/logo.dart';
import 'package:endless/ui/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

String _res(String path) => File('android/app/src/main/res/$path').readAsStringSync();

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the sidebar shows the mark beside "Endless"', (tester) async {
    await pumpApp(tester);
    expect(find.byType(EndlessMark), findsOneWidget);
    expect(tester.getSize(find.byType(EndlessMark)), const Size(40, 40 * 72 / 104));
    expect(find.text('Endless'), findsOneWidget);
  });

  testWidgets('About has the wordmark and the tagline', (tester) async {
    await pumpApp(tester, location: Routes.settings('about'));
    await tester.pump();
    expect(find.text('A Notebook Built for Students, by Students'), findsOneWidget);
  });

  test('the mark uses the logo file\'s strokes', () {
    final svg = File('design/logo/endless-icon-paper.svg').readAsStringSync();
    for (final (d, w) in logoStrokes) {
      expect(svg, contains('d="$d"'));
      expect(svg, contains('stroke-width="${w == w.roundToDouble() ? w.round() : w}"'));
    }
    expect(LogoColors.paper, const Color(0xFFF6F1E7));
    expect(LogoColors.ink, const Color(0xFF0C0C0C));
  });

  test('Android: the adaptive icon (with a monochrome layer), the notification icon, the splash', () {
    final adaptive = _res('mipmap-anydpi-v26/ic_launcher.xml');
    expect(adaptive, contains('@color/ic_launcher_background'));
    expect(adaptive, contains('@drawable/ic_launcher_foreground'));
    expect(adaptive, contains('<monochrome'));
    expect(_res('values/colors.xml'), contains('<color name="ic_launcher_background">#F6F1E7</color>'));
    expect(_res('values-night/colors.xml'), contains('#1C1A17'));
    for (final f in ['drawable/ic_launcher_foreground.xml', 'drawable/ic_notification.xml', 'drawable/splash_mark.xml', 'drawable-night/splash_mark.xml']) {
      final xml = _res(f);
      for (final (d, _) in logoStrokes) {
        expect(xml, contains(d), reason: f);
      }
      expect(xml, contains('android:scaleX="0.66"'), reason: f);
    }
    expect(_res('drawable/ic_notification.xml'), contains('#FFFFFF'));
    expect(_res('drawable-night/splash_mark.xml'), contains('#EEE8DC'));
    expect(_res('values-v31/styles.xml'), contains('windowSplashScreenAnimatedIcon'));
    for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      expect(File('android/app/src/main/res/mipmap-$d/ic_launcher.png').existsSync(), isTrue);
    }
  });
}
