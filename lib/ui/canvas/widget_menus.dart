import 'package:flutter/material.dart';

import '../../calendar/calendar_format.dart';
import '../../calendar/calendar_model.dart';
import '../../study/study_state.dart' show Deck;
import '../../theme/colors.dart';
import '../dialogs.dart';

// Choices for widgets on the page (WidgetBoard.png's options): which
// calendars a calendar widget shows, a flashcards widget's deck, and a Need
// to remember widget's folder.

/// The calendars a calendar widget shows: returns the ids it hides, or null
/// for Cancel.
Future<List<String>?> showWidgetCalendars(BuildContext context, List<CalendarInfo> calendars, List<String> hidden) =>
    showEndlessDialog<List<String>>(context, builder: (_) => _Calendars(calendars, hidden));

class _Calendars extends StatefulWidget {
  const _Calendars(this.calendars, this.hidden);

  final List<CalendarInfo> calendars;
  final List<String> hidden;

  @override
  State<_Calendars> createState() => _CalendarsState();
}

class _CalendarsState extends State<_Calendars> {
  late final _hidden = {...widget.hidden};

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DialogFrame(
      title: 'Calendars on this page',
      width: 440,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
        for (final cal in widget.calendars)
          Semantics(
            checked: !_hidden.contains(cal.id),
            label: cal.source.isEmpty ? cal.name : '${cal.name}, ${cal.source}',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _hidden.contains(cal.id) ? _hidden.remove(cal.id) : _hidden.add(cal.id)),
              child: SizedBox(
                height: 48,
                child: Row(spacing: 12, children: [
                  Checkbox(
                    value: !_hidden.contains(cal.id),
                    onChanged: (_) => setState(() => _hidden.contains(cal.id) ? _hidden.remove(cal.id) : _hidden.add(cal.id)),
                    activeColor: hueColors(cal.hue, c).dot,
                  ),
                  Expanded(child: Text(cal.name, style: TextStyle(fontSize: 15, color: c.text))),
                  Text(cal.source, style: TextStyle(fontSize: 13, color: c.textMuted)),
                ]),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 10, children: [
          SecondaryButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
          PrimaryButton(label: 'Done', onPressed: () => Navigator.of(context).pop([..._hidden])),
        ]),
      ]),
    );
  }
}

/// One of [options], as a list of buttons; null for Cancel.
Future<T?> showWidgetPick<T>(BuildContext context, {required String title, required List<(T, String)> options, required bool Function(T) isCurrent}) =>
    showEndlessDialog<T>(
      context,
      builder: (context) {
        final c = context.colors;
        return DialogFrame(
          title: title,
          width: 440,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: ListView(shrinkWrap: true, children: [
              for (final (value, label) in options)
                Semantics(
                  button: true,
                  selected: isCurrent(value),
                  label: label,
                  excludeSemantics: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => Navigator.of(context).pop(value),
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: isCurrent(value) ? c.sideSelected : null,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.centerLeft,
                      child: Text(label, style: TextStyle(fontSize: 15, fontWeight: isCurrent(value) ? FontWeight.w600 : FontWeight.w400, color: c.text)),
                    ),
                  ),
                ),
            ]),
          ),
        );
      },
    );

/// A deck for a flashcards widget.
Future<Deck?> showWidgetDeck(BuildContext context, List<Deck> decks, String current) =>
    showWidgetPick<Deck>(context, title: 'Which deck?', options: [for (final d in decks) (d, d.name)], isCurrent: (d) => d.id == current);

/// A folder for a Need to remember widget (empty: every notebook).
Future<List<String>?> showWidgetFolder(BuildContext context, List<List<String>> folders, List<String> current) =>
    showWidgetPick<List<String>>(
      context,
      title: 'Remember from',
      options: [(const <String>[], 'Every notebook'), for (final f in folders) (f, f.join(' › '))],
      isCurrent: (f) => f.join('/') == current.join('/'),
    );
