import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../calendar/calendar_format.dart';
import '../../calendar/calendar_model.dart';
import '../../calendar/calendar_state.dart';
import '../../theme/colors.dart';
import '../dialogs.dart';

// Adding and changing an event: its title, calendar, day and times, and
// whether it repeats. Changes to a repeating event apply to every time it
// happens; Delete asks whether to delete just the one.

/// What happened in the editor.
enum EventEdit { saved, deleted, deletedOne }

/// Opens the editor for [occurrence] (changing it) or a new event at
/// [start]. Returns what was done and the event as saved (or as it was
/// before it was deleted, for Undo).
Future<(EventEdit, CalEvent)?> showEventEditor(BuildContext context, {Occurrence? occurrence, DateTime? start, bool allDay = false}) =>
    showEndlessDialog<(EventEdit, CalEvent)>(
      context,
      builder: (_) => _EventEditor(occurrence: occurrence, start: start, allDay: allDay),
    );

class _EventEditor extends ConsumerStatefulWidget {
  const _EventEditor({this.occurrence, this.start, this.allDay = false});

  final Occurrence? occurrence;
  final DateTime? start;
  final bool allDay;

  @override
  ConsumerState<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends ConsumerState<_EventEditor> {
  CalEvent? get _old => widget.occurrence?.event;
  late final _title = TextEditingController(text: _old?.title ?? '');
  late String _calendar = _old?.calendarId ?? ref.read(calendarProvider.notifier).defaultCalendar.id;
  late bool _allDay = _old?.allDay ?? widget.allDay;

  /// The first day (a repeating event's first time, not the one tapped).
  late DateTime _day = dayOf(_old?.localStart ?? widget.start ?? DateTime.now());
  late TimeOfDay _from = TimeOfDay.fromDateTime(_old?.localStart ?? widget.start ?? DateTime.now());
  late TimeOfDay _to = TimeOfDay.fromDateTime(_old?.localEnd ?? (widget.start ?? DateTime.now()).add(const Duration(hours: 1)));
  late final int _days = _old != null && _old!.allDay ? _old!.length.inDays.clamp(1, 365) : 1;
  late RepeatEvery? _repeat = _old?.repeat?.every;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

  Future<void> _pickDay() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(_day.year - 5),
      lastDate: DateTime(_day.year + 10, 12, 31),
    );
    if (d != null && mounted) setState(() => _day = dayOf(d));
  }

  Future<void> _pickTime(bool start) async {
    final t = await showTimePicker(context: context, initialTime: start ? _from : _to);
    if (t == null || !mounted) return;
    setState(() {
      if (start) {
        // The end keeps the length.
        final length = _minutes(_to) - _minutes(_from);
        _from = t;
        final end = (_minutes(t) + (length > 0 ? length : 60)).clamp(0, 24 * 60 - 1);
        _to = TimeOfDay(hour: end ~/ 60, minute: end % 60);
      } else {
        _to = t;
      }
    });
  }

  bool get _valid => _title.text.trim().isNotEmpty && (_allDay || _minutes(_to) > _minutes(_from));

  void _save() {
    if (!_valid) return;
    final notifier = ref.read(calendarProvider.notifier);
    final DateTime start, end;
    if (_allDay) {
      start = _day;
      end = addDays(_day, _days);
    } else {
      start = _day.add(Duration(minutes: _minutes(_from))).toUtc();
      end = _day.add(Duration(minutes: _minutes(_to))).toUtc();
    }
    final keep = _old?.repeat;
    final repeat = _repeat == null ? null : (keep != null && keep.every == _repeat ? keep : Repeat(_repeat!));
    final e = _old == null
        ? notifier.newEvent(title: _title.text.trim(), start: start, end: end, allDay: _allDay, calendarId: _calendar).copyWith(repeat: () => repeat)
        : _old!.copyWith(title: _title.text.trim(), calendarId: _calendar, start: start, end: end, allDay: _allDay, repeat: () => repeat);
    notifier.put(e);
    Navigator.of(context).pop((EventEdit.saved, e));
  }

  Future<void> _delete() async {
    final old = _old!;
    final notifier = ref.read(calendarProvider.notifier);
    if (old.repeat != null) {
      final which = await showEndlessDialog<bool>(
        context,
        builder: (context) => DialogFrame(
          title: 'Delete a repeating event',
          width: 460,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 18,
            children: [
              Text(
                '“${old.title}” repeats. Delete just this one, or every time?',
                style: TextStyle(fontSize: 15, height: 1.45, color: context.colors.textMuted),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: 10,
                children: [
                  SecondaryButton(label: 'Every time', onPressed: () => Navigator.of(context).pop(false)),
                  PrimaryButton(label: 'Just this one', onPressed: () => Navigator.of(context).pop(true)),
                ],
              ),
            ],
          ),
        ),
      );
      if (which == null || !mounted) return;
      if (which) {
        notifier.skip(widget.occurrence!);
        Navigator.of(context).pop((EventEdit.deletedOne, old));
        return;
      }
    }
    notifier.delete(old.id);
    if (mounted) Navigator.of(context).pop((EventEdit.deleted, old));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final data = ref.watch(calendarProvider);
    final calendars = [
      for (final cal in data.calendars)
        if (cal.editable) cal,
    ];
    final label = TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.text);

    Widget chip(String text, bool on, VoidCallback onTap, {Color? swatch}) => Semantics(
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
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                if (swatch != null)
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(color: swatch, borderRadius: BorderRadius.circular(4)),
                  ),
                Text(
                  text,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: on ? c.onInverse : c.text),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    Widget pickButton(String semantic, String text, VoidCallback onTap) => Semantics(
      button: true,
      label: '$semantic, $text',
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: c.lineStrong),
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.centerLeft,
            child: Text(text, style: TextStyle(fontSize: 16, color: c.text)),
          ),
        ),
      ),
    );

    final repeats = [
      (null, 'Never'),
      (RepeatEvery.day, 'Every day'),
      (RepeatEvery.weekdays, 'Weekdays'),
      (RepeatEvery.week, 'Every ${weekdayNames[_day.weekday - 1]}'),
    ];
    final updates = data.calendar(_calendar)?.updates ?? '';

    return DialogFrame(
      title: _old == null ? 'New event' : 'Change event',
      width: 560,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          LabeledField(
            label: 'What',
            controller: _title,
            hint: 'Physics lecture',
            autofocus: _old == null,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(),
            textInputAction: TextInputAction.done,
          ),
          if (calendars.length > 1)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 6,
              children: [
                Text('Calendar', style: label),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final cal in calendars)
                      chip(
                        cal.synced ? '${cal.name} · ${cal.source}' : cal.name,
                        cal.id == _calendar,
                        () => setState(() => _calendar = cal.id),
                        swatch: hueColors(cal.hue, c).dot,
                      ),
                  ],
                ),
              ],
            ),
          Row(
            spacing: 10,
            children: [
              Expanded(child: pickButton('Day', '${dayTitle(_day)} ${_day.year}', _pickDay)),
              if (!_allDay) ...[
                SizedBox(width: 110, child: pickButton('Starts', hmAmPm(_day.add(Duration(minutes: _minutes(_from)))), () => _pickTime(true))),
                Text('–', style: TextStyle(fontSize: 16, color: c.textMuted)),
                SizedBox(width: 110, child: pickButton('Ends', hmAmPm(_day.add(Duration(minutes: _minutes(_to)))), () => _pickTime(false))),
              ],
            ],
          ),
          Semantics(
            toggled: _allDay,
            label: 'All day',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _allDay = !_allDay),
              child: SizedBox(
                height: 44,
                child: Row(
                  children: [
                    Expanded(child: Text('All day', style: label)),
                    Switch(value: _allDay, onChanged: (v) => setState(() => _allDay = v), activeTrackColor: c.accent),
                  ],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 6,
            children: [
              Text('Repeats', style: label),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final (v, text) in repeats) chip(text, v == _repeat, () => setState(() => _repeat = v))],
              ),
              if (_old?.repeat != null) Text('Changes apply to every time it repeats.', style: TextStyle(fontSize: 13, color: c.textMuted)),
            ],
          ),
          if (!_allDay && _title.text.trim().isNotEmpty && _minutes(_to) <= _minutes(_from))
            Text('It has to end after it starts.', style: TextStyle(fontSize: 13, color: c.danger)),
          Row(
            spacing: 10,
            children: [
              if (_old != null)
                TextButton(
                  onPressed: _delete,
                  style: TextButton.styleFrom(foregroundColor: c.danger, minimumSize: const Size(44, 48)),
                  child: const Text('Delete', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              Expanded(
                child: updates.isEmpty ? const SizedBox() : Text('Also changes it in $updates.', style: TextStyle(fontSize: 13, color: c.textMuted)),
              ),
              SecondaryButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
              PrimaryButton(label: 'Save', onPressed: _valid ? _save : null),
            ],
          ),
        ],
      ),
    );
  }
}
