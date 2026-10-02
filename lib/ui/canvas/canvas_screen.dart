import 'dart:async';
import 'dart:math' as math;

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
import '../transfer/share_dialog.dart';
import '../transfer/transfer_dialog.dart';
import '../../canvas/selection.dart';
import 'color_tray.dart';
import 'gesture_status.dart';
import 'insert_actions.dart';
import 'insert_menu.dart';
import 'left_rail.dart';
import 'panels.dart';
import 'pen_popover.dart';
import 'top_bar.dart';

const toolHints = {
  CanvasTool.pen: 'Tap the pen again for colors and thickness',
  CanvasTool.marker: 'Tap the marker again for colors and thickness',
  CanvasTool.eraser: 'Erase whole strokes · hold the S Pen button to erase from any tool',
  CanvasTool.select: 'Tap anything to select it · drag to move · pinch to resize',
  CanvasTool.lasso: 'Circle ink, shapes or stickies to select them together',
  CanvasTool.laser: 'Laser fades after a second · it’s never saved to the page',
  ...placeHints,
};

const boardHint = 'The whole board · tap anywhere to zoom in there';

const rulerHint = 'Two fingers rotate the ruler · the pen snaps to its edge';

/// What the ⋯ menu items open, until their screens exist.
const _moreFeatures = {
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
    case 'Export':
      showTransferDialog(context, pane: pane);
    case 'Import':
      showTransferDialog(context, pane: pane, mode: TransferMode.import);
    case 'Print':
      printNotebook(context, pane);
    default:
      comingSoon(_moreFeatures[item.label] ?? item.label);
  }
}

/// Handles a rail menu choice for [pane] (shared with Split view). [hint]
/// shows a tool's hint where the screen has one.
void handleRailItem(
  BuildContext context,
  WidgetRef ref,
  Pane pane,
  RailItem item,
  ValueChanged<String> comingSoon, {
  ValueChanged<String>? hint,
}) {
  final settings = ref.read(settingsProvider.notifier);
  void useTool(CanvasTool tool) => settings.apply((s) => s.copyWith(tool: tool));
  switch (item.label) {
    case 'Sticky note':
      runInsert(context, ref, pane, InsertAction.sticky, hint: hint);
    case 'Paper frame':
      runInsert(context, ref, pane, InsertAction.frame, hint: hint);
    case 'Image':
      runInsert(context, ref, pane, InsertAction.image, hint: hint);
    case 'Record audio':
      // Audio comes with a later phase: the same card as in the Insert menu.
      showEntryComingSoon(context, insertSections[1].entries.firstWhere((e) => e.label == 'Audio'));
    case 'Everything else':
      showInsertMenu(context).then((action) {
        if (action != null && context.mounted) runInsert(context, ref, pane, action, hint: hint);
      });
    case 'Templates':
      showTemplatesDialog(context, pane: pane);
    case 'Split view':
      openSplitView(context, ref, pane);
    case 'Ruler':
      // Picking it again puts it away.
      if (pane.ruler.visible) {
        pane.ruler.hide();
        return;
      }
      pane.ruler.show(pane.view.size);
      if (!ref.read(settingsProvider).tool.inks) useTool(CanvasTool.pen);
      hint?.call(rulerHint);
    case 'Laser pointer':
      useTool(CanvasTool.laser);
      hint?.call(toolHints[CanvasTool.laser]!);
    case 'Need to remember' || 'Convert to text':
      // Until their own screens exist, both start a lasso whose toolbar
      // leads with that action (RememberMark.png, Convert.png).
      final convert = item.label == 'Convert to text';
      pane.selection.menu = convert ? SelectionMenu.convert : SelectionMenu.remember;
      useTool(CanvasTool.lasso);
      hint?.call(convert ? 'Circle the handwriting to convert' : 'Circle what you need to remember');
    default:
      comingSoon(item.feature);
  }
}

