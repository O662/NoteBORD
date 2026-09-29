import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../canvas/ink_canvas.dart';
import '../../canvas/pane.dart';
import '../../library/library.dart';
import '../../state/notebook.dart';
import '../../state/settings.dart';
import '../common.dart';
import '../dialogs.dart';
import '../lock/lock_dialog.dart';
import '../lock/unlock.dart';
import '../routes.dart';
import '../templates/templates_dialog.dart';
import 'color_tray.dart';
import 'left_rail.dart';
import 'panels.dart';
import 'pen_popover.dart';
import 'top_bar.dart';

const toolHints = {
  CanvasTool.pen: 'Tap the pen again for colors and thickness',
  CanvasTool.marker: 'Tap the marker again for colors and thickness',
  CanvasTool.eraser: 'Erase whole strokes · hold the S Pen button to erase from any tool',
};

/// What the ⋯ menu items open, until their screens exist.
const _moreFeatures = {
  'Export': 'Export',
  'Import': 'Import',
  'Print': 'Printing',
  'Page & paper': 'Page & paper',
  'Version history': 'Version history',
};

/// Handles a ⋯ menu choice for [pane] (shared with Split view).
void handleMoreItem(BuildContext context, Pane pane, MoreItem item, ValueChanged<String> comingSoon) {
  switch (item.label) {
    case 'Settings':
      showQuickSettings(context);
    case 'Password protect':
      showLockDialog(context, pane);
    default:
      comingSoon(_moreFeatures[item.label] ?? item.label);
  }
}

/// Handles a rail menu choice for [pane] (shared with Split view).
void handleRailItem(BuildContext context, WidgetRef ref, Pane pane, RailItem item, ValueChanged<String> comingSoon) {
  switch (item.label) {
    case 'Templates':
      showTemplatesDialog(context, pane: pane);
    case 'Split view':
      openSplitView(context, ref, pane);
    default:
      // Tool items will switch the active tool once those tools exist (Phase 3).
      comingSoon(item.feature);
  }
}

/// Opens Split view with [pane] on the left and, on the right, the most
/// recently edited other notebook (or the next page of this one).
void openSplitView(BuildContext context, WidgetRef ref, Pane pane) {
  final library = ref.read(libraryProvider);
  final other = library.recent(except: pane.notebookId, count: 1).firstOrNull;
  final nb = ref.read(notebookProvider(pane.notebookId));
  final right = other == null
      ? (pane.notebookId, (pane.page + 1) % nb.pages.length)
      : (other.id, other.lastPage);
  context.pushReplacement(Routes.split((pane.notebookId, pane.page), right));
}

/// Renames the notebook shown in [pane].
Future<void> renameNotebook(BuildContext context, WidgetRef ref, String notebookId) async {
  final current = ref.read(libraryProvider).byId(notebookId)?.title ?? '';
  final name = await showNamePrompt(context, title: 'Rename notebook', initial: current, action: 'Rename');
  if (name != null) await ref.read(libraryProvider.notifier).rename(notebookId, name);
}

/// The writing canvas (design/screens/Canvas.png and its Canvas-* states).
class CanvasScreen extends ConsumerStatefulWidget {
  const CanvasScreen({super.key, required this.pane, this.hintDuration = const Duration(seconds: 4)});

  final Pane pane;
  final Duration hintDuration;

