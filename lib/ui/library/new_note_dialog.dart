import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../board/model.dart' show Paper, colorToHex, colorFromHex;
import '../../library/library.dart';
import '../../state/save_location.dart';
import '../../state/settings.dart';
import '../../sync/cloud.dart';
import '../../sync/sync_state.dart';
import '../../templates/templates.dart' show TemplateTarget;
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart' as tokens;
import '../../theme/tokens.g.dart' show FontFamilies, Radii;
import '../dialogs.dart';
import '../icons.dart';
import '../routes.dart';
import '../templates/templates_dialog.dart';

/// New note (Start and the Library). With Settings › Notebooks & pages ›
/// "Use my defaults" it skips the dialog and makes the note at once in the
/// default folder (or [folder], the one the Library shows), place and paper.
Future<void> newNote(BuildContext context, WidgetRef ref, {List<String> folder = const []}) async {
  final s = ref.read(settingsProvider);
  if (!s.askNewNote) {
    final id = await ref.read(libraryProvider.notifier).createNotebook(
          title: 'Untitled note',
          folder: folder.isNotEmpty ? folder : s.defaultFolder,
          paper: s.defaultPaper,
          cover: _defaultCover(s),
          saveTo: defaultSaveLocation(s, ref.read(syncProvider).settings).name,
        );
    if (context.mounted) context.push(Routes.notebook(id, page: 0));
    return;
  }
  final id = await showEndlessDialog<String>(context, builder: (_) => NewNoteDialog(folder: folder.isNotEmpty ? folder : s.defaultFolder));
  if (id != null && context.mounted) context.push(Routes.notebook(id, page: 0));
}

Color? _defaultCover(AppSettings s) {
  final hex = s.prefs['defaultCover'];
  return hex is String ? colorFromHex(hex) : null;
}

/// The New note dialog (NewNote.png): name, folder (with New folder), where
/// it's saved, paper and cover, what it will be saved as, and "Make these my
/// defaults". Pops the new notebook's id.
class NewNoteDialog extends ConsumerStatefulWidget {
  const NewNoteDialog({super.key, this.folder = const []});

  final List<String> folder;

  @override
  ConsumerState<NewNoteDialog> createState() => _NewNoteDialogState();
}

