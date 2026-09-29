import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../canvas/pane.dart';
import '../../library/library.dart';
import '../../library/thumbs.dart';
import '../../state/notebook.dart';
import '../../templates/templates.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../common.dart';
import '../dialogs.dart';
import '../icons.dart';
import '../routes.dart';

/// Opens the Templates dialog (design/screens/Templates.png). From a
/// notebook ([pane]) a template can make a new page, a frame or a new
/// notebook; from the library only a new notebook (in [folder]).
Future<void> showTemplatesDialog(
  BuildContext context, {
  Pane? pane,
  TemplateTarget target = TemplateTarget.newPage,
  String? initial,
  List<String> folder = const [],
}) =>
    showEndlessDialog<void>(
      context,
      builder: (_) => TemplatesDialog(
        pane: pane,
        target: pane == null ? TemplateTarget.newNotebook : target,
        initial: initial ?? 'cornell',
        folder: folder,
        hostContext: context,
      ),
    );

enum _Category { all, paper, study, planning, boards, mine }

const _categoryLabels = {
  _Category.all: 'All',
  _Category.paper: 'Paper',
  _Category.study: 'Study',
  _Category.planning: 'Planning',
  _Category.boards: 'Boards',
  _Category.mine: 'My templates',
};

const _targetLabels = {
  TemplateTarget.newPage: 'New page',
  TemplateTarget.frame: 'Frame',
  TemplateTarget.newNotebook: 'New notebook',
};

class TemplatesDialog extends ConsumerStatefulWidget {
  const TemplatesDialog({
    super.key,
    required this.pane,
    required this.target,
    required this.initial,
    required this.folder,
    required this.hostContext,
  });

  final Pane? pane;
  final TemplateTarget target;
  final String initial;
  final List<String> folder;

  /// The screen that opened the dialog, for navigating after it closes.
  final BuildContext hostContext;

  @override
  ConsumerState<TemplatesDialog> createState() => _TemplatesDialogState();
}

class _TemplatesDialogState extends ConsumerState<TemplatesDialog> {
  late String _selected = widget.initial;
  late TemplateTarget _target = widget.target;
  _Category _category = _Category.all;
  bool _busy = false;

  String _nameOf(String id) =>
      templateById(id)?.name ??
      ref.read(userTemplatesProvider).where((t) => t.id == id).firstOrNull?.name ??
      'template';

  bool _inCategory(TemplateDef t) => switch (_category) {
        _Category.all => true,
        _Category.paper => t.categories.contains(TemplateCategory.paper),
        _Category.study => t.categories.contains(TemplateCategory.study),
        _Category.planning => t.categories.contains(TemplateCategory.planning),
        _Category.boards => t.categories.contains(TemplateCategory.boards),
        _Category.mine => false,
      };

  Future<void> _use() async {
    final builtIn = templateById(_selected);
    final user = ref.read(userTemplatesProvider).where((t) => t.id == _selected).firstOrNull;
    if (builtIn == null && user == null) return;
    final paper = builtIn?.paper ?? user!.paper;
    final layout = builtIn != null ? (builtIn.layout ? builtIn.id : null) : user!.layout;
    final items = user?.freshItems() ?? const [];
    final host = widget.hostContext;
    switch (_target) {
      case TemplateTarget.frame:
        Navigator.of(context).pop();
        showComingSoon(host, 'Paper frames');
      case TemplateTarget.newPage:
        final pane = widget.pane!;
        final i = ref
            .read(notebookProvider(pane.notebookId).notifier)
            .addPage(after: pane.page, paper: paper, template: layout, items: items);
        Navigator.of(context).pop();
        pane.goTo(i);
      case TemplateTarget.newNotebook:
        setState(() => _busy = true);
        final folder = widget.pane == null
            ? widget.folder
            : ref.read(libraryProvider).byId(widget.pane!.notebookId)?.folder ?? const <String>[];
        final id = await ref.read(libraryProvider.notifier).createNotebook(
              folder: folder,
              paper: paper,
              template: layout,
              items: items,
            );
        if (!mounted) return;
        Navigator.of(context).pop();
        if (!host.mounted) return;
        final to = Routes.notebook(id, page: 0);
        if (widget.pane == null) {
          host.push(to);
        } else {
          host.pushReplacement(to);
        }
    }
  }

