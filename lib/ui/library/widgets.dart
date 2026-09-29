import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../library/library.dart';
import '../../library/thumbs.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../dialogs.dart';
import '../icons.dart';
import '../routes.dart';
import 'format.dart';

/// "FOLDERS", "NOTEBOOKS", "CONTINUE WRITING"…
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Text(text.toUpperCase(), style: TypeScale.sectionLabel.copyWith(color: context.colors.textMuted)),
      );
}

/// A folder in its color: tinted fill, colored outline.
class FolderIcon extends StatelessWidget {
  const FolderIcon({super.key, required this.color, this.size = 20, this.fillOpacity = 0.16});

  final Color color;
  final double size;
  final double fillOpacity;

  @override
  Widget build(BuildContext context) {
    final shown = displayInk(color, Theme.of(context).brightness);
    return ExcludeSemantics(
      child: CustomPaint(size: Size.square(size), painter: _FolderPainter(shown, fillOpacity, size <= 20 ? 1.8 : 1.6)),
    );
  }
}

class _FolderPainter extends CustomPainter {
  _FolderPainter(this.color, this.fillOpacity, this.stroke);

  final Color color;
  final double fillOpacity;
  final double stroke;

  static final _path = parseSvgPath(EIcons.folder.parts.single.d);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    canvas
      ..drawPath(_path, Paint()..color = color.withValues(alpha: fillOpacity))
      ..drawPath(
        _path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeJoin = StrokeJoin.round,
      );
  }

  @override
  bool shouldRepaint(_FolderPainter old) => old.color != color || old.fillOpacity != fillOpacity;
}

/// Dotted paper with a colored spine, the notebook's ink, and the "Locked"
/// veil (Main.dc.html covers; smaller on the Start page).
class NotebookCover extends StatelessWidget {
  const NotebookCover({
    super.key,
    required this.entry,
    required this.color,
    this.height = 150,
    this.width,
    this.spine = 10,
    this.dotSpacing = 14,
    this.radius = 12,
    this.showInk = true,
    this.shadow = true,
    this.background,
    this.inkScale = 0.35,
    this.inkPadding = 14,
  });

  final NotebookEntry entry;
  final Color color;
  final double height;
  final double? width;
  final double spine;
  final double dotSpacing;
  final double radius;
  final bool showInk;
  final bool shadow;
  final Color? background;
  final double inkScale;
  final double inkPadding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final brightness = Theme.of(context).brightness;
    final locked = entry.locked;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: background ?? c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow ? c.coverShadow : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(fit: StackFit.expand, children: [
        CustomPaint(
          painter: _CoverPainter(
            dots: c.dot,
            spacing: dotSpacing,
            spine: spine,
            spineColor: displayInk(color, brightness),
            thumb: showInk && !locked ? entry.thumb : null,
            brightness: brightness,
            inkScale: inkScale,
            inkPadding: inkPadding,
          ),
        ),
        if (locked)
          Positioned(
            left: spine,
            top: 0,
            right: 0,
            bottom: 0,
            child: ColoredBox(
              color: c.side.withValues(alpha: 0.85),
              child: height < 100
                  ? Center(child: EIcon(EIcons.lock, size: 18, color: c.inverseRaised))
                  : Column(mainAxisAlignment: MainAxisAlignment.center, spacing: 6, children: [
                      EIcon(EIcons.lock, size: 30, color: c.inverseRaised),
                      Text('Locked', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.inverseRaised)),
                    ]),
            ),
          ),
      ]),
    );
  }
}

class _CoverPainter extends CustomPainter {
  _CoverPainter({
    required this.dots,
    required this.spacing,
    required this.spine,
    required this.spineColor,
    required this.thumb,
    required this.brightness,
    required this.inkScale,
    required this.inkPadding,
  });

  final Color dots;
  final double spacing;
  final double spine;
  final Color spineColor;
  final InkThumb? thumb;
  final Brightness brightness;
  final double inkScale;
  final double inkPadding;

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = dots;
    for (var y = spacing / 2; y < size.height; y += spacing) {
      for (var x = spacing / 2; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 1.1, dot);
      }
    }
    if (spine > 0) canvas.drawRect(Rect.fromLTWH(0, 0, spine, size.height), Paint()..color = spineColor);
    thumb?.paint(
      canvas,
      Rect.fromLTRB(spine + inkPadding, inkPadding, size.width - inkPadding, size.height - inkPadding),
      brightness,
      maxScale: inkScale,
    );
  }

  @override
  bool shouldRepaint(_CoverPainter old) =>
      old.thumb != thumb || old.spineColor != spineColor || old.dots != dots || old.brightness != brightness;
}

// Menus.

class _MenuAction<T> {
  const _MenuAction(this.value, this.label, this.icon);

  final T value;
  final String label;
  final EIconData icon;
}

