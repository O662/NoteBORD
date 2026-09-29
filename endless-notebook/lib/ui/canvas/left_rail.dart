import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/tokens.g.dart' show Radii, TypeScale;
import '../common.dart';
import '../icons.dart';

/// One row of a rail menu.
class RailItem {
  const RailItem(this.label, this.desc, this.icon, this.feature, {this.tile, this.tint, this.isTool = false});

  final String label;
  final String desc;
  final EIconData icon;

  /// Name used in the "coming soon" message until the feature exists.
  final String feature;
  final Color Function(EndlessColors c)? tile;
  final Color Function(EndlessColors c)? tint;

  /// Tool items switch the active tool (sticky, frame, image, ruler, laser).
  final bool isTool;
}

class RailGroup {
  const RailGroup(this.id, this.label, this.icon, this.items, {this.primary = false});

  final String id;
  final String label;
  final EIconData icon;
  final List<RailItem> items;

  /// The blue Insert button.
  final bool primary;
}

/// The four menus of the compact rail (Canvas.dc.html `G`).
final List<RailGroup> railGroups = [
  RailGroup('insert', 'Insert', EIcons.insert, primary: true, [
    RailItem('Sticky note', 'Tap the page to drop one', EIcons.sticky, 'Sticky notes',
        isTool: true, tile: (c) => c.stickyYellow, tint: (c) => c.gold),
    RailItem('Paper frame', 'A lined sheet to write on', EIcons.frame, 'Paper frames', isTool: true),
    RailItem('Image', 'From photos, camera or files', EIcons.image, 'Images', isTool: true),
    RailItem('Record audio', 'Place the clip anywhere', EIcons.mic, 'Audio recording',
        tile: (c) => c.clayTint, tint: (c) => c.danger),
    RailItem('Templates', 'Cornell, planner, lab report…', EIcons.templates, 'Templates'),
    RailItem('Everything else', 'PDF, video, tables, widgets…', EIcons.grid, 'The full Insert menu',
        tile: (c) => c.accentTint, tint: (c) => c.accentDeep),
  ]),
  RailGroup('study', 'Study & math', EIcons.cap, [
    RailItem('Need to remember', 'Star it or lasso it', EIcons.star, 'Need to remember',
        tile: (c) => c.stickyYellow, tint: (c) => c.gold),
    RailItem('Make flashcards', 'Circle the front, then the back', EIcons.flashcards, 'Flashcards',
        tile: (c) => c.clayTint, tint: (c) => c.clayDeep),
    RailItem('Math & graphs', 'Handwriting to math, xy and xyz', EIcons.sigma, 'Math',
        tile: (c) => c.accentTint, tint: (c) => c.accentDeep),
    RailItem('Math tools', 'Number line, unit circle, formulas', EIcons.mathTools, 'Math tools',
        tile: (c) => c.accentTint, tint: (c) => c.accentDeep),
  ]),
  RailGroup('write', 'Writing help', EIcons.spell, [
    RailItem('Spell check', 'Check this page', EIcons.spellPlain, 'Spell check',
        tile: (c) => c.clayTint, tint: (c) => c.danger),
    RailItem('Dictionary & thesaurus', 'Definitions and similar words', EIcons.book, 'The dictionary',
        tile: (c) => c.greenTint, tint: (c) => c.greenDeep),
    RailItem('Convert to text', 'Turn handwriting into type', EIcons.text, 'Convert to text'),
  ]),
  RailGroup('tools', 'Ruler, laser & view', EIcons.ruler, [
    RailItem('Ruler', 'Two fingers rotate · pen snaps', EIcons.ruler, 'The ruler', isTool: true),
    RailItem('Laser pointer', 'Fades away, never saved', EIcons.laser, 'The laser pointer',
        isTool: true, tile: (c) => c.clayTint, tint: (c) => c.danger),
    RailItem('Split view', 'Two notes side by side', EIcons.split, 'Split view'),
  ]),
];

/// The compact floating rail: Insert, Study & math, Writing help,
/// Ruler/laser/view, then Search. Each group opens a menu beside the rail.
/// Hovering (S Pen or mouse) previews it and leaving closes it; tapping pins
/// it until a tap outside, a second tap, or picking an item.
class LeftRail extends StatelessWidget {
  const LeftRail({
    super.key,
    required this.openId,
    required this.pinned,
    required this.onHover,
    required this.onTap,
    required this.onLeave,
    required this.onClose,
    required this.onItem,
    required this.onSearch,
  });

