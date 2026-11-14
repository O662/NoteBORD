import 'package:flutter/foundation.dart' show immutable;

import 'calendar_model.dart';

// Google Calendar and Outlook (Microsoft Graph) as Endless sees them: the
// account's calendars, and their events between two instants. A repeating
// event comes back as one item with every time it happens there (moved
// times included, cancelled ones left out); a time changed to another
// title there (an exception) comes back as an item of its own. The REST
// clients are remote_google.dart and remote_outlook.dart.

/// A calendar in the account.
@immutable
class RemoteCalendar {
  const RemoteCalendar({required this.id, required this.name, this.canEdit = true, this.primary = false, this.shown = true});

  final String id;
  final String name;

  /// Events can be added and changed (owner or writer).
  final bool canEdit;

  /// The account's own calendar (Google: its id is the address).
  final bool primary;

  /// Shown in Google Calendar or Outlook (so shown here at first).
  final bool shown;
}

/// An event there: a single event, a repeating one (with [times]), or one
/// time of a repeating event changed there ([seriesOf]).
@immutable
class RemoteItem {
  const RemoteItem({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.etag,
    this.allDay = false,
    this.repeat,
    this.rule,
    this.times,
    this.instances = const {},
    this.seriesOf,
    this.updated,
  });

  final String id;
  final String? etag;
  final String title;

  /// Instants in UTC; for an all-day event, local midnights (end exclusive).
  /// A repeating event's are its first time's.
  final DateTime start;
  final DateTime end;
  final bool allDay;

  /// Its repeat, when Endless can show it as its own.
  final Repeat? repeat;

  /// A repeating event's rule as it's kept there (non-null for every
  /// repeating event).
  final Object? rule;

  /// Every time a repeating event happens in the window read.
  final List<EventTime>? times;

  /// Each time's id there, by day ([dayKey]).
  final Map<String, String> instances;
  final String? seriesOf;

  /// When it was last changed there.
  final DateTime? updated;

  bool get series => rule != null;
}

/// The call failed because the event changed there since it was read
/// (HTTP 412).
class RemoteConflict implements Exception {
  const RemoteConflict();
}

/// The event isn't there any more (HTTP 404 or 410).
class RemoteGone implements Exception {
  const RemoteGone();
}

/// One account's calendars at Google or Microsoft.
abstract class CalendarRemote {
  Future<List<RemoteCalendar>> calendars();

  /// Everything in calendar [calendarId] that happens between [from] and
  /// [to] (UTC). Throws [RemoteGone] if the calendar is gone.
  Future<List<RemoteItem>> read(String calendarId, DateTime from, DateTime to);

  /// Event [id] as it is now (without its times), or null if it's gone.
  Future<RemoteItem?> get(String calendarId, String id);

  /// Adds [e] (and its repeat) to calendar [calendarId].
  Future<RemoteItem> create(String calendarId, CalEvent e);

  /// Sends what changed in [e]: its [title], its times ([when]), its repeat
  /// ([rule]). Throws [RemoteConflict] if [etag] isn't current, [RemoteGone]
  /// if it was deleted there.
  Future<RemoteItem> update(String calendarId, String id, String? etag, CalEvent e, {required bool title, required bool when, required bool rule});

  /// Deletes event [id] (or one time of a repeating event, by its time's
  /// id). Gone already is fine. Throws [RemoteConflict] if [etag] isn't
  /// current.
  Future<void> delete(String calendarId, String id, {String? etag});

  /// The id of the time repeating event [seriesId] has between [from] and
  /// [to], if any.
  Future<String?> instanceOn(String calendarId, String seriesId, DateTime from, DateTime to);
}

// --- Repeats ---------------------------------------------------------------

const _days = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
const _graphDays = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];

