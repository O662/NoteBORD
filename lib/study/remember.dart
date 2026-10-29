import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show immutable;

import '../board/model.dart';

// Need to remember (RememberMark.png): what an item's `remember` field says.

/// When to be reminded (RememberMark.dc.html's REMIND ME chips).
enum RemindKind {
  none,
  tomorrow,

  /// Before a calendar event ([RememberMark.event]).
  event,

  /// A date and time picked.
  date,
}

/// The event a reminder comes before: its id, the day it happens on (a
/// repeating event happens on many), its title when it was picked, and how
/// many minutes before it. If the event moves, the reminder moves with it.
@immutable
class EventLink {
  const EventLink({required this.id, required this.day, this.title = '', this.before = 30});

  static EventLink? fromJson(Object? json) => json is Map && json['id'] is String
      ? EventLink(
          id: json['id'] as String,
          day: json['day'] as String? ?? '',
          title: json['title'] as String? ?? '',
          before: (json['before'] as num?)?.toInt() ?? 30,
        )
      : null;

  final String id;

  /// "2026-09-25".
  final String day;
  final String title;
  final int before;

  @override
  bool operator ==(Object other) => other is EventLink && other.id == id && other.day == day && other.before == before;

  @override
  int get hashCode => Object.hash(id, day, before);

  Json toJson() => {'id': id, 'day': day, if (title.isNotEmpty) 'title': title, 'before': before};
}

/// An item's `remember` field. Items with the same [id] are one thing to
/// remember (what was lassoed together, or a drawn star and what's beside
/// it).
@immutable
class RememberMark {
  const RememberMark({
    required this.id,
    this.why = '',
    this.remind = RemindKind.none,
    this.remindAt,
    this.flashcard,
    this.drawn = false,
    this.star = false,
    this.at,
    this.event,
  });

  /// Reads [json] on [item]. A mark written before marks had ids (just
  /// `{why, remindAt, flashcard}`) is a thing of its own, named after the item.
  static RememberMark? of(Item item) {
    final json = item.remember;
    if (json == null) return null;
    final remindAt = DateTime.tryParse(json['remindAt'] as String? ?? '')?.toUtc();
    final kind = RemindKind.values.where((k) => k.name == json['remind']).firstOrNull ??
        (remindAt == null ? RemindKind.none : RemindKind.date);
    final card = json['flashcard'];
    return RememberMark(
      id: json['id'] as String? ?? item.id,
      why: json['why'] as String? ?? '',
      remind: kind,
      remindAt: remindAt,
      flashcard: card is String ? card : null,
      drawn: json['drawn'] == true,
      star: json['star'] == true,
      at: DateTime.tryParse(json['at'] as String? ?? '')?.toUtc(),
      event: EventLink.fromJson(json['event']),
    );
  }

  final String id;

  /// "Why it matters" (optional).
  final String why;
  final RemindKind remind;

  /// When the reminder goes off (UTC), or null for none.
  final DateTime? remindAt;

  /// The flashcard made from it ("Also make it a flashcard"), by id.
  final String? flashcard;

  /// Marked by drawing a star next to it.
  final bool drawn;

  /// This item is the drawn star itself (not part of what's remembered).
  final bool star;

  /// When it was marked.
  final DateTime? at;

  /// The event the reminder comes before ([RemindKind.event]).
  final EventLink? event;

  bool get hasReminder => remindAt != null && remind != RemindKind.none;

  RememberMark copyWith({
    String? why,
    RemindKind? remind,
    DateTime? Function()? remindAt,
    String? Function()? flashcard,
    bool? star,
  }) =>
      RememberMark(
        id: id,
        why: why ?? this.why,
        remind: remind ?? this.remind,
        remindAt: remindAt == null ? this.remindAt : remindAt(),
        flashcard: flashcard == null ? this.flashcard : flashcard(),
        drawn: drawn,
        star: star ?? this.star,
        at: at,
        event: event,
      );

  Json toJson() => {
        'id': id,
        if (why.isNotEmpty) 'why': why,
        if (remind != RemindKind.none) 'remind': remind.name,
        if (remindAt != null && remind != RemindKind.none) 'remindAt': remindAt!.toUtc().toIso8601String(),
        if (flashcard != null) 'flashcard': flashcard,
        if (drawn) 'drawn': true,
        if (star) 'star': true,
        if (at != null) 'at': at!.toUtc().toIso8601String(),
        if (event != null && remind == RemindKind.event) 'event': event!.toJson(),
      };
}

/// One thing to remember on a page: its items (without a drawn star) and
/// its mark.
class RememberGroup {
  RememberGroup(this.mark, this.items, {this.star});

  final RememberMark mark;
  final List<Item> items;

  /// The star drawn next to it, if it was marked that way.
  final StrokeItem? star;

  /// Where it is on the page (the star included).
  Rect get area {
    Rect? r;
    for (final i in [...items, ?star]) {
      r = r == null ? i.extent : r.expandToInclude(i.extent);
    }
    return r ?? Rect.zero;
  }

  /// Where what's remembered is (the star left out).
  Rect get content {
    Rect? r;
    for (final i in items) {
      r = r == null ? i.extent : r.expandToInclude(i.extent);
    }
    return r ?? area;
  }
}

/// The things to remember on [items], in the order first marked on the page.
List<RememberGroup> rememberGroups(Iterable<Item> items) {
  final marks = <String, RememberMark>{};
  final members = <String, List<Item>>{};
  final stars = <String, StrokeItem>{};
  for (final item in items) {
    if (item is FlashcardItem) continue;
    final mark = RememberMark.of(item);
    if (mark == null) continue;
    if (mark.star && item is StrokeItem) {
      stars[mark.id] = item;
      continue;
    }
    // The first item that isn't the star speaks for the group.
    marks.putIfAbsent(mark.id, () => mark);
    (members[mark.id] ??= []).add(item);
  }
  return [
    for (final e in marks.entries)
      if (members[e.key] case final list? when list.isNotEmpty) RememberGroup(e.value, list, star: stars[e.key]),
  ];
}
