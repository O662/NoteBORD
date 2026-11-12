# Making flashcards

Turn on Make flashcards, circle the front with the lasso, then circle the back (ink, pictures and typed text all work), and press Add card. You can pick a deck and turn on "also quiz me back to front". The card points at the items on the page instead of copying them, so it changes when your notes change.

This is a copy for reading. The code lives in the Endless app (Flutter/Dart). Whole files are copied as they are. From the big canvas file (`lib/canvas/ink_canvas.dart`) only the parts this feature uses are copied, with their line numbers, so some of them start or end partway through a method.

## The making-cards mode (front, back, deck)

### `lib/canvas/flashcard_mode.dart` (whole file)

```dart
import 'package:flutter/widgets.dart';

// Making flashcards (FlashMake.png): circle the front, then the back, then
// Add card. What the screen's chrome and the canvas share.

/// One side being circled: the items and the loop drawn round them (page
/// space; null when it was picked another way).
@immutable
class CircledSide {
  const CircledSide(this.ids, [this.loop]);

  final List<String> ids;
  final Path? loop;
}

class FlashcardMode extends ChangeNotifier {
  bool _on = false;
  CircledSide? _front;
  CircledSide? _back;
  bool _reverse = false;
  String _deckId = '';
  String _deckName = '';
  String? _added;
  int _serial = 0;

  /// Making flashcards is on.
  bool get on => _on;

  CircledSide? get front => _front;
  CircledSide? get back => _back;

  /// "Also quiz me back to front".
  bool get reverse => _reverse;
  set reverse(bool v) {
    if (v == _reverse) return;
    _reverse = v;
    notifyListeners();
  }

  /// The deck new cards go into.
  String get deckId => _deckId;
  String get deckName => _deckName;

  /// The deck a card was just added to ("Card added to … · Study now"),
  /// until the next one is circled.
  String? get addedTo => _added;

  /// Changes each time a card is added (the screen's message keys on it).
  int get serial => _serial;

  bool get ready => _front != null && _back != null;

  /// Starts, into deck [deckId]; [front] is what's already selected.
  void start({required String deckId, required String deckName, CircledSide? front}) {
    _on = true;
    _deckId = deckId;
    _deckName = deckName;
    _front = front != null && front.ids.isNotEmpty ? front : null;
    _back = null;
    _added = null;
    notifyListeners();
  }

  void end() {
    if (!_on) return;
    _on = false;
    _front = null;
    _back = null;
    _added = null;
    notifyListeners();
  }

  void pickDeck(String id, String name) {
    _deckId = id;
    _deckName = name;
    notifyListeners();
  }

  /// Something was circled: it's the front, then the back. Circling again
  /// with both done changes the back.
  void circled(CircledSide side) {
    if (side.ids.isEmpty) return;
    _added = null;
    if (_front == null) {
      _front = side;
    } else {
      _back = side;
    }
    notifyListeners();
  }

  /// Clear: start the card again.
  void clear() {
    _front = null;
    _back = null;
    notifyListeners();
  }

  /// The card was added: on to the next one.
  void added() {
    _added = _deckName;
    _serial++;
    _front = null;
    _back = null;
    notifyListeners();
  }
}
```

## Its steps: start, pick a deck, add the card

### `lib/ui/study/flash_actions.dart` (whole file)

```dart
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
```

## Circling on the page

### `lib/canvas/ink_canvas_study.dart`, lines 1–53

What was circled (or tapped) becomes the front, then the back.

