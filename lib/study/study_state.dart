import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/ids.dart';
import '../board/model.dart';
import '../library/library.dart';
import '../recognition/handwriting_index.dart';
import '../state/notebook.dart' show writeQueueProvider;
import '../state/settings.dart';
import 'fsrs.dart';
import 'session.dart';
import 'study_rows.dart';

// Flashcards and Need to remember across every notebook: the decks
// (decks.json), how well each card is known (each package's study.json),
// and what the index has gathered from the pages.

@immutable
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

  void _save() {
    final json = {'version': 1, 'decks': [for (final d in state) d.toJson()]};
    final store = ref.read(boardStoreProvider);
    ref.read(writeQueueProvider).run(() => store.saveDecks(json));
  }
}


/// Everything remembered and every flashcard, as the index has them
/// (notebooks in the Trash or with a password left out), with how well
/// each card is known.
@immutable
class StudySnapshot {
  const StudySnapshot({required this.remembered, required this.cards, required this.states});

  static const empty = StudySnapshot(remembered: [], cards: [], states: {});

  final List<RememberedThing> remembered;
  final List<StudyCard> cards;

  /// [StudyItem.key] → how well it's known.
  final Map<String, CardState> states;

  /// Every way of asking every card.
  List<StudyItem> get items => studyItems(cards, states);

  /// How many cards are due at [now], in every deck (the sidebar's badge).
  int dueAt(DateTime now) => items.where((i) => i.dueAt(now)).length;

  StudySnapshot withState(String key, CardState s) =>
      StudySnapshot(remembered: remembered, cards: cards, states: {...states, key: s});
}

/// The study data, read again whenever the index or the library changes.
/// Null until first read.
final studyProvider = NotifierProvider<StudyData, StudySnapshot?>(StudyData.new);

class StudyData extends Notifier<StudySnapshot?> {
  /// Each notebook's study.json as read (unknown entries are kept).
  final _files = <String, Json>{};
  bool _alive = true;
  bool _asked = false;
  Future<void>? _reading;
  bool _again = false;

  @override
  StudySnapshot? build() {
    final index = ref.read(handwritingIndexProvider);
    index.revision.addListener(_changed);
    ref.listen(libraryProvider, (_, _) => _changed());
    ref.onDispose(() {
      _alive = false;
      index.revision.removeListener(_changed);
    });
    _changed();
    return null;
  }

  /// Read again soon. The index can change while a notebook is being
  /// closed (inside another provider's dispose), so never right away.
  void _changed() {
    if (_asked) return;
    _asked = true;
    Future.microtask(() {
      _asked = false;
      if (_alive) refresh();
    });
  }

  /// Reads the index again (after anything just changed on an open page)
  /// and returns once the new data is in [state].
  Future<void> refresh() {
    if (_reading != null) {
      _again = true;
      return _reading!;
    }
    return _reading = () async {
      try {
        do {
          _again = false;
          await _read();
        } while (_again && _alive);
      } finally {
        _reading = null;
      }
    }();
  }

  Future<void> _read() async {
    final index = ref.read(handwritingIndexProvider);
    await index.studyNow();
    final rows = await ref.read(indexDbProvider).studyRows();
    if (!_alive) return;
    final library = ref.read(libraryProvider);
    final remembered = <RememberedThing>[];
    final cards = <StudyCard>[];
    for (final r in rows) {
      final nb = library.byId(r.notebookId);
      if (nb == null || nb.trashed || nb.locked) continue;
      switch (r.kind) {
        case StudyKind.remember:
          remembered.add(RememberedThing.fromRow(r));
        case StudyKind.card:
          cards.add(StudyCard.fromRow(r));
      }
    }
    final store = ref.read(boardStoreProvider);
    for (final nb in {for (final c in cards) c.notebookId}) {
      if (_files.containsKey(nb)) continue;
      _files[nb] = await store.loadStudy(nb) ?? {'version': 1, 'cards': <String, dynamic>{}};
    }
    if (!_alive) return;
    // Decks that came with a board file are listed too.
    final decks = ref.read(decksProvider.notifier);
    for (final c in cards) {
      if (decks.byId(c.deck) == null) decks.ensure(c.deck, c.deckName);
    }
    final states = _parse();
    state = StudySnapshot(
      remembered: oneOfEach(remembered, (t) => t.id, (t) => t.notebookId),
      cards: oneOfEach(cards, (c) => c.id, (c) => c.notebookId, lastStudied: (c) => _lastStudied(c, states)),
      states: states,
    );
  }

