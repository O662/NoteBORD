import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/settings.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../common.dart';
import '../dialogs.dart';
import '../icons.dart';
import 'insert_menu.dart' show InsertAction;

// Your shortcuts (UPDATE_04 §10, CanvasShortcuts.dc.html "your shortcuts"):
// up to 6 tools the student puts on the left toolbar, between the four menus
// and Search. Saved on this tablet in settings.json (`prefs['shortcuts']`);
// settings don't sync yet (the owner's choice, 2026-11-11).

/// What tapping a shortcut does.
enum ShortcutKind {
  /// Switches a tool on in place (dark while on); tapping it again goes back
  /// to the pen.
  tool,

  /// Opens the feature straight away.
  feature,
}

/// One tool that can be a shortcut.
class ShortcutTool {
  const ShortcutTool(
    this.id,
    this.group,
    this.label,
    this.desc,
    this.icon, {
    this.kind = ShortcutKind.feature,
    this.tile,
    this.tint,
    this.railLabel,
    this.insert,
    this.more,
  });

  /// Saved in settings.json.
  final String id;

  /// Insert, Study & math, Writing help or Tools & view.
  final String group;
  final String label;
  final String desc;
  final EIconData icon;
  final ShortcutKind kind;
  final Color Function(EndlessColors c)? tile;
  final Color Function(EndlessColors c)? tint;

  /// Runs like this toolbar menu item (its label in `railGroups`).
  final String? railLabel;

  /// Runs like this Insert menu tile.
  final InsertAction? insert;

  /// Runs like this ⋯ menu item.
  final String? more;

  bool get isTool => kind == ShortcutKind.tool;
}

const maxShortcuts = 6;

/// Reset to the default: Record audio, PDF, Ruler.
const defaultShortcuts = ['mic', 'pdf', 'ruler'];

Color _yellow(EndlessColors c) => c.stickyYellow;
Color _gold(EndlessColors c) => c.gold;
Color _clayTint(EndlessColors c) => c.clayTint;
Color _danger(EndlessColors c) => c.danger;
Color _clay(EndlessColors c) => c.clay;
Color _clayDeep(EndlessColors c) => c.clayDeep;
Color _blueTint(EndlessColors c) => c.accentTint;
Color _blueDeep(EndlessColors c) => c.accentDeep;
Color _greenTint(EndlessColors c) => c.greenTint;
Color _greenDeep(EndlessColors c) => c.greenDeep;

