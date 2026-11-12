import 'dart:io';

import '../board/codec.dart' show encodePage;
import '../board/model.dart';
import '../library/library.dart';
import '../state/notebook.dart';
import '../state/settings.dart' show boardStoreProvider;
import 'pdf_export.dart' show PdfOptions;
import 'transfer.dart';

// Share (Share.png), without a server: copies of a page, a notebook or a
// folder, sent through the share sheet (Gmail, Drive, OneDrive, messages…).
// Pages with a password are never in them: not even sealed.

/// What Share sends: this page, the notebook, or the folder it's in.
enum ShareScope { page, notebook, folder }

/// The pages of [nb] that may leave the device: not locked, and without a
/// password of their own or the notebook's (even while unlocked).
Set<String> shareablePageIds(NotebookState nb) => {
      for (final p in nb.pages)
        if (!nb.isSealed(p.id) && nb.lockFor(p.id) == null) p.id,
    };

/// The recordings and videos on [nb]'s pages: what a board file leaves out
/// without "Include audio and video".
Set<String> mediaAssetsOf(NotebookState nb) => {
      for (final p in nb.pages)
        for (final i in p.page.items)
          if (i is AudioItem)
            i.asset
          else if (i is VideoItem && i.asset != null)
            i.asset!,
    };

/// "about 9 MB" in Share's footer: [bytes] rounded the way people say it.
String sizeWords(int bytes) {
  final mb = bytes / (1024 * 1024);
  if (mb < 0.1) return '0.1 MB';
  if (mb < 10) return '${mb.toStringAsFixed(1).replaceAll('.0', '')} MB';
  return '${mb.round()} MB';
}

/// Copies to send, and what was left out.
class ShareCopies {
  const ShareCopies(this.files, {this.pagesLeftOut = 0, this.notebooksLeftOut = 0});

  final List<ExportFile> files;

  /// Pages with a password, left out.
  final int pagesLeftOut;

  /// Notebooks with a password (or nothing shareable), left out.
  final int notebooksLeftOut;

  /// "2 pages with a password were left out", or null.
  String? get leftOutNote {
    final parts = [
      if (notebooksLeftOut > 0) notebooksLeftOut == 1 ? '1 notebook with a password' : '$notebooksLeftOut notebooks with a password',
      if (pagesLeftOut > 0) pagesLeftOut == 1 ? '1 page with a password' : '$pagesLeftOut pages with a password',
    ];
    if (parts.isEmpty) return null;
    return '${parts.join(' and ')} ${pagesLeftOut + notebooksLeftOut == 1 ? 'was' : 'were'} left out.';
  }
}

extension ShareCopiesOf on Transfers {
  /// The copies of [scope] (from the open notebook [notebookId], on page
  /// [current]) in [format]. Throws [ExportProblem] when there's nothing
  /// that may be sent.
  ///
  /// [pdf]: the PDF's text layer and paper (and an image's paper); [media]:
  /// a board file's recordings and videos.
  Future<ShareCopies> shareCopies(
    String notebookId,
    ShareScope scope,
    ExportFormat format, {
    required int current,
    PdfOptions pdf = const PdfOptions(),
    bool media = true,
  }) async {
    final nb = ref.read(notebookProvider(notebookId));
    switch (scope) {
      case ShareScope.page:
        final page = nb.pageAt(current);
        if (nb.lockFor(page.id) != null || nb.isSealed(page.id)) {
          throw const ExportProblem('This page has a password, so it can’t be shared.');
        }
        return ShareCopies([
          await export(notebookId,
              scope: ExportScope.page,
              format: format,
              current: current,
              pdf: pdf,
              leaveOutAssets: media ? const {} : mediaAssetsOf(nb)),
        ]);
      case ShareScope.notebook:
        if (format == ExportFormat.image) {
          return shareCopies(notebookId, ShareScope.page, format, current: current, pdf: pdf, media: media);
        }
        final (file, left) = await _notebookCopy(notebookId, format, pdf: pdf, media: media);
        if (file == null) throw const ExportProblem('Every page here has a password, so nothing can be shared.');
        return ShareCopies([file], pagesLeftOut: left);
      case ShareScope.folder:
        final lib = ref.read(libraryProvider);
        final folder = lib.byId(notebookId)?.folder ?? const <String>[];
        if (folder.isEmpty) throw const ExportProblem('This notebook isn’t in a folder.');
        final files = <ExportFile>[];
        var pagesLeft = 0, notebooksLeft = 0;
        for (final n in lib.active.where((n) => isInside(n.folder, folder))) {
          if (n.locked) {
            notebooksLeft++;
            continue;
          }
          final (file, left) = await _withOpen(n.id, () => _notebookCopy(n.id, format, pdf: pdf, media: media));
          if (file == null) {
            notebooksLeft++;
          } else {
            files.add(file);
            pagesLeft += left;
          }
        }
        if (files.isEmpty) throw const ExportProblem('Nothing in this folder can be shared: every notebook has a password.');
        return ShareCopies(files, pagesLeftOut: pagesLeft, notebooksLeftOut: notebooksLeft);
    }
  }

