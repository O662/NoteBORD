import 'package:flutter/foundation.dart' show immutable, setEquals;

import '../board/model.dart' show Json;

// The calendar (Calendar.png): calendars and their events, kept in the
// app's calendar.json. A calendar is on this tablet, or one of a Google or
// Outlook account's (Phase 7c sync); "Note deadlines" is made from dates
// written in notes and is never stored. Times are instants in UTC; an
// all-day event is a run of days, the same days in every time zone.

/// A day, as local midnight.
DateTime dayOf(DateTime t) {
  final l = t.isUtc ? t.toLocal() : t;
  return DateTime(l.year, l.month, l.day);
}

/// [day] plus [n] days (calendar days, not 24 hours: daylight saving moves
/// midnight by an hour).
DateTime addDays(DateTime day, int n) => DateTime(day.year, day.month, day.day + n);

/// "2026-09-25".
String dayKey(DateTime day) => '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

DateTime? parseDay(Object? key) {
  if (key is! String) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(key);
  return m == null ? null : DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

/// The Monday of [day]'s week.
DateTime weekStart(DateTime day) => addDays(dayOf(day), -(day.weekday - 1));

/// Where a calendar comes from.
enum CalendarKind {
  /// Kept on this tablet only.
  local,
  google,
  outlook,

  /// Dates written in notes ("Problem set 4 due Sun"); made, not stored.
  deadlines,
}

/// A calendar's color (Calendar.dc.html's blue, green, clay and plum).
enum CalendarHue { blue, green, clay, plum }

@immutable
class CalendarInfo {
  const CalendarInfo({
    required this.id,
    required this.name,
    this.kind = CalendarKind.local,
    this.hue = CalendarHue.blue,
    this.account,
    this.remoteId,
    this.shown = true,
    this.extra = const {},
  });

  static const deadlinesId = 'deadlines';

  static CalendarInfo? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String) return null;
    return CalendarInfo(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      kind: CalendarKind.values.where((k) => k.name == json['kind']).firstOrNull ?? CalendarKind.local,
      hue: CalendarHue.values.where((h) => h.name == json['hue']).firstOrNull ?? CalendarHue.blue,
      account: json['account'] as String?,
      remoteId: json['remoteId'] as String?,
      shown: json['shown'] != false,
      extra: {
        for (final e in json.entries)
          if (!const {'id', 'name', 'kind', 'hue', 'account', 'remoteId', 'shown'}.contains(e.key)) e.key as String: e.value,
      },
    );
  }

  final String id;
  final String name;
  final CalendarKind kind;
  final CalendarHue hue;

  /// The account it syncs with (an email address), for Google and Outlook.
  final String? account;

  /// Its id at Google or Microsoft.
  final String? remoteId;

  /// Toggled with its chip.
  final bool shown;
  final Json extra;

  /// The chip's second word ("Google").
  String get source => switch (kind) {
    CalendarKind.local => 'This tablet',
    CalendarKind.google => 'Google',
    CalendarKind.outlook => 'Outlook',
    CalendarKind.deadlines => '',
  };

  /// "School · Google Calendar" (the event panel's first line).
  String get fullName => switch (kind) {
    CalendarKind.local => '$name · This tablet',
    CalendarKind.google => '$name · Google Calendar',
    CalendarKind.outlook => '$name · Outlook',
    CalendarKind.deadlines => name,
  };

  /// Where its changes go ("Changes here also update Google Calendar.").
  String get updates => switch (kind) {
    CalendarKind.google => 'Google Calendar',
    CalendarKind.outlook => 'Outlook',
    _ => '',
  };

  /// Events can be added and changed here.
  bool get editable => kind != CalendarKind.deadlines;

  bool get synced => kind == CalendarKind.google || kind == CalendarKind.outlook;

  CalendarInfo copyWith({String? name, CalendarHue? hue, bool? shown}) => CalendarInfo(
    id: id,
    name: name ?? this.name,
    kind: kind,
    hue: hue ?? this.hue,
    account: account,
    remoteId: remoteId,
    shown: shown ?? this.shown,
    extra: extra,
  );

  Json toJson() => {
    ...extra,
    'id': id,
    'name': name,
    'kind': kind.name,
    'hue': hue.name,
    if (account != null) 'account': account,
    if (remoteId != null) 'remoteId': remoteId,
    'shown': shown,
  };
}

/// How an event repeats.
enum RepeatEvery { day, weekdays, week }

@immutable
class Repeat {
  const Repeat(this.every, {this.until, this.skip = const {}});

  static Repeat? fromJson(Object? json) {
    if (json is! Map) return null;
    final every = RepeatEvery.values.where((e) => e.name == json['every']).firstOrNull;
    if (every == null) return null;
    return Repeat(
      every,
      until: parseDay(json['until']),
      skip: {
        for (final s in (json['skip'] as List?) ?? const [])
          if (s is String) s,
      },
    );
  }

