import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show Offset, Size;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../board/ids.dart';
import '../board/model.dart';
import '../board/store.dart';
import '../library/library.dart';
import '../state/assets.dart';
import '../state/notebook.dart';
import '../state/settings.dart';
import 'board_file.dart';
import 'files.dart';
import 'image_export.dart';
import 'pdf_export.dart';
import 'pdf_import.dart';

// Export and import (design/screens/Export.png), between the dialog and the
// storage, PDF and file code.

enum ExportScope { page, pages, notebook }

enum ExportFormat { pdf, board, image }

/// A finished export, ready to save or share.
class ExportFile {
  const ExportFile(this.name, this.bytes, this.mime);

  final String name;
  final Uint8List bytes;
  final String mime;
}

const pdfMime = 'application/pdf';
const boardMime = 'application/zip';
const pngMime = 'image/png';

/// Raised when there is nothing to export; [message] is shown as it is.
class ExportProblem implements Exception {
  const ExportProblem(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Where imported files go: a new notebook in [folder], or the open
/// notebook [notebookId] (PDF pages after [page], pictures on it at
/// [center]).
class ImportTarget {
  const ImportTarget.folder(List<String> this.folder)
      : notebookId = null,
        page = 0,
        center = Offset.zero;

  const ImportTarget.notebook(String this.notebookId, {required this.page, required this.center}) : folder = null;

  final List<String>? folder;
  final String? notebookId;
  final int page;
  final Offset center;
}

/// What an import did: the notebook to open (a new one), or the page of the
/// open notebook to go to, and what to say.
class ImportOutcome {
  const ImportOutcome(this.message, {this.openNotebook, this.goToPage});

  final String message;
  final String? openNotebook;
  final int? goToPage;
}

enum ImportKind { pdf, board, image, unknown }

/// What a picked file is, from its first bytes and then its name.
ImportKind importKindOf(PickedFile f) {
  final b = f.bytes;
  if (imageExtension(b) == 'pdf') return ImportKind.pdf;
  if (b.length > 3 && b[0] == 0x50 && b[1] == 0x4B && (f.extension == 'board' || f.extension == 'zip')) return ImportKind.board;
  if (const {'png', 'jpg', 'gif', 'webp', 'bmp'}.contains(imageExtension(b))) return ImportKind.image;
  return ImportKind.unknown;
}

/// The size an imported picture gets on its own page: its own, scaled down
/// to fit a large sheet.
Size importedPictureSize(int w, int h) {
  final k = math.min(1.0, math.min(1200 / w, 1600 / h));
  return Size(w * k, h * k);
}

final transfersProvider = Provider<Transfers>(Transfers.new);

class Transfers {
  Transfers(this.ref);

  final Ref ref;

  BoardStore get _store => ref.read(boardStoreProvider);
  DateTime get _now => ref.read(clockProvider)().toUtc();

  // Export.

  /// The pages [scope] covers, in notebook order.
  List<int> pagesFor(NotebookState nb, ExportScope scope, {required int current, Set<String> picked = const {}}) => switch (scope) {
        ExportScope.page => [current.clamp(0, nb.pages.length - 1)],
        ExportScope.pages => [
            for (final (i, page) in nb.pages.indexed)
              if (picked.contains(page.id)) i,
          ],
        ExportScope.notebook => [for (var i = 0; i < nb.pages.length; i++) i],
      };

  String _fileTitle(Notebook nb, ExportScope scope, List<int> pages) {
    final title = nb.title.trim().isEmpty ? 'Notebook' : nb.title.trim();
    if (scope == ExportScope.notebook || pages.isEmpty) return title;
    if (pages.length == 1) return '$title — page ${pages.single + 1}';
    return '$title — ${pages.length} pages';
  }

  /// Builds the file. Locked pages that aren't open are left out of PDFs
  /// and pictures; a board file keeps them sealed.
  Future<ExportFile> export(
    String notebookId, {
    required ExportScope scope,
    required ExportFormat format,
    required int current,
    Set<String> picked = const {},
    PdfOptions pdf = const PdfOptions(),
    bool includeAssets = true,
    void Function(int done, int total)? onProgress,
  }) async {
    final notifier = ref.read(notebookProvider(notebookId).notifier);
    final nb = ref.read(notebookProvider(notebookId));
    final indexes = pagesFor(nb, scope, current: current, picked: picked);
    if (indexes.isEmpty) throw const ExportProblem('Pick at least one page to export.');
    final title = _fileTitle(nb.notebook, scope, indexes);
    final open = [
      for (final i in indexes)
        if (!nb.isSealed(nb.pages[i].id)) nb.pages[i].page,
    ];
    switch (format) {
      case ExportFormat.board:
        await notifier.flush();
        await ref.read(writeQueueProvider).idle;
        final bytes = await exportBoardFile(
          _store,
          notebookId,
          pageIds: scope == ExportScope.notebook ? null : {for (final i in indexes) nb.pages[i].id},
          includeAssets: includeAssets,
        );
        return ExportFile(fileNameFor(title, 'board'), bytes, boardMime);
      case ExportFormat.pdf:
        if (open.isEmpty) throw const ExportProblem('These pages are locked. Unlock them to export them as a PDF.');
        final bytes = await buildPdf(
          title: nb.notebook.title,
          pages: open,
          readAsset: notifier.readAsset,
          options: pdf,
          onProgress: onProgress,
        );
        return ExportFile(fileNameFor(title, 'pdf'), bytes, pdfMime);
      case ExportFormat.image:
        if (open.isEmpty) throw const ExportProblem('This page is locked. Unlock it to export it as a picture.');
        final page = open.first;
        final images = <String, ui.Image>{};
        final decode = ref.read(imageDecoderProvider);
        try {
          for (final item in page.items) {
            if (item is ImageItem && item.picture.isNotEmpty && !images.containsKey(item.picture)) {
              final bytes = await notifier.readAsset(item.picture);
              if (bytes != null) images[item.picture] = await decode(bytes);
            }
          }
          final png = await renderPagePng(page, images);
          return ExportFile(fileNameFor(_fileTitle(nb.notebook, ExportScope.page, [indexes.first]), 'png'), png, pngMime);
        } finally {
          for (final i in images.values) {
            i.dispose();
          }
        }
    }
  }

  // Import.

  /// Imports [files] into [target]. PDFs and pictures for a new notebook go
  /// into one notebook, named after the first; each board file becomes its
  /// own notebook. Throws [ImportProblem] when nothing could be imported.
  Future<ImportOutcome> import(List<PickedFile> files, ImportTarget target, {void Function(String status)? onStatus}) async {
    final boards = <PickedFile>[], pages = <PickedFile>[], skipped = <String>[];
    for (final f in files) {
      switch (importKindOf(f)) {
        case ImportKind.board:
          boards.add(f);
        case ImportKind.pdf || ImportKind.image:
          pages.add(f);
        case ImportKind.unknown:
          skipped.add(f.name);
      }
    }
    if (boards.isEmpty && pages.isEmpty) {
      throw ImportProblem(files.length == 1
          ? '“${files.single.name}” isn’t a PDF, a picture or a board file.'
          : 'None of these are PDFs, pictures or board files.');
    }

    final made = <String>[];
    var unreadable = 0;
    final library = ref.read(libraryProvider.notifier);
    final boardFolder = target.folder ?? ref.read(libraryProvider).byId(target.notebookId!)?.folder ?? const <String>[];
    for (final f in boards) {
      onStatus?.call('Importing ${f.name}…');
      final result = await importBoardFile(_store, f.bytes, folder: boardFolder, now: _now);
      await library.addFromStore(result.notebookId);
      made.add(result.notebookId);
      unreadable += result.unreadablePages;
    }

    int? goTo;
    var pdfPages = 0, pictures = 0;
    if (pages.isNotEmpty) {
      final built = await _pages(pages, onStatus);
      pictures = built.pictures.length;
      pdfPages = built.pages.length - pictures;
      if (target.notebookId == null) {
        made.add(await _newNotebook(p.basenameWithoutExtension(pages.first.name), target.folder!, built));
      } else {
        goTo = await _intoNotebook(target, built);
      }
    }

    String count(int n, String one, String many) => n == 1 ? '1 $one' : '$n $many';
    final message = [
      if (goTo != null && pdfPages > 0) 'Added ${count(pdfPages, 'page', 'pages')}',
      if (goTo != null && pictures > 0) 'Added ${count(pictures, 'picture', 'pictures')}',
      if (made.length == 1) 'Imported “${ref.read(libraryProvider).byId(made.single)?.title ?? 'notebook'}”',
      if (made.length > 1) 'Imported ${made.length} notebooks',
      if (unreadable > 0) '${count(unreadable, 'page', 'pages')} couldn’t be read',
      if (skipped.isNotEmpty) 'Skipped ${skipped.join(', ')}',
    ].join(' · ');
    return ImportOutcome(message, openNotebook: made.length == 1 && goTo == null ? made.single : null, goToPage: goTo);
  }

  /// Pages (one per PDF page or picture) and the files they use.
  Future<_Built> _pages(List<PickedFile> files, void Function(String status)? onStatus) async {
    final out = _Built();
    final now = _now;
    final decode = ref.read(imageDecoderProvider);
    for (final f in files) {
      if (importKindOf(f) == ImportKind.image) {
        onStatus?.call('Reading ${f.name}…');
        final image = await decode(f.bytes);
        final size = importedPictureSize(image.width, image.height);
        image.dispose();
        final name = assetNameFor(f.bytes);
        out.files[name] = f.bytes;
        out.pictures.add((name, f.bytes));
        out.pages.add(BoardPage(id: newId('pg', now: now), items: [
          ImageItem(id: newId('it', now: now), x: 0, y: 0, z: 1, createdAt: now, w: size.width, h: size.height, asset: name),
        ]));
        continue;
      }
      final pdf = await ref.read(pdfReaderProvider).open(f.bytes, name: f.name);
      try {
        final asset = assetNameFor(f.bytes);
        out.files[asset] = f.bytes;
        for (var i = 0; i < pdf.pageCount; i++) {
          onStatus?.call('Reading page ${i + 1} of ${pdf.pageCount}…');
          final size = pdf.pageSize(i);
          // A poster-sized page gets a smaller picture.
          final scale = math.min(pdfPreviewScale, maxPreviewSide / math.max(size.width, size.height));
          final png = await pdf.renderPng(i, scale: scale);
          final preview = assetNameFor(png);
          out.files[preview] = png;
          out.pages.add(BoardPage(id: newId('pg', now: now), items: [
            FileItem(
              id: newId('it', now: now),
              x: 0,
              y: 0,
              z: 1,
              createdAt: now,
              w: size.width,
              h: size.height,
              asset: asset,
              mime: 'pdf',
              page: i + 1,
              preview: preview,
              name: f.name,
              text: (await pdf.text(i)).trim(),
            ),
          ]));
        }
      } finally {
        await pdf.close();
      }
    }
    return out;
  }

  Future<String> _newNotebook(String title, List<String> folder, _Built built) async {
    final now = _now;
    final id = newId('nb', now: now);
    for (final e in built.files.entries) {
      await _store.saveAsset(id, e.key, e.value);
    }
    for (final page in built.pages) {
      await _store.savePage(id, page);
    }
    await _store.saveNotebook(Notebook(
      id: id,
      title: title.trim().isEmpty ? 'Imported notebook' : title.trim(),
      folderPath: [...folder],
      createdAt: now,
      updatedAt: now,
      pageIds: [for (final p in built.pages) p.id],
    ));
    await ref.read(libraryProvider.notifier).addFromStore(id);
    return id;
  }

  /// PDF pages go after the current page; pictures go on it.
  Future<int?> _intoNotebook(ImportTarget target, _Built built) async {
    final notifier = ref.read(notebookProvider(target.notebookId!).notifier);
    final nb = ref.read(notebookProvider(target.notebookId!));
    final pdfPages = [
      for (final page in built.pages)
        if (page.items.single is FileItem) page,
    ];
    int? first;
    if (pdfPages.isNotEmpty) {
      final used = {for (final page in pdfPages) ...assetRefs(page.items.single.toJson())};
      first = await notifier.addPagesWithFiles(pdfPages, {
        for (final e in built.files.entries)
          if (used.contains(e.key)) e.key: e.value,
      }, after: target.page);
      if (first == null) throw const ImportProblem('Unlock this notebook to import into it.');
    }
    final pageId = nb.pageAt(target.page).id;
    for (final (i, (_, bytes)) in built.pictures.indexed) {
      final item = await notifier.addImage(pageId, bytes, center: target.center + Offset(24.0 * i, 24.0 * i));
      if (item == null) throw const ImportProblem('Unlock this page to add pictures to it.');
    }
    return first ?? target.page;
  }
}

class _Built {
  final pages = <BoardPage>[];
  final files = <String, Uint8List>{};

  /// Pictures, by asset name, in the order picked.
  final pictures = <(String, Uint8List)>[];
}
