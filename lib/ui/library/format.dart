// Dates as the Start page and Library show them (English for now).

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

int _daysBetween(DateTime then, DateTime now) => _day(now).difference(_day(then)).inHours ~/ 24;

String _shortDate(DateTime t, DateTime now) {
  final d = '${_months[t.month - 1].substring(0, 3)} ${t.day}';
  return t.year == now.year ? d : '$d, ${t.year}';
}

/// "Friday, September 25".
String longDate(DateTime now) => '${_weekdays[now.weekday - 1]}, ${_months[now.month - 1]} ${now.day}';

/// For a card: "Edited 2h ago", "Yesterday", "Monday", "Sep 21".
String shortWhen(DateTime when, DateTime now) {
  final t = when.toLocal();
  final n = now.toLocal();
  final days = _daysBetween(t, n);
  if (days <= 0) {
    final mins = n.difference(t).inMinutes;
    if (mins < 1) return 'Edited just now';
    if (mins < 60) return 'Edited ${mins}m ago';
    return 'Edited ${mins ~/ 60}h ago';
  }
  if (days == 1) return 'Yesterday';
  if (days < 7) return _weekdays[t.weekday - 1];
  return _shortDate(t, n);
}

/// In a sentence: "2 hours ago", "yesterday", "on Monday", "on Sep 21".
String agoPhrase(DateTime when, DateTime now) {
  final t = when.toLocal();
  final n = now.toLocal();
  final days = _daysBetween(t, n);
  if (days <= 0) {
    final mins = n.difference(t).inMinutes;
    if (mins < 1) return 'just now';
    if (mins < 60) return mins == 1 ? '1 minute ago' : '$mins minutes ago';
    final hours = mins ~/ 60;
    return hours == 1 ? '1 hour ago' : '$hours hours ago';
  }
  if (days == 1) return 'yesterday';
  if (days < 7) return 'on ${_weekdays[t.weekday - 1]}';
  return 'on ${_shortDate(t, n)}';
}

/// "Yesterday" / "Monday" / "Sep 21" without the "Edited …" form for today.
String dayWhen(DateTime when, DateTime now) {
  final t = when.toLocal();
  final n = now.toLocal();
  final days = _daysBetween(t, n);
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return _weekdays[t.weekday - 1];
  return _shortDate(t, n);
}

String pagesLabel(int n) => n == 1 ? '1 page' : '$n pages';

String notebooksLabel(int n) => n == 1 ? '1 notebook' : '$n notebooks';

/// "School › Physics".
String folderLabel(List<String> path) => path.join(' › ');
