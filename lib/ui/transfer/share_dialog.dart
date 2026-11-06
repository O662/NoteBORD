import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../canvas/pane.dart';
import '../../library/library.dart';
import '../../state/notebook.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../../transfer/files.dart';
import '../../transfer/pdf_export.dart';
import '../../transfer/share.dart';
import '../../transfer/transfer.dart';
import '../calendar/calendar_widgets.dart' show Segmented;
import '../dialogs.dart';
import '../icons.dart';
import 'transfer_dialog.dart';

// Share (design/screens/Share.png), without a server: This page · Notebook
// · Folder, and "Export a copy" through the share sheet (Gmail, Drive,
// OneDrive, messages…). Inviting people, link access and editing together
// need a server to hold shared notes, so they're "Coming later"
// (docs/SPEC.md, "Later"). Pages with a password are never sent.

Future<void> showShareDialog(BuildContext context, Pane pane) =>
    showEndlessDialog<void>(context, builder: (_) => ShareDialog(pane: pane, hostContext: context));

class ShareDialog extends ConsumerStatefulWidget {
  const ShareDialog({super.key, required this.pane, required this.hostContext});

  final Pane pane;
  final BuildContext hostContext;

  @override
  ConsumerState<ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends ConsumerState<ShareDialog> {
  String? _status;
  bool _busy = false;
  var _scope = ShareScope.notebook;

  String _label(ShareScope s) => switch (s) {
        ShareScope.page => 'This page',
        ShareScope.notebook => 'Notebook',
        ShareScope.folder => 'Folder',
      };

  /// The row itself: Export, with more choices (save to the tablet, some
  /// pages, a sealed backup).
  void _openExport() {
    Navigator.of(context).pop();
    showTransferDialog(widget.hostContext, pane: widget.pane, format: ExportFormat.pdf, scope: ExportScope.notebook);
  }

  /// A chip: the copies in [format], straight to the share sheet.
  Future<void> _send(ExportFormat format) async {
    setState(() {
      _busy = true;
      _status = switch (format) {
        ExportFormat.pdf => 'Making the PDF…',
        ExportFormat.board => 'Packing the board file…',
        ExportFormat.image => 'Making a picture of this page…',
      };
    });
    final pane = widget.pane;
    try {
      final copies = await ref.read(transfersProvider).shareCopies(pane.notebookId, _scope, format, current: pane.page);
      await ref.read(fileTransferProvider).shareAll([for (final f in copies.files) (name: f.name, bytes: f.bytes, mime: f.mime)]);
      if (!mounted) return;
      Navigator.of(context).pop();
      final what = copies.files.length == 1 ? copies.files.single.name : '${copies.files.length} files';
      pane.toast(copies.leftOutNote == null ? 'Shared $what' : 'Shared $what · ${copies.leftOutNote}');
    } on ExportProblem catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = e.message;
        });
      }
    } on Object catch (e, st) {
      debugPrint('Share failed: $e\n$st');
      if (mounted) {
        setState(() {
          _busy = false;
          _status = 'Couldn’t make the copy: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final inFolder = (ref.read(libraryProvider).byId(widget.pane.notebookId)?.folder ?? const []).isNotEmpty;
    final nb = ref.watch(notebookProvider(widget.pane.notebookId));
    final page = nb.pageAt(widget.pane.page);
    final pageLocked = nb.lockFor(page.id) != null || nb.isSealed(page.id);
    final note = switch (_scope) {
      ShareScope.page when pageLocked => 'This page has a password, so it can’t be shared.',
      ShareScope.folder when !inFolder => 'This notebook isn’t in a folder.',
      ShareScope.folder => 'Every notebook in “${(ref.read(libraryProvider).byId(widget.pane.notebookId)?.folder ?? const []).last}”, a file each.',
      _ => null,
    };
    final blocked = _scope == ShareScope.page && pageLocked || _scope == ShareScope.folder && !inFolder;
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: 'Share',
      explicitChildNodes: true,
      child: Container(
        width: 640,
        padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(22), boxShadow: c.modalShadow),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 18, children: [
          Row(spacing: 12, children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text('Share', style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 28, color: c.text)),
              ),
            ),
            Segmented<ShareScope>(
              values: ShareScope.values,
              labels: [for (final s in ShareScope.values) _label(s)],
              value: _scope,
              label: 'What to share',
              height: 40,
              fontSize: 13,
              onChanged: (s) => setState(() {
                _scope = s;
                _status = null;
              }),
            ),
            DialogCloseButton(onPressed: () => Navigator.of(context).pop()),
          ]),
          const _ComingLater(),
          _ExportRow(
            busy: _busy || blocked,
            imageOff: _scope == ShareScope.folder,
            onRow: _openExport,
            onFormat: _send,
          ),
          if ((_status ?? note) case final text?) Text(text, style: TextStyle(fontSize: 14, color: c.textMuted)),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            PrimaryButton(label: 'Done', height: 46, onPressed: () => Navigator.of(context).pop()),
          ]),
        ]),
      ),
    );
  }
}

