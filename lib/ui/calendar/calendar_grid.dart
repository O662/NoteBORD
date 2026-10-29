import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../calendar/calendar_format.dart';
import '../../calendar/calendar_model.dart';
import '../../theme/colors.dart';
import '../icons.dart';

// The calendar's grids (Calendar.dc.html): days side by side with an hour
// every 58 px, the all-day row and the red line at now (Week and Day), and
// the month.

/// Where a timed event sits in its day: its lane among the events it
/// overlaps, and how many lanes they need.
typedef Placed = ({Occurrence o, int lane, int lanes});

/// Lays out one day's timed events: overlapping ones side by side.
List<Placed> layoutDay(List<Occurrence> timed) {
  final sorted = [...timed]
    ..sort((a, b) {
      final s = a.start.compareTo(b.start);
      return s != 0 ? s : b.end.compareTo(a.end);
    });
  final out = <Placed>[];
  var group = <({Occurrence o, int lane})>[];
  var groupEnd = DateTime(0);
  final laneEnds = <DateTime>[];
  void flush() {
    final lanes = laneEnds.length;
    for (final g in group) {
      out.add((o: g.o, lane: g.lane, lanes: lanes));
    }
    group = [];
    laneEnds.clear();
  }

  for (final o in sorted) {
    if (group.isNotEmpty && !o.start.isBefore(groupEnd)) flush();
    var lane = laneEnds.indexWhere((end) => !o.start.isBefore(end));
    if (lane < 0) {
      lane = laneEnds.length;
      laneEnds.add(o.end);
    } else {
      laneEnds[lane] = o.end;
    }
    group.add((o: o, lane: lane));
    if (o.end.isAfter(groupEnd)) groupEnd = o.end;
  }
  flush();
  return out;
}

/// All-day (and day-long) events across [days]: each from its first to
/// its last column shown, in the first free row.
List<({Occurrence o, int from, int to, int row})> layoutAllDay(List<Occurrence> list, List<DateTime> days) {
  final rows = <List<(int, int)>>[];
  final out = <({Occurrence o, int from, int to, int row})>[];
  for (final o in list) {
    final first = dayOf(o.start);
    final last = o.allDay ? addDays(o.end, -1) : dayOf(o.end.subtract(const Duration(microseconds: 1)));
    var from = days.indexWhere((d) => !d.isBefore(first));
    var to = days.lastIndexWhere((d) => !d.isAfter(last));
    if (from < 0 || to < 0 || to < from) continue;
    from = math.max(0, from);
    to = math.min(days.length - 1, to);
    var row = rows.indexWhere((r) => r.every((span) => span.$2 < from || span.$1 > to));
    if (row < 0) {
      row = rows.length;
      rows.add([]);
    }
    rows[row].add((from, to));
    out.add((o: o, from: from, to: to, row: row));
  }
  return out;
}

/// Days side by side with their hours (Week: 7, Day: 1).
class TimeGrid extends StatefulWidget {
  const TimeGrid({
    super.key,
    required this.days,
    required this.occurrences,
    required this.data,
    required this.today,
    required this.now,
    required this.selected,
    required this.onPick,
    required this.onEmpty,
  });

  static const hour = 58.0;
  static const gutter = 46.0;
  static const header = 46.0;
  static const allDayRow = 26.0;

  final List<DateTime> days;
  final List<Occurrence> occurrences;
  final CalendarData data;
  final DateTime today;
  final DateTime now;

  /// The picked occurrence's key.
  final String? selected;
  final ValueChanged<Occurrence> onPick;

  /// A tap on an empty half hour: a new event there.
  final ValueChanged<DateTime> onEmpty;

  @override
  State<TimeGrid> createState() => _TimeGridState();
}

