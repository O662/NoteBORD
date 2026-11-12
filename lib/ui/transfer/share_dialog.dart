import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../canvas/pane.dart';
import '../../library/library.dart';
import '../../state/notebook.dart';
import '../../sync/cloud.dart' show CloudKind;
import '../../sync/sync_state.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../../transfer/files.dart';
import '../../transfer/pdf_export.dart';
import '../../transfer/share.dart';
import '../../transfer/transfer.dart';
import '../calendar/calendar_widgets.dart' show Segmented;
import '../canvas/page_bar.dart' show pageTitle;
import '../common.dart' show DashedBorder;
import '../dialogs.dart';
import '../icons.dart';
import '../library/format.dart' show folderLabel;

// Share a copy (design/screens/Share.png, Update 04): This page · Notebook
// · Folder; as a PDF, a board file or an image (This page only); sent with
// the share sheet, saved to Google Drive or OneDrive ("Shared copies" in
// Endless's folder there), or saved on the tablet through the system's file
// picker. Pages with a password are never in a copy, and the dialog says
// which are left out. Inviting people needs a server, so it's a "Coming
// later" card (docs/SPEC.md, "Later").

Future<void> showShareDialog(BuildContext context, Pane pane) =>
    showEndlessDialog<void>(context, builder: (_) => ShareDialog(pane: pane));

/// Where a copy goes.
enum ShareDest {
  sheet('Share sheet', 'Gmail, Messages, Bluetooth and other apps on your tablet.', 'Share…'),
  drive('Google Drive', 'Saved to your Drive, in Shared copies. Share it from Drive; Google keeps it secure.', 'Save to Drive'),
  onedrive('OneDrive', 'Saved to your OneDrive, in Shared copies. Share it from OneDrive; Microsoft keeps it secure.',
      'Save to OneDrive'),
  tablet('Save to tablet', 'You pick where on the tablet, such as Downloads.', 'Save');

  const ShareDest(this.label, this.note, this.action);

  final String label;
  final String note;

  /// The main button.
  final String action;

  CloudKind? get cloud => switch (this) {
        drive => CloudKind.google,
        onedrive => CloudKind.onedrive,
        _ => null,
      };
}

class ShareDialog extends ConsumerStatefulWidget {
  const ShareDialog({super.key, required this.pane});

  final Pane pane;

