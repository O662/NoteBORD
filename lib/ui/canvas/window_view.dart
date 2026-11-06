import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../board/model.dart' show Json;
import '../../canvas/ink_canvas.dart';
import '../../canvas/pane.dart';
import '../../library/library.dart';
import '../../state/notebook.dart';
import '../../state/settings.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart' show Radii;
import '../common.dart';
import '../dialogs.dart';
import '../icons.dart';
import '../routes.dart';
import 'page_bar.dart' show pageTitle;

/// The window view's place and look (Window.dc.html `win…`), saved per
/// notebook on this tablet (Settings' prefs, `window:<notebook id>`).
@immutable
class WindowSpot {
  const WindowSpot({
    this.open = false,
    this.bubble = false,
    this.rect = const Rect.fromLTWH(452, 286, 470, 330),
    this.opacity = 0.88,
    this.pinned = false,
    this.penHere = false,
    required this.notebookId,
    required this.page,
    this.scale = 1,
    this.pan = Offset.zero,
  });

  static const minSize = Size(340, 200);
  static const maxSize = Size(960, 700);
  static const minZoom = 0.5;
  static const maxZoom = 2.0;

  /// At least this much of the window stays on screen.
  static const keepOnScreen = 120.0;

  final bool open;

  /// Shrunk to a bubble with the note's title, where the window was.
  final bool bubble;
  final Rect rect;

  /// The window's paper and ink (25–100%); its bars stay solid.
  final double opacity;

  /// Locked in place: the title bar doesn't move it.
  final bool pinned;

  /// Pen: window. The S Pen writes in the window, not on the page.
  final bool penHere;

  /// What it shows: a page of a notebook, and where it's panned and zoomed.
  final String notebookId;
  final int page;
  final double scale;
  final Offset pan;

  WindowSpot copyWith({
    bool? open,
    bool? bubble,
    Rect? rect,
    double? opacity,
    bool? pinned,
    bool? penHere,
    String? notebookId,
    int? page,
    double? scale,
    Offset? pan,
  }) => WindowSpot(
    open: open ?? this.open,
    bubble: bubble ?? this.bubble,
    rect: rect ?? this.rect,
    opacity: opacity ?? this.opacity,
    pinned: pinned ?? this.pinned,
    penHere: penHere ?? this.penHere,
    notebookId: notebookId ?? this.notebookId,
    page: page ?? this.page,
    scale: scale ?? this.scale,
    pan: pan ?? this.pan,
  );

  Json toJson() => {
    'open': open,
    'bubble': bubble,
    'rect': [rect.left, rect.top, rect.width, rect.height].map((v) => (v * 10).round() / 10).toList(),
    'opacity': opacity,
    'pinned': pinned,
    'penHere': penHere,
    'notebook': notebookId,
    'page': page,
    'scale': scale,
    'pan': [pan.dx.round(), pan.dy.round()],
  };

  static WindowSpot? fromJson(Object? j, {required String fallbackNotebook}) {
    if (j is! Map) return null;
    double n(Object? v, double d) => (v as num?)?.toDouble() ?? d;
    final r = j['rect'] is List && (j['rect'] as List).length == 4 ? (j['rect'] as List) : null;
    final p = j['pan'] is List && (j['pan'] as List).length == 2 ? (j['pan'] as List) : null;
    return WindowSpot(
      open: j['open'] == true,
      bubble: j['bubble'] == true,
      rect: r == null ? const Rect.fromLTWH(452, 286, 470, 330) : Rect.fromLTWH(n(r[0], 452), n(r[1], 286), n(r[2], 470), n(r[3], 330)),
      opacity: n(j['opacity'], 0.88).clamp(0.25, 1.0),
      pinned: j['pinned'] == true,
      penHere: j['penHere'] == true,
      notebookId: j['notebook'] as String? ?? fallbackNotebook,
      page: (j['page'] as num?)?.toInt() ?? 0,
      scale: n(j['scale'], 1).clamp(minZoom, maxZoom),
      pan: p == null ? Offset.zero : Offset(n(p[0], 0), n(p[1], 0)),
    );
  }

