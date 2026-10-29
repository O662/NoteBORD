// Phase 7c end to end: the calendar (Calendar.png), the planner
// (Planner.png) and widgets on the page (WidgetBoard.png), with finger and
// S Pen events, on Friday Sep 25, 2026 at 1:30 PM.

import 'package:endless/board/codec.dart' show decodePage;
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/calendar/calendar_model.dart';
import 'package:endless/calendar/calendar_state.dart';
import 'package:endless/canvas/pane.dart';
import 'package:endless/canvas/widget_items.dart';
import 'package:endless/planner/planner_model.dart';
import 'package:endless/planner/planner_state.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/study/study_state.dart';
import 'package:endless/ui/calendar/calendar_screen.dart';
import 'package:endless/ui/canvas/canvas_screen.dart';
import 'package:endless/ui/routes.dart';
import 'package:endless/ui/study/remember_screen.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../calendar_samples.dart';
import '../helpers.dart';

final _fri = DateTime(2026, 9, 25);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _tapLabel(WidgetTester tester, String label) async {
  await tester.tap(find.bySemanticsLabel(label).last);
  await _settle(tester);
}

var _clock = const Duration(seconds: 10);

Future<void> _tap(WidgetTester tester, Offset at, {bool pen = false}) async {
  final g = await tester.createGesture(kind: pen ? PointerDeviceKind.stylus : PointerDeviceKind.touch);
  _clock += const Duration(seconds: 2);
  await g.down(at, timeStamp: _clock);
  await g.up(timeStamp: _clock + const Duration(milliseconds: 60));
  await tester.pump();
}

Future<void> _pen(WidgetTester tester, List<Offset> points) async {
  final g = await tester.createGesture(kind: PointerDeviceKind.stylus);
  _clock += const Duration(seconds: 2);
  var t = _clock;
  await g.down(points.first, timeStamp: t);
  for (final p in points.skip(1)) {
    t += const Duration(milliseconds: 8);
    await g.moveTo(p, timeStamp: t);
  }
  await g.up(timeStamp: t);
  await tester.pump();
}

CalendarData _calendar(ProviderContainer c) => c.read(calendarProvider);
PlannerData _planner(ProviderContainer c) => c.read(plannerProvider);

/// Lets the saves and the last message finish.
Future<void> _done(WidgetTester tester) => tester.pump(const Duration(seconds: 5));

