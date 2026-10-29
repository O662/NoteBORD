import 'dart:ui' show Color;

import '../theme/colors.dart';
import 'calendar_model.dart';

// How the calendar, the planner and their widgets say times and dates, and
// a calendar's colors (Calendar.dc.html's calDefs).

const weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

String shortWeekday(DateTime d) => weekdayNames[d.weekday - 1].substring(0, 3);
String shortMonth(DateTime d) => monthNames[d.month - 1].substring(0, 3);

/// "10:00", "1:30" (the design's times, without AM or PM).
String hm(DateTime t) => '${t.hour % 12 == 0 ? 12 : t.hour % 12}:${t.minute.toString().padLeft(2, '0')}';

/// "10:00 AM".
String hmAmPm(DateTime t) => '${hm(t)} ${t.hour < 12 ? 'AM' : 'PM'}';

/// "8 AM", "12 PM" (the grid's hours).
String hourLabel(int h) => '${h % 12 == 0 ? 12 : h % 12} ${h < 12 || h == 24 ? 'AM' : 'PM'}';

/// "10:00–11:15", or "all day".
String spanLabel(Occurrence o, {String dash = '–'}) => o.allDay ? 'all day' : '${hm(o.start)}$dash${hm(o.end)}';

/// "Fri, Sep 25 · 10:00 – 11:15" (the event panel).
String whenLabel(Occurrence o) {
  final day = '${shortWeekday(o.start)}, ${shortMonth(o.start)} ${o.start.day}';
  if (!o.allDay) return '$day · ${spanLabel(o, dash: ' – ')}';
  final last = addDays(o.end, -1);
  return last == dayOf(o.start) ? '$day · all day' : '$day – ${shortWeekday(last)}, ${shortMonth(last)} ${last.day}';
}

/// "Friday, Sep 25".
String dayTitle(DateTime d) => '${weekdayNames[d.weekday - 1]}, ${shortMonth(d)} ${d.day}';

/// "Fri 25".
String dayShort(DateTime d) => '${shortWeekday(d)} ${d.day}';

/// "September 2026".
String monthTitle(DateTime d) => '${monthNames[d.month - 1]} ${d.year}';

/// A calendar's swatch, its events' tint and their text.
({Color dot, Color bg, Color fg}) hueColors(CalendarHue h, EndlessColors c) => switch (h) {
  CalendarHue.blue => (dot: c.accent, bg: c.accentTint, fg: c.accentDeep),
  CalendarHue.green => (dot: c.green, bg: c.greenTint, fg: c.greenDeep),
  CalendarHue.clay => (dot: c.clay, bg: c.clayTint, fg: c.clayDeep),
  CalendarHue.plum => (dot: c.plum, bg: c.plumTint, fg: c.plumDeep),
};

/// The colors of [o]'s calendar in [data].
({Color dot, Color bg, Color fg}) eventColors(Occurrence o, CalendarData data, EndlessColors c) =>
    hueColors(data.calendar(o.event.calendarId)?.hue ?? CalendarHue.plum, c);
