import 'dart:math' as math;
import 'dart:ui' show Brightness, FontFeature;

import 'package:flutter/painting.dart';

import '../board/model.dart';
import '../calendar/calendar_format.dart';
import '../calendar/calendar_model.dart';
import '../calendar/calendar_state.dart' show occurrencesIn;
import '../planner/planner_model.dart';
import '../planner/planner_state.dart';
import '../study/fsrs.dart' show Rating;
import '../study/session.dart';
import '../study/study_rows.dart';
import '../study/study_state.dart';
import '../theme/colors.dart';
import '../theme/tokens.g.dart';
import '../ui/icons.dart';
import '../ui/study/study_format.dart';
import 'live_items.dart' show liveNow;
import 'page_runtime.dart' show paintItem, paintStroke;

// Widgets on the page (WidgetBoard.png): the calendar, the planner, a deck
// of flashcards and Need to remember. They hold a reference (which deck,
// which folder, which view), never a copy: what they show comes from
// [widgetFeed], which the app keeps up to date, and the canvas draws them
// again when it changes. Everything is in WidgetBoard.dc.html's units,
// scaled by the item's `unit`.

/// What the widgets show: the calendar, the planner and the study data.
class WidgetFeed {
  const WidgetFeed({
    this.calendar = const CalendarData(),
    this.deadlines = const [],
    this.planner = const PlannerData(),
    this.study,
    this.decks = const [],
    this.notebooks = const {},
  });

  static const empty = WidgetFeed();

  final CalendarData calendar;
  final List<CalEvent> deadlines;
  final PlannerData planner;
  final StudySnapshot? study;
  final List<Deck> decks;

  /// Each notebook's title and folder.
  final Map<String, ({String title, List<String> folder})> notebooks;
}

/// The feed widgets are drawn from (set by the app).
WidgetFeed widgetFeed = WidgetFeed.empty;

/// Flashcard widgets showing a card's back (by item id): how it's shown
/// right now, never saved.
final flippedCards = <String>{};

bool isFeedWidget(Item i) =>
    i is LiveItem &&
    (i.data is CalendarWidgetData || i.data is PlannerWidgetData || i.data is FlashcardsWidgetData || i.data is RememberWidgetData);

// What's under a tap.

sealed class WidgetHit {
  const WidgetHit();
}

/// A day on the calendar widget.
class CalendarDayHit extends WidgetHit {
  const CalendarDayHit(this.day);
  final DateTime day;
}

class PlannerRangeHit extends WidgetHit {
  const PlannerRangeHit(this.range);
  final PlannerWidgetRange range;
}

/// A to-do's box on the planner widget.
class PlannerTodoHit extends WidgetHit {
  const PlannerTodoHit(this.todo);
  final Todo todo;
}

/// "write a task…".
class PlannerWriteHit extends WidgetHit {
  const PlannerWriteHit();
}

/// "Open planner", "Study all", "See all": the screen behind the widget.
class OpenHit extends WidgetHit {
  const OpenHit();
}

class FlipHit extends WidgetHit {
  const FlipHit();
}

/// Again or Got it.
class RateHit extends WidgetHit {
  const RateHit(this.item, this.rating);
  final StudyItem item;
  final Rating rating;
}

/// A thing to remember on the widget.
class RememberHit extends WidgetHit {
  const RememberHit(this.thing);
  final RememberedThing thing;
}

// Text.

TextPainter _text(
  String s,
  double size,
  Color color, {
  FontWeight weight = FontWeight.w400,
  String family = FontFamilies.ui,
  double? maxWidth,
  int maxLines = 1,
  double letterSpacing = 0,
  double height = 1.2,
  TextDecoration? decoration,
  TextAlign align = TextAlign.left,
}) =>
    TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontFamily: family,
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: height,
          letterSpacing: letterSpacing,
          decoration: decoration,
          decorationColor: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: math.max(0, maxWidth ?? double.infinity));

/// Draws [p] at [x] with its middle at [cy], and lets it go.
void _put(Canvas canvas, TextPainter p, double x, double cy) {
  p.paint(canvas, Offset(x, cy - p.height / 2));
  p.dispose();
}

/// Draws [p] with its top-left at [at], and lets it go.
void _putTop(Canvas canvas, TextPainter p, Offset at) {
  p.paint(canvas, at);
  p.dispose();
}

double _width(String s, double size, FontWeight weight) {
  final p = _text(s, size, const Color(0xFF000000), weight: weight);
  final w = p.width;
  p.dispose();
  return w;
}

