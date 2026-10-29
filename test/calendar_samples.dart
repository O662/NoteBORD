import 'dart:io';

import 'package:endless/app.dart';
import 'package:endless/board/codec.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/calendar/calendar_model.dart';
import 'package:endless/canvas/live_items.dart' show liveNow;
import 'package:endless/planner/planner_model.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/study/remember.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:flutter/material.dart' show Brightness;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'study/study_samples.dart';

// The design's sample data for the calendar and the planner
// (Calendar.dc.html, Planner.dc.html, WidgetBoard.dc.html): the week of
// Sep 21, 2026, on Friday the 25th at 1:30 PM.

/// Calendar.png's "now".
final calendarNow = DateTime(2026, 9, 25, 13, 30);

DateTime _at(int day, double hour) => DateTime(2026, 9, day, hour.floor(), ((hour - hour.floor()) * 60).round());

CalEvent _ev(String id, String cal, String title, int day, double from, double to, {NoteLink? notes}) => CalEvent(
      id: id,
      calendarId: cal,
      title: title,
      start: _at(day, from).toUtc(),
      end: _at(day, to).toUtc(),
      notes: notes,
    );

/// School and Personal (Google), Work (Outlook) and the note deadlines,
/// with Calendar.dc.html's events.
CalendarData calendarSample() => CalendarData(
      calendars: const [
        CalendarInfo(id: 'school', name: 'School', kind: CalendarKind.google, account: 'sam@gmail.com', remoteId: 'school@group'),
        CalendarInfo(id: 'personal', name: 'Personal', kind: CalendarKind.google, hue: CalendarHue.green, account: 'sam@gmail.com', remoteId: 'primary'),
        CalendarInfo(id: 'work', name: 'Work', kind: CalendarKind.outlook, hue: CalendarHue.clay, account: 'sam@work.example', remoteId: 'AAMk'),
        CalendarInfo(id: CalendarInfo.deadlinesId, name: 'Note deadlines', kind: CalendarKind.deadlines, hue: CalendarHue.plum),
      ],
      events: [
        _ev('ev_phys_mon', 'school', 'Physics lecture', 21, 10, 11.25, notes: const NoteLink('nb_phys', pageId: 'pp_1')),
        _ev('ev_team', 'work', 'Team meeting', 21, 13, 14),
        _ev('ev_calc_tue', 'school', 'Calculus II', 22, 9, 10.5, notes: const NoteLink('nb_calc')),
        _ev('ev_check', 'work', 'Check-in', 22, 15, 15.5),
        _ev('ev_phys_wed', 'school', 'Physics lecture', 23, 10, 11.25, notes: const NoteLink('nb_phys', pageId: 'pp_2')),
        _ev('ev_lab', 'school', 'Lab 4', 23, 15, 17, notes: const NoteLink('nb_lab')),
        _ev('ev_calc_thu', 'school', 'Calculus II', 24, 9, 10.5),
        _ev('ev_phys_fri', 'school', 'Physics lecture', 25, 10, 11.25, notes: const NoteLink('nb_phys', pageId: 'pg_phys')),
        _ev('ev_lunch', 'personal', 'Lunch', 25, 12.25, 13),
        _ev('ev_study', 'school', 'Study group', 25, 14, 15),
        _ev('ev_gym', 'personal', 'Gym', 24, 17, 18),
        _ev('ev_garden', 'personal', 'Garden', 26, 11, 12),
      ],
    );

/// Study.png's notebooks and decks (Physics — Momentum has 5 cards due),
/// with Calendar.png's calendars, a deadline written in Calculus II and
/// Planner.png's day.
MemoryBoardStore calendarStore({bool planner = true}) {
  final store = studySample(now: calendarNow.toUtc());
  // "Problem set 4 due Sep 27", typed on Calculus II's page.
  final calc = store.pages['nb_calc']!;
  final page = decodePage(calc['pg_calc']!);
  store.savePage(
    'nb_calc',
    BoardPage(id: page.id, items: [
      ...page.items,
      sampleText('t_due', 'Problem set 4 due Sep 27', at: const Offset(100, 700), typed: true),
    ]),
  );
  store.calendar = calendarSample().toJson();
  if (planner) store.planner = plannerSample().toJson();
  store.pageWrites = 0;
  return store;
}

