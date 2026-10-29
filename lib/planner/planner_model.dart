import 'package:flutter/foundation.dart' show immutable;

import '../board/codec.dart' show decodeItem;
import '../board/model.dart';
import '../calendar/calendar_model.dart';

// The planner (Planner.png): to-dos, which can be given a day and a time
// on the schedule ("Drag a to-do here to block time"), and for each day the
// top 3 and notes for today, written with the pen. Kept in the app's
// planner.json; it works without any account.

List<StrokeItem> _ink(Object? list) => [
  for (final s in (list as List?) ?? const [])
    if (s is Map)
      if (decodeItem(s.cast<String, dynamic>()) case final StrokeItem stroke) stroke,
];

List<Json> _inkJson(List<StrokeItem> ink) => [for (final s in ink) s.toJson()];

Json _rest(Map json, Set<String> known) => {
  for (final e in json.entries)
    if (!known.contains(e.key)) e.key as String: e.value,
};

/// One to-do: typed, or written with the pen ([ink], from the top-left of
/// where it's written, at 100%) until its handwriting is read.
@immutable
class PlanTask {
  const PlanTask({
    required this.id,
    this.text = '',
    this.ink = const [],
    this.done = false,
    this.day,
    this.start,
    this.minutes = 60,
    this.deckId,
    required this.createdAt,
    this.doneAt,
    this.extra = const {},
  });

  static const _known = {'id', 'text', 'ink', 'done', 'day', 'start', 'minutes', 'deck', 'createdAt', 'doneAt'};

  static PlanTask? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String) return null;
    return PlanTask(
      id: json['id'] as String,
      text: json['text'] as String? ?? '',
      ink: _ink(json['ink']),
      done: json['done'] == true,
      day: parseDay(json['day']),
      start: (json['start'] as num?)?.toInt(),
      minutes: (json['minutes'] as num?)?.toInt() ?? 60,
      deckId: json['deck'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '')?.toUtc() ?? DateTime.utc(2026),
      doneAt: DateTime.tryParse(json['doneAt'] as String? ?? '')?.toUtc(),
      extra: _rest(json, _known),
    );
  }

  final String id;
  final String text;
  final List<StrokeItem> ink;
  final bool done;

  /// The day it's planned for, or null (it shows today until it's done).
  final DateTime? day;

  /// Blocked on [day]'s schedule: minutes after midnight, for [minutes].
  final int? start;
  final int minutes;

  /// "Review flashcards" for a deck with cards due.
  final String? deckId;
  final DateTime createdAt;
  final DateTime? doneAt;
  final Json extra;

  bool get scheduled => day != null && start != null;
  bool get isEmpty => text.trim().isEmpty && ink.isEmpty;

  /// When it's blocked, as local times.
  (DateTime, DateTime)? get block => scheduled ? (day!.add(Duration(minutes: start!)), day!.add(Duration(minutes: start! + minutes))) : null;

  PlanTask copyWith({
    String? text,
    List<StrokeItem>? ink,
    bool? done,
    DateTime? Function()? day,
    int? Function()? start,
    int? minutes,
    DateTime? Function()? doneAt,
  }) => PlanTask(
    id: id,
    text: text ?? this.text,
    ink: ink ?? this.ink,
    done: done ?? this.done,
    day: day == null ? this.day : day(),
    start: start == null ? this.start : start(),
    minutes: minutes ?? this.minutes,
    deckId: deckId,
    createdAt: createdAt,
    doneAt: doneAt == null ? this.doneAt : doneAt(),
    extra: extra,
  );

  Json toJson() => {
    ...extra,
    'id': id,
    if (text.isNotEmpty) 'text': text,
    if (ink.isNotEmpty) 'ink': _inkJson(ink),
    if (done) 'done': true,
    if (day != null) 'day': dayKey(day!),
    if (start != null) 'start': start,
    if (start != null) 'minutes': minutes,
    if (deckId != null) 'deck': deckId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (doneAt != null) 'doneAt': doneAt!.toUtc().toIso8601String(),
  };
}

/// One of a day's top 3: written with the pen, and ticked off by its number.
@immutable
class TopLine {
  const TopLine({this.ink = const [], this.done = false});

  static TopLine fromJson(Object? json) => json is Map ? TopLine(ink: _ink(json['ink']), done: json['done'] == true) : const TopLine();

  final List<StrokeItem> ink;
  final bool done;

  bool get isEmpty => ink.isEmpty;

  TopLine copyWith({List<StrokeItem>? ink, bool? done}) => TopLine(ink: ink ?? this.ink, done: done ?? this.done);

  Json toJson() => {if (ink.isNotEmpty) 'ink': _inkJson(ink), if (done) 'done': true};
}