/// The widget's card (WidgetBoard.dc.html: 16 px corners, 1 px border,
/// 0 14px 28px -18px shadow).
void _panel(Canvas canvas, Size size, EndlessColors c) {
  final rect = Offset.zero & size;
  final shade = rect.inflate(-18).shift(const Offset(0, 14));
  if (!shade.isEmpty) {
    canvas.drawRect(shade, Paint()
      ..color = c.shadow.withValues(alpha: c.shadow.a * 0.7)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
  }
  final card = RRect.fromRectAndRadius(rect, const Radius.circular(16));
  canvas
    ..drawRRect(card, Paint()..color = c.surface)
    ..drawRRect(card.deflate(0.5), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = c.line);
}

void _label(Canvas canvas, String s, Offset at, EndlessColors c, {double size = 11}) =>
    _putTop(canvas, _text(s, size, c.textMuted, weight: FontWeight.w700, letterSpacing: size * 0.06), at);

void _dashed(Canvas canvas, RRect r, Color color, {double width = 1.5}) {
  final path = Path()..addRRect(r.deflate(width / 2));
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..color = color;
  for (final m in path.computeMetrics()) {
    for (var d = 0.0; d < m.length; d += 7) {
      canvas.drawPath(m.extractPath(d, math.min(d + 4, m.length)), paint);
    }
  }
}

/// [items] (page items, as on their page) drawn to fit [box]: no bigger
/// than [maxScale], at the left or in the middle.
void paintFitted(Canvas canvas, List<Item> items, Rect box, Brightness brightness, EndlessColors c, {double maxScale = 1, bool center = false}) {
  Rect? r;
  for (final i in items) {
    r = r == null ? i.extent : r.expandToInclude(i.extent);
  }
  if (r == null || r.isEmpty) return;
  final k = math.min(maxScale, math.min(box.width / r.width, box.height / r.height));
  final w = r.width * k, h = r.height * k;
  final left = center ? box.center.dx - w / 2 : box.left;
  canvas
    ..save()
    ..clipRect(box)
    ..translate(left, box.center.dy - h / 2)
    ..scale(k)
    ..translate(-r.left, -r.top);
  for (final i in items) {
    paintItem(canvas, i, brightness, c);
  }
  canvas.restore();
}

/// Draws a calendar, planner, flashcards or Need to remember widget with
/// its top-left at the origin (already scaled by its unit).
void paintWidget(Canvas canvas, LiveItem item, Brightness brightness, EndlessColors c) {
  final now = liveNow();
  final feed = widgetFeed;
  _panel(canvas, item.data.size, c);
  switch (item.data) {
    case final CalendarWidgetData d:
      _calendar(canvas, d, feed, now, c);
    case final PlannerWidgetData d:
      _planner(canvas, d, feed, now, brightness, c);
    case final FlashcardsWidgetData d:
      _flashcards(canvas, item, d, feed, now, brightness, c);
    case final RememberWidgetData d:
      _remember(canvas, d, feed, now, brightness, c);
    default:
      break;
  }
}

/// What a widget says, for an exported PDF's text layer and search.
String widgetText(LiveItem item, DateTime now) {
  final feed = widgetFeed;
  final today = dayOf(now);
  switch (item.data) {
    case final CalendarWidgetData d:
      return [
        'Calendar · ${monthTitle(today)}',
        for (final o in _shown(feed, d, today, addDays(today, 1))) o.allDay ? o.event.title : '${hm(o.start)} ${o.event.title}',
      ].join('\n');
    case PlannerWidgetData _:
      return ['Planner', for (final t in _todos(feed, now)) todoLabel(t)].join('\n');
    case final FlashcardsWidgetData d:
      final deck = _deck(feed, d);
      return 'Flashcards · ${deck?.deck.name ?? (d.deckName.isEmpty ? 'Flashcards' : d.deckName)}';
    case final RememberWidgetData d:
      return ['Need to remember', for (final t in _things(feed, d).take(3)) t.said].where((s) => s.isNotEmpty).join('\n');
    default:
      return '';
  }
}

// The calendar (WidgetBoard.dc.html's Calendar widget).

List<Occurrence> _shown(WidgetFeed feed, CalendarWidgetData d, DateTime from, DateTime to) => [
      for (final o in occurrencesIn(feed.calendar, feed.deadlines, from, to))
        if (!d.hidden.contains(o.event.calendarId)) o,
    ];

/// "Google + Outlook · live", from the calendars it shows.
String _sources(WidgetFeed feed, CalendarWidgetData d) {
  final kinds = {
    for (final cal in feed.calendar.calendars)
      if (cal.shown && !d.hidden.contains(cal.id) && cal.kind != CalendarKind.deadlines) cal.kind,
  };
  final names = [
    if (kinds.contains(CalendarKind.google)) 'Google',
    if (kinds.contains(CalendarKind.outlook)) 'Outlook',
    if (kinds.contains(CalendarKind.local)) kinds.length == 1 ? 'This tablet' : 'this tablet',
  ];
  return names.isEmpty ? 'live' : '${names.join(' + ')} · live';
}

const _calendarGridTop = 58.0;
const _calendarRow = 36.0;

/// Sunday first, six weeks from the Sunday on or before the 1st.
DateTime _gridStart(DateTime month) {
  final first = DateTime(month.year, month.month);
  return addDays(first, -(first.weekday % 7));
}

void _calendar(Canvas canvas, CalendarWidgetData d, WidgetFeed feed, DateTime now, EndlessColors c) {
  const w = 370.0, pad = 14.0;
  final today = dayOf(now);
  paintEIcon(canvas, EIcons.calendar, const Offset(pad, 14), 18, c.accentDeep);
  final source = _text(_sources(feed, d), 11, c.textMuted, weight: FontWeight.w600);
  final sourceWidth = source.width;
  _put(canvas, source, w - pad - sourceWidth, 23);
  _put(canvas, _text(d.agenda ? 'Coming up' : monthNames[today.month - 1], 15, c.text, weight: FontWeight.w700, maxWidth: w - 40 - pad - sourceWidth - 8), 40, 23);

  if (d.agenda) {
    var y = 44.0;
    var any = false;
    for (var i = 0; i < 14 && y < 330; i++) {
      final day = addDays(today, i);
      final list = _shown(feed, d, day, addDays(day, 1));
      if (list.isEmpty) continue;
      any = true;
      _label(canvas, i == 0 ? 'TODAY · ${dayShort(day).toUpperCase()}' : (i == 1 ? 'TOMORROW · ${dayShort(day).toUpperCase()}' : dayShort(day).toUpperCase()), Offset(pad, y), c);
      y += 20;
      for (final o in list) {
        if (y > 330) break;
        _eventLine(canvas, o, feed, y, c, w);
        y += 22;
      }
      y += 6;
    }
    if (!any) _put(canvas, _text('Nothing in the next two weeks', 13, c.textMuted), pad, 60);
    return;
  }

  // The month.
  const gridW = w - 2 * pad;
  const colW = gridW / 7;
  for (final (i, l) in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'].indexed) {
    final p = _text(l, 10, c.textMuted, weight: FontWeight.w700);
    _put(canvas, p, pad + colW * (i + 0.5) - p.width / 2, 48);
  }
  final start = _gridStart(today);
  final end = addDays(start, 42);
  final dots = <DateTime, List<Color>>{};
  for (final o in _shown(feed, d, start, end)) {
    final last = o.allDay ? addDays(o.end, -1) : dayOf(o.end.subtract(const Duration(microseconds: 1)));
    final color = eventColors(o, feed.calendar, c).dot;
    for (var day = dayOf(o.start); !day.isAfter(last); day = addDays(day, 1)) {
      final list = dots[day] ??= [];
      if (!list.contains(color)) list.add(color);
    }
  }
  for (var k = 0; k < 42; k++) {
    final day = addDays(start, k);
    if (day.month != today.month) continue;
    final cx = pad + colW * (k % 7 + 0.5);
    final top = _calendarGridTop + (k ~/ 7) * _calendarRow + 2.5;
    final isToday = day == today;
    if (isToday) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 12, top, 24, 22), const Radius.circular(11)), Paint()..color = c.accent);
    }
    final n = _text('${day.day}', 12, isToday ? c.onAccent : c.text, weight: isToday ? FontWeight.w700 : FontWeight.w500);
    _put(canvas, n, cx - n.width / 2, top + 11);
    final colors = (dots[day] ?? const []).take(2).toList();
    for (final (i, color) in colors.indexed) {
      final x = cx - (colors.length * 5 + (colors.length - 1) * 2) / 2 + i * 7;
      canvas.drawCircle(Offset(x + 2.5, top + 26.5), 2.5, Paint()..color = color);
    }
  }

  // Today.
  const sep = _calendarGridTop + 6 * _calendarRow - 2 + 10;
  canvas.drawLine(const Offset(pad, sep + 0.5), const Offset(w - pad, sep + 0.5), Paint()..color = c.lineSoft);
  _label(canvas, 'TODAY · ${dayShort(today).toUpperCase()}', const Offset(pad, sep + 8), c);
  final list = _shown(feed, d, today, addDays(today, 1));
  if (list.isEmpty) {
    _put(canvas, _text('Nothing today', 13, c.textMuted), pad, sep + 37);
  }
  for (final (i, o) in list.take(2).indexed) {
    if (i == 1 && list.length > 2) {
      _put(canvas, _text('+${list.length - 1} more today', 13, c.textMuted), 30, sep + 37 + 22);
      break;
    }
    _eventLine(canvas, o, feed, sep + 29 + i * 22, c, w);
  }
}

