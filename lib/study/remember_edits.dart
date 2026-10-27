import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/codec.dart' show withRemember;
import '../board/model.dart';
import '../recognition/handwriting_index.dart';
import '../state/notebook.dart';
import 'remember.dart';
import 'study_rows.dart';
import 'study_state.dart';

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
      // Its flashcards and what's remembered reach the index while it's open.
      await ref.read(handwritingIndexProvider).studyNow();
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

/// Deletes [copies] (StudySnapshot.copies): the hidden copies of cards in
/// notebooks imported again, and how well they were known. The notes they
/// were made from stay. Returns how many went.
Future<int> deleteCardCopies(WidgetRef ref, List<StudyCard> copies) async {
  final byNotebook = <String, List<StudyCard>>{};
  for (final c in copies) {
    (byNotebook[c.notebookId] ??= []).add(c);
  }
  var gone = 0;
  for (final MapEntry(key: notebookId, value: cards) in byNotebook.entries) {
    final ids = {for (final c in cards) c.id};
    await editNotebook(ref, notebookId, (n, s) {
      for (final pageId in {for (final c in cards) c.pageId}) {
        final i = s.indexOf(pageId);
        if (i < 0 || s.isSealed(pageId)) continue;
        final here = [
          for (final item in s.pages[i].page.items)
            if (item is FlashcardItem && ids.contains(item.id)) item.id,
        ];
        gone += here.length;
        n.removeItems(pageId, here);
      }
    });
    await ref.read(studyProvider.notifier).dropCards(notebookId, ids);
  }
  await ref.read(studyProvider.notifier).refresh();
  return gone;
}
