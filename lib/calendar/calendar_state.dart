import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/ids.dart';
import '../library/library.dart';
import '../recognition/handwriting_index.dart';
import '../state/diag.dart';
import '../state/notebook.dart' show writeQueueProvider;
import '../state/settings.dart' show boardStoreProvider;
import 'calendar_model.dart';
import 'deadlines.dart';

// The calendars and their events (calendar.json), and the deadlines read
// from notes. Every change is saved at once. Events in Google and Outlook
// calendars are marked `pending` when changed here, for calendar sync
// (calendar_sync.dart) to send.

/// A new tablet starts with one calendar of its own and the note deadlines.
const defaultCalendars = [
  CalendarInfo(id: 'local', name: 'Calendar'),
  CalendarInfo(id: CalendarInfo.deadlinesId, name: 'Note deadlines', kind: CalendarKind.deadlines, hue: CalendarHue.plum),
];

/// [data] with the deadlines calendar, and a calendar of the tablet's own if
/// there's none to add events to.
CalendarData withDefaults(CalendarData data) {
  final calendars = [...data.calendars];
  if (!calendars.any((c) => c.editable)) calendars.insert(0, defaultCalendars.first);
  if (!calendars.any((c) => c.kind == CalendarKind.deadlines)) calendars.add(defaultCalendars.last);
  return data.copyWith(calendars: calendars);
}

/// The next color no calendar in [data] has yet (they repeat once all are
/// used).
CalendarHue nextHueOf(CalendarData data) {
  final used = {for (final cal in data.calendars) cal.hue};
  return CalendarHue.values.where((h) => !used.contains(h)).firstOrNull ?? CalendarHue.values[used.length % CalendarHue.values.length];
}

/// [data] with calendar [c] added (before the note deadlines).
CalendarData withCalendar(CalendarData data, CalendarInfo c) => data.copyWith(
  calendars: [
    ...data.calendars.where((x) => x.kind != CalendarKind.deadlines),
    c,
    ...data.calendars.where((x) => x.kind == CalendarKind.deadlines),
  ],
);

/// A synced repeating event's times after it changed from [old] to [e]:
/// moved to its new time of day and length when only those changed; null
/// (worked out from its repeat until Google or Outlook gives them again)
/// when its days or repeat changed.
List<EventTime>? movedTimes(CalEvent old, CalEvent e) {
  final times = old.times;
  if (times == null || e.allDay != old.allDay || e.ruleKey != old.ruleKey || (e.repeat == null && !e.customRepeat)) return null;
  if (dayOf(e.localStart) != dayOf(old.localStart)) return null;
  final sameTime = e.allDay
      ? e.length.inDays == old.length.inDays
      : e.localStart.hour == old.localStart.hour && e.localStart.minute == old.localStart.minute && e.length == old.length;
  if (sameTime) return times;
  return [
    for (final t in times)
      if (e.allDay)
        (start: t.start, end: addDays(t.start, e.length.inDays))
      else
        () {
          final d = dayOf(t.start);
          final s = DateTime(d.year, d.month, d.day, e.localStart.hour, e.localStart.minute).toUtc();
          return (start: s, end: s.add(e.length));
        }(),
  ];
}

/// calendar.json as the app started (bootstrap loads it).
final initialCalendarProvider = Provider<CalendarData>((ref) => const CalendarData());

final calendarProvider = NotifierProvider<Calendars, CalendarData>(Calendars.new);

class Calendars extends Notifier<CalendarData> {
  @override
  CalendarData build() => withDefaults(ref.read(initialCalendarProvider));

  DateTime get _now => ref.read(clockProvider)().toUtc();

  /// Where new events go: the first calendar shown that can take them.
  CalendarInfo get defaultCalendar =>
      state.calendars.where((c) => c.editable && c.shown).firstOrNull ?? state.calendars.firstWhere((c) => c.editable);

  CalEvent newEvent({required String title, required DateTime start, required DateTime end, bool allDay = false, String? calendarId}) => CalEvent(
    id: newId('ev', now: _now),
    calendarId: calendarId ?? defaultCalendar.id,
    title: title,
    start: allDay ? dayOf(start) : start.toUtc(),
    end: allDay ? dayOf(end) : end.toUtc(),
    allDay: allDay,
  );

  bool _synced(String calendarId) => state.calendar(calendarId)?.synced ?? false;
  bool _viewOnly(String calendarId) => state.calendar(calendarId)?.viewOnly ?? false;
  bool _readOnly(String calendarId) => state.calendar(calendarId)?.readOnly ?? false;

