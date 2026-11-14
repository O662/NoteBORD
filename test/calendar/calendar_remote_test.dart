// Google Calendar and Outlook over REST (Phase 9c), against canned
// answers in the shape their docs give: reading events (a repeating one,
// one time renamed there, cancelled, all-day), what's sent to add and
// change one (only what changed, If-Match), 412 and 410; repeats as RRULE
// and Graph recurrence; and finding the tablet's time zone by name.

import 'dart:convert';

import 'package:endless/calendar/calendar_model.dart';
import 'package:endless/calendar/local_zone.dart';
import 'package:endless/calendar/remote.dart';
import 'package:endless/calendar/remote_google.dart';
import 'package:endless/calendar/remote_outlook.dart';
import 'package:endless/sync/cloud.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/timezone.dart' as tz;

import '../sync/sync_app_helpers.dart';

const _chicago = (iana: 'America/Chicago', windows: 'Central Standard Time');
final _from = DateTime.utc(2026, 3, 26), _to = DateTime.utc(2028, 3, 26);

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  group('Google Calendar', () {
    test('calendars: which can be changed, and which show', () async {
      final remote = GoogleCalendarRemote(
        FakeAuth(CloudKind.google),
        MockClient((q) async {
          expect(q.url.path, '/calendar/v3/users/me/calendarList');
          expect(q.headers['Authorization'], 'Bearer token');
          return _json({
            'items': [
              {'id': 'kim@gmail.com', 'summary': 'kim@gmail.com', 'summaryOverride': 'School', 'accessRole': 'owner', 'primary': true, 'selected': true},
              {'id': 'en.usa#holiday@group.v.calendar.google.com', 'summary': 'Holidays in United States', 'accessRole': 'reader'},
            ],
          });
        }),
        zone: () => _chicago,
      );
      final cals = await remote.calendars();
      expect([for (final c in cals) (c.name, c.canEdit, c.primary, c.shown)], [
        ('School', true, true, true),
        ('Holidays in United States', false, false, false),
      ]);
    });

    test('reading: a series with its times, one renamed there, all-day, cancelled', () async {
      final asked = <String>[];
      final remote = GoogleCalendarRemote(
        FakeAuth(CloudKind.google),
        MockClient((q) async {
          asked.add(q.url.path);
          if (q.url.path == '/calendar/v3/calendars/kim@gmail.com/events') {
            expect(q.url.queryParameters['singleEvents'], 'true');
            expect(q.url.queryParameters['timeMin'], _from.toIso8601String());
            return _json({
              'items': [
                {
                  'id': 'mid',
                  'etag': '"31"',
                  'status': 'confirmed',
                  'summary': 'Physics midterm',
                  'start': {'dateTime': '2026-09-28T10:00:00-05:00'},
                  'end': {'dateTime': '2026-09-28T11:00:00-05:00'},
                  'updated': '2026-09-20T12:00:00.000Z',
                },
                {
                  'id': 'lec_20260928T150000Z',
                  'summary': 'Physics lecture',
                  'recurringEventId': 'lec',
                  'start': {'dateTime': '2026-09-28T10:00:00-05:00'},
                  'end': {'dateTime': '2026-09-28T11:15:00-05:00'},
                },
                {
                  'id': 'lec_20261005T150000Z',
                  'summary': 'Physics lecture: review',
                  'recurringEventId': 'lec',
                  'start': {'dateTime': '2026-10-05T10:00:00-05:00'},
                  'end': {'dateTime': '2026-10-05T11:15:00-05:00'},
                },
                {'id': 'gone', 'status': 'cancelled', 'recurringEventId': 'lec'},
                {
                  'id': 'tg',
                  'summary': 'Thanksgiving',
                  'start': {'date': '2026-11-26'},
                  'end': {'date': '2026-11-27'},
                },
              ],
            });
          }
          expect(q.url.path, '/calendar/v3/calendars/kim@gmail.com/events/lec');
          return _json({
            'id': 'lec',
            'etag': '"7"',
            'summary': 'Physics lecture',
            'start': {'dateTime': '2026-09-07T10:00:00-05:00', 'timeZone': 'America/Chicago'},
            'end': {'dateTime': '2026-09-07T11:15:00-05:00', 'timeZone': 'America/Chicago'},
            'recurrence': ['RRULE:FREQ=WEEKLY;BYDAY=MO'],
          });
        }),
        zone: () => _chicago,
      );
      final items = await remote.read('kim@gmail.com', _from, _to);
      final byId = {for (final i in items) i.id: i};
      expect(byId.keys, unorderedEquals(['mid', 'tg', 'lec', 'lec_20261005T150000Z']));
      expect((byId['mid']!.start, byId['mid']!.etag, byId['mid']!.series), (DateTime.utc(2026, 9, 28, 15), '"31"', false));
      expect((byId['tg']!.allDay, byId['tg']!.start, byId['tg']!.end), (true, DateTime(2026, 11, 26), DateTime(2026, 11, 27)));
      final lec = byId['lec']!;
      expect((lec.series, lec.etag, lec.start), (true, '"7"', DateTime.utc(2026, 9, 7, 15)));
      expect(lec.times, [(start: DateTime.utc(2026, 9, 28, 15), end: DateTime.utc(2026, 9, 28, 16, 15))]);
      expect(lec.instances, {dayKey(dayOf(DateTime.utc(2026, 9, 28, 15))): 'lec_20260928T150000Z'});
      expect(byId['lec_20261005T150000Z']!.seriesOf, 'lec');
      expect(asked.where((p) => p.endsWith('/events/lec')), hasLength(1));
    });

    test('adding, changing only what changed, and deleting', () async {
      final sent = <http.Request>[];
      var status = 200;
      final remote = GoogleCalendarRemote(
        FakeAuth(CloudKind.google),
        MockClient((q) async {
          sent.add(q);
          if (q.method == 'DELETE') return http.Response('', 410);
          return _json({
            'id': 'new1',
            'etag': '"2"',
            'summary': 'Gym',
            'start': {'dateTime': '2026-09-28T12:00:00Z'},
            'end': {'dateTime': '2026-09-28T13:00:00Z'},
          }, status);
        }),
        zone: () => _chicago,
      );
      final gym = CalEvent(
        id: 'ev1',
        calendarId: 'c',
        title: 'Gym',
        start: DateTime(2026, 9, 28, 7).toUtc(),
        end: DateTime(2026, 9, 28, 8).toUtc(),
        repeat: const Repeat(RepeatEvery.week),
      );
      final made = await remote.create('kim@gmail.com', gym);
      expect((made.id, made.etag), ('new1', '"2"'));
      final body = jsonDecode(sent.last.body) as Map;
      expect(sent.last.method, 'POST');
      expect(body['summary'], 'Gym');
      expect(body['start'], {'dateTime': DateTime(2026, 9, 28, 7).toUtc().toIso8601String(), 'timeZone': 'America/Chicago'});
      expect(body['recurrence'], ['RRULE:FREQ=WEEKLY;BYDAY=MO']);

      await remote.update('kim@gmail.com', 'new1', '"2"', gym.copyWith(title: 'Gym, early'), title: true, when: false, rule: false);
      expect(sent.last.method, 'PATCH');
      expect(sent.last.headers['If-Match'], '"2"');
      expect(jsonDecode(sent.last.body), {'summary': 'Gym, early'});

      status = 412;
      expect(
        () => remote.update('kim@gmail.com', 'new1', '"1"', gym, title: true, when: false, rule: false),
        throwsA(isA<RemoteConflict>()),
      );
      await remote.delete('kim@gmail.com', 'new1');
    });

    test('a refused change says why', () async {
      final remote = GoogleCalendarRemote(
        FakeAuth(CloudKind.google),
        MockClient(
          (q) async => _json({
            'error': {'code': 403, 'message': 'You need to have writer access to this calendar.'},
          }, 403),
        ),
        zone: () => _chicago,
      );
      final e = CalEvent(id: 'a', calendarId: 'c', title: 'X', start: DateTime.utc(2026, 9, 28), end: DateTime.utc(2026, 9, 28, 1));
      expect(
        () => remote.create('holidays', e),
        throwsA(isA<CloudException>().having((x) => x.message, 'message', contains('writer access')).having((x) => x.failure, 'failure', CloudFailure.other)),
      );
    });
  });

  group('Outlook', () {
    test('reading: a series from the calendar view and its master, all-day, cancelled, pages', () async {
      final remote = OutlookCalendarRemote(
        FakeAuth(CloudKind.onedrive),
        MockClient((q) async {
          expect(q.headers['Prefer'], contains('outlook.timezone="UTC"'));
          if (q.url.path == '/v1.0/me/calendars/AAA=/calendarView' && q.url.queryParameters['page'] == null) {
            expect(q.url.queryParameters['startDateTime'], '2026-03-26T00:00:00Z');
            return _json({
              'value': [
                {
                  'id': 'o1',
                  'subject': 'Physics lecture',
                  'type': 'occurrence',
                  'seriesMasterId': 'm1',
                  '@odata.etag': 'W/"a"',
                  'start': {'dateTime': '2026-09-28T15:00:00.0000000', 'timeZone': 'UTC'},
                  'end': {'dateTime': '2026-09-28T16:15:00.0000000', 'timeZone': 'UTC'},
                },
                {
                  'id': 'ad',
                  'subject': 'Fall break',
                  'type': 'singleInstance',
                  'isAllDay': true,
                  'start': {'dateTime': '2026-09-26T00:00:00.0000000', 'timeZone': 'UTC'},
                  'end': {'dateTime': '2026-09-27T00:00:00.0000000', 'timeZone': 'UTC'},
                },
                {'id': 'x', 'subject': 'Gone', 'isCancelled': true, 'type': 'singleInstance'},
              ],
              '@odata.nextLink': 'https://graph.microsoft.com/v1.0/me/calendars/AAA=/calendarView?page=2',
            });
          }
          if (q.url.path.endsWith('/calendarView')) return _json({'value': []});
          expect(q.url.path, '/v1.0/me/events/m1');
          return _json({
            'id': 'm1',
            '@odata.etag': 'W/"m"',
            'subject': 'Physics lecture',
            'isAllDay': false,
            'start': {'dateTime': '2026-09-07T15:00:00.0000000', 'timeZone': 'UTC'},
            'end': {'dateTime': '2026-09-07T16:15:00.0000000', 'timeZone': 'UTC'},
            'recurrence': {
              'pattern': {
                'type': 'weekly',
                'interval': 1,
                'daysOfWeek': ['monday'],
              },
              'range': {'type': 'endDate', 'startDate': '2026-09-07', 'endDate': '2026-12-11'},
            },
          });
        }),
        zone: () => _chicago,
      );
      final items = await remote.read('AAA=', _from, _to);
      final byId = {for (final i in items) i.id: i};
      expect(byId.keys, unorderedEquals(['ad', 'm1']));
      expect((byId['ad']!.allDay, byId['ad']!.start, byId['ad']!.end), (true, DateTime(2026, 9, 26), DateTime(2026, 9, 27)));
      final m = byId['m1']!;
      expect((m.etag, m.start, m.repeat), ('W/"m"', DateTime.utc(2026, 9, 7, 15), Repeat(RepeatEvery.week, until: DateTime(2026, 12, 11))));
      expect(m.times, [(start: DateTime.utc(2026, 9, 28, 15), end: DateTime.utc(2026, 9, 28, 16, 15))]);
      expect(m.instances.values, ['o1']);
    });

    test('adding in the tablet’s zone; moving a series moves its rule’s start', () async {
      final sent = <http.Request>[];
      final remote = OutlookCalendarRemote(
        FakeAuth(CloudKind.onedrive),
        MockClient((q) async {
          sent.add(q);
          return _json({
            'id': 'n1',
            '@odata.etag': 'W/"1"',
            'subject': 'Gym',
            'start': {'dateTime': '2026-09-28T12:00:00.0000000', 'timeZone': 'UTC'},
            'end': {'dateTime': '2026-09-28T13:00:00.0000000', 'timeZone': 'UTC'},
          }, q.method == 'POST' ? 201 : 200);
        }),
        zone: () => _chicago,
      );
      final gym = CalEvent(
        id: 'ev1',
        calendarId: 'c',
        title: 'Gym',
        start: DateTime(2026, 9, 28, 7).toUtc(),
        end: DateTime(2026, 9, 28, 8).toUtc(),
        repeat: const Repeat(RepeatEvery.weekdays),
      );
      await remote.create('AAA=', gym);
      expect(sent.last.url.path, '/v1.0/me/calendars/AAA=/events');
      final body = jsonDecode(sent.last.body) as Map;
      expect(body['start'], {'dateTime': '2026-09-28T07:00:00', 'timeZone': 'Central Standard Time'});
      expect(body['isAllDay'], false);
      expect((body['recurrence'] as Map)['pattern'], {
        'type': 'weekly',
        'interval': 1,
        'daysOfWeek': ['monday', 'tuesday', 'wednesday', 'thursday', 'friday'],
        'firstDayOfWeek': 'sunday',
      });
      expect((body['recurrence'] as Map)['range'], {'type': 'noEnd', 'startDate': '2026-09-28', 'recurrenceTimeZone': 'Central Standard Time'});

      final later = gym.copyWith(start: DateTime(2026, 9, 29, 7).toUtc(), end: DateTime(2026, 9, 29, 8).toUtc());
      await remote.update('AAA=', 'n1', 'W/"1"', later, title: false, when: true, rule: false);
      expect(sent.last.method, 'PATCH');
      expect(sent.last.url.path, '/v1.0/me/events/n1');
      expect(sent.last.headers['If-Match'], 'W/"1"');
      final patch = jsonDecode(sent.last.body) as Map;
      expect(patch.keys, unorderedEquals(['start', 'end', 'isAllDay', 'recurrence']));
      expect(((patch['recurrence'] as Map)['range'] as Map)['startDate'], '2026-09-29');
    });
  });

  group('repeats', () {
    final friday = DateTime(2026, 9, 25);
    test('Google’s RRULE: what Endless can show, and what it keeps as it is', () {
      expect(repeatFromRRule(['RRULE:FREQ=WEEKLY;BYDAY=FR'], friday), const Repeat(RepeatEvery.week));
      expect(repeatFromRRule(['RRULE:FREQ=WEEKLY'], friday), const Repeat(RepeatEvery.week));
      expect(repeatFromRRule(['RRULE:FREQ=WEEKLY;WKST=SU;BYDAY=MO,TU,WE,TH,FR', 'EXDATE;TZID=America/Chicago:20261002T100000'], friday),
          const Repeat(RepeatEvery.weekdays));
      expect(repeatFromRRule(['RRULE:FREQ=DAILY;UNTIL=20261231'], friday), Repeat(RepeatEvery.day, until: DateTime(2026, 12, 31)));
      expect(repeatFromRRule(['RRULE:FREQ=DAILY;UNTIL=20261231T120000Z'], friday), Repeat(RepeatEvery.day, until: dayOf(DateTime.utc(2026, 12, 31, 12))));
      for (final other in [
        'RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=FR',
        'RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR',
        'RRULE:FREQ=WEEKLY;BYDAY=TH',
        'RRULE:FREQ=DAILY;COUNT=10',
        'RRULE:FREQ=MONTHLY;BYMONTHDAY=25',
      ]) {
        expect(repeatFromRRule([other], friday), isNull, reason: other);
      }
      expect(repeatFromRRule(['RRULE:FREQ=DAILY', 'RDATE:20261003T100000Z'], friday), isNull);

      expect(rruleOf(Repeat(RepeatEvery.week, until: DateTime(2026, 12, 11)), friday, allDay: true), ['RRULE:FREQ=WEEKLY;BYDAY=FR;UNTIL=20261211']);
      final until = DateTime(2026, 12, 11, 23, 59, 59).toUtc();
      expect(rruleOf(Repeat(RepeatEvery.day, until: DateTime(2026, 12, 11)), friday.add(const Duration(hours: 9)).toUtc(), allDay: false).single,
          endsWith('UNTIL=${until.year}${until.month}${until.day.toString().padLeft(2, '0')}T${until.hour.toString().padLeft(2, '0')}5959Z'));
    });

    test('Graph’s recurrence', () {
      Map<String, Object?> rec(String type, List<String> days, Map<String, Object?> range, {int interval = 1}) => {
        'pattern': {'type': type, 'interval': interval, 'daysOfWeek': days},
        'range': range,
      };
      const noEnd = {'type': 'noEnd', 'startDate': '2026-09-25'};
      expect(repeatFromGraph(rec('weekly', ['friday'], noEnd), friday), const Repeat(RepeatEvery.week));
      expect(repeatFromGraph(rec('daily', [], {'type': 'endDate', 'endDate': '2026-12-31'}), friday), Repeat(RepeatEvery.day, until: DateTime(2026, 12, 31)));
      expect(repeatFromGraph(rec('weekly', ['monday', 'tuesday', 'wednesday', 'thursday', 'friday'], noEnd), friday), const Repeat(RepeatEvery.weekdays));
      expect(repeatFromGraph(rec('weekly', ['friday'], noEnd, interval: 2), friday), isNull);
      expect(repeatFromGraph(rec('weekly', ['friday'], {'type': 'numbered', 'numberOfOccurrences': 10}), friday), isNull);
      expect(repeatFromGraph(rec('absoluteMonthly', [], noEnd), friday), isNull);
      expect(graphRecurrenceOf(Repeat(RepeatEvery.week, until: DateTime(2026, 12, 11)), friday, 'UTC'), {
        'pattern': {
          'type': 'weekly',
          'interval': 1,
          'daysOfWeek': ['friday'],
          'firstDayOfWeek': 'sunday',
        },
        'range': {'type': 'endDate', 'startDate': '2026-09-25', 'endDate': '2026-12-11', 'recurrenceTimeZone': 'UTC'},
      });
    });
  });

  group('the tablet’s time zone', () {
    final around = DateTime.utc(2026, 9, 25);
    test('by its Windows name or its own', () {
      expect(findZone(name: 'Central Standard Time', offsetAt: (_) => Duration.zero, around: around), _chicago);
      expect(findZone(name: 'Europe/Berlin', offsetAt: (_) => Duration.zero, around: around), (iana: 'Europe/Berlin', windows: 'W. Europe Standard Time'));
    });

    test('from an abbreviation, by its offsets through the year', () {
      ensureZones();
      Duration Function(DateTime) like(String zone) => (t) => tz.TZDateTime.from(t, tz.getLocation(zone)).timeZoneOffset;
      expect(findZone(name: 'CST', offsetAt: like('America/Chicago'), around: around), _chicago);
      expect(findZone(name: 'AEST', offsetAt: like('Australia/Sydney'), around: around).windows, 'AUS Eastern Standard Time');
      expect(findZone(name: 'IST', offsetAt: (_) => const Duration(hours: 5, minutes: 30), around: around).windows, 'India Standard Time');
    });
  });
}
