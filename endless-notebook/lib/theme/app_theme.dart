import 'package:flutter/material.dart';

import 'colors.dart';
import 'tokens.g.dart';

/// Material theme for a palette. Only Paper exists in Phase 0; other
/// themes and accent choices plug in here with the Themes screen.
ThemeData buildTheme(EndlessColors c, Brightness brightness) {
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.onAccent,
    secondary: c.clay,
    onSecondary: c.onAccent,
    error: c.danger,
    onError: c.onAccent,
    surface: c.surface,
    onSurface: c.text,
    surfaceContainerHighest: c.side,
    outline: c.line,
    outlineVariant: c.lineSoft,
    inverseSurface: c.inverse,
    onInverseSurface: c.onInverse,
    shadow: c.shadow,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: FontFamilies.ui,
    scaffoldBackgroundColor: c.bg,
    extensions: [c],
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: c.text, displayColor: c.text),
    iconTheme: IconThemeData(color: c.text, size: 20),
    dividerColor: c.line,
    splashFactory: InkRipple.splashFactory,
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.inverse,
      contentTextStyle: TextStyle(fontFamily: FontFamilies.ui, fontSize: 14, color: c.onInverse),
      shape: const StadiumBorder(),
      elevation: 0,
      insetPadding: const EdgeInsets.only(bottom: 20),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accent : Colors.transparent),
      checkColor: WidgetStatePropertyAll(c.onAccent),
      side: BorderSide(color: c.lineStrong, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(color: c.line),
      ),
      textStyle: TextStyle(fontFamily: FontFamilies.ui, fontSize: 14, color: c.text),
    ),
  );
}

final lightTheme = buildTheme(paperLight, Brightness.light);
final darkTheme = buildTheme(paperDark, Brightness.dark);