/// The repeat in Google's RRULE lines (["RRULE:FREQ=WEEKLY;BYDAY=FR"]), if
/// Endless can show it as its own: every day, weekdays, or every week on
/// the day it starts ([firstDay]), with or without an end. Otherwise null
/// (every 2 weeks, monthly, a number of times, extra dates…).
Repeat? repeatFromRRule(List<String> lines, DateTime firstDay) {
  final rrules = lines.where((l) => l.toUpperCase().startsWith('RRULE:')).toList();
  if (rrules.length != 1 || lines.any((l) => l.toUpperCase().startsWith('RDATE'))) return null;
  final parts = <String, String>{};
  for (final p in rrules.single.substring(6).split(';')) {
    final eq = p.indexOf('=');
    if (eq > 0) parts[p.substring(0, eq).toUpperCase()] = p.substring(eq + 1).toUpperCase();
  }
  if (parts.keys.any((k) => !const {'FREQ', 'INTERVAL', 'BYDAY', 'UNTIL', 'WKST'}.contains(k))) return null;
  if ((parts['INTERVAL'] ?? '1') != '1') return null;
  DateTime? until;
  if (parts['UNTIL'] case final u?) {
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z?))?$').firstMatch(u);
    if (m == null) return null;
    if (m[4] == null) {
      until = DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    } else {
      final at = DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), int.parse(m[4]!), int.parse(m[5]!), int.parse(m[6]!));
      until = dayOf(at);
    }
  }
  final byDay = parts['BYDAY']?.split(',').toSet();
  RepeatEvery? every;
  switch (parts['FREQ']) {
    case 'DAILY' when byDay == null:
      every = RepeatEvery.day;
    case 'WEEKLY':
      if (byDay == null || (byDay.length == 1 && byDay.single == _days[firstDay.weekday - 1])) {
        every = RepeatEvery.week;
      } else if (byDay.length == 5 && byDay.containsAll(_days.take(5))) {
        every = RepeatEvery.weekdays;
      }
    case 'DAILY' when byDay != null && byDay.length == 5 && byDay.containsAll(_days.take(5)):
      every = RepeatEvery.weekdays;
  }
  return every == null ? null : Repeat(every, until: until);
}

/// [r] as Google's recurrence lines, for an event starting at [start]
/// (all-day: [allDay]).
List<String> rruleOf(Repeat r, DateTime start, {required bool allDay}) {
  final rule = switch (r.every) {
    RepeatEvery.day => 'FREQ=DAILY',
    RepeatEvery.weekdays => 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR',
    RepeatEvery.week => 'FREQ=WEEKLY;BYDAY=${_days[(allDay ? start : start.toLocal()).weekday - 1]}',
  };
  String until() {
    final u = r.until!;
    if (allDay) return dayKey(u).replaceAll('-', '');
    // The end of that day here, in UTC.
    final end = DateTime(u.year, u.month, u.day, 23, 59, 59).toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${end.year}${two(end.month)}${two(end.day)}T${two(end.hour)}${two(end.minute)}${two(end.second)}Z';
  }

  return ['RRULE:$rule${r.until == null ? '' : ';UNTIL=${until()}'}'];
}

/// The repeat in Graph's recurrence (`{pattern, range}`), if Endless can
/// show it as its own; see [repeatFromRRule].
Repeat? repeatFromGraph(Object? recurrence, DateTime firstDay) {
  if (recurrence is! Map) return null;
  final pattern = recurrence['pattern'], range = recurrence['range'];
  if (pattern is! Map || range is! Map) return null;
  if ((pattern['interval'] as num? ?? 1) != 1) return null;
  final DateTime? until;
  switch (range['type']) {
    case 'noEnd':
      until = null;
    case 'endDate':
      until = parseDay(range['endDate']);
      if (until == null) return null;
    default:
      return null;
  }
  final days = {for (final d in (pattern['daysOfWeek'] as List?) ?? const []) '$d'.toLowerCase()};
  final RepeatEvery? every = switch (pattern['type']) {
    'daily' => RepeatEvery.day,
    'weekly' when days.length == 1 && days.single == _graphDays[firstDay.weekday - 1] => RepeatEvery.week,
    'weekly' when days.length == 5 && days.containsAll(_graphDays.take(5)) => RepeatEvery.weekdays,
    _ => null,
  };
  return every == null ? null : Repeat(every, until: until);
}

/// [r] as Graph's recurrence, starting on [firstDay], in time zone [zone].
Map<String, Object?> graphRecurrenceOf(Repeat r, DateTime firstDay, String zone) => {
  'pattern': switch (r.every) {
    RepeatEvery.day => {'type': 'daily', 'interval': 1},
    RepeatEvery.weekdays => {'type': 'weekly', 'interval': 1, 'daysOfWeek': _graphDays.take(5).toList(), 'firstDayOfWeek': 'sunday'},
    RepeatEvery.week => {
      'type': 'weekly',
      'interval': 1,
      'daysOfWeek': [_graphDays[firstDay.weekday - 1]],
      'firstDayOfWeek': 'sunday',
    },
  },
  'range': {
    'type': r.until == null ? 'noEnd' : 'endDate',
    'startDate': dayKey(firstDay),
    if (r.until != null) 'endDate': dayKey(r.until!),
    'recurrenceTimeZone': zone,
  },
};