```dart
part of 'ink_canvas.dart';

// Need to remember and flashcards on the canvas (RememberMark.png,
// FlashMake.png): Remember this for a selection, a star drawn next to
// something, the yellow wash and chips on what's remembered, and circling
// the front and back of a flashcard.

extension _CanvasStudy on InkCanvasState {
  void _cardsChanged() {
    if (mounted) _rebuild();
  }

  /// The topmost stroke or object under [at] (a tap with the lasso).
  Item? _topAt(Offset at) {
    final page = _page;
    final r = 10 * _unit;
    final ids = page.index.query(Rect.fromCircle(center: at, radius: r));
    for (final item in page.items.reversed) {
      if (!ids.contains(item.id)) continue;
      switch (item) {
        case StrokeItem s when strokeHit(s, at, at, r):
          return s;
        case BoxItem b when boxHit(b, at, slop: 4 * _unit):
          return b;
        default:
          continue;
      }
    }
    return null;
  }

  /// Making flashcards: what was circled (or tapped) is the front, then
  /// the back.
  void _circleForCard(List<Offset> loop) {
    if (loop.isEmpty) return;
    if (loop.length < 3 || pathLength(loop) < 20 * _unit) {
      final top = _topAt(loop.first);
      if (top != null) pane.cards.circled(CircledSide([top.id]));
      return;
    }
    final picked = itemsInPolygon(loop, _selectable(InkCanvasState._boundsOf(loop)));
    if (picked.isEmpty) return;
    pane.cards.circled(CircledSide([for (final i in picked) i.id], Path()..addPolygon(loop, true)));
  }

  /// The Remember toolbar's Flashcard: making flashcards, with what's
  /// selected as the front.
  void _flashcardFromSelection() {
    final ids = [for (final i in _selected) i.id];
    final loop = _selection.outlineAt(_nb.revision);
    widget.onFlashcards?.call(CircledSide(ids, loop));
  }

```

### `lib/canvas/ink_canvas_study.dart`, lines 186–200

```dart
  void _deleteCard(FlashcardItem card) {
    _notebook.removeItems(_page.id, [card.id]);
    _toast('Deleted the card');
  }

  /// The loop around a side being circled, or a box around its items.
  Path? _sidePath(CircledSide? side) {
    if (side == null) return null;
    if (side.loop case final loop?) return loop;
    final r = itemsBounds([for (final id in side.ids) ?_page[id]]);
    if (r == null) return null;
    return Path()..addRRect(RRect.fromRectAndRadius(r.inflate(12), const Radius.circular(18)));
  }

  // What's drawn for them.
```

### `lib/canvas/ink_canvas.dart`, lines 1758–1760

When making cards, a finished lasso loop circles a side instead of selecting.

```dart
  void _finishLasso() {
    final loop = _overlay.lasso;
    if (pane.cards.on) return _circleForCard(loop);
```

### `lib/canvas/ink_canvas.dart`, lines 1921–1926

Flashcard on the selection toolbar.

```dart
          showComingSoon(context, 'Making flashcards here');
        } else {
          _flashcardFromSelection();
        }
      case SelectionAction.color:
        setState(() => _colorsOpen = !_colorsOpen);
```

## The bar, hint and New card panel

### `lib/ui/study/flash_widgets.dart` (whole file)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../board/model.dart';
import '../../canvas/flashcard_mode.dart';
import '../../canvas/pane.dart';
import '../../state/notebook.dart';
import '../../study/study_state.dart';
import '../../theme/colors.dart';
import '../common.dart';
import '../dialogs.dart';
import '../icons.dart';
import 'flash_actions.dart';
import 'item_preview.dart';
import 'study_format.dart';

// Making flashcards' chrome (FlashMake.png): the dark bar in the tool
// pill's place, the hint over the page, and the New card panel.

/// "Making flashcards · Deck: Physics — Momentum ▾ · Done".
class FlashBar extends ConsumerWidget {
  const FlashBar({super.key, required this.pane, required this.onDone, this.compact = false});

  final Pane pane;
  final VoidCallback onDone;

  /// Narrow screens: no "Making flashcards" title.
  final bool compact;