  /// When [card] was last studied, either way round, or null if never.
  static DateTime? _lastStudied(StudyCard card, Map<String, CardState> states) {
    DateTime? last;
    for (final side in const ['f', 'r']) {
      final at = states['${card.notebookId}/${card.id}/$side']?.lastReview;
      if (at != null && (last == null || at.isAfter(last))) last = at;
    }
    return last;
  }

  Map<String, CardState> _parse() => {
        for (final f in _files.entries)
          if (f.value['cards'] case final Map cards)
            for (final c in cards.entries)
              if (c.value case final Map sides)
                for (final side in const ['f', 'r']) '${f.key}/${c.key}/$side': ?CardState.fromJson(sides[side]),
      };

  /// Saves how [item] is known now, in its notebook's study.json.
  Future<void> record(StudyItem item, CardState s) async {
    final nb = item.card.notebookId;
    final store = ref.read(boardStoreProvider);
    final file = _files[nb] ??= await store.loadStudy(nb) ?? {'version': 1, 'cards': <String, dynamic>{}};
    final cards = (file['cards'] as Map).cast<String, dynamic>();
    final sides = {...?(cards[item.card.id] as Map?)?.cast<String, dynamic>()};
    sides[item.reverse ? 'r' : 'f'] = s.toJson();
    cards[item.card.id] = sides;
    file['cards'] = cards;
    state = (state ?? StudySnapshot.empty).withState(item.key, s);
    final json = {...file};
    await ref.read(writeQueueProvider).run(() => store.saveStudy(nb, json));
  }
}

/// [list] with each id once. A notebook imported from a board file (or
/// copied) keeps its items' ids, so its cards and things to remember are
/// the same ones as in the notebook it came from: the copy studied last
/// is kept ([lastStudied]), else the one in the oldest notebook (notebook
/// ids sort by when they were made), in [list]'s order.
List<T> oneOfEach<T>(
  List<T> list,
  String Function(T) id,
  String Function(T) notebookId, {
  DateTime? Function(T)? lastStudied,
}) {
  final best = <String, T>{};
  bool better(T a, T b) {
    final la = lastStudied?.call(a), lb = lastStudied?.call(b);
    if (la != null || lb != null) {
      if (la == null) return false;
      if (lb == null) return true;
      if (la != lb) return la.isAfter(lb);
    }
    return notebookId(a).compareTo(notebookId(b)) < 0;
  }

  for (final t in list) {
    final key = id(t);
    final have = best[key];
    if (have == null || better(t, have)) best[key] = t;
  }
  return [for (final t in list) if (identical(best[id(t)], t)) t];
}

/// A deck with its cards, for the Flashcards screen.
class DeckSummary {
  DeckSummary(this.deck, this.items, {required DateTime now})
      : due = items.where((i) => i.dueAt(now)).length,
        notebooks = {for (final i in items) i.card.notebookId}.length,
        cards = {for (final i in items) '${i.card.notebookId}/${i.card.id}'}.length;

  final Deck deck;
  final List<StudyItem> items;
  final int due;
  final int cards;
  final int notebooks;
}

/// Every deck in [decks] (empty ones too), with its cards from [snapshot]
/// and what's due at [now].
List<DeckSummary> deckSummaries(StudySnapshot snapshot, List<Deck> decks, DateTime now) {
  final byDeck = <String, List<StudyItem>>{};
  for (final i in snapshot.items) {
    (byDeck[i.card.deck] ??= []).add(i);
  }
  final known = {for (final d in decks) d.id};
  return [
    for (final d in decks) DeckSummary(d, byDeck[d.id] ?? const [], now: now),
    // Cards whose deck isn't listed yet (it will be in a moment).
    for (final e in byDeck.entries)
      if (!known.contains(e.key))
        DeckSummary(Deck(id: e.key, name: e.value.first.card.deckName, createdAt: now), e.value, now: now),
  ];
}

/// A notebook's pages in order, from its notebook.json (for "p. 3").
final pageIdsProvider = FutureProvider.autoDispose.family<List<String>, String>((ref, notebookId) async {
  ref.watch(libraryProvider.select((l) => l.byId(notebookId)?.pageCount));
  return (await ref.read(boardStoreProvider).loadNotebookMeta(notebookId))?.pageIds ?? const [];
});
