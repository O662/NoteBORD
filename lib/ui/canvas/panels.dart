import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../canvas/page_runtime.dart';
import '../../canvas/canvas_view.dart';
import '../../canvas/pane.dart';
import '../../state/notebook.dart';
import '../../state/settings.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../common.dart';
import '../icons.dart';

/// Right-hand pages rail: current page of total, thumbnails, locked pages, add page.
class PagesRail extends ConsumerWidget {
  const PagesRail({super.key, required this.pane, required this.maxHeight});

  final Pane pane;
  final double maxHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListenableBuilder(
        listenable: pane,
        // A Consumer, so what _build watches is tracked for this build.
        builder: (context, _) => Consumer(builder: (context, ref, _) => _build(context, ref)),
      );

  Widget _build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final nb = ref.watch(notebookProvider(pane.notebookId));
    final open = ref.watch(settingsProvider.select((s) => s.pagesOpen));
    final settings = ref.read(settingsProvider.notifier);
    final notebook = ref.read(notebookProvider(pane.notebookId).notifier);
    final current = pane.page.clamp(0, nb.pages.length - 1);
    final counter = '${current + 1} / ${nb.pages.length}';
    // A new page in a locked notebook needs the notebook's key.
    final canAdd = !(nb.notebookLocked && nb.sealed.isNotEmpty);
    void toggle() => settings.apply((s) => s.copyWith(pagesOpen: !s.pagesOpen));

