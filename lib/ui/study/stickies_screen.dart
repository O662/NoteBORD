import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../board/model.dart';
import '../../canvas/page_runtime.dart' show paintItem;
import '../../library/library.dart';
import '../../math/math_pictures.dart';
import '../../recognition/handwriting_index.dart';
import '../../state/settings.dart';
import '../../study/study_rows.dart';
import '../../study/study_state.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart' as tokens;
import '../../theme/tokens.g.dart' show FontFamilies, Radii;
import '../dialogs.dart';
import '../icons.dart';
import '../library/sidebar.dart';
import '../routes.dart';

/// Each notebook's page order (for "Page 5"), read again when it changes.
final _pageOrderProvider = FutureProvider.autoDispose.family<List<String>, String>((ref, id) async {
  ref.watch(libraryProvider.select((l) => (l.byId(id)?.pageCount, l.byId(id)?.updatedAt)));
  return (await ref.read(boardStoreProvider).loadNotebookMeta(id))?.pageIds ?? const [];
});

enum _Kind { all, stacks, loose }

/// Sticky notes from every notebook (Stickies.png): each note with its
/// handwriting and color and where it lives; stacks as fanned cards. Filters
/// by kind, color and notebook, and a search of what's written on them.
/// They come from the index, so they're the notes as their pages have them;
/// notebooks and pages with a password are left out.
class StickiesScreen extends ConsumerStatefulWidget {
  const StickiesScreen({super.key});

  @override
  ConsumerState<StickiesScreen> createState() => _StickiesScreenState();
}

class _StickiesScreenState extends ConsumerState<StickiesScreen> {
  _Kind _kind = _Kind.all;
  Color? _color;
  String? _notebook;
  final _search = TextEditingController();
  String _query = '';
  StickyEntry? _open;

  @override
  void initState() {
    super.initState();
    // Anything not read into the index yet (as Remember does).
    final index = ref.read(handwritingIndexProvider);
    if (ref.read(catchUpOnStartProvider)) index.catchUp();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(StickyEntry e) {
    if (_kind == _Kind.stacks && !e.isStack) return false;
    if (_kind == _Kind.loose && e.isStack) return false;
    if (_color != null && !e.colors.contains(_color)) return false;
    if (_notebook != null && e.notebookId != _notebook) return false;
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      final words = e.said.toLowerCase();
      for (final w in q.split(RegExp(r'\s+'))) {
        if (!words.contains(w)) return false;
      }
    }
    return true;
  }

  void _clear() => setState(() {
        _kind = _Kind.all;
        _color = null;
        _notebook = null;
        _query = '';
        _search.clear();
      });

  void _go(StickyEntry e) => openSpot(context, ref, e.notebookId, e.pageId, e.rect);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lib = ref.watch(libraryProvider);
    final all = [
      for (final e in ref.watch(studyProvider)?.stickies ?? const <StickyEntry>[])
        if (lib.byId(e.notebookId) case final nb? when !nb.trashed && !nb.locked) e,
    ];
    final stacks = all.where((e) => e.isStack).length;
    final notes = all.fold<int>(0, (n, e) => n + e.count);
    final books = <String>[];
    for (final e in all) {
      if (!books.contains(e.notebookId)) books.add(e.notebookId);
    }
    if (_notebook != null && !books.contains(_notebook)) _notebook = null;
    final shown = [for (final e in all) if (_matches(e)) e];
    final lockedBooks = lib.active.where((n) => n.locked).length;
    final lockedPages = lib.active.where((n) => !n.locked).fold<int>(0, (n, e) => n + e.lockedPages);
    final open = _open == null ? null : all.where((e) => e.id == _open!.id && e.notebookId == _open!.notebookId).firstOrNull;

    final summary = all.isEmpty
        ? 'Sticky notes from every notebook show here.'
        : '${notes == 1 ? '1 note' : '$notes notes'} · ${stacks == 1 ? '1 stack' : '$stacks stacks'} · '
            'from ${books.length == 1 ? '1 notebook' : '${books.length} notebooks'}. Tap one to jump to where it lives.';

