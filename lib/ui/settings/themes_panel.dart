import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../board/model.dart' show Paper, paperFromName;
import '../../state/settings.dart';
import '../../theme/colors.dart';
import '../../theme/palettes.dart';
import '../../theme/tokens.g.dart' as tokens;
import '../../theme/tokens.g.dart' show FontFamilies, Radii, Sizes;
import '../common.dart' show DashedBorder, showComingSoon;
import '../icons.dart';
import 'settings_rows.dart';

/// Settings › Themes & dark mode (Themes.png): the mode, the 7 themes, the
/// accent, the default paper and "Keep pages light in dark mode", with a
/// live preview of a page and the library in what's picked.
class ThemesPanel extends ConsumerWidget {
  const ThemesPanel({super.key});

  static const _modes = [ThemeMode.light, ThemeMode.dark, ThemeMode.system];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final s = ref.watch(settingsProvider);
    final settings = ref.read(settingsProvider.notifier);
    final platform = MediaQuery.platformBrightnessOf(context);
    final dark = switch (s.themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => platform == Brightness.dark,
    };
    final b = dark ? Brightness.dark : Brightness.light;

    Widget label(String text) => Semantics(
          header: true,
          child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.96, color: c.textMuted)),
        );

    final controls = Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 18, children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
        Semantics(
          header: true,
          child: Text('Themes & dark mode', style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 36, height: 1.2, letterSpacing: -0.72, color: c.text)),
        ),
        Text('Changes apply everywhere: library, pages, widgets and menus.', style: TextStyle(fontSize: 14, color: c.textMuted)),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
        label('MODE'),
        _ModeChoice(
          selected: _modes.indexOf(s.themeMode),
          onChanged: (i) => settings.apply((st) => st.copyWith(themeMode: _modes[i])),
        ),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
        label('THEME'),
        Semantics(
          container: true,
          label: 'Theme',
          explicitChildNodes: true,
          child: LayoutBuilder(builder: (context, box) {
            final w = (box.maxWidth - 3 * 8) / 4;
            return Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in themeNames.entries)
                SizedBox(
                  width: w,
                  child: _ThemeTile(
                    name: e.value,
                    swatch: swatchOf(e.key, b),
                    on: s.theme == e.key,
                    onTap: () => settings.apply((st) => st.withPref('theme', e.key)),
                  ),
                ),
              SizedBox(width: w, child: _MakeOwnTile(onTap: () => showComingSoon(context, 'Making your own theme'))),
            ]);
          }),
        ),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
        label('ACCENT COLOR'),
        Semantics(
          container: true,
          label: 'Accent color',
          explicitChildNodes: true,
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            _AccentDot(
              label: 'Theme default',
              on: s.accent == themeAccent,
              light: swatchOf(s.theme, Brightness.light).accent,
              dark: swatchOf(s.theme, Brightness.dark).accent,
              onTap: () => settings.apply((st) => st.withPref('accent', themeAccent)),
            ),
            for (final e in accentNames.entries)
              _AccentDot(
                label: e.value,
                on: s.accent == e.key,
                light: accentOf(s.theme, e.key, b),
                onTap: () => settings.apply((st) => st.withPref('accent', e.key)),
              ),
          ]),
        ),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
        label('DEFAULT PAPER'),
        Semantics(
          container: true,
          label: 'Paper',
          explicitChildNodes: true,
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (p, name) in const [(Paper.dots, 'Dots'), (Paper.lines, 'Lines'), (Paper.grid, 'Grid'), (Paper.blank, 'Blank')])
              _PaperChip(label: name, on: s.defaultPaper == p, onTap: () => settings.apply((st) => st.withPref('defaultPaper', p.name))),
          ]),
        ),
      ]),
      Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(Radii.card)),
        child: Row(spacing: 16, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, spacing: 2, children: [
              Text('Keep pages light in dark mode', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
              Text('Menus go dark, the paper stays like real paper', style: TextStyle(fontSize: 12, color: c.textMuted)),
            ]),
          ),
          SettingsSwitch(
            label: 'Keep pages light in dark mode',
            value: s.keepPagesLight,
            onChanged: (v) => settings.apply((st) => st.withPref('keepPagesLight', v)),
          ),
        ]),
      ),
    ]);

    final note = switch (s.themeMode) {
      ThemeMode.system => 'Following your tablet: light by day, dark after sunset',
      _ => dark ? 'Dark mode' : 'Light mode',
    };
    final preview = Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: label('PREVIEW')),
        Text(note, style: TextStyle(fontSize: 12, color: c.textMuted)),
      ]),
      Expanded(
        child: _Preview(
          palette: paletteFor(s.theme, s.accent, b),
          light: paletteFor(s.theme, s.accent, Brightness.light),
          dark: dark,
          keepLight: s.keepPagesLight,
          paper: paperFromName(s.pref<String>('defaultPaper')),
        ),
      ),
      Text(
        'In dark mode, black ink shows as off-white and colors are brightened so they stay readable. Exports and PDFs keep your original colors.',
        style: TextStyle(fontSize: 12, height: 1.45, color: c.textMuted),
      ),
    ]);

    return LayoutBuilder(builder: (context, box) {
      // Side by side on the tablet; stacked when there's no room.
      if (box.maxWidth >= 860) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(40, 28, 40, 28),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 32, children: [
            SizedBox(width: 520, child: SingleChildScrollView(child: controls)),
            Expanded(child: preview),
          ]),
        );
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 24, children: [
          controls,
          SizedBox(height: 520, child: preview),
        ]),
      );
    });
  }
}