/// Picks a tool from the tool pill. Tapping the active pen or marker again
/// calls [onPopover] instead; Select and Lasso lead with Convert to text.
void pickCanvasTool(WidgetRef ref, Pane pane, CanvasTool tool, {required VoidCallback onPopover}) {
  if (ref.read(settingsProvider).tool == tool && tool.inks) {
    onPopover();
    return;
  }
  if (tool.selects) pane.selection.menu = SelectionMenu.convert;
  ref.read(settingsProvider.notifier).apply((s) => s.copyWith(tool: tool));
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

class _CanvasScreenState extends ConsumerState<CanvasScreen> with SingleTickerProviderStateMixin {
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

  /// The whole board is showing (design/screens/Board.png): everything on
  /// the page at once, no menus. A tap zooms in there.
  bool _board = false;

  /// The zoom and pan to go back to from the whole board.
  (double, Offset)? _before;

  /// Glides the view to a zoom and place.
  late final AnimationController _glide;
  void Function(double t)? _glideStep;

  Pane get pane => widget.pane;

  @override
  void initState() {
    super.initState();
    _glide = AnimationController(vsync: this, duration: const Duration(milliseconds: 280))
      ..addListener(() => _glideStep?.call(Curves.easeInOutCubic.transform(_glide.value)));
    // Anything unsaved is written as soon as the app leaves the foreground.
    _lifecycle = AppLifecycleListener(onStateChange: (state) {
      if (state == AppLifecycleState.resumed) return;
      // Text still being typed goes on the page first.
      if (state != AppLifecycleState.inactive) pane.dismiss();
      ref.read(notebookProvider(pane.notebookId).notifier).flush();
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
    _glide.dispose();
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
    var toggled = false;
    pickCanvasTool(ref, pane, tool, onPopover: () => toggled = true);
    if (toggled) {
      setState(() => _popover = !_popover);
      return;
    }
    setState(() => _popover = false);
    _showHint(toolHints[tool]);
  }

  void _togglePopover() {
    final settings = ref.read(settingsProvider.notifier);
    if (!ref.read(settingsProvider).tool.inks) {
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
    handleRailItem(context, ref, pane, item, _comingSoon, hint: _showHint);
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

  /// Glides from the current zoom and pan to [scale] and [translation].
  void _glideTo(double scale, Offset translation) {
    final view = pane.view;
    final mid = view.size.center(Offset.zero);
    final s0 = view.scale;
    final c0 = view.toPage(mid), c1 = (mid - translation) / scale;
    _glideStep = (t) {
      final s = s0 * math.pow(scale / s0, t);
      view.jumpTo(s, mid - Offset.lerp(c0, c1, t)! * s);
    };
    _glide
      ..stop()
      ..value = 0
      ..forward();
  }

  /// The zoom pill's "whole board" button: everything on the page at once,
  /// or back to where you were.
  void _toggleBoard() {
    if (_board) {
      _leaveBoard();
      return;
    }
    final content = ref.read(notebookProvider(pane.notebookId)).pageAt(pane.page).contentBounds;
    final view = pane.view;
    if (content == null) {
      view.reset();
      _showHint('Nothing on this page yet');
      return;
    }
    _before = (view.scale, view.translation);
    pane
      ..dismiss()
      ..selection.clear();
    setState(() {
      _board = true;
      _fly = null;
      _pinned = false;
      _more = false;
      _popover = false;
    });
    final size = view.size;
    // The menus are hidden, so the board gets the whole screen (Board.png).
    final fit = view.fitted(content.inflate(32), Rect.fromLTRB(36, 56, size.width - 36, size.height - 72));
    if (fit != null) _glideTo(fit.$1, fit.$2);
    _showHint(boardHint);
  }

  /// Leaves the whole board: back to the zoom you had, at the same place
  /// or, after a tap, centered [at] that page point.
  void _leaveBoard({Offset? at}) {
    if (!_board) return;
    final view = pane.view;
    final (scale, translation) = _before ?? (1.0, view.home);
    setState(() => _board = false);
    _glideTo(scale, at == null ? translation : view.size.center(Offset.zero) - at * scale);
    _showHint(toolHints[ref.read(settingsProvider).tool]);
  }

  void _back() => leaveNotebook(context);

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final nb = ref.watch(notebookProvider(pane.notebookId));
    final notebook = ref.read(notebookProvider(pane.notebookId).notifier);
    final pageId = nb.pageAt(pane.page).id;
    final sealed = nb.isSealed(pageId);
    if (sealed && _board) _board = false;
    final chrome = !_full && !_board;
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
            pane
              ..dismiss()
              ..selection.clear();
            _leaveBoard();
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
                  _glide.stop(); // a touch takes over from a glide
                },
                child: InkCanvas(
                  pane: pane,
                  onBoardTap: _board ? (at) => _leaveBoard(at: at) : null,
                  // Clear of the rail, the top pills (and the color tray), and the pages rail.
                  chrome: EdgeInsets.fromLTRB(
                    80,
                    tools && (settings.trayOpen || settings.tool == CanvasTool.laser || settings.tool == CanvasTool.shape)
                        ? 128
                        : 84,
                    chrome && settings.pagesOpen ? 124 : 60,
                    16,
                  ),
                ),
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
                        onShare: () => showShareDialog(context, pane),
                      ),
                    ),
                  if (tools && settings.tool == CanvasTool.laser && !_popover)
                    const Positioned(top: 74, left: 0, right: 0, child: Center(child: LaserColors()))
                  else if (tools && settings.tool == CanvasTool.shape && !_popover)
                    const Positioned(top: 74, left: 0, right: 0, child: Center(child: ShapeKinds()))
                  else if (tools && settings.trayOpen && !_popover)
                    const Positioned(top: 70, left: 0, right: 0, child: Center(child: ColorTray())),
                  if (chrome)
                    Positioned(
                      right: settings.pagesOpen ? 14 : 0,
                      top: 84,
                      child: PagesRail(pane: pane, maxHeight: box.maxHeight - 84 - (mapShown ? 250 : 80)),
                    ),
                  if (!sealed && !blocking)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 20,
                      child: Center(
                        child: GestureStatus(pane: pane, orElse: hintShown ? HintPill(text: _hint!) : null),
                      ),
                    ),
                  if (!sealed)
                    Positioned(
                      right: 14,
                      bottom: 16,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.end, spacing: 8, children: [
                        if (mapShown) MapPanel(pane: pane, onHide: () => _setMap(false)),
                        ZoomPill(
                          view: pane.view,
                          onFit: _toggleBoard,
                          board: _board,
                          showMapButton: !mapShown && !_board,
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
