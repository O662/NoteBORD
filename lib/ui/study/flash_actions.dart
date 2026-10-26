import 'dart:ui' show Offset, Rect;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../board/ids.dart';
import '../../board/model.dart';
import '../../canvas/flashcard_mode.dart';
import '../../canvas/pane.dart';
import '../../library/library.dart';
import '../../state/notebook.dart';
import '../../state/settings.dart';
import '../../study/study_state.dart';

// Making flashcards (FlashMake.png): its steps, shared by the Canvas screen
// and the canvas (the Remember toolbar's Flashcard).

/// The hint above the page while making cards.
String flashHint(FlashcardMode mode) {
  if (mode.ready) return 'Front and back circled';
  if (mode.front != null) return 'Now circle the back';
  return 'Circle the front, then the back';
}

/// Making flashcards in [pane]: the lasso circles, into the deck used last.
/// [front] is what's already selected (the Remember toolbar's Flashcard).
void startFlashcards(WidgetRef ref, Pane pane, {CircledSide? front}) {
  pane
    ..dismiss()
    ..selection.clear();
  if (pane.math.on) pane.math.end();
  final title = ref.read(libraryProvider).byId(pane.notebookId)?.title ?? '';
  final deck = ref.read(decksProvider.notifier).current(title);
  pane.cards.start(deckId: deck.id, deckName: deck.name, front: front);
  ref.read(settingsProvider.notifier).apply((s) => s.copyWith(tool: CanvasTool.lasso));
}

/// Done: back to the pen.
void endFlashcards(WidgetRef ref, Pane pane) {
  pane.cards.end();
  ref.read(settingsProvider.notifier).apply((s) => s.copyWith(tool: CanvasTool.pen));
}

/// New cards go into [deck].
void pickDeck(WidgetRef ref, Pane pane, Deck deck) {
  ref.read(decksProvider.notifier).use(deck);
  pane.cards.pickDeck(deck.id, deck.name);
}

Rect? _around(Iterable<Item> items) {
  Rect? r;
  for (final i in items) {
    r = r == null ? i.extent : r.expandToInclude(i.extent);
  }
  return r;
}

/// Add card: the card circled, on the page (one undo step). Null if it
/// isn't ready or the page can't be written to.
FlashcardItem? addCard(WidgetRef ref, Pane pane) {
  final mode = pane.cards;
  final front = mode.front, back = mode.back;
  if (front == null || back == null) return null;
  final nb = ref.read(notebookProvider(pane.notebookId));
  final page = nb.pageAt(pane.page);
  if (nb.isSealed(page.id)) return null;
  List<String> here(List<String> ids) => [for (final id in ids) if (page[id] != null) id];
  final f = here(front.ids), b = here(back.ids);
  if (f.isEmpty || b.isEmpty) return null;
  final now = DateTime.now().toUtc();
  final at = _around([for (final id in f) page[id]!])?.topLeft ?? Offset.zero;
  final card = FlashcardItem(
    id: newId('fc', now: now),
    x: at.dx,
    y: at.dy,
    z: page.nextZ,
    createdAt: now,
    deck: mode.deckId,
    deckName: mode.deckName,
    front: CardSide(ids: f),
    back: CardSide(ids: b),
    reverse: mode.reverse,
  );
  ref.read(notebookProvider(pane.notebookId).notifier).insertItems(page.id, [card]);
  mode.added();
  return card;
}

/// A card of typed text on the page shown in [pane], into the deck used
/// last (the dictionary's Make flashcard). Null if the page is locked.
FlashcardItem? addTextCard(WidgetRef ref, Pane pane, {required String front, required String back}) {
  final nb = ref.read(notebookProvider(pane.notebookId));
  final page = nb.pageAt(pane.page);
  if (nb.isSealed(page.id)) return null;
  final title = ref.read(libraryProvider).byId(pane.notebookId)?.title ?? '';
  final deck = ref.read(decksProvider.notifier).current(title);
  final now = DateTime.now().toUtc();
  final at = pane.view.size.isEmpty ? Offset.zero : pane.view.toPage(pane.view.size.center(Offset.zero));
  final card = FlashcardItem(
    id: newId('fc', now: now),
    x: at.dx,
    y: at.dy,
    z: page.nextZ,
    createdAt: now,
    deck: deck.id,
    deckName: deck.name,
    front: CardSide(text: front),
    back: CardSide(text: back),
  );
  ref.read(notebookProvider(pane.notebookId).notifier).insertItems(page.id, [card]);
  return card;
}
