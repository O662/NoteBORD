import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../board/model.dart';
import '../../canvas/new_items.dart';
import '../../canvas/pane.dart';
import '../../canvas/selection.dart';
import '../../state/notebook.dart';
import '../../state/photos.dart';
import '../../state/settings.dart';
import '../../templates/templates.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../common.dart';
import '../dialogs.dart';
import '../icons.dart';
import '../templates/templates_dialog.dart';
import 'insert_menu.dart';

/// What the tools that drop something say when picked.
const placeHints = {
  CanvasTool.text: 'Tap the page to type · tap a text box or sticky note to edit it',
  CanvasTool.sticky: 'Tap the page to drop a sticky note',
  CanvasTool.stack: 'Tap the page to drop a stack of sticky notes',
  CanvasTool.frame: 'Tap the page to place a lined sheet',
  CanvasTool.shape: 'Drag to draw the shape · tap to drop one',
};

/// Does what was picked in the Insert menu (or the rail's Insert flyout)
/// for [pane]. [hint] shows a tool's hint where the screen has one.
Future<void> runInsert(
  BuildContext context,
  WidgetRef ref,
  Pane pane,
  InsertAction action, {
  ValueChanged<String>? hint,
}) async {
  void place(CanvasTool tool) {
    ref.read(settingsProvider.notifier).apply((s) => s.copyWith(tool: tool));
    hint?.call(placeHints[tool]!);
  }

  switch (action) {
    case InsertAction.sticky:
      place(CanvasTool.sticky);
    case InsertAction.stack:
      place(CanvasTool.stack);
    case InsertAction.text:
      place(CanvasTool.text);
    case InsertAction.frame:
      place(CanvasTool.frame);
    case InsertAction.shape:
      place(CanvasTool.shape);
    case InsertAction.templates:
      await showTemplatesDialog(context, pane: pane);
    case InsertAction.tablet:
      await insertImage(context, ref, pane, PhotoOrigin.tablet);
    case InsertAction.camera:
      await insertImage(context, ref, pane, PhotoOrigin.camera);
    case InsertAction.image:
      // With a camera, ask where the picture comes from.
      final origin = ref.read(photoPickerProvider).hasCamera ? await showImageSources(context) : PhotoOrigin.tablet;
      if (origin != null && context.mounted) await insertImage(context, ref, pane, origin);
  }
}

/// Picks a picture and puts it in the middle of the view, selected.
Future<void> insertImage(BuildContext context, WidgetRef ref, Pane pane, PhotoOrigin origin) async {
  final picker = ref.read(photoPickerProvider);
  if (origin == PhotoOrigin.camera && !picker.hasCamera) {
    showNote(context, 'This device has no camera Endless can use');
    return;
  }
  final notebookId = pane.notebookId;
  final notifier = ref.read(notebookProvider(notebookId).notifier);
  final Uint8List? bytes;
  try {
    bytes = await picker.pick(origin);
  } on Object catch (e) {
    debugPrint('Picking an image failed: $e');
    if (context.mounted) showNote(context, 'Couldn’t open ${origin == PhotoOrigin.camera ? 'the camera' : 'your photos'}');
    return;
  }
  if (bytes == null || !context.mounted || pane.notebookId != notebookId) return;
  final pageId = ref.read(notebookProvider(notebookId)).pageAt(pane.page).id;
  final ImageItem? item;
  try {
    item = await notifier.addImage(pageId, bytes, center: pane.view.visiblePage.center);
  } on Object catch (e) {
    debugPrint('Adding an image failed: $e');
    if (context.mounted) showNote(context, 'That file isn’t a picture Endless can show');
    return;
  }
  if (item == null || !context.mounted) return;
  ref.read(settingsProvider.notifier).apply((s) => s.copyWith(tool: CanvasTool.select));
  pane.selection
    ..menu = SelectionMenu.convert
    ..select([item.id]);
  pane.toast('Added an image to the page', undoPageId: pageId);
}

/// Puts a paper frame with [template] near the top of the view ("Use for:
/// Frame" in Templates). Returns false if the page can't be written to.
bool insertTemplateFrame(WidgetRef ref, Pane pane, TemplateDef template) {
  final nb = ref.read(notebookProvider(pane.notebookId));
  final page = nb.pageAt(pane.page);
  if (nb.isSealed(page.id)) return false;
  final view = pane.view.visiblePage;
  final frame = newFrame(
    Offset(view.center.dx, view.top + 120 / pane.view.scale),
    z: page.isEmpty ? 1 : page.items.first.z - 1,
    now: DateTime.now().toUtc(),
    template: template,
  );
  ref.read(notebookProvider(pane.notebookId).notifier).insertItems(page.id, [frame], at: 0);
  ref.read(settingsProvider.notifier).apply((s) => s.tool.inks ? s : s.copyWith(tool: CanvasTool.pen));
  pane.toast('Added a paper frame to the page', undoPageId: page.id);
  return true;
}

/// Asks where a picture comes from: the tablet or the camera.
Future<PhotoOrigin?> showImageSources(BuildContext context) => showEndlessDialog<PhotoOrigin>(
      context,
      builder: (context) {
        final c = context.colors;
        Widget option(String title, String desc, EIconData icon, PhotoOrigin origin) => Expanded(
              child: Semantics(
                button: true,
                label: title,
                hint: desc,
                excludeSemantics: true,
                child: Material(
                  color: c.surface,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: c.cardLine),
                    borderRadius: BorderRadius.circular(Radii.card),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(origin),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
                      child: Column(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(color: c.greenTint, borderRadius: BorderRadius.circular(Radii.button)),
                          child: Center(child: EIcon(icon, size: 24, color: c.greenDeep)),
                        ),
                        Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                        Text(desc, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: c.textMuted)),
                      ]),
                    ),
                  ),
                ),
              ),
            );
        return DialogFrame(
          title: 'Add an image',
          width: 460,
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
              option('This tablet', 'Photos and files', EIcons.image, PhotoOrigin.tablet),
              option('Camera', 'Take a photo now', EIcons.camera, PhotoOrigin.camera),
            ]),
          ),
        );
      },
    );

/// Rectangle, oval, triangle, line or arrow, under the tool pill while the
/// Shapes tool is picked (like the laser's colors).
class ShapeKinds extends ConsumerWidget {
  const ShapeKinds({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final picked = ref.watch(settingsProvider.select((s) => s.shapeKind));
    final icons = {
      ShapeType.rect: EIcons.shapeRect,
      ShapeType.ellipse: EIcons.shapeEllipse,
      ShapeType.triangle: EIcons.shapeTriangle,
      ShapeType.line: EIcons.shapeLine,
      ShapeType.arrow: EIcons.shapeArrow,
    };
    return Semantics(
      container: true,
      label: 'Shape',
      explicitChildNodes: true,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(Radii.button),
          boxShadow: c.pillShadow,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 2, children: [
          for (final kind in ShapeType.values)
            ChromeButton(
              label: shapeName(kind),
              icon: icons[kind],
              width: 44,
              height: 38,
              radius: 9,
              background: picked == kind ? c.side : null,
              onPressed: () => ref.read(settingsProvider.notifier).apply((s) => s.copyWith(shapeKind: kind)),
            ),
        ]),
      ),
    );
  }
}