/// Every tool that can be a shortcut, grouped as the panel lists them.
final List<ShortcutTool> shortcutCatalog = [
  ShortcutTool('sticky', 'Insert', 'Sticky note', 'Drop one on the page', EIcons.sticky,
      kind: ShortcutKind.tool, tile: _yellow, tint: _gold, railLabel: 'Sticky note'),
  ShortcutTool('image', 'Insert', 'Image', 'Photos, camera or files', EIcons.image, railLabel: 'Image'),
  ShortcutTool('pdf', 'Insert', 'PDF', 'Pages you can write on', EIcons.pdfDoc, tile: _clayTint, tint: _clay),
  ShortcutTool('mic', 'Insert', 'Record audio', 'Replays with your ink', EIcons.mic,
      tile: _clayTint, tint: _danger, railLabel: 'Record audio'),
  ShortcutTool('video', 'Insert', 'Video', 'From files or a link', EIcons.video, insert: InsertAction.video),
  ShortcutTool('web', 'Insert', 'Website', 'A live web page on the board', EIcons.globe,
      tile: _blueTint, tint: _blueDeep, insert: InsertAction.website),
  ShortcutTool('table', 'Insert', 'Table', 'Rows and columns', EIcons.table, insert: InsertAction.table),
  ShortcutTool('chart', 'Insert', 'Chart', 'Linked to a table or Excel', EIcons.chart, insert: InsertAction.chart),
  ShortcutTool('check', 'Insert', 'Checklist', 'Tick things off', EIcons.checklist, insert: InsertAction.checklist),
  ShortcutTool('clock', 'Insert', 'Time stamp', 'Date, time or a live clock', EIcons.clock, insert: InsertAction.clock),
  ShortcutTool('frame', 'Insert', 'Paper frame', 'A lined sheet to write on', EIcons.frame,
      kind: ShortcutKind.tool, railLabel: 'Paper frame'),
  ShortcutTool('templates', 'Insert', 'Templates', 'Cornell, planner, lab report…', EIcons.templates, railLabel: 'Templates'),
  ShortcutTool('remember', 'Study & math', 'Need to remember', 'Star it or lasso it', EIcons.star,
      tile: _yellow, tint: _gold, railLabel: 'Need to remember'),
  ShortcutTool('cards', 'Study & math', 'Make flashcards', 'Circle the front, then the back', EIcons.flashcards,
      tile: _clayTint, tint: _clayDeep, railLabel: 'Make flashcards'),
  ShortcutTool('math', 'Study & math', 'Math & graphs', 'Handwriting to math', EIcons.sigma,
      tile: _blueTint, tint: _blueDeep, railLabel: 'Math & graphs'),
  ShortcutTool('graph', 'Study & math', 'Graph', 'Plot y = … or x, y, z', EIcons.graph,
      tile: _blueTint, tint: _blueDeep, insert: InsertAction.graph),
  ShortcutTool('mathtools', 'Study & math', 'Math tools', 'Number line, unit circle, formulas', EIcons.mathTools,
      tile: _blueTint, tint: _blueDeep, railLabel: 'Math tools'),
  ShortcutTool('spell', 'Writing help', 'Spell check', 'Check this page', EIcons.spellPlain,
      tile: _clayTint, tint: _danger, railLabel: 'Spell check'),
  ShortcutTool('dict', 'Writing help', 'Dictionary & thesaurus', 'Definitions and similar words', EIcons.book,
      tile: _greenTint, tint: _greenDeep, railLabel: 'Dictionary & thesaurus'),
  ShortcutTool('convert', 'Writing help', 'Convert to text', 'Handwriting into type', EIcons.text, railLabel: 'Convert to text'),
  ShortcutTool('ruler', 'Tools & view', 'Ruler', 'Two fingers rotate · pen snaps', EIcons.ruler,
      kind: ShortcutKind.tool, railLabel: 'Ruler'),
  ShortcutTool('laser', 'Tools & view', 'Laser pointer', 'Fades away, never saved', EIcons.laser,
      kind: ShortcutKind.tool, tile: _clayTint, tint: _danger, railLabel: 'Laser pointer'),
  ShortcutTool('split', 'Tools & view', 'Split view', 'Two notes side by side', EIcons.split, railLabel: 'Split view'),
  ShortcutTool('window', 'Tools & view', 'Window view', 'A floating window', EIcons.windowView, railLabel: 'Window view'),
  ShortcutTool('print', 'Tools & view', 'Print', 'Drag page boxes over the board', EIcons.print, more: 'Print…'),
  ShortcutTool('export', 'Tools & view', 'Export', 'PDF, board file or image', EIcons.export, more: 'Export'),
  ShortcutTool('history', 'Tools & view', 'Version history', 'See and restore earlier versions', EIcons.history,
      more: 'Version history'),
];

const shortcutGroups = ['Insert', 'Study & math', 'Writing help', 'Tools & view'];

final Map<String, ShortcutTool> _byId = {for (final t in shortcutCatalog) t.id: t};

ShortcutTool? shortcutById(String id) => _byId[id];

/// The shortcut a toolbar menu item can be pinned as (by its label), if any.
/// "Everything else" opens a menu, so it can't.
ShortcutTool? shortcutForRailItem(String label) =>
    shortcutCatalog.where((t) => t.railLabel == label).firstOrNull;

/// Tools whose catalog text matches [query] (label, description or group).
List<ShortcutTool> searchShortcuts(String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return shortcutCatalog;
  return [
    for (final t in shortcutCatalog)
      if ('${t.label} ${t.desc} ${t.group}'.toLowerCase().contains(q)) t,
  ];
}

