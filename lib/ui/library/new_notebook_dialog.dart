import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../board/model.dart' show colorFromHex, colorToHex;
import '../../library/library.dart';
import '../../state/save_location.dart';
import '../../state/settings.dart';
import '../../sync/sync_state.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart' as tokens;
import '../../theme/tokens.g.dart' show FontFamilies, Radii;
import '../common.dart';
import '../dialogs.dart';
import '../icons.dart';
import '../routes.dart';
import 'new_note_dialog.dart' show ensureCloud;
import 'widgets.dart' show FolderIcon;

// New notebook (UPDATE_04 §6, NewNotebook.dc.html): three quick choices,
// or Skip for now. Start's Notebook tile and the Library's New notebook open
// it; New note keeps its own dialog (Update 02b).
//
// Where it's saved maps onto Notebook.saveTo: This tablet with "No backup"
// is `device`; This tablet backed up to a cloud, or that cloud picked
// outright, is that cloud. (Every notebook is on the tablet first either
// way; sync keeps the cloud copy.)

/// The three choices: what's remembered by "Use these every time".
@immutable
class NotebookChoices {
  const NotebookChoices({this.folder = const [], this.place = SaveLocation.device, this.backup = false, this.cover});

  final List<String> folder;

  /// Where it lives: This tablet, Google Drive or OneDrive.
  final SaveLocation place;

  /// On this tablet: also kept in the cloud (always so for a cloud place).
  final bool backup;
  final Color? cover;

  /// The cloud that backs a notebook on this tablet up: the one that's on
  /// (Google Drive first), else Google Drive (signed in to on Create).
  static SaveLocation backupCloud(SyncSettings sync) =>
      !sync.google.active && sync.onedrive.active ? SaveLocation.onedrive : SaveLocation.google;

  /// Notebook.saveTo for these choices.
  SaveLocation saveTo(SyncSettings sync) =>
      place != SaveLocation.device ? place : (backup ? backupCloud(sync) : SaveLocation.device);

  Map<String, Object?> toJson() => {
        'folder': folder,
        'place': place.name,
        'backup': backup,
        if (cover != null) 'cover': colorToHex(cover!),
      };

  static NotebookChoices? fromJson(Object? j) {
    if (j is! Map) return null;
    final cover = j['cover'];
    return NotebookChoices(
      folder: [...?(j['folder'] as List?)?.whereType<String>()],
      place: SaveLocation.parse(j['place']) ?? SaveLocation.device,
      backup: j['backup'] == true,
      cover: cover is String ? colorFromHex(cover) : null,
    );
  }
}

extension NewNotebookSettings on AppSettings {
  /// "Use these every time and stop asking": the saved choices, or null to
  /// ask (Settings › Notebooks & pages › New notebooks).
  NotebookChoices? get notebookDefaults => NotebookChoices.fromJson(prefs['newNotebookDefaults']);
}

/// The five cover colors the prompt offers (Blue, Rust, Green, Plum, Gold).
final List<(Color, String)> _covers = [
  (tokens.coverColors[0], 'Blue'),
  (tokens.coverColors[1], 'Rust'),
  (tokens.coverColors[2], 'Green'),
  (tokens.coverColors[3], 'Plum'),
  (tokens.coverColors[5], 'Gold'),
];

/// New notebook from Start or the Library ([folder]: the one it shows). With
/// saved choices it makes the notebook at once; otherwise it asks.
Future<void> newNotebook(BuildContext context, WidgetRef ref, {List<String> folder = const []}) async {
  final saved = ref.read(settingsProvider).notebookDefaults;
  if (saved != null) {
    final id = await _make(context, ref, 'Untitled notebook', saved);
    if (id != null && context.mounted) context.push(Routes.notebook(id, page: 0));
    return;
  }
  final result = await showEndlessDialog<_Result>(context, builder: (_) => NewNotebookDialog(folder: folder));
  if (result == null || !context.mounted) return;
  context.push(Routes.notebook(result.id, page: 0));
  if (result.skipped) {
    showNote(context, 'Untitled notebook is ready. When you have a minute, open More options › Finish setting up.');
  }
}

/// Finish setting up a skipped notebook (FinishSetup.png): the same three
/// steps; Save names it, puts it in its folder and place, and drops the
/// "Not set up" tag.
Future<void> finishNotebookSetup(BuildContext context, WidgetRef ref, String notebookId) async {
  final entry = ref.read(libraryProvider).byId(notebookId);
  if (entry == null) return;
  await showEndlessDialog<_Result>(context, builder: (_) => NewNotebookDialog(finishing: entry));
}