  /// Notebook [id] without its pages with a password, and how many those
  /// were; no file if every page has one.
  Future<(ExportFile?, int)> _notebookCopy(String id, ExportFormat format,
      {PdfOptions pdf = const PdfOptions(), bool media = true}) async {
    final nb = ref.read(notebookProvider(id));
    final ok = shareablePageIds(nb);
    final left = nb.pages.length - ok.length;
    if (ok.isEmpty) return (null, left);
    final file = await export(
      id,
      scope: left == 0 ? ExportScope.notebook : ExportScope.pages,
      picked: ok,
      format: format,
      current: 0,
      pdf: pdf,
      leaveOutAssets: media ? const {} : mediaAssetsOf(nb),
    );
    return (file, left);
  }

  /// About how big Share's copy of [scope] will be (the footer's "about
  /// 9 MB"). From the open notebook's pages and files; other notebooks in a
  /// folder count by their pages.
  Future<int> estimateShare(String notebookId, ShareScope scope, ExportFormat format,
      {required int current, bool media = true}) async {
    final nb = ref.read(notebookProvider(notebookId));
    final store = ref.read(boardStoreProvider);
    final ok = shareablePageIds(nb);
    final pages = switch (scope) {
      ShareScope.page => [nb.pageAt(current)],
      _ when format == ExportFormat.image => [nb.pageAt(current)],
      _ => [for (final p in nb.pages) if (ok.contains(p.id)) p],
    }.map((p) => p.page).toList();
    Future<int> fileSize(String name) async {
      final path = store.assetPath(notebookId, name);
      if (path != null) {
        final f = File(path);
        if (await f.exists()) return f.length();
      }
      return (await store.loadAsset(notebookId, name))?.length ?? 0;
    }

    final mediaFiles = mediaAssetsOf(nb);
    var ink = 0, files = 0;
    final counted = <String>{};
    for (final p in pages) {
      ink += encodePage(p).length;
      for (final i in p.items) {
        final name = switch (i) {
          ImageItem(:final asset) => asset,
          AudioItem(:final asset) => asset,
          VideoItem(:final asset?) => asset,
          _ => null,
        };
        if (name == null || !counted.add(name)) continue;
        if (mediaFiles.contains(name) && (format != ExportFormat.board || !media)) continue;
        files += await fileSize(name);
      }
    }
    var bytes = switch (format) {
      ExportFormat.pdf => (ink * 0.6).round() + files + 40 * 1024 * pages.length,
      ExportFormat.board => (ink * 0.3).round() + files,
      ExportFormat.image => (ink * 0.8).round() + 300 * 1024,
    };
    if (scope == ShareScope.folder && format != ExportFormat.image) {
      final lib = ref.read(libraryProvider);
      final folder = lib.byId(notebookId)?.folder ?? const <String>[];
      for (final n in lib.active.where((n) => n.id != notebookId && isInside(n.folder, folder) && !n.locked)) {
        bytes += n.pageCount * (format == ExportFormat.pdf ? 120 : 40) * 1024;
      }
    }
    return bytes;
  }

  /// Runs [task] with notebook [id] open (loaded, if it wasn't).
  Future<T> _withOpen<T>(String id, Future<T> Function() task) async {
    final loaded = ref.listen(loadedNotebookProvider(id), (_, _) {});
    try {
      await ref.read(loadedNotebookProvider(id).future);
      final open = ref.listen(notebookProvider(id), (_, _) {});
      try {
        return await task();
      } finally {
        open.close();
      }
    } finally {
      loaded.close();
    }
  }
}
