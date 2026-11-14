import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../board/ids.dart';
import '../board/model.dart' show Json;
import '../library/library.dart' show clockProvider;
import '../recognition/segment.dart' show fnv64;
import '../sync/cloud.dart';
import '../sync/cloud_auth.dart';
import 'calendar_model.dart';
import 'calendar_state.dart';
import 'feeds.dart' show feedAhead, feedPast;
import 'remote.dart';
import 'remote_google.dart';
import 'remote_outlook.dart';

// Two-way sync with Google Calendar and Outlook (Phase 9c). One Google and
// one Outlook account; every calendar the account can see shows here, and
// those it can change can be changed here. Endless talks to Google and
// Microsoft straight from the tablet; there's no Endless server.
//
// A sync first sends what changed here (new events, changes, deletions,
// times taken off a repeating event), then reads each calendar again (6
// months back, 18 ahead, as calendar links are read). Only what changed
// is sent: each event keeps what Google or Microsoft last had (`base`), so
// a change made there meanwhile isn't overwritten. If both sides changed
// the same event, the parts changed on one side are both kept; where both
// changed the same part (the title, the times or the repeat), the later
// change wins. A deletion here loses to a change there made after it.
//
// It syncs at start, every 15 minutes while Endless is open, a few seconds
// after a change here, when the Calendar or Planner opens (if it's been 5
// minutes), and with Sync now.

/// Signs in to Google Calendar or Outlook, apart from Drive and OneDrive.
CloudAuth calendarAuthFor(CalendarKind kind) {
  final mobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  return switch (kind) {
    CalendarKind.google =>
      mobile
          ? GoogleAuth(scopes: googleCalendarScopes, label: 'Google Calendar')
          : LoopbackAuth(CloudKind.google, scopes: googleCalendarScopes, key: 'endless.calendar.google.refresh', label: 'Google Calendar'),
    CalendarKind.outlook =>
      mobile
          ? MicrosoftAuth(scopes: microsoftCalendarScopes, key: 'endless.calendar.outlook.refresh', label: 'Outlook')
          : LoopbackAuth(CloudKind.onedrive, scopes: microsoftCalendarScopes, key: 'endless.calendar.outlook.refresh', label: 'Outlook'),
    _ => throw ArgumentError('Only Google and Outlook calendars sign in'),
  };
}

final calendarAuthProvider = Provider.family<CloudAuth, CalendarKind>((ref, kind) => calendarAuthFor(kind));

final calendarRemoteProvider = Provider.family<CalendarRemote, CalendarKind>((ref, kind) {
  final auth = ref.read(calendarAuthProvider(kind));
  final client = http.Client();
  ref.onDispose(client.close);
  return kind == CalendarKind.google ? GoogleCalendarRemote(auth, client) : OutlookCalendarRemote(auth, client);
});

/// Syncs on its own (at start, on a timer, after changes). Tests call
/// [CalendarSync.sync] instead.
final autoCalendarSyncProvider = Provider<bool>((ref) => true);

/// The accounts syncing right now.
final calendarSyncProvider = NotifierProvider<CalendarSync, Set<CalendarKind>>(CalendarSync.new);

// --- What changed ----------------------------------------------------------

/// What Google or Microsoft have of [e] once it's sent: its calendar here,
/// title, times and repeat.
Json baseOf(CalEvent e) => {
  'cal': e.calendarId,
  'title': e.title,
  'allDay': e.allDay,
  'start': e.allDay ? dayKey(e.start) : e.start.toUtc().toIso8601String(),
  'end': e.allDay ? dayKey(e.end) : e.end.toUtc().toIso8601String(),
  'rule': e.ruleKey,
};

typedef Changes = ({bool title, bool when, bool rule});

/// What differs between [e] and [base] (all of it with no base).
Changes changesOf(CalEvent e, Json? base) {
  if (base == null) return (title: true, when: true, rule: true);
  final now = baseOf(e);
  return (
    title: now['title'] != base['title'],
    when: now['start'] != base['start'] || now['end'] != base['end'] || now['allDay'] != base['allDay'],
    rule: now['rule'] != base['rule'],
  );
}

