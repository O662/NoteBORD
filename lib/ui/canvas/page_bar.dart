import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../board/model.dart';
import '../../canvas/page_runtime.dart';
import '../../canvas/pane.dart';
import '../../library/library.dart';
import '../../state/notebook.dart';
import '../../state/page_moves.dart';
import '../../templates/templates.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart' as tokens;
import '../../theme/tokens.g.dart' show Radii, TypeScale, FontFamilies;
import '../common.dart';
import '../dialogs.dart';
import '../icons.dart';
import '../library/format.dart';
import 'panels.dart' show paintPageFitted;

/// What opens above the page bar.
enum PageLayer { peek, all, menu }

/// A page's name in the page bar ("Untitled page" until it has one).
String pageTitle(BoardPage page) => page.title.trim().isEmpty ? 'Untitled page' : page.title.trim();

/// The page bar in the bottom-left corner (Canvas.png): previous and next
/// page, the page's color, title and "3 of 12" (tap for the preview), then
/// Preview, All pages and the page menu. What they open sits above it.
class PageBar extends ConsumerStatefulWidget {
  const PageBar({super.key, required this.pane, required this.layer, required this.onLayer, required this.maxWidth});

  /// Height of the bar itself; what opens above it starts 10 dp higher.
  static const height = 48.0;

  final Pane pane;
  final PageLayer? layer;
  final ValueChanged<PageLayer?> onLayer;

  /// Room for the All pages strip.
  final double maxWidth;

  @override
  ConsumerState<PageBar> createState() => _PageBarState();
}

class _PageBarState extends ConsumerState<PageBar> {
  final _draft = TextEditingController();
  final _draftFocus = FocusNode();
  bool _renaming = false;
  bool _moving = false;

  Pane get pane => widget.pane;

  @override
  void dispose() {
    _draft.dispose();
    _draftFocus.dispose();
    super.dispose();
  }

  NotebookNotifier get _notebook => ref.read(notebookProvider(pane.notebookId).notifier);

  void _toggle(PageLayer layer) {
    setState(() => _moving = false);
    widget.onLayer(widget.layer == layer ? null : layer);
  }

  void _go(int index) {
    final n = ref.read(notebookProvider(pane.notebookId)).pages.length;
    if (index < 0 || index >= n) return;
    if (_renaming) _saveName();
    pane.goTo(index);
  }

  void _startRename(BoardPage page) {
    widget.onLayer(null);
    _draft.text = page.title;
    _draft.selection = TextSelection(baseOffset: 0, extentOffset: _draft.text.length);
    setState(() => _renaming = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _draftFocus.requestFocus());
  }

  void _saveName() {
    if (!_renaming) return;
    final nb = ref.read(notebookProvider(pane.notebookId));
    final page = nb.pageAt(pane.page);
    final name = _draft.text.trim();
    if (name.isNotEmpty) _notebook.renamePage(page.id, name);
    setState(() => _renaming = false);
  }

  void _duplicate(BoardPage page) {
    widget.onLayer(null);
    final why = _notebook.cantCopyOut(page.id);
    if (why != null) return pane.toast(why);
    final at = _notebook.duplicatePage(page.id);
    if (at == null) return;
    final copyId = ref.read(notebookProvider(pane.notebookId)).pages[at].id;
    pane.goTo(at);
    pane.toast(
      'Page duplicated',
      action: (
        'Undo',
        () {
          final back = ref.read(notebookProvider(pane.notebookId)).indexOf(page.id);
          _notebook.removePage(copyId, force: true);
          if (back >= 0) pane.goTo(back);
        },
      ),
    );
  }

  void _delete(BoardPage page) {
    widget.onLayer(null);
    final why = _notebook.cantDelete(page.id);
    if (why != null) return pane.toast(why);
    final removed = _notebook.removePage(page.id);
    if (removed == null) return;
    final n = ref.read(notebookProvider(pane.notebookId)).pages.length;
    pane.goTo(math.min(removed.$2, n - 1));
    pane.toast(
      'Page deleted',
      action: (
        'Undo',
        () {
          _notebook.restorePage(removed.$1, removed.$2);
          pane.goTo(removed.$2);
        },
      ),
    );
  }

