import 'package:flutter/material.dart';

import 'tokens.g.dart' as tokens;

/// One full palette (a theme in one mode). Instances come from
/// design/tokens.json through the generated tokens.g.dart.
@immutable
class EndlessColors extends ThemeExtension<EndlessColors> {
  const EndlessColors({
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.surface,
    required this.surfaceSunk,
    required this.bg,
    required this.side,
    required this.line,
    required this.lineStrong,
    required this.lineSoft,
    required this.dot,
    required this.inverse,
    required this.inverseRaised,
    required this.onInverse,
    required this.accent,
    required this.accentHover,
    required this.accentDeep,
    required this.accentTint,
    required this.onAccent,
    required this.clay,
    required this.clayTint,
    required this.green,
    required this.greenTint,
    required this.plum,
    required this.plumTint,
    required this.gold,
    required this.star,
    required this.stickyYellow,
    required this.danger,
    required this.spellUnderline,
    required this.shadow,
    required this.menuTile,
    required this.clayDeep,
    required this.greenDeep,
    required this.sideSelected,
    required this.lineDashed,
    required this.accentWash,
    required this.switchOff,
    required this.warningTint,
    required this.onWarning,
    required this.goldDeep,
    required this.moss,
    required this.paperLine,
    required this.paperGrid,
    required this.paperMargin,
    required this.scrim,
    required this.frost,
    required this.laserRed,
    required this.laserGreen,
    required this.laserBlue,
    required this.scribbleMark,
    required this.onStar,
    required this.cardLine,
    required this.plumDeep,
    required this.stickyDeep,
    required this.previewBg,
  });

  final Color text;
  final Color textMuted;
  final Color textFaint;
  final Color surface;
  final Color surfaceSunk;
  final Color bg;
  final Color side;
  final Color line;
  final Color lineStrong;
  final Color lineSoft;
  final Color dot;
  final Color inverse;
  final Color inverseRaised;
  final Color onInverse;
  final Color accent;
  final Color accentHover;
  final Color accentDeep;
  final Color accentTint;
  final Color onAccent;
  final Color clay;
  final Color clayTint;
  final Color green;
  final Color greenTint;
  final Color plum;
  final Color plumTint;
  final Color gold;
  final Color star;
  final Color stickyYellow;
  final Color danger;
  final Color spellUnderline;
  final Color shadow;

  /// Neutral icon tile in menus.
  final Color menuTile;
  final Color clayDeep;
  final Color greenDeep;

  /// Selected row in the sidebar and category lists.
  final Color sideSelected;

  /// Dashed "add" outlines (New folder, Save as template).
  final Color lineDashed;

  /// Selected option card background.
  final Color accentWash;

  /// Switch track when off.
  final Color switchOff;

  /// Warning box background.
  final Color warningTint;

  /// Warning box text.
  final Color onWarning;

  /// Text on the gold "remember" badge.
  final Color goldDeep;

  /// The green notebook and folder color.
  final Color moss;

  /// Lined paper rules.
  final Color paperLine;

  /// Graph paper grid.
  final Color paperGrid;

  /// Lined paper margin.
  final Color paperMargin;

  /// Behind dialogs.
  final Color scrim;

  /// Over a locked page.
  final Color frost;

  /// Laser pointer trail colors (Tools.dc.html).
  final Color laserRed;
  final Color laserGreen;
  final Color laserBlue;

  /// Ink that a scribble is about to erase (Scribble.dc.html).
  final Color scribbleMark;

  /// Text and icons on the yellow star (the Remember button).
  final Color onStar;

  /// Outline of the Insert menu's tiles.
  final Color cardLine;

  /// Icons on a plum tile.
  final Color plumDeep;

  /// Icons on a sticky-yellow tile.
  final Color stickyDeep;

  /// Behind a website card's page preview.
  final Color previewBg;

  /// Floating pill shadow: `0 6px 18px -12px shadow`.
  List<BoxShadow> get pillShadow => [
        BoxShadow(color: shadow, offset: const Offset(0, 6), blurRadius: 18, spreadRadius: -12),
      ];

  /// Rails and trays: `0 10px 28px -14px shadow`.
  List<BoxShadow> get railShadow => [
        BoxShadow(color: shadow, offset: const Offset(0, 10), blurRadius: 28, spreadRadius: -14),
      ];

  /// Menus and flyouts: `0 20px 40px -20px shadow`.
  List<BoxShadow> get menuShadow => [
        BoxShadow(color: shadow, offset: const Offset(0, 20), blurRadius: 40, spreadRadius: -20),
      ];

  /// Map card and zoom pill: `0 10px 24px -18px shadow`.
  List<BoxShadow> get cardShadow => [
        BoxShadow(color: shadow, offset: const Offset(0, 10), blurRadius: 24, spreadRadius: -18),
      ];

  /// Full dialogs (Templates, Password protect): `0 30px 60px -24px shadow`.
  List<BoxShadow> get modalShadow => [
        BoxShadow(color: shadow, offset: const Offset(0, 30), blurRadius: 60, spreadRadius: -24),
      ];

