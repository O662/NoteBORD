import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../canvas/pane.dart';
import '../../state/notebook.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../../transfer/files.dart';
import '../../transfer/pdf_export.dart';
import '../../transfer/transfer.dart';
import '../dialogs.dart';
import '../icons.dart';
import 'transfer_dialog.dart';

// Share (design/screens/Share.png). Inviting people and links come with
// cloud sync (Phase 9); for now the dialog sends a copy ("Export a copy").

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

  /// Closes Share and opens Export with [format] picked.
  void _export(ExportFormat format) {
    Navigator.of(context).pop();
    showTransferDialog(widget.hostContext, pane: widget.pane, format: format, scope: ExportScope.notebook);
  }

  /// "Image": this page as a PNG, saved or shared.
  Future<void> _image(Offset at) async {
    final c = context.colors;
    final choice = await showMenu<bool>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      color: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.card), side: BorderSide(color: c.line)),
      items: [
        PopupMenuItem(value: false, height: 44, child: Text('Save to this tablet', style: TextStyle(fontSize: 15, color: c.text))),
        PopupMenuItem(value: true, height: 44, child: Text('Share…', style: TextStyle(fontSize: 15, color: c.text))),
      ],
    );
    if (choice == null || !mounted) return;
    setState(() {
      _busy = true;
      _status = 'Making a picture of this page…';
    });
    final pane = widget.pane;
    try {
      final file = await ref.read(transfersProvider).export(
            pane.notebookId,
            scope: ExportScope.page,
            format: ExportFormat.image,
            current: pane.page,
          );
      final files = ref.read(fileTransferProvider);
      if (choice) {
        await files.share(file.name, file.bytes, file.mime);
      } else if (!await files.save(file.name, file.bytes, file.mime)) {
        if (mounted) {
          setState(() {
            _busy = false;
            _status = null;
          });
        }
        return;
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      pane.toast(savedNote(file, shared: choice));
    } on ExportProblem catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = e.message;
        });
      }
    } on Object catch (e, st) {
      debugPrint('Image export failed: $e\n$st');
      if (mounted) {
        setState(() {
          _busy = false;
          _status = 'Couldn’t make the picture: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
          Row(children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text('Share', style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 28, color: c.text)),
              ),
            ),
            DialogCloseButton(onPressed: () => Navigator.of(context).pop()),
          ]),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(Radii.card)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
              Text('Inviting people and sharing a link come with cloud sync', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
              Text(
                'Until then, send a copy as a file. Locked pages stay locked in a board file and are left out of PDFs.',
                style: TextStyle(fontSize: 13, height: 1.4, color: c.textMuted),
              ),
            ]),
          ),
          _ExportRow(busy: _busy, onRow: () => _export(ExportFormat.pdf), onFormat: _export, onImage: _image),
          if (_status != null) Text(_status!, style: TextStyle(fontSize: 14, color: c.textMuted)),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            PrimaryButton(label: 'Done', height: 46, onPressed: () => Navigator.of(context).pop()),
          ]),
        ]),
      ),
    );
  }
}

/// "Export a copy": Save or send it as a file, with PDF · Board file · Image.
class _ExportRow extends StatelessWidget {
  const _ExportRow({required this.busy, required this.onRow, required this.onFormat, required this.onImage});

  final bool busy;
  final VoidCallback onRow;
  final ValueChanged<ExportFormat> onFormat;
  final ValueChanged<Offset> onImage;

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
            hint: 'Save or send it as a file, also in the more menu',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: busy ? null : onRow,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                  Text('Export a copy', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                  Text.rich(
                    TextSpan(children: [
                      const TextSpan(text: 'Save or send it as a file · also in the '),
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
        _Chip(label: 'PDF', onTap: busy ? null : (_) => onFormat(ExportFormat.pdf)),
        _Chip(label: 'Board file', onTap: busy ? null : (_) => onFormat(ExportFormat.board)),
        _Chip(label: 'Image', onTap: busy ? null : onImage),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onTap});

  final String label;

  /// Gets where the chip is on screen, for a menu.
  final ValueChanged<Offset>? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: Builder(
        builder: (context) => Material(
          color: c.surface,
          shape: StadiumBorder(side: BorderSide(color: c.lineStrong)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap == null
                ? null
                : () {
                    final box = context.findRenderObject()! as RenderBox;
                    onTap!(box.localToGlobal(box.size.bottomLeft(Offset.zero)));
                  },
            child: Container(
              // 36 tall as in Share.dc.html; the row around it is 56.
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.text)),
            ),
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