  final RepeatEvery every;

  /// The last day it happens on (inclusive), or null for no end.
  final DateTime? until;

  /// Days it doesn't happen on ([dayKey]s): occurrences deleted one by one.
  final Set<String> skip;

  bool on(DateTime day, DateTime first) => switch (every) {
    RepeatEvery.day => true,
    RepeatEvery.weekdays => day.weekday <= DateTime.friday,
    RepeatEvery.week => day.weekday == first.weekday,
  };

  Repeat copyWith({DateTime? Function()? until, Set<String>? skip}) =>
      Repeat(every, until: until == null ? this.until : until(), skip: skip ?? this.skip);

  @override
  bool operator ==(Object other) => other is Repeat && other.every == every && other.until == until && setEquals(other.skip, skip);

  @override
  int get hashCode => Object.hash(every, until, skip.length);

  Json toJson() => {
    'every': every.name,
    if (until != null) 'until': dayKey(until!),
    if (skip.isNotEmpty) 'skip': [...skip]..sort(),
  };
}

/// Notes for an event ("Open notes"): a notebook, at a page.
@immutable
class NoteLink {
  const NoteLink(this.notebookId, {this.pageId});

  static NoteLink? fromJson(Object? json) =>
      json is Map && json['notebook'] is String ? NoteLink(json['notebook'] as String, pageId: json['page'] as String?) : null;

  final String notebookId;
  final String? pageId;

  @override
  bool operator ==(Object other) => other is NoteLink && other.notebookId == notebookId && other.pageId == pageId;

  @override
  int get hashCode => Object.hash(notebookId, pageId);

  Json toJson() => {'notebook': notebookId, if (pageId != null) 'page': pageId};
}

@immutable
class CalEvent {
  const CalEvent({
    required this.id,
    required this.calendarId,
    required this.title,
    required this.start,
    required this.end,
    this.allDay = false,
    this.repeat,
    this.notes,
    this.remoteId,
    this.etag,
    this.updatedAt,
    this.pending = false,
    this.deleted = false,
    this.extra = const {},
  });

  static const _known = {
    'id', 'calendar', 'title', 'start', 'end', 'startDate', 'endDate', 'allDay', 'repeat', 'notes', //
    'remoteId', 'etag', 'updatedAt', 'pending', 'deleted',
  };