  static const _buttonPitch = 46.0; // 44 + 2 gap

  final String? openId;
  final bool pinned;
  final ValueChanged<String> onHover;
  final ValueChanged<String> onTap;
  final VoidCallback onLeave;
  final VoidCallback onClose;
  final ValueChanged<RailItem> onItem;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final index = railGroups.indexWhere((g) => g.id == openId);
    final open = index >= 0 ? railGroups[index] : null;

    final rail = Semantics(
      container: true,
      label: 'Page tools',
      explicitChildNodes: true,
      child: Container(
        width: 58,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(Radii.dialog),
          boxShadow: c.railShadow,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, spacing: 2, children: [
          for (final g in railGroups)
            MouseRegion(
              onEnter: (_) => onHover(g.id),
              child: _GroupButton(group: g, open: g.id == openId, pinned: pinned && g.id == openId, onTap: () => onTap(g.id)),
            ),
          const PillDivider(vertical: false),
          MouseRegion(
            onEnter: (_) => onLeave(),
            child: ChromeButton(label: 'Search', icon: EIcons.search, onPressed: onSearch),
          ),
        ]),
      ),
    );

    return MouseRegion(
      onExit: (_) => onLeave(),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        rail,
        if (open != null)
          Padding(
            // The gap is part of the hover area, so moving to the menu keeps it open.
            padding: EdgeInsets.only(left: 8, top: math.max(0, 6 + index * _buttonPitch - 8)),
            child: _Flyout(group: open, pinned: pinned, onClose: onClose, onItem: onItem),
          ),
      ]),
    );
  }
}

class _GroupButton extends StatelessWidget {
  const _GroupButton({required this.group, required this.open, required this.pinned, required this.onTap});

  final RailGroup group;
  final bool open;
  final bool pinned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final Color bg, fg;
    if (group.primary) {
      bg = pinned ? c.accentHover : c.accent;
      fg = c.onAccent;
    } else if (pinned) {
      bg = c.inverse;
      fg = c.onInverse;
    } else {
      bg = open ? c.side : Colors.transparent;
      fg = c.text;
    }
    final light = group.primary || pinned;
    return ChromeButton(
      label: group.label,
      expanded: open,
      background: bg,
      foreground: fg,
      onPressed: onTap,
      child: Stack(children: [
        Center(child: EIcon(group.icon, color: fg)),
        // Corner tick: this button opens a menu.
        Positioned(
          right: 4,
          bottom: 4,
          child: CustomPaint(
            size: const Size.square(5),
            painter: _TickPainter(light ? fg.withValues(alpha: 0.75) : c.textFaint),
          ),
        ),
      ]),
    );
  }
}

class _TickPainter extends CustomPainter {
  _TickPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(size.width, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.color != color;
}

class _Flyout extends StatelessWidget {
  const _Flyout({required this.group, required this.pinned, required this.onClose, required this.onItem});

  final RailGroup group;
  final bool pinned;
  final VoidCallback onClose;
  final ValueChanged<RailItem> onItem;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      label: '${group.label} menu',
      explicitChildNodes: true,
      child: Container(
        width: 272,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(Radii.pill),
          boxShadow: c.menuShadow,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 2, children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 4, 4),
              child: Row(spacing: 8, children: [
                Expanded(
                  child: Text(
                    group.label.toUpperCase(),
                    style: TypeScale.sectionLabel.copyWith(fontWeight: FontWeight.w700, color: c.textMuted),
                  ),
                ),
                if (pinned) ...[
                  Text('Pinned', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.accent)),
                  ChromeButton(
                    label: 'Close menu',
                    icon: EIcons.close,
                    iconSize: 16,
                    width: 36,
                    height: 36,
                    radius: Radii.key,
                    foreground: c.textMuted,
                    onPressed: onClose,
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text('Tap to keep open', style: TextStyle(fontSize: 12, color: c.textFaint)),
                  ),
              ]),
            ),
          ),
          for (final item in group.items) _Row(item: item, onTap: () => onItem(item)),
        ]),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item, required this.onTap});

  final RailItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: item.label,
      hint: item.desc,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.button),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(spacing: 12, children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: item.tile?.call(c) ?? c.menuTile,
                  borderRadius: BorderRadius.circular(Radii.key),
                ),
                child: Center(child: EIcon(item.icon, color: item.tint?.call(c) ?? c.text)),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                  Text(item.label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                  Text(item.desc, style: TextStyle(fontSize: 12, color: c.textMuted)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
