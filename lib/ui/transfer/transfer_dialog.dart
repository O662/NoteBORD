import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../board/model.dart';
import '../../canvas/pane.dart';
import '../../library/library.dart';
import '../../state/notebook.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../../transfer/board_file.dart' show ImportProblem;
import '../../transfer/files.dart';
import '../../transfer/pdf_export.dart';
import '../../transfer/transfer.dart';
import '../canvas/panels.dart' show PageThumbPainter;
import '../common.dart';
import '../dialogs.dart';
import '../icons.dart';
import '../library/widgets.dart' show FolderIcon, SectionLabel;
import '../routes.dart';

// Import and export (design/screens/Export.png, Export.dc.html).

enum TransferMode { export, import }

enum _Dest { device, drive, onedrive, share }

const _destLabels = {
  _Dest.device: 'This tablet',
  _Dest.drive: 'Google Drive',
  _Dest.onedrive: 'OneDrive',
  _Dest.share: 'Share…',
};

/// Opens Import and export. From a notebook ([pane]) both tabs are there;
/// from the library only Import, into [folder].
Future<void> showTransferDialog(
  BuildContext context, {
  Pane? pane,
  TransferMode mode = TransferMode.export,
  ExportFormat format = ExportFormat.pdf,
  ExportScope scope = ExportScope.page,
  List<String> folder = const [],
}) => showEndlessDialog<void>(
  context,
  builder: (_) => TransferDialog(
    pane: pane,
    mode: pane == null ? TransferMode.import : mode,
    format: format,
    scope: scope,
    folder: folder,
    hostContext: context,
  ),
);

/// What a successful export says.
String savedNote(ExportFile file, {required bool shared}) => shared ? 'Shared ${file.name}' : 'Saved ${file.name}';

class TransferDialog extends ConsumerStatefulWidget {
  const TransferDialog({
    super.key,
    required this.pane,
    required this.mode,
    required this.format,
    required this.scope,
    required this.folder,
    required this.hostContext,
  });

  final Pane? pane;
  final TransferMode mode;
  final ExportFormat format;
  final ExportScope scope;
  final List<String> folder;

  /// The screen that opened the dialog, for notes and navigating after it closes.
  final BuildContext hostContext;

