import 'package:flutter/foundation.dart' show immutable, setEquals;

import '../board/model.dart' show Json;

// The calendar (Calendar.png): calendars and their events, kept in the
// app's calendar.json. A calendar is on this tablet, read from a calendar
// link (an .ics address from Google Calendar or Outlook, view only), or one
// of a Google or Outlook account's (two-way sync, Phase 9c); "Note
// deadlines" is made from dates written in notes and is never stored. Times
// are instants in UTC; an all-day event is a run of days, the same days in
// every time zone.

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

  /// Read from a calendar link (.ics); view only. Its events aren't kept in
  /// calendar.json but read again from the copy of the link's file.
  feed,

  /// Dates written in notes ("Problem set 4 due Sun"); made, not stored.
  deadlines,
}

/// Where a calendar link comes from.
enum FeedFrom { google, outlook, web }

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
    this.from,
    this.fetchedAt,
    this.error,
    this.readOnly = false,
    this.extra = const {},
  });

  static const deadlinesId = 'deadlines';

  static const _known = {'id', 'name', 'kind', 'hue', 'account', 'remoteId', 'shown', 'from', 'fetchedAt', 'error', 'readOnly'};

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
      from: FeedFrom.values.where((f) => f.name == json['from']).firstOrNull,
      fetchedAt: DateTime.tryParse(json['fetchedAt'] as String? ?? '')?.toUtc(),
      error: json['error'] as String?,
      readOnly: json['readOnly'] == true,
      extra: {
        for (final e in json.entries)
          if (!_known.contains(e.key)) e.key as String: e.value,
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

  /// A calendar link's: where it's from, when it was last read, and why the
  /// last try didn't work (null when it did). The link itself is kept in
  /// the platform's secure storage, not here: anyone with it can read the
  /// calendar.
  final FeedFrom? from;
  final DateTime? fetchedAt;
  final String? error;

  /// A Google or Outlook calendar the account can see but not change (a
  /// shared calendar, holidays): synced one way, from there.
  final bool readOnly;
  final Json extra;

  /// The chip's second word ("Google").
  String get source => switch (kind) {
    CalendarKind.local => 'This tablet',
    CalendarKind.google => 'Google',
    CalendarKind.outlook => 'Outlook',
    CalendarKind.feed => switch (from) {
      FeedFrom.google => 'Google',
      FeedFrom.outlook => 'Outlook',
      _ => 'Link',
    },
    CalendarKind.deadlines => '',
  };

  /// "School · Google Calendar" (the event panel's first line).
  String get fullName => switch (kind) {
    CalendarKind.local => '$name · This tablet',
    CalendarKind.google => '$name · Google Calendar',
    CalendarKind.outlook => '$name · Outlook',
    CalendarKind.feed => '$name · ${app ?? 'Calendar link'}',
    CalendarKind.deadlines => name,
  };

  /// The app a calendar link's events are changed in ("Google Calendar").
  String? get app => switch (from) {
    FeedFrom.google => 'Google Calendar',
    FeedFrom.outlook => 'Outlook',
    _ => null,
  };

  /// Where its changes go ("Changes here also update Google Calendar.").
  String get updates => switch (kind) {
    CalendarKind.google => 'Google Calendar',
    CalendarKind.outlook => 'Outlook',
    _ => '',
  };

  /// Events can be added and changed here.
  bool get editable => kind != CalendarKind.deadlines && kind != CalendarKind.feed && !readOnly;

  /// Its events can be given notes (Start notes).
  bool get linkable => kind != CalendarKind.deadlines;

  /// Read from a calendar link: shown, not changed.
  bool get viewOnly => kind == CalendarKind.feed;

  /// Synced with a Google or Outlook account (both ways, unless [readOnly]).
  bool get synced => kind == CalendarKind.google || kind == CalendarKind.outlook;

  CalendarInfo copyWith({String? name, CalendarHue? hue, bool? shown, DateTime? fetchedAt, String? Function()? error, bool? readOnly}) =>
      CalendarInfo(
        id: id,
        name: name ?? this.name,
        kind: kind,
        hue: hue ?? this.hue,
        account: account,
        remoteId: remoteId,
        shown: shown ?? this.shown,
        from: from,
        fetchedAt: fetchedAt ?? this.fetchedAt,
        error: error == null ? this.error : error(),
        readOnly: readOnly ?? this.readOnly,
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
    if (from != null) 'from': from!.name,
    if (fetchedAt != null) 'fetchedAt': fetchedAt!.toUtc().toIso8601String(),
    if (error != null) 'error': error,
    if (readOnly) 'readOnly': true,
  };
}

/// A Google or Outlook account whose calendars sync both ways (one of each
/// on a tablet). The sign-in itself is in the platform's secure storage.
@immutable
class CalendarAccount {
  const CalendarAccount({required this.kind, required this.email, this.name, this.syncedAt, this.error, this.signedOut = false, this.extra = const {}});

  static const _known = {'kind', 'email', 'name', 'syncedAt', 'error', 'signedOut'};

