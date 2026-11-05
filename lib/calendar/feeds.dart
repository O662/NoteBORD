import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:firstfloor_calendar/firstfloor_calendar.dart' as ics;
import 'package:timezone/data/latest_all.dart' as tzdata;

import '../recognition/segment.dart' show fnv64;
import 'calendar_model.dart';
import 'windows_zones.dart';

// Calendar links: the private iCal (.ics) address Google Calendar and
// Outlook give for a calendar. Endless reads the file at the address and
// shows its events, view only; nothing is sent back. Repeats are worked out
// when the file is read, for [feedPast] before now to [feedAhead] after.

/// How far back and ahead a calendar link's repeating events are worked out.
const feedPast = Duration(days: 183);
const feedAhead = Duration(days: 549);

/// Why a calendar link couldn't be added or read again.
class FeedException implements Exception {
  const FeedException(this.message);

  static const notLink = FeedException('That isn’t a web address. Paste the whole link, starting with https://.');
  static const offline = FeedException('Couldn’t reach it. Check the connection and try again.');
  static const gone = FeedException('The link doesn’t open any more. Copy it again and add it again.');
  static const notCalendar = FeedException('That link isn’t a calendar. Copy the iCal (.ics) address.');
  static const tooBig = FeedException('That calendar is too big to read (over 20 MB).');
  static const forgotten = FeedException('The link isn’t on this tablet any more. Remove this calendar and add it again.');

  final String message;

  @override
  String toString() => message;
}

/// The link in [text] (pasted), or null if it isn't one. `webcal://` is
/// how calendars say "subscribe"; it's https underneath.
Uri? feedUri(String text) {
  var t = text.trim();
  final lower = t.toLowerCase();
  if (lower.startsWith('webcal://')) t = 'https://${t.substring(9)}';
  if (lower.startsWith('webcals://')) t = 'https://${t.substring(10)}';
  final u = Uri.tryParse(t);
  if (u == null || (u.scheme != 'https' && u.scheme != 'http') || !u.host.contains('.')) return null;
  return u;
}

/// Where a link is from, by its address.
FeedFrom feedFromOf(Uri u) {
  final h = u.host.toLowerCase();
  bool at(String domain) => h == domain || h.endsWith('.$domain');
  if (at('google.com')) return FeedFrom.google;
  if (at('outlook.com') || at('office365.com') || at('office.com') || at('live.com') || at('hotmail.com')) return FeedFrom.outlook;
  return FeedFrom.web;
}

/// Reads the file at a calendar link.
abstract class FeedFetcher {
  /// The file's text. Throws a [FeedException].
  Future<String> fetch(Uri uri);
}

class HttpFeedFetcher implements FeedFetcher {
  static const limit = 20 * 1024 * 1024;

  @override
  Future<String> fetch(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..userAgent = 'Endless';
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 30));
      request.headers.set(HttpHeaders.acceptHeader, 'text/calendar, */*;q=0.5');
      final response = await request.close().timeout(const Duration(seconds: 30));
      final status = response.statusCode;
      if (status == 401 || status == 403 || status == 404 || status == 410) throw FeedException.gone;
      if (status != 200) throw FeedException('The calendar didn’t answer (error $status). Endless tries again later.');
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 60))) {
        bytes.add(chunk);
        if (bytes.length > limit) throw FeedException.tooBig;
      }
      return utf8.decode(bytes.takeBytes(), allowMalformed: true);
    } on FeedException {
      rethrow;
    } on SocketException {
      throw FeedException.offline;
    } on TimeoutException {
      throw FeedException.offline;
    } on HandshakeException {
      throw FeedException.offline;
    } on HttpException {
      throw FeedException.offline;
    } finally {
      client.close(force: true);
    }
  }
}

/// What a calendar link's file has.
class FeedRead {
  const FeedRead({this.name, this.events = const [], this.skipped = 0});

  /// The calendar's own name (X-WR-CALNAME), if it says.
  final String? name;
  final List<CalEvent> events;

  /// Events it couldn't read (broken in the file).
  final int skipped;
}

/// [readFeed] away from the screen's thread (a year of a busy calendar
/// takes a moment).
Future<FeedRead> readFeedInBackground(String text, String calendarId, DateTime now) =>
    Isolate.run(() => readFeed(text, calendarId, now));

var _zones = false;

