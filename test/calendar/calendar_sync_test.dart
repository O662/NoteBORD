// Two-way sync with Google Calendar and Outlook (Phase 9c), against an
// in-memory calendar (fake_remote.dart): connecting, sending what changed
// here (and only that), reading what changed there, both at once, deleting
// (and Undo), "Just this one", repeats Endless can't show, moving to a
// tablet calendar, offline, signed out, view-only calendars, and
// disconnecting. On Friday Sep 25, 2026 at 10 AM.

import 'package:endless/board/store.dart';
import 'package:endless/calendar/calendar_model.dart';
import 'package:endless/calendar/calendar_state.dart';
import 'package:endless/calendar/calendar_sync.dart';
import 'package:endless/sync/cloud.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'fake_remote.dart';

FakeRemote _school() {
  final r = FakeRemote();
  r.addCalendar('kim@gmail.com', 'School', primary: true);
  r.addCalendar('holidays', 'Holidays', canEdit: false, shown: false);
  r.add('kim@gmail.com', 'Physics midterm', DateTime(2026, 9, 28, 10), DateTime(2026, 9, 28, 11));
  r.add('kim@gmail.com', 'Physics lecture', DateTime(2026, 9, 7, 10), DateTime(2026, 9, 7, 11, 15), repeat: const Repeat(RepeatEvery.week));
  r.add('holidays', 'Thanksgiving', DateTime(2026, 11, 26), DateTime(2026, 11, 27), allDay: true);
  return r;
}

Future<ProviderContainer> _app(FakeRemote remote, {String email = 'kim@gmail.com', bool connect = true}) async {
  final c = ProviderContainer(overrides: await testOverrides(MemoryBoardStore(), calendarRemote: remote, calendarEmail: email));
  addTearDown(c.dispose);
  c.listen(calendarProvider, (_, _) {});
  c.listen(calendarSyncProvider, (_, _) {});
  if (connect) await c.read(calendarSyncProvider.notifier).connect(CalendarKind.google);
  return c;
}

CalendarData _data(ProviderContainer c) => c.read(calendarProvider);
Calendars _cals(ProviderContainer c) => c.read(calendarProvider.notifier);
Future<void> _sync(ProviderContainer c) => c.read(calendarSyncProvider.notifier).sync();
CalEvent _ev(ProviderContainer c, String title) => _data(c).events.singleWhere((e) => e.title == title && !e.deleted);
CalendarInfo _cal(ProviderContainer c, String name) => _data(c).calendars.singleWhere((x) => x.name == name);