  static CalendarAccount? fromJson(Object? json) {
    if (json is! Map || json['email'] is! String) return null;
    final kind = CalendarKind.values.where((k) => k.name == json['kind']).firstOrNull;
    if (kind != CalendarKind.google && kind != CalendarKind.outlook) return null;
    return CalendarAccount(
      kind: kind!,
      email: json['email'] as String,
      name: json['name'] as String?,
      syncedAt: DateTime.tryParse(json['syncedAt'] as String? ?? '')?.toUtc(),
      error: json['error'] as String?,
      signedOut: json['signedOut'] == true,
      extra: {
        for (final e in json.entries)
          if (!_known.contains(e.key)) e.key as String: e.value,
      },
    );
  }

  /// [CalendarKind.google] or [CalendarKind.outlook].
  final CalendarKind kind;
  final String email;
  final String? name;

  /// When it last synced all the way.
  final DateTime? syncedAt;

  /// Why the last sync didn't finish (null when it did).
  final String? error;

  /// The sign-in ran out or was removed: sign in again.
  final bool signedOut;
  final Json extra;

  /// "Google" or "Outlook".
  String get label => kind == CalendarKind.google ? 'Google' : 'Outlook';

  /// "Google Calendar" or "Outlook".
  String get app => kind == CalendarKind.google ? 'Google Calendar' : 'Outlook';

  CalendarAccount copyWith({String? email, String? name, DateTime? syncedAt, String? Function()? error, bool? signedOut}) => CalendarAccount(
    kind: kind,
    email: email ?? this.email,
    name: name ?? this.name,
    syncedAt: syncedAt ?? this.syncedAt,
    error: error == null ? this.error : error(),
    signedOut: signedOut ?? this.signedOut,
    extra: extra,
  );

  Json toJson() => {
    ...extra,
    'kind': kind.name,
    'email': email,
    if (name != null) 'name': name,
    if (syncedAt != null) 'syncedAt': syncedAt!.toUtc().toIso8601String(),
    if (error != null) 'error': error,
    if (signedOut) 'signedOut': true,
  };
}

/// One time an event from a calendar link happens: instants in UTC, or for
/// an all-day event local midnights (the end exclusive), as [CalEvent]'s.
typedef EventTime = ({DateTime start, DateTime end});

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
    this.times,
    this.extra = const {},
  });

  static const _known = {
    'id', 'calendar', 'title', 'start', 'end', 'startDate', 'endDate', 'allDay', 'repeat', 'notes', //
    'remoteId', 'etag', 'updatedAt', 'pending', 'deleted', 'times',
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
      times: _timesFromJson(json['times'], allDay),
      extra: {
        for (final e in json.entries)
          if (!_known.contains(e.key)) e.key as String: e.value,
      },
    );
  }

  static List<EventTime>? _timesFromJson(Object? json, bool allDay) {
    if (json is! List) return null;
    DateTime? at(Object? v) => allDay ? parseDay(v) : DateTime.tryParse(v as String? ?? '')?.toUtc();
    return [
      for (final t in json)
        if (t is List && t.length == 2)
          if ((at(t[0]), at(t[1])) case (final s?, final e?)) (start: s, end: e),
    ];
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

  /// For an event from a calendar link, or a repeating event from Google or
  /// Outlook: every time it happens (repeats worked out there, with times
  /// moved or taken off), oldest first. A link's are never stored (it's
  /// read again); a synced event's are, so they show offline. For a link's
  /// event [start] and [end] are the first; for a synced one, the series'.
  final List<EventTime>? times;
  final Json extra;

  Duration get length => end.difference(start);

  /// It happens more than once (a repeat here, or times from a link).
  bool get repeats => repeat != null || (times?.length ?? 0) > 1;

  /// What [start] says as a local time (all-day events: the day).
  DateTime get localStart => allDay ? start : start.toLocal();
  DateTime get localEnd => allDay ? end : end.toLocal();

  /// Every time it happens that overlaps [from]–[to) (local times).
  Iterable<Occurrence> occurrences(DateTime from, DateTime to) sync* {
    if (deleted) return;
    if (times case final list?) {
      for (final t in list) {
        final s = allDay ? t.start : t.start.toLocal(), e = allDay ? t.end : t.end.toLocal();
        if (!s.isBefore(to)) break;
        if (e.isAfter(from)) yield Occurrence(this, s, e);
      }
      return;
    }
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
    List<EventTime>? Function()? times,
    Json? extra,
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
    times: times == null ? this.times : times(),
    extra: extra ?? this.extra,
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
    if (times case final ts?)
      'times': [
        for (final t in ts)
          allDay ? [dayKey(t.start), dayKey(t.end)] : [t.start.toUtc().toIso8601String(), t.end.toUtc().toIso8601String()],
      ],
  };
}