/// The events in [text] (an .ics file) for calendar [calendarId], their
/// repeats worked out around [now]. Throws [FeedException.notCalendar] if
/// it isn't a calendar. An event that can't be read is skipped, not the
/// whole file.
FeedRead readFeed(String text, String calendarId, DateTime now) {
  if (!text.contains('BEGIN:VCALENDAR')) throw FeedException.notCalendar;
  if (!_zones) {
    tzdata.initializeTimeZones();
    _zones = true;
  }
  final ics.CalendarDocument doc;
  try {
    final start = text.indexOf('BEGIN:VCALENDAR');
    doc = ics.DocumentParser().parse(withIanaZones(text.substring(start)));
  } on Object {
    throw FeedException.notCalendar;
  }
  final from = now.toUtc().subtract(feedPast), to = now.toUtc().add(feedAhead);
  final parser = ics.CalendarParser();

  // Each event's first version, and the times moved or taken off
  // (RECURRENCE-ID), by UID.
  final masters = <String, List<ics.EventComponent>>{};
  final moved = <String, List<_Moved>>{};
  var skipped = 0;
  for (final c in doc.componentsNamed('VEVENT')) {
    try {
      final e = parser.parseComponent<ics.EventComponent>(c);
      if (e.dtstart == null) {
        skipped++;
        continue;
      }
      final rid = c.propertiesNamed('RECURRENCE-ID').firstOrNull;
      if (rid == null) {
        (masters[e.uid] ??= []).add(e);
      } else {
        (moved[e.uid] ??= []).add(_Moved(e, ics.parseCalDateOrDateTime(rid)));
      }
    } on Object {
      skipped++;
    }
  }

  final events = <CalEvent>[];
  String id(String key) => '${calendarId}_${fnv64(key)}';
  for (final MapEntry(key: uid, value: list) in masters.entries) {
    for (final (i, m) in list.indexed) {
      final key = i == 0 ? uid : '$uid#$i';
      try {
        events.addAll(_events(m, i == 0 ? moved.remove(uid) ?? const [] : const [], calendarId, id(key), id, from, to));
      } on Object {
        skipped++;
      }
    }
  }
  // Moved times whose event isn't in the file: events of their own.
  for (final MapEntry(key: uid, value: list) in moved.entries) {
    for (final o in list) {
      if (_cancelled(o.event)) continue;
      final t = _span(o.event.dtstart!, o.event.effectiveEnd, null);
      if (!_overlaps(t, from, to)) continue;
      events.add(_single(o.event, calendarId, id('$uid|${o.at}'), t));
    }
  }
  String? name;
  if (doc.propertiesNamed('X-WR-CALNAME').firstOrNull case final p?) {
    name = ics.parseString(p).trim();
    if (name.isEmpty) name = null;
  }
  return FeedRead(name: name, events: events, skipped: skipped);
}

class _Moved {
  const _Moved(this.event, this.at);

  final ics.EventComponent event;

  /// The time it replaces.
  final ics.CalDateTime at;
}

bool _cancelled(ics.EventComponent e) => e.statusName?.toUpperCase() == 'CANCELLED';

String _title(ics.EventComponent e) {
  final t = e.summary?.trim() ?? '';
  return t.isEmpty ? '(No title)' : t;
}

/// How long a timed event lasts, or how many days an all-day one has.
({Duration length, int days}) _lengthOf(ics.CalDateTime start, ics.CalDateTime? end) {
  if (start.isDate) {
    if (end == null) return (length: Duration.zero, days: 1);
    final hours = DateTime(end.year, end.month, end.day).difference(DateTime(start.year, start.month, start.day)).inHours;
    return (length: Duration.zero, days: ((hours + 12) ~/ 24).clamp(1, 3660));
  }
  final length = end == null || end.isDate ? Duration.zero : end.native.difference(start.native);
  // No end (RFC 5545: it takes no time): shown as half an hour.
  return (length: length > Duration.zero ? length : const Duration(minutes: 30), days: 0);
}

/// The time [s] starts, lasting as [end] says (or as [like] does).
EventTime _span(ics.CalDateTime s, ics.CalDateTime? end, ({Duration length, int days})? like) {
  final len = like ?? _lengthOf(s, end);
  if (s.isDate) {
    final d = DateTime(s.year, s.month, s.day);
    return (start: d, end: addDays(d, len.days));
  }
  final t = _utc(s);
  return (start: t, end: t.add(len.length));
}