/// Makes the notebook; a cloud that isn't on is signed in to first. Null
/// when that fails (and says why).
Future<String?> _make(BuildContext context, WidgetRef ref, String title, NotebookChoices ch) async {
  final saveTo = ch.saveTo(ref.read(syncProvider).settings);
  final kind = saveTo.cloud;
  if (kind != null) {
    final why = await ensureCloud(ref, kind);
    if (why != null) {
      if (context.mounted) await showMessage(context, title: 'Can’t connect ${kind.label}', message: why);
      return null;
    }
  }
  return ref.read(libraryProvider.notifier).createNotebook(
        title: title,
        folder: ch.folder,
        cover: ch.cover,
        saveTo: saveTo.name,
      );
}

class _Result {
  const _Result(this.id, {this.skipped = false});

  final String id;
  final bool skipped;
}

class NewNotebookDialog extends ConsumerStatefulWidget {
  const NewNotebookDialog({super.key, this.folder = const [], this.finishing});

  /// The folder the Library shows (picked to start with).
  final List<String> folder;

  /// Finish setting up this notebook instead of making one.
  final NotebookEntry? finishing;

  @override
  ConsumerState<NewNotebookDialog> createState() => _NewNotebookDialogState();
}

class _NewNotebookDialogState extends ConsumerState<NewNotebookDialog> {
  late final TextEditingController _name;
  late List<String> _folder;
  late SaveLocation _place;
  late bool _backup;
  late Color _cover;
  bool _remember = false;
  bool _busy = false;

  bool get _finishing => widget.finishing != null;