  @override
  ConsumerState<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends ConsumerState<CanvasScreen> {
  final penLink = LayerLink();
  final markerLink = LayerLink();
  late final AppLifecycleListener _lifecycle;
  bool _popover = false;
  String? _hint;
  Timer? _hintTimer;

  /// Open rail menu, and whether it was pinned by a tap (vs. hover preview).
  String? _fly;
  bool _pinned = false;
  bool _more = false;

  /// Full screen hides every menu except the zoom pill.
  bool _full = false;

  Pane get pane => widget.pane;

  @override
  void initState() {
    super.initState();
    // Anything unsaved is written as soon as the app leaves the foreground.
    _lifecycle = AppLifecycleListener(onStateChange: (state) {
      if (state != AppLifecycleState.resumed) ref.read(notebookProvider(pane.notebookId).notifier).flush();
    });
    pane.addListener(_paneChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _recordOpened());
    _showHint(toolHints[ref.read(settingsProvider).tool]);
  }

  @override
  void dispose() {
    pane.removeListener(_paneChanged);
    _lifecycle.dispose();
    _hintTimer?.cancel();
    super.dispose();
  }

  void _paneChanged() {
    setState(() {});
    _recordOpened();
  }

  void _recordOpened() {
    if (mounted) ref.read(libraryProvider.notifier).recordOpened(pane.notebookId, pane.page);
  }

  void _showHint(String? text) {
    _hintTimer?.cancel();
    setState(() => _hint = text);
    if (text != null) _hintTimer = Timer(widget.hintDuration, () => setState(() => _hint = null));
  }

  void _comingSoon(String feature) {
    _hintTimer?.cancel();
    setState(() => _hint = null);
    showComingSoon(context, feature);
  }

  void _closeMenus() => setState(() {
        _fly = null;
        _pinned = false;
        _more = false;
      });

  void _pickTool(CanvasTool tool) {
    final s = ref.read(settingsProvider);
    if (s.tool == tool && tool != CanvasTool.eraser) {
      setState(() => _popover = !_popover);
      return;
    }
    ref.read(settingsProvider.notifier).apply((s) => s.copyWith(tool: tool));
    setState(() => _popover = false);
    _showHint(toolHints[tool]);
  }

  void _togglePopover() {
    final settings = ref.read(settingsProvider.notifier);
    if (ref.read(settingsProvider).tool == CanvasTool.eraser) {
      settings.apply((s) => s.copyWith(tool: CanvasTool.pen));
    }
    setState(() => _popover = !_popover);
  }

  void _toggleTray() {
    ref.read(settingsProvider.notifier).apply((s) => s.copyWith(trayOpen: !s.trayOpen));
    setState(() => _popover = false);
  }

  // Rail menus: hover previews, tap pins.
  void _hoverGroup(String id) {
    if (!_pinned) setState(() => _fly = id);
    if (_more) setState(() => _more = false);
  }

  void _tapGroup(String id) => setState(() {
        if (_pinned && _fly == id) {
          _fly = null;
          _pinned = false;
        } else {
          _fly = id;
          _pinned = true;
          _more = false;
          _popover = false;
        }
      });

  void _leaveRail() {
    if (!_pinned && _fly != null) setState(() => _fly = null);
  }

  void _pickRailItem(RailItem item) {
    _closeMenus();
    handleRailItem(context, ref, pane, item, _comingSoon);
  }

  void _toggleMore() => setState(() {
        _more = !_more;
        _fly = null;
        _pinned = false;
        _popover = false;
      });

  void _pickMoreItem(MoreItem item) {
    _closeMenus();
    handleMoreItem(context, pane, item, _comingSoon);
  }

  void _toggleFull() => setState(() {
        _full = !_full;
        _fly = null;
        _pinned = false;
        _more = false;
        _popover = false;
      });

  void _setMap(bool open) {
    if (open && _full) setState(() => _full = false);
    ref.read(settingsProvider.notifier).apply((s) => s.copyWith(mapOpen: open));
  }

  void _fit() {
    final content = ref.read(notebookProvider(pane.notebookId)).pageAt(pane.page).contentBounds;
    final view = pane.view;
    if (content == null) {
      view.reset();
      return;
    }
    final size = view.size;
    // Leave room for the floating chrome.
    view.fit(content.inflate(24), Rect.fromLTRB(90, 90, size.width - 130, size.height - 90));
  }

  void _back() => leaveNotebook(context);

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final nb = ref.watch(notebookProvider(pane.notebookId));
    final notebook = ref.read(notebookProvider(pane.notebookId).notifier);
    final pageId = nb.pageAt(pane.page).id;
    final sealed = nb.isSealed(pageId);
    final chrome = !_full;
    final tools = chrome && !sealed;
    final mapShown = tools && settings.mapOpen;
    final blocking = tools && (_more || (_pinned && _fly != null));
    final hintShown = !sealed && _hint != null && !_popover && !blocking;

    return Scaffold(
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () => notebook.undo(pageId),
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): () => notebook.redo(pageId),
          const SingleActivator(LogicalKeyboardKey.keyY, control: true): () => notebook.redo(pageId),
          const SingleActivator(LogicalKeyboardKey.escape): () {
            _closeMenus();
            setState(() => _popover = false);
          },
        },
        child: Focus(
          autofocus: true,
          child: Stack(children: [
            Positioned.fill(
              child: Listener(
                onPointerDown: (_) {
                  if (_popover) setState(() => _popover = false);
                },
                child: InkCanvas(pane: pane),
              ),
            ),
            if (sealed)
              Positioned.fill(
                child: LockedOverlay(
                  notebookId: pane.notebookId,
                  pageId: pageId,
                  pageNumber: pane.page + 1,
                  onBack: _back,
                ),
              ),
            SafeArea(
              child: LayoutBuilder(builder: (context, box) {
                return Stack(clipBehavior: Clip.none, children: [
                  if (chrome)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 72,
                      child: TopBar(
                        title: TitlePill(
                          pane: pane,
                          onBack: _back,
                          onRename: () => renameNotebook(context, ref, pane.notebookId),
                        ),
                        pane: pane,
                        showTools: tools,
                        showActions: tools,
                        popoverOpen: _popover,
                        penLink: penLink,
                        markerLink: markerLink,
                        onPickTool: _pickTool,
                        onTogglePopover: _togglePopover,
                        onToggleTray: _toggleTray,
                        moreOpen: _more,
                        onToggleMore: _toggleMore,
                        onComingSoon: _comingSoon,
                      ),
                    ),
                  if (tools && settings.trayOpen && !_popover)
                    const Positioned(top: 70, left: 0, right: 0, child: Center(child: ColorTray())),
                  if (chrome)
                    Positioned(
                      right: settings.pagesOpen ? 14 : 0,
                      top: 84,
                      child: PagesRail(pane: pane, maxHeight: box.maxHeight - 84 - (mapShown ? 250 : 80)),
                    ),
                  if (hintShown)
                    Positioned(left: 0, right: 0, bottom: 20, child: Center(child: HintPill(text: _hint!))),
                  if (!sealed)
                    Positioned(
                      right: 14,
                      bottom: 16,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.end, spacing: 8, children: [
                        if (mapShown) MapPanel(pane: pane, onHide: () => _setMap(false)),
                        ZoomPill(
                          view: pane.view,
                          onFit: _fit,
                          showMapButton: !mapShown,
                          onShowMap: () => _setMap(true),
                          fullScreen: _full,
                          onToggleFullScreen: _toggleFull,
                        ),
                      ]),
                    ),
                  // A pinned menu or ⋯ stays open until a tap anywhere else.
                  if (blocking)
                    Positioned.fill(
                      child: Listener(behavior: HitTestBehavior.opaque, onPointerDown: (_) => _closeMenus()),
                    ),
                  if (tools)
                    Positioned(
                      left: 12,
                      top: 84,
                      child: LeftRail(
                        openId: _fly,
                        pinned: _pinned,
                        onHover: _hoverGroup,
                        onTap: _tapGroup,
                        onLeave: _leaveRail,
                        onClose: _closeMenus,
                        onItem: _pickRailItem,
                        onSearch: () {
                          _closeMenus();
                          _comingSoon('Search');
                        },
                      ),
                    ),
                  if (tools && _more) Positioned(right: 12, top: 70, child: MoreMenu(onItem: _pickMoreItem)),
                  if (tools && _popover)
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
                ]);
              }),
            ),
          ]),
        ),
      ),
    );
  }
}
