import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../calendar/calendar_format.dart';
import '../../calendar/calendar_model.dart';
import '../../calendar/calendar_state.dart';
import '../../library/library.dart' show clockProvider;
import '../../study/remember.dart' show EventLink;
import '../../theme/colors.dart';
import '../dialogs.dart';
import 'calendar_widgets.dart' show CardLabel;

// "Before an event" (RememberMark.png's REMIND ME): an event in the next
// two weeks, and how long before it.

/// How long before, in minutes.
const reminderLeads = [(0, 'When it starts'), (15, '15 min'), (60, '1 hour'), (24 * 60, '1 day')];

/// "Before Physics lecture" for a chip.
String beforeLabel(EventLink e) {
  final title = e.title.length > 22 ? '${e.title.substring(0, 21)}…' : e.title;
  return title.isEmpty ? 'Before an event' : 'Before $title';
}

/// Picks an event coming up and how long before it to be reminded. Returns
/// the link and when the reminder goes off, or null for Cancel.
Future<(EventLink, DateTime)?> showEventPicker(BuildContext context, {EventLink? current}) =>
    showEndlessDialog<(EventLink, DateTime)>(context, builder: (_) => _EventPicker(current: current));

class _EventPicker extends ConsumerStatefulWidget {
  const _EventPicker({this.current});

  final EventLink? current;

  @override
  ConsumerState<_EventPicker> createState() => _EventPickerState();
}

class _EventPickerState extends ConsumerState<_EventPicker> {
  late int _before = widget.current?.before ?? 15;

  void _pick(Occurrence o) {
    final start = o.allDay ? o.start.add(const Duration(hours: 9)) : o.start;
    final link = EventLink(id: o.event.id, day: dayKey(dayOf(o.start)), title: o.event.title, before: _before);
    Navigator.of(context).pop((link, start.subtract(Duration(minutes: _before)).toUtc()));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = ref.read(clockProvider)();
    final today = dayOf(now);
    final data = ref.watch(calendarProvider);
    final coming = [
      for (final o in occurrencesIn(data, ref.watch(deadlinesProvider), today, addDays(today, 14)))
        if ((o.allDay ? o.start.add(const Duration(hours: 9)) : o.start).isAfter(now)) o,
    ]..sort((a, b) => a.start.compareTo(b.start));

    final rows = <Widget>[];
    DateTime? shownDay;
    for (final o in coming) {
      final day = dayOf(o.start);
      if (day != shownDay) {
        shownDay = day;
        final name = day == today ? 'TODAY · ${dayShort(day).toUpperCase()}' : (day == addDays(today, 1) ? 'TOMORROW · ${dayShort(day).toUpperCase()}' : dayShort(day).toUpperCase());
        rows.add(Padding(padding: const EdgeInsets.fromLTRB(4, 12, 4, 4), child: CardLabel(name, size: 11)));
      }
      final k = eventColors(o, data, c);
      final picked = widget.current?.id == o.event.id && widget.current?.day == dayKey(day);
      rows.add(Semantics(
        button: true,
        selected: picked,
        label: '${o.event.title}, ${whenLabel(o)}',
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _pick(o),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: picked ? c.sideSelected : null, borderRadius: BorderRadius.circular(10)),
            child: Row(spacing: 10, children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: k.dot, borderRadius: BorderRadius.circular(3))),
              SizedBox(width: 72, child: Text(o.allDay ? 'all day' : hmAmPm(o.start), style: TextStyle(fontSize: 13, color: c.textMuted))),
              Expanded(child: Text(o.event.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, color: c.text))),
            ]),
          ),
        ),
      ));
    }

    Widget chip(int minutes, String text) {
      final on = minutes == _before;
      return Semantics(
        button: true,
        inMutuallyExclusiveGroup: true,
        selected: on,
        label: text,
        excludeSemantics: true,
        child: Material(
          color: on ? c.inverse : Colors.transparent,
          shape: StadiumBorder(side: BorderSide(color: on ? c.inverse : c.lineStrong)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => setState(() => _before = minutes),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Center(widthFactor: 1, child: Text(text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: on ? c.onInverse : c.text))),
            ),
          ),
        ),
      );
    }

    return DialogFrame(
      title: 'Remind me before',
      width: 520,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [for (final (m, t) in reminderLeads) chip(m, t)]),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: coming.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Nothing on your calendar in the next two weeks. Add an event in the Calendar first.',
                    style: TextStyle(fontSize: 15, height: 1.4, color: c.textMuted),
                  ),
                )
              : ListView(shrinkWrap: true, children: rows),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          SecondaryButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
        ]),
      ]),
    );
  }
}
