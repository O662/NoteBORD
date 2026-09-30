import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../dialogs.dart';
import '../icons.dart';
import 'coming_soon.dart';

/// What picking something in the Insert menu does. Everything else in the
/// menu opens a "coming soon" card.
enum InsertAction {
  sticky,
  stack,
  text,
  frame,
  shape,
  image,
  tablet,
  camera,
  templates,
  table,
  diagram,
  timeline,
  kanban,
  website,
}

/// One tile of the Insert menu (Insert.dc.html).
class InsertEntry {
  const InsertEntry(
    this.label, {
    this.icon,
    this.badge,
    this.math = false,
    required this.tile,
    required this.tint,
    this.action,
    this.soon,
    this.keywords = '',
    this.small = false,
  }) : assert(action != null || soon != null);

  final String label;
  final EIconData? icon;

  /// A file type shown as letters instead of an icon: PDF, DOCX…
  final String? badge;

  /// The "∑ π" tile.
  final bool math;
  final Color Function(EndlessColors c) tile;
  final Color Function(EndlessColors c) tint;

  /// What it does now…
  final InsertAction? action;

  /// …or what it will do, for the "coming soon" card.
  final String? soon;

  /// Other words the search finds it by.
  final String keywords;

  /// The design sets a few labels at 13 px.
  final bool small;

  /// Whether a search for [query] finds it: anywhere in its name, or at the
  /// start of one of its other words.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    return q.isEmpty || label.toLowerCase().contains(q) || keywords.split(' ').any((w) => w.startsWith(q));
  }

  /// The icon on its 44 px colored tile.
  Widget iconTile(EndlessColors c, {double size = 44}) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: tile(c), borderRadius: BorderRadius.circular(Radii.button)),
        child: badge != null
            ? Text(badge!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: tint(c), height: 1))
            : math
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    EIcon(EIcons.sigma, size: 19, color: tint(c)),
                    EIcon(EIcons.pi, size: 19, color: tint(c)),
                  ])
                : EIcon(icon!, size: 24, color: tint(c)),
      );
}

Color _yellow(EndlessColors c) => c.stickyYellow;
Color _stickyInk(EndlessColors c) => c.stickyDeep;
Color _neutral(EndlessColors c) => c.side;
Color _ink(EndlessColors c) => c.text;
Color _blue(EndlessColors c) => c.accentTint;
Color _blueInk(EndlessColors c) => c.accentDeep;
Color _clay(EndlessColors c) => c.clayTint;
Color _clayInk(EndlessColors c) => c.clayDeep;
Color _green(EndlessColors c) => c.greenTint;
Color _greenInk(EndlessColors c) => c.greenDeep;
Color _plum(EndlessColors c) => c.plumTint;
Color _plumInk(EndlessColors c) => c.plumDeep;
Color _gold(EndlessColors c) => c.gold;

class InsertSection {
  const InsertSection(this.title, this.columns, this.entries);

  final String title;
  final int columns;
  final List<InsertEntry> entries;
}