    final content = ListView(padding: const EdgeInsets.fromLTRB(36, 28, 36, 36), children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, spacing: 16, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
            Semantics(
              header: true,
              child: Row(spacing: 12, children: [
                EIcon(EIcons.stickyNotes, size: 32, color: c.text),
                Flexible(
                  child: Text('Sticky notes',
                      style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 40, height: 1.2, letterSpacing: -0.8, color: c.text)),
                ),
              ]),
            ),
            Text(summary, style: TextStyle(fontSize: 14, color: c.textMuted)),
          ]),
        ),
        Container(
          width: 280,
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(Radii.button)),
          child: Row(spacing: 8, children: [
            EIcon(EIcons.search, size: 18, color: c.textMuted),
            Expanded(
              child: Semantics(
                label: 'Search sticky notes',
                textField: true,
                child: TextField(
                  controller: _search,
                  onChanged: (q) => setState(() => _query = q),
                  style: TextStyle(fontSize: 15, color: c.text),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Search what’s written on them',
                    hintStyle: TextStyle(fontSize: 15, color: c.textMuted),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ]),
      const SizedBox(height: 18),
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: [
        _KindChoice(
          selected: _kind,
          counts: {_Kind.all: all.length, _Kind.stacks: stacks, _Kind.loose: all.length - stacks},
          onPick: (k) => setState(() => _kind = k),
        ),
        _Rule(),
        Semantics(
          container: true,
          label: 'Filter by color',
          explicitChildNodes: true,
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 2, children: [
            for (final (i, col) in tokens.stickyColors.indexed)
              _ColorFilter(
                color: col,
                name: _paperNames[i],
                on: _color == col,
                onTap: () => setState(() => _color = _color == col ? null : col),
              ),
          ]),
        ),
        _Rule(),
        Semantics(
          container: true,
          label: 'Notebook',
          explicitChildNodes: true,
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            _BookChip(label: 'All notebooks', on: _notebook == null, onTap: () => setState(() => _notebook = null)),
            for (final id in books)
              _BookChip(
                label: lib.byId(id)?.title ?? 'Notebook',
                spine: lib.coverOf(lib.byId(id)!),
                on: _notebook == id,
                onTap: () => setState(() => _notebook = id),
              ),
          ]),
        ),
      ]),
      const SizedBox(height: 24),
      if (all.isEmpty)
        _Empty(title: 'No sticky notes yet', note: 'Insert → Sticky note puts one on any page. It shows up here.')
      else if (shown.isEmpty)
        _Empty(title: 'No sticky notes match', action: ('Clear filters', _clear))
      else
        LayoutBuilder(builder: (context, box) {
          const gap = 22.0, columns = 4;
          final w = (box.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(spacing: gap, runSpacing: 24, children: [
            for (final (i, e) in shown.indexed)
              SizedBox(
                width: w,
                child: _Card(
                  entry: e,
                  tilt: _tilts[i % _tilts.length],
                  onTap: () => e.isStack ? setState(() => _open = e) : _go(e),
                  onOpen: () => _go(e),
                ),
              ),
          ]);
        }),
      if (lockedBooks > 0 || lockedPages > 0) ...[
        const SizedBox(height: 28),
        Text(_lockedLine(lockedBooks, lockedPages), style: TextStyle(fontSize: 13, color: c.textMuted)),
      ],
    ]);

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const AppSidebar(selected: SidebarItem.stickies),
          Expanded(
            child: Stack(children: [
              Positioned.fill(child: ExcludeSemantics(excluding: open != null, child: content)),
              if (open != null)
                Positioned.fill(
                  child: _StackView(entry: open, onClose: () => setState(() => _open = null), onOpen: () => _go(open)),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

const _paperNames = ['yellow', 'pink', 'peach', 'green'];
const _tilts = [-1.5, 1.0, -0.5, 1.5, -1.0, 0.5];

/// "2 locked notebooks aren't shown…": what the list leaves out.
String _lockedLine(int books, int pages) {
  final parts = <String>[
    if (books > 0) books == 1 ? '1 locked notebook isn’t shown' : '$books locked notebooks aren’t shown',
    if (pages > 0) pages == 1 ? '1 page with a password isn’t' : '$pages pages with a password aren’t',
  ];
  final what = parts.length == 2 ? '${parts[0]}, and ${parts[1]} either' : (pages > 0 ? '${parts[0]} shown' : parts[0]);
  final them = books + pages == 1 ? 'its password' : 'their passwords';
  return '$what. Remove $them to include their sticky notes.';
}

class _Rule extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 26, margin: const EdgeInsets.symmetric(horizontal: 6), color: context.colors.line);
}

class _KindChoice extends StatelessWidget {
  const _KindChoice({required this.selected, required this.counts, required this.onPick});

  final _Kind selected;
  final Map<_Kind, int> counts;
  final ValueChanged<_Kind> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const labels = {_Kind.all: 'All', _Kind.stacks: 'Stacks', _Kind.loose: 'Loose notes'};
    return Semantics(
      container: true,
      label: 'Show',
      explicitChildNodes: true,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: c.side, borderRadius: BorderRadius.circular(Radii.button)),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 2, children: [
          for (final k in _Kind.values)
            Semantics(
              inMutuallyExclusiveGroup: true,
              checked: k == selected,
              button: true,
              label: '${labels[k]}, ${counts[k]}',
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () => onPick(k),
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: k == selected
                      ? BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(9),
                          boxShadow: [BoxShadow(color: c.shadow.withValues(alpha: 0.2), blurRadius: 2, offset: const Offset(0, 1))],
                        )
                      : null,
                  child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                    Text(labels[k]!, style: TextStyle(fontSize: 14, fontWeight: k == selected ? FontWeight.w700 : FontWeight.w500, color: c.text)),
                    Text('${counts[k]}', style: TextStyle(fontSize: 12, color: c.textMuted)),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _ColorFilter extends StatelessWidget {
  const _ColorFilter({required this.color, required this.name, required this.on, required this.onTap});

  final Color color;
  final String name;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      toggled: on,
      label: on ? 'Showing $name notes' : 'Only $name notes',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.key),
        onTap: onTap,
        child: SizedBox.square(
          dimension: 44,
          child: Center(
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
                border: on ? Border.all(color: c.text, width: 2) : Border.all(color: c.text.withValues(alpha: 0.15)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BookChip extends StatelessWidget {
  const _BookChip({required this.label, required this.on, required this.onTap, this.spine});

  final String label;
  final bool on;
  final VoidCallback onTap;
  final Color? spine;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: on,
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: on ? c.inverse : c.surface,
        shape: StadiumBorder(side: BorderSide(color: on ? c.inverse : c.line)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
              if (spine != null)
                Container(
                  width: 5,
                  height: 14,
                  decoration: BoxDecoration(color: displayInk(spine!, Theme.of(context).brightness), borderRadius: BorderRadius.circular(2)),
                ),
              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: on ? c.onInverse : c.text)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// One note (or a stack, fanned with a "Stack · 5" badge), and where it
/// lives.
class _Card extends ConsumerWidget {
  const _Card({required this.entry, required this.tilt, required this.onTap, required this.onOpen});

  final StickyEntry entry;
  final double tilt;
  final VoidCallback onTap;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final note = entry.note!;
    final lib = ref.watch(libraryProvider);
    final nb = lib.byId(entry.notebookId);
    final order = ref.watch(_pageOrderProvider(entry.notebookId)).value ?? const <String>[];
    final pageNo = order.indexOf(entry.pageId);
    final where = [
      if (pageNo >= 0) 'Page ${pageNo + 1}',
      if (entry.pageTitle.trim().isNotEmpty) entry.pageTitle.trim(),
    ].join(' · ');
    final said = entry.said.isEmpty ? 'A sticky note' : entry.said;
    final label = entry.isStack ? 'Stack of ${entry.count}: $said. Open the stack' : 'Sticky note: $said. Open it on its page';

    final paper = Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          height: 176,
          child: Stack(clipBehavior: Clip.none, children: [
            if (entry.isStack) ...[
              Positioned(left: 10, top: 8, right: -6, bottom: -6, child: _Paper(color: entry.colors.elementAtOrNull(2) ?? note.color, tilt: 4)),
              Positioned(left: 5, top: 4, right: -3, bottom: -3, child: _Paper(color: entry.colors.elementAtOrNull(1) ?? note.color, tilt: 2)),
            ],
            Positioned.fill(child: _Paper(color: note.color, tilt: entry.isStack ? 0 : tilt, items: note.items, size: Size(note.w, note.h))),
            if (entry.isStack)
              Positioned(
                right: -10,
                top: -12,
                child: Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(color: c.inverse, borderRadius: BorderRadius.circular(Radii.chip), border: Border.all(color: c.bg, width: 2)),
                  child: Row(mainAxisSize: MainAxisSize.min, spacing: 5, children: [
                    EIcon(EIcons.stickyStack, size: 12, color: c.onInverse),
                    Text('Stack · ${entry.count}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.onInverse)),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
      paper,
      Semantics(
        button: true,
        label: 'Open ${nb?.title ?? 'its notebook'}${where.isEmpty ? '' : ', $where'}',
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.small),
          onTap: onOpen,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(spacing: 8, children: [
              Container(
                width: 5,
                height: 26,
                decoration: BoxDecoration(
                  color: nb == null ? c.line : displayInk(lib.coverOf(nb), Theme.of(context).brightness),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(nb?.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text)),
                  if (where.isNotEmpty) Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.textMuted)),
                ]),
              ),
              EIcon(EIcons.arrowRight, size: 16, color: c.accent),
            ]),
          ),
        ),
      ),
    ]);
  }
}

/// A sheet of sticky paper, slightly turned, with what's on it drawn as on
/// the page (scaled to fit across).
class _Paper extends ConsumerWidget {
  const _Paper({required this.color, required this.tilt, this.items = const [], this.size});

  final Color color;
  final double tilt;
  final List<Item> items;
  final Size? size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final pictures = ref.watch(mathPicturesProvider);
    return Transform.rotate(
      angle: tilt * math.pi / 180,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: color,
          boxShadow: [BoxShadow(color: c.shadow, offset: const Offset(0, 10), blurRadius: 18, spreadRadius: -12)],
        ),
        child: items.isEmpty || size == null
            ? null
            : CustomPaint(painter: _NotePainter(items, size!, pictures), size: Size.infinite),
      ),
    );
  }
}

/// A note's ink and text, from its top-left corner, scaled so the note
/// fills the width. Ink on sticky paper keeps its own color in dark mode
/// too, as on the page.
class _NotePainter extends CustomPainter {
  _NotePainter(this.items, this.note, this.math) : super(repaint: math);

  final List<Item> items;
  final Size note;
  final MathPictures math;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / note.width;
    canvas
      ..save()
      ..scale(scale);
    for (final i in items) {
      paintItem(canvas, i, Brightness.light, tokens.paperLight, math: math);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_NotePainter old) => old.items != items || old.note != note;
}

/// A stack's notes, every one (Stickies-stack.png), with Open on the page.
class _StackView extends ConsumerWidget {
  const _StackView({required this.entry, required this.onClose, required this.onOpen});

  final StickyEntry entry;
  final VoidCallback onClose;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final note = entry.note!;
    final nb = ref.watch(libraryProvider).byId(entry.notebookId);
    final order = ref.watch(_pageOrderProvider(entry.notebookId)).value ?? const <String>[];
    final pageNo = order.indexOf(entry.pageId);
    final sheets = [(note.color, note.items), for (final n in note.under) (n.color, n.items)];
    final words = entry.top.split(' ').where((w) => w.isNotEmpty).toList();
    final title = words.isEmpty ? 'Stack' : '${words.take(6).join(' ')}${words.length > 6 ? '…' : ''}';
    final where = [
      'Stack of ${entry.count}',
      ?nb?.title,
      if (pageNo >= 0) 'Page ${pageNo + 1}',
      if (entry.pageTitle.trim().isNotEmpty) entry.pageTitle.trim(),
    ].join(' · ');
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: 'Stack: $title',
      explicitChildNodes: true,
      child: Container(
        color: c.bg.withValues(alpha: 0.97),
        child: ListView(padding: const EdgeInsets.fromLTRB(40, 36, 40, 36), children: [
          Row(spacing: 14, children: [
            Semantics(
              button: true,
              label: 'Close stack',
              excludeSemantics: true,
              child: Material(
                color: c.side,
                borderRadius: BorderRadius.circular(Radii.button),
                child: InkWell(
                  borderRadius: BorderRadius.circular(Radii.button),
                  onTap: onClose,
                  child: SizedBox.square(dimension: 44, child: Center(child: EIcon(EIcons.chevronLeft, size: 20, color: c.text))),
                ),
              ),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 30, color: c.text)),
                Text(where, style: TextStyle(fontSize: 14, color: c.textMuted)),
              ]),
            ),
            SecondaryButton(label: 'Open on the page', height: 46, onPressed: onOpen),
            PrimaryButton(label: 'Done', height: 46, onPressed: onClose),
          ]),
          const SizedBox(height: 22),
          LayoutBuilder(builder: (context, box) {
            const gap = 22.0;
            final w = (box.maxWidth - gap * 3) / 4;
            return Wrap(spacing: gap, runSpacing: 24, children: [
              for (final (i, (color, items)) in sheets.indexed)
                SizedBox(
                  width: w,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
                    SizedBox(
                      height: 176,
                      child: Semantics(
                        label: 'Note ${i + 1} of ${sheets.length}',
                        image: true,
                        excludeSemantics: true,
                        child: _Paper(color: color, tilt: const [-1.0, 1.0, -0.5, 0.8, -1.2][i % 5], items: items, size: Size(note.w, note.h)),
                      ),
                    ),
                    Text('${i + 1} of ${sheets.length}', style: TextStyle(fontSize: 12, color: c.textMuted)),
                  ]),
                ),
            ]);
          }),
          const SizedBox(height: 22),
          Text('Notes stay in sync with the page they live on. Open it on the page to write on them, reorder or unstack them.',
              style: TextStyle(fontSize: 14, color: c.inverseRaised)),
        ]),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.title, this.note, this.action});

  final String title;
  final String? note;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(spacing: 8, children: [
        Text(title, style: TextStyle(fontFamily: FontFamilies.handwritingSample, fontSize: 32, color: c.textMuted)),
        if (note != null) Text(note!, style: TextStyle(fontSize: 14, color: c.textMuted)),
        if (action != null) SecondaryButton(label: action!.$1, height: 44, onPressed: action!.$2),
      ]),
    );
  }
}
