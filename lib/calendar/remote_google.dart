import 'package:http/http.dart' as http;

import '../sync/cloud_auth.dart';
import 'calendar_model.dart';
import 'local_zone.dart';
import 'remote.dart';
import 'rest_call.dart';

// Google Calendar (API v3) as a [CalendarRemote]. Scopes:
// `calendar.calendarlist.readonly` (the calendars) and `calendar.events`
// (their events). Repeating events are read twice over: each time it
// happens (singleEvents), and the series itself for its rule and its first
// time, so a change to the series doesn't cut off its past.

class GoogleCalendarRemote implements CalendarRemote {
  GoogleCalendarRemote(CloudAuth auth, http.Client client, {LocalZone Function()? zone})
    : _call = RestCall(auth, client, 'Google Calendar'),
      _zone = zone ?? localZone;

  final RestCall _call;
  final LocalZone Function() _zone;

  static Uri _url(List<String> path, [Map<String, String>? query]) =>
      Uri(scheme: 'https', host: 'www.googleapis.com', pathSegments: ['calendar', 'v3', ...path], queryParameters: query);

  static const _fields = 'id,etag,status,summary,start,end,recurringEventId,recurrence,updated';

  @override
  Future<List<RemoteCalendar>> calendars() async {
    final out = <RemoteCalendar>[];
    String? page;
    do {
      final j = await _call.json(
        'GET',
        _url(['users', 'me', 'calendarList'], {
          'minAccessRole': 'reader',
          'maxResults': '250',
          'fields': 'nextPageToken,items(id,summary,summaryOverride,accessRole,primary,selected,hidden,deleted)',
          'pageToken': ?page,
        }),
        what: 'Listing calendars',
      );
      for (final c in (j['items'] as List?) ?? const []) {
        final m = c as Map;
        if (m['deleted'] == true || m['id'] is! String) continue;
        out.add(
          RemoteCalendar(
            id: m['id'] as String,
            name: (m['summaryOverride'] ?? m['summary'] ?? 'Calendar') as String,
            canEdit: m['accessRole'] == 'owner' || m['accessRole'] == 'writer',
            primary: m['primary'] == true,
            shown: m['selected'] == true && m['hidden'] != true,
          ),
        );
      }
      page = j['nextPageToken'] as String?;
    } while (page != null);
    return out;
  }

  /// A time as Google gives it ({date} or {dateTime}).
  static DateTime? _at(Object? t) {
    if (t is! Map) return null;
    if (t['date'] is String) return parseDay(t['date']);
    return DateTime.tryParse(t['dateTime'] as String? ?? '')?.toUtc();
  }

  static RemoteItem? _item(Map j, {String? seriesOf}) {
    final start = _at(j['start']), end = _at(j['end']);
    if (start == null || end == null || j['id'] is! String) return null;
    final allDay = (j['start'] as Map)['date'] is String;
    final rule = (j['recurrence'] as List?)?.whereType<String>().toList();
    return RemoteItem(
      id: j['id'] as String,
      etag: j['etag'] as String?,
      title: (j['summary'] as String?) ?? '(No title)',
      start: start,
      end: end,
      allDay: allDay,
      rule: rule == null || rule.isEmpty ? null : rule,
      repeat: rule == null || rule.isEmpty ? null : repeatFromRRule(rule, allDay ? start : start.toLocal()),
      seriesOf: seriesOf,
      updated: DateTime.tryParse(j['updated'] as String? ?? '')?.toUtc(),
    );
  }