  /// Adds [e], or changes the event with its id. For an event from a
  /// calendar link, only its notes change (Start notes): it's read again
  /// from the link, so its notes are kept apart, in [CalendarData.links].
  /// So too for a calendar that Google or Outlook won't let this account
  /// change. A change to a Google or Outlook event is marked to send.
  void put(CalEvent e) {
    if (_readOnly(e.calendarId)) {
      final i = state.events.indexWhere((x) => x.id == e.id);
      if (i >= 0) _set(state.copyWith(events: [...state.events]..[i] = state.events[i].copyWith(notes: () => e.notes)));
      return;
    }
    if (_viewOnly(e.calendarId)) {
      final i = state.events.indexWhere((x) => x.id == e.id);
      if (i < 0) return;
      final links = {...state.links};
      if (e.notes case final n?) {
        links[e.id] = n;
      } else {
        links.remove(e.id);
      }
      _set(state.copyWith(events: [...state.events]..[i] = state.events[i].copyWith(notes: () => e.notes), links: links));
      return;
    }
    final i = state.events.indexWhere((x) => x.id == e.id);
    final old = i < 0 ? null : state.events[i];
    final syncs = _synced(e.calendarId) || e.remoteId != null;
    var x = e;
    if (old != null && old.times != null && identical(e.times, old.times)) x = x.copyWith(times: () => movedTimes(old, e));
    final stamped = x.copyWith(updatedAt: _now, pending: syncs || e.pending);
    _set(state.copyWith(events: i < 0 ? [...state.events, stamped] : ([...state.events]..[i] = stamped)));
  }

  /// Deletes event [id] (every time it happens). Synced ones are kept as
  /// deleted until sync has told Google or Microsoft.
  void delete(String id) {
    final e = state.event(id);
    if (e == null || _viewOnly(e.calendarId)) return;
    _set(
      state.copyWith(
        events: [
          for (final x in state.events)
            if (x.id != id) x else if (x.remoteId != null) x.copyWith(deleted: true, pending: true, updatedAt: _now),
        ],
      ),
    );
  }

  /// Takes one time a repeating event happens off the calendar. For a
  /// Google or Outlook event, that time is taken off there too.
  void skip(Occurrence o) {
    final e = state.events.where((x) => x.id == o.event.id).firstOrNull ?? o.event;
    final day = dayKey(dayOf(o.start));
    final r = e.repeat;
    if (_synced(e.calendarId) || e.remoteId != null) {
      if (_readOnly(e.calendarId)) return;
      if (e.times == null && r == null) return delete(e.id);
      var x = e.withExtra({
        'cancel': [...{...e.cancel, day}],
      });
      if (e.times case final ts?) {
        x = x.copyWith(times: () => [for (final t in ts) if (dayKey(e.allDay ? t.start : dayOf(t.start)) != day) t]);
      } else {
        x = x.copyWith(repeat: () => r!.copyWith(skip: {...r.skip, day}));
      }
      final i = state.events.indexWhere((y) => y.id == e.id);
      _set(state.copyWith(events: [...state.events]..[i] = x.copyWith(updatedAt: _now, pending: true)));
      return;
    }
    if (r == null) return delete(e.id);
    put(e.copyWith(repeat: () => r.copyWith(skip: {...r.skip, day})));
  }

  /// Puts back an event deleted a moment ago (Undo). A Google or Outlook
  /// event whose deletion may have been sent is added there again if it's
  /// gone.
  void restore(CalEvent e) {
    final x = e.remoteId != null && _synced(e.calendarId) ? e.withExtra({'restored': true}).copyWith(pending: true, updatedAt: _now) : e;
    final i = state.events.indexWhere((y) => y.id == e.id);
    _set(state.copyWith(events: i < 0 ? [...state.events, x] : ([...state.events]..[i] = x)));
  }

  /// A change made by calendar sync (calendar_sync.dart), to the data as it
  /// is now.
  void apply(CalendarData Function(CalendarData) f) => _set(f(state));

  void toggle(String calendarId) =>
      _set(state.copyWith(calendars: [for (final c in state.calendars) c.id == calendarId ? c.copyWith(shown: !c.shown) : c]));

  /// A new calendar on this tablet.
  CalendarInfo addCalendar(String name, CalendarHue hue) => _add(CalendarInfo(id: newId('cal', now: _now), name: name.trim(), hue: hue));

  /// The next color no calendar has yet (they repeat once all are used).
  CalendarHue get nextHue => nextHueOf(state);

  /// A calendar read from a link (feed_sync.dart adds it, then its events).
  CalendarInfo addFeed({required String id, required String name, required FeedFrom from, required DateTime fetchedAt}) =>
      _add(CalendarInfo(id: id, name: name.trim(), kind: CalendarKind.feed, hue: nextHue, from: from, fetchedAt: fetchedAt.toUtc()));

