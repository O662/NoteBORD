import 'package:endless/calendar/calendar_model.dart';
import 'package:endless/calendar/remote.dart';
import 'package:endless/sync/cloud.dart';

/// An event in [FakeRemote].
class FakeEvent {
  FakeEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.updated,
    this.allDay = false,
    this.repeat,
    this.everyDays,
  });

  final String id;
  String title;
  DateTime start, end;
  bool allDay;
  Repeat? repeat;

  /// A repeat Endless can't show as its own: every this many days.
  int? everyDays;
  DateTime updated;
  int version = 1;

  /// Times taken off, by day.
  final cancelled = <String>{};

  String get etag => '"$id.$version"';
  bool get repeats => repeat != null || everyDays != null;
}

/// Google Calendar or Outlook, in memory: etags that change with each
/// change (412 when stale), times taken off a repeating event, and its
/// times worked out as Google and Microsoft would.
class FakeRemote implements CalendarRemote {
  final calendarsThere = <RemoteCalendar>[];
  final events = <String, Map<String, FakeEvent>>{};
  final log = <String>[];

  /// The time there (for `updated`).
  DateTime now = DateTime.utc(2026, 9, 25, 15);
  CloudException? failWith;
  int _n = 0;

  void addCalendar(String id, String name, {bool canEdit = true, bool primary = false, bool shown = true}) {
    calendarsThere.add(RemoteCalendar(id: id, name: name, canEdit: canEdit, primary: primary, shown: shown));
    events[id] = {};
  }

  FakeEvent add(String cal, String title, DateTime start, DateTime end, {bool allDay = false, Repeat? repeat, int? everyDays, String? id}) {
    final f = FakeEvent(
      id: id ?? 'r${++_n}',
      title: title,
      start: allDay ? start : start.toUtc(),
      end: allDay ? end : end.toUtc(),
      allDay: allDay,
      repeat: repeat,
      everyDays: everyDays,
      updated: now,
    );
    events[cal]![f.id] = f;
    return f;
  }

  FakeEvent? find(String title) {
    for (final cal in events.values) {
      for (final f in cal.values) {
        if (f.title == title) return f;
      }
    }
    return null;
  }

  /// Changes [f] there (as someone in Google Calendar would).
  void change(FakeEvent f, void Function(FakeEvent) how) {
    how(f);
    f.version++;
    f.updated = now;
  }

  void _check() {
    if (failWith case final e?) throw e;
  }

  RemoteItem _item(FakeEvent f, {List<EventTime>? times, Map<String, String> instances = const {}}) => RemoteItem(
    id: f.id,
    etag: f.etag,
    title: f.title,
    start: f.start,
    end: f.end,
    allDay: f.allDay,
    repeat: f.repeat,
    rule: f.everyDays != null ? ['RRULE:FREQ=DAILY;INTERVAL=${f.everyDays}'] : (f.repeat != null ? const ['RRULE:FREQ=WEEKLY'] : null),
    times: times,
    instances: instances,
    updated: f.updated,
  );

  @override
  Future<List<RemoteCalendar>> calendars() async {
    _check();
    log.add('calendars');
    return [...calendarsThere];
  }

  @override
  Future<List<RemoteItem>> read(String calendarId, DateTime from, DateTime to) async {
    _check();
    final cal = events[calendarId];
    if (cal == null) throw const RemoteGone();
    log.add('read $calendarId');
    final out = <RemoteItem>[];
    for (final f in cal.values) {
      if (!f.repeats) {
        if (f.start.isBefore(to) && f.end.isAfter(from)) out.add(_item(f));
        continue;
      }
      final times = <EventTime>[];
      final ids = <String, String>{};
      void time(DateTime s, DateTime e) {
        final day = dayKey(f.allDay ? s : dayOf(s));
        if (f.cancelled.contains(day)) return;
        times.add((start: s, end: e));
        ids[day] = '${f.id}_$day';
      }

      if (f.everyDays case final n?) {
        for (var s = f.start, e = f.end; s.isBefore(to); s = s.add(Duration(days: n)), e = e.add(Duration(days: n))) {
          if (e.isAfter(from)) time(s, e);
        }
      } else {
        final probe = CalEvent(id: f.id, calendarId: calendarId, title: f.title, start: f.start, end: f.end, allDay: f.allDay, repeat: f.repeat);
        for (final o in probe.occurrences(from.toLocal(), to.toLocal())) {
          time(f.allDay ? o.start : o.start.toUtc(), f.allDay ? o.end : o.end.toUtc());
        }
      }
      out.add(_item(f, times: times, instances: ids));
    }
    return out;
  }

  @override
  Future<RemoteItem?> get(String calendarId, String id) async {
    _check();
    final f = events[calendarId]?[id];
    return f == null ? null : _item(f);
  }

  @override
  Future<RemoteItem> create(String calendarId, CalEvent e) async {
    _check();
    log.add('create ${e.title}');
    final f = add(calendarId, e.title, e.start, e.end, allDay: e.allDay, repeat: e.repeat);
    if (e.repeat == null && e.rule != null) f.everyDays = 14;
    return _item(f);
  }

  @override
  Future<RemoteItem> update(String calendarId, String id, String? etag, CalEvent e, {required bool title, required bool when, required bool rule}) async {
    _check();
    final f = events[calendarId]?[id];
    if (f == null) throw const RemoteGone();
    if (etag != null && etag != f.etag) throw const RemoteConflict();
    log.add('update ${f.id}${title ? ' title' : ''}${when ? ' when' : ''}${rule ? ' rule' : ''}');
    change(f, (f) {
      if (title) f.title = e.title;
      if (when || rule) {
        f.start = e.start;
        f.end = e.end;
        f.allDay = e.allDay;
      }
      if (rule) {
        f.repeat = e.repeat;
        if (e.repeat != null || e.rule == null) f.everyDays = null;
      }
    });
    return _item(f);
  }

  @override
  Future<void> delete(String calendarId, String id, {String? etag}) async {
    _check();
    final cal = events[calendarId]!;
    final under = id.indexOf('_');
    final master = under > 0 ? cal[id.substring(0, under)] : null;
    if (master != null) {
      log.add('cancel $id');
      master.cancelled.add(id.substring(under + 1));
      return;
    }
    final f = cal[id];
    if (f == null) return;
    if (etag != null && etag != f.etag) throw const RemoteConflict();
    log.add('delete ${f.title}');
    cal.remove(id);
  }

  @override
  Future<String?> instanceOn(String calendarId, String seriesId, DateTime from, DateTime to) async {
    _check();
    return '${seriesId}_${dayKey(dayOf(from))}';
  }
}