  Future<void> _moveTo(BoardPage page, NotebookEntry target) async {
    widget.onLayer(null);
    setState(() => _moving = false);
    final container = ProviderScope.containerOf(context, listen: false);
    final (moved, why) = await movePage(container, pane.notebookId, page.id, target.id);
    if (!mounted) return;
    if (why != null) return pane.toast(why);
    if (moved == null) return;
    final n = ref.read(notebookProvider(pane.notebookId)).pages.length;
    pane.goTo(math.min(moved.index, n - 1));
    pane.toast(
      'Moved to ${target.title}',
      action: (
        'Undo',
        () async {
          await undoMove(container, moved);
          if (mounted) pane.goTo(moved.index);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: pane,
    builder: (context, _) => Consumer(builder: (context, ref, _) => _build(context, ref)),
  );

  Widget _build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final nb = ref.watch(notebookProvider(pane.notebookId));
    final n = nb.pages.length;
    final index = pane.page.clamp(0, n - 1);
    final runtime = nb.pages[index];
    final page = runtime.page;
    final sealed = nb.isSealed(page.id);
    final layer = widget.layer;
    final brightness = Theme.of(context).brightness;
    final dot = page.color == null ? c.bg : displayInk(page.color!, brightness);

    final bar = Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(Radii.card),
        boxShadow: c.cardShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 2,
        children: [
          _BarButton(label: 'Previous page', icon: EIcons.chevronLeft, enabled: index > 0, onPressed: () => _go(index - 1)),
          if (_renaming)
            _RenameField(controller: _draft, focus: _draftFocus, onSave: _saveName)
          else
            Semantics(
              button: true,
              label: 'Page ${index + 1}: ${pageTitle(page)}. Tap for the preview',
              excludeSemantics: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.key),
                onTap: () => _toggle(PageLayer.peek),
                child: SizedBox(
                  width: 196,
                  height: 40,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      spacing: 9,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: dot,
                            shape: BoxShape.circle,
                            border: Border.all(color: c.text.withValues(alpha: 0.15)),
                          ),
                        ),
                        Expanded(
                          // Two lines in a 40 dp bar: text grows only a little.
                          child: MediaQuery.withClampedTextScaling(
                            maxScaleFactor: 1.15,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  sealed ? 'Locked page' : pageTitle(page),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text, height: 1.2),
                                ),
                                Text('${index + 1} of $n', maxLines: 1, style: TextStyle(fontSize: 12, color: c.textMuted, height: 1.2)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          _BarButton(label: 'Next page', icon: EIcons.chevronRight, enabled: index < n - 1, onPressed: () => _go(index + 1)),
          Container(width: 1, height: 24, margin: const EdgeInsets.symmetric(horizontal: 3), color: c.line),
          _BarButton(
            label: 'Preview this page',
            icon: layer == PageLayer.peek ? EIcons.chevronDown : EIcons.chevronUp,
            expanded: layer == PageLayer.peek,
            background: layer == PageLayer.peek ? c.side : null,
            onPressed: () => _toggle(PageLayer.peek),
          ),
          _BarButton(label: 'Show all pages', icon: EIcons.allPages, selected: layer == PageLayer.all, onPressed: () => _toggle(PageLayer.all)),
          _BarButton(
            label: 'Page options',
            icon: EIcons.more,
            expanded: layer == PageLayer.menu,
            background: layer == PageLayer.menu ? c.side : null,
            onPressed: () => _toggle(PageLayer.menu),
          ),
        ],
      ),
    );

    Widget? above;
    switch (layer) {
      case PageLayer.peek:
        above = _PreviewCard(
          key: ValueKey(page.id),
          pane: pane,
          runtime: runtime,
          index: index,
          count: n,
          sealed: sealed,
          prevTitle: index > 0 ? pageTitle(nb.pages[index - 1].page) : 'First page',
          nextTitle: index < n - 1 ? pageTitle(nb.pages[index + 1].page) : 'Last page',
          onPrev: () => _go(index - 1),
          onNext: () => _go(index + 1),
          onClose: () => widget.onLayer(null),
        );
      case PageLayer.all:
        above = _AllPages(pane: pane, width: math.min(1004, widget.maxWidth), onHide: () => widget.onLayer(null));
      case PageLayer.menu:
        above = Padding(
          padding: const EdgeInsets.only(left: 108),
          child: _moving
              ? _MoveMenu(notebookId: pane.notebookId, onBack: () => setState(() => _moving = false), onPick: (target) => _moveTo(page, target))
              : _PageMenu(
                  title: pageTitle(page),
                  color: page.color,
                  sealed: sealed,
                  onPreview: () => widget.onLayer(PageLayer.peek),
                  onRename: () => _startRename(page),
                  onEdit: () {
                    widget.onLayer(null);
                    showEditPage(context, pane);
                  },
                  onDuplicate: () => _duplicate(page),
                  onMove: () => setState(() => _moving = true),
                  onColor: (color) => _notebook.setPageColor(page.id, color),
                  onDelete: () => _delete(page),
                ),
        );
      case null:
        above = null;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (above != null) ...[above, const SizedBox(height: 10)],
        bar,
      ],
    );
  }
}