extension ShortcutSettings on AppSettings {
  /// The shortcuts on the toolbar, in order (unknown ids dropped).
  List<String> get shortcuts {
    final v = prefs['shortcuts'];
    if (v is! List) return defaultShortcuts;
    return [
      for (final id in v.whereType<String>())
        if (_byId.containsKey(id)) id,
    ].take(maxShortcuts).toList();
  }

  AppSettings withShortcuts(List<String> ids) => withPref('shortcuts', ids.take(maxShortcuts).toList());
}

extension ShortcutEditing on SettingsNotifier {
  /// Adds [id] at the end, or takes it off; nothing when adding to a full
  /// toolbar.
  void toggleShortcut(String id) => apply((s) {
        final list = s.shortcuts;
        if (list.contains(id)) return s.withShortcuts([...list]..remove(id));
        if (list.length >= maxShortcuts) return s;
        return s.withShortcuts([...list, id]);
      });

  /// Swaps the shortcut at [index] with the one [by] away (−1 up, +1 down).
  void moveShortcut(int index, int by) => apply((s) {
        final list = [...s.shortcuts];
        final to = index + by;
        if (index < 0 || to < 0 || index >= list.length || to >= list.length) return s;
        final t = list[index];
        list[index] = list[to];
        list[to] = t;
        return s.withShortcuts(list);
      });

  void resetShortcuts() => apply((s) => s.withShortcuts(defaultShortcuts));
}

/// The Your shortcuts panel as a dialog (Settings › Pen & S Pen › Writing ›
/// Toolbar shortcuts).
Future<void> showShortcutsDialog(BuildContext context) => showEndlessDialog<void>(
      context,
      builder: (context) {
        final size = MediaQuery.sizeOf(context);
        return ShortcutsPanel(
          width: dialogMaxWidth(size.width).clamp(0, 690).toDouble(),
          height: (size.height - 48).clamp(0, 640).toDouble(),
          onClose: () => Navigator.of(context).pop(),
        );
      },
    );

/// The dashed "Your shortcuts" button at the bottom of the toolbar.
class ShortcutsButton extends StatelessWidget {
  const ShortcutsButton({super.key, required this.open, required this.onPressed});

  final bool open;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ChromeButton(
      label: 'Add or edit your shortcuts',
      expanded: open,
      background: open ? c.inverse : null,
      onPressed: onPressed,
      child: DashedBorder(
        color: open ? c.inverse : c.lineDashed,
        radius: Radii.button,
        child: SizedBox.square(
          dimension: Sizes.touchTarget,
          child: Center(child: EIcon(EIcons.addShortcut, color: open ? c.onInverse : c.textMuted)),
        ),
      ),
    );
  }
}

/// The pin beside a toolbar menu item: adds it to the shortcuts, or (filled)
/// takes it off. Greyed when the toolbar is full.
class ShortcutPin extends ConsumerWidget {
  const ShortcutPin({super.key, required this.tool});

  final ShortcutTool tool;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final list = ref.watch(settingsProvider.select((s) => s.shortcuts));
    final on = list.contains(tool.id);
    final full = !on && list.length >= maxShortcuts;
    final label = on
        ? 'Remove ${tool.label} from your shortcuts'
        : full
            ? 'Your shortcuts are full ($maxShortcuts)'
            : 'Add ${tool.label} to your shortcuts';
    return Semantics(
      container: true,
      button: true,
      toggled: on,
      enabled: !full,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.key),
        onTap: full ? null : () => ref.read(settingsProvider.notifier).toggleShortcut(tool.id),
        child: SizedBox(
          width: 40,
          height: 44,
          child: Center(
            child: EIcon(
              on ? EIcons.pushpinFilled : EIcons.pushpin,
              size: 18,
              color: on ? c.accent : (full ? c.lineStrong : c.textFaint),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 36 dp tile with a tool's icon (the menus' and the panel's).
class ShortcutTile extends StatelessWidget {
  const ShortcutTile({super.key, required this.tool, this.size = 36});

  final ShortcutTool tool;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tool.tile?.call(c) ?? c.menuTile,
        borderRadius: BorderRadius.circular(size > 33 ? Radii.key : 9),
      ),
      child: Center(child: EIcon(tool.icon, color: tool.tint?.call(c) ?? c.text)),
    );
  }
}

/// The Your shortcuts panel (CanvasShortcuts.png): on the left what's on the
/// toolbar ("3 of 6") with move up / down, remove, empty spots and Reset to
/// the default; on the right every tool, grouped, with a search and + Add /
/// ✓ Added / Full. Done closes it.
class ShortcutsPanel extends ConsumerStatefulWidget {
  const ShortcutsPanel({super.key, required this.onClose, this.width = 690, this.height = 640});