/// Lines of real handwriting (the owner's page from the tablet), each from
/// its own top-left.
List<List<StrokeItem>> handLines() {
  final page = decodePage(File('test/fixtures/recognition/tablet_2026-10-15.json').readAsStringSync());
  final strokes = [for (final i in page.items) if (i is StrokeItem) i]..sort((a, b) => a.bounds.center.dy.compareTo(b.bounds.center.dy));
  final lines = <List<StrokeItem>>[];
  for (final s in strokes) {
    if (lines.isEmpty || s.bounds.center.dy - lines.last.last.bounds.center.dy > 40) {
      lines.add([s]);
    } else {
      lines.last.add(s);
    }
  }
  return [for (final l in lines) _moved(l, 1)];
}

/// [ink] from its own top-left, scaled by [k].
List<StrokeItem> _moved(List<StrokeItem> ink, double k, {Offset to = Offset.zero}) {
  var r = ink.first.bounds;
  for (final s in ink) {
    r = r.expandToInclude(s.bounds);
  }
  return [
    for (final s in ink)
      StrokeItem.fromPagePoints(
        id: s.id,
        z: s.z,
        createdAt: s.createdAt,
        tool: s.tool,
        penType: s.penType,
        color: s.color,
        width: s.width * k,
        usePressure: s.usePressure,
        pagePoints: [for (final p in s.pageInk) InkPoint((p.x - r.left) * k + to.dx, (p.y - r.top) * k + to.dy, p.pressure, p.t)],
      ),
  ];
}

/// A line of handwriting [height] tall, at [at].
List<StrokeItem> handLine(int i, {double height = 26, Offset at = Offset.zero}) {
  final line = handLines()[i % handLines().length];
  var r = line.first.bounds;
  for (final s in line) {
    r = r.expandToInclude(s.bounds);
  }
  return _moved(line, height / r.height, to: at);
}

/// Planner.png on Friday the 25th: the top 3 (the second done), the to-dos
/// (Review flashcards done and blocked 11:30–12:00), Lab report draft
/// blocked 3:30–5:00, notes for today, and Flashcards · 20 min tomorrow.
PlannerData plannerSample() {
  final made = DateTime.utc(2026, 9, 24, 18);
  final fri = DateTime(2026, 9, 25), sat = DateTime(2026, 9, 26);
  PlanTask task(String id, String text, {DateTime? day, int? start, int minutes = 60, bool done = false, String? deck}) => PlanTask(
        id: id,
        text: text,
        day: day,
        start: start,
        minutes: minutes,
        done: done,
        deckId: deck,
        createdAt: made,
        doneAt: done ? DateTime.utc(2026, 9, 25, 16) : null,
      );
  return PlannerData(
    tasks: [
      task('td_cards', 'Review flashcards', day: fri, start: 11 * 60 + 30, minutes: 30, done: true, deck: 'dk_mom'),
      task('td_read', 'Read ch. 9 (p. 214–230)'),
      task('td_ps4', 'Problem set 4, Q1–5'),
      task('td_email', 'Email lab partner'),
      task('td_print', 'Print formula sheet'),
      task('td_lab', 'Lab report draft', day: fri, start: 15 * 60 + 30, minutes: 90),
      task('td_sat', 'Flashcards', day: sat, start: 14 * 60, minutes: 20, deck: 'dk_mom'),
    ],
    days: {
      dayKey(fri): PlanDay(
        top: [
          TopLine(ink: handLine(0, height: 26, at: const Offset(4, 8))),
          TopLine(ink: handLine(1, height: 24, at: const Offset(4, 9)), done: true),
          TopLine(ink: handLine(2, height: 26, at: const Offset(4, 8))),
        ],
        notes: [
          ...handLine(3, height: 26, at: const Offset(2, 4)),
          ...handLine(4, height: 26, at: const Offset(2, 36)),
          ...handLine(5, height: 26, at: const Offset(2, 68)),
        ],
      ),
    },
  );
}