/// What sync keeps in a Google or Outlook event's [CalEvent.extra]:
/// - `base`: the event as Google or Microsoft last had it (title, times,
///   calendar, repeat), so only what changed here is sent, and a change
///   made there meanwhile is merged rather than overwritten;
/// - `rule`: a repeating event's rule as Google or Microsoft keep it
///   (RRULE lines, or Graph's recurrence), so a repeat Endless can't show
///   as its own ("every 2 weeks") is kept as it was;
/// - `instances`: each time's id there, by day, and `cancel`: days taken
///   off here, to take off there ("Just this one");
/// - `of`: for one time of a repeating event changed there (an exception),
///   the series' id;
/// - `restored`: put back with Undo after its deletion may have been sent.
extension SyncFields on CalEvent {
  Json? get base => extra['base'] is Map ? (extra['base'] as Map).cast<String, Object?>() : null;
  Object? get rule => extra['rule'];

  /// It repeats in a way Endless can't show as its own ("every 2 weeks"):
  /// the times come from Google or Outlook, and the rule is kept as it is.
  bool get customRepeat => repeat == null && rule != null;

  Map<String, String> get instances => {
    for (final e in ((extra['instances'] as Map?) ?? const {}).entries)
      if (e.key is String && e.value is String) e.key as String: e.value as String,
  };

  List<String> get cancel => [
    for (final d in (extra['cancel'] as List?) ?? const [])
      if (d is String) d,
  ];

  /// For one time of a repeating event changed in Google or Outlook: the
  /// series' id there.
  String? get seriesOf => extra['of'] as String?;
  bool get restored => extra['restored'] == true;

  /// "none", "custom", or the repeat ("week·2026-12-18").
  String get ruleKey => repeat != null ? '${repeat!.every.name}·${repeat!.until == null ? '' : dayKey(repeat!.until!)}' : (rule != null ? 'custom' : 'none');

  /// [extra] with [changes] (null removes a key).
  CalEvent withExtra(Map<String, Object?> changes) {
    final x = {...extra};
    for (final c in changes.entries) {
      if (c.value == null) {
        x.remove(c.key);
      } else {
        x[c.key] = c.value;
      }
    }
    return copyWith(extra: x);
  }
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
  const CalendarData({this.calendars = const [], this.events = const [], this.links = const {}, this.accounts = const [], this.extra = const {}});

  static CalendarData fromJson(Json? json) {
    final data = CalendarData(
      calendars: [for (final c in (json?['calendars'] as List?) ?? const []) ?CalendarInfo.fromJson(c)],
      events: [for (final e in (json?['events'] as List?) ?? const []) ?CalEvent.fromJson(e)],
      links: {
        for (final e in ((json?['links'] as Map?) ?? const {}).entries)
          if (e.key is String) e.key as String: ?NoteLink.fromJson(e.value),
      },
      accounts: [for (final a in (json?['accounts'] as List?) ?? const []) ?CalendarAccount.fromJson(a)],
      extra: {
        for (final e in (json ?? const {}).entries)
          if (!const {'version', 'calendars', 'events', 'links', 'accounts'}.contains(e.key)) e.key: e.value,
      },
    );
    // A calendar link's events come from its file, not from here.
    final feeds = data._feedIds;
    return feeds.isEmpty ? data : data.copyWith(events: [for (final e in data.events) if (!feeds.contains(e.calendarId)) e]);
  }

  final List<CalendarInfo> calendars;

  /// Every event, including those read from calendar links (which aren't
  /// stored: they're read again from the link's file at start).
  final List<CalEvent> events;

  /// Notes for events from calendar links, by event id: their events are
  /// read again from the link, so the links to their notes are kept here.
  final Map<String, NoteLink> links;

  /// Google and Outlook accounts connected for two-way sync.
  final List<CalendarAccount> accounts;
  final Json extra;

  Set<String> get _feedIds => {
    for (final c in calendars)
      if (c.viewOnly) c.id,
  };

  CalendarInfo? calendar(String id) => calendars.where((c) => c.id == id).firstOrNull;
  CalEvent? event(String id) => events.where((e) => e.id == id && !e.deleted).firstOrNull;
  CalendarAccount? account(CalendarKind kind) => accounts.where((a) => a.kind == kind).firstOrNull;

  CalendarData copyWith({List<CalendarInfo>? calendars, List<CalEvent>? events, Map<String, NoteLink>? links, List<CalendarAccount>? accounts}) =>
      CalendarData(
        calendars: calendars ?? this.calendars,
        events: events ?? this.events,
        links: links ?? this.links,
        accounts: accounts ?? this.accounts,
        extra: extra,
      );

  Json toJson() {
    final feeds = _feedIds;
    return {
      ...extra,
      'version': 1,
      'calendars': [for (final c in calendars) c.toJson()],
      'events': [
        for (final e in events)
          if (!feeds.contains(e.calendarId)) e.toJson(),
      ],
      if (links.isNotEmpty) 'links': {for (final e in links.entries) e.key: e.value.toJson()},
      if (accounts.isNotEmpty) 'accounts': [for (final a in accounts) a.toJson()],
    };
  }
}