/// "■ 10:00 Physics lecture" with its top at [y].
void _eventLine(Canvas canvas, Occurrence o, WidgetFeed feed, double y, EndlessColors c, double w) {
  final k = eventColors(o, feed.calendar, c);
  canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(14, y + 4, 8, 8), const Radius.circular(3)), Paint()..color = k.dot);
  _put(canvas, _text(o.allDay ? o.event.title : '${hm(o.start)} ${o.event.title}', 13, c.text, maxWidth: w - 30 - 14), 30, y + 8);
}

/// The day under [p] on a calendar widget's month (in its units).
DateTime? _calendarDayAt(CalendarWidgetData d, Offset p, DateTime now) {
  if (d.agenda) return null;
  const colW = (370 - 28) / 7;
  final col = ((p.dx - 14) / colW).floor();
  final row = ((p.dy - _calendarGridTop) / _calendarRow).floor();
  if (col < 0 || col > 6 || row < 0 || row > 5) return null;
  final day = addDays(_gridStart(dayOf(now)), row * 7 + col);
  return day.month == dayOf(now).month ? day : null;
}

// The planner.

const _plannerRanges = [(PlannerWidgetRange.today, 'Today'), (PlannerWidgetRange.three, '3 days'), (PlannerWidgetRange.week, 'Week')];

