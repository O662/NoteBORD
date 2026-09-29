import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../canvas/ink_canvas.dart';
import '../../canvas/pane.dart';
import '../../library/library.dart';
import '../../state/notebook.dart';
import '../../state/settings.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../canvas/canvas_screen.dart' show handleMoreItem, handleRailItem, pickCanvasTool;
import '../canvas/gesture_status.dart';
import '../canvas/left_rail.dart';
import '../canvas/pen_popover.dart';
import '../canvas/top_bar.dart';
import '../common.dart';
import '../icons.dart';
import '../library/format.dart';
import '../lock/unlock.dart';
import '../routes.dart';

/// Two notes side by side, or two pages of one note
/// (design/screens/Split.png). The pen writes in the focused side.
class SplitScreen extends ConsumerStatefulWidget {
  const SplitScreen({super.key, required this.left, required this.right});

  /// (notebook id, page index) for each side.
  final (String, int) left;
  final (String, int) right;

  @override
  ConsumerState<SplitScreen> createState() => _SplitScreenState();
}

class _SplitScreenState extends ConsumerState<SplitScreen> {
  // Pages start below the pane headers.
  late final _panes = [
    Pane(widget.left.$1, page: widget.left.$2, home: const Offset(0, 56)),
    Pane(widget.right.$1, page: widget.right.$2, home: const Offset(0, 56)),
  ];
  late final AppLifecycleListener _lifecycle;
  final penLink = LayerLink();
  final markerLink = LayerLink();

  /// Which side the pen writes in.
  int _focused = 0;

  /// Left pane's share of the width.
  double _ratio = 0.5;

  /// The right pane's last "other note", for switching back from "Same note".
  String? _otherNote;

  bool _popover = false;
  String? _fly;
  bool _pinned = false;
  bool _more = false;

  Pane get _active => _panes[_focused];