Future<T?> _showActions<T>(BuildContext context, Offset at, List<_MenuAction<T>> actions) {
  final c = context.colors;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
    color: c.surface,
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.pill), side: BorderSide(color: c.line)),
    menuPadding: const EdgeInsets.all(8),
    items: [
      for (final a in actions)
        PopupMenuItem<T>(
          value: a.value,
          height: 48,
          child: Row(spacing: 12, children: [
            EIcon(a.icon, color: c.text),
            Text(a.label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.text)),
          ]),
        ),
    ],
  );
}

enum _NotebookAction { open, split, rename, move, color, pin, trash, restore, delete }

/// The long-press menu for a notebook card.
Future<void> showNotebookMenu(BuildContext context, WidgetRef ref, NotebookEntry n, Offset at) async {
  final lib = ref.read(libraryProvider.notifier);
  final actions = n.trashed
      ? [
          _MenuAction(_NotebookAction.restore, 'Restore', EIcons.restore),
          _MenuAction(_NotebookAction.delete, 'Delete forever', EIcons.trash),
        ]
      : [
          _MenuAction(_NotebookAction.open, 'Open', EIcons.notebook),
          _MenuAction(_NotebookAction.split, 'Open in split view', EIcons.split),
          _MenuAction(_NotebookAction.rename, 'Rename', EIcons.edit),
          _MenuAction(_NotebookAction.move, 'Move to folder', EIcons.folder),
          _MenuAction(_NotebookAction.color, 'Color', EIcons.palette),
          _MenuAction(_NotebookAction.pin, n.pinned ? 'Unpin from Start' : 'Pin to Start', EIcons.pin),
          _MenuAction(_NotebookAction.trash, 'Move to Trash', EIcons.trash),
        ];
  final choice = await _showActions(context, at, actions);
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case _NotebookAction.open:
      openNotebook(context, ref, n.id);
    case _NotebookAction.split:
      final other = ref.read(libraryProvider).recent(except: n.id, count: 1).firstOrNull;
      context.push(Routes.split((n.id, n.lastPage), other == null ? (n.id, n.lastPage + 1) : (other.id, other.lastPage)));
    case _NotebookAction.rename:
      final name = await showNamePrompt(context, title: 'Rename notebook', initial: n.title, action: 'Rename');
      if (name != null) await lib.rename(n.id, name);
    case _NotebookAction.move:
      final to = await showFolderPicker(context, ref, current: n.folder);
      if (to != null) await lib.move(n.id, to);
    case _NotebookAction.color:
      final color = await showColorPicker(context, title: 'Notebook color', current: ref.read(libraryProvider).coverOf(n));
      if (color != null) await lib.setCover(n.id, color);
    case _NotebookAction.pin:
      await lib.setPinned(n.id, !n.pinned);
    case _NotebookAction.trash:
      await lib.trash(n.id);
      if (context.mounted) _snack(context, '“${n.title}” moved to Trash');
    case _NotebookAction.restore:
      await lib.restore(n.id);
    case _NotebookAction.delete:
      final ok = await showConfirm(
        context,
        title: 'Delete forever?',
        message: '“${n.title}” and all its pages will be deleted from this tablet. This can’t be undone.',
        action: 'Delete forever',
      );
      if (ok) await lib.deleteForever(n.id);
  }
}

void _snack(BuildContext context, String text) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(content: Text(text, textAlign: TextAlign.center), width: 420, duration: const Duration(seconds: 3)));
}

enum _FolderAction { rename, color, delete }

/// The long-press menu for a folder.
Future<void> showFolderMenu(BuildContext context, WidgetRef ref, FolderEntry f, Offset at) async {
  final lib = ref.read(libraryProvider.notifier);
  final choice = await _showActions(context, at, [
    _MenuAction(_FolderAction.rename, 'Rename', EIcons.edit),
    _MenuAction(_FolderAction.color, 'Color', EIcons.palette),
    _MenuAction(_FolderAction.delete, 'Delete folder', EIcons.trash),
  ]);
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case _FolderAction.rename:
      final name = await showNamePrompt(context, title: 'Rename folder', initial: f.name, action: 'Rename');
      if (name == null) return;
      final ok = await lib.renameFolder(f.path, name);
      if (!context.mounted) return;
      if (!ok) {
        _snack(context, 'There’s already a folder called “$name”');
      } else if (GoRouterState.of(context).uri.queryParametersAll['f'] case final shown?
          when isInside(shown, f.path)) {
        context.go(Routes.library([...f.path.sublist(0, f.path.length - 1), name.trim(), ...shown.sublist(f.path.length)]));
      }
    case _FolderAction.color:
      final color = await showColorPicker(context, title: 'Folder color', current: f.color);
      if (color != null) await lib.setFolderColor(f.path, color);
    case _FolderAction.delete:
      final count = ref.read(libraryProvider).countUnder(f.path);
      final ok = await showConfirm(
        context,
        title: 'Delete “${f.name}”?',
        message: count == 0
            ? 'The folder is empty.'
            : 'Its ${notebooksLabel(count)} will move to the Trash, where you can restore them for 30 days.',
        action: 'Delete folder',
      );
      if (!ok) return;
      await lib.deleteFolder(f.path);
      if (context.mounted && (GoRouterState.of(context).uri.queryParametersAll['f'] ?? const []).length >= f.path.length) {
        final shown = GoRouterState.of(context).uri.queryParametersAll['f'] ?? const [];
        if (isInside(shown, f.path)) context.go(Routes.library(f.path.sublist(0, f.path.length - 1)));
      }
  }
}