class _TimeGridState extends State<TimeGrid> {
  // 8 AM at the top, as in the design.
  final _scroll = ScrollController(initialScrollOffset: 8 * TimeGrid.hour);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final days = widget.days;
    final allDay = [
      for (final o in widget.occurrences)
        if (o.allDay || o.long) o,
    ];
    final timed = [
      for (final o in widget.occurrences)
        if (!o.allDay && !o.long) o,
    ];
    final spans = layoutAllDay(allDay, days);
    final rows = spans.fold(0, (n, s) => math.max(n, s.row + 1));
    final allDayHeight = TimeGrid.allDayRow * math.max(1, math.min(rows, 3));
    final todayCol = days.indexOf(widget.today);
    return LayoutBuilder(
      builder: (context, box) {
        final colW = (box.maxWidth - TimeGrid.gutter) / days.length;
        double left(int col) => TimeGrid.gutter + col * colW;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The days.
            Container(
              height: TimeGrid.header,
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.lineSoft)),
              ),
              child: Row(
                children: [
                  const SizedBox(width: TimeGrid.gutter),
                  for (final (i, d) in days.indexed)
                    Expanded(
                      child: Semantics(
                        label: dayTitle(d),
                        excludeSemantics: true,
                        child: Container(
                          color: i == todayCol ? c.accent.withValues(alpha: 0.06) : null,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            spacing: 1,
                            children: [
                              Text(
                                shortWeekday(d).toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.66,
                                  color: i == todayCol ? c.accentDeep : c.textMuted,
                                ),
                              ),
                              Container(
                                width: 26,
                                height: 22,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(color: i == todayCol ? c.accent : null, borderRadius: BorderRadius.circular(999)),
                                child: Text(
                                  '${d.day}',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: i == todayCol ? c.onAccent : c.text),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // All day.
            Container(
              height: allDayHeight,
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.lineSoft)),
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    width: TimeGrid.gutter,
                    top: 0,
                    height: TimeGrid.allDayRow,
                    child: Center(
                      child: Text(
                        'all day',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c.textMuted),
                      ),
                    ),
                  ),
                  for (final s in spans)
                    if (s.row < 3)
                      Positioned(
                        left: left(s.from) + 2,
                        width: (s.to - s.from + 1) * colW - 4,
                        top: s.row * TimeGrid.allDayRow + 3,
                        height: 20,
                        child: _AllDayChip(o: s.o, data: widget.data, selected: s.o.key == widget.selected, onTap: () => widget.onPick(s.o)),
                      ),
                ],
              ),
            ),
            // The hours.
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    final col = ((d.localPosition.dx - TimeGrid.gutter) / colW).floor();
                    if (col < 0 || col >= days.length) return;
                    final halfHours = (d.localPosition.dy / (TimeGrid.hour / 2)).floor().clamp(0, 47);
                    widget.onEmpty(days[col].add(Duration(minutes: halfHours * 30)));
                  },
                  child: SizedBox(
                    height: 24 * TimeGrid.hour,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (var h = 0; h < 24; h++)
                          Positioned(
                            left: 0,
                            right: 0,
                            top: h * TimeGrid.hour,
                            height: TimeGrid.hour,
                            child: Container(
                              decoration: h == 0
                                  ? null
                                  : BoxDecoration(
                                      border: Border(top: BorderSide(color: c.lineSoft.withValues(alpha: 0.7))),
                                    ),
                              padding: const EdgeInsets.only(left: 6, top: 3),
                              alignment: Alignment.topLeft,
                              child: h == 0 ? null : Text(hourLabel(h), style: TextStyle(fontSize: 11, color: c.textMuted)),
                            ),
                          ),
                        if (todayCol >= 0)
                          Positioned(
                            left: left(todayCol),
                            width: colW,
                            top: 0,
                            bottom: 0,
                            child: IgnorePointer(child: ColoredBox(color: c.accent.withValues(alpha: 0.04))),
                          ),
                        for (final (col, day) in days.indexed)
                          for (final p in layoutDay([
                            for (final o in timed)
                              if (dayOf(o.start) == day) o,
                          ]))
                            Positioned(
                              left: left(col) + 2 + p.lane * (colW - 5) / p.lanes,
                              width: (colW - 5) / p.lanes - (p.lanes > 1 ? 2 : 0),
                              top: _y(p.o.start, day) + 1,
                              height: math.max(26, _y(p.o.end, day) - _y(p.o.start, day) - 3),
                              child: EventBlock(o: p.o, data: widget.data, selected: p.o.key == widget.selected, onTap: () => widget.onPick(p.o)),
                            ),
                        if (todayCol >= 0) ...[
                          Positioned(
                            left: left(todayCol) - 4,
                            width: colW + 4,
                            top: _y(widget.now, widget.today) - 1,
                            height: 2,
                            child: IgnorePointer(
                              child: Semantics(
                                label: 'Now, ${hmAmPm(widget.now)}',
                                child: ColoredBox(color: c.danger),
                              ),
                            ),
                          ),
                          Positioned(
                            left: left(todayCol) - 8,
                            top: _y(widget.now, widget.today) - 5,
                            width: 10,
                            height: 10,
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(color: c.danger, shape: BoxShape.circle),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Where [t] is in [day]'s column (an event past midnight ends at the
  /// bottom).
  static double _y(DateTime t, DateTime day) {
    final minutes = t.difference(day).inMinutes.clamp(0, 24 * 60);
    return minutes / 60 * TimeGrid.hour;
  }
}

/// An event in a day's column (Calendar.dc.html's event button).
class EventBlock extends StatelessWidget {
  const EventBlock({super.key, required this.o, required this.data, required this.selected, required this.onTap});

  final Occurrence o;
  final CalendarData data;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final k = eventColors(o, data, c);
    return Semantics(
      button: true,
      selected: selected,
      label: '${o.event.title}, ${spanLabel(o)}${o.event.notes != null ? ', has notes' : ''}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: k.bg,
            borderRadius: BorderRadius.circular(7),
            boxShadow: selected ? [BoxShadow(color: k.dot, spreadRadius: 4), BoxShadow(color: c.surface, spreadRadius: 2)] : null,
          ),
          // A short event shows what fits.
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxHeight: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: 2,
              children: [
                Text(
                  o.event.title.isEmpty ? '(No title)' : o.event.title,
                  maxLines: 2,
                  overflow: TextOverflow.clip,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1.2, color: k.fg),
                ),
                Text(
                  spanLabel(o),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(fontSize: 11, color: k.fg.withValues(alpha: 0.85)),
                ),
                if (o.event.notes != null)
                  Row(
                    spacing: 3,
                    children: [
                      EIcon(EIcons.edit, size: 11, color: k.fg),
                      Text(
                        'notes',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: k.fg),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AllDayChip extends StatelessWidget {
  const _AllDayChip({required this.o, required this.data, required this.selected, required this.onTap});

  final Occurrence o;
  final CalendarData data;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final k = eventColors(o, data, c);
    return Semantics(
      button: true,
      selected: selected,
      label: '${o.event.title}, ${o.allDay ? 'all day' : spanLabel(o)}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: k.bg,
            borderRadius: BorderRadius.circular(5),
            border: selected ? Border.all(color: k.dot, width: 1.5) : null,
          ),
          child: Text(
            o.event.title,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: k.fg),
          ),
        ),
      ),
    );
  }
}