class _NewNoteDialogState extends ConsumerState<NewNoteDialog> {
  final _name = TextEditingController();
  final _newFolder = TextEditingController();
  late List<String> _folder = widget.folder;
  late SaveLocation _place;
  late Paper _paper;
  late Color _cover;
  bool _remember = false;
  bool _adding = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _place = defaultSaveLocation(s, ref.read(syncProvider).settings);
    _paper = s.defaultPaper;
    _cover = _defaultCover(s) ?? tokens.noteCovers.first;
    // A folder that's gone (renamed, deleted) isn't offered.
    final folders = ref.read(libraryProvider).folders;
    if (_folder.isNotEmpty && !folders.any((f) => f.key == folderKey(_folder))) _folder = const [];
  }

  @override
  void dispose() {
    _name.dispose();
    _newFolder.dispose();
    super.dispose();
  }

  Future<void> _addFolder() async {
    final name = _newFolder.text.trim();
    if (name.isEmpty) {
      setState(() => _adding = false);
      return;
    }
    final ok = await ref.read(libraryProvider.notifier).createFolder(_folder, name);
    if (!mounted) return;
    setState(() {
      _adding = false;
      _newFolder.clear();
      if (ok) _folder = [..._folder, name];
    });
  }

  Future<void> _create() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // A cloud that isn't connected (or is off) is signed in to first.
      final kind = _place.cloud;
      if (kind != null) {
        final why = await ensureCloud(ref, kind);
        if (!mounted) return;
        if (why != null) {
          await showMessage(context, title: 'Can’t connect ${kind.label}', message: why);
          return;
        }
      }
      final s = ref.read(settingsProvider);
      if (_remember) {
        ref.read(settingsProvider.notifier).apply((st) => st
            .withPref('defaultFolder', _folder)
            .withPref('saveNewTo', _place.name)
            .withPref('defaultPaper', _paper.name)
            .withPref('defaultCover', colorToHex(_cover)));
      }
      final name = _name.text.trim();
      final id = await ref.read(libraryProvider.notifier).createNotebook(
            title: name.isEmpty ? 'Untitled note' : name,
            folder: _folder,
            paper: _paper,
            cover: _cover,
            saveTo: _place.name,
          );
      if (s.saveNewTo == null && !_remember) {
        // Nothing to remember; the default stays as it was.
      }
      if (mounted) Navigator.of(context).pop(id);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _template() async {
    Navigator.of(context).pop();
    await showTemplatesDialog(context, target: TemplateTarget.newNotebook, folder: _folder);
  }

  String _path(SyncSettings sync) {
    final root = switch (_place) {
      SaveLocation.device => 'This tablet',
      SaveLocation.google => 'Google Drive › ${sync.google.folder}',
      SaveLocation.onedrive => 'OneDrive › ${sync.onedrive.folder}',
    };
    final name = _name.text.trim().isEmpty ? 'Untitled note' : _name.text.trim();
    return [root, ..._folder, name].join(' › ');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sync = ref.watch(syncProvider.select((s) => s.settings));

    Widget label(String text) => Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.inverseRaised));

    final left = Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        label('Name'),
        Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(border: Border.all(color: c.accent, width: 1.5), borderRadius: BorderRadius.circular(Radii.button)),
          child: Row(spacing: 10, children: [
            Expanded(
              child: TextField(
                controller: _name,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _create(),
                textInputAction: TextInputAction.done,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: c.text),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Untitled note',
                  hintStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: c.textFaint),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            EIcon(EIcons.edit, size: 18, color: c.textFaint),
          ]),
        ),
        Text('Write it with the S Pen or type. You can rename it any time.', style: TextStyle(fontSize: 12, color: c.textMuted)),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        Row(children: [
          Expanded(child: label('Folder')),
          _LinkButton(label: 'New folder', icon: EIcons.plus, onTap: () => setState(() => _adding = true)),
        ]),
        _FolderTree(
          selected: _folder,
          onPick: (f) => setState(() => _folder = f),
          adding: _adding,
          newFolder: _newFolder,
          onAdd: _addFolder,
        ),
      ]),
    ]);

    final right = Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        label('Save to'),
        SaveToChoice(selected: _place, onPick: (p) => setState(() => _place = p)),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        Row(children: [
          Expanded(child: label('Paper')),
          _LinkButton(label: 'Use a template…', onTap: _template),
        ]),
        Semantics(
          container: true,
          label: 'Paper',
          explicitChildNodes: true,
          child: Row(spacing: 6, children: [
            for (final (p, name) in const [(Paper.dots, 'Dots'), (Paper.lines, 'Lines'), (Paper.grid, 'Grid'), (Paper.blank, 'Blank')])
              Expanded(child: _PaperTile(paper: p, label: name, on: _paper == p, onTap: () => setState(() => _paper = p))),
          ]),
        ),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        label('Cover color'),
        Semantics(
          container: true,
          label: 'Cover color',
          explicitChildNodes: true,
          child: Row(spacing: 2, children: [
            for (final (i, col) in tokens.noteCovers.indexed)
              _CoverDot(
                color: col,
                label: '${_coverNames[i]} cover',
                on: col == _cover,
                onTap: () => setState(() => _cover = col),
              ),
          ]),
        ),
      ]),
    ]);

    final brightness = Theme.of(context).brightness;
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: 'New note',
      explicitChildNodes: true,
      child: Container(
        width: 860,
        padding: const EdgeInsets.fromLTRB(26, 22, 26, 20),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(22), boxShadow: c.modalShadow),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 18, children: [
            Row(children: [
              Expanded(child: Text('New note', style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 30, height: 1.2, color: c.text))),
              DialogCloseButton(onPressed: () => Navigator.of(context).pop()),
            ]),
            Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 26, children: [
              Expanded(child: left),
              SizedBox(width: 360, child: right),
            ]),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: c.menuTile, borderRadius: BorderRadius.circular(Radii.button)),
              child: Row(spacing: 12, children: [
                Container(
                  width: 6,
                  height: 30,
                  decoration: BoxDecoration(color: displayInk(_cover, brightness), borderRadius: BorderRadius.circular(3)),
                ),
                Expanded(
                  child: Semantics(
                    label: 'Will be saved as ${_path(sync)}',
                    excludeSemantics: true,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                      Text('Will be saved as', style: TextStyle(fontSize: 12, color: c.textMuted)),
                      Text(_path(sync),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
                    ]),
                  ),
                ),
                Semantics(
                  checked: _remember,
                  label: 'Make these my defaults',
                  excludeSemantics: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Radii.small),
                    onTap: () => setState(() => _remember = !_remember),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
                        SizedBox.square(
                          dimension: 18,
                          child: Checkbox(
                            value: _remember,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            onChanged: (v) => setState(() => _remember = v ?? false),
                          ),
                        ),
                        Text('Make these my defaults', style: TextStyle(fontSize: 13, color: c.inverseRaised)),
                      ]),
                    ),
                  ),
                ),
              ]),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 10, children: [
              SecondaryButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
              PrimaryButton(label: _busy ? 'Creating…' : 'Create note', icon: EIcons.plus, onPressed: _busy ? null : _create),
            ]),
          ]),
        ),
      ),
    );
  }
}