/// The app on [location] with Calendar.png's data, at 1:30 PM on Friday
/// Sep 25, with every notebook read into the index.
Future<ProviderContainer> pumpCalendar(WidgetTester tester, String location, {MemoryBoardStore? store, bool dark = false}) async {
  tester.view.physicalSize = tokens.Sizes.tabletFrame;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.platformBrightnessTestValue = dark ? Brightness.dark : Brightness.light;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  liveNow = () => calendarNow;
  addTearDown(() => liveNow = DateTime.now);
  final overrides = await testOverrides(store ?? calendarStore(), location: location, clock: () => calendarNow);
  await tester.pumpWidget(ProviderScope(overrides: overrides, child: const EndlessApp()));
  await tester.pump();
  final c = ProviderScope.containerOf(tester.element(find.byType(EndlessApp)));
  await indexAll(tester, c);
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  return c;
}

/// WidgetBoard.png's "Study plan" (in School): the title, the calendar,
/// planner, Physics — Momentum and Need to remember widgets, a sticky note
/// and notes. Its second page holds the three things to remember.
MemoryBoardStore widgetBoardStore() {
  final store = calendarStore();
  final made = DateTime.utc(2026, 9, 24, 18);
  final blue = tokens.inkDefaults[1], clay = tokens.inkDefaults[2];
  LiveItem widget(String id, double x, double y, LiveData data) => LiveItem(id: id, x: x, y: y, z: 10, createdAt: made, data: data);
  final board = BoardPage(id: 'pg_board', items: [
    sampleText('t_title', 'Midterm prep — this week', at: const Offset(110, 90), size: 46, color: blue),
    widget('w_cal', 110, 202, const CalendarWidgetData()),
    widget('w_plan', 512, 160, const PlannerWidgetData()),
    widget('w_cards', 994, 160, const FlashcardsWidgetData(deck: 'dk_mom', deckName: 'Physics — Momentum')),
    widget('w_rem', 700, 562, const RememberWidgetData(folder: ['School'])),
    sampleText('t_sun', 'Sunday = rest day :)\nask Maya about lab data', at: const Offset(340, 586), size: 34),
    sampleText('t_bus', 'do these on\nthe bus!', at: const Offset(1000, 466), size: 30, color: clay),
  ]);
  Json mark(String id, {DateTime? remindAt, int day = 20}) => RememberMark(
        id: id,
        remind: remindAt == null ? RemindKind.none : RemindKind.date,
        remindAt: remindAt,
        at: DateTime.utc(2026, 9, day, 12),
      ).toJson();
  final things = BoardPage(id: 'pg_things', items: [
    withRemember(sampleText('t_mom', 'total momentum is conserved', at: const Offset(100, 100), size: 34), mark('rm_mom', day: 22)),
    withRemember(
      sampleText('t_lab', 'Lab report due Sep 30, 11:59 PM — submit as PDF', at: const Offset(100, 200), typed: true, size: 16),
      mark('rm_lab', remindAt: DateTime(2026, 9, 29, 18).toUtc(), day: 21),
    ),
    withRemember(sampleText('t_j', 'J = F · t = p₂ − p₁', at: const Offset(100, 300), size: 40), mark('rm_j')),
  ]);
  final nb = Notebook(
    id: 'nb_plan',
    title: 'Study plan',
    folderPath: const ['School'],
    createdAt: made,
    updatedAt: made,
    pageIds: [board.id, things.id],
  );
  store.saveNotebook(nb);
  store.savePage(nb.id, board);
  store.savePage(nb.id, things);
  store.settings = AppSettings(pagesOpen: false, mapOpen: false, trayOpen: false).toJson();
  store.pageWrites = 0;
  return store;
}
