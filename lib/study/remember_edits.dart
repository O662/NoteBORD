import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/codec.dart' show withRemember;
import '../board/model.dart';
import '../state/notebook.dart';
import 'remember.dart';
import 'study_rows.dart';

/// Opens notebook [notebookId] (if it isn't open), runs [edit] on it, and
/// saves. The notebook closes again once nothing else shows it.
Future<void> editNotebook(WidgetRef ref, String notebookId, void Function(NotebookNotifier n, NotebookState s) edit) async {
  final loaded = ref.listenManual(loadedNotebookProvider(notebookId), (_, _) {});
  try {
    await ref.read(loadedNotebookProvider(notebookId).future);
    final open = ref.listenManual(notebookProvider(notebookId), (_, _) {});
    try {
      final notifier = ref.read(notebookProvider(notebookId).notifier);
      edit(notifier, ref.read(notebookProvider(notebookId)));
      await notifier.flush();
    } finally {
      open.close();
    }
  } finally {
    loaded.close();
  }
}

/// Unstars [thing] (Remember.png's star): its items are no longer marked.
/// Returns their marks as they were, by item id, to star it again.
Future<Map<String, Json>> forgetThing(WidgetRef ref, RememberedThing thing) async {
  final was = <String, Json>{};
  await editNotebook(ref, thing.notebookId, (n, s) {
    final i = s.indexOf(thing.pageId);
    if (i < 0 || s.isSealed(thing.pageId)) return;
    final page = s.pages[i];
    final marked = [
      for (final item in page.items)
        if (item is! FlashcardItem && RememberMark.of(item)?.id == thing.id) item,
    ];
    for (final item in marked) {
      was[item.id] = item.remember!;
    }
    n.replaceItems(thing.pageId, [for (final item in marked) withRemember(item, null)]);
  });
  return was;
}

/// Stars it again, with the marks [was] as they were.
Future<void> restoreThing(WidgetRef ref, RememberedThing thing, Map<String, Json> was) async {
  await editNotebook(ref, thing.notebookId, (n, s) {
    final i = s.indexOf(thing.pageId);
    if (i < 0 || s.isSealed(thing.pageId)) return;
    final page = s.pages[i];
    n.replaceItems(thing.pageId, [
      for (final e in was.entries)
        if (page[e.key] case final item?) withRemember(item, e.value),
    ]);
  });
}
