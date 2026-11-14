import 'package:http/http.dart' as http;

import '../sync/cloud_auth.dart';
import 'calendar_model.dart';
import 'local_zone.dart';
import 'remote.dart';
import 'rest_call.dart';

// Outlook and Microsoft 365 calendars (Microsoft Graph v1.0) as a
// [CalendarRemote]. Scope: `Calendars.ReadWrite`. Each time a repeating
// event happens comes from the calendar view; the series itself (its rule
// and first time) from the event. Times are asked for in UTC.

class OutlookCalendarRemote implements CalendarRemote {
  OutlookCalendarRemote(CloudAuth auth, http.Client client, {LocalZone Function()? zone})
    : _call = RestCall(auth, client, 'Outlook'),
      _zone = zone ?? localZone;

  final RestCall _call;
  final LocalZone Function() _zone;

  static const _utc = {'Prefer': 'outlook.timezone="UTC"'};
  static const _select = 'id,subject,start,end,isAllDay,type,seriesMasterId,isCancelled,lastModifiedDateTime,recurrence';

  static Uri _url(List<String> path, [Map<String, String>? query]) =>
      Uri(scheme: 'https', host: 'graph.microsoft.com', pathSegments: ['v1.0', 'me', ...path], queryParameters: query);

  /// Follows `@odata.nextLink` from [first].
  Future<List<Map>> _all(Uri first, String what) async {
    final out = <Map>[];
    Uri? url = first;
    while (url != null) {
      final j = await _call.json('GET', url, headers: {..._utc, 'Prefer': '${_utc['Prefer']}, odata.maxpagesize=250'}, what: what);
      out.addAll([for (final v in (j['value'] as List?) ?? const []) v as Map]);
      final next = j['@odata.nextLink'] as String?;
      url = next == null ? null : Uri.parse(next);
    }
    return out;
  }

  @override
  Future<List<RemoteCalendar>> calendars() async => [
    for (final c in await _all(_url(['calendars'], {r'$select': 'id,name,canEdit,isDefaultCalendar', r'$top': '100'}), 'Listing calendars'))
      if (c['id'] is String)
        RemoteCalendar(
          id: c['id'] as String,
          name: (c['name'] as String?) ?? 'Calendar',
          canEdit: c['canEdit'] != false,
          primary: c['isDefaultCalendar'] == true,
        ),
  ];

  /// A time as Graph gives it, in UTC ("2026-09-25T15:00:00.0000000").
  static DateTime? _at(Object? t, bool allDay) {
    if (t is! Map || t['dateTime'] is! String) return null;
    final s = t['dateTime'] as String;
    if (allDay) return s.length >= 10 ? parseDay(s.substring(0, 10)) : null;
    final whole = s.split('.').first;
    final zone = t['timeZone'] as String?;
    return DateTime.tryParse(zone == null || zone == 'UTC' || zone == 'Etc/UTC' ? '${whole}Z' : whole)?.toUtc();
  }

  static RemoteItem? _item(Map j, {String? seriesOf}) {
    final allDay = j['isAllDay'] == true;
    final start = _at(j['start'], allDay), end = _at(j['end'], allDay);
    if (start == null || end == null || j['id'] is! String) return null;
    final rule = j['recurrence'] is Map ? j['recurrence'] : null;
    return RemoteItem(
      id: j['id'] as String,
      etag: j['@odata.etag'] as String?,
      title: (j['subject'] as String?)?.isNotEmpty == true ? j['subject'] as String : '(No title)',
      start: start,
      end: end,
      allDay: allDay,
      rule: rule,
      repeat: rule == null ? null : repeatFromGraph(rule, allDay ? start : start.toLocal()),
      seriesOf: seriesOf,
      updated: DateTime.tryParse(j['lastModifiedDateTime'] as String? ?? '')?.toUtc(),
    );
  }

  static String _iso(DateTime t) => t.toUtc().toIso8601String().split('.').first;