  Future<void> _pickDeck(BuildContext context, WidgetRef ref, Offset at) async {
    final decks = ref.read(decksProvider);
    final picked = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx + 1, at.dy + 1),
      items: [
        for (final d in decks)
          CheckedPopupMenuItem(value: d.id, checked: d.id == pane.cards.deckId, child: Text(d.name)),
        const PopupMenuDivider(),
        const PopupMenuItem(value: '', child: Text('New deck…')),
      ],
    );
    if (picked == null || !context.mounted) return;
    if (picked.isEmpty) {
      final name = await showNamePrompt(context, title: 'New deck', action: 'Create');
      if (name == null || name.trim().isEmpty || !context.mounted) return;
      pickDeck(ref, pane, ref.read(decksProvider.notifier).add(name));
      return;
    }
    final deck = ref.read(decksProvider.notifier).byId(picked);
    if (deck != null) pickDeck(ref, pane, deck);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: pane.cards,
      builder: (context, _) => Semantics(
        container: true,
        label: 'Flashcard mode',
        explicitChildNodes: true,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
          decoration: BoxDecoration(
            color: c.inverse,
            borderRadius: BorderRadius.circular(16),
            boxShadow: c.pillShadow,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
            EIcon(EIcons.flashcards, size: 20, color: c.onInverse),
            if (!compact) Text('Making flashcards', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.onInverse)),
            Builder(
              builder: (context) => Semantics(
                button: true,
                label: 'Deck: ${pane.cards.deckName}. Change deck',
                excludeSemantics: true,
                child: Material(
                  color: c.inverseRaised,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      final box = context.findRenderObject() as RenderBox;
                      _pickDeck(context, ref, box.localToGlobal(Offset(0, box.size.height + 6)));
                    },
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                        Flexible(
                          child: Text(
                            'Deck: ${pane.cards.deckName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.onInverse),
                          ),
                        ),
                        EIcon(EIcons.chevronDown, size: 14, color: c.onInverse),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
            Semantics(
              button: true,
              label: 'Done making flashcards',
              excludeSemantics: true,
              child: Material(
                color: c.surface,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onDone,
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    child: Text('Done', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text)),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Over the page: what to circle next, or "Card added to … · Study now".
class FlashHint extends StatelessWidget {
  const FlashHint({super.key, required this.mode, required this.onStudy});

  final FlashcardMode mode;
  final VoidCallback onStudy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: mode,
      builder: (context, _) {
        final added = mode.addedTo;
        if (added != null) {
          return Semantics(
            liveRegion: true,
            explicitChildNodes: true,
            child: Container(
              key: ValueKey(mode.serial),
              padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
              decoration: BoxDecoration(color: c.inverse, borderRadius: BorderRadius.circular(999)),
              child: Row(mainAxisSize: MainAxisSize.min, spacing: 12, children: [
                Text('Card added to $added', style: TextStyle(fontSize: 14, color: c.onInverse)),
                Semantics(
                  button: true,
                  label: 'Study now',
                  excludeSemantics: true,
                  child: Material(
                    color: c.inverseRaised,
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: onStudy,
                      child: Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.center,
                        child: Text('Study now', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.onInverse)),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          );
        }
        return Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${flashHint(mode)} · images, typed text and ink all work',
              style: TextStyle(fontSize: 14, color: c.text),
            ),
          ),
        );
      },
    );
  }
}

/// "New card 4" (FlashMake.png): the front and back as circled, "Also quiz
/// me back to front", Clear and Add card.
class NewCardPanel extends ConsumerWidget {
  const NewCardPanel({super.key, required this.pane, required this.onAdd});

  static const width = 620.0;

  final Pane pane;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final nb = ref.watch(notebookProvider(pane.notebookId));
    final page = nb.pageAt(pane.page);
    final snapshot = ref.watch(studyProvider) ?? StudySnapshot.empty;
    final summaries = deckSummaries(snapshot, ref.watch(decksProvider), DateTime.now().toUtc());
    return ListenableBuilder(
      listenable: pane.cards,
      builder: (context, _) {
        final mode = pane.cards;
        // Cards in the deck: the index's from other notebooks, and this
        // notebook's as they are now.
        final elsewhere = {
          for (final s in summaries)
            if (s.deck.id == mode.deckId)
              for (final i in s.items)
                if (i.card.notebookId != pane.notebookId) i.card.id,
        }.length;
        final here = [
          for (final p in nb.pages)
            for (final i in p.items)
              if (i is FlashcardItem && i.deck == mode.deckId) i,
        ].length;
        final count = elsewhere + here;

        List<Item> items(CircledSide? side) => [for (final id in side?.ids ?? const <String>[]) ?page[id]];

        Widget side(String label, CircledSide? s, Color border, Color labelColor, String waiting) {
          final shown = items(s);
          final box = SizedBox(
            height: 118,
            child: Stack(children: [
              Positioned(
                left: 10,
                top: 8,
                child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.88, color: labelColor)),
              ),
              Positioned.fill(
                top: 24,
                left: 14,
                right: 14,
                bottom: 10,
                child: shown.isEmpty
                    ? Center(child: Text(waiting, style: TextStyle(fontSize: 14, color: c.textMuted)))
                    : ItemsPreview(items: shown, images: page.images, maxScale: 1.2, label: '$label of the new card'),
              ),
            ]),
          );
          if (shown.isEmpty) {
            return DecoratedBox(
              decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(12)),
              child: DashedBorder(color: c.lineStrong, radius: 12, child: box),
            );
          }
          return DecoratedBox(
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: border, width: 1.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: box,
          );
        }

        return Semantics(
          container: true,
          label: 'New flashcard',
          explicitChildNodes: true,
          child: Container(
            width: NewCardPanel.width,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(18),
              boxShadow: c.dialogShadow,
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
              Row(spacing: 10, children: [
                Expanded(child: Text('New card ${count + 1}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.text))),
                Text('${cardsLabel(count)} in this deck so far', style: TextStyle(fontSize: 13, color: c.textMuted)),
              ]),
              Row(spacing: 12, children: [
                Expanded(child: side('FRONT', mode.front, c.accent, c.accentDeep, 'Circle the front')),
                Expanded(
                  child: side('BACK', mode.back, c.clay, c.clayDeep, mode.front == null ? 'Then the back' : 'Now circle the back'),
                ),
              ]),
              Row(spacing: 8, children: [
                Expanded(
                  child: Semantics(
                    checked: mode.reverse,
                    label: 'Also quiz me back to front',
                    excludeSemantics: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => mode.reverse = !mode.reverse,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Row(spacing: 10, children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: Checkbox(
                              value: mode.reverse,
                              onChanged: (v) => mode.reverse = v ?? false,
                              activeColor: c.accent,
                              side: BorderSide(color: c.lineStrong, width: 1.5),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          Text('Also quiz me back to front', style: TextStyle(fontSize: 14, color: c.text)),
                        ]),
                      ),
                    ),
                  ),
                ),
                SecondaryButton(label: 'Clear', height: 44, onPressed: mode.front == null ? null : mode.clear),
                PrimaryButton(label: 'Add card', height: 44, onPressed: mode.ready ? onAdd : null),
              ]),
            ]),
          ),
        );
      },
    );
  }
}
```

## How a card is stored

### `lib/board/model.dart`, lines 3048–3138

```dart
/// One side of a flashcard: items on the page it was made on, by id (drawn
/// as they are now, so the card follows the notes), and typed [text] (a
/// word's definition, a "why it matters" note).
@immutable
class CardSide {
  const CardSide({this.ids = const [], this.text = ''});