  /// Notebook covers in the library: `0 1px 0 shadow/8%, 0 6px 16px -10px shadow/55%`.
  List<BoxShadow> get coverShadow => [
        BoxShadow(color: shadow.withValues(alpha: shadow.a * 0.09), offset: const Offset(0, 1)),
        BoxShadow(color: shadow.withValues(alpha: shadow.a * 0.55), offset: const Offset(0, 6), blurRadius: 16, spreadRadius: -10),
      ];

  /// Popovers and dialogs: `0 24px 48px -20px shadow`.
  List<BoxShadow> get dialogShadow => [
        BoxShadow(color: shadow, offset: const Offset(0, 24), blurRadius: 48, spreadRadius: -20),
      ];

  @override
  EndlessColors copyWith() => this;

  @override
  EndlessColors lerp(EndlessColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return EndlessColors(
      text: l(text, other.text),
      textMuted: l(textMuted, other.textMuted),
      textFaint: l(textFaint, other.textFaint),
      surface: l(surface, other.surface),
      surfaceSunk: l(surfaceSunk, other.surfaceSunk),
      bg: l(bg, other.bg),
      side: l(side, other.side),
      line: l(line, other.line),
      lineStrong: l(lineStrong, other.lineStrong),
      lineSoft: l(lineSoft, other.lineSoft),
      dot: l(dot, other.dot),
      inverse: l(inverse, other.inverse),
      inverseRaised: l(inverseRaised, other.inverseRaised),
      onInverse: l(onInverse, other.onInverse),
      accent: l(accent, other.accent),
      accentHover: l(accentHover, other.accentHover),
      accentDeep: l(accentDeep, other.accentDeep),
      accentTint: l(accentTint, other.accentTint),
      onAccent: l(onAccent, other.onAccent),
      clay: l(clay, other.clay),
      clayTint: l(clayTint, other.clayTint),
      green: l(green, other.green),
      greenTint: l(greenTint, other.greenTint),
      plum: l(plum, other.plum),
      plumTint: l(plumTint, other.plumTint),
      gold: l(gold, other.gold),
      star: l(star, other.star),
      stickyYellow: l(stickyYellow, other.stickyYellow),
      danger: l(danger, other.danger),
      spellUnderline: l(spellUnderline, other.spellUnderline),
      shadow: l(shadow, other.shadow),
      menuTile: l(menuTile, other.menuTile),
      clayDeep: l(clayDeep, other.clayDeep),
      greenDeep: l(greenDeep, other.greenDeep),
      sideSelected: l(sideSelected, other.sideSelected),
      lineDashed: l(lineDashed, other.lineDashed),
      accentWash: l(accentWash, other.accentWash),
      switchOff: l(switchOff, other.switchOff),
      warningTint: l(warningTint, other.warningTint),
      onWarning: l(onWarning, other.onWarning),
      goldDeep: l(goldDeep, other.goldDeep),
      moss: l(moss, other.moss),
      paperLine: l(paperLine, other.paperLine),
      paperGrid: l(paperGrid, other.paperGrid),
      paperMargin: l(paperMargin, other.paperMargin),
      scrim: l(scrim, other.scrim),
      frost: l(frost, other.frost),
      laserRed: l(laserRed, other.laserRed),
      laserGreen: l(laserGreen, other.laserGreen),
      laserBlue: l(laserBlue, other.laserBlue),
      scribbleMark: l(scribbleMark, other.scribbleMark),
      onStar: l(onStar, other.onStar),
      cardLine: l(cardLine, other.cardLine),
      plumDeep: l(plumDeep, other.plumDeep),
      stickyDeep: l(stickyDeep, other.stickyDeep),
      previewBg: l(previewBg, other.previewBg),
    );
  }
}

/// The small palette shown on a Themes screen card.
@immutable
class ThemeSwatch {
  const ThemeSwatch({
    required this.bg,
    required this.side,
    required this.surface,
    required this.line,
    required this.text,
    required this.dot,
    required this.accent,
  });

  final Color bg;
  final Color side;
  final Color surface;
  final Color line;
  final Color text;
  final Color dot;
  final Color accent;
}

/// How stored ink shows on screen. Dark mode brightens ink so it stays
/// readable; the stored color (and exports) keep the original.
Color displayInk(Color stored, Brightness brightness) {
  if (brightness == Brightness.light) return stored;
  final mapped = tokens.inkDisplayDark[stored.toARGB32() | 0xFF000000];
  if (mapped != null) return mapped.withValues(alpha: stored.a);
  final hsl = HSLColor.fromColor(stored);
  final lightness = hsl.lightness < 0.72 ? 0.72 : hsl.lightness;
  return hsl.withLightness(lightness).toColor();
}

extension EndlessThemeContext on BuildContext {
  EndlessColors get colors => Theme.of(this).extension<EndlessColors>()!;
}