  Future<void> _saveAsTemplate() async {
    final pane = widget.pane!;
    final nb = ref.read(notebookProvider(pane.notebookId));
    final page = nb.pageAt(pane.page);
    final name = await showNamePrompt(
      context,
      title: 'Save as template',
      initial: page.page.title.isNotEmpty ? page.page.title : nb.notebook.title,
      action: 'Save',
    );
    if (name == null || !mounted) return;
    final t = await ref.read(userTemplatesProvider.notifier).saveFromPage(page.page, name);
    if (!mounted) return;
    setState(() {
      _category = _Category.mine;
      _selected = t.id;
    });
  }

  Future<void> _deleteTemplate(UserTemplate t) async {
    final ok = await showConfirm(
      context,
      title: 'Delete “${t.name}”?',
      message: 'Pages already made from it stay as they are.',
      action: 'Delete',
    );
    if (!ok) return;
    await ref.read(userTemplatesProvider.notifier).delete(t.id);
    if (mounted && _selected == t.id) setState(() => _selected = 'cornell');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = MediaQuery.sizeOf(context);
    final user = ref.watch(userTemplatesProvider);
    final canSave = widget.pane != null &&
        !ref.watch(notebookProvider(widget.pane!.notebookId)).isSealed(
              ref.read(notebookProvider(widget.pane!.notebookId)).pageAt(widget.pane!.page).id,
            );
    final targets = widget.pane == null ? const [TemplateTarget.newNotebook] : TemplateTarget.values;
    final tiles = <Widget>[
      if (_category != _Category.mine)
        for (final t in builtInTemplates)
          if (_inCategory(t))
            _Tile(
              name: t.name,
              selected: _selected == t.id,
              onTap: () => setState(() => _selected = t.id),
              preview: CustomPaint(painter: _PreviewPainter(t.id, c)),
            ),
      if (_category == _Category.all || _category == _Category.mine)
        for (final t in user)
          _Tile(
            name: t.name,
            selected: _selected == t.id,
            onTap: () => setState(() => _selected = t.id),
            onLongPress: () => _deleteTemplate(t),
            preview: CustomPaint(painter: _UserPreviewPainter(t, c, Theme.of(context).brightness)),
          ),
      if (canSave && (_category == _Category.all || _category == _Category.mine))
        _SaveTile(onTap: _saveAsTemplate),
    ];

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: 'Templates',
      explicitChildNodes: true,
      child: Container(
        width: math.min(1060, size.width - 48),
        height: math.min(720, size.height - 48),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(22), boxShadow: c.modalShadow),
        clipBehavior: Clip.antiAlias,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            width: 220,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
            decoration: BoxDecoration(color: c.menuTile, border: Border(right: BorderSide(color: c.lineSoft))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
              Padding(
                padding: const EdgeInsets.only(left: 10, bottom: 14),
                child: Semantics(
                  header: true,
                  child: Text(
                    'Templates',
                    style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 30, height: 1.1, color: c.text),
                  ),
                ),
              ),
              for (final cat in _Category.values)
                Semantics(
                  button: true,
                  selected: _category == cat,
                  label: _categoryLabels[cat],
                  excludeSemantics: true,
                  child: Material(
                    color: _category == cat ? c.sideSelected : Colors.transparent,
                    borderRadius: BorderRadius.circular(Radii.key),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Radii.key),
                      onTap: () => setState(() => _category = cat),
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _categoryLabels[cat]!,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: _category == cat ? FontWeight.w600 : FontWeight.w400,
                            color: c.text,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 18, children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      'Every template stays endless — it’s a starting layout, not a boundary.',
                      style: TextStyle(fontSize: 14, color: c.textMuted),
                    ),
                  ),
                  DialogCloseButton(onPressed: () => Navigator.of(context).pop()),
                ]),
                Expanded(
                  child: tiles.isEmpty
                      ? Center(
                          child: Text(
                            'Open a page and choose “Save as template” to keep its layout here.',
                            style: TextStyle(fontSize: 14, color: c.textMuted),
                          ),
                        )
                      : LayoutBuilder(builder: (context, box) {
                          final w = (box.maxWidth - 3 * 14) / 4;
                          return SingleChildScrollView(
                            child: Wrap(spacing: 14, runSpacing: 16, children: [
                              for (final t in tiles) SizedBox(width: w, child: t),
                            ]),
                          );
                        }),
                ),
                Container(
                  padding: const EdgeInsets.only(top: 16),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: c.lineSoft))),
                  child: Row(spacing: 16, children: [
                    Expanded(
                      child: targets.length == 1
                          ? Text('Starts a new notebook', style: TextStyle(fontSize: 14, color: c.textMuted))
                          : Semantics(
                              label: 'Use it for',
                              container: true,
                              explicitChildNodes: true,
                              child: Row(spacing: 8, children: [
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Text('Use for', style: TextStyle(fontSize: 14, color: c.textMuted)),
                                ),
                                for (final t in targets)
                                  _TargetChip(
                                    label: _targetLabels[t]!,
                                    selected: _target == t,
                                    onTap: () => setState(() => _target = t),
                                  ),
                              ]),
                            ),
                    ),
                    SecondaryButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
                    PrimaryButton(label: 'Use “${_nameOf(_selected)}”', onPressed: _busy ? null : _use),
                  ]),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.name, required this.selected, required this.onTap, required this.preview, this.onLongPress});

  final String name;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          Container(
            height: 112,
            decoration: BoxDecoration(
              border: Border.all(color: selected ? c.accent : c.line, width: selected ? 3 : 1),
              borderRadius: BorderRadius.circular(Radii.key),
            ),
            child: ClipRRect(borderRadius: BorderRadius.circular(selected ? 7 : 9), child: preview),
          ),
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
        ]),
      ),
    );
  }
}

