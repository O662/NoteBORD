import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../../theme/tokens.g.dart' as tokens show paperLight;
import '../icons.dart';

// The parts of a Settings section (Settings.dc.html): a group title, a card
// of rows, and the controls at a row's end.

/// "WRITING" over a card of rows.
class SettingsGroupView extends StatelessWidget {
  const SettingsGroupView({super.key, required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      label: title,
      explicitChildNodes: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        Semantics(
          header: true,
          child: Text(title.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.96, color: c.textMuted)),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, r) in rows.indexed) ...[
              if (i > 0) Container(height: 1, color: c.lineSoft),
              r,
            ],
          ]),
        ),
      ]),
    );
  }
}

/// A row: its label and description, and [trailing] at the end.
class SettingsRowView extends StatelessWidget {
  const SettingsRowView({super.key, required this.label, this.desc = '', this.trailing, this.danger = false});

  final String label;
  final String desc;
  final Widget? trailing;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 62),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: Row(spacing: 16, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, spacing: 2, children: [
              Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: danger ? c.danger : c.text)),
              if (desc.isNotEmpty) Text(desc, style: TextStyle(fontSize: 13, color: c.textMuted)),
            ]),
          ),
          ?trailing,
        ]),
      ),
    );
  }
}

/// The 50 × 30 switch in a 56 × 44 target.
class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({super.key, required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      toggled: value,
      label: label,
      button: true,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.button),
        onTap: () => onChanged(!value),
        child: SizedBox(
          width: 56,
          height: 44,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 50,
              height: 30,
              padding: const EdgeInsets.all(3),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(color: value ? c.accent : c.switchOff, borderRadius: BorderRadius.circular(15)),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  // Light in both modes, as in the design.
                  color: tokens.paperLight.surface,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: c.shadow, blurRadius: 2, offset: const Offset(0, 1))],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The segmented choice: options on a sunk track, the chosen one raised.
class SettingsChoice extends StatelessWidget {
  const SettingsChoice({super.key, required this.label, required this.options, required this.selected, required this.onChanged, this.icons});

  final String label;
  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;

  /// Optional icons before each option (Themes' Mode).
  final List<EIconData>? icons;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      label: label,
      explicitChildNodes: true,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: c.side, borderRadius: BorderRadius.circular(11)),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 2, children: [
          for (final (i, o) in options.indexed)
            Semantics(
              inMutuallyExclusiveGroup: true,
              checked: i == selected,
              button: true,
              label: o,
              excludeSemantics: true,
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(Radii.small),
                child: InkWell(
                  borderRadius: BorderRadius.circular(Radii.small),
                  onTap: () => onChanged(i),
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: i == selected
                        ? BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(Radii.small),
                            boxShadow: [BoxShadow(color: c.shadow.withValues(alpha: 0.2), blurRadius: 2, offset: const Offset(0, 1))],
                          )
                        : null,
                    child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
                      if (icons != null) EIcon(icons![i], size: 18, color: c.text),
                      Text(o, style: TextStyle(fontSize: 13, fontWeight: i == selected ? FontWeight.w700 : FontWeight.w500, color: c.text)),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// "English (US) ›": a value that opens what changes it (or just shows it).
class SettingsValue extends StatelessWidget {
  const SettingsValue({super.key, required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: onTap != null,
      label: value.isEmpty ? label : '$label: $value',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.key),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 4),
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
              if (value.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: c.inverseRaised)),
                ),
              if (onTap != null) EIcon(EIcons.chevronRight, size: 16, color: c.textFaint),
            ]),
          ),
        ),
      ),
    );
  }
}

enum SettingsButtonKind { plain, primary, danger }

/// "Manage", "Connect", "Sign out": an outlined (or blue) button.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key, required this.label, required this.onPressed, this.kind = SettingsButtonKind.plain});

  final String label;
  final VoidCallback? onPressed;
  final SettingsButtonKind kind;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg, border) = switch (kind) {
      SettingsButtonKind.primary => (c.accent, c.onAccent, c.accent),
      SettingsButtonKind.danger => (Colors.transparent, c.danger, c.clayLine),
      SettingsButtonKind.plain => (Colors.transparent, c.text, c.lineStrong),
    };
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(side: BorderSide(color: border), borderRadius: BorderRadius.circular(Radii.key)),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.key),
          onTap: onPressed,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: fg)),
            ]),
          ),
        ),
      ),
    );
  }
}
