import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../canvas/ruler.dart';
import '../../state/settings.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart' show Radii, TypeScale;
import '../common.dart';
import '../icons.dart';
import 'pen_settings.dart';

/// The number pad's delete key.
const backspace = '⌫';

/// Angles offered as one tap.
const rulerPresets = [0, 15, 30, 45, 60, 75, 90, 120, 135, 150, 180];

/// Opened by tapping the ruler's angle chip: a number pad for an exact
/// angle (up to three decimals, counter-clockwise positive), preset angles,
/// and the ruler's unit.
Future<void> showRulerMenu(BuildContext context, Ruler ruler) => showDialog<void>(
  context: context,
  builder: (_) => RulerMenu(ruler: ruler),
);

class RulerMenu extends ConsumerStatefulWidget {
  const RulerMenu({super.key, required this.ruler});

  final Ruler ruler;

  @override
  ConsumerState<RulerMenu> createState() => _RulerMenuState();
}

class _RulerMenuState extends ConsumerState<RulerMenu> {
  /// What's been typed ("" shows the current angle).
  String _typed = '';

  double? get _value => double.tryParse(_typed.replaceAll(RegExp(r'\.$'), ''));

  void _key(String k) {
    var next = _typed;
    switch (k) {
      case backspace:
        if (next.isNotEmpty) next = next.substring(0, next.length - 1);
      case '±':
        next = next.startsWith('-') ? next.substring(1) : '-$next';
      case '.':
        if (!next.contains('.')) next = '$next.';
      default:
        final dot = next.indexOf('.');
        if (dot >= 0 && next.length - dot > 3) return; // three decimals at most
        next = '$next$k';
    }
    final v = double.tryParse(next.replaceAll(RegExp(r'\.$'), ''));
    if (v != null && v.abs() > 180) return;
    setState(() => _typed = next);
  }

  void _set(double deg) {
    widget.ruler.setDegrees(deg);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final unit = ref.watch(settingsProvider.select((s) => s.rulerUnit));
    final value = _value;
    final shown = _typed.isEmpty ? formatDegrees(widget.ruler.degrees) : '${_typed.replaceFirst('-', '−')}°';

    Widget key(String k, {String? label}) => Expanded(
      child: Semantics(
        button: true,
        label: label ?? k,
        excludeSemantics: true,
        child: Material(
          color: c.surfaceSunk,
          borderRadius: BorderRadius.circular(Radii.key),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.key),
            onTap: () => _key(k),
            child: SizedBox(
              height: 48,
              child: Center(
                child: k == backspace
                    ? EIcon(EIcons.backspace, size: 22, color: c.text)
                    : Text(
                        k,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: c.text),
                      ),
              ),
            ),
          ),
        ),
      ),
    );

    final pad = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Semantics(
          liveRegion: true,
          label: 'Angle $shown',
          excludeSemantics: true,
          child: Container(
            height: 56,
            margin: const EdgeInsets.only(bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.centerRight,
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: _typed.isEmpty ? c.lineStrong : c.accent, width: 1.5),
              borderRadius: BorderRadius.circular(Radii.button),
            ),
            child: Text(
              shown,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: _typed.isEmpty ? c.textMuted : c.text),
            ),
          ),
        ),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['±', '0', '.'],
        ])
          Row(
            spacing: 6,
            children: [
              for (final k in row)
                key(
                  k,
                  label: switch (k) {
                    '±' => 'Plus or minus',
                    '.' => 'Decimal point',
                    _ => null,
                  },
                ),
            ],
          ),
        Row(
          spacing: 6,
          children: [
            key(backspace, label: 'Delete digit'),
            Expanded(
              flex: 2,
              child: Semantics(
                button: true,
                enabled: value != null,
                label: 'Set angle',
                excludeSemantics: true,
                child: Material(
                  color: value == null ? c.side : c.inverse,
                  borderRadius: BorderRadius.circular(Radii.key),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Radii.key),
                    onTap: value == null ? null : () => _set(value),
                    child: SizedBox(
                      height: 48,
                      child: Center(
                        child: Text(
                          'Set angle',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: value == null ? c.textFaint : c.onInverse,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );

    final presets = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final p in rulerPresets)
          Semantics(
            button: true,
            label: 'Set $p°',
            excludeSemantics: true,
            child: Material(
              color: widget.ruler.degrees == p ? c.inverse : Colors.transparent,
              shape: StadiumBorder(side: BorderSide(color: widget.ruler.degrees == p ? c.inverse : c.lineStrong)),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => _set(p.toDouble()),
                child: Container(
                  height: 44,
                  constraints: const BoxConstraints(minWidth: 56),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      '$p°',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: widget.ruler.degrees == p ? c.onInverse : c.text,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    final units = Semantics(
      container: true,
      label: 'Ruler units',
      explicitChildNodes: true,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: c.side, borderRadius: BorderRadius.circular(Radii.button)),
        child: Row(
          spacing: 2,
          children: [
            for (final (u, label) in const [
              (RulerUnit.cm, 'Centimeters'),
              (RulerUnit.mm, 'Millimeters'),
              (RulerUnit.inch, 'Inches'),
            ])
              Expanded(
                child: SettingsSegment(
                  label: u.label,
                  semanticLabel: label,
                  selected: unit == u,
                  onTap: () => ref.read(settingsProvider.notifier).apply((s) => s.copyWith(rulerUnit: u)),
                ),
              ),
          ],
        ),
      ),
    );

    Widget section(String text) => Text(text.toUpperCase(), style: TypeScale.sectionLabel.copyWith(color: c.textMuted));

    return Dialog(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.dialog),
        side: BorderSide(color: c.line),
      ),
      child: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Ruler', style: TypeScale.panelTitle.copyWith(color: c.text)),
                  ),
                  ChromeButton(
                    label: 'Close',
                    icon: EIcons.close,
                    foreground: c.textMuted,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 24,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 10,
                      children: [section('Angle'), pad],
                    ),
                  ),
                  SizedBox(
                    width: 260,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 10,
                      children: [
                        section('Presets'),
                        presets,
                        const SizedBox(height: 4),
                        section('Units'),
                        units,
                        Text(
                          'Counter-clockwise is positive. Pinch along the ruler to make it longer or shorter. '
                          'It measures the page: at 100% it matches a real ruler.',
                          style: TextStyle(fontSize: 13, height: 1.4, color: c.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