  factory CardSide.fromJson(Object? json) {
    if (json is! Map) return const CardSide();
    return CardSide(
      ids: [...?(json['ids'] as List?)?.whereType<String>()],
      text: json['text'] as String? ?? '',
    );
  }

  final List<String> ids;
  final String text;

  bool get isEmpty => ids.isEmpty && text.trim().isEmpty;

  Json toJson() => {
        if (ids.isNotEmpty) 'ids': ids,
        if (text.isNotEmpty) 'text': text,
      };
}

/// A flashcard made on this page (FlashMake.png): its front and back, the
/// deck it's in, and whether it's also asked back to front. It isn't drawn
/// and can't be selected; `x`/`y` is where its front was when it was made.
/// How well it's known lives in the package's `study.json`.
class FlashcardItem extends Item {
  FlashcardItem({
    required super.id,
    required super.x,
    required super.y,
    required super.z,
    required super.createdAt,
    super.author,
    super.remember,
    super.extra,
    required this.deck,
    required this.deckName,
    required this.front,
    required this.back,
    this.reverse = false,
  });

  /// The deck's id (`dk_…`), and its name when the card was made, so a
  /// board file brings its deck along.
  final String deck;
  final String deckName;
  final CardSide front;
  final CardSide back;

  /// "Also quiz me back to front".
  final bool reverse;

  @override
  String get type => 'flashcard';