  static CalEvent? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String || json['calendar'] is! String) return null;
    final allDay = json['allDay'] == true;
    final DateTime? start, end;
    if (allDay) {
      start = parseDay(json['startDate']);
      end = parseDay(json['endDate']) ?? (start == null ? null : addDays(start, 1));
    } else {
      start = DateTime.tryParse(json['start'] as String? ?? '')?.toUtc();
      end = DateTime.tryParse(json['end'] as String? ?? '')?.toUtc() ?? start?.add(const Duration(hours: 1));
    }
    if (start == null || end == null) return null;
    return CalEvent(
      id: json['id'] as String,
      calendarId: json['calendar'] as String,
      title: json['title'] as String? ?? '',
      start: start,
      end: end.isAfter(start) ? end : (allDay ? addDays(start, 1) : start.add(const Duration(minutes: 30))),
      allDay: allDay,
      repeat: Repeat.fromJson(json['repeat']),
      notes: NoteLink.fromJson(json['notes']),
      remoteId: json['remoteId'] as String?,
      etag: json['etag'] as String?,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
      pending: json['pending'] == true,
      deleted: json['deleted'] == true,
      extra: {
        for (final e in json.entries)
          if (!_known.contains(e.key)) e.key as String: e.value,
      },
    );
  }

  final String id;
  final String calendarId;
  final String title;

  /// For a timed event, instants in UTC. For an all-day one, local
  /// midnights: the first day, and the day after the last ([end] is
  /// exclusive).
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final Repeat? repeat;
  final NoteLink? notes;

  /// Its id and version at Google or Microsoft (sync).
  final String? remoteId;
  final String? etag;
  final DateTime? updatedAt;

  /// Changed here and not sent yet (sync).
  final bool pending;

  /// Deleted here; kept until the deletion is sent (sync).
  final bool deleted;
  final Json extra;

  Duration get length => end.difference(start);

  /// What [start] says as a local time (all-day events: the day).
  DateTime get localStart => allDay ? start : start.toLocal();
  DateTime get localEnd => allDay ? end : end.toLocal();

  /// Every time it happens that overlaps [from]–[to) (local times).
  Iterable<Occurrence> occurrences(DateTime from, DateTime to) sync* {
    if (deleted) return;
    final first = localStart, len = localEnd.difference(localStart);
    final r = repeat;
    if (r == null) {
      if (first.isBefore(to) && localEnd.isAfter(from)) yield Occurrence(this, first, localEnd);
      return;
    }
    // Days that could start an occurrence reaching into [from, to).
    final lengthDays = len.inHours ~/ 24 + 1;
    var day = dayOf(first);
    final earliest = addDays(dayOf(from), -lengthDays);
    if (day.isBefore(earliest)) day = earliest;
    final last = r.until == null || dayOf(to).isBefore(r.until!) ? dayOf(to) : r.until!;
    for (; !day.isAfter(last); day = addDays(day, 1)) {
      if (day.isBefore(dayOf(first)) || !r.on(day, first) || r.skip.contains(dayKey(day))) continue;
      final s = DateTime(day.year, day.month, day.day, first.hour, first.minute);
      final e = allDay ? addDays(s, len.inDays) : s.add(len);
      if (s.isBefore(to) && e.isAfter(from)) yield Occurrence(this, s, e);
    }
  }

  CalEvent copyWith({
    String? id,
    String? calendarId,
    String? title,
    DateTime? start,
    DateTime? end,
    bool? allDay,
    Repeat? Function()? repeat,
    NoteLink? Function()? notes,
    String? Function()? remoteId,
    String? Function()? etag,
    DateTime? updatedAt,
    bool? pending,
    bool? deleted,
  }) => CalEvent(
    id: id ?? this.id,
    calendarId: calendarId ?? this.calendarId,
    title: title ?? this.title,
    start: start ?? this.start,
    end: end ?? this.end,
    allDay: allDay ?? this.allDay,
    repeat: repeat == null ? this.repeat : repeat(),
    notes: notes == null ? this.notes : notes(),
    remoteId: remoteId == null ? this.remoteId : remoteId(),
    etag: etag == null ? this.etag : etag(),
    updatedAt: updatedAt ?? this.updatedAt,
    pending: pending ?? this.pending,
    deleted: deleted ?? this.deleted,
    extra: extra,
  );

  Json toJson() => {
    ...extra,
    'id': id,
    'calendar': calendarId,
    'title': title,
    if (allDay) ...{
      'allDay': true,
      'startDate': dayKey(start),
      'endDate': dayKey(end),
    } else ...{
      'start': start.toUtc().toIso8601String(),
      'end': end.toUtc().toIso8601String(),
    },
    if (repeat != null) 'repeat': repeat!.toJson(),
    if (notes != null) 'notes': notes!.toJson(),
    if (remoteId != null) 'remoteId': remoteId,
    if (etag != null) 'etag': etag,
    if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
    if (pending) 'pending': true,
    if (deleted) 'deleted': true,
  };
}

/// One time an event happens, in local time.
@immutable
class Occurrence {
  const Occurrence(this.event, this.start, this.end);

  final CalEvent event;
  final DateTime start;
  final DateTime end;

  bool get allDay => event.allDay;

  /// Spans more than one day without being all-day: shown in the all-day row.
  bool get long => !allDay && end.difference(start) >= const Duration(hours: 24);

  /// This occurrence, the same everywhere (an event id and its day).
  String get key => '${event.id}@${dayKey(dayOf(start))}';

  @override
  bool operator ==(Object other) => other is Occurrence && other.event.id == event.id && other.start == start;

  @override
  int get hashCode => Object.hash(event.id, start);
}

/// Everything in calendar.json.
@immutable
class CalendarData {
  const CalendarData({this.calendars = const [], this.events = const [], this.extra = const {}});

  static CalendarData fromJson(Json? json) => CalendarData(
    calendars: [for (final c in (json?['calendars'] as List?) ?? const []) ?CalendarInfo.fromJson(c)],
    events: [for (final e in (json?['events'] as List?) ?? const []) ?CalEvent.fromJson(e)],
    extra: {
      for (final e in (json ?? const {}).entries)
        if (!const {'version', 'calendars', 'events'}.contains(e.key)) e.key: e.value,
    },
  );

  final List<CalendarInfo> calendars;
  final List<CalEvent> events;
  final Json extra;

  CalendarInfo? calendar(String id) => calendars.where((c) => c.id == id).firstOrNull;
  CalEvent? event(String id) => events.where((e) => e.id == id && !e.deleted).firstOrNull;

  CalendarData copyWith({List<CalendarInfo>? calendars, List<CalEvent>? events}) =>
      CalendarData(calendars: calendars ?? this.calendars, events: events ?? this.events, extra: extra);

  Json toJson() => {
    ...extra,
    'version': 1,
    'calendars': [for (final c in calendars) c.toJson()],
    'events': [for (final e in events) e.toJson()],
  };
}
