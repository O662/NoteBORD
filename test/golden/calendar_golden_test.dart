// Golden images of Phase 7c at the tablet size (1280×800). Compare with
// design/screens/Calendar.png, Planner.png and WidgetBoard.png.
//
// Regenerate after an intended visual change:
//   flutter test --update-goldens test/golden/calendar_golden_test.dart
@Tags(['golden'])
library;

import 'package:endless/app.dart';
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