  @override
  ConsumerState<ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends ConsumerState<ShareDialog> {
  var _scope = ShareScope.notebook;
  var _format = ExportFormat.pdf;
  var _dest = ShareDest.sheet;
  bool _searchable = true;
  bool _background = true;
  bool _media = false;
  bool _busy = false;
  String? _status;
  Future<int>? _size;
  (ShareScope, ExportFormat, bool)? _sizedFor;

  Pane get pane => widget.pane;

  String _scopeLabel(ShareScope s) => switch (s) {
        ShareScope.page => 'This page',
        ShareScope.notebook => 'Notebook',
        ShareScope.folder => 'Folder',
      };

  void _pickScope(ShareScope s) => setState(() {
        _scope = s;
        // A picture is of one page.
        if (s != ShareScope.page && _format == ExportFormat.image) _format = ExportFormat.pdf;
        _status = null;
      });

  /// What's left out, in words (the yellow note), or null.
  String? _lockedNote(NotebookState nb, LibraryState lib) {
    switch (_scope) {
      case ShareScope.page:
        final page = nb.pageAt(pane.page);
        if (nb.lockFor(page.id) == null && !nb.isSealed(page.id)) return null;
        return 'This page is locked, so it can’t be shared.';
      case ShareScope.notebook:
        final ok = shareablePageIds(nb);
        final locked = [
          for (var i = 0; i < nb.pages.length; i++)
            if (!ok.contains(nb.pages[i].id)) (i + 1, nb.isSealed(nb.pages[i].id) ? null : pageTitle(nb.pages[i].page)),
        ];
        if (locked.isEmpty) return null;
        if (locked.length == 1) {
          final (n, title) = locked.single;
          return 'Page $n${title == null || title == 'Untitled page' ? '' : ' ($title)'} is locked, so it won’t be included.';
        }
        final nums = [for (final (n, _) in locked) '$n'];
        final shown = nums.length > 4 ? '${nums.take(3).join(', ')} and ${nums.length - 3} more' : '${nums.sublist(0, nums.length - 1).join(', ')} and ${nums.last}';
        return 'Pages $shown are locked, so they won’t be included.';
      case ShareScope.folder:
        final folder = lib.byId(pane.notebookId)?.folder ?? const <String>[];
        if (folder.isEmpty) return null;
        var books = 0, pages = 0;
        for (final n in lib.active.where((n) => isInside(n.folder, folder))) {
          if (n.locked) {
            books++;
          } else {
            pages += n.id == pane.notebookId ? nb.pages.length - shareablePageIds(nb).length : n.lockedPages;
          }
        }
        if (books + pages == 0) return null;
        final parts = [
          if (books > 0) books == 1 ? '1 notebook' : '$books notebooks',
          if (pages > 0) pages == 1 ? '1 page' : '$pages pages',
        ];
        return '${parts.join(' and ')} ${books + pages == 1 ? 'is' : 'are'} locked, so ${books + pages == 1 ? 'it won’t' : 'they won’t'} be included.';
    }
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _status = switch (_format) {
        ExportFormat.pdf => 'Making the PDF…',
        ExportFormat.board => 'Packing the board file…',
        ExportFormat.image => 'Making a picture of this page…',
      };
    });
    try {
      final copies = await ref.read(transfersProvider).shareCopies(
            pane.notebookId,
            _scope,
            _format,
            current: pane.page,
            pdf: PdfOptions(searchable: _searchable, background: _background),
            media: _media,
          );
      final files = ref.read(fileTransferProvider);
      final what = copies.files.length == 1 ? copies.files.single.name : '${copies.files.length} files';
      String done;
      switch (_dest) {
        case ShareDest.sheet:
          await files.shareAll([for (final f in copies.files) (name: f.name, bytes: f.bytes, mime: f.mime)]);
          done = 'Shared $what';
        case ShareDest.drive || ShareDest.onedrive:
          if (mounted) setState(() => _status = 'Saving to ${_dest.label}…');
          final why = await ref
              .read(syncProvider.notifier)
              .saveSharedCopies(_dest.cloud!, [for (final f in copies.files) (name: f.name, bytes: f.bytes)]);
          if (why != null) throw ExportProblem('Couldn’t save to ${_dest.label}: $why');
          done = 'Saved $what to ${_dest.label} › ${SyncController.sharedCopiesFolder}';
        case ShareDest.tablet:
          var saved = 0;
          for (final f in copies.files) {
            if (await files.save(f.name, f.bytes, f.mime)) saved++;
          }
          if (saved == 0) {
            if (mounted) setState(() => _busy = false);
            return;
          }
          done = saved == 1 ? 'Saved ${copies.files.first.name}' : 'Saved $saved files';
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      pane.toast(copies.leftOutNote == null ? done : '$done · ${copies.leftOutNote}');
    } on ExportProblem catch (e) {
      if (mounted) _failed(e.message);
    } on Object catch (e, st) {
      debugPrint('Share failed: $e\n$st');
      if (mounted) _failed('Couldn’t make the copy: $e');
    }
  }

  void _failed(String message) => setState(() {
        _busy = false;
        _status = message;
      });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lib = ref.watch(libraryProvider);
    final nb = ref.watch(notebookProvider(pane.notebookId));
    final folder = lib.byId(pane.notebookId)?.folder ?? const <String>[];
    final locked = _lockedNote(nb, lib);
    final blocked = _scope == ShareScope.page && locked != null ||
        _scope == ShareScope.folder && folder.isEmpty ||
        _scope == ShareScope.notebook && shareablePageIds(nb).isEmpty;