class _SaveTile extends StatelessWidget {
  const _SaveTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'Save as template, from this page',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          DashedBorder(
            color: c.lineDashed,
            radius: Radii.key,
            width: 2,
            child: SizedBox(
              height: 112,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, spacing: 6, children: [
                EIcon(EIcons.plus, size: 22, color: c.textMuted),
                Text('From this page', style: TextStyle(fontSize: 13, color: c.textMuted)),
              ]),
            ),
          ),
          Text('Save as template', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
        ]),
      ),
    );
  }
}

class _TargetChip extends StatelessWidget {
  const _TargetChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? c.inverse : Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: selected ? c.inverse : c.lineStrong)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: selected ? c.onInverse : c.text),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.id, this.colors);

  final String id;
  final EndlessColors colors;

  @override
  void paint(Canvas canvas, Size size) => paintTemplatePreview(canvas, size, id, colors);

  @override
  bool shouldRepaint(_PreviewPainter old) => old.id != id || old.colors != colors;
}

class _UserPreviewPainter extends CustomPainter {
  _UserPreviewPainter(this.template, this.colors, this.brightness);

  final UserTemplate template;
  final EndlessColors colors;
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.surface);
    final area = (Offset.zero & size).deflate(10);
    final layout = layoutBounds(template.layout);
    final ink = InkThumb.fromPage(template.previewPage());
    var bounds = layout ?? ink?.bounds;
    if (bounds == null) return;
    if (layout != null && ink != null) bounds = bounds.expandToInclude(ink.bounds);
    final scale = math.min(area.width / bounds.width, area.height / bounds.height);
    if (layout != null) {
      final picture = layoutPicture(template.layout, colors);
      if (picture != null) {
        canvas
          ..save()
          ..translate(area.left - bounds.left * scale, area.top - bounds.top * scale)
          ..scale(scale)
          ..drawPicture(picture)
          ..restore();
      }
    }
    if (ink != null) {
      final inkArea = Rect.fromLTWH(
        area.left + (ink.bounds.left - bounds.left) * scale,
        area.top + (ink.bounds.top - bounds.top) * scale,
        ink.bounds.width * scale,
        ink.bounds.height * scale,
      );
      ink.paint(canvas, inkArea, brightness, maxScale: scale);
    }
  }

  @override
  bool shouldRepaint(_UserPreviewPainter old) => old.template != template || old.colors != colors;
}
