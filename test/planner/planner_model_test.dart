import 'dart:convert';
import 'dart:ui';

import 'package:endless/board/model.dart';
import 'package:endless/calendar/calendar_model.dart';
import 'package:endless/calendar/calendar_state.dart';
import 'package:endless/planner/planner_model.dart';
import 'package:endless/planner/planner_state.dart';
import 'package:endless/study/fsrs.dart';
import 'package:endless/study/reminders.dart';
import 'package:endless/study/remember.dart';
import 'package:endless/study/study_rows.dart';
import 'package:endless/study/study_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../calendar_samples.dart';

PlanTask _t(String id, {DateTime? day, bool done = false, DateTime? doneAt, int? start}) =>
    PlanTask(id: id, text: id, day: day, done: done, doneAt: doneAt, start: start, createdAt: DateTime.utc(2026, 9, 20));

void main() {
  final fri = DateTime(2026, 9, 25);
  final thu = DateTime(2026, 9, 24);
  final sat = DateTime(2026, 9, 26);

  group('to-dos', () {
    final planner = PlannerData(tasks: [
      _t('inbox'),
      _t('inbox done today', done: true, doneAt: DateTime(2026, 9, 25, 9).toUtc()),
      _t('inbox done before', done: true, doneAt: DateTime(2026, 9, 23, 9).toUtc()),
      _t('for today', day: fri),
      _t('left from Thursday', day: thu),
      _t('done Thursday', day: thu, done: true, doneAt: DateTime(2026, 9, 24, 9).toUtc()),
      _t('for Saturday', day: sat),
      _t('blocked today', day: fri, start: 15 * 60 + 30),
    ]);

    String ids(List<PlanTask> l) => [for (final t in l) t.id].join(', ');

    test('today: its own, those without a day, and what’s left from before', () {
      expect(ids(planner.todosFor(fri, fri)), 'inbox, inbox done today, for today, left from Thursday, blocked today');
    });

    test('another day: only its own', () {
      expect(ids(planner.todosFor(sat, fri)), 'for Saturday');
      expect(ids(planner.todosFor(thu, fri)), 'left from Thursday, done Thursday');
    });

    test('blocked time and what isn’t scheduled', () {
      expect(ids(planner.blocksOn(fri)), 'blocked today');
      expect(planner.blocksOn(fri).single.block, (DateTime(2026, 9, 25, 15, 30), DateTime(2026, 9, 25, 16, 30)));
      expect(ids(planner.unscheduled(weekStart(fri), 7)), 'inbox, for today, left from Thursday, for Saturday');
    });

    test('decks with cards due are to-dos of their own until one is made', () {
      final study = StudySnapshot(remembered: const [], cards: const [], states: const {});
      expect(todosFor(planner, study, const [], fri, fri, fri.toUtc()).where((t) => t.deck != null), isEmpty);
      final data = plannerSample();
      final now = calendarNow.toUtc();
      final snapshot = _snapshot(now);
      final decks = [Deck(id: 'dk_mom', name: 'Physics — Momentum', createdAt: now), Deck(id: 'dk_calc', name: 'Calculus II', createdAt: now)];
      final todos = todosFor(data, snapshot, decks, fri, fri, now);
      // Physics has a to-do (td_cards); Calculus II doesn't, so it gets one.
      final cards = todos.firstWhere((t) => t.task?.id == 'td_cards');
      expect(todoFrom(cards), 'Physics — Momentum deck');
      final calc = todos.singleWhere((t) => t.task == null);
      expect(calc.deck!.deck.id, 'dk_calc');
      expect(todoLabel(calc), 'Review flashcards');
      expect(calc.due, 1);
    });
  });

  group('planner.json', () {
    test('round trips with ink, blocks and unknown fields', () {
      final data = plannerSample();
      final json = jsonDecode(jsonEncode({...data.toJson(), 'later': true})) as Map<String, dynamic>;
      (json['tasks'] as List).first['priority'] = 2;
      final again = PlannerData.fromJson(json);
      expect(again.tasks.length, data.tasks.length);
      expect(again.task('td_lab')!.block, (DateTime(2026, 9, 25, 15, 30), DateTime(2026, 9, 25, 17)));
      expect(again.task('td_cards')!.deckId, 'dk_mom');
      expect(again.day(fri).top[1].done, isTrue);
      expect(again.day(fri).top[0].ink, isNotEmpty);
      expect(again.day(fri).notes.length, data.day(fri).notes.length);
      expect(again.toJson()['later'], true);
      expect((again.toJson()['tasks'] as List).first['priority'], 2);
      expect(jsonEncode(PlannerData.fromJson(jsonDecode(jsonEncode(again.toJson())) as Map<String, dynamic>).toJson()), jsonEncode(again.toJson()));
    });

    test('empty days aren’t written', () {
      final data = PlannerData(days: {dayKey(fri): PlanDay.empty}, goals: {dayKey(weekStart(fri)): const <StrokeItem>[]});
      expect(data.toJson()['days'], isEmpty);
      expect(data.toJson()['weeks'], isEmpty);
    });
  });

  group('reminders before an event', () {
    RememberedThing thing({EventLink? event, DateTime? remindAt}) => RememberedThing.fromRow(StudyRow(
          notebookId: 'nb_phys',
          pageId: 'pg',
          kind: StudyKind.remember,
          ref: 'rm_1',
          rect: const Rect.fromLTWH(0, 0, 10, 10),
          at: DateTime.utc(2026, 9, 20),
          data: RememberMark(id: 'rm_1', remind: RemindKind.event, remindAt: remindAt, event: event).toJson(),
        ));

    test('go off before the event, wherever it has moved', () {
      final link = const EventLink(id: 'ev_phys_fri', day: '2026-09-25', title: 'Physics lecture', before: 30);
      final t = thing(event: link, remindAt: DateTime(2026, 9, 25, 9, 30).toUtc());
      expect(t.event, link);
      final data = calendarSample();
      DateTime? at(CalendarData d) => reminderAt(t, (e) => eventStart(d, const [], e.id, e.day));
      expect(at(data), DateTime(2026, 9, 25, 9, 30).toUtc());
      final moved = data.copyWith(events: [
        for (final e in data.events)
          e.id == 'ev_phys_fri' ? e.copyWith(start: DateTime(2026, 9, 25, 13).toUtc(), end: DateTime(2026, 9, 25, 14).toUtc()) : e,
      ]);
      expect(at(moved), DateTime(2026, 9, 25, 12, 30).toUtc());
      // Gone: when it was set for.
      expect(at(const CalendarData()), DateTime(2026, 9, 25, 9, 30).toUtc());
      final r = remindersFor([t], {'nb_phys': 'Physics'}, DateTime.utc(2026, 9, 24), eventAt: (e) => eventStart(moved, const [], e.id, e.day)).single;
      expect(r.title, 'Before Physics lecture');
      expect(r.at, DateTime(2026, 9, 25, 12, 30).toUtc());
    });

    test('the mark keeps its event only for an event reminder', () {
      final link = const EventLink(id: 'e', day: '2026-09-25', title: 'Lab', before: 60);
      expect(RememberMark(id: 'm', remind: RemindKind.event, remindAt: DateTime.utc(2026, 9, 25), event: link).toJson()['event'], link.toJson());
      expect(RememberMark(id: 'm', remind: RemindKind.date, remindAt: DateTime.utc(2026, 9, 25), event: link).toJson().containsKey('event'), isFalse);
    });
  });
}

/// One Physics card done long ago and due now, one Calculus card due now.
StudySnapshot _snapshot(DateTime now) {
  StudyCard card(String nb, String id, String deck) => StudyCard.fromRow(StudyRow(
        notebookId: nb,
        pageId: 'pg',
        kind: StudyKind.card,
        ref: id,
        rect: const Rect.fromLTWH(0, 0, 1, 1),
        at: now,
        data: {'deck': deck, 'deckName': deck, 'front': {'text': 'q'}, 'back': {'text': 'a'}},
      ));
  final due = const Fsrs().review(null, Rating.good, now.subtract(const Duration(days: 30)));
  return StudySnapshot(
    remembered: const [],
    cards: [card('nb_phys', 'c1', 'dk_mom'), card('nb_calc', 'c2', 'dk_calc')],
    states: {'nb_phys/c1/f': due, 'nb_calc/c2/f': due},
  );
}