const _coverNames = ['Blue', 'Terracotta', 'Green', 'Plum', 'Teal', 'Amber', 'Pink', 'Graphite'];

/// Signs in to [kind] if it isn't connected, and turns it on if it's off.
/// Returns why it can't, or null.
Future<String?> ensureCloud(WidgetRef ref, CloudKind kind) async {
  final c = ref.read(syncProvider).settings.of(kind);
  if (c.active) return null;
  return ref.read(syncProvider.notifier).setOn(kind, true);
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.onTap, this.icon});

  final String label;
  final VoidCallback onTap;
  final EIconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
              if (icon != null) EIcon(icon!, size: 14, color: c.accent),
              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.accent)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Every folder as a tree, with counts, the chosen one ticked, and the New
/// folder field under it.
class _FolderTree extends ConsumerWidget {
  const _FolderTree({required this.selected, required this.onPick, required this.adding, required this.newFolder, required this.onAdd});

  final List<String> selected;
  final ValueChanged<List<String>> onPick;
  final bool adding;
  final TextEditingController newFolder;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final lib = ref.watch(libraryProvider);
    final brightness = Theme.of(context).brightness;
    // Parents before children, in the order they were made.
    final folders = [...lib.folders]..sort((a, b) {
        for (var i = 0; i < a.path.length && i < b.path.length; i++) {
          if (a.path[i] != b.path[i]) {
            final ia = lib.folders.indexWhere((f) => f.path.length == 1 && f.path.first == a.path.first);
            final ib = lib.folders.indexWhere((f) => f.path.length == 1 && f.path.first == b.path.first);
            if (i == 0 && ia != ib) return ia.compareTo(ib);
            return a.path[i].toLowerCase().compareTo(b.path[i].toLowerCase());
          }
        }
        return a.path.length.compareTo(b.path.length);
      });
    int count(List<String> path) => lib.active.where((n) => isInside(n.folder, path)).length;
    final sel = folderKey(selected);

    Widget row(List<String> path, String name, Color color, int depth) {
      final on = folderKey(path) == sel;
      final n = path.isEmpty ? null : count(path);
      return Semantics(
        inMutuallyExclusiveGroup: true,
        checked: on,
        button: true,
        label: path.isEmpty ? 'No folder' : 'Folder $name',
        excludeSemantics: true,
        child: Material(
          color: on ? c.accentTint : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onPick(path),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: EdgeInsets.only(left: 12.0 + depth * 26, right: 12),
              child: Row(spacing: 10, children: [
                _FolderIcon(color: displayInk(color, brightness)),
                Expanded(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: c.text)),
                ),
                if (n != null) Text('$n', style: TextStyle(fontSize: 12, color: c.textMuted)),
                if (on) EIcon(EIcons.checkBold, size: 18, color: c.accent),
              ]),
            ),
          ),
        ),
      );
    }

    final parentName = selected.isEmpty ? 'the top level' : selected.last;
    return Container(
      height: 296,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: c.surfaceSunk, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(Radii.card)),
      child: Semantics(
        container: true,
        label: 'Folder',
        explicitChildNodes: true,
        child: ListView(padding: EdgeInsets.zero, children: [
          row(const [], 'No folder', c.textFaint, 0),
          for (final f in folders) ...[
            row(f.path, f.name, f.color, f.path.length - 1),
            if (adding && folderKey(f.path) == sel) _NewFolderField(controller: newFolder, parent: parentName, depth: f.path.length, onAdd: onAdd),
          ],
          if (adding && selected.isEmpty) _NewFolderField(controller: newFolder, parent: parentName, depth: 0, onAdd: onAdd),
        ]),
      ),
    );
  }
}

