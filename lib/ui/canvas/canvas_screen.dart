import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../canvas/canvas_view.dart';
import '../../canvas/ink_canvas.dart';
import '../../state/notebook.dart';
import '../../state/settings.dart';
import '../common.dart';
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
  'Password protect': 'Password protection',
  'Page & paper': 'Page & paper',
  'Version history': 'Version history',
};

/// The writing canvas (design/screens/Canvas.png and its Canvas-* states).
class CanvasScreen extends ConsumerStatefulWidget {
  const CanvasScreen({super.key, this.hintDuration = const Duration(seconds: 4)});

  final Duration hintDuration;

  @override
  ConsumerState<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends ConsumerState<CanvasScreen> {
  final view = CanvasView();
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

  @override
  void initState() {
    super.initState();
    // Anything unsaved is written as soon as the app leaves the foreground.
    _lifecycle = AppLifecycleListener(onStateChange: (state) {
      if (state != AppLifecycleState.resumed) ref.read(notebookProvider.notifier).flush();
    });
    _showHint(toolHints[ref.read(settingsProvider).tool]);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _hintTimer?.cancel();
    view.dispose();
    super.dispose();
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
    // Tool items will switch the active tool once those tools exist (Phase 3).
    _comingSoon(item.feature);
  }

  void _toggleMore() => setState(() {
        _more = !_more;
        _fly = null;
        _pinned = false;
        _popover = false;
      });

  void _pickMoreItem(MoreItem item) {
    _closeMenus();
    if (item.label == 'Settings') {
      showQuickSettings(context);
    } else {
      _comingSoon(_moreFeatures[item.label] ?? item.label);
    }
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
    final content = ref.read(notebookProvider).page.contentBounds;
    if (content == null) {
      view.reset();
      return;
    }
    final size = view.size;
    // Leave room for the floating chrome.
    view.fit(content.inflate(24), Rect.fromLTRB(90, 90, size.width - 130, size.height - 90));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(notebookProvider.select((s) => s.page.id), (_, _) => view.reset());
    final settings = ref.watch(settingsProvider);
    final notebook = ref.read(notebookProvider.notifier);
    final chrome = !_full;
    final mapShown = chrome && settings.mapOpen;
    final blocking = chrome && (_more || (_pinned && _fly != null));
    final hintShown = _hint != null && !_popover && !blocking;

    return Scaffold(
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): notebook.undo,
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): notebook.redo,
          const SingleActivator(LogicalKeyboardKey.keyY, control: true): notebook.redo,
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
                child: InkCanvas(view: view),
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
                  if (chrome && settings.trayOpen && !_popover)
                    const Positioned(top: 70, left: 0, right: 0, child: Center(child: ColorTray())),
                  if (chrome)
                    Positioned(
                      right: settings.pagesOpen ? 14 : 0,
                      top: 84,
                      child: PagesRail(maxHeight: box.maxHeight - 84 - (mapShown ? 250 : 80)),
                    ),
                  if (hintShown)
                    Positioned(left: 0, right: 0, bottom: 20, child: Center(child: HintPill(text: _hint!))),
                  Positioned(
                    right: 14,
                    bottom: 16,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.end, spacing: 8, children: [
                      if (mapShown) MapPanel(view: view, onHide: () => _setMap(false)),
                      ZoomPill(
                        view: view,
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
                  if (chrome)
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
                  if (chrome && _more) Positioned(right: 12, top: 70, child: MoreMenu(onItem: _pickMoreItem)),
                  if (chrome && _popover)
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