class _ModeChoice extends StatelessWidget {
  const _ModeChoice({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const labels = ['Light', 'Dark', 'Match tablet'];
    final icons = [EIcons.sun, EIcons.moon, EIcons.device];
    return Semantics(
      container: true,
      label: 'Mode',
      explicitChildNodes: true,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: c.side, borderRadius: BorderRadius.circular(Radii.button)),
        child: Row(spacing: 2, children: [
          for (final (i, l) in labels.indexed)
            Expanded(
              child: Semantics(
                inMutuallyExclusiveGroup: true,
                checked: i == selected,
                button: true,
                label: l,
                excludeSemantics: true,
                child: Material(
                  color: i == selected ? c.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(9),
                    onTap: () => onChanged(i),
                    child: SizedBox(
                      height: 44,
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 8, children: [
                        EIcon(icons[i], size: 18, color: c.text),
                        Text(l, style: TextStyle(fontSize: 14, fontWeight: i == selected ? FontWeight.w700 : FontWeight.w500, color: c.text)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// A theme: a little window in its colors, and its name.
class _ThemeTile extends StatelessWidget {
  const _ThemeTile({required this.name, required this.swatch, required this.on, required this.onTap});

  final String name;
  final ThemeSwatch swatch;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: on,
      button: true,
      label: '$name theme',
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: on ? c.accent : c.line, width: on ? 2 : 1),
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.card),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
              Container(
                height: 58,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: swatch.bg, borderRadius: BorderRadius.circular(9)),
                child: Stack(children: [
                  Positioned(left: 0, top: 0, bottom: 0, width: 22, child: ColoredBox(color: swatch.side)),
                  Positioned(left: 30, top: 10, width: 56, height: 14, child: _Box(swatch.surface, 4)),
                  Positioned(left: 30, top: 32, width: 36, height: 6, child: _Box(swatch.text, 3)),
                  Positioned(right: 8, bottom: 8, width: 14, height: 14, child: _Box(swatch.accent, 7)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box(this.color, this.radius);

  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius)));
}

class _MakeOwnTile extends StatelessWidget {
  const _MakeOwnTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'Make my own theme',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.card),
        onTap: onTap,
        child: DashedBorder(
          color: c.lineDashed,
          radius: Radii.card,
          child: SizedBox(
            height: 96,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, spacing: 4, children: [
              EIcon(EIcons.plus, color: c.text),
              Text('Make my own', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// An accent: a dot in its color ("Theme default": half light, half dark, with an A).
class _AccentDot extends StatelessWidget {
  const _AccentDot({required this.label, required this.on, required this.light, this.dark, required this.onTap});

  final String label;
  final bool on;
  final Color light;
  final Color? dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dot = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dark == null ? light : null,
        // Light on the right, dark on the left, as the design's conic gradient.
        gradient: dark == null
            ? null
            : SweepGradient(colors: [light, light, dark!, dark!], stops: const [0, 0.5, 0.5, 1], transform: const GradientRotation(-1.5707963)),
        border: on ? null : Border.all(color: c.text.withValues(alpha: 0.15)),
      ),
      alignment: Alignment.center,
      child: dark == null ? null : Text('A', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: tokens.paperLight.surface)),
    );
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: on,
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.button),
        onTap: onTap,
        child: SizedBox.square(
          dimension: 48,
          child: Center(
            child: on
                ? Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: c.bg, border: Border.all(color: c.text, width: 2)),
                    child: dot,
                  )
                : dot,
          ),
        ),
      ),
    );
  }
}

class _PaperChip extends StatelessWidget {
  const _PaperChip({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: on,
      button: true,
      label: '$label paper',
      excludeSemantics: true,
      child: Material(
        color: on ? c.inverse : c.surface,
        shape: StadiumBorder(side: BorderSide(color: on ? c.inverse : c.lineStrong)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: on ? c.onInverse : c.text)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A page and the library drawn in [palette] (Themes.dc.html's preview).
class _Preview extends StatelessWidget {
  const _Preview({required this.palette, required this.light, required this.dark, required this.keepLight, required this.paper});

  final EndlessColors palette;
  final EndlessColors light;
  final bool dark;
  final bool keepLight;
  final Paper paper;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final pageDark = dark && !keepLight;
    final page = pageDark ? p : light;
    final b = pageDark ? Brightness.dark : Brightness.light;
    final ink = displayInk(tokens.inkDefaults[0], b);
    final title = pageDark ? p.accent : light.accent;
    final marker = displayInk(tokens.extraInkDefaults[3], b).withValues(alpha: 0.45);
    TextStyle hand(double size, Color color, {FontWeight weight = FontWeight.w600}) =>
        TextStyle(fontFamily: FontFamilies.handwritingSample, fontSize: size, height: 1, fontWeight: weight, color: color);

    return Semantics(
      label: 'Preview of a page and the library',
      image: true,
      excludeSemantics: true,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: p.side,
          border: Border.all(color: p.line),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: p.shadow, offset: const Offset(0, 24), blurRadius: 40, spreadRadius: -26)],
        ),
        child: LayoutBuilder(builder: (context, box) {
          final libraryHeight = box.maxHeight < 520 ? box.maxHeight * 0.42 : 250.0;
          return Stack(children: [
            Positioned(
              left: 0,
              top: 0,
              right: 0,
              bottom: libraryHeight,
              child: CustomPaint(painter: _PaperPainter(page.bg, page.dot, paper)),
            ),
            Positioned(
              left: 12,
              top: 12,
              child: _Chip(p, child: Text('‹ Physics — Lecture notes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.text))),
            ),
            Positioned(
              right: 12,
              top: 12,
              child: _Chip(p, padding: 6, child: Row(spacing: 6, children: [
                Container(width: 22, height: 22, decoration: BoxDecoration(color: p.text, borderRadius: BorderRadius.circular(7))),
                Container(width: 14, height: 14, decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle)),
                Container(width: 14, height: 14, decoration: BoxDecoration(color: p.clay, shape: BoxShape.circle)),
              ])),
            ),
            Positioned(
              left: 12,
              top: 64,
              width: 30,
              height: 150,
              child: DecoratedBox(
                decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.line), borderRadius: BorderRadius.circular(Radii.button)),
              ),
            ),
            Positioned(
              left: 12,
              top: 66,
              width: 30,
              height: 26,
              child: DecoratedBox(
                decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(Radii.key)),
                child: Center(child: Text('+', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.onAccent))),
              ),
            ),
            Positioned(left: 62, top: 66, child: Text('Lecture 3 — Momentum', style: hand(34, title))),
            Positioned(left: 70, top: 112, child: Text('p = m · v', style: hand(30, ink))),
            Positioned(
              left: 62,
              top: 158,
              width: 250,
              height: 26,
              child: DecoratedBox(decoration: BoxDecoration(color: marker, borderRadius: BorderRadius.circular(4))),
            ),
            Positioned(left: 66, top: 154, child: Text('total momentum is conserved', style: hand(26, ink, weight: FontWeight.w400))),
            Positioned(
              right: 24,
              top: 150,
              child: Transform.rotate(
                angle: 0.05,
                child: Container(
                  width: 96,
                  height: 80,
                  padding: const EdgeInsets.all(8),
                  color: tokens.stickyColors[0],
                  child: Text('ask in office hours', style: hand(18, tokens.inkDefaults[0], weight: FontWeight.w400).copyWith(height: 1.05)),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: libraryHeight,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: p.side, border: Border(top: BorderSide(color: p.line))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
                  Text('Library', style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 22, color: p.text)),
                  Expanded(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
                      for (final (name, spine) in [('Physics', p.accent), ('Calculus II', p.clay), ('Lab journal', p.green)])
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
                            Flexible(
                              child: Container(
                                constraints: const BoxConstraints(maxHeight: 96),
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.line), borderRadius: BorderRadius.circular(Radii.key)),
                                child: Row(children: [Container(width: 7, color: spine), const Spacer()]),
                              ),
                            ),
                            Text(name, maxLines: 1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.text)),
                          ]),
                        ),
                    ]),
                  ),
                  Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(Radii.key)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('+ New note', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.onAccent)),
                    ]),
                  ),
                ]),
              ),
            ),
          ]);
        }),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.p, {required this.child, this.padding = 12});

  final EndlessColors p;
  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) => Container(
        height: 34,
        padding: EdgeInsets.symmetric(horizontal: padding),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.line), borderRadius: BorderRadius.circular(Radii.button)),
        child: child,
      );
}

class _PaperPainter extends CustomPainter {
  _PaperPainter(this.bg, this.dot, this.paper);

  final Color bg;
  final Color dot;
  final Paper paper;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    final line = Paint()
      ..color = dot
      ..strokeWidth = 1;
    switch (paper) {
      case Paper.dots:
        const step = 20.0;
        canvas.drawPoints(
          PointMode.points,
          [
            for (var y = step / 2; y < size.height; y += step)
              for (var x = step / 2; x < size.width; x += step) Offset(x, y),
          ],
          Paint()
            ..color = dot
            ..strokeWidth = Sizes.paperDotRadius * 2
            ..strokeCap = StrokeCap.round,
        );
      case Paper.lines:
        for (var y = 26.0; y < size.height; y += 26) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
      case Paper.grid:
        for (var y = 20.0; y < size.height; y += 20) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
        for (var x = 20.0; x < size.width; x += 20) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
        }
      case Paper.blank:
        break;
    }
  }

  @override
  bool shouldRepaint(_PaperPainter old) => old.bg != bg || old.dot != dot || old.paper != paper;
}
