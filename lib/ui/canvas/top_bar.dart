import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../canvas/pane.dart';
import '../../canvas/pens.dart';
import '../../state/notebook.dart';
import '../../state/settings.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart' as tokens;
import '../../theme/tokens.g.dart' show Radii, TypeScale;
import '../common.dart';
import '../icons.dart';
import 'pen_settings.dart';

/// Title · tools · Share/⋯, floating over the page (Canvas.dc.html header).
class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.title,
    required this.pane,
    this.showTools = true,
    this.showActions = true,
    this.showTrayButton = true,
    required this.popoverOpen,
    required this.penLink,
    required this.markerLink,
    required this.onPickTool,
    required this.onTogglePopover,
    required this.onToggleTray,
    required this.moreOpen,
    required this.onToggleMore,
    required this.onComingSoon,
  });

  /// The left pill: [TitlePill] on the canvas, the split title in Split view.
  final Widget title;

  /// The pane the tools write to (undo and redo act on its page).
  final Pane pane;
  final bool showTools;
  final bool showActions;

  /// The "More colors" button (Split view has none).
  final bool showTrayButton;
  final bool popoverOpen;
  final LayerLink penLink;
  final LayerLink markerLink;
  final ValueChanged<CanvasTool> onPickTool;
  final VoidCallback onTogglePopover;
  final VoidCallback onToggleTray;
  final bool moreOpen;
  final VoidCallback onToggleMore;
  final ValueChanged<String> onComingSoon;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tools = ToolPill(
          pane: pane,
          showTrayButton: showTrayButton,
          popoverOpen: popoverOpen,
          penLink: penLink,
          markerLink: markerLink,
          onPickTool: onPickTool,
          onTogglePopover: onTogglePopover,
          onToggleTray: onToggleTray,
          onComingSoon: onComingSoon,
        );
        // The tool pill is centered on screen; the title takes what's left on
        // the left. As in the design, the right pill may use part of the gap.
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (showTools) tools,
              Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.max(160, (constraints.maxWidth - ToolPill.width) / 2 - 24),
                  ),
                  child: title,
                ),
              ),
              if (showActions)
                Align(
                  alignment: Alignment.centerRight,
                  child: ActionsPill(moreOpen: moreOpen, onToggleMore: onToggleMore, onComingSoon: onComingSoon),
                ),
            ],
          ),
        );
      },
    );
  }
}

class TitlePill extends ConsumerWidget {
  const TitlePill({super.key, required this.pane, required this.onBack, required this.onRename});

  final Pane pane;
  final VoidCallback onBack;

  /// Tapping the title renames the notebook.
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListenableBuilder(
        listenable: pane,
        // A Consumer, so what _build watches is tracked for this build.
        builder: (context, _) => Consumer(builder: (context, ref, _) => _build(context, ref)),
      );