/// [s] as a plain DateTime in UTC: a time with a TZID comes as the time
/// zone package's TZDateTime, whose toLocal() is the package's own "local"
/// (UTC unless set), not the tablet's.
DateTime _utc(ics.CalDateTime s) => DateTime.fromMicrosecondsSinceEpoch(s.native.microsecondsSinceEpoch, isUtc: true);

bool _overlaps(EventTime t, DateTime from, DateTime to) => t.end.isAfter(from) && t.start.isBefore(to);

/// Two times are the same one: the same instant, or for days, the same day.
bool _same(ics.CalDateTime a, ics.CalDateTime b) {
  if (a.isDate || b.isDate) return a.year == b.year && a.month == b.month && a.day == b.day;
  return a.native.isAtSameMomentAs(b.native);
}

CalEvent _single(ics.EventComponent e, String calendarId, String id, EventTime t) =>
    CalEvent(id: id, calendarId: calendarId, title: _title(e), start: t.start, end: t.end, allDay: e.dtstart!.isDate);

/// Event [m] with its times from [from] to [to]: one event, and one more
/// for each time moved and renamed.
List<CalEvent> _events(
  ics.EventComponent m,
  List<_Moved> moves,
  String calendarId,
  String id,
  String Function(String key) idFor,
  DateTime from,
  DateTime to,
) {
  if (_cancelled(m)) return const [];
  final start = m.dtstart!, allDay = start.isDate, title = _title(m);
  final length = _lengthOf(start, m.effectiveEnd);
  var starts = <ics.CalDateTime>[start];
  if (m.isRecurring) {
    // Excluded times (EXDATE) are matched here, by instant or day, so one
    // written in UTC still takes off a time written in its zone.
    starts = ics.RecurrenceIterator(
      dtstart: start,
      rrule: m.rrule,
      rdates: m.rdates,
      maxIterations: ics.RecurrenceIterator.absoluteMaxIterations,
    ).occurrences(start: _cal(from), end: _cal(to), duration: m.effectiveDuration).toList();
    final ex = m.exdates;
    if (ex.isNotEmpty) starts.removeWhere((s) => ex.any((x) => _same(s, x)));
  }
  final extra = <CalEvent>[];
  for (final o in moves) {
    starts.removeWhere((s) => _same(s, o.at));
    if (_cancelled(o.event)) continue;
    final os = o.event.dtstart!;
    // A moved time without its own end lasts as the others do.
    final end = o.event.effectiveEnd;
    final t = _span(os, end, end == null && os.isDate == allDay ? length : null);
    if (!_overlaps(t, from, to)) continue;
    if (_title(o.event) == title && os.isDate == allDay) {
      starts.add(os);
    } else {
      extra.add(_single(o.event, calendarId, idFor('${m.uid}|${o.at}'), t));
    }
  }
  final times = [
    for (final s in starts)
      if (_span(s, null, length) case final t when _overlaps(t, from, to)) t,
  ]..sort((a, b) => a.start.compareTo(b.start));
  if (times.isEmpty) return extra;
  return [
    CalEvent(
      id: id,
      calendarId: calendarId,
      title: title,
      start: times.first.start,
      end: times.first.end,
      allDay: allDay,
      times: m.isRecurring || times.length > 1 ? times : null,
    ),
    ...extra,
  ];
}

ics.CalDateTime _cal(DateTime t) {
  final u = t.toUtc();
  return ics.CalDateTime.utc(u.year, u.month, u.day, u.hour, u.minute, u.second);
}

final _tzidParam = RegExp(r'(;TZID=)("?)([^";:\r\n]+)("?)');
final _tzidLine = RegExp(r'^(TZID:)([^\r\n]+)', multiLine: true);
final _fold = RegExp(r'\r?\n[ \t]');

/// [text] with Outlook's Windows time zone names ("Central Standard Time")
/// changed to the database's ("America/Chicago"). Lines are unfolded first,
/// so a name split over two lines is found.
String withIanaZones(String text) {
  if (!text.contains('TZID')) return text;
  return text
      .replaceAll(_fold, '')
      .replaceAllMapped(_tzidParam, (m) {
        final z = windowsZones[m[3]!.trim()];
        return z == null ? m[0]! : '${m[1]}$z';
      })
      .replaceAllMapped(_tzidLine, (m) {
        final z = windowsZones[m[2]!.trim()];
        return z == null ? m[0]! : '${m[1]}$z';
      });
}