  CalendarInfo _add(CalendarInfo c) {
    _set(withCalendar(state, c));
    return c;
  }

  /// A calendar link's events as read from its file ([events]), when it
  /// was last read, and why it couldn't be read again ([error]). Notes
  /// given to its events before stay with them.
  void setFeed(String calendarId, {List<CalEvent>? events, DateTime? fetchedAt, String? Function()? error}) {
    final cal = state.calendar(calendarId);
    if (cal == null || !cal.viewOnly) return;
    _set(
      state.copyWith(
        calendars: [for (final c in state.calendars) c.id == calendarId ? c.copyWith(fetchedAt: fetchedAt?.toUtc(), error: error) : c],
        events: events == null
            ? null
            : [
                for (final e in state.events)
                  if (e.calendarId != calendarId) e,
                for (final e in events)
                  if (state.links[e.id] case final link?) e.copyWith(notes: () => link) else e,
              ],
      ),
    );
  }

  /// Takes calendar [id] off this tablet with its events (and their notes'
  /// links; the notebooks stay).
  void removeCalendar(String id) {
    final cal = state.calendar(id);
    if (cal == null || cal.kind == CalendarKind.deadlines) return;
    final gone = {
      for (final e in state.events)
        if (e.calendarId == id) e.id,
    };
    _set(
      withDefaults(
        state.copyWith(
          calendars: [for (final c in state.calendars) if (c.id != id) c],
          events: [for (final e in state.events) if (e.calendarId != id) e],
          links: {for (final l in state.links.entries) if (!gone.contains(l.key) && !l.key.startsWith('${id}_')) l.key: l.value},
        ),
      ),
    );
  }

  void _set(CalendarData data) {
    state = data;
    final json = data.toJson();
    final store = ref.read(boardStoreProvider);
    unawaited(ref.read(writeQueueProvider).run(() => store.saveCalendar(json)));
  }
}

/// The deadlines written in notes, read again whenever the index changes.
final deadlinesProvider = NotifierProvider<Deadlines, List<CalEvent>>(Deadlines.new);

class Deadlines extends Notifier<List<CalEvent>> {
  bool _alive = true;
  bool _asked = false;

  @override
  List<CalEvent> build() {
    final index = ref.read(handwritingIndexProvider);
    index.revision.addListener(_changed);
    ref.listen(libraryProvider, (_, _) => _changed());
    ref.onDispose(() {
      _alive = false;
      index.revision.removeListener(_changed);
    });
    _changed();
    return const [];
  }

  /// Read again soon (never inside another provider's update).
  void _changed() {
    if (_asked) return;
    _asked = true;
    Future.microtask(() async {
      _asked = false;
      if (!_alive) return;
      final rows = await diagTimeAsync('calendar deadlines', () => ref.read(indexDbProvider).searchText(const ['due']));
      if (!_alive) return;
      final library = ref.read(libraryProvider);
      state = deadlinesIn(
        rows.where((r) {
          final nb = library.byId(r.notebookId);
          return nb != null && !nb.trashed && !nb.locked;
        }),
      );
    });
  }
}

/// What the calendars shown have from [from] to [to) (local times), all-day
/// ones first, then by start.
List<Occurrence> occurrencesIn(CalendarData data, List<CalEvent> deadlines, DateTime from, DateTime to, {bool all = false}) {
  final shown = {
    for (final c in data.calendars)
      if (all || c.shown) c.id,
  };
  final list = [
    for (final e in [...data.events, ...deadlines])
      if (shown.contains(e.calendarId)) ...e.occurrences(from, to),
  ];
  list.sort((a, b) {
    if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
    final s = a.start.compareTo(b.start);
    return s != 0 ? s : a.event.title.compareTo(b.event.title);
  });
  return list;
}

/// When the event [id] starts on [day] now (it may have moved since the
/// reminder was set): a repeating event's time that day, else its start. An
/// all-day event starts at 9 in the morning. Null if it's gone.
DateTime? eventStart(CalendarData data, List<CalEvent> deadlines, String id, String day) {
  final e = data.event(id) ?? deadlines.where((x) => x.id == id).firstOrNull;
  if (e == null) return null;
  DateTime? start;
  final d = parseDay(day);
  if ((e.repeat != null || e.times != null) && d != null) {
    start = e.occurrences(d, addDays(d, 1)).where((o) => dayOf(o.start) == d).firstOrNull?.start;
  } else {
    start = e.localStart;
  }
  if (start == null) return null;
  return e.allDay ? start.add(const Duration(hours: 9)) : start;
}