/// The range buttons, right-aligned in the header.
List<(PlannerWidgetRange, Rect)> _rangeButtons(PlannerWidgetData d) {
  final widths = [for (final (r, l) in _plannerRanges) _width(l, 12, r == d.range ? FontWeight.w700 : FontWeight.w500) + 20];
  final total = widths.fold(0.0, (a, b) => a + b) + 2 * (widths.length - 1);
  var x = 450 - 14 - 3 - total;
  return [
    for (final (i, (r, _)) in _plannerRanges.indexed) (r, Rect.fromLTWH((x += i == 0 ? 0 : widths[i - 1] + 2), 17, widths[i], 34)),
  ];
}

List<Todo> _todos(WidgetFeed feed, DateTime now) => todosFor(feed.planner, feed.study, feed.decks, dayOf(now), dayOf(now), now.toUtc());

const _todoTop = 82.0;
const _todoRow = 36.0;
const _bodyBottom = 324.0;

/// How many to-dos fit above "write a task…".
int _todoRows(int count) => math.min(count, ((_bodyBottom - _todoTop - 44) / _todoRow).floor());

Rect _openRect(String label, double w, double cy) {
  final tw = _width(label, 13, FontWeight.w600);
  return Rect.fromLTWH(w - 14 - tw, cy - 16, tw, 32);
}