  @override
  Future<List<RemoteItem>> read(String calendarId, DateTime from, DateTime to) async {
    final items = await _all(
      _url(['calendars', calendarId, 'calendarView'], {
        'startDateTime': '${_iso(from)}Z',
        'endDateTime': '${_iso(to)}Z',
        r'$select': 'id,subject,start,end,isAllDay,type,seriesMasterId,isCancelled,lastModifiedDateTime',
        r'$top': '250',
      }),
      'Reading events',
    );
    final singles = <RemoteItem>[];
    final bySeries = <String, List<Map>>{};
    for (final m in items) {
      if (m['isCancelled'] == true) continue;
      if (m['seriesMasterId'] case final String series when m['type'] != 'singleInstance') {
        (bySeries[series] ??= []).add(m);
      } else if (_item(m) case final item?) {
        singles.add(item);
      }
    }
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
          ids[dayKey(i.allDay ? i.start : dayOf(i.start))] = i.id;
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
            rule: master.rule ?? const <String, Object?>{},
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
      final j = await _call.json('GET', _url(['events', id], {r'$select': _select}), headers: _utc, what: 'Reading an event');
      return j['isCancelled'] == true ? null : _item(j);
    } on RemoteGone {
      return null;
    }
  }

  /// The zone events are sent in: Windows's name for the tablet's zone when
  /// it has one, else the database's.
  String get _zoneName {
    final z = _zone();
    return z.windows ?? z.iana;
  }

  Map<String, Object?> _when(DateTime t, bool allDay) {
    final utc = _zone().iana == 'UTC';
    final local = allDay ? t : (utc ? t.toUtc() : t.toLocal());
    String two(int n) => n.toString().padLeft(2, '0');
    final wall = allDay
        ? '${dayKey(local)}T00:00:00'
        : '${local.year.toString().padLeft(4, '0')}-${two(local.month)}-${two(local.day)}T${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
    return {'dateTime': wall, 'timeZone': utc ? 'UTC' : _zoneName};
  }

  /// [e]'s rule for Graph: its repeat, or the rule kept as it was, starting
  /// on [e]'s first day.
  Map<String, Object?>? _rule(CalEvent e) {
    final first = e.allDay ? e.start : dayOf(e.start);
    if (e.repeat case final r?) return graphRecurrenceOf(r, first, _zoneName);
    if (e.rule case final Map raw) {
      final range = {...((raw['range'] as Map?) ?? const {}).cast<String, Object?>(), 'startDate': dayKey(first)};
      return {...raw.cast<String, Object?>(), 'range': range};
    }
    return null;
  }

  @override
  Future<RemoteItem> create(String calendarId, CalEvent e) async {
    final j = await _call.json(
      'POST',
      _url(['calendars', calendarId, 'events']),
      headers: _utc,
      body: {
        'subject': e.title,
        'start': _when(e.start, e.allDay),
        'end': _when(e.end, e.allDay),
        'isAllDay': e.allDay,
        'recurrence': ?_rule(e),
      },
      what: 'Adding “${e.title}”',
    );
    return _item(j)!;
  }

  @override
  Future<RemoteItem> update(String calendarId, String id, String? etag, CalEvent e, {required bool title, required bool when, required bool rule}) async {
    final series = e.repeat != null || e.rule != null;
    final j = await _call.json(
      'PATCH',
      _url(['events', id]),
      headers: {..._utc, 'If-Match': ?etag},
      body: {
        if (title) 'subject': e.title,
        if (when || rule) ...{'start': _when(e.start, e.allDay), 'end': _when(e.end, e.allDay), 'isAllDay': e.allDay},
        // A series' rule starts on its first day, so it goes with any change
        // of times.
        if (rule || (when && series)) 'recurrence': _rule(e),
      },
      what: 'Changing “${e.title}”',
    );
    return _item(j)!;
  }

  @override
  Future<void> delete(String calendarId, String id, {String? etag}) async {
    try {
      await _call.json('DELETE', _url(['events', id]), headers: {'If-Match': ?etag}, what: 'Deleting an event');
    } on RemoteGone {
      return;
    }
  }

  @override
  Future<String?> instanceOn(String calendarId, String seriesId, DateTime from, DateTime to) async {
    try {
      final j = await _call.json(
        'GET',
        _url(['events', seriesId, 'instances'], {'startDateTime': '${_iso(from)}Z', 'endDateTime': '${_iso(to)}Z', r'$select': 'id,isCancelled'}),
        headers: _utc,
        what: 'Reading a repeating event',
      );
      return [
        for (final i in (j['value'] as List?) ?? const [])
          if ((i as Map)['isCancelled'] != true) i['id'] as String,
      ].firstOrNull;
    } on RemoteGone {
      return null;
    }
  }
}