bool _any(Changes c) => c.title || c.when || c.rule;

/// [into] with [from]'s title, times or repeat.
CalEvent takeFields(CalEvent into, CalEvent from, Changes which) {
  var x = into;
  if (which.title) x = x.copyWith(title: from.title);
  if (which.when) x = x.copyWith(start: from.start, end: from.end, allDay: from.allDay);
  if (which.rule) x = x.copyWith(repeat: () => from.repeat).withExtra({'rule': from.rule});
  return x;
}

const _syncKeys = ['base', 'rule', 'instances', 'cancel', 'of', 'restored'];

/// [r] as an event in calendar [calendarId], keeping [local]'s id and notes.
CalEvent eventFromRemote(RemoteItem r, String calendarId, CalEvent? local) {
  final e = CalEvent(
    id: local?.id ?? '${calendarId}_${fnv64(r.id)}',
    calendarId: calendarId,
    title: r.title,
    start: r.start,
    end: r.end,
    allDay: r.allDay,
    repeat: r.repeat,
    notes: local?.notes,
    remoteId: r.id,
    etag: r.etag,
    updatedAt: r.updated,
    times: r.series ? (r.times ?? local?.times) : null,
    extra: {
      for (final x in (local?.extra ?? const <String, Object?>{}).entries)
        if (!_syncKeys.contains(x.key)) x.key: x.value,
    },
  ).withExtra({'rule': r.rule, 'of': r.seriesOf, if (r.instances.isNotEmpty) 'instances': r.instances});
  return e.withExtra({'base': baseOf(e)});
}

/// [data] with calendar [calendarId]'s events as Google or Microsoft have
/// them ([items]); events changed here and not sent yet stay as they are.
CalendarData mergeRead(CalendarData data, String calendarId, List<RemoteItem> items) {
  bool ours(CalEvent e) => e.calendarId == calendarId || e.base?['cal'] == calendarId;
  final byRemote = {
    for (final e in data.events)
      if (ours(e) && e.remoteId != null) e.remoteId!: e,
  };
  final fresh = <CalEvent>[];
  for (final r in items) {
    final local = byRemote[r.id];
    if (local != null && local.pending) continue;
    fresh.add(eventFromRemote(r, calendarId, local));
  }
  return data.copyWith(
    events: [
      for (final e in data.events)
        if (!ours(e) || e.pending || e.remoteId == null) e,
      ...fresh,
    ],
  );
}

/// [data] without Google's or Outlook's calendar [id] and its events.
CalendarData withoutCalendar(CalendarData data, String id) => withDefaults(
  data.copyWith(
    calendars: [for (final c in data.calendars) if (c.id != id) c],
    events: [for (final e in data.events) if (e.calendarId != id) e],
  ),
);

/// The message an account's card shows after [e].
String syncError(CloudException e) => switch (e.failure) {
  CloudFailure.offline => 'Offline. Changes here are sent when Endless is back online.',
  _ => e.message,
};

// --- The sync --------------------------------------------------------------

class CalendarSync extends Notifier<Set<CalendarKind>> {
  static const every = Duration(minutes: 15);
  static const fresh = Duration(minutes: 5);

  /// How long after a change here it's sent (long enough to Undo a delete).
  static const afterChange = Duration(seconds: 6);

  Timer? _timer, _soon;
  bool _alive = true, _started = false, _again = false;
  Future<void>? _running;

  @override
  Set<CalendarKind> build() {
    ref.onDispose(() {
      _alive = false;
      _timer?.cancel();
      _soon?.cancel();
    });
    if (ref.read(autoCalendarSyncProvider)) ref.listen(calendarProvider, _changed);
    return const {};
  }

  Calendars get _calendars => ref.read(calendarProvider.notifier);
  CalendarData get _data => ref.read(calendarProvider);
  DateTime get _now => ref.read(clockProvider)().toUtc();
  CalendarRemote _remote(CalendarKind kind) => ref.read(calendarRemoteProvider(kind));