class _NewFolderField extends StatelessWidget {
  const _NewFolderField({required this.controller, required this.parent, required this.depth, required this.onAdd});

  final TextEditingController controller;
  final String parent;
  final int depth;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      margin: const EdgeInsets.only(top: 1),
      padding: EdgeInsets.only(left: 12.0 + depth * 26, right: 6),
      decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.accent, width: 1.5), borderRadius: BorderRadius.circular(10)),
      child: Row(spacing: 8, children: [
        _FolderIcon(color: c.accent, filled: false),
        Expanded(
          child: TextField(
            controller: controller,
            autofocus: true,
            onSubmitted: (_) => onAdd(),
            style: TextStyle(fontSize: 15, color: c.text),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: 'New folder in $parent',
              hintStyle: TextStyle(fontSize: 15, color: c.textFaint),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        Semantics(
          button: true,
          label: 'Add folder',
          excludeSemantics: true,
          child: Material(
            color: c.accent,
            borderRadius: BorderRadius.circular(Radii.small),
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.small),
              onTap: onAdd,
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                child: Text('Add', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.onAccent)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _FolderIcon extends StatelessWidget {
  const _FolderIcon({required this.color, this.filled = true});

  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 20,
        child: Stack(children: [
          if (filled) Positioned.fill(child: EIcon(EIcons.folderFill, size: 20, color: color.withValues(alpha: 0.16))),
          Positioned.fill(child: EIcon(EIcons.folder, size: 20, color: color)),
        ]),
      );
}

/// The three places a notebook can be saved, as radio cards (NewNote.png).
class SaveToChoice extends ConsumerWidget {
  const SaveToChoice({super.key, required this.selected, required this.onPick});

  final SaveLocation selected;
  final ValueChanged<SaveLocation> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final sync = ref.watch(syncProvider.select((s) => s.settings));
    String sub(SaveLocation p) {
      final kind = p.cloud;
      if (kind == null) return 'Not backed up';
      final setting = sync.of(kind);
      if (!setting.connected) return 'Not connected · you’ll sign in first';
      if (!setting.on) return 'Turned off · it’s turned on first';
      return '${setting.folder} folder · connected';
    }

    return Semantics(
      container: true,
      label: 'Save to',
      explicitChildNodes: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        for (final p in SaveLocation.values)
          () {
            final on = p == selected;
            final warn = p.cloud != null && !sync.of(p.cloud!).active;
            final (tint, ic, icon) = switch (p) {
              SaveLocation.device => (c.side, c.inverseRaised, EIcons.tablet),
              SaveLocation.google => (c.greenTint, c.greenDeep, EIcons.cloudCheck),
              SaveLocation.onedrive => (c.accentTint, c.accent, EIcons.cloud),
            };
            return Semantics(
              inMutuallyExclusiveGroup: true,
              checked: on,
              button: true,
              label: '${p.label}. ${sub(p)}',
              excludeSemantics: true,
              child: Material(
                color: on ? c.accentWash : c.surface,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: on ? c.accent : c.cardLine, width: on ? 2 : 1),
                  borderRadius: BorderRadius.circular(Radii.button),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(Radii.button),
                  onTap: () => onPick(p),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 58),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(spacing: 12, children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(Radii.key)),
                        child: Center(child: EIcon(icon, size: 20, color: ic)),
                      ),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                          Text(p.label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                          Text(sub(p), style: TextStyle(fontSize: 12, color: warn ? c.clayDeep : c.textMuted)),
                        ]),
                      ),
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: on ? c.accent : c.lineDashed, width: on ? 6 : 2),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            );
          }(),
      ]),
    );
  }
}

