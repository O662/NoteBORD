// Calendar links (view only), end to end: Connect → Add a calendar link,
// the events in the Calendar with their notes, read again (and offline),
// wrong links, removing one, and the copy kept for the next start. On
// Friday Sep 25, 2026 at 1:30 PM. The links' times are floating (no time
// zone), so they read the same on any machine.

import 'dart:convert';

import 'package:endless/calendar/calendar_model.dart';
import 'package:endless/calendar/calendar_state.dart';
import 'package:endless/calendar/feed_sync.dart';
import 'package:endless/calendar/feeds.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/ui/canvas/canvas_screen.dart';
import 'package:endless/ui/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../calendar_samples.dart';
import '../helpers.dart';

const _link = 'https://calendar.google.com/calendar/ical/sam%40gmail.com/private-1f2e3d/basic.ics';

String _ics({bool review = false}) => [
  'BEGIN:VCALENDAR',
  'VERSION:2.0',
  'PRODID:-//Google Inc//Google Calendar 70.9054//EN',
  'X-WR-CALNAME:Classes',
  'BEGIN:VEVENT',
  'UID:hours@google.com',
  'DTSTAMP:20260901T000000Z',
  'DTSTART:20260907T150000',
  'DTEND:20260907T160000',
  'RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;UNTIL=20261211T235959',
  'EXDATE:20260923T150000',
  'SUMMARY:Office hours',
  'END:VEVENT',
  'BEGIN:VEVENT',
  'UID:break@google.com',
  'DTSTAMP:20260901T000000Z',
  'DTSTART;VALUE=DATE:20260926',
  'DTEND;VALUE=DATE:20260927',
  'SUMMARY:Fall break',
  'END:VEVENT',
  if (review) ...[
    'BEGIN:VEVENT',
    'UID:review@google.com',
    'DTSTAMP:20260901T000000Z',
    'DTSTART:20260924T180000',
    'DTEND:20260924T190000',
    'SUMMARY:Midterm review',
    'END:VEVENT',
  ],
  'END:VCALENDAR',
].join('\r\n');

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _tapLabel(WidgetTester tester, String label) async {
  await tester.tap(find.bySemanticsLabel(label).last);
  await _settle(tester);
}

Future<void> _addLink(WidgetTester tester, String link, {String name = ''}) async {
  await tester.enterText(find.byType(TextField).at(0), link);
  await tester.enterText(find.byType(TextField).at(1), name);
  await tester.pump();
  await _tapLabel(tester, 'Add');
}

CalendarData _calendar(ProviderContainer c) => c.read(calendarProvider);
CalendarInfo _feed(ProviderContainer c) => _calendar(c).calendars.singleWhere((x) => x.viewOnly);
List<CalEvent> _events(ProviderContainer c, String id) => [
  for (final e in _calendar(c).events)
    if (e.calendarId == id) e,
];

/// Lets the saves and the last message finish.
Future<void> _done(WidgetTester tester) => tester.pump(const Duration(seconds: 5));