/// Creates a folder inside [parent] and opens it.
Future<void> createFolderFlow(BuildContext context, WidgetRef ref, List<String> parent) async {
  final name = await showNamePrompt(context, title: 'New folder', action: 'Create', hint: 'e.g. Physics');
  if (name == null || !context.mounted) return;
  final ok = await ref.read(libraryProvider.notifier).createFolder(parent, name);
  if (!context.mounted) return;
  if (ok) {
    context.go(Routes.library([...parent, name.trim()]));
  } else {
    _snack(context, 'There’s already a folder called “${name.trim()}”');
  }
}

/// Picks a folder ("No folder" is `[]`). Null when cancelled.
Future<List<String>?> showFolderPicker(BuildContext context, WidgetRef ref, {required List<String> current}) =>
    showEndlessDialog<List<String>>(context, builder: (context) => _FolderPicker(current: current));

class _FolderPicker extends ConsumerWidget {
  const _FolderPicker({required this.current});

  final List<String> current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final folders = ref.watch(libraryProvider).folders;
    Widget row(List<String> path, String label, {Color? color}) {
      final selected = listEquals(path, current);
      return Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.key),
          onTap: () => Navigator.of(context).pop(path),
          child: Container(
            height: 44,
            padding: EdgeInsets.only(left: 12.0 + (path.isEmpty ? 0 : (path.length - 1) * 22), right: 12),
            decoration: BoxDecoration(
              color: selected ? c.sideSelected : null,
              borderRadius: BorderRadius.circular(Radii.key),
            ),
            child: Row(spacing: 12, children: [
              if (color == null) EIcon(EIcons.notebook, color: c.textMuted) else FolderIcon(color: color),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: c.text),
                ),
              ),
              if (selected) EIcon(EIcons.check, size: 18, color: c.accent),
            ]),
          ),
        ),
      );
    }

    return DialogFrame(
      title: 'Move to folder',
      width: 460,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 420),
        child: ListView(shrinkWrap: true, children: [
          row(const [], 'No folder'),
          for (final f in folders) row(f.path, f.name, color: f.color),
        ]),
      ),
    );
  }
}

/// Picks one of the cover colors. Null when cancelled.
Future<Color?> showColorPicker(BuildContext context, {required String title, required Color current}) =>
    showEndlessDialog<Color>(
      context,
      builder: (context) {
        final brightness = Theme.of(context).brightness;
        return DialogFrame(
          title: title,
          width: 460,
          child: Wrap(spacing: 12, runSpacing: 12, children: [
            for (final color in coverColors)
              Semantics(
                button: true,
                selected: color == current,
                label: colorLabel(color),
                excludeSemantics: true,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.of(context).pop(color),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: _Swatch(color: displayInk(color, brightness), selected: color == current),
                    ),
                  ),
                ),
              ),
          ]),
        );
      },
    );

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected});

  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: selected
              ? [BoxShadow(color: color, spreadRadius: 5), BoxShadow(color: context.colors.surface, spreadRadius: 3)]
                  .reversed
                  .toList()
              : null,
        ),
      );
}

/// Names for the cover colors (screen readers).
String colorLabel(Color c) => switch (coverColors.indexOf(c)) {
      0 => 'Blue',
      1 => 'Terracotta',
      2 => 'Green',
      3 => 'Plum',
      4 => 'Teal',
      5 => 'Gold',
      _ => 'Color',
    };

/// A long press, or a right click with a mouse, at the pointer.
class ContextTarget extends StatefulWidget {
  const ContextTarget({super.key, required this.onMenu, required this.child});

  final ValueChanged<Offset> onMenu;
  final Widget child;

  @override
  State<ContextTarget> createState() => _ContextTargetState();
}

class _ContextTargetState extends State<ContextTarget> {
  Offset _at = Offset.zero;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onLongPressStart: (d) => widget.onMenu(d.globalPosition),
        onSecondaryTapDown: (d) => _at = d.globalPosition,
        onSecondaryTap: () => widget.onMenu(_at),
        child: widget.child,
      );
}

/// Where a menu opens for a keyboard or screen reader (no pointer position).
Offset menuAnchor(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  return box == null ? Offset.zero : box.localToGlobal(box.size.center(Offset.zero));
}
