import '../library/library.dart';
import '../state/notebook.dart';
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
  Future<ShareCopies> shareCopies(String notebookId, ShareScope scope, ExportFormat format, {required int current}) async {
    final nb = ref.read(notebookProvider(notebookId));
    switch (scope) {
      case ShareScope.page:
        final page = nb.pageAt(current);
        if (nb.lockFor(page.id) != null || nb.isSealed(page.id)) {
          throw const ExportProblem('This page has a password, so it can’t be shared.');
        }
        return ShareCopies([await export(notebookId, scope: ExportScope.page, format: format, current: current)]);
      case ShareScope.notebook:
        if (format == ExportFormat.image) {
          return shareCopies(notebookId, ShareScope.page, format, current: current);
        }
        final (file, left) = await _notebookCopy(notebookId, format);
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
          final (file, left) = await _withOpen(n.id, () => _notebookCopy(n.id, format));
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
  Future<(ExportFile?, int)> _notebookCopy(String id, ExportFormat format) async {
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
    );
    return (file, left);
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
