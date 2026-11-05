// Golden images of Phase 7c at the tablet size (1280×800). Compare with
// design/screens/Calendar.png, Planner.png and WidgetBoard.png.
//
// Regenerate after an intended visual change:
//   flutter test --update-goldens test/golden/calendar_golden_test.dart
@Tags(['golden'])
library;

import 'package:endless/app.dart';
import 'package:endless/calendar/feed_sync.dart' show MemoryFeedLinks;
import 'package:endless/ui/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../calendar_samples.dart';
import '../helpers.dart';

Future<void> _withShadows(Future<void> Function() body) async {
  debugDisableShadows = false;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
  }
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('calendar', (tester) => _withShadows(() async {
        await pumpCalendar(tester, Routes.calendar);
        await expectLater(find.byType(EndlessApp), matchesGoldenFile('calendar.png'));
      }));

  testWidgets('calendar_dark', (tester) => _withShadows(() async {
        await pumpCalendar(tester, Routes.calendar, dark: true);
        await expectLater(find.byType(EndlessApp), matchesGoldenFile('calendar_dark.png'));
      }));

  testWidgets('calendar_month', (tester) => _withShadows(() async {
        await pumpCalendar(tester, Routes.calendar);
        await tester.tap(find.bySemanticsLabel('Month'));
        await tester.pump();
        await expectLater(find.byType(EndlessApp), matchesGoldenFile('calendar_month.png'));
      }));

  testWidgets('calendar_connect', (tester) => _withShadows(() async {
        // Two calendar links: Classes read just now, Team not reachable.
        final store = calendarStore();
        final calendars = store.calendar!['calendars'] as List;
        for (final (i, (id, name, from)) in [('cal_classes', 'Classes', 'google'), ('cal_team', 'Team', 'outlook')].indexed) {
          calendars.insert(3 + i, {'id': id, 'name': name, 'kind': 'feed', 'hue': i == 0 ? 'blue' : 'green', 'from': from});
          store.feeds[id] = [
            'BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:x', //
            'BEGIN:VEVENT', 'UID:$id', 'DTSTAMP:20260901T000000Z', 'DTSTART:20260922T${i == 0 ? '13' : '11'}0000',
            'DTEND:20260922T${i == 0 ? '14' : '12'}0000', 'RRULE:FREQ=WEEKLY;BYDAY=TU,TH', 'SUMMARY:${i == 0 ? 'Office hours' : 'Standup'}',
            'END:VEVENT', 'END:VCALENDAR',
          ].join('\r\n');
        }
        final feeds = FakeFeeds({'https://calendar.google.com/x/basic.ics': store.feeds['cal_classes']!});
        final links = MemoryFeedLinks()
          ..links['cal_classes'] = 'https://calendar.google.com/x/basic.ics'
          ..links['cal_team'] = 'https://outlook.office365.com/x/calendar.ics';
        await pumpCalendar(tester, Routes.calendar, store: store, feeds: feeds, feedLinks: links);
        await tester.tap(find.bySemanticsLabel('Connect calendars'));
        await tester.pump();
        await expectLater(find.byType(EndlessApp), matchesGoldenFile('calendar_connect.png'));
      }));

  testWidgets('planner', (tester) => _withShadows(() async {
        await pumpCalendar(tester, Routes.planner);
        await expectLater(find.byType(EndlessApp), matchesGoldenFile('planner.png'));
      }));

  testWidgets('planner_three', (tester) => _withShadows(() async {
        await pumpCalendar(tester, Routes.planner);
        await tester.tap(find.bySemanticsLabel('3 days'));
        await tester.pump();
        await expectLater(find.byType(EndlessApp), matchesGoldenFile('planner_three.png'));
      }));

  testWidgets('planner_week', (tester) => _withShadows(() async {
        await pumpCalendar(tester, Routes.planner);
        await tester.tap(find.bySemanticsLabel('Week'));
        await tester.pump();
        await expectLater(find.byType(EndlessApp), matchesGoldenFile('planner_week.png'));
      }));

  testWidgets('widget_board', (tester) => _withShadows(() async {
        await pumpCalendar(tester, Routes.notebook('nb_plan', page: 0), store: widgetBoardStore());
        await expectLater(find.byType(EndlessApp), matchesGoldenFile('widget_board.png'));
      }));

  testWidgets('widget_board_dark', (tester) => _withShadows(() async {
        await pumpCalendar(tester, Routes.notebook('nb_plan', page: 0), store: widgetBoardStore(), dark: true);
        await expectLater(find.byType(EndlessApp), matchesGoldenFile('widget_board_dark.png'));
      }));
}