/// A 40 × 40 button in the page bar (Canvas.dc.html).
class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.enabled = true,
    this.selected = false,
    this.expanded,
    this.background,
  });

  final String label;
  final EIconData icon;
  final VoidCallback onPressed;
  final bool enabled;
  final bool selected;
  final bool? expanded;
  final Color? background;

  @override
  Widget build(BuildContext context) => ChromeButton(
    label: label,
    icon: icon,
    width: 40,
    height: 40,
    radius: Radii.key,
    iconSize: 18,
    enabled: enabled,
    selected: selected,
    expanded: expanded,
    background: background,
    onPressed: onPressed,
  );
}

/// Rename right in the bar: the title field and a blue ✓.
class _RenameField extends StatelessWidget {
  const _RenameField({required this.controller, required this.focus, required this.onSave});

  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: 196,
      height: 40,
      padding: const EdgeInsets.only(left: 8, right: 2),
      decoration: BoxDecoration(
        border: Border.all(color: c.accent, width: 1.5),
        borderRadius: BorderRadius.circular(Radii.key),
      ),
      child: Row(
        spacing: 4,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              onSubmitted: (_) => onSave(),
              onTapOutside: (_) => onSave(),
              textInputAction: TextInputAction.done,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Page name',
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'Save name',
            excludeSemantics: true,
            child: Material(
              color: c.accent,
              borderRadius: BorderRadius.circular(Radii.small),
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.small),
                onTap: onSave,
                child: SizedBox.square(
                  dimension: 32,
                  child: Center(child: EIcon(EIcons.checkBold, size: 16, color: c.onAccent)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The card shown above the bar: the whole page, its title, when it was
/// edited, and the previous and next page (Canvas-page-preview.png).
class _PreviewCard extends ConsumerStatefulWidget {
  const _PreviewCard({
    super.key,
    required this.pane,
    required this.runtime,
    required this.index,
    required this.count,
    required this.sealed,
    required this.prevTitle,
    required this.nextTitle,
    required this.onPrev,
    required this.onNext,
    required this.onClose,
  });

  final Pane pane;
  final PageRuntime runtime;
  final int index;
  final int count;
  final bool sealed;
  final String prevTitle;
  final String nextTitle;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onClose;

  @override
  ConsumerState<_PreviewCard> createState() => _PreviewCardState();
}

class _PreviewCardState extends ConsumerState<_PreviewCard> {
  DateTime? _edited;

  @override
  void initState() {
    super.initState();
    ref.read(notebookProvider(widget.pane.notebookId).notifier).pageEdited(widget.runtime.id).then((t) {
      if (mounted) setState(() => _edited = t);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final nb = ref.watch(notebookProvider(widget.pane.notebookId));
    final page = widget.runtime.page;
    final brightness = Theme.of(context).brightness;
    final stripe = page.color == null ? c.line : displayInk(page.color!, brightness);
    final when = _edited == null ? '' : ' · edited ${agoPhrase(_edited!, DateTime.now())}';

    Widget neighbor(String label, String title, VoidCallback onTap, {required bool next}) => Semantics(
      button: true,
      label: '$label: $title',
      excludeSemantics: true,
      child: Material(
        color: c.surfaceSunk,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: c.lineSoft),
          borderRadius: BorderRadius.circular(Radii.key),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.key),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                mainAxisAlignment: next ? MainAxisAlignment.end : MainAxisAlignment.start,
                spacing: 6,
                children: [
                  if (!next) EIcon(EIcons.chevronLeft, size: 14, color: c.text),
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: next ? TextAlign.right : TextAlign.left,
                      style: TextStyle(fontSize: 13, color: c.text),
                    ),
                  ),
                  if (next) EIcon(EIcons.chevronRight, size: 14, color: c.text),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return _Card(
      width: 380,
      label: 'Page preview',
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Row(
              children: [
                Expanded(child: Text('PREVIEW', style: _labelStyle(c))),
                ChromeButton(
                  label: 'Close preview',
                  icon: EIcons.close,
                  width: 36,
                  height: 36,
                  radius: Radii.key,
                  iconSize: 16,
                  foreground: c.textMuted,
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
          Semantics(
            label: 'Whole page: ${pageTitle(page)}',
            image: true,
            excludeSemantics: true,
            child: Container(
              height: 210,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: widget.sealed ? c.side : c.bg,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(Radii.key),
              ),
              child: Stack(
                children: [
                  Positioned.fill(child: CustomPaint(painter: _DotsPainter(c.dot, 14))),
                  if (widget.sealed)
                    Center(child: EIcon(EIcons.lock, size: 28, color: c.textMuted))
                  else
                    Positioned.fill(child: CustomPaint(painter: _WholePagePainter(widget.runtime, nb.revision, brightness, c))),
                  Positioned(left: 0, right: 0, top: 0, height: 5, child: ColoredBox(color: stripe)),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  widget.sealed ? 'Locked page' : pageTitle(page),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.text),
                ),
                Text('Page ${widget.index + 1} of ${widget.count}$when', style: TextStyle(fontSize: 13, color: c.textMuted)),
              ],
            ),
          ),
          Row(
            spacing: 8,
            children: [
              Expanded(child: neighbor('Previous page', widget.prevTitle, widget.onPrev, next: false)),
              Expanded(child: neighbor('Next page', widget.nextTitle, widget.onNext, next: true)),
            ],
          ),
        ],
      ),
    );
  }
}

TextStyle _labelStyle(EndlessColors c) => TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.96, color: c.textMuted);

/// A floating card above the bar.
class _Card extends StatelessWidget {
  const _Card({required this.width, required this.label, required this.child, this.padding = const EdgeInsets.all(8)});

  final double width;
  final String label;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      label: label,
      explicitChildNodes: true,
      child: Container(
        width: width,
        padding: padding,
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(Radii.pill),
          boxShadow: c.menuShadow,
        ),
        child: child,
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  _DotsPainter(this.color, this.spacing);

  final Color color;
  final double spacing;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = <Offset>[
      for (var y = spacing / 2; y < size.height; y += spacing)
        for (var x = spacing / 2; x < size.width; x += spacing) Offset(x, y),
    ];
    canvas.drawPoints(
      PointMode.points,
      pts,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.color != color || old.spacing != spacing;
}

/// The whole page, fitted (the preview's big picture and the strip's
/// thumbnails).
class _WholePagePainter extends CustomPainter {
  _WholePagePainter(this.page, this.revision, this.brightness, this.colors, {this.inset = 12});

  final PageRuntime page;
  final int revision;
  final Brightness brightness;
  final EndlessColors colors;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final content = page.contentBounds;
    if (content == null) return;
    final padded = content.inflate(math.max(content.width, content.height) * 0.06 + 8);
    paintPageFitted(canvas, (Offset.zero & size).deflate(inset), padded, page, brightness, colors);
  }

  @override
  bool shouldRepaint(_WholePagePainter old) => old.page != page || old.revision != revision || old.brightness != brightness || old.colors != colors;
}

/// The strip of every page above the bar (Canvas.png): page colors, lock
/// badges, Add page and Hide. A long press drags a page to reorder.
class _AllPages extends ConsumerWidget {
  const _AllPages({required this.pane, required this.width, required this.onHide});

  final Pane pane;
  final double width;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final nb = ref.watch(notebookProvider(pane.notebookId));
    final notebook = ref.read(notebookProvider(pane.notebookId).notifier);
    final current = pane.page.clamp(0, nb.pages.length - 1);
    final brightness = Theme.of(context).brightness;
    // A new page in a locked notebook needs the notebook's key.
    final canAdd = !(nb.notebookLocked && nb.sealed.isNotEmpty);

    return _Card(
      width: width,
      label: 'All pages',
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Row(
              spacing: 10,
              children: [
                Expanded(child: Text('ALL PAGES · ${nb.pages.length}', style: _labelStyle(c))),
                if (width > 640) Text('Drag a page to reorder', style: TextStyle(fontSize: 12, color: c.textFaint)),
                if (canAdd)
                  Semantics(
                    button: true,
                    label: 'Add page',
                    excludeSemantics: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Radii.key),
                      onTap: () => pane.goTo(notebook.addPage()),
                      child: DashedBorder(
                        color: c.lineDashed,
                        radius: Radii.key,
                        width: 1,
                        child: SizedBox(
                          height: 36,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              spacing: 6,
                              children: [
                                EIcon(EIcons.plus, size: 14, color: c.text),
                                Text(
                                  'Add page',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Semantics(
                  button: true,
                  label: 'Hide all pages',
                  excludeSemantics: true,
                  child: Material(
                    color: c.side,
                    borderRadius: BorderRadius.circular(Radii.key),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Radii.key),
                      onTap: onHide,
                      child: SizedBox(
                        height: 36,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Center(
                            child: Text(
                              'Hide',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 124,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.fromLTRB(2, 2, 2, 6),
              itemCount: nb.pages.length,
              proxyDecorator: (child, _, _) => Material(color: Colors.transparent, child: child),
              onReorder: (from, to) {
                final id = nb.pages[current].id;
                notebook.movePage(from, to > from ? to - 1 : to);
                final now = ref.read(notebookProvider(pane.notebookId)).indexOf(id);
                if (now >= 0) pane.goTo(now);
              },
              itemBuilder: (context, i) {
                final runtime = nb.pages[i];
                final page = runtime.page;
                final locked = page.locked || nb.isSealed(page.id);
                final on = i == current;
                final stripe = page.color == null ? null : displayInk(page.color!, brightness);
                return ReorderableDelayedDragStartListener(
                  key: ValueKey(page.id),
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Semantics(
                      button: true,
                      selected: on,
                      label: 'Page ${i + 1}: ${pageTitle(page)}${locked ? ', locked' : ''}',
                      excludeSemantics: true,
                      child: GestureDetector(
                        onTap: () => pane.goTo(i),
                        child: SizedBox(
                          width: 112,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 5,
                            children: [
                              Container(
                                width: 112,
                                height: 80,
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  color: locked ? c.side : c.bg,
                                  border: Border.all(color: on ? c.accent : c.line, width: on ? 2 : 1),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Stack(
                                  children: [
                                    if (locked)
                                      Center(child: EIcon(EIcons.lock, size: 20, color: c.textMuted))
                                    else
                                      Positioned.fill(child: CustomPaint(painter: _WholePagePainter(runtime, nb.revision, brightness, c, inset: 4))),
                                    if (stripe != null) Positioned(left: 0, right: 0, top: 0, height: 4, child: ColoredBox(color: stripe)),
                                  ],
                                ),
                              ),
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '${i + 1}  ',
                                      style: TextStyle(fontWeight: FontWeight.w700, color: on ? c.accent : c.textMuted),
                                    ),
                                    TextSpan(
                                      text: pageTitle(page),
                                      style: TextStyle(fontWeight: on ? FontWeight.w700 : FontWeight.w500),
                                    ),
                                  ],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, height: 1.25, color: c.text),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The ⋯ page menu (Canvas-page-menu.png).
class _PageMenu extends StatelessWidget {
  const _PageMenu({
    required this.title,
    required this.color,
    required this.sealed,
    required this.onPreview,
    required this.onRename,
    required this.onEdit,
    required this.onDuplicate,
    required this.onMove,
    required this.onColor,
    required this.onDelete,
  });

  final String title;
  final Color? color;
  final bool sealed;
  final VoidCallback onPreview;
  final VoidCallback onRename;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onMove;
  final ValueChanged<Color?> onColor;
  final VoidCallback onDelete;

  static const _colorNames = ['Blue', 'Terracotta', 'Green', 'Plum', 'Amber', 'Teal', 'Pink'];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final brightness = Theme.of(context).brightness;
    final swatches = <(Color?, String)>[(null, 'No color'), for (final (i, col) in tokens.pageColors.indexed) (col, _colorNames[i])];
    return _Card(
      width: 276,
      label: 'Page options',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 2,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
            child: Text(title.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: _labelStyle(c)),
          ),
          MenuRow(icon: EIcons.eye, label: 'Preview', desc: 'See the whole page', onTap: onPreview),
          if (!sealed) ...[
            MenuRow(icon: EIcons.pencil, label: 'Rename', desc: 'Change the page title', onTap: onRename),
            MenuRow(icon: EIcons.sliders, label: 'Edit page', desc: 'Paper, template and background', onTap: onEdit),
            MenuRow(icon: EIcons.duplicate, label: 'Duplicate', desc: 'Adds a copy after this page', onTap: onDuplicate),
            MenuRow(icon: EIcons.moveTo, label: 'Move to…', desc: 'Another notebook', onTap: onMove),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 6,
                children: [
                  Text(
                    'Page color',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text),
                  ),
                  Semantics(
                    container: true,
                    label: 'Page color',
                    explicitChildNodes: true,
                    child: Row(
                      spacing: 2,
                      children: [
                        for (final (col, name) in swatches)
                          Semantics(
                            inMutuallyExclusiveGroup: true,
                            checked: col == color,
                            button: true,
                            label: name,
                            excludeSemantics: true,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(Radii.small),
                              onTap: () => onColor(col),
                              child: SizedBox(
                                // 28, not the design's 30: eight fit the menu.
                                width: 28,
                                height: 40,
                                child: Center(
                                  child: _Swatch(color: col == null ? null : displayInk(col, brightness), on: col == color),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          // A locked page shows its Preview only: it has to be opened first.
          if (!sealed) ...[
            Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), color: c.lineSoft),
            MenuRow(icon: EIcons.trash, label: 'Delete page', danger: true, onTap: onDelete),
          ],
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.on});

  final Color? color;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dot = color == null
        ? DashedBorder(color: c.textFaint, radius: 11, child: const SizedBox.square(dimension: 22))
        : Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          );
    if (!on) return dot;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color ?? c.textMuted, width: 2),
      ),
      child: dot,
    );
  }
}

/// A menu row: icon, label and a smaller description (46 dp tall).
class MenuRow extends StatelessWidget {
  const MenuRow({super.key, required this.icon, required this.label, this.desc, required this.onTap, this.danger = false});

  final EIconData icon;
  final String label;
  final String? desc;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = danger ? c.danger : c.text;
    return Semantics(
      button: true,
      label: desc == null ? label : '$label. $desc',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.button),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 46),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            child: Row(
              spacing: 12,
              children: [
                EIcon(icon, color: fg),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 1,
                    children: [
                      Text(
                        label,
                        style: TextStyle(fontSize: 15, fontWeight: danger ? FontWeight.w600 : FontWeight.w500, color: fg),
                      ),
                      if (desc != null) Text(desc!, style: TextStyle(fontSize: 12, color: c.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Move page to…: the other notebooks (Canvas-page-move.png).
class _MoveMenu extends ConsumerWidget {
  const _MoveMenu({required this.notebookId, required this.onBack, required this.onPick});

  final String notebookId;
  final VoidCallback onBack;
  final ValueChanged<NotebookEntry> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final library = ref.watch(libraryProvider);
    final brightness = Theme.of(context).brightness;
    final here = library.active.where((n) => n.id == notebookId).firstOrNull;
    final others = [...library.active.where((n) => n.id != notebookId)]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final list = [?here, ...others];

    Widget row(NotebookEntry n) {
      final mine = n.id == notebookId;
      final sub = mine
          ? 'This notebook · ${pagesLabel(n.pageCount)}'
          : [if (n.folder.isNotEmpty) folderLabel(n.folder), pagesLabel(n.pageCount), if (n.locked) 'Password'].join(' · ');
      return Semantics(
        button: true,
        selected: mine,
        label: '${n.title}. $sub',
        excludeSemantics: true,
        child: Material(
          color: mine ? c.side : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.button),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.button),
            onTap: mine ? onBack : () => onPick(n),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                child: Row(
                  spacing: 12,
                  children: [
                    Container(
                      width: 6,
                      height: 28,
                      decoration: BoxDecoration(color: displayInk(n.cover ?? tokens.coverColors.first, brightness), borderRadius: BorderRadius.circular(3)),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 1,
                        children: [
                          Text(
                            n.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.text),
                          ),
                          Text(
                            sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: c.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return _Card(
      width: 276,
      label: 'Move page to',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 2,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 4, bottom: 4),
            child: Row(
              spacing: 4,
              children: [
                ChromeButton(label: 'Back', icon: EIcons.chevronLeft, width: 40, height: 40, radius: Radii.key, iconSize: 18, onPressed: onBack),
                Text(
                  'Move page to…',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final n in list) row(n),
                if (others.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text('No other notebooks yet.', style: TextStyle(fontSize: 13, color: c.textMuted)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Edit page (the page menu, and ⋯ → Page & paper): the page's paper and
/// template, applied as they're picked.
Future<void> showEditPage(BuildContext context, Pane pane) => showEndlessDialog<void>(context, builder: (context) => _EditPage(pane: pane));

class _EditPage extends ConsumerWidget {
  const _EditPage({required this.pane});

  final Pane pane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final nb = ref.watch(notebookProvider(pane.notebookId));
    final notebook = ref.read(notebookProvider(pane.notebookId).notifier);
    final page = nb.pageAt(pane.page).page;
    final layouts = [
      for (final t in builtInTemplates)
        if (t.layout) t,
    ];

    Widget chip(String label, bool on, VoidCallback onTap) => Semantics(
      button: true,
      selected: on,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: on ? c.inverse : c.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: on ? c.inverse : c.lineStrong),
          borderRadius: BorderRadius.circular(Radii.chip),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: on ? c.onInverse : c.text)),
              ],
            ),
          ),
        ),
      ),
    );

    Widget section(String label) => Text(label.toUpperCase(), style: TypeScale.sectionLabel.copyWith(color: c.textMuted));

    return DialogFrame(
      title: 'Edit page',
      width: 560,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Text(
            pageTitle(page),
            style: TextStyle(fontFamily: FontFamilies.ui, fontSize: 14, color: c.textMuted),
          ),
          section('Paper'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (p, label) in const [(Paper.dots, 'Dots'), (Paper.lines, 'Lines'), (Paper.grid, 'Grid'), (Paper.blank, 'Blank')])
                chip(label, page.paper == p, () => notebook.setPagePaper(page.id, paper: p)),
            ],
          ),
          const SizedBox(height: 4),
          section('Template'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              chip('None', page.template == null, () => notebook.setPagePaper(page.id, template: () => null)),
              for (final t in layouts) chip(t.name, page.template == t.id, () => notebook.setPagePaper(page.id, template: () => t.id)),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: PrimaryButton(label: 'Done', onPressed: () => Navigator.of(context).pop()),
          ),
        ],
      ),
    );
  }
}