/// Where Share.png has the invites and link access: what's coming, and why.
class _ComingLater extends StatelessWidget {
  const _ComingLater();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(Radii.card)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
        Row(spacing: 10, children: [
          Expanded(
            child: Text('Invite people · Anyone with the link · Edit together',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: c.side, borderRadius: BorderRadius.circular(Radii.chip)),
            child: Text('Coming later', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textMuted)),
          ),
        ]),
        Text(
          'These need a server to keep shared notes, and Endless doesn’t use one: your notes stay on your devices and '
          'in your own cloud. For now, send a copy below. Pages with a password are never sent.',
          style: TextStyle(fontSize: 13, height: 1.4, color: c.textMuted),
        ),
      ]),
    );
  }
}

/// "Export a copy": PDF · Board file · Image, each straight to the share
/// sheet; the row itself opens Export (save to the tablet, and more).
class _ExportRow extends StatelessWidget {
  const _ExportRow({required this.busy, required this.imageOff, required this.onRow, required this.onFormat});

  final bool busy;
  final bool imageOff;
  final VoidCallback onRow;
  final ValueChanged<ExportFormat> onFormat;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
      decoration: BoxDecoration(border: Border.all(color: c.cardLine), borderRadius: BorderRadius.circular(Radii.card)),
      child: Row(spacing: 12, children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: c.side, borderRadius: BorderRadius.circular(Radii.key)),
          child: Center(child: EIcon(EIcons.export, size: 20, color: c.text)),
        ),
        Expanded(
          child: Semantics(
            button: true,
            label: 'Export a copy',
            hint: 'More ways to save or send it',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRow,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                  Text('Export a copy', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                  Text.rich(
                    TextSpan(children: [
                      const TextSpan(text: 'Send it as a file · or save it from the '),
                      // ⋯ isn't in Figtree: the ⋯ button's own icon.
                      WidgetSpan(alignment: PlaceholderAlignment.middle, child: EIcon(EIcons.more, size: 14, color: c.textMuted)),
                      const TextSpan(text: ' menu'),
                    ]),
                    style: TextStyle(fontSize: 13, color: c.textMuted),
                  ),
                ]),
              ),
            ),
          ),
        ),
        _Chip(label: 'PDF', onTap: busy ? null : () => onFormat(ExportFormat.pdf)),
        _Chip(label: 'Board file', onTap: busy ? null : () => onFormat(ExportFormat.board)),
        _Chip(label: 'Image', onTap: busy || imageOff ? null : () => onFormat(ExportFormat.image)),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final on = onTap != null;
    return Semantics(
      button: true,
      enabled: on,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: StadiumBorder(side: BorderSide(color: on ? c.lineStrong : c.line)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            // 36 tall as in Share.dc.html; the row around it is 56.
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: on ? c.text : c.textFaint)),
          ),
        ),
      ),
    );
  }
}

/// ⋯ → Print: the whole notebook on A4 or Letter sheets, in the system's
/// print dialog. Locked pages that aren't open are left out.
Future<void> printNotebook(BuildContext context, Pane pane) =>
    showEndlessDialog<void>(context, dismissible: false, builder: (_) => _Printing(pane: pane, hostContext: context));

class _Printing extends ConsumerStatefulWidget {
  const _Printing({required this.pane, required this.hostContext});

  final Pane pane;
  final BuildContext hostContext;

  @override
  ConsumerState<_Printing> createState() => _PrintingState();
}

class _PrintingState extends ConsumerState<_Printing> {
  String _status = 'Getting the pages ready…';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final pane = widget.pane;
    final paper = paperForLocale(WidgetsBinding.instance.platformDispatcher.locale);
    String? problem;
    try {
      final file = await ref.read(transfersProvider).export(
            pane.notebookId,
            scope: ExportScope.notebook,
            format: ExportFormat.pdf,
            current: pane.page,
            pdf: PdfOptions(pages: EndlessPages.split, paper: paper),
            onProgress: (done, total) {
              if (mounted) setState(() => _status = 'Getting page $done of $total ready…');
            },
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      await ref.read(fileTransferProvider).print(file.name, file.bytes);
      return;
    } on ExportProblem catch (e) {
      problem = e.message;
    } on Object catch (e, st) {
      debugPrint('Print failed: $e\n$st');
      problem = 'Couldn’t print: $e';
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    pane.toast(problem);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = ref.watch(notebookProvider(widget.pane.notebookId)).notebook.title;
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: 'Print',
      explicitChildNodes: true,
      liveRegion: true,
      child: Container(
        width: 460,
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(22), boxShadow: c.modalShadow),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 18, children: [
          Text('Print', style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 30, height: 1.2, color: c.text)),
          Row(spacing: 14, children: [
            SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: c.accent)),
            Expanded(
              child: Text('$_status\n$title', style: TextStyle(fontSize: 15, height: 1.4, color: c.textMuted)),
            ),
          ]),
        ]),
      ),
    );
  }
}
