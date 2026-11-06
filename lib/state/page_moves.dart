import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/codec.dart';
import 'notebook.dart';

/// A page moved to another notebook, to undo.
class MovedPage {
  const MovedPage({required this.from, required this.to, required this.pageId, required this.index});

  final String from;
  final String to;
  final String pageId;

  /// Where it was in [from].
  final int index;
}

/// Runs [task] with notebook [id] open (loaded and kept until [task] and
/// its save finish), whether or not anything shows it.
Future<T> withNotebook<T>(ProviderContainer container, String id, Future<T> Function(NotebookNotifier n) task) async {
  // Both providers go once nothing listens, so they're listened to here.
  final load = container.listen(loadedNotebookProvider(id), (_, _) {});
  ProviderSubscription<NotebookState>? sub;
  try {
    await container.read(loadedNotebookProvider(id).future);
    sub = container.listen(notebookProvider(id), (_, _) {});
    final notifier = container.read(notebookProvider(id).notifier);
    final result = await task(notifier);
    await notifier.flush();
    return result;
  } finally {
    sub?.close();
    load.close();
  }
}

/// Moves page [pageId] of notebook [from] to the end of notebook [to], with
/// its files. Returns what to undo, or a message saying why it can't move.
Future<(MovedPage?, String?)> movePage(ProviderContainer container, String from, String pageId, String to) async {
  if (from == to) return (null, null);
  final source = container.read(notebookProvider(from).notifier);
  final why = source.cantCopyOut(pageId, moving: true) ?? source.cantDelete(pageId);
  if (why != null) return (null, why);
  final state = container.read(notebookProvider(from));
  final index = state.indexOf(pageId);
  if (index < 0) return (null, null);
  final files = await source.filesOf(pageId);
  if (files == null) return (null, 'Couldn’t read this page’s pictures and files.');
  final page = decodePage(encodePage(state.pages[index].page));
  final added = await withNotebook(container, to, (target) => target.addPagesWithFiles([page], files));
  if (added == null) return (null, 'Unlock that notebook to move pages into it.');
  source.removePage(pageId, force: true);
  await source.flush();
  return (MovedPage(from: from, to: to, pageId: pageId, index: index), null);
}

/// Undoes [movePage]: the page goes back where it was.
Future<void> undoMove(ProviderContainer container, MovedPage moved) async {
  final page = await withNotebook(container, moved.to, (target) async => target.removePage(moved.pageId, force: true));
  if (page == null) return;
  await withNotebook(container, moved.from, (source) async => source.restorePage(page.$1, moved.index));
}