  @override
  Rect get bounds => Rect.fromLTWH(x, y, 1, 1);

  FlashcardItem copyWith({String? deck, String? deckName, CardSide? front, CardSide? back, bool? reverse}) =>
      FlashcardItem(
        id: id,
        x: x,
        y: y,
        z: z,
        createdAt: createdAt,
        author: author,
        remember: remember,
        extra: extra,
        deck: deck ?? this.deck,
        deckName: deckName ?? this.deckName,
        front: front ?? this.front,
        back: back ?? this.back,
        reverse: reverse ?? this.reverse,
      );

  @override
  Json toJson() => {
        ...baseJson(),
        'deck': deck,
        'deckName': deckName,
        'reverse': reverse,
        'front': front.toJson(),
        'back': back.toJson(),
      };
}

```

### `lib/study/study_state.dart`, lines 21–108

Decks, saved in decks.json.

```dart
class Deck {
  const Deck({required this.id, required this.name, required this.createdAt});

  static Deck? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String) return null;
    return Deck(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '')?.toUtc() ?? DateTime.utc(2026),
    );
  }

  final String id;
  final String name;
  final DateTime createdAt;

  Json toJson() => {'id': id, 'name': name, 'createdAt': createdAt.toUtc().toIso8601String()};
}

/// The decks in [json] (a decks.json).
List<Deck> decksFromJson(Json? json) => [
      for (final d in (json?['decks'] as List? ?? const [])) ?Deck.fromJson(d),
    ];

/// The decks as the app started (bootstrap loads decks.json).
final initialDecksProvider = Provider<List<Deck>>((ref) => const []);

final decksProvider = NotifierProvider<Decks, List<Deck>>(Decks.new);

class Decks extends Notifier<List<Deck>> {
  @override
  List<Deck> build() => ref.read(initialDecksProvider);

  Deck? byId(String id) => state.where((d) => d.id == id).firstOrNull;

  /// A new deck called [name] (or the one already called that).
  Deck add(String name) {
    final trimmed = name.trim();
    final same = state.where((d) => d.name.toLowerCase() == trimmed.toLowerCase()).firstOrNull;
    if (same != null) return same;
    final now = ref.read(clockProvider)().toUtc();
    final deck = Deck(id: newId('dk', now: now), name: trimmed, createdAt: now);
    state = [...state, deck];
    _save();
    return deck;
  }

  /// Makes sure deck [id] is listed, as [name] (cards from another device
  /// bring their deck's name along).
  void ensure(String id, String name) {
    if (id.isEmpty || byId(id) != null) return;
    state = [...state, Deck(id: id, name: name.isEmpty ? 'Flashcards' : name, createdAt: ref.read(clockProvider)().toUtc())];
    _save();
  }

  /// The deck new cards go into: the one used last, else a new one named
  /// after [notebookTitle].
  Deck current(String notebookTitle) {
    final last = ref.read(settingsProvider).lastDeck;
    final deck = (last == null ? null : byId(last)) ?? add(notebookTitle.trim().isEmpty ? 'Flashcards' : notebookTitle);
    if (deck.id != last) use(deck);
    return deck;
  }

  /// New cards go into [deck] from now on.
  void use(Deck deck) => ref.read(settingsProvider.notifier).apply((s) => s.copyWith(lastDeck: () => deck.id));

  /// Decks changed on another device (cloud sync): from [from] to [to]
  /// (deck JSON by id). Decks made here since stay.
  void applyRemote(Map<String, Object?> from, Map<String, Object?> to) {
    final out = [
      for (final d in state)
        if (!from.containsKey(d.id) || to.containsKey(d.id)) Deck.fromJson(to[d.id]) ?? d,
      for (final e in to.entries)
        if (!state.any((d) => d.id == e.key)) ?Deck.fromJson(e.value),
    ];
    state = out;
    _save(signal: false);
  }

  void _save({bool signal = true}) {
    final json = {'version': 1, 'decks': [for (final d in state) d.toJson()]};
    final store = ref.read(boardStoreProvider);
    ref.read(writeQueueProvider).run(() => store.saveDecks(json));
    if (signal) ref.read(localChangesProvider).changed();
  }
}

```