void _planner(Canvas canvas, PlannerWidgetData d, WidgetFeed feed, DateTime now, Brightness brightness, EndlessColors c) {
  const w = 450.0, pad = 14.0;
  final today = dayOf(now);
  paintEIcon(canvas, EIcons.planner, const Offset(pad, 25), 18, c.greenDeep);
  _put(canvas, _text('Planner', 15, c.text, weight: FontWeight.w700), 40, 34);
  final buttons = _rangeButtons(d);
  canvas.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTRB(buttons.first.$2.left - 3, 14, buttons.last.$2.right + 3, 54), const Radius.circular(10)),
    Paint()..color = c.side,
  );
  for (final (r, rect) in buttons) {
    final on = r == d.range;
    if (on) canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)), Paint()..color = c.surface);
    final t = _text(_plannerRanges.firstWhere((x) => x.$1 == r).$2, 12, c.text, weight: on ? FontWeight.w700 : FontWeight.w500);
    _put(canvas, t, rect.center.dx - t.width / 2, rect.center.dy);
  }
  final open = _openRect('Open planner', w, 350);
  _put(canvas, _text('Open planner', 13, c.accent, weight: FontWeight.w600), open.left, open.center.dy);

  final calendar = feed.calendar;
  List<_Line> lines(DateTime day) {
    final out = <_Line>[
      for (final o in occurrencesIn(calendar, feed.deadlines, day, addDays(day, 1)))
        (
          time: o.allDay ? '' : hm(o.start),
          label: o.event.title,
          colors: eventColors(o, calendar, c),
          planned: false,
          at: o.allDay ? day : o.start,
        ),
      for (final t in feed.planner.blocksOn(day))
        (
          time: hm(t.block!.$1),
          label: t.deckId != null ? 'Review flashcards · ${t.minutes} min' : (t.text.isEmpty ? 'To-do' : t.text),
          colors: hueColors(t.deckId != null ? CalendarHue.clay : CalendarHue.plum, c),
          planned: true,
          at: t.block!.$1,
        ),
    ]..sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  switch (d.range) {
    case PlannerWidgetRange.today:
      const colW = (w - 2 * pad - 12) / 2;
      _label(canvas, 'SCHEDULE', const Offset(pad, 64), c);
      var y = 84.0;
      final list = lines(today);
      if (list.isEmpty) _put(canvas, _text('Nothing planned', 12, c.textMuted), pad, y + 10);
      for (final l in list) {
        final t = _text(l.label, 12, l.colors.fg, weight: FontWeight.w600, maxWidth: colW - 46 - 16, maxLines: 2);
        final h = t.height + 10;
        if (y + h > _bodyBottom) {
          t.dispose();
          break;
        }
        _putTop(canvas, _text(l.time, 11, c.textMuted), Offset(pad, y + 5));
        final chip = RRect.fromRectAndRadius(Rect.fromLTWH(pad + 46, y, colW - 46, h), const Radius.circular(7));
        if (l.planned) {
          canvas.drawRRect(chip, Paint()..color = c.surface);
          _dashed(canvas, chip, l.colors.fg);
        } else {
          canvas.drawRRect(chip, Paint()..color = l.colors.bg);
        }
        _putTop(canvas, t, Offset(chip.left + 8, y + 5));
        y += h + 6;
      }
      const x = pad + colW + 12;
      _label(canvas, 'TO-DO', const Offset(x, 64), c);
      final todos = _todos(feed, now);
      final shown = _todoRows(todos.length);
      for (var i = 0; i < shown; i++) {
        final t = todos[i];
        final cy = _todoTop + i * _todoRow + _todoRow / 2;
        _box(canvas, Rect.fromLTWH(x, cy - 9, 18, 18), t.done, c);
        final task = t.task;
        if (task != null && task.text.isEmpty && task.ink.isNotEmpty) {
          _inkFitted(canvas, task.ink, Rect.fromLTWH(x + 26, cy - 10, colW - 26, 20), brightness, c, faded: t.done);
        } else {
          _put(canvas, _text(todoLabel(t), 13, t.done ? c.textMuted : c.text, maxWidth: colW - 26, decoration: t.done ? TextDecoration.lineThrough : null), x + 26, cy);
        }
      }
      final slot = RRect.fromRectAndRadius(Rect.fromLTWH(x, _todoTop + shown * _todoRow + 4, colW, 40), const Radius.circular(8));
      _dashed(canvas, slot, c.lineStrong);
      _put(canvas, _text('write a task…', 20, c.textMuted, family: FontFamilies.handwritingSample), x + 9, slot.center.dy);
    case PlannerWidgetRange.three:
      const colW = (w - 2 * pad - 16) / 3;
      for (var i = 0; i < 3; i++) {
        final day = addDays(today, i);
        final x = pad + i * (colW + 8);
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTRB(x, 64, x + colW, _bodyBottom), const Radius.circular(10)),
          Paint()..color = i == 0 ? c.accent.withValues(alpha: 0.07) : c.bg,
        );
        _putTop(canvas, _text(i == 0 ? '${dayShort(day)} · today' : dayShort(day), 12, c.text, weight: FontWeight.w700), Offset(x + 8, 72));
        var y = 94.0;
        for (final l in lines(day)) {
          final t = _text(l.label, 11, l.colors.fg, weight: FontWeight.w600, maxWidth: colW - 28, maxLines: 2);
          final h = t.height + 8;
          if (y + h > _bodyBottom - 8) {
            t.dispose();
            break;
          }
          final chip = RRect.fromRectAndRadius(Rect.fromLTWH(x + 8, y, colW - 16, h), const Radius.circular(6));
          canvas.drawRRect(chip, Paint()..color = l.planned ? c.surface : l.colors.bg);
          if (l.planned) _dashed(canvas, chip, l.colors.fg, width: 1.2);
          _putTop(canvas, t, Offset(chip.left + 6, y + 4));
          y += h + 5;
        }
      }
    case PlannerWidgetRange.week:
      final week = weekStart(today);
      final goals = RRect.fromRectAndRadius(const Rect.fromLTWH(pad, 64, w - 2 * pad, 58), const Radius.circular(10));
      canvas.drawRRect(goals, Paint()..color = c.bg);
      _label(canvas, 'WEEK GOALS', const Offset(pad + 10, 72), c);
      final ink = feed.planner.goalsFor(week);
      if (ink.isEmpty) {
        _put(canvas, _text('write this week’s goals in the planner', 16, c.textFaint, family: FontFamilies.handwritingSample), pad + 10, 104);
      } else {
        _inkFitted(canvas, ink, const Rect.fromLTWH(pad + 10, 90, w - 2 * pad - 20, 26), brightness, c);
      }
      const colW = (w - 2 * pad - 24) / 7;
      for (var i = 0; i < 7; i++) {
        final day = addDays(week, i);
        final x = pad + i * (colW + 4);
        const top = 130.0;
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTRB(x, top, x + colW, _bodyBottom), const Radius.circular(8)),
          Paint()..color = day == today ? c.accent.withValues(alpha: 0.08) : c.bg,
        );
        final name = _text(shortWeekday(day), 11, c.text, weight: FontWeight.w700);
        _putTop(canvas, name, Offset(x + colW / 2 - name.width / 2, top + 6));
        final list = lines(day);
        for (final (j, l) in list.take(12).indexed) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(x + 4, top + 26 + j * 12, colW - 8, 8), const Radius.circular(3)),
            Paint()..color = l.colors.fg,
          );
        }
        final count = _text(list.length == 1 ? '1 item' : '${list.length} items', 10, c.textMuted);
        _putTop(canvas, count, Offset(x + colW / 2 - count.width / 2, _bodyBottom - 18));
      }
  }
}