  static Set<String> _pendingOf(CalendarData? d) => {
    for (final e in d?.events ?? const <CalEvent>[])
      if (e.pending) '${e.id}@${e.updatedAt}',
  };

  /// A change here is sent a few seconds later.
  void _changed(CalendarData? before, CalendarData now) {
    if (now.accounts.isEmpty || !_alive) return;
    if (_pendingOf(now).difference(_pendingOf(before)).isEmpty) return;
    _soon?.cancel();
    _soon = Timer(afterChange, () => unawaited(sync()));
  }

  /// At start: syncs if an account is connected.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    if (_data.accounts.isEmpty) return;
    _watch();
    await sync();
  }

  void _watch() {
    if (ref.read(autoCalendarSyncProvider)) _timer ??= Timer.periodic(every, (_) => unawaited(sync()));
  }

  /// Syncs if an account last synced more than [olderThan] ago.
  Future<void> refreshAll({Duration olderThan = fresh}) async {
    final now = _now;
    if (_data.accounts.any((a) => !a.signedOut && (a.syncedAt == null || now.difference(a.syncedAt!) >= olderThan))) await sync();
  }

  /// Sends what changed here, then reads every calendar again. One sync at
  /// a time; asked during one, another follows.
  Future<void> sync() async {
    if (_running case final r?) {
      _again = true;
      return r;
    }
    final run = _running = _run();
    try {
      await run;
    } finally {
      _running = null;
    }
    if (_again && _alive) {
      _again = false;
      await sync();
    }
  }

  void _setAccount(CalendarKind kind, CalendarAccount Function(CalendarAccount) f) => _calendars.apply(
    (d) => d.copyWith(accounts: [for (final a in d.accounts) a.kind == kind ? f(a) : a]),
  );

  Future<void> _run() async {
    final accounts = [
      for (final a in _data.accounts)
        if (!a.signedOut) a,
    ];
    if (accounts.isEmpty || !_alive) return;
    state = {for (final a in accounts) a.kind};
    final failed = <CalendarKind, CloudException>{};
    final notes = <CalendarKind, String>{};
    try {
      await _push(failed, notes);
      for (final a in accounts) {
        if (!_alive) return;
        if (failed.containsKey(a.kind) || _data.account(a.kind)?.email != a.email) continue;
        try {
          await _pull(a);
        } on CloudException catch (e) {
          failed[a.kind] = e;
        } on Object catch (e) {
          debugPrint('Calendar sync (${a.kind.name}): $e');
          failed[a.kind] = CloudException(CloudFailure.other, 'Couldn’t read ${a.app}');
        }
      }
      if (!_alive) return;
      final now = _now;
      for (final a in accounts) {
        final e = failed[a.kind];
        _setAccount(
          a.kind,
          (x) => e == null
              ? x.copyWith(syncedAt: now, error: () => notes[a.kind])
              : x.copyWith(error: () => syncError(e), signedOut: e.failure == CloudFailure.signedOut),
        );
      }
    } finally {
      if (_alive) state = const {};
    }
  }

  // --- Sending ---------------------------------------------------------------

  Future<void> _push(Map<CalendarKind, CloudException> failed, Map<CalendarKind, String> notes) async {
    for (final id in [
      for (final e in _data.events)
        if (e.pending) e.id,
    ]) {
      if (!_alive) return;
      final e = _data.events.where((x) => x.id == id).firstOrNull;
      if (e == null || !e.pending) continue;
      final home = e.remoteId == null ? null : _data.calendar(e.base?['cal'] as String? ?? e.calendarId);
      final target = _data.calendar(e.calendarId);
      final kinds = {
        for (final c in [home, target])
          if (c != null && c.synced) c.kind,
      };
      if (kinds.any((k) => failed.containsKey(k) || (_data.account(k)?.signedOut ?? true))) continue;
      try {
        await _send(e, home?.synced == true ? home : null, target);
      } on CloudException catch (x) {
        if (x.failure == CloudFailure.other) {
          // Google or Microsoft refused it: it stays here as it is, and is
          // read again from there.
          for (final k in kinds) {
            notes[k] = 'Couldn’t send “${e.title}”. ${x.message}';
          }
          _edit(id, (c) => c.copyWith(pending: false).withExtra({'base': null}));
        } else {
          for (final k in kinds) {
            failed[k] = x;
          }
        }
      } on Object catch (x) {
        debugPrint('Calendar sync: sending ${e.id}: $x');
        for (final k in kinds) {
          notes[k] = 'Couldn’t send “${e.title}”.';
        }
        _edit(id, (c) => c.copyWith(pending: false));
      }
    }
  }

  /// Changes event [id] as it is now; [f] returning null removes it.
  void _edit(String id, CalEvent? Function(CalEvent) f) => _calendars.apply((d) {
    final i = d.events.indexWhere((x) => x.id == id);
    if (i < 0) return d;
    final x = f(d.events[i]);
    return d.copyWith(events: x == null ? ([...d.events]..removeAt(i)) : ([...d.events]..[i] = x));
  });

  static CalEvent _unlinked(CalEvent e, {bool keepRule = true}) => e
      .copyWith(remoteId: () => null, etag: () => null, times: () => null)
      .withExtra({'base': null, 'instances': null, 'of': null, 'cancel': null, 'restored': null, if (!keepRule) 'rule': null});

  /// Sends event [e] ([home]: the calendar it's in at Google or Microsoft;
  /// [target]: the one it's in here).
  Future<void> _send(CalEvent e, CalendarInfo? home, CalendarInfo? target) async {
    final id = e.id, sentAt = e.updatedAt;
    var x = e;

    if (x.deleted) {
      if (home != null) {
        final kept = await _deleteThere(home, x);
        if (kept) return;
      }
      _edit(id, (c) => c.updatedAt == sentAt || c.deleted ? null : c);
      return;
    }

    // Moved to another calendar: out of the old one there.
    if (home != null && home.id != x.calendarId) {
      await _remote(home.kind).delete(home.remoteId!, x.remoteId!);
      final keepRule = target?.kind == home.kind;
      x = _unlinked(x, keepRule: keepRule);
      _edit(id, (c) => _unlinked(c, keepRule: keepRule));
    }
    if (target == null || !target.synced || target.readOnly) {
      _edit(id, (c) => c.copyWith(pending: c.updatedAt != sentAt));
      return;
    }
    final remote = _remote(target.kind);
    final cal = target.remoteId!;

    // Put back with Undo: added again if its deletion got there.
    if (x.restored && x.remoteId != null) {
      final there = await remote.get(cal, x.remoteId!);
      x = there == null ? _unlinked(x) : x.withExtra({'restored': null});
      final gone = there == null;
      _edit(id, (c) => gone ? _unlinked(c) : c.withExtra({'restored': null}));
    }

    if (x.remoteId == null) {
      final made = await remote.create(cal, x);
      final cancel = {...x.cancel, ...?x.repeat?.skip};
      final base = baseOf(x);
      var gone = false;
      _edit(id, (c) {
        if (c.deleted) gone = true;
        return c
            .copyWith(remoteId: () => made.id, etag: () => made.etag)
            .withExtra({'base': base, 'cancel': cancel.isEmpty ? null : cancel.toList(), 'restored': null});
      });
      if (!_data.events.any((c) => c.id == id)) {
        // Deleted here while it was being added: deleted there too.
        await remote.delete(cal, made.id);
        return;
      }
      if (gone) return;
      x = x.copyWith(remoteId: () => made.id, etag: () => made.etag).withExtra({'cancel': cancel.isEmpty ? null : cancel.toList()});
    } else {
      final ch = changesOf(x, x.base);
      if (ch.rule && x.repeat == null && !x.customRepeat && x.seriesOf == null && x.base?['rule'] != 'none') {
        // No longer repeats: a single event in place of the series.
        await remote.delete(cal, x.remoteId!);
        final made = await remote.create(cal, _unlinked(x, keepRule: false));
        final base = baseOf(x);
        _edit(
          id,
          (c) => _unlinked(c, keepRule: false).copyWith(remoteId: () => made.id, etag: () => made.etag).withExtra({'base': base}),
        );
        x = _unlinked(x, keepRule: false);
      } else if (_any(ch)) {
        final done = await _update(remote, cal, x, ch);
        if (done == null) return;
        x = done;
      }
    }

    // Times taken off a repeating event ("Just this one").
    for (final day in x.cancel) {
      final d = parseDay(day);
      if (d != null && x.remoteId != null) {
        final one = x.instances[day] ?? await remote.instanceOn(cal, x.remoteId!, d.toUtc(), addDays(d, 1).toUtc());
        if (one != null) await remote.delete(cal, one);
      }
      _edit(id, (c) {
        final rest = [for (final k in c.cancel) if (k != day) k];
        return c.withExtra({'cancel': rest.isEmpty ? null : rest});
      });
    }
    _edit(id, (c) => c.copyWith(pending: c.updatedAt != sentAt));
  }

  /// Sends [ch] of [x]; if it changed there meanwhile, both changes are
  /// kept (where both changed the same part, the later one). Returns the
  /// event as sent, or null if it's gone there (and so here).
  Future<CalEvent?> _update(CalendarRemote remote, String cal, CalEvent x, Changes ch) async {
    final id = x.id;
    try {
      final done = await remote.update(cal, x.remoteId!, x.etag, x, title: ch.title, when: ch.when, rule: ch.rule && x.seriesOf == null);
      final base = baseOf(x);
      _edit(id, (c) => c.copyWith(etag: () => done.etag).withExtra({'base': base}));
      return x.copyWith(etag: () => done.etag).withExtra({'base': base});
    } on RemoteGone {
      _edit(id, (_) => null);
      return null;
    } on RemoteConflict {
      final now = await remote.get(cal, x.remoteId!);
      if (now == null) {
        _edit(id, (_) => null);
        return null;
      }
      final theirs = eventFromRemote(now, x.calendarId, x);
      final changedThere = changesOf(theirs, x.base);
      final theyWin = now.updated != null && x.updatedAt != null && now.updated!.isAfter(x.updatedAt!);
      final take = (
        title: changedThere.title && (!ch.title || theyWin),
        when: changedThere.when && (!ch.when || theyWin),
        rule: changedThere.rule && (!ch.rule || theyWin),
      );
      final merged = takeFields(x, theirs, take).copyWith(etag: () => now.etag);
      final send = changesOf(merged, theirs.base);
      var sent = merged.withExtra({'base': theirs.base});
      if (_any(send)) {
        try {
          final done = await remote.update(cal, x.remoteId!, now.etag, merged, title: send.title, when: send.when, rule: send.rule && x.seriesOf == null);
          sent = merged.copyWith(etag: () => done.etag).withExtra({'base': baseOf(merged)});
        } on RemoteConflict {
          throw const CloudException(CloudFailure.offline, 'Changed there again while syncing; trying again soon');
        }
      }
      final out = sent;
      _edit(
        id,
        (c) => takeFields(c, out, take).copyWith(etag: () => out.etag, times: () => c.times).withExtra({'base': out.base}),
      );
      return out;
    }
  }

  /// Deletes [x] in [home]. Returns true if it was kept instead: changed
  /// there after it was deleted here.
  Future<bool> _deleteThere(CalendarInfo home, CalEvent x) async {
    final remote = _remote(home.kind);
    try {
      await remote.delete(home.remoteId!, x.remoteId!, etag: x.etag);
      return false;
    } on RemoteConflict {
      final now = await remote.get(home.remoteId!, x.remoteId!);
      if (now == null) return false;
      if (now.updated != null && x.updatedAt != null && now.updated!.isAfter(x.updatedAt!)) {
        _edit(x.id, (c) => c.copyWith(deleted: false, pending: false));
        return true;
      }
      await remote.delete(home.remoteId!, x.remoteId!);
      return false;
    }
  }

  // --- Reading ---------------------------------------------------------------

  Future<void> _pull(CalendarAccount a) async {
    final remote = _remote(a.kind);
    final cals = await remote.calendars();
    if (a.kind == CalendarKind.google) {
      // Google's sign-in on Android is shared: make sure it's this account.
      final primary = cals.where((c) => c.primary).firstOrNull;
      if (primary != null && primary.id.contains('@') && primary.id.toLowerCase() != a.email.toLowerCase()) {
        throw CloudException(CloudFailure.signedOut, 'Signed in to Google as ${primary.id}. Sign in again as ${a.email}.');
      }
    }
    if (!_alive || _data.account(a.kind)?.email != a.email) return;
    final ids = {for (final c in cals) c.id};
    _calendars.apply((d) {
      var out = d;
      for (final rc in cals) {
        final here = out.calendars.where((c) => c.kind == a.kind && c.remoteId == rc.id).firstOrNull;
        if (here == null) {
          out = withCalendar(
            out,
            CalendarInfo(
              id: newId('cal', now: _now),
              name: rc.name,
              kind: a.kind,
              hue: nextHueOf(out),
              account: a.email,
              remoteId: rc.id,
              shown: rc.shown,
              readOnly: !rc.canEdit,
            ),
          );
        } else if (here.name != rc.name || here.readOnly != !rc.canEdit) {
          out = out.copyWith(calendars: [for (final c in out.calendars) c.id == here.id ? c.copyWith(name: rc.name, readOnly: !rc.canEdit) : c]);
        }
      }
      for (final c in d.calendars) {
        if (c.kind == a.kind && !ids.contains(c.remoteId)) out = withoutCalendar(out, c.id);
      }
      return out;
    });
    final now = _now;
    final from = now.subtract(feedPast), to = now.add(feedAhead);
    for (final cal in [
      for (final c in _data.calendars)
        if (c.kind == a.kind && c.remoteId != null) c,
    ]) {
      if (!_alive) return;
      try {
        final items = await remote.read(cal.remoteId!, from, to);
        if (!_alive || _data.calendar(cal.id) == null) continue;
        _calendars.apply((d) => mergeRead(d, cal.id, items));
      } on RemoteGone {
        _calendars.apply((d) => withoutCalendar(d, cal.id));
      }
    }
  }

  // --- Accounts --------------------------------------------------------------

  /// Why [kind] can't sign in with this build (no client id), or null.
  String? notReady(CalendarKind kind) => ref.read(calendarAuthProvider(kind)).notReady;

  /// Signs in to Google Calendar or Outlook (again, if its sign-in ran out)
  /// and syncs its calendars. Throws a [CloudException] if it can't.
  Future<CalendarAccount> connect(CalendarKind kind) async {
    final auth = ref.read(calendarAuthProvider(kind));
    if (auth.notReady case final why?) throw CloudException(CloudFailure.other, why);
    final who = await auth.signIn();
    final account = CalendarAccount(kind: kind, email: who.email, name: who.name);
    _calendars.apply((d) {
      var out = d;
      final old = d.account(kind);
      if (old != null && old.email.toLowerCase() != who.email.toLowerCase()) {
        // Another account: the old one's calendars leave.
        for (final c in d.calendars) {
          if (c.kind == kind) out = withoutCalendar(out, c.id);
        }
      }
      return out.copyWith(accounts: [...out.accounts.where((a) => a.kind != kind), account]);
    });
    _watch();
    await sync();
    return _data.account(kind) ?? account;
  }

  /// Signs out of [kind]: its calendars and their events leave this tablet
  /// (they stay in Google or Outlook). Changes not sent yet are lost.
  Future<void> disconnect(CalendarKind kind) async {
    _calendars.apply((d) {
      var out = d.copyWith(accounts: [...d.accounts.where((a) => a.kind != kind)]);
      for (final c in d.calendars) {
        if (c.kind == kind) out = withoutCalendar(out, c.id);
      }
      return out;
    });
    try {
      await ref.read(calendarAuthProvider(kind)).signOut();
    } on Object catch (e) {
      debugPrint('Calendar sign-out: $e');
    }
    if (_data.accounts.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }
}
