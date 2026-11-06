import 'package:endless/theme/colors.dart';
import 'package:endless/theme/palettes.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:flutter/material.dart' show Brightness, Color;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Paper with its own accent is exactly the Paper palette', () {
    expect(identical(paletteFor('paper', themeAccent, Brightness.light), tokens.paperLight), isTrue);
    expect(identical(paletteFor('paper', themeAccent, Brightness.dark), tokens.paperDark), isTrue);
  });

  test('the recipes, applied to Paper\'s own 7 colors, give Paper\'s palette (within rounding)', () {
    // Paper with Blue (its own accent color) goes through the recipes.
    for (final (b, base) in [(Brightness.light, tokens.paperLight), (Brightness.dark, tokens.paperDark)]) {
      final made = tokens.colorsToMap(paletteFor('paper', 'blue', b));
      for (final e in tokens.colorsToMap(base).entries) {
        final m = made[e.key]!;
        expect((m.r - e.value.r).abs() * 255, lessThanOrEqualTo(1.01), reason: '${e.key} $b');
        expect((m.g - e.value.g).abs() * 255, lessThanOrEqualTo(1.01), reason: '${e.key} $b');
        expect((m.b - e.value.b).abs() * 255, lessThanOrEqualTo(1.01), reason: '${e.key} $b');
        expect(m.a, e.value.a, reason: '${e.key} $b');
      }
    }
  });

  test('every theme uses its 7 colors from tokens.json; meaningful colors stay', () {
    for (final theme in themeNames.keys) {
      for (final b in Brightness.values) {
        final p = paletteFor(theme, themeAccent, b);
        final s = swatchOf(theme, b);
        expect(p.bg, s.bg, reason: theme);
        expect(p.side, s.side, reason: theme);
        expect(p.surface, s.surface, reason: theme);
        expect(p.line, s.line, reason: theme);
        expect(p.text, s.text, reason: theme);
        expect(p.dot, s.dot, reason: theme);
        expect(p.accent, s.accent, reason: theme);
        final base = b == Brightness.light ? tokens.paperLight : tokens.paperDark;
        expect(p.clay, base.clay);
        expect(p.record, base.record);
        expect(p.star, base.star);
      }
    }
  });

  test('an accent changes the accent colors only', () {
    final p = paletteFor('sage', 'rose', Brightness.light);
    expect(p.accent, tokens.accents['rose']!.$1);
    expect(p.accentTint, isNot(paletteFor('sage', themeAccent, Brightness.light).accentTint));
    expect(p.paperLine, paletteFor('sage', themeAccent, Brightness.light).paperLine);
    expect(p.text, swatchOf('sage', Brightness.light).text);
  });

  test('High contrast keeps text readable on its surfaces', () {
    double lum(Color c) => 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
    for (final b in Brightness.values) {
      final p = paletteFor('contrast', themeAccent, b);
      expect((lum(p.text) - lum(p.surface)).abs(), greaterThan(0.9));
      expect((lum(p.textMuted) - lum(p.surface)).abs(), greaterThan(0.3));
    }
  });

  test('unknown themes and accents fall back to Paper and the theme accent', () {
    expect(identical(paletteFor('nope', 'nope', Brightness.light), tokens.paperLight), isTrue);
    expect(accentOf('harbor', themeAccent, Brightness.dark), swatchOf('harbor', Brightness.dark).accent);
    expect(EndlessColors, isNotNull);
  });
}
