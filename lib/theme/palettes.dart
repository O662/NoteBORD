import 'package:flutter/material.dart' show Brightness, Color;

import 'colors.dart';
import 'tokens.g.dart' as tokens;

/// The 7 themes (Themes.png), by id, with their names.
const themeNames = {
  'paper': 'Paper',
  'midnight': 'Midnight',
  'sage': 'Sage',
  'blush': 'Blush',
  'graphite': 'Graphite',
  'contrast': 'High contrast',
  'harbor': 'Harbor',
};

/// The accent choices after "Theme default" (Themes.dc.html `A`).
const accentNames = {
  'blue': 'Blue',
  'terracotta': 'Terracotta',
  'green': 'Green',
  'plum': 'Plum',
  'teal': 'Teal',
  'gold': 'Gold',
  'rose': 'Rose',
};

/// "Theme default" in the accent row.
const themeAccent = 'theme';

/// The 7 colors of [theme] in [brightness] (Paper for one this app doesn't know).
ThemeSwatch swatchOf(String theme, Brightness brightness) {
  final pair = tokens.themeSwatches[theme] ?? tokens.themeSwatches['paper']!;
  return brightness == Brightness.light ? pair.$1 : pair.$2;
}

/// The accent color [accent] stands for in [theme] ([themeAccent]: the theme's own).
Color accentOf(String theme, String accent, Brightness brightness) {
  final pick = tokens.accents[accent];
  if (pick == null) return swatchOf(theme, brightness).accent;
  return brightness == Brightness.light ? pick.$1 : pick.$2;
}

final _cache = <(String, String, Brightness), EndlessColors>{};

/// The full palette of [theme] with [accent], made from the theme's 7
/// colors by the recipes in tokens.g.dart (Paper's own colors, exactly, for
/// Paper with its own accent).
EndlessColors paletteFor(String theme, String accent, Brightness brightness) {
  final light = brightness == Brightness.light;
  final key = (themeNames.containsKey(theme) ? theme : 'paper', tokens.accents.containsKey(accent) ? accent : themeAccent, brightness);
  return _cache[key] ??= () {
    final base = light ? tokens.paperLight : tokens.paperDark;
    if (key.$1 == 'paper' && key.$2 == themeAccent) return base;
    final s = swatchOf(key.$1, brightness);
    final picked = accentOf(key.$1, key.$2, brightness);
    final recipes = light ? tokens.recipesLight : tokens.recipesDark;
    final baseMap = tokens.colorsToMap(base);
    Color core(String name, {required bool useAccent}) => switch (name) {
          'bg' => s.bg,
          'side' => s.side,
          'surface' => s.surface,
          'line' => s.line,
          'text' => s.text,
          'dot' => s.dot,
          'accent' => useAccent ? picked : s.accent,
          'black' => const Color(0xFF000000),
          _ => const Color(0xFFFFFFFF),
        };
    int ch(double v) => v.round().clamp(0, 255);
    final out = <String, Color>{};
    for (final e in baseMap.entries) {
      final r = recipes[e.key];
      if (r == null) {
        out[e.key] = e.value;
        continue;
      }
      // The chosen accent shows in the accent colors; everything else keeps
      // the theme's own (lined paper, for one, stays the theme's blue).
      final useAccent = e.key.startsWith('accent');
      final a = core(r.a, useAccent: useAccent), b = core(r.b, useAccent: useAccent);
      double mix(double x, double y) => (x + (y - x) * r.t) * 255;
      out[e.key] = Color.fromARGB(
        r.alpha,
        ch(mix(a.r, b.r) + r.dr),
        ch(mix(a.g, b.g) + r.dg),
        ch(mix(a.b, b.b) + r.db),
      );
    }
    return tokens.colorsFromMap(out);
  }();
}
