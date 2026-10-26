// Wording for reminders and study (Remember.dc.html, RememberMark.dc.html).

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Tomorrow" means tomorrow at 9 in the morning, local time.
DateTime tomorrowMorning(DateTime now) {
  final l = now.toLocal();
  return DateTime(l.year, l.month, l.day + 1, 9);
}

/// "9 AM", "6:30 PM".
String clockTime(DateTime t) {
  final l = t.toLocal();
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  final m = l.minute == 0 ? '' : ':${l.minute.toString().padLeft(2, '0')}';
  return '$h$m ${l.hour < 12 ? 'AM' : 'PM'}';
}

/// "Oct 14".
String monthDay(DateTime t) {
  final l = t.toLocal();
  return '${_months[l.month - 1]} ${l.day}';
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// A reminder's chip (Remember.png): "Today · 6 PM", "Tomorrow · 9 AM",
/// "Mon · 9 AM" within the week, "Tue 29 · 6 PM" this month, else
/// "Oct 14 · 9 AM".
String reminderChip(DateTime at, DateTime now) {
  final t = at.toLocal(), n = now.toLocal();
  final today = DateTime(n.year, n.month, n.day);
  final days = DateTime(t.year, t.month, t.day).difference(today).inDays;
  final time = clockTime(t);
  if (_sameDay(t, n)) return 'Today · $time';
  if (days == 1) return 'Tomorrow · $time';
  if (days > 1 && days < 7) return '${_weekdays[t.weekday - 1]} · $time';
  if (t.year == n.year && t.month == n.month) return '${_weekdays[t.weekday - 1]} ${t.day} · $time';
  return '${monthDay(t)} · $time';
}

/// After "reminder" in "Saved to Need to remember · reminder tomorrow".
String reminderShort(DateTime at, DateTime now) {
  if (_sameDay(at.toLocal(), tomorrowMorning(now)) && at.toLocal().hour == 9 && at.toLocal().minute == 0) {
    return 'tomorrow';
  }
  return reminderChip(at, now).replaceFirst(' · ', ', ');
}

String cardsLabel(int n) => n == 1 ? '1 card' : '$n cards';

String thingsLabel(int n) => n == 1 ? '1 thing' : '$n things';
