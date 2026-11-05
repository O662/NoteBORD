// Calendar links (view only): reading .ics files as Google Calendar and
// Outlook publish them, with repeats, times taken off, moved, renamed and
// cancelled, all-day events, daylight saving and Windows time zone names.

import 'dart:io';

import 'package:endless/calendar/calendar_model.dart';
import 'package:endless/calendar/feeds.dart';
import 'package:endless/calendar/windows_zones.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

String fixture(String name) => File('test/fixtures/calendar/$name').readAsStringSync();

final now = DateTime.utc(2026, 9, 25, 18, 30);

void main() {
  group('links', () {
    test('a pasted link, webcal, and what isn’t one', () {
      expect(feedUri('  https://calendar.google.com/calendar/ical/a%40b.com/private-1f2e/basic.ics ')!.host, 'calendar.google.com');
      expect(feedUri('webcal://outlook.live.com/owa/calendar/1/2/calendar.ics').toString(), 'https://outlook.live.com/owa/calendar/1/2/calendar.ics');
      expect(feedUri('WEBCAL://example.org/cal.ics')!.scheme, 'https');
      expect(feedUri('http://timetable.school.edu/feed.ics')!.scheme, 'http');
      expect(feedUri('calendar.google.com/calendar/ical'), isNull);
      expect(feedUri('ftp://example.org/cal.ics'), isNull);
      expect(feedUri('https://localhost/cal.ics'), isNull);
      expect(feedUri(''), isNull);
    });

    test('where it’s from', () {
      FeedFrom of(String s) => feedFromOf(feedUri(s)!);
      expect(of('https://calendar.google.com/calendar/ical/x/basic.ics'), FeedFrom.google);
      expect(of('https://outlook.live.com/owa/calendar/x/calendar.ics'), FeedFrom.outlook);
      expect(of('https://outlook.office365.com/owa/calendar/x/calendar.ics'), FeedFrom.outlook);
      expect(of('https://timetable.school.edu/feed.ics'), FeedFrom.web);
      expect(of('https://notgoogle.com/x.ics'), FeedFrom.web);
    });
  });

  group('Google Calendar', () {
    late FeedRead read;
    setUpAll(() => read = readFeed(fixture('google_school.ics'), 'cal1', now));

    CalEvent named(String title) => read.events.singleWhere((e) => e.title == title);

    test('its name, its events, and the broken one skipped', () {
      expect(read.name, 'School');
      expect(read.events.map((e) => e.title), unorderedEquals(['Physics lecture', 'Physics midterm', 'Thanksgiving break', 'Study group, room 4']));
      expect(read.skipped, 1);
      expect({for (final e in read.events) e.calendarId}, {'cal1'});
    });

    test('a weekly lecture: Labor Day taken off, one moved, one renamed, one cancelled', () {
      final e = named('Physics lecture');
      expect(e.repeats, isTrue);
      expect(e.allDay, isFalse);
      final times = e.times!;
      // 15 weeks of Mon, Wed and Fri (Aug 31 – Dec 11), less Sep 7, Oct 2
      // (its own event now) and Oct 12.
      expect(times, hasLength(42));
      expect(times.first, (start: DateTime.utc(2026, 8, 31, 15), end: DateTime.utc(2026, 8, 31, 16, 15)));
      expect(times.last.start, DateTime.utc(2026, 12, 11, 16));
      final starts = times.map((t) => t.start).toSet();
      expect(starts, isNot(contains(DateTime.utc(2026, 9, 7, 15))));
      expect(starts, isNot(contains(DateTime.utc(2026, 9, 23, 15))));
      expect(starts, contains(DateTime.utc(2026, 9, 23, 19)), reason: 'moved to 2 PM');
      expect(starts, isNot(contains(DateTime.utc(2026, 10, 2, 15))));
      expect(starts, isNot(contains(DateTime.utc(2026, 10, 12, 15))));
      // Daylight saving ends Nov 1: still 10 AM in Chicago.
      expect(starts, contains(DateTime.utc(2026, 11, 2, 16)));
      expect(e.start, times.first.start);
    });

    test('the renamed one is an event of its own', () {
      final e = named('Physics midterm');
      expect(e.times, isNull);
      expect(e.start, DateTime.utc(2026, 10, 2, 15));
      expect(e.end, DateTime.utc(2026, 10, 2, 17));
      expect(e.id, isNot(named('Physics lecture').id));
    });

    test('an all-day break and a time in UTC', () {
      final b = named('Thanksgiving break');
      expect(b.allDay, isTrue);
      expect(b.start, DateTime(2026, 11, 26));
      expect(b.end, DateTime(2026, 11, 28));
      final s = named('Study group, room 4');
      expect(s.start, DateTime.utc(2026, 9, 25, 23));
      expect(s.length, const Duration(hours: 1));
    });

    test('occurrences in a week, in local time', () {
      final e = named('Physics lecture');
      final week = e.occurrences(DateTime(2026, 9, 21), DateTime(2026, 9, 28)).toList();
      expect(week.map((o) => o.start.toUtc()), [DateTime.utc(2026, 9, 21, 15), DateTime.utc(2026, 9, 23, 19), DateTime.utc(2026, 9, 25, 15)]);
      expect(week.every((o) => !o.start.isUtc), isTrue);
    });

    test('ids stay the same each time it’s read, and differ by calendar', () {
      final again = readFeed(fixture('google_school.ics'), 'cal1', now.add(const Duration(days: 3)));
      expect(again.events.map((e) => e.id), unorderedEquals(read.events.map((e) => e.id)));
      final other = readFeed(fixture('google_school.ics'), 'cal2', now);
      expect(other.events.map((e) => e.id).toSet().intersection(read.events.map((e) => e.id).toSet()), isEmpty);
      expect(read.events.every((e) => !e.id.contains('@')), isTrue, reason: 'Occurrence keys use @');
    });

    test('Windows line ends read the same', () {
      final crlf = readFeed(fixture('google_school.ics').replaceAll('\n', '\r\n'), 'cal1', now);
      expect(crlf.events.map((e) => (e.title, e.times?.length)), unorderedEquals(read.events.map((e) => (e.title, e.times?.length))));
    });
  });

  group('Outlook', () {
    late FeedRead read;
    setUpAll(() => read = readFeed(fixture('outlook_work.ics'), 'work', now));

    test('Windows time zone names keep their times', () {
      final e = read.events.singleWhere((e) => e.title == 'Team standup');
      // Tue and Thu, Sep 1 – Dec 17, less Nov 24 and 26.
      expect(e.times, hasLength(30));
      expect(e.times!.first.start, DateTime.utc(2026, 9, 1, 14));
      expect(e.times!.first.end, DateTime.utc(2026, 9, 1, 14, 15));
      expect(e.times!.last.start, DateTime.utc(2026, 12, 17, 15));
      expect(e.times!.map((t) => t.start), isNot(contains(DateTime.utc(2026, 11, 24, 15))));
    });

    test('a time zone name folded over two lines', () {
      final e = read.events.singleWhere((e) => e.title == 'Quarterly review');
      expect(e.start, DateTime.utc(2026, 10, 1, 19));
      expect(e.end, DateTime.utc(2026, 10, 1, 20, 30));
    });

    test('an all-day holiday and the calendar’s name', () {
      final e = read.events.singleWhere((e) => e.title == 'Company holiday');
      expect((e.allDay, e.start, e.end), (true, DateTime(2026, 10, 9), DateTime(2026, 10, 10)));
      expect(read.name, 'Calendar');
      expect(read.skipped, 0);
    });

    test('every Windows name is in the time zone database', () {
      for (final MapEntry(key: name, value: zone) in windowsZones.entries) {
        expect(() => tz.getLocation(zone), returnsNormally, reason: name);
      }
    });
  });

  test('read in a background isolate, as the app does, errors and all', () async {
    final read = await readFeedInBackground(fixture('outlook_work.ics'), 'work', now);
    expect(read.events.map((e) => e.title), unorderedEquals(['Team standup', 'Quarterly review', 'Company holiday']));
    expect(read.events.singleWhere((e) => e.title == 'Team standup').times!.first.start, DateTime.utc(2026, 9, 1, 14));
    await expectLater(readFeedInBackground('not a calendar', 'c', now), throwsA(isA<FeedException>()));
  });

  group('what isn’t right', () {
    test('a web page isn’t a calendar', () {
      expect(() => readFeed('<!doctype html><title>Sign in</title>', 'c', now), throwsA(FeedException.notCalendar));
    });

    test('repeats are worked out around now, and an endless one stops', () {
      const ics = 'BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:x\nBEGIN:VEVENT\nUID:daily\nDTSTAMP:20200101T000000Z\n'
          'DTSTART:20200106T080000Z\nDTEND:20200106T083000Z\nRRULE:FREQ=DAILY\nSUMMARY:Run\nEND:VEVENT\n'
          'BEGIN:VEVENT\nUID:old\nDTSTAMP:20200101T000000Z\nDTSTART:20200106T080000Z\nSUMMARY:Long ago\nEND:VEVENT\n'
          'BEGIN:VEVENT\nUID:noend\nDTSTAMP:20200101T000000Z\nDTSTART:20260926T080000Z\nSUMMARY:\nEND:VEVENT\nEND:VCALENDAR\n';
      final read = readFeed(ics, 'c', now);
      final run = read.events.singleWhere((e) => e.title == 'Run');
      expect(run.times!.first.start.isBefore(now.subtract(feedPast)), isFalse);
      expect(run.times!.first.end.isAfter(now.subtract(feedPast)), isTrue);
      expect(run.times!.last.start.isAfter(now.add(feedAhead)), isFalse);
      expect(run.times!.length, closeTo((feedPast + feedAhead).inDays, 2));
      expect(read.events.where((e) => e.title == 'Long ago'), isEmpty);
      // No end: half an hour. No title: "(No title)".
      final noEnd = read.events.singleWhere((e) => e.title == '(No title)');
      expect(noEnd.length, const Duration(minutes: 30));
    });
  });

  group('calendar.json', () {
    test('a link’s events aren’t stored; its notes, name and state are', () {
      final read = readFeed(fixture('google_school.ics'), 'cal1', now);
      final lecture = read.events.firstWhere((e) => e.title == 'Physics lecture');
      final data = CalendarData(
        calendars: [
          const CalendarInfo(id: 'local', name: 'Calendar'),
          CalendarInfo(id: 'cal1', name: 'School', kind: CalendarKind.feed, from: FeedFrom.google, fetchedAt: now, error: 'Couldn’t reach it.'),
        ],
        events: [
          CalEvent(id: 'mine', calendarId: 'local', title: 'Dentist', start: now, end: now.add(const Duration(hours: 1))),
          ...read.events,
        ],
        links: {lecture.id: const NoteLink('nb1', pageId: 'p3')},
      );
      final json = data.toJson();
      expect([for (final e in json['events'] as List) (e as Map)['id']], ['mine']);
      final back = CalendarData.fromJson(json);
      expect(back.events.single.id, 'mine');
      expect(back.links[lecture.id], const NoteLink('nb1', pageId: 'p3'));
      final cal = back.calendar('cal1')!;
      expect((cal.kind, cal.from, cal.fetchedAt, cal.error), (CalendarKind.feed, FeedFrom.google, now, 'Couldn’t reach it.'));
      expect((cal.viewOnly, cal.editable, cal.linkable, cal.source, cal.fullName), (true, false, true, 'Google', 'School · Google Calendar'));
      expect(const CalendarInfo(id: 'x', name: 'Club', kind: CalendarKind.feed, from: FeedFrom.web).source, 'Link');
    });
  });
}