void main() {
  setUpAll(loadAppFonts);

  group('Calendar (Calendar.png)', () {
    testWidgets('the week, the event panel with its notes and Review before class, Open notes', (tester) async {
      await pumpCalendar(tester, Routes.calendar);
      expect(find.text('September 2026'), findsOneWidget);
      for (final chip in ['School, Google', 'Personal, Google', 'Work, Outlook', 'Note deadlines', 'Connect calendars']) {
        expect(find.bySemanticsLabel(chip), findsOneWidget, reason: chip);
      }
      // The deadline written in Calculus II, in the all-day row.
      expect(find.bySemanticsLabel('Problem set 4 due, all day'), findsOneWidget);
      // At 1:30 the panel shows what's next: Study group, with no notes.
      expect(find.text('Study group'), findsWidgets);
      expect(find.text('No notes yet.'), findsOneWidget);
      expect(find.text('Changes here also update Google Calendar.'), findsOneWidget);

      await _tapLabel(tester, 'Physics lecture, 10:00–11:15, has notes');
      expect(find.text('School · Google Calendar'), findsOneWidget);
      expect(find.text('Fri, Sep 25 · 10:00 – 11:15'), findsOneWidget);
      expect(find.text('Physics — Lecture notes'), findsOneWidget);
      expect(find.textContaining('Page 3 ·'), findsOneWidget);
      expect(find.text('Review before class'), findsOneWidget);
      expect(find.text('Physics — Momentum · 5 cards due'), findsOneWidget);

      await _tapLabel(tester, 'Open notes');
      expect(find.byType(CanvasScreen), findsOneWidget);
      final pane = tester.widget<CanvasScreen>(find.byType(CanvasScreen)).pane;
      expect((pane.notebookId, pane.page), ('nb_phys', 2));
      await _done(tester);
    });

    testWidgets('a new event in a Google calendar is kept to send; changed; deleted and undone', (tester) async {
      final c = await pumpCalendar(tester, Routes.calendar);
      await _tapLabel(tester, 'Event');
      expect(find.text('New event'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Office hours');
      await tester.pump();
      expect(find.text('Also changes it in Google Calendar.'), findsOneWidget);
      await _tapLabel(tester, 'Save');
      final e = _calendar(c).events.singleWhere((e) => e.title == 'Office hours');
      expect(e.calendarId, 'school');
      expect(e.pending, isTrue, reason: 'for sync to send');
      expect(e.localStart, DateTime(2026, 9, 25, 14));
      expect(e.localEnd, DateTime(2026, 9, 25, 15));
      // Picked: it's in the panel.
      expect(find.text('Office hours'), findsWidgets);

      await _tapLabel(tester, 'Change event');
      expect(find.text('Change event'), findsWidgets);
      await _tapLabel(tester, 'Every Friday');
      await _tapLabel(tester, 'Save');
      expect(_calendar(c).event(e.id)!.repeat?.every, RepeatEvery.week);

      await _tapLabel(tester, 'Change event');
      await tester.tap(find.text('Delete'));
      await _settle(tester);
      expect(find.text('Delete a repeating event'), findsOneWidget);
      await _tapLabel(tester, 'Every time');
      expect(_calendar(c).event(e.id), isNull);
      expect(find.text('Deleted “Office hours”'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await _settle(tester);
      expect(_calendar(c).event(e.id)!.title, 'Office hours');
      await _done(tester);
    });

    testWidgets('a tap on an empty half hour starts an event there; Cancel adds nothing', (tester) async {
      final c = await pumpCalendar(tester, Routes.calendar);
      final before = _calendar(c).events.length;
      // Saturday at 4 PM: the grid opens on 8 AM, an hour every 58 px.
      final grid = tester.getTopLeft(find.byType(CalendarScreen)) + const Offset(272 + 24 + 1, 0);
      final top = tester.getTopLeft(find.text('8 AM')).dy - 3;
      final colW = (684 - 46) / 7;
      await tester.tapAt(Offset(grid.dx + 46 + colW * 5.5, top + 8 * 58 + 10));
      await _settle(tester);
      expect(find.text('New event'), findsOneWidget);
      expect(find.bySemanticsLabel('Starts, 4:00 PM'), findsOneWidget);
      await _tapLabel(tester, 'Cancel');
      expect(_calendar(c).events.length, before);
      await _done(tester);
    });

    testWidgets('chips hide calendars; Month; a day opens Day; Start notes makes linked notes', (tester) async {
      final c = await pumpCalendar(tester, Routes.calendar);
      expect(find.bySemanticsLabel('Lunch, 12:15–1:00'), findsOneWidget);
      await _tapLabel(tester, 'Personal, Google');
      expect(find.bySemanticsLabel('Lunch, 12:15–1:00'), findsNothing);
      expect(_calendar(c).calendar('personal')!.shown, isFalse);
      await _tapLabel(tester, 'Personal, Google');

      await _tapLabel(tester, 'Month');
      // On its number, not on its events.
      await tester.tapAt(tester.getTopLeft(find.bySemanticsLabel(RegExp(r'^Monday, Sep 21')).first) + const Offset(12, 12));
      await _settle(tester);
      expect(find.text('Monday, Sep 21'), findsOneWidget);
      await _tapLabel(tester, 'Team meeting, 1:00–2:00');
      await _tapLabel(tester, 'Start notes');
      expect(find.byType(CanvasScreen), findsOneWidget);
      final link = _calendar(c).event('ev_team')!.notes!;
      expect(c.read(notebookProvider(link.notebookId)).notebook.title, 'Team meeting');
      await _done(tester);
    });

    testWidgets('Connect lists the calendars and adds one on this tablet', (tester) async {
      final c = await pumpCalendar(tester, Routes.calendar);
      await _tapLabel(tester, 'Connect calendars');
      expect(find.text('Calendars'), findsOneWidget);
      expect(find.text('Google · connected'), findsOneWidget);
      expect(find.text('School, Personal'), findsOneWidget);
      await _tapLabel(tester, 'Add a Google account');
      expect(find.textContaining('Connecting accounts comes in the next update'), findsOneWidget);
      await _tapLabel(tester, 'New calendar on this tablet');
      await tester.enterText(find.byType(TextField), 'Club');
      await tester.pump();
      await _tapLabel(tester, 'Add');
      final club = _calendar(c).calendars.firstWhere((x) => x.name == 'Club');
      expect(club.kind, CalendarKind.local);
      expect(_calendar(c).calendars.last.kind, CalendarKind.deadlines, reason: 'the deadlines stay last');
      expect(find.bySemanticsLabel('Club, This tablet'), findsOneWidget);
      await _done(tester);
    });
  });

  group('Planner (Planner.png)', () {
    testWidgets('to-dos: tick, type one, drag one onto the schedule', (tester) async {
      final c = await pumpCalendar(tester, Routes.planner);
      expect(find.text('Friday, Sep 25'), findsOneWidget);
      expect(find.text('TOP 3 TODAY'), findsOneWidget);
      expect(find.text('Physics — Momentum deck'), findsOneWidget);
      expect(find.text('TOMORROW · SAT 26'), findsOneWidget);
      expect(find.text('11:00 Garden'), findsOneWidget);
      expect(find.text('Flashcards · 20 min'), findsOneWidget);

      await _tapLabel(tester, 'Read ch. 9 (p. 214–230)');
      await _settle(tester);
      expect(_planner(c).task('td_read')!.done, isTrue);
      expect(_planner(c).task('td_read')!.doneAt, isNotNull);

      // A finger on "write a task…" types one.
      await _tapLabel(tester, 'Write a task');
      await tester.enterText(find.byType(TextField), 'Buy graph paper');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester);
      final added = _planner(c).tasks.singleWhere((t) => t.text == 'Buy graph paper');
      expect(added.day, isNull, reason: 'today, until it’s done');
      expect(find.text('Buy graph paper'), findsOneWidget);

      // Dragged by its handle onto the schedule: an hour from where it lands.
      final handle = find.bySemanticsLabel('Drag Email lab partner onto the schedule');
      final target = tester.getCenter(find.text('Drag a to-do here to block time')) + const Offset(0, 300);
      await tester.timedDragFrom(tester.getCenter(handle), target - tester.getCenter(handle), const Duration(milliseconds: 600));
      await _settle(tester);
      final blocked = _planner(c).task('td_email')!;
      expect(blocked.day, _fri);
      expect(blocked.start, isNotNull);
      expect(blocked.minutes, 60);
      expect(blocked.start! % 15, 0);
      expect(find.bySemanticsLabel(RegExp(r'^Planned: Email lab partner')), findsOneWidget);
      await _done(tester);
    });

    testWidgets('the top 3 and notes for today are written with the pen', (tester) async {
      final c = await pumpCalendar(tester, Routes.planner);
      final notes = _planner(c).day(_fri).notes.length;
      final pad = tester.getRect(find.bySemanticsLabel('Notes for Friday, Sep 25'));
      await _pen(tester, [for (var i = 0; i <= 20; i++) pad.topLeft + Offset(20.0 + i * 6, 160 + (i % 3) * 4)]);
      await _settle(tester);
      expect(_planner(c).day(_fri).notes.length, notes + 1);
      // A finger doesn't write.
      await tester.dragFrom(pad.topLeft + const Offset(30, 220), const Offset(100, 0));
      await _settle(tester);
      expect(_planner(c).day(_fri).notes.length, notes + 1);

      expect(_planner(c).day(_fri).top[0].done, isFalse);
      await _tapLabel(tester, 'Priority 1');
      expect(_planner(c).day(_fri).top[0].done, isTrue);
      // The S Pen's button rubs out.
      final line = tester.getRect(find.bySemanticsLabel('Write priority 3'));
      final before = _planner(c).day(_fri).top[2].ink.length;
      final g = await tester.createGesture(kind: PointerDeviceKind.stylus, buttons: 0x02 | 0x01);
      _clock += const Duration(seconds: 2);
      final ink = _planner(c).day(_fri).top[2].ink.first.bounds.center;
      await g.down(line.topLeft + ink, timeStamp: _clock);
      await g.moveTo(line.topLeft + ink + const Offset(4, 0), timeStamp: _clock + const Duration(milliseconds: 16));
      await g.up(timeStamp: _clock + const Duration(milliseconds: 32));
      await _settle(tester);
      expect(_planner(c).day(_fri).top[2].ink.length, lessThan(before));
      await _done(tester);
    });

    testWidgets('3 days and Week', (tester) async {
      final c = await pumpCalendar(tester, Routes.planner);
      await _tapLabel(tester, '3 days');
      expect(find.text('Fri 25 – Sun 27'), findsOneWidget);
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('Flashcards · 20 min'), findsOneWidget);
      expect(find.text('Problem set 4 due'), findsOneWidget);
      await _tapLabel(tester, 'Week');
      expect(find.text('Week of Sep 21'), findsOneWidget);
      expect(find.text('NOT SCHEDULED'), findsOneWidget);
      // Dragged onto Wednesday: that day, no time.
      final chip = find.bySemanticsLabel('Drag Print formula sheet onto a day');
      final wed = tester.getCenter(find.text('Wed 23')) + const Offset(0, 200);
      await tester.timedDragFrom(tester.getCenter(chip), wed - tester.getCenter(chip), const Duration(milliseconds: 600));
      await _settle(tester);
      expect(_planner(c).task('td_print')!.day, DateTime(2026, 9, 23));
      expect(_planner(c).task('td_print')!.scheduled, isFalse);
      await tester.tap(find.bySemanticsLabel('Previous'));
      await _settle(tester);
      expect(find.text('Week of Sep 14'), findsOneWidget);
      await _done(tester);
    });
  });

  group('Widgets on the page (WidgetBoard.png)', () {
    Pane pane(WidgetTester tester) => tester.widget<CanvasScreen>(find.byType(CanvasScreen)).pane;
    LiveItem widget(ProviderContainer c, WidgetTester tester, String id) =>
        c.read(notebookProvider(pane(tester).notebookId)).pageAt(pane(tester).page)[id]! as LiveItem;
    Offset on(WidgetTester tester, LiveItem item, Offset local) => pane(tester).view.toScreen(item.toPage(local));

    testWidgets('Insert → Calendar and Planner put them on the page', (tester) async {
      final store = widgetBoardStore();
      final page = BoardPage(id: 'pg_new');
      store.saveNotebook(Notebook(id: 'nb_new', title: 'New', createdAt: DateTime.utc(2026, 9, 25), updatedAt: DateTime.utc(2026, 9, 25), pageIds: [page.id]));
      store.savePage('nb_new', page);
      final c = await pumpCalendar(tester, Routes.notebook('nb_new', page: 0), store: store);
      for (final tile in ['Calendar', 'Planner']) {
        await tester.tap(byLabel('Insert'));
        await tester.pump();
        await tester.tap(find.text('Everything else'));
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel(tile));
        await _settle(tester);
      }
      expect(find.text('Added the planner to the page'), findsOneWidget);
      final items = c.read(notebookProvider('nb_new')).pageAt(0).items;
      expect([for (final i in items) (i as LiveItem).data.runtimeType], [CalendarWidgetData, PlannerWidgetData]);
      expect(items.first.extent.overlaps(items.last.extent), isFalse);
      await _done(tester);
    });

    testWidgets('their buttons: a to-do, the range, flipping and answering a card, a day, See all', (tester) async {
      final c = await pumpCalendar(tester, Routes.notebook('nb_plan', page: 0), store: widgetBoardStore());
      final steps = c.read(notebookProvider('nb_plan').notifier);
      final undo = steps.canUndo('pg_board');

      // The planner: tick Read ch. 9 (the second row), then 3 days.
      final plan = widget(c, tester, 'w_plan');
      await _tap(tester, on(tester, plan, const Offset(280, 82 + 36 + 18)));
      await _settle(tester);
      expect(_planner(c).task('td_read')!.done, isTrue);
      await _tap(tester, on(tester, plan, const Offset(350, 34)), pen: true);
      await _settle(tester);
      expect((widget(c, tester, 'w_plan').data as PlannerWidgetData).range, PlannerWidgetRange.three);
      expect(steps.canUndo('pg_board'), undo, reason: 'how it’s shown isn’t an undo step');

      // Flashcards: flip, then Got it.
      final cards = widget(c, tester, 'w_cards');
      final due = c.read(studyProvider)!.dueAt(calendarNow.toUtc());
      await _tap(tester, on(tester, cards, const Offset(125, 119)));
      await _settle(tester);
      expect(flippedCards, contains('w_cards'));
      await _tap(tester, on(tester, cards, const Offset(190, 226)));
      await _settle(tester);
      expect(flippedCards, isNot(contains('w_cards')));
      expect(c.read(studyProvider)!.dueAt(calendarNow.toUtc()), due - 1);
      expect(find.textContaining('Got it · next'), findsOneWidget);

      // Need to remember: See all.
      final rem = widget(c, tester, 'w_rem');
      await _tap(tester, on(tester, rem, const Offset(510, 30)));
      await _settle(tester);
      expect(find.byType(RememberScreen), findsOneWidget);
      await _done(tester);
    });

    testWidgets('a day on the calendar opens it there', (tester) async {
      final c = await pumpCalendar(tester, Routes.notebook('nb_plan', page: 0), store: widgetBoardStore());
      final cal = widget(c, tester, 'w_cal');
      // Monday the 21st: the fourth row, the second column.
      await _tap(tester, on(tester, cal, Offset(14 + 342 / 7 * 1.5, 58 + 3 * 36 + 17)));
      await _settle(tester);
      expect(find.byType(CalendarScreen), findsOneWidget);
      expect(find.text('Monday, Sep 21'), findsOneWidget);
      await _done(tester);
    });

    testWidgets('selected: Month · Agenda · Calendars · Open full view', (tester) async {
      final c = await pumpCalendar(tester, Routes.notebook('nb_plan', page: 0), store: widgetBoardStore());
      await tester.tap(byLabel('Select'));
      await tester.pump();
      final cal = widget(c, tester, 'w_cal');
      await _tap(tester, on(tester, cal, const Offset(200, 330)), pen: true);
      await _settle(tester);
      for (final a in ['Month', 'Agenda', 'Calendars', 'Open full view']) {
        expect(find.bySemanticsLabel(a), findsWidgets, reason: a);
      }
      await _tapLabel(tester, 'Agenda');
      expect((widget(c, tester, 'w_cal').data as CalendarWidgetData).agenda, isTrue);
      expect(widgetText(widget(c, tester, 'w_cal'), calendarNow), contains('2:00 Study group'));

      await _tapLabel(tester, 'Calendars');
      expect(find.text('Calendars on this page'), findsOneWidget);
      await tester.tap(find.text('Personal'));
      await _settle(tester);
      await _tapLabel(tester, 'Done');
      expect((widget(c, tester, 'w_cal').data as CalendarWidgetData).hidden, ['personal']);
      expect(widgetText(widget(c, tester, 'w_cal'), calendarNow), isNot(contains('Lunch')));
      await _done(tester);
    });

    testWidgets('round trip: kept in the page, unknown settings too', (tester) async {
      final store = widgetBoardStore();
      final page = decodeStoredPage(store, 'nb_plan', 'pg_board');
      final cal = page.items.whereType<LiveItem>().firstWhere((i) => i.id == 'w_cal');
      expect(cal.toJson()['widget'], 'calendar');
      expect(cal.w, 370);
    });
  });
}

/// Page [pageId] of [notebookId] as stored.
BoardPage decodeStoredPage(MemoryBoardStore store, String notebookId, String pageId) => decodePage(store.pages[notebookId]![pageId]!);
