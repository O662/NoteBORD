import 'fsrs.dart';
import 'study_rows.dart';

/// One way of asking a card: front to back, or ([reverse]) back to front.
class StudyItem {
  const StudyItem(this.card, {this.reverse = false, this.state});

  final StudyCard card;
  final bool reverse;

  /// How well it's known, or null if it was never studied.
  final CardState? state;

  /// `<notebook>/<card>/f` or `/r`.
  String get key => '${card.notebookId}/${card.id}/${reverse ? 'r' : 'f'}';

  /// What's asked, and the answer.
  SideView get question => reverse ? card.back : card.front;
  SideView get answer => reverse ? card.front : card.back;

  bool dueAt(DateTime now) => state == null || !state!.due.isAfter(now);

  StudyItem withState(CardState s) => StudyItem(card, reverse: reverse, state: s);
}

/// Every way of asking each card ([states] by [StudyItem.key]).
List<StudyItem> studyItems(Iterable<StudyCard> cards, Map<String, CardState> states) => [
      for (final c in cards) ...[
        StudyItem(c, state: states['${c.notebookId}/${c.id}/f']),
        if (c.reverse) StudyItem(c, reverse: true, state: states['${c.notebookId}/${c.id}/r']),
      ],
    ];

/// A round of studying (Study.png): the cards due, one at a time. A card
/// answered Again or Hard while it's being learned comes back later in the
/// round, once it's due again (or when nothing else is left).
class StudySession {
  StudySession(List<StudyItem> items, {this.fsrs = const Fsrs(), this.learnAhead = const Duration(minutes: 20)})
      : _queue = [...items],
        total = items.length;

  final Fsrs fsrs;

  /// Cards due within this long come back in the same round.
  final Duration learnAhead;
  final List<StudyItem> _queue;

  /// How many cards the round started with ("Card 3 of 5 due").
  final int total;

  /// Cards finished for this round.
  int done = 0;

  bool get finished => _queue.isEmpty;

  /// The card showing now: the first one due, or the soonest when none are.
  StudyItem? current(DateTime now) {
    if (_queue.isEmpty) return null;
    for (final item in _queue) {
      if (item.dueAt(now)) return item;
    }
    return _queue.reduce((a, b) => a.state!.due.isBefore(b.state!.due) ? a : b);
  }

  /// How [rating] would schedule [item] at [now] (for the buttons).
  Duration waitFor(StudyItem item, Rating rating, DateTime now) =>
      fsrs.review(item.state, rating, now).due.difference(now.toUtc());

  /// Answers the current card. Returns its new state, to be saved.
  CardState answer(StudyItem item, Rating rating, DateTime now) {
    final next = fsrs.review(item.state, rating, now);
    final at = _queue.indexWhere((i) => i.key == item.key);
    if (at >= 0) _queue.removeAt(at);
    if (next.due.difference(now.toUtc()) <= learnAhead) {
      _queue.add(item.withState(next));
    } else {
      done++;
    }
    return next;
  }
}