  @override
  ConsumerState<TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends ConsumerState<TransferDialog> {
  late TransferMode _mode = widget.mode;

  // Export.
  late ExportScope _scope = widget.scope;
  late ExportFormat _format = widget.format == ExportFormat.image ? ExportFormat.pdf : widget.format;
  Set<String> _picked = {};
  EndlessPages _endless = EndlessPages.fit;
  PaperSize? _paper;
  bool _searchable = true;
  bool _background = false;
  bool _images = true;
  _Dest _dest = _Dest.device;

  // Import.
  List<PickedFile> _files = const [];

  /// null: this notebook (from a notebook only); else a folder.
  List<String>? _into;

  bool _busy = false;
  String? _progress;
  String? _error;
  String? _info;

  Pane? get _pane => widget.pane;

  @override
  void initState() {
    super.initState();
    _into = _pane == null ? widget.folder : null;
    if (_pane != null) _picked = {_notebook.pageAt(_pane!.page).id};
  }

  NotebookState get _notebook => ref.read(notebookProvider(_pane!.notebookId));

  PaperSize get _paperSize => _paper ?? paperForLocale(WidgetsBinding.instance.platformDispatcher.locale);

  // Export.

  /// Why the export can't go ahead, or null.
  String? _blocked(NotebookState nb) {
    final pages = ref.read(transfersProvider).pagesFor(nb, _scope, current: _pane!.page, picked: _picked);
    if (pages.isEmpty) return 'Pick at least one page.';
    if (_format == ExportFormat.pdf && pages.every((i) => nb.isSealed(nb.pages[i].id))) {
      if (pages.length > 1) return 'These pages are locked. Unlock them to export them as a PDF.';
      final which = _scope == ExportScope.page ? 'This page is' : 'Page ${pages.single + 1} is';
      return '$which locked. Unlock it to export it as a PDF, or export a board file, which keeps it locked.';
    }
    return null;
  }

  Future<void> _export() async {
    final pane = _pane!;
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Exporting…';
    });
    final host = widget.hostContext;
    try {
      final file = await ref
          .read(transfersProvider)
          .export(
            pane.notebookId,
            scope: _scope,
            format: _format,
            current: pane.page,
            picked: _picked,
            pdf: PdfOptions(pages: _endless, paper: _paperSize, searchable: _searchable, background: _background),
            includeAssets: _images,
            onProgress: (done, total) {
              if (mounted && total > 1) setState(() => _progress = 'Exporting page $done of $total…');
            },
          );
      if (!mounted) return;
      setState(() => _progress = _dest == _Dest.share ? 'Opening the share sheet…' : 'Choose where to save it…');
      final files = ref.read(fileTransferProvider);
      final shared = _dest == _Dest.share;
      if (shared) {
        await files.share(file.name, file.bytes, file.mime);
      } else if (!await files.save(file.name, file.bytes, file.mime)) {
        // Cancelled in the Save dialog: stay here.
        if (mounted) {
          setState(() {
            _busy = false;
            _progress = null;
          });
        }
        return;
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      if (host.mounted) pane.toast(savedNote(file, shared: shared));
    } on ExportProblem catch (e) {
      _fail(e.message);
    } on Object catch (e, st) {
      debugPrint('Export failed: $e\n$st');
      _fail('Couldn’t export: $e');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _progress = null;
      _error = message;
    });
  }

  Future<void> _pickPages() async {
    final picked = await showEndlessDialog<Set<String>>(
      context,
      builder: (_) => _PagePicker(notebookId: _pane!.notebookId, picked: _picked),
    );
    if (picked != null && mounted) {
      setState(() {
        _picked = picked;
        _scope = ExportScope.pages;
      });
    }
  }

  // Import.

  Future<void> _browse() async {
    setState(() => _error = null);
    final List<PickedFile> files;
    try {
      files = await ref.read(fileTransferProvider).pick();
    } on Object catch (e) {
      _fail('Couldn’t open the file: $e');
      return;
    }
    if (files.isEmpty || !mounted) return;
    setState(() => _files = files);
  }

  Future<void> _import() async {
    final pane = _pane;
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Importing…';
    });
    final host = widget.hostContext;
    final target = _into == null
        ? ImportTarget.notebook(pane!.notebookId, page: pane.page, center: pane.view.visiblePage.center)
        : ImportTarget.folder(_into!);
    try {
      final outcome = await ref
          .read(transfersProvider)
          .import(
            _files,
            target,
            onStatus: (s) {
              if (mounted) setState(() => _progress = s);
            },
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      if (!host.mounted) return;
      if (outcome.openNotebook != null) {
        final to = Routes.notebook(outcome.openNotebook!, page: 0);
        if (pane == null) {
          host.push(to);
        } else {
          host.pushReplacement(to);
        }
        showNote(host, outcome.message);
      } else if (pane != null && outcome.goToPage != null) {
        pane.goTo(outcome.goToPage!);
        pane.toast(outcome.message);
      } else {
        showNote(host, outcome.message);
      }
    } on ImportProblem catch (e) {
      _fail(e.message);
    } on Object catch (e, st) {
      debugPrint('Import failed: $e\n$st');
      _fail('Couldn’t import: $e');
    }
  }

  Future<void> _pickTarget() async {
    final picked = await showEndlessDialog<_Target>(
      context,
      builder: (_) => _TargetPicker(current: _into, thisNotebook: _pane != null),
    );
    if (picked != null && mounted) setState(() => _into = picked.folder);
  }

  String _targetLabel() {
    final into = _into;
    if (into == null) return 'This notebook';
    if (into.isEmpty) return 'All notebooks';
    return into.join(' › ');
  }

  // Layout.

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final height = math.min(712.0, MediaQuery.sizeOf(context).height - 48);
    final tabs = _pane == null ? const [TransferMode.import] : TransferMode.values;
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: 'Import and export',
      explicitChildNodes: true,
      child: Container(
        width: 700,
        height: height,
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(22), boxShadow: c.modalShadow),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 18,
          children: [
            Row(
              children: [
                _Tabs(
                  labels: [for (final t in tabs) t == TransferMode.export ? 'Export' : 'Import'],
                  selected: tabs.indexOf(_mode),
                  onSelect: _busy
                      ? null
                      : (i) => setState(() {
                          _mode = tabs[i];
                          _error = null;
                          _info = null;
                        }),
                ),
                const Spacer(),
                DialogCloseButton(onPressed: () => Navigator.of(context).pop()),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(child: _mode == TransferMode.export ? _exportBody(c) : _importBody(c)),
            ),
            if (_error != null || _info != null || _progress != null)
              Text(
                _error ?? _progress ?? _info!,
                style: TextStyle(fontSize: 14, height: 1.4, color: _error != null ? c.danger : c.textMuted),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              spacing: 10,
              children: [
                SecondaryButton(label: 'Cancel', onPressed: _busy ? null : () => Navigator.of(context).pop()),
                if (_mode == TransferMode.export)
                  _exportButton()
                else
                  PrimaryButton(label: 'Import', onPressed: _files.isEmpty || _busy ? null : _import),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _exportButton() {
    final nb = ref.watch(notebookProvider(_pane!.notebookId));
    final blocked = _blocked(nb);
    return PrimaryButton(
      label: _format == ExportFormat.pdf ? 'Export PDF' : 'Export board file',
      onPressed: blocked != null || _busy ? null : _export,
    );
  }

  Widget _exportBody(EndlessColors c) {
    final nb = ref.watch(notebookProvider(_pane!.notebookId));
    final page = _pane!.page.clamp(0, nb.pages.length - 1);
    final blocked = _blocked(nb);
    final pickedPages = [
      for (final (i, p) in nb.pages.indexed)
        if (_picked.contains(p.id)) i + 1,
    ];
    final pdf = _format == ExportFormat.pdf;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 18,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            const SectionLabel('What to export'),
            Semantics(
              container: true,
              label: 'Scope',
              explicitChildNodes: true,
              child: Row(
                spacing: 10,
                children: [
                  Expanded(
                    child: _ChoiceCard(
                      selected: _scope == ExportScope.page,
                      onTap: () => setState(() => _scope = ExportScope.page),
                      child: _cardText('This page', 'Page ${page + 1}', c),
                    ),
                  ),
                  Expanded(
                    child: _ChoiceCard(
                      selected: _scope == ExportScope.pages,
                      onTap: _pickPages,
                      child: _cardText(
                        'Some pages',
                        _scope == ExportScope.pages && pickedPages.isNotEmpty ? pageList(pickedPages) : 'Pick pages',
                        c,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _ChoiceCard(
                      selected: _scope == ExportScope.notebook,
                      onTap: () => setState(() => _scope = ExportScope.notebook),
                      child: _cardText(
                        'Whole notebook',
                        nb.pages.length == 1 ? '1 page' : '${nb.pages.length} pages',
                        c,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            const SectionLabel('Format'),
            Semantics(
              container: true,
              label: 'Format',
              explicitChildNodes: true,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 10,
                  children: [
                    Expanded(
                      child: _ChoiceCard(
                        selected: pdf,
                        padding: const EdgeInsets.all(14),
                        onTap: () => setState(() => _format = ExportFormat.pdf),
                        child: _formatText(
                          const _PdfBadge(),
                          'PDF document',
                          'To share, print or open anywhere. Ink is flattened.',
                          c,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _ChoiceCard(
                        selected: !pdf,
                        padding: const EdgeInsets.all(14),
                        onTap: () => setState(() => _format = ExportFormat.board),
                        child: _formatText(
                          const _BoardBadge(),
                          'Board file (.board)',
                          'Lossless: every stroke, pressure point, shape and image. Import it to keep editing.',
                          c,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(Radii.card)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 4,
            children: [
              if (pdf) ...[
                _OptionRow(
                  label: 'Endless pages',
                  child: _Segments(
                    label: 'Endless pages',
                    labels: ['Fit page to its ink', 'Split into ${PaperSize.a4.label} / ${PaperSize.letter.label}'],
                    selected: _endless.index,
                    onSelect: (i) => setState(() => _endless = EndlessPages.values[i]),
                  ),
                ),
                if (_endless == EndlessPages.split)
                  _OptionRow(
                    label: 'Paper',
                    child: _Segments(
                      label: 'Paper',
                      labels: [for (final p in PaperSize.values) p.label],
                      selected: _paperSize.index,
                      onSelect: (i) => setState(() => _paper = PaperSize.values[i]),
                    ),
                  ),
                _Check(
                  label: 'Make handwriting searchable inside the PDF',
                  value: _searchable,
                  onChanged: (v) => setState(() => _searchable = v),
                ),
                _Check(
                  label: _backgroundLabel(nb.pageAt(page).page.paper),
                  value: _background,
                  onChanged: (v) => setState(() => _background = v),
                ),
              ] else ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'One file holding the notebook as readable JSON, with its images packed alongside.',
                      style: TextStyle(fontSize: 14, height: 1.4, color: c.text),
                    ),
                  ),
                ),
                _Check(
                  label: 'Include images and attached PDFs',
                  value: _images,
                  onChanged: (v) => setState(() => _images = v),
                ),
              ],
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            const SectionLabel('Save to'),
            Semantics(
              container: true,
              label: 'Destination',
              explicitChildNodes: true,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final d in _Dest.values)
                    _DestChip(
                      label: _destLabels[d]!,
                      selected: _dest == d,
                      onTap: () => setState(() {
                        if (d == _Dest.drive || d == _Dest.onedrive) {
                          // Cloud saving comes with sync (Phase 9).
                          _info =
                              '${_destLabels[d]} comes with cloud sync. For now, choose Share… and pick ${_destLabels[d]} there.';
                          return;
                        }
                        _info = null;
                        _dest = d;
                      }),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (blocked != null && _error == null)
          Text(blocked, style: TextStyle(fontSize: 14, height: 1.4, color: c.textMuted)),
      ],
    );
  }

  Widget _importBody(EndlessColors c) {
    final picked = _files;
    final title = switch (picked.length) {
      0 => 'Choose a PDF, image or .board file',
      1 => picked.single.name,
      final n => '$n files',
    };
    final sub = picked.isEmpty
        ? 'From this tablet, Google Drive or OneDrive'
        : picked.map((f) => '${_kindLabel(f)} · ${fileSize(f.bytes.length)}').take(3).join('   ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 18,
      children: [
        DashedBorder(
          color: c.lineDashed,
          radius: 18,
          width: 2,
          child: Container(
            height: 220,
            decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(18)),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 12,
              children: [
                EIcon(EIcons.importDrop, size: 40, color: c.accent),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 24, color: c.text),
                ),
                Text(
                  sub,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(fontSize: 14, color: c.textMuted),
                ),
                PrimaryButton(
                  label: picked.isEmpty ? 'Browse files' : 'Choose other files',
                  height: 44,
                  onPressed: _busy ? null : _browse,
                ),
              ],
            ),
          ),
        ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Expanded(
                child: _InfoCard(
                  title: 'PDF',
                  body:
                      'Each PDF page becomes a notebook page you can write on. Text already in the PDF stays searchable.',
                ),
              ),
              Expanded(
                child: _InfoCard(
                  title: 'Board file (.board)',
                  body: 'Restored exactly as it was: strokes, shapes, images, pages and passwords.',
                ),
              ),
            ],
          ),
        ),
        Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(Radii.card)),
          child: Row(
            children: [
              Expanded(
                child: Text('Import into', style: TextStyle(fontSize: 14, color: c.text)),
              ),
              Semantics(
                button: true,
                label: 'Import into ${_targetLabel()}',
                excludeSemantics: true,
                child: Material(
                  color: c.surface,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: c.lineStrong),
                    borderRadius: BorderRadius.circular(Radii.key),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Radii.key),
                    onTap: _busy ? null : _pickTarget,
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 8,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 320),
                            child: Text(
                              _targetLabel(),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.text),
                            ),
                          ),
                          EIcon(EIcons.chevronDown, size: 14, color: c.text),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cardText(String label, String sub, EndlessColors c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 2,
    children: [
      Text(
        label,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text),
      ),
      Text(
        sub,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, color: c.textMuted),
      ),
    ],
  );

  Widget _formatText(Widget badge, String label, String desc, EndlessColors c) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 14,
    children: [
      badge,
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 3,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text),
            ),
            Text(desc, style: TextStyle(fontSize: 13, height: 1.4, color: c.textMuted)),
          ],
        ),
      ),
    ],
  );
}

String _backgroundLabel(Paper paper) => switch (paper) {
  Paper.lines => 'Include the ruled lines',
  Paper.grid => 'Include the grid background',
  _ => 'Include the dot-grid background',
};

String _kindLabel(PickedFile f) => switch (importKindOf(f)) {
  ImportKind.pdf => 'PDF',
  ImportKind.board => 'Board file',
  ImportKind.image => 'Image',
  ImportKind.unknown => 'Can’t import',
};

/// "1.4 MB", "820 KB".
String fileSize(int bytes) {
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${math.max(1, (bytes / 1024).round())} KB';
}

/// "Pages 1–3, 5" from page numbers in order.
String pageList(List<int> numbers) {
  final parts = <String>[];
  var i = 0;
  while (i < numbers.length) {
    var j = i;
    while (j + 1 < numbers.length && numbers[j + 1] == numbers[j] + 1) {
      j++;
    }
    parts.add(j == i ? '${numbers[i]}' : '${numbers[i]}–${numbers[j]}');
    i = j + 1;
  }
  return '${numbers.length == 1 ? 'Page' : 'Pages'} ${parts.join(', ')}';
}

/// Export / Import: a sunk segmented control (12 corners, 40 tall).
class _Tabs extends StatelessWidget {
  const _Tabs({required this.labels, required this.selected, required this.onSelect});

  final List<String> labels;
  final int selected;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      label: 'Mode',
      explicitChildNodes: true,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: c.side, borderRadius: BorderRadius.circular(Radii.button)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 2,
          children: [
            for (final (i, label) in labels.indexed)
              Semantics(
                button: true,
                selected: i == selected,
                label: label,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onSelect == null ? null : () => onSelect!(i),
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    alignment: Alignment.center,
                    decoration: _segmentBox(c, i == selected, 9),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: i == selected ? FontWeight.w600 : FontWeight.w500,
                        color: c.text,
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

BoxDecoration _segmentBox(EndlessColors c, bool selected, double radius) => BoxDecoration(
  color: selected ? c.surface : Colors.transparent,
  borderRadius: BorderRadius.circular(radius),
  boxShadow: selected
      ? [BoxShadow(color: c.shadow.withValues(alpha: 0.2), offset: const Offset(0, 1), blurRadius: 2)]
      : null,
);

/// "Fit page to its ink | Split into A4 / Letter": 36 tall, 10 corners.
class _Segments extends StatelessWidget {
  const _Segments({required this.label, required this.labels, required this.selected, required this.onSelect});

  final String label;
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      label: label,
      explicitChildNodes: true,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: c.side, borderRadius: BorderRadius.circular(Radii.key)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 2,
          children: [
            for (final (i, text) in labels.indexed)
              Semantics(
                button: true,
                inMutuallyExclusiveGroup: true,
                checked: i == selected,
                label: text,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(i),
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: _segmentBox(c, i == selected, Radii.small),
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: i == selected ? FontWeight.w600 : FontWeight.w500,
                        color: c.text,
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

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 48),
    child: Row(
      spacing: 12,
      children: [
        Expanded(
          child: Text(label, style: TextStyle(fontSize: 14, color: context.colors.text)),
        ),
        child,
      ],
    ),
  );
}

class _Check extends StatelessWidget {
  const _Check({required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      checked: value,
      label: label,
      excludeSemantics: true,
      onTap: () => onChanged(!value),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            spacing: 12,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: value ? c.accent : c.surface,
                  border: Border.all(color: value ? c.accent : c.lineStrong, width: 1.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: value ? Center(child: EIcon(EIcons.check, size: 16, color: c.onAccent)) : null,
              ),
              Expanded(
                child: Text(label, style: TextStyle(fontSize: 14, color: c.text)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A scope or format choice: 2 px border, 14 corners, washed when picked.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.selected,
    required this.onTap,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: Material(
        color: selected ? c.accentWash : c.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: selected ? c.accent : c.cardLine, width: 2),
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.card),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _PdfBadge extends StatelessWidget {
  const _PdfBadge();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: 44,
      height: 52,
      padding: const EdgeInsets.only(bottom: 6),
      alignment: Alignment.bottomCenter,
      decoration: BoxDecoration(
        border: Border.all(color: c.clay, width: 1.5),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(6),
          topRight: Radius.circular(14),
          bottomLeft: Radius.circular(6),
          bottomRight: Radius.circular(6),
        ),
      ),
      child: Text(
        'PDF',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.clayDeep),
      ),
    );
  }
}

class _BoardBadge extends StatelessWidget {
  const _BoardBadge();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: 44,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: c.accent, width: 1.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '{ }',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.accent),
      ),
    );
  }
}