class _PaperTile extends StatelessWidget {
  const _PaperTile({required this.paper, required this.label, required this.on, required this.onTap});

  final Paper paper;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: on,
      button: true,
      label: '$label paper',
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: on ? c.accent : c.cardLine, width: on ? 2 : 1),
          borderRadius: BorderRadius.circular(Radii.key),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.key),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(spacing: 4, children: [
              Container(
                width: 52,
                height: 40,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: c.bg, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(4)),
                child: CustomPaint(painter: _MiniPaper(paper, paper == Paper.lines ? c.paperLine : c.dot)),
              ),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: c.text)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _MiniPaper extends CustomPainter {
  _MiniPaper(this.paper, this.color);

  final Paper paper;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    switch (paper) {
      case Paper.dots:
        for (var y = 4.0; y < size.height; y += 8) {
          for (var x = 4.0; x < size.width; x += 8) {
            canvas.drawCircle(Offset(x, y), 1, p);
          }
        }
      case Paper.lines:
        for (var y = 7.5; y < size.height; y += 8) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
      case Paper.grid:
        for (var y = 0.5; y < size.height; y += 8) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
        for (var x = 0.5; x < size.width; x += 8) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
        }
      case Paper.blank:
        break;
    }
  }

  @override
  bool shouldRepaint(_MiniPaper old) => old.paper != paper || old.color != color;
}

class _CoverDot extends StatelessWidget {
  const _CoverDot({required this.color, required this.label, required this.on, required this.onTap});

  final Color color;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = displayInk(color, Theme.of(context).brightness);
    final dot = Container(width: 26, height: 26, decoration: BoxDecoration(color: shown, shape: BoxShape.circle));
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: on,
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.button),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 44,
          child: Center(
            child: on
                ? Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: c.surface, border: Border.all(color: shown, width: 2)),
                    child: dot,
                  )
                : dot,
          ),
        ),
      ),
    );
  }
}

/// The library menu's "Save to…": where notebook [n] is saved. A cloud that
/// isn't connected is signed in to first.
Future<void> showSaveTo(BuildContext context, WidgetRef ref, NotebookEntry n) async {
  final picked = await showEndlessDialog<SaveLocation>(context, builder: (_) => _SaveToDialog(entry: n));
  if (picked == null || !context.mounted) return;
  final kind = picked.cloud;
  if (kind != null) {
    final why = await ensureCloud(ref, kind);
    if (why != null) {
      if (context.mounted) await showMessage(context, title: 'Can’t connect ${kind.label}', message: why);
      return;
    }
  }
  await ref.read(libraryProvider.notifier).setSaveTo(n.id, picked.name);
  // It goes there now.
  ref.read(syncProvider.notifier).syncNow();
}

class _SaveToDialog extends ConsumerStatefulWidget {
  const _SaveToDialog({required this.entry});

  final NotebookEntry entry;

  @override
  ConsumerState<_SaveToDialog> createState() => _SaveToDialogState();
}

class _SaveToDialogState extends ConsumerState<_SaveToDialog> {
  late SaveLocation _place = SaveLocation.parse(widget.entry.saveTo) ??
      defaultSaveLocation(ref.read(settingsProvider), ref.read(syncProvider).settings);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final before = widget.entry.saveTo == null;
    return DialogFrame(
      title: 'Save “${widget.entry.title}” to',
      width: 480,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
        Text(
          before
              ? 'Now it goes to every cloud that’s on. Pick one place, and it only goes there.'
              : 'It only goes to the place you pick. A copy already in another cloud stays there.',
          style: TextStyle(fontSize: 14, color: c.textMuted),
        ),
        SaveToChoice(selected: _place, onPick: (p) => setState(() => _place = p)),
        Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 10, children: [
          SecondaryButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
          PrimaryButton(label: 'Save here', onPressed: () => Navigator.of(context).pop(_place)),
        ]),
      ]),
    );
  }
}