/// The Insert menu's four groups, in design order.
final List<InsertSection> insertSections = [
  InsertSection('On the page', 5, [
    InsertEntry('Sticky note', icon: EIcons.sticky, tile: _yellow, tint: _stickyInk, action: InsertAction.sticky, keywords: 'post-it note'),
    InsertEntry('Sticky stack', icon: EIcons.stickyStack, tile: _yellow, tint: _stickyInk, action: InsertAction.stack, keywords: 'post-it notes pile'),
    InsertEntry('Text box', icon: EIcons.text, tile: _neutral, tint: _ink, action: InsertAction.text, keywords: 'type typed keyboard label'),
    InsertEntry('Paper frame', icon: EIcons.frame, tile: _neutral, tint: _ink, action: InsertAction.frame, keywords: 'lined sheet a4 page'),
    InsertEntry('Shape', icon: EIcons.shapes, tile: _neutral, tint: _ink, action: InsertAction.shape, keywords: 'rectangle circle oval triangle line arrow'),
  ]),
  InsertSection('Files', 7, [
    InsertEntry('Video', icon: EIcons.video, tile: _plum, tint: _plumInk, small: true, keywords: 'movie clip mp4',
        soon: 'Play a video inside your notes, pin notes to moments in it and grab a frame.'),
    InsertEntry('Audio', icon: EIcons.mic, tile: _clay, tint: _clayInk, small: true, keywords: 'record recording sound voice',
        soon: 'Record while you write. Your ink lights up as the recording plays back, and you get a transcript.'),
    InsertEntry('Image or photo', icon: EIcons.image, tile: _green, tint: _greenInk, action: InsertAction.image, keywords: 'picture camera png jpg'),
    InsertEntry('PDF', badge: 'PDF', tile: _clay, tint: _clayInk, keywords: 'document file',
        soon: 'Put a PDF on the board and write on top of it.'),
    InsertEntry('Word document', badge: 'DOCX', tile: _blue, tint: _blueInk, keywords: 'docx file',
        soon: 'A live preview of a Word document on the board. Write on top of it, or tap to open it in its own app.'),
    InsertEntry('PowerPoint', badge: 'PPTX', tile: _clay, tint: _clayInk, keywords: 'pptx slides presentation file',
        soon: 'Slides on the board, one at a time, with your ink on top.'),
    InsertEntry('Excel sheet', badge: 'XLSX', tile: _green, tint: _greenInk, keywords: 'xlsx spreadsheet file',
        soon: 'A spreadsheet on the board. Charts linked to it update when it changes.'),
  ]),
  InsertSection('Build on the board', 7, [
    InsertEntry('Math', math: true, tile: _blue, tint: _blueInk, small: true, keywords: 'equation formula latex',
        soon: 'Write an equation by hand and it turns into typeset math as you go.'),
    InsertEntry('Graph', icon: EIcons.graph, tile: _blue, tint: _blueInk, small: true, keywords: 'plot function xy xyz',
        soon: 'Plot functions in 2D or 3D, trace them and find where they cross.'),
    InsertEntry('Table', icon: EIcons.table, tile: _blue, tint: _blueInk, action: InsertAction.table, keywords: 'rows columns grid cells'),
    InsertEntry('Diagram', icon: EIcons.diagram, tile: _plum, tint: _plumInk, action: InsertAction.diagram, keywords: 'flowchart flow steps boxes arrows'),
    InsertEntry('Timeline', icon: EIcons.timeline, tile: _plum, tint: _plumInk, action: InsertAction.timeline, keywords: 'dates schedule milestones events'),
    InsertEntry('Kanban board', icon: EIcons.kanban, tile: _plum, tint: _plumInk, action: InsertAction.kanban, keywords: 'tasks to do doing done cards'),
    InsertEntry('Website', icon: EIcons.globe, tile: _blue, tint: _blueInk, action: InsertAction.website, keywords: 'web page link url embed'),
  ]),
  InsertSection('Live widgets', 7, [
    InsertEntry('Calendar', icon: EIcons.calendar, tile: _blue, tint: _blueInk, keywords: 'events month week',
        soon: 'Your calendar on the page, always up to date.'),
    InsertEntry('Planner', icon: EIcons.planner, tile: _green, tint: _greenInk, keywords: 'today schedule to-do',
        soon: 'Today’s top three, to-dos and schedule, live on the page.'),
    InsertEntry('Flashcards', icon: EIcons.flashcards, tile: _clay, tint: _clayInk, keywords: 'deck study cards',
        soon: 'A deck on the page showing what’s due, ready to study.'),
    InsertEntry('Need to remember', icon: EIcons.star, tile: _yellow, tint: _gold, keywords: 'star starred important',
        soon: 'Everything you starred, gathered on the page.'),
    InsertEntry('Chart', icon: EIcons.chart, tile: _blue, tint: _blueInk, keywords: 'bar line area scatter data',
        soon: 'Bar, line, area or scatter charts that follow a table or an Excel sheet.'),
    InsertEntry('Clock & date', icon: EIcons.clock, tile: _blue, tint: _blueInk, small: true, keywords: 'time stamp today',
        soon: 'A live clock, the date, or a time stamp.'),
    InsertEntry('Checklist', icon: EIcons.checklist, tile: _green, tint: _greenInk, small: true, keywords: 'to-do tasks tick',
        soon: 'Tick things off and watch the progress bar fill.'),
  ]),
];

/// Where files can be picked from (the chips under the tiles).
final List<InsertEntry> insertSources = [
  InsertEntry('This tablet', icon: EIcons.download, tile: _neutral, tint: _ink, action: InsertAction.tablet),
  InsertEntry('Google Drive', icon: EIcons.folder, tile: _blue, tint: _blueInk,
      soon: 'Pick files straight from Google Drive.'),
  InsertEntry('OneDrive', icon: EIcons.folder, tile: _blue, tint: _blueInk, soon: 'Pick files straight from OneDrive.'),
  InsertEntry('Camera', icon: EIcons.camera, tile: _green, tint: _greenInk, action: InsertAction.camera),
  InsertEntry('Scan a document', icon: EIcons.scan, tile: _neutral, tint: _ink,
      soon: 'Scan paper notes with the camera and straighten them into pages.'),
];

/// The "coming soon" card for an Insert menu entry.
Future<void> showEntryComingSoon(BuildContext context, InsertEntry entry) => showComingSoonCard(
      context,
      title: entry.label,
      message: entry.soon!,
      icon: entry.iconTile(context.colors, size: 52),
    );

/// Opens the full Insert menu (design/screens/Insert.png). Returns what to
/// insert, or null if it was closed.
Future<InsertAction?> showInsertMenu(BuildContext context) =>
    showEndlessDialog<InsertAction>(context, builder: (_) => const InsertMenu());