/// A month: six weeks from the Monday on or before the 1st.
class MonthGrid extends StatelessWidget {
  const MonthGrid({
    super.key,
    required this.month,
    required this.occurrences,
    required this.data,
    required this.today,
    required this.selected,
    required this.onPick,
    required this.onDay,
  });

  final DateTime month;
  final List<Occurrence> occurrences;
  final CalendarData data;
  final DateTime today;
  final String? selected;
  final ValueChanged<Occurrence> onPick;
  final ValueChanged<DateTime> onDay;

  static List<DateTime> daysOf(DateTime month) {
    final first = weekStart(DateTime(month.year, month.month));
    return [for (var i = 0; i < 42; i++) addDays(first, i)];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final days = daysOf(month);
    final byDay = <DateTime, List<Occurrence>>{};
    for (final o in occurrences) {
      final last = o.allDay ? addDays(o.end, -1) : dayOf(o.end.subtract(const Duration(microseconds: 1)));
      for (var d = dayOf(o.start); !d.isAfter(last); d = addDays(d, 1)) {
        (byDay[d] ??= []).add(o);
      }
    }
    return Column(
      children: [
        Container(
          height: 34,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.lineSoft)),
          ),
          child: Row(
            children: [
              for (final d in days.take(7))
                Expanded(
                  child: Center(
                    child: Text(
                      shortWeekday(d).toUpperCase(),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.66, color: c.textMuted),
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (var w = 0; w < 6; w++)
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final d in days.skip(w * 7).take(7))
                  Expanded(
                    child: _DayCell(day: d, inMonth: d.month == month.month, today: d == today, list: byDay[d] ?? const [], grid: this),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.inMonth, required this.today, required this.list, required this.grid});

  final DateTime day;
  final bool inMonth;
  final bool today;
  final List<Occurrence> list;
  final MonthGrid grid;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: '${dayTitle(day)}${list.isEmpty ? '' : ', ${list.length} ${list.length == 1 ? 'event' : 'events'}'}',
      explicitChildNodes: true,
      child: InkWell(
        onTap: () => grid.onDay(day),
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
          decoration: BoxDecoration(
            color: today ? c.accent.withValues(alpha: 0.05) : null,
            border: Border(
              right: BorderSide(color: c.lineSoft),
              bottom: BorderSide(color: c.lineSoft),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, box) {
              // Room for the number and as many 18 px events as fit.
              final fit = math.max(0, ((box.maxHeight - 26) / 19).floor());
              final shown = list.length > fit ? math.max(0, fit - 1) : list.length;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 1,
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: Container(
                      width: 24,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: today ? c.accent : null, borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: today ? FontWeight.w700 : FontWeight.w500,
                          color: today ? c.onAccent : (inMonth ? c.text : c.textFaint),
                        ),
                      ),
                    ),
                  ),
                  for (final o in list.take(shown))
                    SizedBox(
                      height: 18,
                      child: _MonthChip(o: o, data: grid.data, selected: o.key == grid.selected, onTap: () => grid.onPick(o)),
                    ),
                  if (shown < list.length)
                    Text(
                      '+${list.length - shown} more',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.textMuted),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MonthChip extends StatelessWidget {
  const _MonthChip({required this.o, required this.data, required this.selected, required this.onTap});

  final Occurrence o;
  final CalendarData data;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final k = eventColors(o, data, c);
    final text = o.allDay ? o.event.title : '${hm(o.start)} ${o.event.title}';
    return Semantics(
      button: true,
      selected: selected,
      label: '${o.event.title}, ${spanLabel(o)}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: o.allDay || selected ? k.bg : null,
            borderRadius: BorderRadius.circular(4),
            border: selected ? Border.all(color: k.dot, width: 1.5) : null,
          ),
          child: Row(
            spacing: 4,
            children: [
              if (!o.allDay)
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: k.dot, borderRadius: BorderRadius.circular(2)),
                ),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: o.allDay ? k.fg : c.text),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