  /// [r] kept within the sizes allowed, and on [screen] by at least
  /// [keepOnScreen] (the title bar always reachable).
  static Rect fit(Rect r, Size screen) {
    final w = r.width.clamp(minSize.width, maxSize.width);
    final h = r.height.clamp(minSize.height, maxSize.height);
    final x = r.left.clamp(keepOnScreen - w, math.max(keepOnScreen - w, screen.width - keepOnScreen)).toDouble();
    final y = r.top.clamp(0.0, math.max(0.0, screen.height - 46)).toDouble();
    return Rect.fromLTWH(x, y, w.toDouble(), h.toDouble());
  }
}

String _key(String notebookId) => 'window:$notebookId';

/// The window view of the notebook shown in [main]: its state, the pane it
/// shows, and saving both.
class WindowController extends ChangeNotifier {
  WindowController(this.ref, this.main) {
    final saved = WindowSpot.fromJson(ref.read(settingsProvider).prefs[_key(main.notebookId)], fallbackNotebook: main.notebookId);
    _spot = saved ?? _fresh();
    pane = Pane(_spot.notebookId, page: _spot.page);
    pane.view.jumpTo(_spot.scale, _spot.pan);
    pane.view.addListener(_viewChanged);
  }

  final WidgetRef ref;
  final Pane main;
  late final Pane pane;
  late WindowSpot _spot;
  Timer? _save;

  WindowSpot get spot => _spot;

  /// A new window shows the next page of this notebook (or another spot on
  /// this one, for a notebook of one page).
  WindowSpot _fresh() {
    final n = ref.read(notebookProvider(main.notebookId)).pages.length;
    return WindowSpot(notebookId: main.notebookId, page: n > 1 ? (main.page + 1) % n : main.page);
  }

  void _viewChanged() {
    final v = pane.view;
    // Pinching inside zooms 50–200%.
    final s = v.scale.clamp(WindowSpot.minZoom, WindowSpot.maxZoom);
    if (s != v.scale) {
      final mid = v.size.center(Offset.zero);
      v.jumpTo(s, mid - v.toPage(mid) * s);
      return;
    }
    _set(_spot.copyWith(scale: v.scale, pan: v.translation), notify: false);
  }

  void _set(WindowSpot s, {bool notify = true}) {
    _spot = s;
    if (notify) notifyListeners();
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 400), _write);
  }

  void _write() {
    final s = _spot;
    ref.read(settingsProvider.notifier).apply((st) => st.withPref(_key(main.notebookId), s.toJson()));
  }

  void toggle() => _set(_spot.copyWith(open: !_spot.open || _spot.bubble, bubble: false));
  void close() => _set(_spot.copyWith(open: false, bubble: false, penHere: false));
  void shrink() => _set(_spot.copyWith(bubble: true, penHere: false));
  void restore() => _set(_spot.copyWith(bubble: false));
  void togglePin() => _set(_spot.copyWith(pinned: !_spot.pinned));
  void togglePen() => _set(_spot.copyWith(penHere: !_spot.penHere));
  void penToPage() {
    if (_spot.penHere) _set(_spot.copyWith(penHere: false));
  }

  void setOpacity(double v) => _set(_spot.copyWith(opacity: (v * 20).round() / 20));
  void moveTo(Rect r) => _set(_spot.copyWith(rect: r));

  /// − and +: by 25%, about the middle of the window.
  void zoomBy(double step) {
    final v = pane.view;
    final s = ((v.scale + step) * 4).round() / 4;
    final to = s.clamp(WindowSpot.minZoom, WindowSpot.maxZoom).toDouble();
    final mid = v.size.isEmpty ? Offset.zero : v.size.center(Offset.zero);
    v.jumpTo(to, mid - v.toPage(mid) * to);
  }

  /// Shows page [page] of [notebookId] (a different spot of this page keeps
  /// where it was panned to).
  void show(String notebookId, int page) {
    if (notebookId == pane.notebookId && page == pane.page) return;
    pane.show(notebookId, page);
    _set(_spot.copyWith(notebookId: notebookId, page: page, scale: 1, pan: pane.view.translation));
  }

  /// Swaps what's in the window with the main view.
  void swap() {
    final (mainNb, mainPage, mainScale, mainPan) = (main.notebookId, main.page, main.view.scale, main.view.translation);
    final (winNb, winPage, winScale, winPan) = (pane.notebookId, pane.page, pane.view.scale, pane.view.translation);
    main.show(winNb, winPage);
    main.view.jumpTo(winScale, winPan);
    pane.show(mainNb, mainPage);
    pane.view.jumpTo(mainScale, mainPan);
    _set(_spot.copyWith(notebookId: mainNb, page: mainPage, scale: mainScale, pan: mainPan));
  }

  @override
  void dispose() {
    if (_save?.isActive ?? false) {
      _save!.cancel();
      _write();
    }
    pane.view.removeListener(_viewChanged);
    pane.dispose();
    super.dispose();
  }
}