  final VoidCallback onClose;
  final double width;
  final double height;

  @override
  ConsumerState<ShortcutsPanel> createState() => _ShortcutsPanelState();
}

class _ShortcutsPanelState extends ConsumerState<ShortcutsPanel> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mine = ref.watch(settingsProvider.select((s) => s.shortcuts));
    final edit = ref.read(settingsProvider.notifier);
    final full = mine.length >= maxShortcuts;
    final found = searchShortcuts(_query.text);
    final narrow = widget.width < 600;

    final left = Container(
      color: c.surfaceSunk,
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        Text(
          'On your toolbar · ${mine.length} of $maxShortcuts'.toUpperCase(),
          style: TypeScale.sectionLabel.copyWith(fontWeight: FontWeight.w700, color: c.textMuted),
        ),
        Expanded(
          child: ListView(padding: EdgeInsets.zero, children: [
            for (var i = 0; i < mine.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _MineRow(
                  tool: shortcutById(mine[i])!,
                  first: i == 0,
                  last: i == mine.length - 1,
                  onUp: () => edit.moveShortcut(i, -1),
                  onDown: () => edit.moveShortcut(i, 1),
                  onRemove: () => edit.toggleShortcut(mine[i]),
                ),
              ),
            for (var i = 0; i < (maxShortcuts - mine.length).clamp(0, 3); i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: DashedBorder(
                  color: c.lineStrong,
                  radius: Radii.button,
                  child: SizedBox(
                    height: 52,
                    child: Center(child: Text('Empty spot', style: TextStyle(fontSize: 13, color: c.textFaint))),
                  ),
                ),
              ),
          ]),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Semantics(
            button: true,
            label: 'Reset to the default',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.key),
              onTap: edit.resetShortcuts,
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                child: Text('Reset to the default', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.accent)),
              ),
            ),
          ),
        ),
      ]),
    );

    final right = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Semantics(
          label: 'Find a tool',
          textField: true,
          child: TextField(
            controller: _query,
            onChanged: (_) => setState(() {}),
            style: TextStyle(fontSize: 15, color: c.text),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Find a tool, e.g. website, ruler, PDF',
              hintStyle: TextStyle(fontSize: 15, color: c.textMuted),
              prefixIcon: Padding(padding: const EdgeInsets.all(12), child: EIcon(EIcons.search, color: c.textMuted)),
              prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              filled: true,
              fillColor: c.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Radii.button),
                borderSide: BorderSide(color: c.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Radii.button),
                borderSide: BorderSide(color: c.accent, width: 1.5),
              ),
            ),
          ),
        ),
      ),
      Expanded(
        child: found.isEmpty
            ? Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Text(
                  'Nothing matches. Try “audio”, “web” or “graph”.',
                  style: TextStyle(fontSize: 14, color: c.textMuted),
                ),
              )
            : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 10, 12), children: [
                for (final g in shortcutGroups)
                  if (found.any((t) => t.group == g)) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 4),
                      child: Text(
                        g.toUpperCase(),
                        style: TypeScale.sectionLabel.copyWith(fontWeight: FontWeight.w700, color: c.textMuted),
                      ),
                    ),
                    for (final t in found.where((t) => t.group == g))
                      _CatalogRow(
                        tool: t,
                        added: mine.contains(t.id),
                        full: full,
                        onToggle: () => edit.toggleShortcut(t.id),
                      ),
                  ],
              ]),
      ),
    ]);

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: 'Your shortcuts',
      explicitChildNodes: true,
      child: Container(
        width: widget.width,
        height: widget.height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(20),
          boxShadow: c.modalShadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(22, 18, 18, 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.lineSoft))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
                  Semantics(
                    header: true,
                    child: Text('Your shortcuts', style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 26, color: c.text)),
                  ),
                  Text(
                    'Put the things you use most on the left toolbar, one tap away. Up to $maxShortcuts.',
                    style: TextStyle(fontSize: 14, color: c.textMuted),
                  ),
                ]),
              ),
              ChromeButton(label: 'Close', icon: EIcons.close, foreground: c.textMuted, onPressed: widget.onClose),
            ]),
          ),
          Expanded(
            child: narrow
                // Portrait phones and narrow windows: the list above the catalog.
                ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    SizedBox(height: 260, child: left),
                    Divider(height: 1, color: c.lineSoft),
                    Expanded(child: right),
                  ])
                : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    SizedBox(width: 280, child: left),
                    VerticalDivider(width: 1, color: c.lineSoft),
                    Expanded(child: right),
                  ]),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(22, 12, 18, 14),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.lineSoft))),
            child: Row(spacing: 12, children: [
              EIcon(EIcons.pushpin, size: 18, color: c.greenDeep),
              Expanded(
                child: Text(
                  'Tip: in any toolbar menu, tap the pin next to a tool to add it here.',
                  style: TextStyle(fontSize: 13, color: c.text),
                ),
              ),
              PrimaryButton(label: 'Done', height: 44, onPressed: widget.onClose),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _MineRow extends StatelessWidget {
  const _MineRow({
    required this.tool,
    required this.first,
    required this.last,
    required this.onUp,
    required this.onDown,
    required this.onRemove,
  });

  final ShortcutTool tool;
  final bool first;
  final bool last;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget small(String label, EIconData icon, VoidCallback? onTap, {Color? color, double width = 30}) => ChromeButton(
          label: label,
          icon: icon,
          width: width,
          iconSize: 18,
          enabled: onTap != null,
          foreground: color ?? c.text,
          onPressed: onTap,
        );
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.only(left: 8, right: 4),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.lineSoft),
        borderRadius: BorderRadius.circular(Radii.button),
      ),
      child: Row(spacing: 8, children: [
        ShortcutTile(tool: tool, size: 32),
        Expanded(
          child: Text(tool.label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.2, color: c.text)),
        ),
        small('Move ${tool.label} up', EIcons.chevronUp, first ? null : onUp),
        small('Move ${tool.label} down', EIcons.chevronDown, last ? null : onDown),
        small('Remove ${tool.label}', EIcons.close, onRemove, color: c.danger, width: 34),
      ]),
    );
  }
}

