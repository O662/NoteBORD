import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:endless/study/fsrs.dart';
import 'package:endless/study/session.dart';
import 'package:endless/study/study_rows.dart';
import 'package:flutter_test/flutter_test.dart';

final _start = DateTime.utc(2026, 9, 25, 10);

StudyCard _card(String id, {bool reverse = false}) => StudyCard.fromRow(StudyRow(
      notebookId: 'nb',
      pageId: 'pg',
      kind: StudyKind.card,
      ref: id,
      rect: Rect.zero,
      at: _start,
      data: {'deck': 'dk', 'deckName': 'Physics', 'reverse': reverse, 'front': {'text': id}, 'back': {'text': 'back'}},
    ));

void main() {
  const fsrs = Fsrs();

  group('FSRS-6', () {
    // test/fixtures/study/fsrs_reference.json is py-fsrs 6.3.2's answers
    // (tool/fsrs_reference.py).
    final reference = (jsonDecode(File('test/fixtures/study/fsrs_reference.json').readAsStringSync()) as Map).cast<String, dynamic>();
    for (final run in reference.entries) {
      test('matches py-fsrs: ${run.key}', () {
        CardState? card;
        for (final (i, step) in (run.value as List).cast<Map<String, dynamic>>().indexed) {
          final rating = Rating.values.byName((step['rating'] as String).toLowerCase());
          card = fsrs.review(card, rating, DateTime.parse(step['at'] as String));
          final why = '${run.key}, answer ${i + 1} (${step['rating']})';
          expect(card.phase.name, (step['state'] as String).toLowerCase(), reason: why);
          expect(card.step, step['step'], reason: why);
          expect(card.stability, closeTo((step['s'] as num).toDouble(), 1e-6), reason: why);
          expect(card.difficulty, closeTo((step['d'] as num).toDouble(), 1e-6), reason: why);
          expect(card.due, DateTime.parse(step['due'] as String), reason: why);
        }
      });
    }

    test('a new card: Again in 1 min, Hard in 5½, Good in 10, Easy in 8 days', () {
      Duration wait(Rating r) => fsrs.review(null, r, _start).due.difference(_start);
      expect(wait(Rating.again), const Duration(minutes: 1));
      expect(wait(Rating.hard), const Duration(minutes: 5, seconds: 30));
      expect(wait(Rating.good), const Duration(minutes: 10));
      expect(wait(Rating.easy), const Duration(days: 8));
    });

    test('learned with Good twice, it comes back in 2 days (Study.png)', () {
      final first = fsrs.review(null, Rating.good, _start);
      final second = fsrs.review(first, Rating.good, first.due);
      expect(second.phase, CardPhase.review);
      expect(second.due.difference(first.due), const Duration(days: 2));
      expect(waitLabel(second.due.difference(first.due)), 'in 2 days');
    });

    test('forgotten in review: relearned in 10 minutes, and counted', () {
      var card = fsrs.review(null, Rating.easy, _start);
      card = fsrs.review(card, Rating.again, card.due);
      expect(card.phase, CardPhase.relearning);
      expect(card.lapses, 1);
      expect(card.reps, 2);
      expect(card.due.difference(card.lastReview), const Duration(minutes: 10));
    });

    test('the state round-trips through study.json', () {
      final card = fsrs.review(fsrs.review(null, Rating.good, _start), Rating.hard, _start.add(const Duration(minutes: 10)));
      final back = CardState.fromJson(jsonDecode(jsonEncode(card.toJson())))!;
      expect(back.phase, card.phase);
      expect(back.step, card.step);
      expect(back.stability, closeTo(card.stability, 1e-4));
      expect(back.difficulty, closeTo(card.difficulty, 1e-4));
      expect(back.due, card.due);
      expect(back.lastReview, card.lastReview);
      expect(CardState.fromJson({'s': 1}), isNull);
      expect(CardState.fromJson('nonsense'), isNull);
    });

    test('wait labels', () {
      expect(waitLabel(const Duration(seconds: 20)), 'in 1 min');
      expect(waitLabel(const Duration(minutes: 10)), 'in 10 min');
      expect(waitLabel(const Duration(hours: 1)), 'in 1 hour');
      expect(waitLabel(const Duration(hours: 5)), 'in 5 hours');
      expect(waitLabel(const Duration(days: 1)), 'in 1 day');
      expect(waitLabel(const Duration(days: 45)), 'in 1 month');
      expect(waitLabel(const Duration(days: 800)), 'in 2.2 years');
    });
  });

  group('a round of studying', () {
    test('every way each card is asked: back to front too when asked', () {
      final items = studyItems([_card('a'), _card('b', reverse: true)], const {});
      expect(items.map((i) => i.key), ['nb/a/f', 'nb/b/f', 'nb/b/r']);
      expect(items[2].question.text, 'back');
      expect(items[2].answer.text, 'b');
    });

    test('Again comes back later in the round; Good on a learned card finishes it', () {
      final known = fsrs.review(fsrs.review(null, Rating.good, _start), Rating.good, _start.add(const Duration(minutes: 10)));
      final items = studyItems([_card('a'), _card('b')], {'nb/b/f': known});
      final session = StudySession(items);
      var now = known.due;
      expect(session.total, 2);

      final first = session.current(now)!;
      expect(first.card.id, 'a');
      session.answer(first, Rating.again, now);
      expect(session.done, 0);

      // b is due; a isn't for a minute.
      final second = session.current(now)!;
      expect(second.card.id, 'b');
      session.answer(second, Rating.good, now);
      expect(session.done, 1);

      // Only a is left, not due yet: it shows anyway.
      expect(session.current(now)!.card.id, 'a');
      now = now.add(const Duration(minutes: 1));
      final again = session.current(now)!;
      session.answer(again, Rating.good, now);
      expect(session.done, 1, reason: 'one more learning step');
      now = now.add(const Duration(minutes: 10));
      session.answer(session.current(now)!, Rating.good, now);
      expect(session.done, 2);
      expect(session.finished, isTrue);
    });

    test('the buttons say when the card would come back', () {
      final session = StudySession(studyItems([_card('a')], const {}));
      final item = session.current(_start)!;
      expect(waitLabel(session.waitFor(item, Rating.again, _start)), 'in 1 min');
      expect(waitLabel(session.waitFor(item, Rating.good, _start)), 'in 10 min');
      expect(waitLabel(session.waitFor(item, Rating.easy, _start)), 'in 8 days');
    });
  });
}