    if (!open) {
      return Semantics(
        button: true,
        expanded: false,
        label: 'Show pages',
        excludeSemantics: true,
        child: Material(
          color: c.surface.withValues(alpha: 0.96),
          shape: RoundedRectangleBorder(
            side: BorderSide(color: c.line),
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(Radii.card)),
          ),
          child: InkWell(
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(Radii.card)),
            onTap: toggle,
            child: SizedBox(
              width: 48,
              height: 96,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, spacing: 6, children: [
                EIcon(EIcons.pages, size: 18, color: c.inverseRaised),
                Text(counter.replaceAll(' ', ''),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.inverseRaised)),
              ]),
            ),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      label: 'Pages',
      explicitChildNodes: true,
      child: Container(
        width: 100,
        constraints: BoxConstraints(maxHeight: maxHeight),
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        decoration: BoxDecoration(
          color: c.surface.withValues(alpha: 0.96),
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ChromeButton(
            label: 'Hide pages',
            expanded: true,
            width: 80,
            radius: Radii.key,
            onPressed: toggle,
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
              // "12 / 12" at large font sizes shrinks to fit the rail.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(counter, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.inverseRaised)),
                ),
              ),
              EIcon(EIcons.chevronRight, size: 16, color: c.inverseRaised),
            ]),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: nb.pages.length + (canAdd ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                if (i == nb.pages.length) {
                  return Semantics(
                    button: true,
                    label: 'Add page',
                    excludeSemantics: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Radii.small),
                      onTap: () => pane.goTo(notebook.addPage()),
                      child: DashedBorder(
                        color: c.lineStrong,
                        child: SizedBox(
                          width: 78,
                          height: 44,
                          child: Center(child: EIcon(EIcons.plus, size: 18, color: c.textMuted)),
                        ),
                      ),
                    ),
                  );
                }
                return _PageThumb(
                  page: nb.pages[i],
                  number: i + 1,
                  current: i == current,
                  locked: nb.pages[i].page.locked || nb.isSealed(nb.pages[i].id),
                  revision: nb.revision,
                  onTap: () => pane.goTo(i),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

class _PageThumb extends StatelessWidget {
  const _PageThumb({
    required this.page,
    required this.number,
    required this.current,
    required this.locked,
    required this.revision,
    required this.onTap,
  });

  final PageRuntime page;
  final int number;
  final bool current;
  final bool locked;
  final int revision;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = locked ? 'Page $number, locked' : (current ? 'Page $number, current' : 'Page $number');
    return Semantics(
      button: true,
      selected: current,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: locked ? c.side : c.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: current ? c.accent : c.line, width: current ? 2 : 1),
          borderRadius: BorderRadius.circular(Radii.small),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 78,
            height: 58,
            child: Stack(children: [
              if (locked)
                Center(child: EIcon(EIcons.lock, size: 18, color: c.textMuted))
              else
                Positioned.fill(
                  child: CustomPaint(
                    painter: PageThumbPainter(page, revision, Theme.of(context).brightness, c),
                  ),
                ),
              Positioned(
                right: 5,
                bottom: 3,
                child: Text(
                  '$number',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: current ? FontWeight.w700 : FontWeight.w400,
                    color: current ? c.accent : c.textMuted,
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

/// Draws a page's ink scaled to fit [area].
void paintPageFitted(Canvas canvas, Rect area, Rect content, PageRuntime page, Brightness b, EndlessColors c) {
  final scale = math.min(area.width / content.width, area.height / content.height);
  canvas
    ..save()
    ..clipRect(area)
    ..translate(area.center.dx - content.center.dx * scale, area.center.dy - content.center.dy * scale)
    ..scale(scale)
    ..drawPicture(page.fullPicture(b, c))
    ..restore();
}

class PageThumbPainter extends CustomPainter {
  PageThumbPainter(this.page, this.revision, this.brightness, this.colors);

  final PageRuntime page;
  final int revision;
  final Brightness brightness;
  final EndlessColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final content = page.contentBounds;
    if (content == null) return;
    final padded = content.inflate(math.max(content.width, content.height) * 0.08 + 8);
    paintPageFitted(canvas, (Offset.zero & size).deflate(4), padded, page, brightness, colors);
  }

  @override
  bool shouldRepaint(PageThumbPainter old) =>
      old.page != page || old.revision != revision || old.brightness != brightness || old.colors != colors;
}

/// Width of the bottom-right map card and zoom pill.
const cornerWidth = 236.0;

/// − · % · + | [show map] · whole board · full screen.
class ZoomPill extends StatelessWidget {
  const ZoomPill({
    super.key,
    required this.view,
    required this.onFit,
    required this.showMapButton,
    required this.onShowMap,
    required this.fullScreen,
    required this.onToggleFullScreen,
    this.board = false,
  });

  final CanvasView view;

  /// The whole board is showing: its button goes back.
  final bool board;
  final VoidCallback onFit;
  final bool showMapButton;
  final VoidCallback onShowMap;
  final bool fullScreen;
  final VoidCallback onToggleFullScreen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Buttons share the pill's fixed 236 dp in proportion to their design
    // widths, so larger system font sizes or the extra map button can't
    // overflow it; the percentage scales down if it has to.
    Widget cell(int flex, Widget child) => Expanded(flex: flex, child: child);
    Widget button(String label, EIconData icon, VoidCallback onPressed, {bool selected = false, bool? expanded}) =>
        ChromeButton(
          label: label,
          icon: icon,
          iconSize: 18,
          width: null,
          height: 40,
          radius: Radii.key,
          selected: selected,
          expanded: expanded,
          onPressed: onPressed,
        );
    return Container(
      width: cornerWidth,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(Radii.card),
        boxShadow: c.cardShadow,
      ),
      child: Row(children: [
        cell(44, button('Zoom out', EIcons.minus, () => view.zoomStep(-1))),
        cell(
          52,
          ListenableBuilder(
            listenable: view,
            builder: (context, _) {
              final pct = '${(view.scale * 100).round()}%';
              return ChromeButton(
                label: 'Zoom level $pct, tap to reset',
                width: null,
                padding: 4,
                height: 40,
                radius: Radii.key,
                onPressed: () => view.setScale(1),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    pct,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.text,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        cell(44, button('Zoom in', EIcons.plus, () => view.zoomStep(1))),
        Container(width: 1, height: 24, margin: const EdgeInsets.symmetric(horizontal: 2), color: c.line),
        if (showMapButton) cell(40, button('Show map', EIcons.map, onShowMap, expanded: false)),
        cell(
          40,
          button(board ? 'Back from the whole board' : 'Zoom out to the whole board', EIcons.board, onFit, selected: board),
        ),
        cell(
          40,
          button(
            fullScreen ? 'Exit full screen' : 'Full screen: hide menus',
            fullScreen ? EIcons.exitFullScreen : EIcons.fullScreen,
            onToggleFullScreen,
            selected: fullScreen,
          ),
        ),
      ]),
    );
  }
}

/// Minimap of the endless page, above the zoom pill. The box is your view;
/// tap or drag to move it.
class MapPanel extends ConsumerWidget {
  const MapPanel({super.key, required this.pane, required this.onHide});

  final Pane pane;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListenableBuilder(
        listenable: pane,
        // A Consumer, so what _build watches is tracked for this build.
        builder: (context, _) => Consumer(builder: (context, ref, _) => _build(context, ref)),
      );

  Widget _build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final nb = ref.watch(notebookProvider(pane.notebookId));
    final brightness = Theme.of(context).brightness;
    return Container(
      width: cornerWidth,
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(Radii.card),
        boxShadow: c.cardShadow,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
        Row(children: [
          const SizedBox(width: 4),
          Expanded(child: Text('Map', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textMuted))),
          Transform.translate(
            offset: const Offset(6, 0),
            child: ChromeButton(
              label: 'Hide map',
              expanded: true,
              height: 36,
              radius: Radii.key,
              icon: EIcons.chevronDown,
              iconSize: 16,
              foreground: c.inverseRaised,
              onPressed: onHide,
            ),
          ),
        ]),
        _MinimapView(view: pane.view, page: nb.pageAt(pane.page), revision: nb.revision, brightness: brightness),
      ]),
    );
  }
}

class _MinimapView extends StatelessWidget {
  const _MinimapView({required this.view, required this.page, required this.revision, required this.brightness});

  static const size = Size(218, 112);

  final CanvasView view;
  final PageRuntime page;
  final int revision;
  final Brightness brightness;

  _MapGeometry _geometry() {
    final visible = view.visiblePage;
    final content = page.contentBounds;
    var world = content == null ? visible : content.expandToInclude(visible);
    world = world.inflate(math.max(world.width, world.height) * 0.06);
    final inner = (Offset.zero & size).deflate(4);
    final scale = math.min(inner.width / world.width, inner.height / world.height);
    final offset = inner.center - world.center * scale;
    return _MapGeometry(world, scale, offset);
  }

  void _jump(Offset local) {
    final g = _geometry();
    view.centerOn((local - g.offset) / g.scale);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: 'Map: the box shows your view. Tap to move there.',
      child: GestureDetector(
        onTapDown: (d) => _jump(d.localPosition),
        onPanUpdate: (d) => _jump(d.localPosition),
        child: Container(
          width: size.width,
          height: size.height,
          decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(Radii.small)),
          child: CustomPaint(painter: _MinimapPainter(this, c)),
        ),
      ),
    );
  }
}

class _MapGeometry {
  _MapGeometry(this.world, this.scale, this.offset);

  final Rect world;
  final double scale;
  final Offset offset;

  Rect toMap(Rect r) => Rect.fromPoints(r.topLeft * scale + offset, r.bottomRight * scale + offset);
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter(this.map, this.colors) : super(repaint: map.view);

  final _MinimapView map;
  final EndlessColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final g = map._geometry();
    final pageRect = (Offset.zero & size).deflate(4);
    final dashed = Path()..addRRect(RRect.fromRectAndRadius(pageRect, const Radius.circular(4)));
    final dashPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = colors.lineStrong;
    for (final m in dashed.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 6) {
        canvas.drawPath(m.extractPath(d, d + 3), dashPaint);
      }
    }
    final content = map.page.contentBounds;
    if (content != null) {
      canvas
        ..save()
        ..clipRect(pageRect)
        ..translate(g.offset.dx, g.offset.dy)
        ..scale(g.scale)
        ..drawPicture(map.page.fullPicture(map.brightness, colors))
        ..restore();
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(g.toMap(map.view.visiblePage).intersect(pageRect), const Radius.circular(3)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = colors.accent,
    );
  }

  @override
  bool shouldRepaint(_MinimapPainter old) =>
      old.map.page != map.page || old.map.revision != map.revision || old.map.brightness != map.brightness ||
      old.colors != colors;
}

/// The tip pill at the bottom, e.g. "Tap the pen again for colors and thickness".
class HintPill extends StatelessWidget {
  const HintPill({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: c.inverse,
          borderRadius: BorderRadius.circular(Radii.chip),
          boxShadow: [BoxShadow(color: c.shadow, offset: const Offset(0, 10), blurRadius: 24, spreadRadius: -12)],
        ),
        child: Text(text, style: TextStyle(fontSize: 14, color: c.onInverse)),
      ),
    );
  }
}