/// The floating window (Window.png): a title bar to drag (⋮⋮), what it
/// shows (tap to pick), swap, split view, lock, shrink and close; the page,
/// faded; and a footer with opacity, zoom and Pen: page / window. The dark
/// corner resizes it. Shrunk, it's a bubble with the note's title.
class WindowView extends ConsumerStatefulWidget {
  const WindowView({super.key, required this.controller, required this.screen});

  final WindowController controller;

  /// The area it moves in.
  final Size screen;

  @override
  ConsumerState<WindowView> createState() => _WindowViewState();
}

class _WindowViewState extends ConsumerState<WindowView> {
  bool _picking = false;
  Offset? _dragFrom;
  Rect? _dragRect;

  WindowController get w => widget.controller;

  void _startDrag(Offset at) {
    if (w.spot.pinned) return;
    _dragFrom = at;
    _dragRect = w.spot.rect;
  }

  void _drag(Offset at) {
    final from = _dragFrom, r = _dragRect;
    if (from == null || r == null) return;
    w.moveTo(WindowSpot.fit(r.shift(at - from), widget.screen));
  }

  void _resize(Offset delta) {
    final r = w.spot.rect;
    w.moveTo(WindowSpot.fit(Rect.fromLTWH(r.left, r.top, r.width + delta.dx, r.height + delta.dy), widget.screen));
  }

  String _sub(LibraryState lib, String mainNotebook, int mainPage) {
    final p = w.pane;
    if (p.notebookId == mainNotebook) {
      return p.page == mainPage ? 'This page · another spot' : 'This notebook · page ${p.page + 1}';
    }
    return 'Another note · page ${p.page + 1}';
  }

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: Listenable.merge([w, w.pane, w.pane.view, w.main]), builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final c = context.colors;
    final spot = w.spot;
    // Always a positioned child: an unpositioned one would size the Stack.
    if (!spot.open) return const Positioned(left: 0, top: 0, child: SizedBox.shrink());
    final lib = ref.watch(libraryProvider);
    final entry = lib.byId(w.pane.notebookId);
    final rect = WindowSpot.fit(spot.rect, widget.screen);
    final title = _title(ref);
    final spine = entry == null ? c.line : displayInk(lib.coverOf(entry), Theme.of(context).brightness);