typedef _Line = ({String time, String label, ({Color dot, Color bg, Color fg}) colors, bool planned, DateTime at});

void _box(Canvas canvas, Rect r, bool done, EndlessColors c) {
  final box = RRect.fromRectAndRadius(r, const Radius.circular(4));
  if (!done) {
    canvas
      ..drawRRect(box, Paint()..color = c.surface)
      ..drawRRect(box.deflate(0.75), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = c.lineStrong);
    return;
  }
  canvas
    ..drawRRect(box, Paint()..color = c.accent)
    ..drawPath(
      Path()
        ..moveTo(r.left + 4.5, r.top + 9.5)
        ..lineTo(r.left + 7.8, r.top + 12.8)
        ..lineTo(r.left + 13.8, r.top + 5.8),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = c.onAccent,
    );
}

/// Strokes (from their own origin) fitted into [box], at the left.
void _inkFitted(Canvas canvas, List<StrokeItem> ink, Rect box, Brightness brightness, EndlessColors c, {bool faded = false}) {
  Rect? r;
  for (final s in ink) {
    r = r == null ? s.bounds : r.expandToInclude(s.bounds);
  }
  if (r == null || r.isEmpty) return;
  final k = math.min(1.0, math.min(box.width / r.width, box.height / r.height));
  canvas
    ..save()
    ..clipRect(box)
    ..translate(box.left, box.center.dy - r.height * k / 2)
    ..scale(k)
    ..translate(-r.left, -r.top);
  for (final s in ink) {
    paintStroke(canvas, s, faded ? c.textFaint : displayInk(s.color, brightness));
  }
  canvas.restore();
}

// Flashcards.

DeckSummary? _deck(WidgetFeed feed, FlashcardsWidgetData d) {
  final study = feed.study;
  if (study == null) return null;
  final all = deckSummaries(study, feed.decks, liveNow().toUtc());
  return all.where((s) => s.deck.id == d.deck).firstOrNull ?? (d.deck.isEmpty ? all.where((s) => s.cards > 0).firstOrNull : null);
}

/// The card the widget shows: the next one due in its deck.
StudyItem? _nextCard(DeckSummary? deck, DateTime now) {
  if (deck == null) return null;
  final due = [for (final i in deck.items) if (i.dueAt(now.toUtc())) i];
  return due.isEmpty ? null : StudySession(due).current(now.toUtc());
}

const _cardRect = Rect.fromLTWH(14, 44, 222, 150);
const _rowTop = 204.0;