  @override
  void initState() {
    super.initState();
    final f = widget.finishing;
    final sync = ref.read(syncProvider).settings;
    if (f != null) {
      _name = TextEditingController(text: f.title == 'Untitled notebook' ? '' : f.title);
      _folder = [...f.folder];
      final at = SaveLocation.parse(f.saveTo) ?? SaveLocation.device;
      _place = at;
      _backup = at != SaveLocation.device;
      _cover = f.cover ?? _covers[0].$1;
    } else {
      _name = TextEditingController();
      _folder = [...widget.folder];
      // On this tablet, backed up when a cloud is on (as new notes are saved).
      _place = SaveLocation.device;
      _backup = defaultSaveLocation(ref.read(settingsProvider), sync) != SaveLocation.device;
      _cover = _covers[0].$1;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  NotebookChoices get _choices => NotebookChoices(folder: _folder, place: _place, backup: _backup, cover: _cover);

  String get _title {
    final t = _name.text.trim();
    return t.isEmpty ? 'Untitled notebook' : t;
  }

  Future<void> _create() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final f = widget.finishing;
      if (f != null) {
        final saveTo = _choices.saveTo(ref.read(syncProvider).settings);
        final kind = saveTo.cloud;
        if (kind != null) {
          final why = await ensureCloud(ref, kind);
          if (!mounted) return;
          if (why != null) {
            await showMessage(context, title: 'Can’t connect ${kind.label}', message: why);
            return;
          }
        }
        await ref.read(libraryProvider.notifier).finishSetup(f.id, title: _title, folder: _folder, cover: _cover, saveTo: saveTo.name);
        if (kind != null) ref.read(syncProvider.notifier).syncNow();
        if (mounted) Navigator.of(context).pop(_Result(f.id));
        return;
      }
      if (_remember) {
        ref.read(settingsProvider.notifier).apply((s) => s.withPref('newNotebookDefaults', _choices.toJson()));
      }
      final id = await _make(context, ref, _title, _choices);
      if (id != null && mounted) Navigator.of(context).pop(_Result(id));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Skip for now: "Untitled notebook" on this tablet, no folder, no
  /// backup, tagged Not set up.
  Future<void> _skip() async {
    if (_busy) return;
    setState(() => _busy = true);
    final id = await ref.read(libraryProvider.notifier).createNotebook(
          title: 'Untitled notebook',
          saveTo: SaveLocation.device.name,
          setupPending: true,
        );
    if (mounted) Navigator.of(context).pop(_Result(id, skipped: true));
  }

  Future<void> _newFolder() async {
    final name = (await showNamePrompt(context, title: 'New folder', action: 'Create', hint: 'e.g. Physics'))?.trim();
    if (name == null || name.isEmpty || !mounted) return;
    // A folder that's already there is simply picked.
    await ref.read(libraryProvider.notifier).createFolder(const [], name);
    if (mounted) setState(() => _folder = [name]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sync = ref.watch(syncProvider.select((s) => s.settings));
    final lib = ref.watch(libraryProvider);
    final cloud = _place != SaveLocation.device;
    final backedUp = cloud || _backup;
    final where = cloud ? _place : NotebookChoices.backupCloud(sync);
    final folders = [
      for (final f in lib.childrenOf(const [])) (f.path, f.name, f.color),
      // A nested folder picked (the Library was showing it) shows too.
      if (_folder.length > 1) (_folder, _folder.last, lib.folder(_folder)?.color),
    ];

    Widget step(int n, String label) => Semantics(
          header: true,
          child: Row(spacing: 10, children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.inverse, shape: BoxShape.circle),
              child: Text('$n', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.onInverse)),
            ),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.textMuted)),
          ]),
        );

    final nameRow = Container(
      height: 54,
      padding: const EdgeInsets.only(left: 16, right: 8),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.accent, width: 2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _name,
            autofocus: !_finishing,
            onChanged: (_) => setState(() {}),
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: c.text),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: 'Untitled notebook',
              hintStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: c.textFaint),
              semanticCounterText: '',
            ),
          ),
        ),
        Semantics(
          label: 'Cover color',
          container: true,
          explicitChildNodes: true,
          child: Row(children: [
            for (final (color, name) in _covers)
              Semantics(
                inMutuallyExclusiveGroup: true,
                checked: _cover == color,
                button: true,
                label: name,
                excludeSemantics: true,
                child: InkResponse(
                  radius: 20,
                  onTap: () => setState(() => _cover = color),
                  child: SizedBox(
                    width: 32,
                    height: 44,
                    child: Center(
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: displayInk(color, Theme.of(context).brightness),
                          shape: BoxShape.circle,
                          boxShadow: _cover == color
                              ? [BoxShadow(color: color, spreadRadius: 4), BoxShadow(color: c.surface, spreadRadius: 2)]
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );

    Widget folderChip(List<String> path, String label, Color? color) {
      final on = listEquals(_folder, path);
      return Semantics(
        inMutuallyExclusiveGroup: true,
        checked: on,
        button: true,
        label: path.isEmpty ? 'No folder' : '$label folder',
        excludeSemantics: true,
        child: Material(
          color: on ? c.accentWash : c.surface,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: on ? c.accent : c.line, width: on ? 2 : 1),
            borderRadius: BorderRadius.circular(Radii.key),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.key),
            onTap: () => setState(() => _folder = path),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(mainAxisSize: MainAxisSize.min, spacing: 7, children: [
                FolderIcon(color: color ?? c.textFaint, size: 18),
                Text(label, style: TextStyle(fontSize: 14, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: c.text)),
              ]),
            ),
          ),
        ),
      );
    }

    Widget placeCard(SaveLocation p) {
      final on = _place == p;
      final kind = p.cloud;
      final connected = kind == null || sync.of(kind).active;
      final (label, note, icon, tint) = switch (p) {
        SaveLocation.device => ('This tablet', 'Works offline', EIcons.tablet, c.text),
        SaveLocation.google => ('Google Drive', connected ? 'Connected' : 'Sign in first', EIcons.cloud, c.green),
        SaveLocation.onedrive => ('OneDrive', connected ? 'Connected' : 'Sign in first', EIcons.cloud, c.accent),
      };
      return Semantics(
        inMutuallyExclusiveGroup: true,
        checked: on,
        button: true,
        label: '$label, $note',
        excludeSemantics: true,
        child: Material(
          color: on ? c.accentWash : c.surface,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: on ? c.accent : c.line, width: on ? 2 : 1),
            borderRadius: BorderRadius.circular(Radii.button),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.button),
            onTap: () => setState(() {
              _place = p;
              // A cloud is always backed up; back to the tablet keeps the switch.
              if (p != SaveLocation.device) _backup = true;
            }),
            child: Container(
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(spacing: 10, children: [
                EIcon(icon, color: tint),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text)),
                    Text(note, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: connected ? c.textMuted : c.clayDeep)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    final (bkTitle, bkNote) = cloud
        ? ('Already backed up in ${where.label}', 'Saved there as you write, with 30 days of version history.')
        : _backup
            ? ('Back up to ${where.label}', 'A copy is saved there every few minutes. You keep working offline.')
            : ('No backup', 'Only on this tablet. If the tablet is lost or reset, this notebook is gone.');
    final backupCard = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: backedUp ? c.greenTint : c.clayTint,
        border: Border.all(color: backedUp ? c.greenLine : c.clayLine),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(spacing: 14, children: [
        EIcon(backedUp ? EIcons.shieldCheck : EIcons.shieldWarn, size: 22, color: backedUp ? c.green : c.clay),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            Text(bkTitle, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
            Text(bkNote, style: TextStyle(fontSize: 13, color: c.textMuted)),
          ]),
        ),
        Semantics(
          label: 'Back up this notebook',
          toggled: backedUp,
          enabled: !cloud,
          excludeSemantics: true,
          child: Switch(
            value: backedUp,
            activeThumbColor: c.surface,
            activeTrackColor: c.green,
            inactiveThumbColor: c.surface,
            inactiveTrackColor: c.switchOff,
            trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
            onChanged: cloud ? null : (v) => setState(() => _backup = v),
          ),
        ),
      ]),
    );

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: _finishing ? 'Finish setting up' : 'New notebook',
      explicitChildNodes: true,
      child: Container(
        width: 680,
        padding: const EdgeInsets.fromLTRB(26, 22, 26, 20),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(22), boxShadow: c.modalShadow),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 18, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
                  Text(
                    _finishing ? 'Finish setting up' : 'New notebook',
                    style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 30, height: 1.2, color: c.text),
                  ),
                  Text(
                    _finishing
                        ? 'This notebook was made in a hurry. Give it a name, a home and a backup.'
                        : 'Three quick choices. In a rush? Skip and start writing.',
                    style: TextStyle(fontSize: 14, color: c.textMuted),
                  ),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: c.side, borderRadius: BorderRadius.circular(999)),
                child: Text('About 10 seconds', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.textMuted)),
              ),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [step(1, 'Name it'), nameRow]),
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
              step(2, 'Where should it live?'),
              // Wraps on a narrow screen (portrait).
              Wrap(spacing: 6, runSpacing: 6, children: [
                folderChip(const [], 'No folder', null),
                for (final (path, name, color) in folders) folderChip(path, name, color),
                ChromeButton(
                  label: 'New folder',
                  height: 44,
                  onPressed: _newFolder,
                  child: DashedBorder(
                    color: c.lineDashed,
                    radius: Radii.key,
                    child: SizedBox(width: 44, height: 44, child: Center(child: EIcon(EIcons.plus, size: 16, color: c.textMuted))),
                  ),
                ),
              ]),
              const SizedBox(height: 2),
              Row(spacing: 6, children: [for (final p in SaveLocation.values) Expanded(child: placeCard(p))]),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [step(3, 'Back it up?'), backupCard]),
            Container(
              padding: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: c.lineSoft))),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 8,
                children: [
                  if (!_finishing)
                    Semantics(
                      checked: _remember,
                      label: 'Use these every time and stop asking',
                      excludeSemantics: true,
                      child: InkWell(
                        onTap: () => setState(() => _remember = !_remember),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 44),
                          child: Row(mainAxisSize: MainAxisSize.min, spacing: 9, children: [
                            Checkbox(
                              value: _remember,
                              onChanged: (v) => setState(() => _remember = v ?? false),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                            Text('Use these every time and stop asking', style: TextStyle(fontSize: 13, color: c.textMuted)),
                          ]),
                        ),
                      ),
                    )
                  else
                    const SizedBox(),
                  DialogActions(children: [
                    if (!_finishing) _SkipButton(onPressed: _busy ? null : _skip),
                    if (_finishing) SecondaryButton(label: 'Cancel', height: 48, onPressed: () => Navigator.of(context).pop()),
                    PrimaryButton(
                      label: _finishing ? 'Save' : 'Create notebook',
                      height: 48,
                      onPressed: _busy ? null : _create,
                    ),
                  ]),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// "Skip for now" with "set up later from ⋯" under it.
class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'Skip for now. Set up later from More options',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(side: BorderSide(color: c.lineStrong), borderRadius: BorderRadius.circular(Radii.button)),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.button),
          onTap: onPressed,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('Skip for now', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
              // ⋯ isn't in Figtree: the ⋯ button's own icon.
              Row(mainAxisSize: MainAxisSize.min, spacing: 3, children: [
                Text('set up later from', style: TextStyle(fontSize: 11, color: c.textMuted)),
                EIcon(EIcons.more, size: 12, color: c.textMuted),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