  @override
  void initState() {
    super.initState();
    if (widget.right.$1 != widget.left.$1) _otherNote = widget.right.$1;
    _lifecycle = AppLifecycleListener(onStateChange: (state) {
      if (state == AppLifecycleState.resumed) return;
      for (final id in {for (final p in _panes) p.notebookId}) {
        if (ref.exists(notebookProvider(id))) ref.read(notebookProvider(id).notifier).flush();
      }
    });
    for (final p in _panes) {
      p.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    for (final p in _panes) {
      p.removeListener(_changed);
      p.dispose();
    }
    super.dispose();
  }

  void _changed() {
    setState(() {});
    ref.read(libraryProvider.notifier).recordOpened(_active.notebookId, _active.page);
  }

  void _focus(int i) {
    if (_focused == i) return;
    setState(() {
      _focused = i;
      _popover = false;
    });
  }

  void _comingSoon(String feature) => showComingSoon(context, feature);

  void _closeMenus() => setState(() {
        _fly = null;
        _pinned = false;
        _more = false;
      });

  /// Leaves Split view, keeping [keep]'s side open in the canvas.
  void _closeSplit(int keep) {
    final p = _panes[keep];
    context.pushReplacement(Routes.notebook(p.notebookId, page: p.page));
  }

  void _swap() {
    final a = (_panes[0].notebookId, _panes[0].page);
    final b = (_panes[1].notebookId, _panes[1].page);
    _panes[0].show(b.$1, b.$2);
    _panes[1].show(a.$1, a.$2);
    // Focus follows the content that moved.
    setState(() => _focused = 1 - _focused);
  }

  void _sameNote() {
    final left = _panes[0];
    final right = _panes[1];
    if (right.notebookId == left.notebookId) return;
    _otherNote = right.notebookId;
    final count = ref.read(libraryProvider).byId(left.notebookId)?.pageCount ?? 1;
    right.show(left.notebookId, count > 1 ? (left.page + 1) % count : left.page);
  }

  void _otherNoteShown() {
    final left = _panes[0];
    final lib = ref.read(libraryProvider);
    final other = (_otherNote != null && _otherNote != left.notebookId ? lib.byId(_otherNote!) : null) ??
        lib.recent(except: left.notebookId, count: 1).firstOrNull;
    if (other == null || other.trashed) return;
    _panes[1].show(other.id, other.lastPage);
  }

  void _pickTool(CanvasTool tool) {
    var toggled = false;
    pickCanvasTool(ref, _active, tool, onPopover: () => toggled = true);
    setState(() => _popover = toggled && !_popover);
  }

  void _togglePopover() {
    if (!ref.read(settingsProvider).tool.inks) {
      ref.read(settingsProvider.notifier).apply((s) => s.copyWith(tool: CanvasTool.pen));
    }
    setState(() => _popover = !_popover);
  }

  void _pickRailItem(RailItem item) {
    _closeMenus();
    if (item.label == 'Split view') {
      _closeSplit(_focused);
    } else {
      handleRailItem(context, ref, _active, item, _comingSoon);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final settings = ref.watch(settingsProvider);
    final lib = ref.watch(libraryProvider);
    final blocking = _more || (_pinned && _fly != null);
    final activeTitle = lib.byId(_active.notebookId)?.title ?? '';
    final canOther = lib.active.any((n) => n.id != _panes[0].notebookId);

    void undo(bool redo) {
      if (!ref.exists(notebookProvider(_active.notebookId))) return;
      final n = ref.read(notebookProvider(_active.notebookId).notifier);
      final pageId = ref.read(notebookProvider(_active.notebookId)).pageAt(_active.page).id;
      redo ? n.redo(pageId) : n.undo(pageId);
    }

    return Scaffold(
      backgroundColor: c.side,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () => undo(false),
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): () => undo(true),
          const SingleActivator(LogicalKeyboardKey.keyY, control: true): () => undo(true),
          const SingleActivator(LogicalKeyboardKey.escape): () {
            _closeMenus();
            setState(() => _popover = false);
          },
        },
        child: Focus(
          autofocus: true,
          child: SafeArea(
            child: Stack(children: [
              Positioned(
                left: 84,
                top: 76,
                right: 12,
                bottom: 12,
                child: LayoutBuilder(builder: (context, box) {
                  final leftWidth = (box.maxWidth - 16) * _ratio;
                  return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    SizedBox(
                      width: leftWidth,
                      child: _SplitPane(
                        pane: _panes[0],
                        side: 'Left',
                        focused: _focused == 0,
                        onFocus: () => _focus(0),
                        onClose: () => _closeSplit(1),
                      ),
                    ),
                    _Divider(
                      onSwap: _swap,
                      onDrag: (dx) => setState(() => _ratio = ((leftWidth + dx) / (box.maxWidth - 16)).clamp(0.3, 0.7)),
                    ),
                    Expanded(
                      child: _SplitPane(
                        pane: _panes[1],
                        side: 'Right',
                        focused: _focused == 1,
                        onFocus: () => _focus(1),
                        onClose: () => _closeSplit(0),
                        sameNote: _panes[1].notebookId == _panes[0].notebookId,
                        onSameNote: _sameNote,
                        onOtherNote: canOther ? _otherNoteShown : null,
                      ),
                    ),
                  ]);
                }),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 72,
                child: _ToolsGate(
                  pane: _active,
                  child: (ready) => TopBar(
                    title: _SplitTitle(
                      writingIn: '$activeTitle · page ${_active.page + 1} (${_focused == 0 ? 'left' : 'right'})',
                      onClose: () => _closeSplit(_focused),
                    ),
                    pane: _active,
                    showTools: ready,
                    showActions: ready,
                    showTrayButton: false,
                    popoverOpen: _popover,
                    penLink: penLink,
                    markerLink: markerLink,
                    onPickTool: _pickTool,
                    onTogglePopover: _togglePopover,
                    onToggleTray: () {},
                    moreOpen: _more,
                    onToggleMore: () => setState(() {
                      _more = !_more;
                      _fly = null;
                      _pinned = false;
                      _popover = false;
                    }),
                    onComingSoon: _comingSoon,
                  ),
                ),
              ),
              if (blocking)
                Positioned.fill(
                  child: Listener(behavior: HitTestBehavior.opaque, onPointerDown: (_) => _closeMenus()),
                ),
              Positioned(
                left: 12,
                top: 170,
                child: LeftRail(
                  openId: _fly,
                  pinned: _pinned,
                  onHover: (id) {
                    if (!_pinned) setState(() => _fly = id);
                  },
                  onTap: (id) => setState(() {
                    if (_pinned && _fly == id) {
                      _fly = null;
                      _pinned = false;
                    } else {
                      _fly = id;
                      _pinned = true;
                      _more = false;
                      _popover = false;
                    }
                  }),
                  onLeave: () {
                    if (!_pinned && _fly != null) setState(() => _fly = null);
                  },
                  onClose: _closeMenus,
                  onItem: _pickRailItem,
                  onSearch: () {
                    _closeMenus();
                    _comingSoon('Search');
                  },
                ),
              ),
              if (_more)
                Positioned(
                  right: 12,
                  top: 70,
                  child: MoreMenu(onItem: (item) {
                    _closeMenus();
                    handleMoreItem(context, _active, item, _comingSoon);
                  }),
                ),
              if (_popover)
                Positioned(
                  left: 0,
                  top: 0,
                  child: CompositedTransformFollower(
                    link: settings.tool == CanvasTool.marker ? markerLink : penLink,
                    showWhenUnlinked: false,
                    targetAnchor: Alignment.bottomCenter,
                    offset: const Offset(-51, 13),
                    child: PenPopover(
                      caretLeft: 45,
                      onClose: () => setState(() => _popover = false),
                      onComingSoon: _comingSoon,
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Shows the tools only once the focused pane's notebook is open (they read it).
class _ToolsGate extends ConsumerWidget {
  const _ToolsGate({required this.pane, required this.child});

  final Pane pane;
  final Widget Function(bool ready) child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = ref.watch(loadedNotebookProvider(pane.notebookId));
    var ready = loaded.hasValue;
    if (ready) {
      final nb = ref.watch(notebookProvider(pane.notebookId));
      ready = !nb.isSealed(nb.pageAt(pane.page).id);
    }
    return child(ready);
  }
}

class _SplitTitle extends StatelessWidget {
  const _SplitTitle({required this.writingIn, required this.onClose});

  final String writingIn;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pill(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
      child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
        ChromeButton(label: 'Close split view', icon: EIcons.back, iconSize: 22, onPressed: onClose),
        Flexible(
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              Text('Split view', maxLines: 1, style: TypeScale.pillTitle.copyWith(color: c.text)),
              Semantics(
                liveRegion: true,
                child: Text(
                  'Writing in: $writingIn',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TypeScale.pillSub.copyWith(color: c.textMuted),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.onSwap, required this.onDrag});

  final VoidCallback onSwap;
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget handle() => Semantics(
          label: 'Drag to resize',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
            child: SizedBox(
              width: 16,
              height: 48,
              child: Center(
                child: Container(
                  width: 5,
                  height: 48,
                  decoration: BoxDecoration(color: c.lineDashed, borderRadius: BorderRadius.circular(Radii.chip)),
                ),
              ),
            ),
          ),
        );
    return SizedBox(
      width: 16,
      child: OverflowBox(
        maxWidth: 44,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, spacing: 10, children: [
          handle(),
          Semantics(
            button: true,
            label: 'Swap panes',
            excludeSemantics: true,
            child: Material(
              color: c.surface,
              shape: CircleBorder(side: BorderSide(color: c.line)),
              elevation: 0,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onSwap,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: c.cardShadow),
                  child: Center(child: EIcon(EIcons.swap, size: 18, color: c.text)),
                ),
              ),
            ),
          ),
          handle(),
        ]),
      ),
    );
  }
}

class _SplitPane extends ConsumerWidget {
  const _SplitPane({
    required this.pane,
    required this.side,
    required this.focused,
    required this.onFocus,
    required this.onClose,
    this.sameNote,
    this.onSameNote,
    this.onOtherNote,
  });

  final Pane pane;

  /// "Left" or "Right", for labels.
  final String side;
  final bool focused;
  final VoidCallback onFocus;
  final VoidCallback onClose;

  /// Right pane only: showing the left pane's notebook.
  final bool? sameNote;
  final VoidCallback? onSameNote;
  final VoidCallback? onOtherNote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Semantics(
      container: true,
      label: '$side pane',
      explicitChildNodes: true,
      child: Container(
        decoration: BoxDecoration(
          color: c.bg,
          border: Border.all(color: focused ? c.accent : c.line, width: focused ? 2 : 1),
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        clipBehavior: Clip.antiAlias,
        child: NotebookGate(
          pane: pane,
          compact: true,
          builder: (context) {
            final nb = ref.watch(notebookProvider(pane.notebookId));
            final page = nb.pageAt(pane.page);
            return Stack(fit: StackFit.expand, children: [
              InkCanvas(pane: pane, writable: focused, onActivate: onFocus),
              if (nb.isSealed(page.id))
                Positioned.fill(
                  top: 56,
                  child: LockedOverlay(
                    notebookId: pane.notebookId,
                    pageId: page.id,
                    pageNumber: pane.page + 1,
                    compact: true,
                  ),
                ),
              Positioned(
                left: 0,
                top: 0,
                right: 0,
                child: _PaneHeader(
                  pane: pane,
                  focused: focused,
                  onFocus: onFocus,
                  onClose: onClose,
                  sameNote: sameNote,
                  onSameNote: onSameNote,
                  onOtherNote: onOtherNote,
                  side: side,
                ),
              ),
              Positioned(right: 12, bottom: 12, child: _PageNav(pane: pane, count: nb.pages.length)),
              Positioned(left: 0, right: 0, bottom: 72, child: Center(child: GestureStatus(pane: pane))),
            ]);
          },
        ),
      ),
    );
  }
}

class _PaneHeader extends ConsumerWidget {
  const _PaneHeader({
    required this.pane,
    required this.focused,
    required this.onFocus,
    required this.onClose,
    required this.side,
    this.sameNote,
    this.onSameNote,
    this.onOtherNote,
  });

  final Pane pane;
  final bool focused;
  final VoidCallback onFocus;
  final VoidCallback onClose;
  final String side;
  final bool? sameNote;
  final VoidCallback? onSameNote;
  final VoidCallback? onOtherNote;

  Future<void> _pickNotebook(BuildContext context, WidgetRef ref) async {
    onFocus();
    final c = context.colors;
    final lib = ref.read(libraryProvider);
    final box = context.findRenderObject()! as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final at = box.localToGlobal(const Offset(8, 52), ancestor: overlay);
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
      color: c.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.pill), side: BorderSide(color: c.line)),
      menuPadding: const EdgeInsets.all(8),
      items: [
        for (final n in lib.recent(count: 40))
          PopupMenuItem(
            value: n.id,
            height: 48,
            child: Row(spacing: 10, children: [
              Container(
                width: 8,
                height: 24,
                decoration: BoxDecoration(
                  color: displayInk(lib.coverOf(n), Theme.of(context).brightness),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Text(
                n.title,
                style: TextStyle(fontSize: 15, fontWeight: n.id == pane.notebookId ? FontWeight.w600 : FontWeight.w400, color: c.text),
              ),
            ]),
          ),
      ],
    );
    if (choice == null || choice == pane.notebookId) return;
    pane.show(choice, ref.read(libraryProvider).byId(choice)?.lastPage ?? 0);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final lib = ref.watch(libraryProvider);
    final entry = lib.byId(pane.notebookId);
    final title = entry?.title ?? '';
    final sub = [
      'Page ${pane.page + 1}',
      if (sameNote == true)
        'same notebook'
      else if (sameNote == false && (entry?.folder.isNotEmpty ?? false))
        folderLabel(entry!.folder),
    ].join(' · ');
    return Container(
      height: 56,
      padding: const EdgeInsets.fromLTRB(8, 0, 6, 0),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.94),
        border: Border(bottom: BorderSide(color: c.lineSoft)),
      ),
      child: Row(spacing: 6, children: [
        Expanded(
          child: Semantics(
            button: true,
            selected: focused,
            label: '$title, $sub. ${focused ? 'The pen writes here.' : 'Tap to write here.'} Choose a notebook.',
            excludeSemantics: true,
            child: Builder(
              builder: (context) => InkWell(
                borderRadius: BorderRadius.circular(Radii.key),
                onTap: () => _pickNotebook(context, ref),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(spacing: 8, children: [
                    Container(
                      width: 10,
                      height: 24,
                      decoration: BoxDecoration(
                        color: entry == null ? c.line : displayInk(lib.coverOf(entry), Theme.of(context).brightness),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    Flexible(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
                        Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.textMuted)),
                      ]),
                    ),
                    EIcon(EIcons.chevronDown, size: 16, color: c.text),
                  ]),
                ),
              ),
            ),
          ),
        ),
        if (focused)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: c.accentTint, borderRadius: BorderRadius.circular(Radii.chip)),
            child: Text('Pen writes here', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.accentDeep)),
          ),
        if (sameNote != null)
          Semantics(
            label: 'What to show in this pane',
            container: true,
            explicitChildNodes: true,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: c.side, borderRadius: BorderRadius.circular(Radii.key)),
              child: Row(mainAxisSize: MainAxisSize.min, spacing: 2, children: [
                _Segment(label: 'Same note', selected: sameNote!, onTap: onSameNote),
                _Segment(label: 'Other note', selected: !sameNote!, onTap: onOtherNote),
              ]),
            ),
          ),
        ChromeButton(
          label: 'Close this pane',
          icon: EIcons.close,
          iconSize: 18,
          radius: Radii.key,
          foreground: c.textMuted,
          onPressed: onClose,
        ),
      ]),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      toggled: selected,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.small),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: onTap == null && !selected ? c.textFaint : c.text,
            ),
          ),
        ),
      ),
    );
  }
}

class _PageNav extends StatelessWidget {
  const _PageNav({required this.pane, required this.count});

  final Pane pane;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final page = pane.page.clamp(0, count - 1);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(Radii.button),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, spacing: 2, children: [
        ChromeButton(
          label: 'Previous page',
          icon: EIcons.chevronLeft,
          iconSize: 16,
          height: 38,
          radius: 9,
          enabled: page > 0,
          onPressed: () => pane.goTo(page - 1),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('${page + 1} / $count', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text)),
        ),
        ChromeButton(
          label: 'Next page',
          icon: EIcons.chevronRight,
          iconSize: 16,
          height: 38,
          radius: 9,
          enabled: page < count - 1,
          onPressed: () => pane.goTo(page + 1),
        ),
      ]),
    );
  }
}