void _flashcards(Canvas canvas, LiveItem item, FlashcardsWidgetData d, WidgetFeed feed, DateTime now, Brightness brightness, EndlessColors c) {
  const w = 250.0, pad = 14.0;
  final deck = _deck(feed, d);
  final next = _nextCard(deck, now);
  final flipped = next != null && flippedCards.contains(item.id);
  paintEIcon(canvas, EIcons.flashcards, const Offset(pad, 15), 18, c.clayDeep);
  final due = deck?.due ?? 0;
  var right = w - pad;
  if (due > 0) {
    final t = _text('$due due', 11, c.clayDeep, weight: FontWeight.w700);
    final pill = Rect.fromLTWH(right - t.width - 16, 15, t.width + 16, 18);
    canvas.drawRRect(RRect.fromRectAndRadius(pill, const Radius.circular(9)), Paint()..color = c.clayTint);
    _put(canvas, t, pill.left + 8, pill.center.dy);
    right = pill.left - 8;
  }
  final name = deck?.deck.name ?? (d.deckName.isEmpty ? 'Flashcards' : d.deckName);
  _put(canvas, _text(name, 14, c.text, weight: FontWeight.w700, maxWidth: right - 40), 40, 24);

  // The card.
  final card = RRect.fromRectAndRadius(_cardRect, const Radius.circular(12));
  canvas
    ..drawRRect(card, Paint()..color = c.bg)
    ..save()
    ..clipRRect(card);
  final dots = Paint()..color = c.dot.withValues(alpha: 0.6);
  for (var y = _cardRect.top + 7; y < _cardRect.bottom; y += 14) {
    for (var x = _cardRect.left + 7; x < _cardRect.right; x += 14) {
      canvas.drawCircle(Offset(x, y), 1, dots);
    }
  }
  canvas
    ..restore()
    ..drawRRect(card.deflate(0.5), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = c.cardLine);
  if (next == null) {
    final title = deck == null || deck.cards == 0 ? 'No flashcards yet' : 'All caught up';
    final sub = deck == null || deck.cards == 0 ? 'Make some from your notes' : '${cardsLabel(deck.cards)} in this deck';
    final t = _text(title, 22, c.text, family: FontFamilies.serif);
    _put(canvas, t, _cardRect.center.dx - t.width / 2, _cardRect.center.dy - 10);
    final s = _text(sub, 12, c.textMuted);
    _put(canvas, s, _cardRect.center.dx - s.width / 2, _cardRect.center.dy + 16);
  } else {
    final side = (next.reverse != flipped) ? next.card.back : next.card.front;
    final label = _text(flipped ? 'BACK' : 'FRONT', 10, flipped ? c.clayDeep : c.accentDeep, weight: FontWeight.w700, letterSpacing: 0.8);
    _put(canvas, label, _cardRect.center.dx - label.width / 2, _cardRect.top + 22);
    final box = Rect.fromLTRB(_cardRect.left + 12, _cardRect.top + 34, _cardRect.right - 12, _cardRect.bottom - 14);
    if (side.items.isNotEmpty) {
      paintFitted(canvas, side.items, box, brightness, c, maxScale: 2, center: true);
    } else {
      final t = _text(side.text.isEmpty ? '(empty)' : side.text, 26, c.text, family: FontFamilies.serif, maxWidth: box.width, maxLines: 3, align: TextAlign.center);
      _put(canvas, t, box.center.dx - t.width / 2, box.center.dy);
    }
  }

  // Again · Got it, or Study all.
  if (flipped) {
    for (final (i, label, fill, line, ink) in [
      (0, 'Again', c.clayTint, c.clayLine, c.clayDeep),
      (1, 'Got it', c.accentTint, c.accentLine, c.accentDeep),
    ]) {
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(pad + i * 114, _rowTop, 108, 44), const Radius.circular(10));
      canvas
        ..drawRRect(r, Paint()..color = fill)
        ..drawRRect(r.deflate(0.5), Paint()
          ..style = PaintingStyle.stroke
          ..color = line);
      final t = _text(label, 13, ink, weight: FontWeight.w700);
      _put(canvas, t, r.center.dx - t.width / 2, r.center.dy);
    }
  } else {
    final r = RRect.fromRectAndRadius(const Rect.fromLTWH(pad, _rowTop, w - 2 * pad, 44), const Radius.circular(10));
    canvas.drawRRect(r, Paint()..color = c.inverse);
    final t = _text('Study all', 13, c.onInverse, weight: FontWeight.w600);
    _put(canvas, t, r.center.dx - t.width / 2, r.center.dy);
  }
}

// Need to remember.

/// The newest things to remember in [d]'s folder.
List<RememberedThing> _things(WidgetFeed feed, RememberWidgetData d) {
  final list = [
    for (final t in feed.study?.remembered ?? const <RememberedThing>[])
      if (d.folder.isEmpty || _inFolder(feed.notebooks[t.notebookId]?.folder ?? const [], d.folder)) t,
  ]..sort((a, b) => b.at.compareTo(a.at));
  return list;
}

bool _inFolder(List<String> path, List<String> folder) {
  if (path.length < folder.length) return false;
  for (var i = 0; i < folder.length; i++) {
    if (path[i] != folder[i]) return false;
  }
  return true;
}

const _rememberTop = 56.0;
const _rememberCard = Size((544 - 28 - 16) / 3, 90);

Rect _rememberRect(int i) => Rect.fromLTWH(14 + i * (_rememberCard.width + 8), _rememberTop, _rememberCard.width, _rememberCard.height);

Rect _seeAllRect() {
  final tw = _width('See all', 13, FontWeight.w600);
  return Rect.fromLTWH(544 - 14 - 4 - tw, 14, tw + 8, 32);
}