  Widget _build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final nb = ref.watch(notebookProvider(pane.notebookId));
    final page = pane.page.clamp(0, nb.pages.length - 1);
    final status = switch (nb.saveStatus) {
      SaveStatus.saved => 'Saved',
      SaveStatus.saving => 'Saving…',
      SaveStatus.failed => 'Couldn’t save · retrying',
    };
    return Pill(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChromeButton(label: 'Back to library', icon: EIcons.back, iconSize: 22, onPressed: onBack),
          const SizedBox(width: 4),
          Flexible(
            // Two lines of text must fit the 72 dp top bar, so very large
            // system font sizes are capped here.
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    button: true,
                    hint: 'Rename',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onRename,
                      child: Text(
                        nb.notebook.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TypeScale.pillTitle.copyWith(color: c.text),
                      ),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      'Page ${page + 1} of ${nb.pages.length} · $status',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TypeScale.pillSub.copyWith(
                        color: nb.saveStatus == SaveStatus.failed ? c.danger : c.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ToolPill extends ConsumerWidget {
  /// Approximate laid-out width, used to share the rest of the top bar.
  static const width = 660.0;

  const ToolPill({
    super.key,
    required this.pane,
    this.showTrayButton = true,
    required this.popoverOpen,
    required this.penLink,
    required this.markerLink,
    required this.onPickTool,
    required this.onTogglePopover,
    required this.onToggleTray,
    required this.onComingSoon,
  });

  final Pane pane;
  final bool showTrayButton;
  final bool popoverOpen;
  final LayerLink penLink;
  final LayerLink markerLink;
  final ValueChanged<CanvasTool> onPickTool;
  final VoidCallback onTogglePopover;
  final VoidCallback onToggleTray;
  final ValueChanged<String> onComingSoon;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListenableBuilder(
        listenable: pane,
        // A Consumer, so what _build watches is tracked for this build.
        builder: (context, _) => Consumer(builder: (context, ref, _) => _build(context, ref)),
      );

  Widget _build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final s = ref.watch(settingsProvider);
    final nb = ref.watch(notebookProvider(pane.notebookId));
    final notebook = ref.read(notebookProvider(pane.notebookId).notifier);
    final pageId = nb.pageAt(pane.page).id;
    final brightness = Theme.of(context).brightness;
    final extras = tokens.extraInkDefaults;

    Widget quick(Color color) => ChromeButton(
      label: 'Quick color: ${colorName(color)}',
      width: 36,
      selected: false,
      onPressed: () => ref.read(settingsProvider.notifier).pickColor(color),
      child: ColorDot(color: displayInk(color, brightness), selected: s.tool.inks && s.color == color),
    );

    return Semantics(
      container: true,
      label: 'Writing tools',
      child: Pill(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 2,
          children: [
            ChromeButton(
              label: 'Undo',
              icon: EIcons.undo,
              enabled: notebook.canUndo(pageId),
              onPressed: () => notebook.undo(pageId),
            ),
            ChromeButton(
              label: 'Redo',
              icon: EIcons.redo,
              enabled: notebook.canRedo(pageId),
              onPressed: () => notebook.redo(pageId),
            ),
            const PillDivider(),
            ChromeButton(
              label: 'Select',
              icon: EIcons.select,
              selected: s.tool == CanvasTool.select,
              onPressed: () => onPickTool(CanvasTool.select),
            ),
            ChromeButton(
              label: 'Lasso select',
              icon: EIcons.lasso,
              selected: s.tool == CanvasTool.lasso,
              onPressed: () => onPickTool(CanvasTool.lasso),
            ),
            const PillDivider(),
            CompositedTransformTarget(
              link: penLink,
              child: ChromeButton(
                label: 'Pen',
                icon: EIcons.pen,
                selected: s.tool == CanvasTool.pen,
                expanded: s.tool == CanvasTool.pen ? popoverOpen : null,
                onPressed: () => onPickTool(CanvasTool.pen),
              ),
            ),
            CompositedTransformTarget(
              link: markerLink,
              child: ChromeButton(
                label: 'Marker',
                icon: EIcons.marker,
                selected: s.tool == CanvasTool.marker,
                expanded: s.tool == CanvasTool.marker ? popoverOpen : null,
                onPressed: () => onPickTool(CanvasTool.marker),
              ),
            ),
            ChromeButton(
              label: 'Eraser',
              icon: EIcons.eraser,
              selected: s.tool == CanvasTool.eraser,
              onPressed: () => onPickTool(CanvasTool.eraser),
            ),
            ChromeButton(label: 'Shapes', icon: EIcons.shapes, onPressed: () => onComingSoon('Shapes')),
            ChromeButton(label: 'Text', icon: EIcons.text, onPressed: () => onComingSoon('Text boxes')),
            const PillDivider(),
            for (final color in tokens.inkDefaults) quick(color),
            if (showTrayButton)
              ChromeButton(
                label: 'More colors',
                width: 40,
                expanded: s.trayOpen,
                background: s.trayOpen ? c.side : null,
                onPressed: onToggleTray,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ColorDot(
                      color: extras[0],
                      size: 20,
                      gradient: SweepGradient(
                        transform: const GradientRotation(-math.pi / 2),
                        colors: [
                          for (final i in [0, 1, 3, 2]) ...[
                            displayInk(extras[i], brightness),
                            displayInk(extras[i], brightness),
                          ],
                        ],
                        stops: const [0, .25, .25, .5, .5, .75, .75, 1],
                      ),
                    ),
                    const SizedBox(height: 1),
                    Transform.rotate(
                      angle: s.trayOpen ? math.pi : 0,
                      child: EIcon(EIcons.trayChevron, size: 12, color: c.textMuted),
                    ),
                  ],
                ),
              ),
            ChromeButton(
              label: 'Color and thickness',
              background: c.side,
              expanded: popoverOpen,
              onPressed: onTogglePopover,
              child: Container(
                width: math.max(6, penSizes[s.sizeIndex].dotPx),
                height: math.max(6, penSizes[s.sizeIndex].dotPx),
                decoration: BoxDecoration(shape: BoxShape.circle, color: displayInk(s.color, brightness)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Share (dark) and ⋯. Export lives in the ⋯ menu and, later, the Share dialog.
class ActionsPill extends StatelessWidget {
  const ActionsPill({super.key, required this.moreOpen, required this.onToggleMore, required this.onComingSoon});

  final bool moreOpen;
  final VoidCallback onToggleMore;
  final ValueChanged<String> onComingSoon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pill(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          ChromeButton(
            label: 'Share',
            width: null,
            padding: 15,
            background: c.inverse,
            foreground: c.onInverse,
            onPressed: () => onComingSoon('Sharing'),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                EIcon(EIcons.share, size: 18, color: c.onInverse),
                Text(
                  'Share',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.onInverse),
                ),
              ],
            ),
          ),
          ChromeButton(
            label: 'More options',
            icon: EIcons.more,
            expanded: moreOpen,
            background: moreOpen ? c.side : null,
            onPressed: onToggleMore,
          ),
        ],
      ),
    );
  }
}

/// A row in the ⋯ menu (Canvas.dc.html `moreItems`).
class MoreItem {
  const MoreItem(this.label, this.icon, {this.desc, this.strong = false, this.separatorBefore = false});

  final String label;
  final EIconData icon;
  final String? desc;
  final bool strong;
  final bool separatorBefore;
}

final List<MoreItem> moreItems = [
  MoreItem('Export', EIcons.exportRow, desc: 'PDF, board file or image', strong: true),
  MoreItem('Import', EIcons.import, desc: 'PDF, images or a board file'),
  MoreItem('Print', EIcons.print),
  MoreItem('Password protect', EIcons.lockRow, desc: 'This page or the whole notebook', separatorBefore: true),
  MoreItem('Page & paper', EIcons.pagePaper, desc: 'Dots, lines, grid or blank'),
  MoreItem('Version history', EIcons.history, desc: 'See and restore earlier versions'),
  MoreItem('Settings', EIcons.settings, separatorBefore: true),
];

/// The ⋯ menu panel.
class MoreMenu extends StatelessWidget {
  const MoreMenu({super.key, required this.onItem});

  final ValueChanged<MoreItem> onItem;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      label: 'More options menu',
      explicitChildNodes: true,
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(Radii.pill),
          boxShadow: c.menuShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 2,
          children: [
            for (final item in moreItems) ...[
              if (item.separatorBefore)
                Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), color: c.lineSoft),
              Semantics(
                button: true,
                label: item.label,
                hint: item.desc,
                excludeSemantics: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(Radii.button),
                  onTap: () => onItem(item),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      child: Row(
                        spacing: 12,
                        children: [
                          EIcon(item.icon, color: c.text),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              spacing: 1,
                              children: [
                                Text(
                                  item.label,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: item.strong ? FontWeight.w600 : FontWeight.w500,
                                    color: c.text,
                                  ),
                                ),
                                if (item.desc != null)
                                  Text(item.desc!, style: TextStyle(fontSize: 12, color: c.textMuted)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Stand-in for the Settings screen: mode, name, finger drawing and the
/// pen gesture settings.
Future<void> showQuickSettings(BuildContext context) =>
    showDialog<void>(context: context, builder: (context) => const _QuickSettings());

class _QuickSettings extends ConsumerWidget {
  const _QuickSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final s = ref.watch(settingsProvider);
    final settings = ref.read(settingsProvider.notifier);
    return Dialog(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.dialog),
        side: BorderSide(color: c.line),
      ),
      child: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Settings', style: TypeScale.panelTitle.copyWith(color: c.text)),
                  ),
                  ChromeButton(
                    label: 'Close',
                    icon: EIcons.close,
                    foreground: c.textMuted,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Text('MODE', style: TypeScale.sectionLabel.copyWith(color: c.textMuted)),
              SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                  ButtonSegment(value: ThemeMode.system, label: Text('Match tablet')),
                ],
                selected: {s.themeMode},
                onSelectionChanged: (m) => settings.apply((st) => st.copyWith(themeMode: m.first)),
              ),
              TextFormField(
                initialValue: s.userName ?? '',
                decoration: const InputDecoration(labelText: 'Your name (for the Start page)'),
                style: TextStyle(fontSize: 15, color: c.text),
                onChanged: (v) => settings.apply((st) => st.copyWith(userName: () => v.trim().isEmpty ? null : v.trim())),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Draw with finger', style: TextStyle(fontSize: 15, color: c.text)),
                subtitle: Text(
                  'Off: only the pen draws; fingers pan and zoom.',
                  style: TextStyle(fontSize: 13, color: c.textMuted),
                ),
                value: s.fingerDraws,
                onChanged: (v) => settings.apply((st) => st.copyWith(fingerDraws: v)),
              ),
              Text('PEN & S PEN', style: TypeScale.sectionLabel.copyWith(color: c.textMuted)),
              const QuickArrowSettings(),
              Divider(color: c.lineSoft, height: 8),
              const ScribbleSettings(),
              Text('The full Settings screen is coming soon.', style: TextStyle(fontSize: 13, color: c.textFaint)),
            ],
          ),
        ),
      ),
    );
  }
}