class InsertMenu extends StatefulWidget {
  const InsertMenu({super.key});

  @override
  State<InsertMenu> createState() => _InsertMenuState();
}

class _InsertMenuState extends State<InsertMenu> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _pick(InsertEntry entry) {
    if (entry.action case final action?) {
      Navigator.of(context).pop(action);
    } else {
      showEntryComingSoon(context, entry);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = MediaQuery.sizeOf(context);
    final query = _search.text;
    final sections = [
      for (final s in insertSections)
        if (s.entries.any((e) => e.matches(query))) s,
    ];

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: 'Insert',
      explicitChildNodes: true,
      child: Container(
        width: math.min(780, size.width - 48),
        height: math.min(752, size.height - 48),
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(22), boxShadow: c.modalShadow),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
          Row(spacing: 14, children: [
            Semantics(
              header: true,
              child: Text('Insert', style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 30, height: 1.2, color: c.text)),
            ),
            Expanded(child: _searchField(c)),
            DialogCloseButton(onPressed: () => Navigator.of(context).pop()),
          ]),
          Expanded(
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
                for (final s in sections) _section(c, s, query),
                if (sections.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Text(
                      'Nothing to insert matches “${query.trim()}”.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: c.textMuted),
                    ),
                  ),
                if (query.trim().isEmpty) _sources(c),
              ]),
            ),
          ),
          Container(
            padding: const EdgeInsets.only(top: 14),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.lineSoft))),
            child: Row(spacing: 16, children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Text(
                      'Files show a live preview on the board. Write on top of them, or tap to open in their own app.',
                      style: TextStyle(fontSize: 13, height: 1.45, color: c.textMuted),
                    ),
                  ),
                ),
              ),
              SecondaryButton(
                label: 'Browse templates',
                icon: EIcons.templates,
                height: 46,
                onPressed: () => Navigator.of(context).pop(InsertAction.templates),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _searchField(EndlessColors c) => Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: c.bg,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(Radii.button),
        ),
        child: Row(spacing: 10, children: [
          EIcon(EIcons.search, size: 18, color: c.textMuted),
          Expanded(
            child: Semantics(
              label: 'Search things to insert',
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                cursorColor: c.accent,
                style: TextStyle(fontSize: 15, color: c.text),
                decoration: InputDecoration.collapsed(
                  hintText: 'Search: table, timeline, PDF…',
                  hintStyle: TextStyle(fontSize: 15, color: c.textMuted),
                ),
              ),
            ),
          ),
        ]),
      );

  Widget _section(EndlessColors c, InsertSection s, String query) {
    final shown = [for (final e in s.entries) if (e.matches(query)) e];
    final gap = s.columns == 5 ? 10.0 : 8.0;
    return Semantics(
      container: true,
      label: s.title,
      explicitChildNodes: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        Text(s.title.toUpperCase(), style: TypeScale.sectionLabel.copyWith(height: 1.2, color: c.textMuted)),
        // Tiles keep their column's width, so search results don't stretch.
        Row(spacing: gap, children: [
          for (var i = 0; i < s.columns; i++)
            Expanded(child: i < shown.length ? _Tile(entry: shown[i], onTap: () => _pick(shown[i])) : const SizedBox()),
        ]),
      ]),
    );
  }

  Widget _sources(EndlessColors c) => Semantics(
        container: true,
        label: 'Pick files from',
        explicitChildNodes: true,
        child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text('Pick files from', style: TextStyle(fontSize: 14, height: 1.2, color: c.textMuted)),
          ),
          for (final e in insertSources)
            Semantics(
              button: true,
              label: e.label,
              excludeSemantics: true,
              child: Material(
                color: Colors.transparent,
                shape: StadiumBorder(side: BorderSide(color: c.lineStrong)),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => _pick(e),
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Center(
                      widthFactor: 1,
                      child: Text(e.label, style: TextStyle(fontSize: 14, height: 1.2, color: c.text)),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.entry, required this.onTap});

  final InsertEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: entry.label,
      hint: entry.action == null ? 'Coming soon' : null,
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(side: BorderSide(color: c.cardLine), borderRadius: BorderRadius.circular(Radii.card)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 84,
            child: LayoutBuilder(
              builder: (context, box) => Center(
                // Two-line labels are a touch taller than the tile; they
                // shrink to fit, as they do at large font sizes. Labels
                // wrap 7 px in from the tile's edges, as in the design.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: math.max(40, box.maxWidth - 14)),
                    child: Column(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                      entry.iconTile(c),
                      Text(
                        entry.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: TextStyle(
                          fontSize: entry.small ? 13 : 14,
                          fontWeight: FontWeight.w500,
                          height: 1.2,
                          color: c.text,
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