    if (spot.bubble) {
      return Positioned(
        left: rect.left.clamp(0.0, math.max(0.0, widget.screen.width - 200)),
        top: rect.top,
        child: Semantics(
          button: true,
          label: 'Open window: $title',
          excludeSemantics: true,
          child: Material(
            color: c.inverse,
            shape: const StadiumBorder(),
            elevation: 0,
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: w.restore,
              child: Container(
                height: 44,
                padding: const EdgeInsets.only(left: 10, right: 14),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.chip), boxShadow: c.menuShadow),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 8,
                  children: [
                    EIcon(EIcons.windowView, size: 18, color: c.onInverse),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.onInverse),
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

    Widget bar(String label, EIconData icon, VoidCallback onTap, {bool on = false}) =>
        ChromeButton(label: label, icon: icon, width: 38, height: 38, radius: Radii.key, iconSize: 18, selected: on, onPressed: onTap);

    final titleBar = GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Moves from where it was touched, not from past the drag slop.
      dragStartBehavior: DragStartBehavior.down,
      onPanStart: (d) => _startDrag(d.globalPosition),
      onPanUpdate: (d) => _drag(d.globalPosition),
      onPanEnd: (_) => _dragFrom = null,
      child: Container(
        height: 46,
        padding: const EdgeInsets.only(left: 6, right: 4),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.pill)),
          border: Border(bottom: BorderSide(color: c.lineSoft)),
        ),
        child: Row(
          spacing: 2,
          children: [
            SizedBox(
              width: 22,
              child: Center(child: EIcon(EIcons.grip, size: 20, color: c.textFaint)),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  button: true,
                  expanded: _picking,
                  label: 'Show in the window: $title',
                  excludeSemantics: true,
                  child: Material(
                    color: _picking ? c.side : Colors.transparent,
                    borderRadius: BorderRadius.circular(Radii.key),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Radii.key),
                      onTap: () => setState(() => _picking = !_picking),
                      child: Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 8,
                          children: [
                            Container(
                              width: 5,
                              height: 20,
                              decoration: BoxDecoration(color: spine, borderRadius: BorderRadius.circular(2)),
                            ),
                            Flexible(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.15, color: c.text),
                                  ),
                                  Text(
                                    _sub(lib, w.main.notebookId, w.main.page),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11, height: 1.15, color: c.textMuted),
                                  ),
                                ],
                              ),
                            ),
                            EIcon(EIcons.chevronDown, size: 14, color: c.textMuted),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            bar('Show this in the main view', EIcons.windowSwap, () {
              setState(() => _picking = false);
              w.swap();
            }),
            bar('Open as split view', EIcons.split, () {
              final left = (w.main.notebookId, w.main.page), right = (w.pane.notebookId, w.pane.page);
              w.close();
              context.pushReplacement(Routes.split(left, right));
            }),
            bar(spot.pinned ? 'Unlock position' : 'Lock position', EIcons.pin, w.togglePin, on: spot.pinned),
            bar('Shrink to a bubble', EIcons.minus, () {
              setState(() => _picking = false);
              w.shrink();
            }),
            bar('Close window', EIcons.close, w.close),
          ],
        ),
      ),
    );

    final page = ClipRect(
      child: Semantics(
        label: 'Window content. Drag with a finger to move around, pinch or use + and − to zoom',
        container: true,
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: spot.opacity,
                child: NotebookGate(
                  pane: w.pane,
                  compact: true,
                  builder: (context) => InkCanvas(pane: w.pane, writable: spot.penHere, chrome: const EdgeInsets.all(8)),
                ),
              ),
            ),
            if (spot.penHere)
              Positioned(
                left: 10,
                top: 10,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(Radii.chip)),
                    child: Text(
                      'Pen writes here',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.onAccent),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    final footer = Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(Radii.pill)),
        border: Border(top: BorderSide(color: c.lineSoft)),
      ),
      child: Row(
        spacing: 8,
        children: [
          EIcon(EIcons.opacity, size: 18, color: c.inverseRaised),
          Expanded(
            child: Semantics(
              label: 'Window opacity',
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  activeTrackColor: c.accent,
                  inactiveTrackColor: c.line,
                  thumbColor: c.accent,
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(value: spot.opacity, min: 0.25, max: 1, divisions: 15, onChanged: w.setOpacity),
              ),
            ),
          ),
          SizedBox(
            width: 38,
            child: Text(
              '${(spot.opacity * 100).round()}%',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.inverseRaised, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
          Container(width: 1, height: 22, color: c.line),
          ChromeButton(label: 'Zoom out in the window', icon: EIcons.minus, width: 34, height: 36, radius: 9, iconSize: 16, onPressed: () => w.zoomBy(-0.25)),
          SizedBox(
            width: 40,
            child: Text(
              '${(w.pane.view.scale * 100).round()}%',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.text, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
          ChromeButton(label: 'Zoom in in the window', icon: EIcons.plus, width: 34, height: 36, radius: 9, iconSize: 16, onPressed: () => w.zoomBy(0.25)),
          Container(width: 1, height: 22, color: c.line),
          Semantics(
            button: true,
            toggled: spot.penHere,
            label: spot.penHere ? 'Pen: window' : 'Pen: page',
            excludeSemantics: true,
            child: Material(
              color: spot.penHere ? c.accent : c.side,
              borderRadius: BorderRadius.circular(9),
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: w.togglePen,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  child: Text(
                    spot.penHere ? 'Pen: window' : 'Pen: page',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: spot.penHere ? c.onAccent : c.text),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: Semantics(
        container: true,
        label: 'Window view: $title',
        explicitChildNodes: true,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // The shadow only outside it, so a faded window doesn't look grey.
            Positioned.fill(
              child: IgnorePointer(child: CustomPaint(painter: _OuterShadow(c.shadow, Radii.pill))),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  border: Border.all(color: c.text.withValues(alpha: 0.12 + (1 - spot.opacity) * 0.4)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      titleBar,
                      Expanded(child: page),
                      footer,
                    ],
                  ),
                ),
              ),
            ),
            // The corner that resizes it.
            Positioned(
              right: -6,
              bottom: -6,
              child: Semantics(
                label: 'Resize window',
                value: '${rect.width.round()} by ${rect.height.round()}',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  dragStartBehavior: DragStartBehavior.down,
                  onPanUpdate: (d) => _resize(d.delta),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeDownRight,
                    child: SizedBox.square(
                      dimension: 30,
                      child: Center(
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(color: c.inverse, borderRadius: BorderRadius.circular(6)),
                          child: Center(child: EIcon(EIcons.resizeCorner, size: 10, color: c.onInverse)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_picking)
              Positioned(
                left: 30,
                top: 48,
                child: _SourceMenu(controller: w, onDone: () => setState(() => _picking = false)),
              ),
          ],
        ),
      ),
    );
  }

  String _title(WidgetRef ref) {
    final nb = ref.watch(notebookProvider(w.pane.notebookId));
    final page = nb.pages.isEmpty ? null : nb.pageAt(w.pane.page).page;
    final t = page == null ? '' : page.title.trim();
    if (t.isNotEmpty) return t;
    return ref.read(libraryProvider).byId(w.pane.notebookId)?.title ?? (page == null ? 'Window' : pageTitle(page));
  }
}

/// `0 28px 56px -22px shadow`, painted only outside a rounded rect.
class _OuterShadow extends CustomPainter {
  _OuterShadow(this.color, this.radius);

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final box = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect((Offset.zero & size).inflate(120))
      ..addRRect(box);
    canvas
      ..save()
      ..clipPath(outside)
      ..drawRRect(
        box.shift(const Offset(0, 28)).deflate(22),
        Paint()
          ..color = color
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_OuterShadow old) => old.color != color || old.radius != radius;
}

/// "Show in the window": another spot on this page, another page of this
/// notebook, or another note (recent ones, or Find another note…).
class _SourceMenu extends ConsumerWidget {
  const _SourceMenu({required this.controller, required this.onDone});

  final WindowController controller;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final main = controller.main;
    final nb = ref.watch(notebookProvider(main.notebookId));
    final lib = ref.watch(libraryProvider);
    final brightness = Theme.of(context).brightness;
    final here = lib.byId(main.notebookId);
    final others = lib.recent(except: main.notebookId, count: 3);

    Widget row(String title, String sub, Color spine, bool on, VoidCallback pick) => Semantics(
      inMutuallyExclusiveGroup: true,
      checked: on,
      button: true,
      label: '$title. $sub',
      excludeSemantics: true,
      child: Material(
        color: on ? c.side : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.key),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.key),
          onTap: () {
            pick();
            onDone();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              child: Row(
                spacing: 10,
                children: [
                  Container(
                    width: 5,
                    height: 26,
                    decoration: BoxDecoration(color: displayInk(spine, brightness), borderRadius: BorderRadius.circular(2)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 1,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text),
                        ),
                        Text(sub, style: TextStyle(fontSize: 12, color: c.textMuted)),
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

    final p = controller.pane;
    final cover = here == null ? c.line : lib.coverOf(here);
    return Container(
      width: 300,
      constraints: const BoxConstraints(maxHeight: 420),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(Radii.card),
        boxShadow: c.menuShadow,
      ),
      child: Semantics(
        container: true,
        label: 'Show in the window',
        explicitChildNodes: true,
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
              child: Text(
                'SHOW IN THE WINDOW',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.96, color: c.textMuted),
              ),
            ),
            row(
              pageTitle(nb.pageAt(main.page).page),
              'This page · another spot',
              cover,
              p.notebookId == main.notebookId && p.page == main.page,
              () => controller.show(main.notebookId, main.page),
            ),
            for (final (i, page) in nb.pages.indexed)
              if (i != main.page)
                row(
                  pageTitle(page.page),
                  'This notebook · page ${i + 1}',
                  page.page.color ?? cover,
                  p.notebookId == main.notebookId && p.page == i,
                  () => controller.show(main.notebookId, i),
                ),
            for (final o in others)
              row(o.title, 'Another note · page ${o.lastPage + 1}', lib.coverOf(o), p.notebookId == o.id, () => controller.show(o.id, o.lastPage)),
            Semantics(
              button: true,
              label: 'Find another note…',
              excludeSemantics: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.key),
                onTap: () async {
                  onDone();
                  final picked = await showEndlessDialog<NotebookEntry>(context, builder: (_) => const _FindNote());
                  if (picked != null) controller.show(picked.id, picked.lastPage);
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      spacing: 10,
                      children: [
                        EIcon(EIcons.search, size: 16, color: c.accent),
                        Text(
                          'Find another note…',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.accent),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every notebook, found by its name, for the window.
class _FindNote extends ConsumerStatefulWidget {
  const _FindNote();

  @override
  ConsumerState<_FindNote> createState() => _FindNoteState();
}

class _FindNoteState extends ConsumerState<_FindNote> {
  String _q = '';
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lib = ref.watch(libraryProvider);
    final q = _q.trim().toLowerCase();
    final found = [
      for (final n in [...lib.active]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)))
        if (q.isEmpty || n.title.toLowerCase().contains(q)) n,
    ];
    return DialogFrame(
      title: 'Show another note',
      width: 520,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          LabeledField(label: 'Notebook', hint: 'Search by name', autofocus: true, controller: _field, onChanged: (v) => setState(() => _q = v)),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 380),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final n in found)
                  Semantics(
                    button: true,
                    label: n.title,
                    excludeSemantics: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Radii.key),
                      onTap: () => Navigator.of(context).pop(n),
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          spacing: 10,
                          children: [
                            Container(
                              width: 5,
                              height: 26,
                              decoration: BoxDecoration(
                                color: displayInk(lib.coverOf(n), Theme.of(context).brightness),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                n.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 15, color: c.text),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (found.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text('No notebook is called that.', style: TextStyle(fontSize: 14, color: c.textMuted)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
