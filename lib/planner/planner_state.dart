import 'dart:async';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/ids.dart';
import '../board/model.dart';
import '../calendar/calendar_model.dart';
import '../library/library.dart';
import '../state/notebook.dart' show writeQueueProvider;
import '../state/settings.dart' show boardStoreProvider;
import '../study/study_state.dart';
import 'planner_model.dart';

// The planner's data (planner.json): every change is saved at once, as
// everywhere else. Decks with cards due show as "Review flashcards" to-dos
// of their own; ticking or planning one keeps it as a to-do.

/// planner.json as the app started (bootstrap loads it).
final initialPlannerProvider = Provider<PlannerData>((ref) => const PlannerData());

final plannerProvider = NotifierProvider<Planner, PlannerData>(Planner.new);

class Planner extends Notifier<PlannerData> {
  @override
  PlannerData build() => ref.read(initialPlannerProvider);

  DateTime get _now => ref.read(clockProvider)();

  /// A new to-do (typed, or written), for [day] or for no day.
  PlanTask add({String text = '', List<StrokeItem> ink = const [], DateTime? day, String? deckId}) {
    final t = PlanTask(
      id: newId('td', now: _now),
      text: text.trim(),
      ink: ink,
      day: day == null ? null : dayOf(day),
      deckId: deckId,
      createdAt: _now.toUtc(),
    );
    _set(state.copyWith(tasks: [...state.tasks, t]));
    return t;
  }

  /// The to-do [t] is, made for a deck's "Review flashcards" (for today)
  /// the first time it's ticked or planned.
  PlanTask real(Todo t) => t.task ?? add(text: 'Review flashcards', deckId: t.deck!.deck.id, day: _now);

  void put(PlanTask t) {
    final i = state.tasks.indexWhere((x) => x.id == t.id);
    _set(state.copyWith(tasks: i < 0 ? [...state.tasks, t] : ([...state.tasks]..[i] = t)));
  }

  void tick(PlanTask t, bool done) => put(t.copyWith(done: done, doneAt: () => done ? _now.toUtc() : null));

  void remove(String id) => _set(
    state.copyWith(
      tasks: [
        for (final t in state.tasks)
          if (t.id != id) t,
      ],
    ),
  );

  /// Blocks [t] on [day]'s schedule from [start] (minutes after midnight).
  void schedule(PlanTask t, DateTime day, int start, {int? minutes}) => put(t.copyWith(day: () => dayOf(day), start: () => start, minutes: minutes));

  /// Puts [t] on [day] without a time (Week's "Drag onto a day").
  void moveTo(PlanTask t, DateTime? day) => put(t.copyWith(day: () => day == null ? null : dayOf(day), start: () => null));

  /// Off the schedule; still a to-do for that day.
  void unschedule(PlanTask t) => put(t.copyWith(start: () => null));

  void setTop(DateTime day, int i, TopLine line) {
    final d = state.day(day);
    _setDay(day, d.copyWith(top: [...d.top]..[i] = line));
  }

  void setNotes(DateTime day, List<StrokeItem> ink) => _setDay(day, state.day(day).copyWith(notes: ink));

  void setGoals(DateTime day, List<StrokeItem> ink) => _set(state.copyWith(goals: {...state.goals, dayKey(weekStart(day)): ink}));

  void _setDay(DateTime day, PlanDay d) => _set(state.copyWith(days: {...state.days, dayKey(dayOf(day)): d}));

  void _set(PlannerData data) {
    state = data;
    final json = data.toJson();
    final store = ref.read(boardStoreProvider);
    unawaited(ref.read(writeQueueProvider).run(() => store.savePlanner(json)));
  }
}

/// A to-do as the planner shows it: one of the planner's, or a deck with
/// cards due ("Review flashcards", from "Physics — Momentum deck").
@immutable
class Todo {
  const Todo(this.task, {this.deck, this.due = 0});

  final PlanTask? task;
  final DeckSummary? deck;

  /// Cards due in [deck] now.
  final int due;

  String get key => task?.id ?? 'deck:${deck!.deck.id}';
  bool get done => task?.done ?? false;
}

/// [day]'s to-dos (see [PlannerData.todosFor]), with "Review flashcards"
/// for each deck with cards due on [today] that has no to-do yet.
List<Todo> todosFor(PlannerData planner, StudySnapshot? study, List<Deck> decks, DateTime day, DateTime today, DateTime now) {
  final tasks = planner.todosFor(day, today);
  final summaries = study == null ? const <DeckSummary>[] : deckSummaries(study, decks, now);
  final byDeck = {for (final s in summaries) s.deck.id: s};
  final withDeck = {
    for (final t in planner.tasks)
      if (t.deckId != null && t.day == dayOf(today)) t.deckId!,
  };
  return [
    for (final t in tasks) Todo(t, deck: byDeck[t.deckId], due: byDeck[t.deckId]?.due ?? 0),
    if (dayOf(day) == dayOf(today))
      for (final s in summaries)
        if (s.due > 0 && !withDeck.contains(s.deck.id)) Todo(null, deck: s, due: s.due),
  ];
}

/// What a to-do says.
String todoLabel(Todo t) => t.task?.text.isNotEmpty ?? false ? t.task!.text : (t.deck != null ? 'Review flashcards' : '');

/// Where a to-do comes from (Planner.png's second line).
String todoFrom(Todo t) => t.deck != null ? '${t.deck!.deck.name} deck' : 'Added here';
