import '../search/search_text.dart' show SearchRow;
import 'calendar_model.dart';

// "Note deadlines" (Calendar.png's plum chip): dates written in notes and on
// task boards after "due", read from the search index ("Problem set 4 due
// Sun", "Lab report due Sep 30, 11:59 PM"). They're made again whenever the
// index changes, and never stored.

const _months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
const _days = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

/// What's due and on which day, from a line of notes written at [written]
/// (dates without a year are the next one on or after it; weekdays the next
/// one after it). Null when it says no "due" with a date.
({String title, DateTime day})? parseDue(String text, DateTime written) {
  final m = RegExp(r'\bdue\b[\s:,]*(?:on\s+|by\s+)?(.+)$', caseSensitive: false).firstMatch(text);
  if (m == null) return null;
  final day = _dateAt(m[1]!.toLowerCase(), dayOf(written));
  if (day == null) return null;
  var title = text.substring(0, m.start).trim().replaceAll(RegExp(r'[\s:,–—-]+$'), '');
  if (title.isEmpty) title = 'Due';
  return (title: '$title due', day: day);
}

DateTime? _dateAt(String s, DateTime from) {
  if (s.startsWith('today')) return from;
  if (s.startsWith('tomorrow')) return addDays(from, 1);
  // "Sep 30", "September 30th", "30 Sep".
  final md =
      RegExp(r'^([a-z]{3})[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?\b').firstMatch(s) ??
      RegExp(r'^(\d{1,2})(?:st|nd|rd|th)?\s+([a-z]{3})[a-z]*\b').firstMatch(s);
  if (md != null) {
    final first = int.tryParse(md[1]!);
    final month = _months.indexOf(first == null ? md[1]! : md[2]!) + 1;
    final day = first ?? int.parse(md[2]!);
    if (month > 0) return _next(month, day, from);
  }
  // "9/30" (month first).
  final slash = RegExp(r'^(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b').firstMatch(s);
  if (slash != null) {
    final month = int.parse(slash[1]!), day = int.parse(slash[2]!);
    if (slash[3] case final y?) {
      final year = int.parse(y) < 100 ? 2000 + int.parse(y) : int.parse(y);
      return _valid(year, month, day);
    }
    return _next(month, day, from);
  }
  // "Sun", "next Monday".
  final wd = RegExp(r'^(?:next\s+)?([a-z]{3})[a-z]*\b').firstMatch(s);
  if (wd != null) {
    final i = _days.indexOf(wd[1]!);
    if (i >= 0) {
      final ahead = (i + 1 - from.weekday + 7) % 7;
      return addDays(from, ahead == 0 ? 7 : ahead);
    }
  }
  return null;
}

DateTime? _valid(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final d = DateTime(year, month, day);
  return d.month == month ? d : null;
}

/// [month]/[day] on or after [from], or within two months before it (a
/// deadline just past), else next year's.
DateTime? _next(int month, int day, DateTime from) {
  final d = _valid(from.year, month, day);
  if (d == null) return null;
  if (!d.isBefore(addDays(from, -60))) return d;
  return _valid(from.year + 1, month, day);
}

/// The deadlines in [rows] (the index's lines and typed text with "due"):
/// all-day events in the "Note deadlines" calendar, linked to their notes.
List<CalEvent> deadlinesIn(Iterable<SearchRow> rows) {
  final seen = <String>{};
  return [
    for (final r in rows)
      if (parseDue(r.text, r.at.toLocal()) case final due?)
        if (seen.add('${r.notebookId}/${r.ref}'))
          CalEvent(
            id: 'deadline:${r.notebookId}/${r.ref}',
            calendarId: CalendarInfo.deadlinesId,
            title: due.title,
            start: due.day,
            end: addDays(due.day, 1),
            allDay: true,
            notes: NoteLink(r.notebookId, pageId: r.pageId),
          ),
  ];
}