/// "This tablet", "Google Drive"…: 44 tall pills, dark when picked.
class _DestChip extends StatelessWidget {
  const _DestChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
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
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: selected ? c.onInverse : c.text),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text),
          ),
          Text(body, style: TextStyle(fontSize: 14, height: 1.45, color: c.text)),
        ],
      ),
    );
  }
}

/// "Some pages": tick the pages to export.
class _PagePicker extends ConsumerStatefulWidget {
  const _PagePicker({required this.notebookId, required this.picked});

  final String notebookId;
  final Set<String> picked;

  @override
  ConsumerState<_PagePicker> createState() => _PagePickerState();
}

class _PagePickerState extends ConsumerState<_PagePicker> {
  late final _picked = {...widget.picked};

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final nb = ref.watch(notebookProvider(widget.notebookId));
    final all = _picked.length == nb.pages.length;
    return DialogFrame(
      title: 'Pick pages',
      width: 620,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 18,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: math.max(160, MediaQuery.sizeOf(context).height - 300)),
            child: GridView.count(
              shrinkWrap: true,
              crossAxisCount: 4,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.05,
              children: [
                for (final (i, page) in nb.pages.indexed)
                  _PickPage(
                    number: i + 1,
                    page: nb,
                    index: i,
                    picked: _picked.contains(page.id),
                    onTap: () =>
                        setState(() => _picked.contains(page.id) ? _picked.remove(page.id) : _picked.add(page.id)),
                  ),
              ],
            ),
          ),
          Row(
            spacing: 10,
            children: [
              SecondaryButton(
                label: all ? 'Clear' : 'All pages',
                onPressed: () => setState(() => all ? _picked.clear() : _picked.addAll(nb.pages.map((p) => p.id))),
              ),
              const Spacer(),
              Text(
                _picked.isEmpty ? 'No pages' : (_picked.length == 1 ? '1 page' : '${_picked.length} pages'),
                style: TextStyle(fontSize: 14, color: c.textMuted),
              ),
              PrimaryButton(
                label: 'Done',
                onPressed: _picked.isEmpty ? null : () => Navigator.of(context).pop(_picked),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PickPage extends StatelessWidget {
  const _PickPage({
    required this.number,
    required this.page,
    required this.index,
    required this.picked,
    required this.onTap,
  });

  final int number;
  final NotebookState page;
  final int index;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final runtime = page.pages[index];
    final locked = page.isSealed(runtime.id);
    return Semantics(
      checked: picked,
      label: locked ? 'Page $number, locked' : 'Page $number',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          spacing: 6,
          children: [
            Expanded(
              child: Material(
                color: locked ? c.side : c.surface,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: picked ? c.accent : c.line, width: picked ? 2 : 1),
                  borderRadius: BorderRadius.circular(Radii.small),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  child: Stack(
                    children: [
                      if (locked)
                        Center(child: EIcon(EIcons.lock, size: 20, color: c.textMuted))
                      else
                        Positioned.fill(
                          child: CustomPaint(
                            painter: PageThumbPainter(runtime, page.revision, Theme.of(context).brightness, c),
                          ),
                        ),
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: picked ? c.accent : c.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: picked ? c.accent : c.lineStrong, width: 1.5),
                          ),
                          child: picked ? Center(child: EIcon(EIcons.check, size: 14, color: c.onAccent)) : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Text(
              '$number',
              style: TextStyle(fontSize: 13, fontWeight: picked ? FontWeight.w600 : FontWeight.w400, color: c.text),
            ),
          ],
        ),
      ),
    );
  }
}

class _Target {
  const _Target(this.folder);

  /// null: this notebook.
  final List<String>? folder;
}

/// Import into: this notebook (from a notebook), all notebooks or a folder.
class _TargetPicker extends ConsumerWidget {
  const _TargetPicker({required this.current, required this.thisNotebook});

  final List<String>? current;
  final bool thisNotebook;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final folders = ref.watch(libraryProvider).folders;
    Widget row(List<String>? path, String label, {Color? color, String? sub}) {
      final selected = path == null ? current == null : current != null && listEquals(path, current);
      return Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.key),
          onTap: () => Navigator.of(context).pop(_Target(path)),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: EdgeInsets.only(
              left: 12.0 + (path == null || path.isEmpty ? 0 : (path.length - 1) * 22),
              right: 12,
            ),
            decoration: BoxDecoration(
              color: selected ? c.sideSelected : null,
              borderRadius: BorderRadius.circular(Radii.key),
            ),
            child: Row(
              spacing: 12,
              children: [
                if (color == null) EIcon(EIcons.notebook, color: c.textMuted) else FolderIcon(color: color),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                          color: c.text,
                        ),
                      ),
                      if (sub != null) Text(sub, style: TextStyle(fontSize: 13, color: c.textMuted)),
                    ],
                  ),
                ),
                if (selected) EIcon(EIcons.check, size: 18, color: c.accent),
              ],
            ),
          ),
        ),
      );
    }

    return DialogFrame(
      title: 'Import into',
      width: 460,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 420),
        child: ListView(
          shrinkWrap: true,
          children: [
            if (thisNotebook) row(null, 'This notebook', sub: 'PDF pages after this page, pictures on it'),
            row(const [], 'All notebooks', sub: thisNotebook ? 'A new notebook' : null),
            for (final f in folders) row(f.path, f.name, color: f.color),
          ],
        ),
      ),
    );
  }
}