class _CatalogRow extends StatelessWidget {
  const _CatalogRow({required this.tool, required this.added, required this.full, required this.onToggle});

  final ShortcutTool tool;
  final bool added;
  final bool full;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final off = !added && full;
    final text = added ? 'Added' : (off ? 'Full' : '+ Add');
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.only(right: 4, top: 2, bottom: 2),
        child: Row(spacing: 12, children: [
          ShortcutTile(tool: tool),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              Text(tool.label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
              Text(tool.desc, style: TextStyle(fontSize: 12, color: c.textMuted)),
            ]),
          ),
          Semantics(
            container: true,
            button: true,
            toggled: added,
            enabled: !off,
            label: added ? 'Remove ${tool.label} from your shortcuts' : (off ? 'Your shortcuts are full' : 'Add ${tool.label}'),
            excludeSemantics: true,
            child: Opacity(
              opacity: off ? 0.45 : 1,
              child: Material(
                color: added ? c.greenTint : c.surface,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: added ? c.greenLine : c.lineStrong),
                  borderRadius: BorderRadius.circular(Radii.key),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(Radii.key),
                  onTap: off ? null : onToggle,
                  child: Container(
                    height: 44,
                    constraints: const BoxConstraints(minWidth: 84),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                      // Figtree has no ✓, so the check is drawn.
                      if (added) EIcon(EIcons.checkBold, size: 14, color: c.greenDeep),
                      Text(
                        text,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: added ? c.greenDeep : c.text),
                      ),
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