void _remember(Canvas canvas, RememberWidgetData d, WidgetFeed feed, DateTime now, Brightness brightness, EndlessColors c) {
  const pad = 14.0;
  paintEIcon(canvas, EIcons.starSolid, const Offset(pad, 21), 18, c.star);
  paintEIcon(canvas, EIcons.star, const Offset(pad, 21), 18, c.gold);
  _put(canvas, _text('Need to remember', 15, c.text, weight: FontWeight.w700), 40, 30);
  final things = _things(feed, d);
  final see = _seeAllRect();
  _put(canvas, _text('See all', 13, c.accent, weight: FontWeight.w600), see.left + 4, see.center.dy);
  final where = _text('${d.folder.isEmpty ? 'All' : d.folder.last} · ${things.length}', 12, c.textMuted);
  _put(canvas, where, see.left - 10 - where.width, 30);
  if (things.isEmpty) {
    _put(canvas, _text('Nothing yet · draw a star next to anything to remember it', 13, c.textMuted, maxWidth: 516), pad, 100);
    return;
  }
  for (final (i, t) in things.take(3).indexed) {
    final r = _rememberRect(i);
    final card = RRect.fromRectAndRadius(r, const Radius.circular(10));
    canvas
      ..drawRRect(card, Paint()..color = c.rememberPaper)
      ..drawRRect(card.deflate(0.5), Paint()
        ..style = PaintingStyle.stroke
        ..color = c.rememberLine);
    final box = Rect.fromLTWH(r.left + 10, r.top + 8, r.width - 20, 52);
    if (t.typedOnly) {
      final text = t.items.whereType<TextItem>().map((x) => x.text.trim()).join(' ');
      _putTop(canvas, _text(text, 13, c.text, weight: FontWeight.w600, maxWidth: box.width, maxLines: 3, height: 1.3), box.topLeft);
    } else {
      paintFitted(canvas, t.items, box, brightness, c, maxScale: 0.8);
    }
    final meta = t.hasReminder
        ? thingReminder(t.remindAt!, now, beforeEvent: t.event?.title)
        : (feed.notebooks[t.notebookId]?.title ?? '');
    _put(canvas, _text(meta, 11, t.hasReminder ? c.goldDeep : c.textMuted, weight: t.hasReminder ? FontWeight.w600 : FontWeight.w400, maxWidth: box.width), r.left + 10, r.bottom - 16);
  }
}

// Taps.

/// What's under [local] (relative to the widget's top-left, unrotated).
WidgetHit? widgetHitAt(LiveItem item, Offset local) {
  final p = local / item.unit;
  final now = liveNow();
  final feed = widgetFeed;
  // At least 44 px for a finger.
  bool near(Rect r) => Rect.fromCenter(center: r.center, width: math.max(r.width, 44), height: math.max(r.height, 44)).contains(p);
  switch (item.data) {
    case final CalendarWidgetData d:
      final day = _calendarDayAt(d, p, now);
      return day == null ? null : CalendarDayHit(day);
    case final PlannerWidgetData d:
      for (final (r, rect) in _rangeButtons(d)) {
        if (rect.inflate(4).contains(p)) return PlannerRangeHit(r);
      }
      if (near(_openRect('Open planner', 450, 350))) return const OpenHit();
      if (d.range != PlannerWidgetRange.today) return null;
      const x = 14 + (450 - 28 - 12) / 2 + 12;
      if (p.dx < x - 4) return null;
      final todos = _todos(feed, now);
      final shown = _todoRows(todos.length);
      final i = ((p.dy - _todoTop) / _todoRow).floor();
      if (i >= 0 && i < shown) return PlannerTodoHit(todos[i]);
      final slot = Rect.fromLTWH(x, _todoTop + shown * _todoRow + 4, (450 - 28 - 12) / 2, 40);
      return slot.inflate(2).contains(p) ? const PlannerWriteHit() : null;
    case final FlashcardsWidgetData d:
      final next = _nextCard(_deck(feed, d), now);
      if (_cardRect.contains(p)) return next == null ? const OpenHit() : const FlipHit();
      if (p.dy < _rowTop - 2 || p.dy > _rowTop + 46) return null;
      if (next != null && flippedCards.contains(item.id)) {
        return RateHit(next, p.dx < 125 ? Rating.again : Rating.good);
      }
      return const OpenHit();
    case final RememberWidgetData d:
      if (near(_seeAllRect())) return const OpenHit();
      final things = _things(feed, d);
      for (var i = 0; i < math.min(3, things.length); i++) {
        if (_rememberRect(i).contains(p)) return RememberHit(things[i]);
      }
      return null;
    default:
      return null;
  }
}
