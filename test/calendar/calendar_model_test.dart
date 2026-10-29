import 'dart:convert';

import 'package:endless/calendar/calendar_model.dart';
import 'package:endless/calendar/calendar_state.dart';
import 'package:endless/calendar/deadlines.dart';
import 'package:endless/search/search_text.dart';
import 'package:endless/ui/calendar/calendar_grid.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../calendar_samples.dart';

CalEvent _ev(String id, DateTime start, DateTime end, {Repeat? repeat, bool allDay = false}) => CalEvent(
      id: id,
      calendarId: 'local',
      title: id,
      start: allDay ? start : start.toUtc(),
      end: allDay ? end : end.toUtc(),
      allDay: allDay,
      repeat: repeat,
    );

void main() {
  final mon = DateTime(2026, 9, 21);

  group('days', () {
    test('keys, weeks and adding days', () {
      expect(dayKey(DateTime(2026, 9, 5)), '2026-09-05');
      expect(parseDay('2026-09-05'), DateTime(2026, 9, 5));
      expect(parseDay('Sep 5'), isNull);
      expect(weekStart(DateTime(2026, 9, 27, 18)), mon);
      expect(weekStart(mon), mon);
      expect(addDays(DateTime(2026, 9, 30), 1), DateTime(2026, 10, 1));
      expect(dayOf(DateTime.utc(2026, 9, 25, 12)), dayOf(DateTime.utc(2026, 9, 25, 12).toLocal()));
    });
  });

  group('occurrences', () {
    test('a one-off event, in and out of the range', () {
      final e = _ev('a', DateTime(2026, 9, 25, 10), DateTime(2026, 9, 25, 11, 15));
      expect(e.occurrences(mon, addDays(mon, 7)).single.start, DateTime(2026, 9, 25, 10));
      expect(e.occurrences(addDays(mon, 7), addDays(mon, 14)), isEmpty);
    });

    test('every week, with a day skipped and an end', () {
      final e = _ev('phys', DateTime(2026, 9, 7, 10), DateTime(2026, 9, 7, 11, 15),
          repeat: Repeat(RepeatEvery.week, until: DateTime(2026, 10, 12), skip: {'2026-09-28'}));
      final starts = [for (final o in e.occurrences(DateTime(2026, 9, 1), DateTime(2026, 11, 1))) o.start];
      expect(starts, [
        DateTime(2026, 9, 7, 10),
        DateTime(2026, 9, 14, 10),
        DateTime(2026, 9, 21, 10),
        DateTime(2026, 10, 5, 10),
        DateTime(2026, 10, 12, 10),
      ]);
      expect(e.occurrences(mon, addDays(mon, 7)).single.end, DateTime(2026, 9, 21, 11, 15));
    });

    test('weekdays and every day', () {
      final wd = _ev('w', DateTime(2026, 9, 21, 9), DateTime(2026, 9, 21, 10), repeat: const Repeat(RepeatEvery.weekdays));
      expect(wd.occurrences(mon, addDays(mon, 7)).length, 5);
      final daily = _ev('d', DateTime(2026, 9, 23, 7), DateTime(2026, 9, 23, 8), repeat: const Repeat(RepeatEvery.day));
      expect([for (final o in daily.occurrences(mon, addDays(mon, 7))) o.start.day], [23, 24, 25, 26, 27]);
    });

    test('all-day events span their days', () {
      final e = _ev('trip', DateTime(2026, 9, 26), DateTime(2026, 9, 28), allDay: true);
      final o = e.occurrences(mon, addDays(mon, 7)).single;
      expect(o.allDay, isTrue);
      expect(o.start, DateTime(2026, 9, 26));
      expect(o.end, DateTime(2026, 9, 28));
      expect(e.occurrences(DateTime(2026, 9, 27), DateTime(2026, 9, 28)), hasLength(1));
      expect(e.occurrences(DateTime(2026, 9, 28), DateTime(2026, 9, 29)), isEmpty);
    });

    test('deleted events never happen', () {
      final e = _ev('x', DateTime(2026, 9, 25, 10), DateTime(2026, 9, 25, 11)).copyWith(deleted: true);
      expect(e.occurrences(mon, addDays(mon, 7)), isEmpty);
    });
  });

  group('calendar.json', () {
    test('round trips, keeping what this version doesn’t know', () {
      final data = CalendarData.fromJson({
        'version': 1,
        'future': {'a': 1},
        'calendars': [
          {'id': 'school', 'name': 'School', 'kind': 'google', 'hue': 'blue', 'account': 'sam@gmail.com', 'remoteId': 'x', 'shown': false, 'color2': 'teal'},
        ],
        'events': [
          {
            'id': 'ev1',
            'calendar': 'school',
            'title': 'Physics lecture',
            'start': '2026-09-25T15:00:00.000Z',
            'end': '2026-09-25T16:15:00.000Z',
            'repeat': {'every': 'week', 'until': '2026-12-11', 'skip': ['2026-10-02']},
            'notes': {'notebook': 'nb_phys', 'page': 'pg_3'},
            'remoteId': 'g1',
            'etag': '"3"',
            'pending': true,
            'location': 'Room 4',
          },
          {'id': 'ev2', 'calendar': 'school', 'title': 'Trip', 'allDay': true, 'startDate': '2026-09-26', 'endDate': '2026-09-28'},
          {'id': 'bad'},
        ],
      });
      expect(data.calendars.single.shown, isFalse);
      expect(data.calendars.single.kind, CalendarKind.google);
      expect(data.events, hasLength(2));
      final e = data.event('ev1')!;
      expect(e.repeat!.until, DateTime(2026, 12, 11));
      expect(e.notes, const NoteLink('nb_phys', pageId: 'pg_3'));
      final again = CalendarData.fromJson(jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>);
      expect(jsonEncode(again.toJson()), jsonEncode(data.toJson()));
      final json = again.toJson();
      expect(json['future'], {'a': 1});
      expect((json['calendars'] as List).single['color2'], 'teal');
      expect((json['events'] as List).first['location'], 'Room 4');
      expect((json['events'] as List).last['startDate'], '2026-09-26');
    });

    test('a new tablet gets a calendar of its own and the note deadlines', () {
      final data = withDefaults(const CalendarData());
      expect([for (final c in data.calendars) c.id], ['local', CalendarInfo.deadlinesId]);
      final synced = withDefaults(calendarSample());
      expect(synced.calendars.length, 4, reason: 'nothing added when there are calendars already');
    });

    test('what the calendars shown have, all-day first', () {
      final data = calendarSample();
      final fri = DateTime(2026, 9, 25);
      final deadline = CalEvent(id: 'dl', calendarId: CalendarInfo.deadlinesId, title: 'Lab due', start: fri, end: addDays(fri, 1), allDay: true);
      final list = occurrencesIn(data, [deadline], fri, addDays(fri, 1));
      expect([for (final o in list) o.event.title], ['Lab due', 'Physics lecture', 'Lunch', 'Study group']);
      final hidden = data.copyWith(calendars: [for (final c in data.calendars) c.id == 'personal' ? c.copyWith(shown: false) : c]);
      expect([for (final o in occurrencesIn(hidden, const [], fri, addDays(fri, 1))) o.event.title], ['Physics lecture', 'Study group']);
    });
  });

  group('laying out a day', () {
    Occurrence o(String id, double from, double to) {
      final e = _ev(id, DateTime(2026, 9, 25, from.floor(), ((from % 1) * 60).round()), DateTime(2026, 9, 25, to.floor(), ((to % 1) * 60).round()));
      return e.occurrences(mon, addDays(mon, 7)).single;
    }

    test('overlapping events side by side; others full width', () {
      final placed = layoutDay([o('a', 9, 10.5), o('b', 10, 11), o('c', 10.5, 12), o('d', 13, 14)]);
      final byId = {for (final p in placed) p.o.event.id: p};
      expect((byId['a']!.lane, byId['a']!.lanes), (0, 2));
      expect((byId['b']!.lane, byId['b']!.lanes), (1, 2));
      expect(byId['c']!.lane, 0, reason: 'a has ended by 10:30');
      expect((byId['d']!.lane, byId['d']!.lanes), (0, 1));
    });

    test('all-day rows don’t overlap', () {
      final fri = DateTime(2026, 9, 25);
      final days = [for (var i = 0; i < 7; i++) addDays(mon, i)];
      final a = _ev('a', DateTime(2026, 9, 23), DateTime(2026, 9, 26), allDay: true).occurrences(mon, addDays(mon, 7)).single;
      final b = _ev('b', fri, addDays(fri, 1), allDay: true).occurrences(mon, addDays(mon, 7)).single;
      final c = _ev('c', DateTime(2026, 9, 27), DateTime(2026, 9, 28), allDay: true).occurrences(mon, addDays(mon, 7)).single;
      final spans = layoutAllDay([a, b, c], days);
      expect([for (final s in spans) (s.from, s.to, s.row)], [(2, 4, 0), (4, 4, 1), (6, 6, 0)]);
    });
  });

  group('note deadlines', () {
    final fri = DateTime(2026, 9, 25, 14);

    test('dates after "due"', () {
      expect(parseDue('Problem set 4 due Sun', fri), (title: 'Problem set 4 due', day: DateTime(2026, 9, 27)));
      expect(parseDue('Lab report due Sep 30, 11:59 PM — submit as PDF', fri)?.day, DateTime(2026, 9, 30));
      expect(parseDue('essay due by October 3rd', fri)?.day, DateTime(2026, 10, 3));
      expect(parseDue('quiz due 10/14', fri)?.day, DateTime(2026, 10, 14));
      expect(parseDue('reading due tomorrow', fri)?.day, DateTime(2026, 9, 26));
      expect(parseDue('due Fri', fri)?.day, DateTime(2026, 10, 2), reason: 'a weekday is the next one');
      expect(parseDue('due: 3 Jan', fri)?.day, DateTime(2027, 1, 3), reason: 'months long past are next year');
      expect(parseDue('Midterm due Feb 30', fri), isNull);
    });

    test('not dates', () {
      expect(parseDue('due to the rain', fri), isNull);
      expect(parseDue('overdue books', fri), isNull);
      expect(parseDue('Sep 30 lab report', fri), isNull);
    });

    test('from the index: one all-day event each, linked to its notes', () {
      SearchRow row(String ref, String text) => SearchRow(
            notebookId: 'nb',
            pageId: 'pg',
            kind: SearchKind.typed,
            ref: ref,
            text: text,
            rect: const Rect.fromLTWH(0, 0, 10, 10),
            at: fri.toUtc(),
          );
      final list = deadlinesIn([row('a', 'Problem set 4 due Sun'), row('a', 'Problem set 4 due Sun'), row('b', 'nothing here')]);
      expect(list, hasLength(1));
      expect(list.single.allDay, isTrue);
      expect(list.single.calendarId, CalendarInfo.deadlinesId);
      expect(list.single.notes, const NoteLink('nb', pageId: 'pg'));
    });
  });

  group('when an event starts now', () {
    test('a moved event, a repeating one and an all-day one', () {
      final data = calendarSample();
      expect(eventStart(data, const [], 'ev_phys_fri', '2026-09-25'), DateTime(2026, 9, 25, 10));
      final moved = data.copyWith(events: [
        for (final e in data.events)
          e.id == 'ev_phys_fri' ? e.copyWith(start: DateTime(2026, 9, 25, 11).toUtc(), end: DateTime(2026, 9, 25, 12).toUtc()) : e,
      ]);
      expect(eventStart(moved, const [], 'ev_phys_fri', '2026-09-25'), DateTime(2026, 9, 25, 11));
      final weekly = _ev('w', DateTime(2026, 9, 7, 10), DateTime(2026, 9, 7, 11), repeat: const Repeat(RepeatEvery.week));
      final withWeekly = data.copyWith(events: [...data.events, weekly]);
      expect(eventStart(withWeekly, const [], 'w', '2026-09-21'), DateTime(2026, 9, 21, 10));
      expect(eventStart(withWeekly, const [], 'w', '2026-09-22'), isNull, reason: 'not on a Tuesday');
      final trip = _ev('t', DateTime(2026, 9, 26), DateTime(2026, 9, 27), allDay: true);
      expect(eventStart(data.copyWith(events: [trip]), const [], 't', '2026-09-26'), DateTime(2026, 9, 26, 9));
      expect(eventStart(data, const [], 'gone', '2026-09-25'), isNull);
    });
  });
}