void main() {
  setUpAll(loadAppFonts);

  testWidgets('Add a calendar link: read at once, view only, notes kept when it’s read again', (tester) async {
    final store = calendarStore();
    final feeds = FakeFeeds({_link: _ics()});
    final links = MemoryFeedLinks();
    final c = await pumpCalendar(tester, Routes.calendar, store: store, feeds: feeds, feedLinks: links);
    await _tapLabel(tester, 'Connect calendars');
    await _tapLabel(tester, 'Add a calendar link');
    expect(find.text('Add a calendar link'), findsWidgets);
    expect(find.textContaining('Secret address in iCal format'), findsOneWidget);
    await _addLink(tester, 'webcal://calendar.google.com/calendar/ical/sam%40gmail.com/private-1f2e3d/basic.ics');
    expect(find.text('Added “Classes” · view only'), findsOneWidget);

    // Named as the calendar names itself; the link kept apart, the file kept.
    final cal = _feed(c);
    expect((cal.name, cal.kind, cal.from, cal.fetchedAt, cal.error), ('Classes', CalendarKind.feed, FeedFrom.google, calendarNow.toUtc(), null));
    expect(links.links[cal.id], _link);
    expect(store.feeds[cal.id], _ics());
    expect(feeds.asked.single.toString(), _link);
    expect(find.bySemanticsLabel('Classes, Google'), findsOneWidget);
    expect(find.text('Updated just now'), findsOneWidget);

    // In the week: Monday and Friday (Wednesday taken off), and the break.
    expect(find.bySemanticsLabel('Office hours, 3:00–4:00'), findsNWidgets(2));
    expect(find.bySemanticsLabel('Fall break, all day'), findsOneWidget);
    final hours = _events(c, cal.id).singleWhere((e) => e.title == 'Office hours');
    expect(eventStart(_calendar(c), const [], hours.id, '2026-09-25'), DateTime(2026, 9, 25, 15));

    // View only, but it can have notes.
    await _tapLabel(tester, 'Office hours, 3:00–4:00');
    expect(find.text('Classes · Google Calendar'), findsOneWidget);
    expect(find.bySemanticsLabel('Change event'), findsNothing);
    expect(find.textContaining('View only. Change it in Google Calendar'), findsOneWidget);
    await _tapLabel(tester, 'Start notes');
    expect(find.byType(CanvasScreen), findsOneWidget);
    final link = _calendar(c).links[hours.id]!;
    expect(c.read(notebookProvider(link.notebookId)).notebook.title, 'Office hours');
    expect(_calendar(c).event(hours.id)!.notes, link);
    await _done(tester);

    // calendar.json: the link's calendar and the notes' link, not its events.
    final json = store.calendar!;
    expect([for (final e in json['events'] as List) (e as Map)['calendar']], isNot(contains(cal.id)));
    expect((json['links'] as Map)[hours.id], {'notebook': link.notebookId});
    expect(jsonEncode(json), isNot(contains('private-1f2e3d')), reason: 'the link is kept like a password');

    // Read again: a new event; the notes stay with theirs.
    feeds.files[_link] = _ics(review: true);
    expect(await c.read(feedSyncProvider.notifier).refresh(cal.id), isNull);
    expect(_events(c, cal.id).map((e) => e.title), unorderedEquals(['Office hours', 'Fall break', 'Midterm review']));
    expect(_calendar(c).event(hours.id)!.notes, link);

    // Offline: it says so, and keeps what it had.
    feeds.files.clear();
    expect(await c.read(feedSyncProvider.notifier).refresh(cal.id), FeedException.offline.message);
    expect(_feed(c).error, FeedException.offline.message);
    expect(_events(c, cal.id), hasLength(3));
    await _done(tester);
  });

  testWidgets('wrong links say why; the same link twice; Refresh; Remove', (tester) async {
    final store = calendarStore();
    final feeds = FakeFeeds({_link: _ics(), 'https://example.org/page': '<!doctype html><title>Sign in</title>'});
    final links = MemoryFeedLinks();
    final c = await pumpCalendar(tester, Routes.calendar, store: store, feeds: feeds, feedLinks: links);
    await _tapLabel(tester, 'Connect calendars');
    await _tapLabel(tester, 'Add a calendar link');
    await _addLink(tester, 'my calendar');
    expect(find.text(FeedException.notLink.message), findsOneWidget);
    await _addLink(tester, 'https://example.org/page');
    expect(find.text(FeedException.notCalendar.message), findsOneWidget);
    await _addLink(tester, 'https://example.org/away.ics');
    expect(find.text(FeedException.offline.message), findsOneWidget);
    expect(_calendar(c).calendars.where((x) => x.viewOnly), isEmpty);
    await _addLink(tester, _link, name: 'Mine');
    expect(_feed(c).name, 'Mine');

    await _tapLabel(tester, 'Add a calendar link');
    await _addLink(tester, _link);
    expect(find.text('That calendar is here already, as “Mine”.'), findsOneWidget);
    await _tapLabel(tester, 'Cancel');

    await _tapLabel(tester, 'Refresh');
    expect(find.text('Updated “Mine”'), findsOneWidget);
    feeds.files.clear();
    await _tapLabel(tester, 'Refresh');
    expect(find.text('Couldn’t update “Mine”. ${FeedException.offline.message}'), findsOneWidget);
    expect(find.text(FeedException.offline.message), findsOneWidget, reason: 'on its card');

    final id = _feed(c).id;
    await _tapLabel(tester, 'Remove');
    expect(find.text('Remove “Mine”?'), findsOneWidget);
    await _tapLabel(tester, 'Remove');
    expect(find.text('Removed “Mine”'), findsOneWidget);
    expect(_calendar(c).calendar(id), isNull);
    expect(_events(c, id), isEmpty);
    expect(links.links, isEmpty);
    expect(store.feeds, isEmpty);
    expect(find.bySemanticsLabel('Office hours, 3:00–4:00'), findsNothing);
    await _done(tester);
  });

  testWidgets('with the on-screen keyboard up, Add stays above it; Connect stays on screen', (tester) async {
    final c = await pumpCalendar(tester, Routes.calendar, feeds: FakeFeeds({_link: _ics()}));
    // Connect is at the end of the chips, on screen, however many there are.
    expect(tester.getRect(find.bySemanticsLabel('Connect calendars')).right, lessThanOrEqualTo(1280 - 24));
    await _tapLabel(tester, 'Connect calendars');
    await _tapLabel(tester, 'Add a calendar link');
    bool linkFocused() => tester.widget<EditableText>(find.byType(EditableText).at(0)).focusNode.hasFocus;
    expect(linkFocused(), isTrue);
    // The tablet's keyboard takes about half the screen.
    tester.view.viewInsets = const FakeViewPadding(bottom: 430);
    addTearDown(tester.view.resetViewInsets);
    await _settle(tester);
    expect(linkFocused(), isTrue, reason: 'making room mustn’t rebuild the field (the keyboard would close)');
    final add = tester.getRect(find.bySemanticsLabel('Add'));
    expect(add.bottom, lessThanOrEqualTo(800 - 430));
    expect(add.top, greaterThanOrEqualTo(0));
    expect(find.textContaining('Its events show here'), findsNothing, reason: 'the intro makes room');
    expect(tester.getRect(find.byType(TextField).at(0)).top, greaterThanOrEqualTo(0), reason: 'the link field shows too');
    await tester.enterText(find.byType(TextField).at(0), _link);
    await tester.pump();
    await _tapLabel(tester, 'Add');
    expect(_feed(c).name, 'Classes');
    await _done(tester);
  });

  testWidgets('at start: the copy kept shows offline; read again when it can be', (tester) async {
    final store = calendarStore();
    final json = store.calendar!;
    (json['calendars'] as List).insert(3, {
      'id': 'cal_link',
      'name': 'Classes',
      'kind': 'feed',
      'hue': 'clay',
      'from': 'google',
      'fetchedAt': DateTime.utc(2026, 9, 24, 8).toIso8601String(),
    });
    store.feeds['cal_link'] = _ics();
    final feeds = FakeFeeds();
    final links = MemoryFeedLinks()..links['cal_link'] = _link;
    final c = await pumpCalendar(tester, Routes.calendar, store: store, feeds: feeds, feedLinks: links);
    await _settle(tester);
    expect(find.bySemanticsLabel('Office hours, 3:00–4:00'), findsNWidgets(2));
    expect(feeds.asked, isNotEmpty, reason: 'read again at start');
    expect(_feed(c).error, FeedException.offline.message);
    expect(_feed(c).fetchedAt, DateTime.utc(2026, 9, 24, 8));

    feeds.files[_link] = _ics(review: true);
    await c.read(feedSyncProvider.notifier).refreshAll(olderThan: Duration.zero);
    await _settle(tester);
    expect(_feed(c).error, isNull);
    expect(_feed(c).fetchedAt, calendarNow.toUtc());
    expect(find.bySemanticsLabel('Midterm review, 6:00–7:00'), findsOneWidget);
    expect(store.feeds['cal_link'], _ics(review: true));
    await _done(tester);
  });
}