    final key = (_scope, _format, _media);
    if (_sizedFor != key) {
      _sizedFor = key;
      _size = ref.read(transfersProvider).estimateShare(pane.notebookId, _scope, _format, current: pane.page, media: _media);
    }
    final what = switch (_scope) {
      ShareScope.page => pageTitle(nb.pageAt(pane.page).page),
      ShareScope.notebook => '${nb.notebook.title} · ${shareablePageIds(nb).length == 1 ? '1 page' : '${shareablePageIds(nb).length} pages'}',
      ShareScope.folder when folder.isEmpty => 'This notebook isn’t in a folder',
      ShareScope.folder => () {
          final n = lib.active.where((e) => isInside(e.folder, folder) && !e.locked).length;
          return '${folderLabel(folder)} · ${n == 1 ? '1 notebook' : '$n notebooks'}';
        }(),
    };

    Widget section(String label, Widget child) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          Text(label.toUpperCase(), style: TypeScale.sectionLabel.copyWith(color: c.textMuted)),
          child,
        ]);

    final options = switch (_format) {
      ExportFormat.pdf => [
          ('Make handwriting searchable', 'Recommended', _searchable, (bool v) => _searchable = v),
          ('Include the dot paper background', '', _background, (bool v) => _background = v),
        ],
      ExportFormat.board => [('Include audio and video', 'Bigger file', _media, (bool v) => _media = v)],
      ExportFormat.image => [('Include the dot paper background', '', _background, (bool v) => _background = v)],
    };

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: 'Share a copy',
      explicitChildNodes: true,
      child: Container(
        width: 660,
        padding: const EdgeInsets.fromLTRB(26, 22, 26, 20),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(22), boxShadow: c.modalShadow),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 10,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, spacing: 2, children: [
                  Semantics(
                    header: true,
                    child: Text('Share a copy', style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 28, color: c.text)),
                  ),
                  Text('Send it as a file anyone can open.', style: TextStyle(fontSize: 13, color: c.textMuted)),
                ]),
                Row(mainAxisSize: MainAxisSize.min, spacing: 12, children: [
                  Segmented<ShareScope>(
                    values: ShareScope.values,
                    labels: [for (final s in ShareScope.values) _scopeLabel(s)],
                    value: _scope,
                    label: 'What to share',
                    height: 44,
                    fontSize: 13,
                    onChanged: _pickScope,
                  ),
                  DialogCloseButton(onPressed: () => Navigator.of(context).pop()),
                ]),
              ],
            ),
            section(
              'As a',
              IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
                for (final f in ExportFormat.values)
                  Expanded(
                    child: _FormatCard(
                      format: f,
                      selected: _format == f,
                      enabled: f != ExportFormat.image || _scope == ShareScope.page,
                      onTap: () => setState(() {
                        _format = f;
                        _status = null;
                      }),
                    ),
                  ),
                ]),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(14)),
              child: Column(spacing: 2, children: [
                for (final (label, note, on, set) in options)
                  Semantics(
                    checked: on,
                    label: label,
                    excludeSemantics: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Radii.key),
                      onTap: () => setState(() => set(!on)),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 46),
                        child: Row(children: [
                          Checkbox(value: on, onChanged: (v) => setState(() => set(v ?? false))),
                          Expanded(child: Text(label, style: TextStyle(fontSize: 14, color: c.text))),
                          if (note.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: Text(note, style: TextStyle(fontSize: 12, color: c.textMuted)),
                            ),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
            section(
              'Send with',
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
                Row(spacing: 8, children: [
                  for (final d in ShareDest.values)
                    Expanded(
                      child: _DestCard(dest: d, selected: _dest == d, onTap: () => setState(() {
                        _dest = d;
                        _status = null;
                      }),
                      ),
                    ),
                ]),
                Row(spacing: 8, children: [
                  EIcon(EIcons.shieldCheck, size: 14, color: c.green),
                  Expanded(child: Text(_dest.note, style: TextStyle(fontSize: 12, color: c.textMuted))),
                ]),
              ]),
            ),
            if (locked != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: c.stickyYellow, borderRadius: BorderRadius.circular(Radii.button)),
                child: Row(spacing: 10, children: [
                  EIcon(EIcons.lock, size: 16, color: c.goldDeep),
                  Expanded(child: Text(locked, style: TextStyle(fontSize: 13, color: c.goldDeep))),
                ]),
              ),
            DashedBorder(
              color: c.lineStrong,
              radius: 14,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(spacing: 12, children: [
                  EIcon(EIcons.personAdd, color: c.textMuted),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                      Text('Invite people and write together',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.textMuted)),
                      Text('Coming later, once it can be done securely. For now, share a copy.',
                          style: TextStyle(fontSize: 12, color: c.textMuted)),
                    ]),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: c.side, borderRadius: BorderRadius.circular(999)),
                    child: Text('Coming later', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.textMuted)),
                  ),
                ]),
              ),
            ),
            if (_status != null)
              Semantics(liveRegion: true, child: Text(_status!, style: TextStyle(fontSize: 14, color: c.textMuted))),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 10,
              spacing: 12,
              children: [
                FutureBuilder<int>(
                  future: _size,
                  builder: (context, snap) => Text(
                    snap.hasData && !blocked ? '$what · about ${sizeWords(snap.data!)}' : what,
                    style: TextStyle(fontSize: 13, color: c.textMuted),
                  ),
                ),
                DialogActions(children: [
                  SecondaryButton(label: 'Cancel', height: 48, onPressed: () => Navigator.of(context).pop()),
                  PrimaryButton(label: _dest.action, height: 48, onPressed: _busy || blocked ? null : _send),
                ]),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

class _FormatCard extends StatelessWidget {
  const _FormatCard({required this.format, required this.selected, required this.enabled, required this.onTap});

  final ExportFormat format;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (label, badge, tint, ink, desc) = switch (format) {
      ExportFormat.pdf => ('PDF', 'PDF', c.clayTint, c.clayDeep, 'Best for reading and printing. Opens on any device.'),
      ExportFormat.board => ('Board file', '.BOARD', c.accentTint, c.accentDeep, 'Opens in Endless with everything still editable.'),
      ExportFormat.image => ('Image', 'PNG', c.greenTint, c.greenDeep, 'A picture of this page. Only for one page.'),
    };
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      enabled: enabled,
      button: true,
      label: label,
      hint: desc,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Material(
          color: selected ? c.accentWash : c.surface,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: selected ? c.accent : c.lineSoft, width: selected ? 2 : 1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled ? onTap : null,
            child: Container(
              constraints: const BoxConstraints(minHeight: 96),
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
                Row(spacing: 8, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(5)),
                    child: Text(badge, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: ink)),
                  ),
                  Flexible(child: Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text))),
                ]),
                Text(desc, style: TextStyle(fontSize: 12, height: 1.35, color: c.textMuted)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _DestCard extends StatelessWidget {
  const _DestCard({required this.dest, required this.selected, required this.onTap});

  final ShareDest dest;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final icon = switch (dest) {
      ShareDest.sheet => EIcons.shareSheet,
      ShareDest.drive => EIcons.cloud,
      ShareDest.onedrive => EIcons.cloudUp,
      ShareDest.tablet => EIcons.tablet,
    };
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: dest.label,
      excludeSemantics: true,
      child: Material(
        color: selected ? c.accentWash : c.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: selected ? c.accent : c.lineSoft, width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            height: 82,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, spacing: 6, children: [
              EIcon(icon, color: c.text),
              Text(dest.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text)),
            ]),
          ),
        ),
      ),
    );
  }
}