  @override
  Future<List<RemoteItem>> read(String calendarId, DateTime from, DateTime to) async {
    final singles = <RemoteItem>[];
    final bySeries = <String, List<Map>>{};
    String? page;
    do {
      final j = await _call.json(
        'GET',
        _url(['calendars', calendarId, 'events'], {
          'singleEvents': 'true',
          'timeMin': from.toUtc().toIso8601String(),
          'timeMax': to.toUtc().toIso8601String(),
          'maxResults': '2500',
          'fields': 'nextPageToken,items($_fields,originalStartTime)',
          'pageToken': ?page,
        }),
        what: 'Reading events',
      );
      for (final e in (j['items'] as List?) ?? const []) {
        final m = e as Map;
        if (m['status'] == 'cancelled') continue;
        if (m['recurringEventId'] case final String series) {
          (bySeries[series] ??= []).add(m);
        } else if (_item(m) case final item?) {
          singles.add(item);
        }
      }
      page = j['nextPageToken'] as String?;
    } while (page != null);

    final series = await inBatches(bySeries.entries, 6, (s) async {
      final master = await get(calendarId, s.key);
      final out = <RemoteItem>[];
      final times = <EventTime>[];
      final ids = <String, String>{};
      for (final m in s.value) {
        final i = _item(m, seriesOf: s.key);
        if (i == null) continue;
        if (master == null || i.title != master.title) {
          out.add(i);
        } else {
          times.add((start: i.start, end: i.end));
          ids[dayKey(dayOf(i.start))] = i.id;
        }
      }
      if (master != null) {
        times.sort((a, b) => a.start.compareTo(b.start));
        out.add(
          RemoteItem(
            id: master.id,
            etag: master.etag,
            title: master.title,
            start: master.start,
            end: master.end,
            allDay: master.allDay,
            repeat: master.repeat,
            rule: master.rule ?? const <String>[],
            times: times,
            instances: ids,
            updated: master.updated,
          ),
        );
      }
      return out;
    });
    return [...singles, for (final s in series) ...s];
  }

  @override
  Future<RemoteItem?> get(String calendarId, String id) async {
    try {
      final j = await _call.json('GET', _url(['calendars', calendarId, 'events', id], {'fields': _fields}), what: 'Reading an event');
      return j['status'] == 'cancelled' ? null : _item(j);
    } on RemoteGone {
      return null;
    }
  }

  Map<String, Object?> _when(DateTime t, bool allDay) => allDay ? {'date': dayKey(t)} : {'dateTime': t.toUtc().toIso8601String(), 'timeZone': _zone().iana};

  List<String>? _rule(CalEvent e) => switch (e.repeat) {
    final r? => rruleOf(r, e.start, allDay: e.allDay),
    null => e.rule is List ? [...(e.rule as List).whereType<String>()] : null,
  };

  @override
  Future<RemoteItem> create(String calendarId, CalEvent e) async {
    final j = await _call.json(
      'POST',
      _url(['calendars', calendarId, 'events'], {'fields': _fields}),
      body: {
        'summary': e.title,
        'start': _when(e.start, e.allDay),
        'end': _when(e.end, e.allDay),
        'recurrence': ?_rule(e),
      },
      what: 'Adding “${e.title}”',
    );
    return _item(j)!;
  }

  @override
  Future<RemoteItem> update(String calendarId, String id, String? etag, CalEvent e, {required bool title, required bool when, required bool rule}) async {
    final j = await _call.json(
      'PATCH',
      _url(['calendars', calendarId, 'events', id], {'fields': _fields}),
      headers: {'If-Match': ?etag},
      body: {
        if (title) 'summary': e.title,
        if (when || rule) ...{'start': _when(e.start, e.allDay), 'end': _when(e.end, e.allDay)},
        if (rule) 'recurrence': _rule(e) ?? const <String>[],
      },
      what: 'Changing “${e.title}”',
    );
    return _item(j)!;
  }

  @override
  Future<void> delete(String calendarId, String id, {String? etag}) async {
    try {
      await _call.json('DELETE', _url(['calendars', calendarId, 'events', id]), headers: {'If-Match': ?etag}, what: 'Deleting an event');
    } on RemoteGone {
      return;
    }
  }

  @override
  Future<String?> instanceOn(String calendarId, String seriesId, DateTime from, DateTime to) async {
    try {
      final j = await _call.json(
        'GET',
        _url(['calendars', calendarId, 'events', seriesId, 'instances'], {
          'timeMin': from.toUtc().toIso8601String(),
          'timeMax': to.toUtc().toIso8601String(),
          'fields': 'items(id,status)',
        }),
        what: 'Reading a repeating event',
      );
      return [
        for (final i in (j['items'] as List?) ?? const [])
          if ((i as Map)['status'] != 'cancelled') i['id'] as String,
      ].firstOrNull;
    } on RemoteGone {
      return null;
    }
  }
}