/// What's written for one day.
@immutable
class PlanDay {
  const PlanDay({this.top = const [TopLine(), TopLine(), TopLine()], this.notes = const [], this.extra = const {}});

  static const empty = PlanDay();

  static PlanDay fromJson(Object? json) {
    if (json is! Map) return empty;
    final top = [for (final t in (json['top'] as List?) ?? const []) TopLine.fromJson(t)];
    while (top.length < 3) {
      top.add(const TopLine());
    }
    return PlanDay(top: top.take(3).toList(), notes: _ink(json['notes']), extra: _rest(json, const {'top', 'notes'}));
  }

  final List<TopLine> top;

  /// Notes for today, at 100% from the top-left of the lined area.
  final List<StrokeItem> notes;
  final Json extra;

  bool get isEmpty => notes.isEmpty && top.every((t) => t.isEmpty && !t.done) && extra.isEmpty;

  PlanDay copyWith({List<TopLine>? top, List<StrokeItem>? notes}) => PlanDay(top: top ?? this.top, notes: notes ?? this.notes, extra: extra);

  Json toJson() => {
    ...extra,
    if (top.any((t) => !t.isEmpty || t.done)) 'top': [for (final t in top) t.toJson()],
    if (notes.isNotEmpty) 'notes': _inkJson(notes),
  };
}

/// Everything in planner.json.
@immutable
class PlannerData {
  const PlannerData({this.tasks = const [], this.days = const {}, this.goals = const {}, this.extra = const {}});

  static PlannerData fromJson(Json? json) => PlannerData(
    tasks: [for (final t in (json?['tasks'] as List?) ?? const []) ?PlanTask.fromJson(t)],
    days: {
      for (final e in ((json?['days'] as Map?) ?? const {}).entries)
        if (parseDay(e.key) != null) e.key as String: PlanDay.fromJson(e.value),
    },
    goals: {
      for (final e in ((json?['weeks'] as Map?) ?? const {}).entries)
        if (parseDay(e.key) != null && e.value is Map) e.key as String: _ink((e.value as Map)['goals']),
    },
    extra: _rest(json ?? const {}, const {'version', 'tasks', 'days', 'weeks'}),
  );

  final List<PlanTask> tasks;

  /// [dayKey] → what's written that day.
  final Map<String, PlanDay> days;

  /// The Monday's [dayKey] → the week's goals, written with the pen.
  final Map<String, List<StrokeItem>> goals;
  final Json extra;

  PlanDay day(DateTime day) => days[dayKey(dayOf(day))] ?? PlanDay.empty;
  List<StrokeItem> goalsFor(DateTime day) => goals[dayKey(weekStart(day))] ?? const [];
  PlanTask? task(String id) => tasks.where((t) => t.id == id).firstOrNull;

  PlannerData copyWith({List<PlanTask>? tasks, Map<String, PlanDay>? days, Map<String, List<StrokeItem>>? goals}) =>
      PlannerData(tasks: tasks ?? this.tasks, days: days ?? this.days, goals: goals ?? this.goals, extra: extra);

  Json toJson() => {
    ...extra,
    'version': 1,
    'tasks': [for (final t in tasks) t.toJson()],
    'days': {
      for (final e in days.entries)
        if (!e.value.isEmpty) e.key: e.value.toJson(),
    },
    'weeks': {
      for (final e in goals.entries)
        if (e.value.isNotEmpty) e.key: {'goals': _inkJson(e.value)},
    },
  };

  /// The to-dos for [day] when it's [today]: those for that day, and on
  /// today also those without a day (not done, or done today) and any not
  /// done from the days before. Oldest first.
  List<PlanTask> todosFor(DateTime day, DateTime today) {
    final d = dayOf(day), t = dayOf(today);
    bool doneToday(PlanTask x) => x.doneAt != null && dayOf(x.doneAt!) == t;
    return [
      for (final x in tasks)
        if (x.day == d ||
            (d == t && ((x.day == null && (!x.done || doneToday(x))) || (x.day != null && x.day!.isBefore(t) && (!x.done || doneToday(x))))))
          x,
    ];
  }

  /// To-dos blocked on [day]'s schedule, by start.
  List<PlanTask> blocksOn(DateTime day) {
    final d = dayOf(day);
    return [
      for (final x in tasks)
        if (x.scheduled && x.day == d) x,
    ]..sort((a, b) => a.start!.compareTo(b.start!));
  }

  /// To-dos not done and not on a schedule, from [from] for [days] days, or
  /// without a day (Week's NOT SCHEDULED).
  List<PlanTask> unscheduled(DateTime from, int days) {
    final a = dayOf(from), b = addDays(a, days);
    return [
      for (final x in tasks)
        if (!x.done && !x.scheduled && (x.day == null || (!x.day!.isBefore(a) && x.day!.isBefore(b)))) x,
    ];
  }
}