void main() {
  test('connecting adds the account, its calendars and their events', () async {
    final remote = _school();
    final c = await _app(remote);
    final a = _data(c).account(CalendarKind.google)!;
    expect(a.email, 'kim@gmail.com');
    expect(a.syncedAt, testNow.toUtc());
    expect(a.error, isNull);

    final school = _cal(c, 'School'), holidays = _cal(c, 'Holidays');
    expect((school.kind, school.remoteId, school.account, school.editable, school.shown), (CalendarKind.google, 'kim@gmail.com', 'kim@gmail.com', true, true));
    expect((holidays.readOnly, holidays.editable, holidays.shown), (true, false, false));

    final lecture = _ev(c, 'Physics lecture');
    expect(lecture.remoteId, isNotNull);
    expect(lecture.pending, isFalse);
    expect(lecture.repeat?.every, RepeatEvery.week);
    expect(lecture.times, isNotEmpty);
    final monday = lecture.occurrences(DateTime(2026, 9, 28), DateTime(2026, 9, 29)).single;
    expect(monday.start, DateTime(2026, 9, 28, 10));
    expect(_ev(c, 'Thanksgiving').allDay, isTrue);

    // calendar.json keeps all of it, the times included.
    final again = CalendarData.fromJson(_data(c).toJson());
    expect(again.accounts.single.email, 'kim@gmail.com');
    final kept = again.events.singleWhere((e) => e.title == 'Physics lecture');
    expect(kept.times, lecture.times);
    expect(kept.base, lecture.base);
    expect(again.calendars.singleWhere((x) => x.name == 'Holidays').readOnly, isTrue);
  });

  test('a new event goes to Google, then only what changed', () async {
    final remote = _school();
    final c = await _app(remote);
    final school = _cal(c, 'School');
    _cals(c).put(_cals(c).newEvent(title: 'Study group', start: DateTime(2026, 9, 26, 15), end: DateTime(2026, 9, 26, 16), calendarId: school.id));
    expect(_ev(c, 'Study group').pending, isTrue);
    await _sync(c);
    final there = remote.find('Study group')!;
    expect(there.start, DateTime(2026, 9, 26, 15).toUtc());
    final here = _ev(c, 'Study group');
    expect((here.remoteId, here.pending), (there.id, false));

    _cals(c).put(here.copyWith(title: 'Study group, room 4'));
    await _sync(c);
    expect(remote.log.where((l) => l.startsWith('update')).single, 'update ${there.id} title');
    expect(there.title, 'Study group, room 4');

    _cals(c).put(_ev(c, 'Study group, room 4').copyWith(start: DateTime(2026, 9, 26, 16).toUtc(), end: DateTime(2026, 9, 26, 17).toUtc()));
    await _sync(c);
    expect(remote.log.where((l) => l.startsWith('update')).last, 'update ${there.id} when');
    expect(there.start, DateTime(2026, 9, 26, 16).toUtc());
    expect(_ev(c, 'Study group, room 4').pending, isFalse);
  });

  test('notes stay with an event, and aren’t sent', () async {
    final remote = _school();
    final c = await _app(remote);
    _cals(c).put(_ev(c, 'Physics lecture').copyWith(notes: () => const NoteLink('nb_physics')));
    final id = _ev(c, 'Physics lecture').id;
    await _sync(c);
    expect(remote.log.where((l) => l.startsWith('update')), isEmpty);

    remote.change(remote.find('Physics lecture')!, (f) => f.title = 'Physics 101 lecture');
    await _sync(c);
    final e = _ev(c, 'Physics 101 lecture');
    expect((e.id, e.notes), (id, const NoteLink('nb_physics')));
  });

  test('changed on both sides: both changes are kept', () async {
    final remote = _school();
    final c = await _app(remote);
    _cals(c).put(_ev(c, 'Physics midterm').copyWith(start: DateTime(2026, 9, 28, 13).toUtc(), end: DateTime(2026, 9, 28, 14).toUtc()));
    final there = remote.find('Physics midterm')!;
    remote.change(there, (f) => f.title = 'Physics midterm (room 2)');
    await _sync(c);
    expect(there.title, 'Physics midterm (room 2)');
    expect(there.start, DateTime(2026, 9, 28, 13).toUtc());
    final here = _ev(c, 'Physics midterm (room 2)');
    expect(here.localStart, DateTime(2026, 9, 28, 13));
    expect(here.pending, isFalse);
  });

  test('the same part changed on both sides: the later change wins', () async {
    for (final (laterThere, wins) in [(true, 'Midterm B'), (false, 'Midterm A')]) {
      final remote = _school();
      final c = await _app(remote);
      _cals(c).put(_ev(c, 'Physics midterm').copyWith(title: 'Midterm A'));
      remote.now = testNow.toUtc().add(Duration(hours: laterThere ? 1 : -1));
      remote.change(remote.find('Physics midterm')!, (f) => f.title = 'Midterm B');
      await _sync(c);
      expect(remote.find(wins), isNotNull, reason: 'later there: $laterThere');
      expect(_ev(c, wins).pending, isFalse);
    }
  });

  test('deleted here, deleted there; unless it changed there since', () async {
    final remote = _school();
    final c = await _app(remote);
    final midterm = _ev(c, 'Physics midterm');
    _cals(c).delete(midterm.id);
    expect(_data(c).events.singleWhere((e) => e.id == midterm.id).deleted, isTrue);
    await _sync(c);
    expect(remote.find('Physics midterm'), isNull);
    expect(_data(c).events.where((e) => e.id == midterm.id), isEmpty);

    // Undo after the deletion went: it's added there again.
    _cals(c).restore(midterm);
    await _sync(c);
    expect(remote.find('Physics midterm'), isNotNull);
    expect(_ev(c, 'Physics midterm').remoteId, remote.find('Physics midterm')!.id);

    // Changed there after it was deleted here: kept.
    _cals(c).delete(_ev(c, 'Physics lecture').id);
    remote.now = testNow.toUtc().add(const Duration(minutes: 5));
    remote.change(remote.find('Physics lecture')!, (f) => f.title = 'Physics lecture (moved)');
    await _sync(c);
    expect(remote.find('Physics lecture (moved)'), isNotNull);
    expect(_ev(c, 'Physics lecture (moved)').deleted, isFalse);
  });

  test('just this one: one time of a repeating event, off there too', () async {
    final remote = _school();
    final c = await _app(remote);
    final lecture = _ev(c, 'Physics lecture');
    final o = lecture.occurrences(DateTime(2026, 9, 28), DateTime(2026, 9, 29)).single;
    _cals(c).skip(o);
    expect(_ev(c, 'Physics lecture').occurrences(DateTime(2026, 9, 28), DateTime(2026, 9, 29)), isEmpty);
    await _sync(c);
    final there = remote.find('Physics lecture')!;
    expect(there.cancelled, {'2026-09-28'});
    expect(remote.log.where((l) => l.startsWith('update')), isEmpty);
    final after = _ev(c, 'Physics lecture');
    expect(after.occurrences(DateTime(2026, 9, 28), DateTime(2026, 9, 29)), isEmpty);
    expect(after.occurrences(DateTime(2026, 10, 5), DateTime(2026, 10, 6)), hasLength(1));
    expect((after.pending, after.cancel.isEmpty), (false, true));
  });

  test('a new repeating event with a time taken off before it was sent', () async {
    final remote = _school();
    final c = await _app(remote);
    final e = _cals(c)
        .newEvent(title: 'Gym', start: DateTime(2026, 9, 28, 7), end: DateTime(2026, 9, 28, 8), calendarId: _cal(c, 'School').id)
        .copyWith(repeat: () => const Repeat(RepeatEvery.week));
    _cals(c).put(e);
    _cals(c).skip(_ev(c, 'Gym').occurrences(DateTime(2026, 10, 5), DateTime(2026, 10, 6)).single);
    await _sync(c);
    final there = remote.find('Gym')!;
    expect(there.repeat?.every, RepeatEvery.week);
    expect(there.cancelled, {'2026-10-05'});
    expect(_ev(c, 'Gym').occurrences(DateTime(2026, 10, 5), DateTime(2026, 10, 6)), isEmpty);
  });

  test('a repeat Endless can’t show stays as it was; changing its time moves every time', () async {
    final remote = _school();
    remote.add('kim@gmail.com', 'Lab', DateTime(2026, 9, 22, 14), DateTime(2026, 9, 22, 16), everyDays: 14);
    final c = await _app(remote);
    final lab = _ev(c, 'Lab');
    expect((lab.customRepeat, lab.repeat, lab.repeats), (true, null, true));
    expect(lab.occurrences(DateTime(2026, 10, 6), DateTime(2026, 10, 7)), hasLength(1));
    expect(lab.occurrences(DateTime(2026, 9, 29), DateTime(2026, 9, 30)), isEmpty);

    // A later start moves every time here at once, and is sent as times.
    _cals(c).put(lab.copyWith(title: 'Chem lab', start: DateTime(2026, 9, 22, 15).toUtc(), end: DateTime(2026, 9, 22, 17).toUtc()));
    final moved = _ev(c, 'Chem lab').occurrences(DateTime(2026, 10, 6), DateTime(2026, 10, 7)).single;
    expect((moved.start, moved.end), (DateTime(2026, 10, 6, 15), DateTime(2026, 10, 6, 17)));
    await _sync(c);
    final there = remote.find('Chem lab')!;
    expect(remote.log.where((l) => l.startsWith('update')).single, 'update ${there.id} title when');
    expect(there.everyDays, 14);
  });

  test('no longer repeats: a single event in place of the series', () async {
    final remote = _school();
    final c = await _app(remote);
    final lecture = _ev(c, 'Physics lecture');
    _cals(c).put(lecture.copyWith(repeat: () => null).withExtra({'rule': null}));
    await _sync(c);
    expect(remote.log, containsAllInOrder(['delete Physics lecture', 'create Physics lecture']));
    expect(remote.find('Physics lecture')!.repeats, isFalse);
    final after = _ev(c, 'Physics lecture');
    expect((after.id, after.repeats, after.pending), (lecture.id, false, false));
  });

  test('moved to a tablet calendar: out of Google, kept here', () async {
    final remote = _school();
    final c = await _app(remote);
    _cals(c).put(_ev(c, 'Physics midterm').copyWith(calendarId: 'local'));
    await _sync(c);
    expect(remote.find('Physics midterm'), isNull);
    final here = _ev(c, 'Physics midterm');
    expect((here.calendarId, here.remoteId, here.pending), ('local', null, false));
  });

  test('offline: changes wait here and go when it’s back', () async {
    final remote = _school();
    final c = await _app(remote);
    remote.failWith = const CloudException(CloudFailure.offline, 'no network');
    _cals(c).put(_ev(c, 'Physics midterm').copyWith(title: 'Midterm'));
    await _sync(c);
    expect(_data(c).account(CalendarKind.google)!.error, startsWith('Offline'));
    expect(_ev(c, 'Midterm').pending, isTrue);
    expect(remote.find('Physics midterm'), isNotNull);

    remote.failWith = null;
    await _sync(c);
    expect(remote.find('Midterm'), isNotNull);
    expect(_data(c).account(CalendarKind.google)!.error, isNull);
  });

  test('signed out: it waits for Sign in again', () async {
    final remote = _school();
    final c = await _app(remote);
    remote.failWith = const CloudException(CloudFailure.signedOut, 'Sign in to Google Calendar again');
    await _sync(c);
    final a = _data(c).account(CalendarKind.google)!;
    expect((a.signedOut, a.error), (true, 'Sign in to Google Calendar again'));
    remote.failWith = null;
    final calls = remote.log.length;
    await _sync(c);
    expect(remote.log, hasLength(calls));

    await c.read(calendarSyncProvider.notifier).connect(CalendarKind.google);
    expect(_data(c).account(CalendarKind.google)!.signedOut, isFalse);
    expect(_cal(c, 'School').kind, CalendarKind.google);
  });

  test('Google signed in as another account: not synced', () async {
    final remote = _school();
    final c = await _app(remote, email: 'sam@gmail.com');
    final a = _data(c).account(CalendarKind.google)!;
    expect(a.signedOut, isTrue);
    expect(a.error, 'Signed in to Google as kim@gmail.com. Sign in again as sam@gmail.com.');
    expect(_data(c).calendars.where((x) => x.kind == CalendarKind.google), isEmpty);
  });

  test('a view-only calendar: notes only', () async {
    final remote = _school();
    final c = await _app(remote);
    final e = _ev(c, 'Thanksgiving');
    _cals(c).put(e.copyWith(title: 'Turkey', notes: () => const NoteLink('nb_family')));
    final after = _ev(c, 'Thanksgiving');
    expect((after.notes, after.pending), (const NoteLink('nb_family'), false));
  });

  test('a calendar deleted there leaves; Disconnect takes the rest', () async {
    final remote = _school();
    final c = await _app(remote);
    remote.calendarsThere.removeWhere((x) => x.id == 'holidays');
    remote.events.remove('holidays');
    await _sync(c);
    expect(_data(c).calendars.map((x) => x.name), isNot(contains('Holidays')));
    expect(_data(c).events.where((e) => e.title == 'Thanksgiving'), isEmpty);

    await c.read(calendarSyncProvider.notifier).disconnect(CalendarKind.google);
    expect(_data(c).accounts, isEmpty);
    expect(_data(c).calendars.where((x) => x.synced), isEmpty);
    expect(_data(c).events.where((e) => e.remoteId != null), isEmpty);
    expect(_data(c).calendars.any((x) => x.id == 'local'), isTrue);
    // Nothing deleted there.
    expect(remote.find('Physics midterm'), isNotNull);
  });

  test('what changed since Google or Outlook last had it', () {
    expect(changesOf(CalEvent(id: 'a', calendarId: 'c', title: 'x', start: testNow, end: testNow), null), (title: true, when: true, rule: true));
    final e = CalEvent(id: 'a', calendarId: 'c', title: 'x', start: testNow.toUtc(), end: testNow.toUtc().add(const Duration(hours: 1)));
    final sent = e.withExtra({'base': baseOf(e)});
    expect(changesOf(sent, sent.base), (title: false, when: false, rule: false));
    expect(changesOf(sent.copyWith(repeat: () => const Repeat(RepeatEvery.day)), sent.base), (title: false, when: false, rule: true));
  });
}
