import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../calendar/calendar_format.dart';
import '../../calendar/calendar_model.dart';
import '../../calendar/calendar_state.dart';
import '../../library/library.dart';
import '../../study/study_state.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../common.dart';
import '../dialogs.dart';
import '../icons.dart';
import '../library/format.dart' show dayWhen, pagesLabel;
import '../library/sidebar.dart';
import '../routes.dart';
import '../study/study_format.dart' show cardsLabel;
import '../templates/templates_dialog.dart';
import 'calendar_grid.dart';
import 'calendar_widgets.dart';
import 'event_editor.dart';

// The calendar (Calendar.png): Day, Week and Month; a chip per calendar to
// show or hide it, and Connect; the event picked, with its notes ("Open
// notes" or "Start notes", or from a template) and the flashcards due from
// them ("Review before class").

enum CalendarView { day, week, month }

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key, this.view = CalendarView.week, this.day});

  final CalendarView view;

  /// The day shown first (today if null).
  final DateTime? day;

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late CalendarView _view = widget.view;
  late DateTime _day = dayOf(widget.day ?? _now);

  /// The occurrence shown in the panel, by key, or null for the next one
  /// today.
  String? _picked;
  bool _connect = false;
  Timer? _minute;

  DateTime get _now => ref.read(clockProvider)();

  @override
  void initState() {
    super.initState();
    // The red line moves with the time.
    _minute = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _minute?.cancel();
    super.dispose();
  }

  List<DateTime> get _days => switch (_view) {
    CalendarView.day => [_day],
    CalendarView.week => [for (var i = 0; i < 7; i++) addDays(weekStart(_day), i)],
    CalendarView.month => MonthGrid.daysOf(_day),
  };

  void _step(int n) => setState(() {
    _day = switch (_view) {
      CalendarView.day => addDays(_day, n),
      CalendarView.week => addDays(_day, 7 * n),
      CalendarView.month => DateTime(_day.year, _day.month + n),
    };
  });

  String get _title {
    if (_view == CalendarView.day) return dayTitle(_day);
    if (_view == CalendarView.month) return monthTitle(_day);
    final days = _days;
    final a = days.first, b = days.last;
    if (a.month == b.month) return monthTitle(a);
    return a.year == b.year ? '${shortMonth(a)} – ${monthTitle(b)}' : '${shortMonth(a)} ${a.year} – ${monthTitle(b)}';
  }

  Future<void> _newEvent([DateTime? at]) async {
    final start = at ?? _defaultStart();
    final result = await showEventEditor(context, start: start);
    if (result != null && mounted) setState(() => _picked = '${result.$2.id}@${dayKey(dayOf(result.$2.localStart))}');
  }

  /// The next whole hour on the day shown (today), or 9 AM.
  DateTime _defaultStart() {
    final now = _now;
    if (_day == dayOf(now) && now.hour < 23) return DateTime(now.year, now.month, now.day, now.hour + 1);
    return _day.add(const Duration(hours: 9));
  }

  Future<void> _edit(Occurrence o) async {
    final result = await showEventEditor(context, occurrence: o);
    if (result == null || !mounted) return;
    final (what, e) = result;
    final notifier = ref.read(calendarProvider.notifier);
    switch (what) {
      case EventEdit.saved:
        setState(() => _picked = null);
      case EventEdit.deleted || EventEdit.deletedOne:
        setState(() => _picked = null);
        showNote(context, what == EventEdit.deletedOne ? 'Deleted this one' : 'Deleted “${e.title}”', onUndo: () => notifier.restore(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final data = ref.watch(calendarProvider);
    final deadlines = ref.watch(deadlinesProvider);
    final now = _now;
    final today = dayOf(now);
    final days = _days;
    final shown = occurrencesIn(data, deadlines, days.first, addDays(days.last, 1));
    // The panel: the one picked, else the next one today.
    final todays = [
      for (final o in shown)
        if (dayOf(o.start) == today && !o.allDay) o,
    ];
    final picked =
        shown.where((o) => o.key == _picked).firstOrNull ??
        (_picked == null ? (todays.where((o) => o.end.isAfter(now)).firstOrNull ?? todays.lastOrNull) : null);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _step(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _step(1),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: c.bg,
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppSidebar(selected: SidebarItem.calendar),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: [
                      Row(
                        spacing: 10,
                        children: [
                          const CalendarPlannerSwitch(planner: false),
                          Expanded(child: CalendarTitle(_title)),
                          SecondaryButton(label: 'Today', height: 44, filled: true, onPressed: () => setState(() => _day = today)),
                          StepButtons(onStep: _step, unit: _view.name),
                          Segmented<CalendarView>(
                            label: 'View',
                            values: CalendarView.values,
                            labels: const ['Day', 'Week', 'Month'],
                            value: _view,
                            onChanged: (v) => setState(() => _view = v),
                          ),
                          PrimaryButton(label: 'Event', icon: EIcons.plus, height: 44, onPressed: () => _newEvent()),
                        ],
                      ),
                      _CalendarChips(data: data, onConnect: () => setState(() => _connect = true)),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 14,
                          children: [
                            Expanded(
                              child: CalendarCard(
                                child: _view == CalendarView.month
                                    ? MonthGrid(
                                        month: DateTime(_day.year, _day.month),
                                        occurrences: shown,
                                        data: data,
                                        today: today,
                                        selected: picked?.key,
                                        onPick: (o) => setState(() {
                                          _picked = o.key;
                                          _connect = false;
                                        }),
                                        onDay: (d) => setState(() {
                                          _day = d;
                                          _view = CalendarView.day;
                                        }),
                                      )
                                    : TimeGrid(
                                        key: ValueKey(_view),
                                        days: days,
                                        occurrences: shown,
                                        data: data,
                                        today: today,
                                        now: now,
                                        selected: picked?.key,
                                        onPick: (o) => setState(() {
                                          _picked = o.key;
                                          _connect = false;
                                        }),
                                        onEmpty: _newEvent,
                                      ),
                              ),
                            ),
                            SizedBox(
                              width: 262,
                              child: CalendarCard(
                                padding: const EdgeInsets.all(18),
                                child: _connect
                                    ? _ConnectPanel(onClose: () => setState(() => _connect = false))
                                    : picked == null
                                    ? _NothingPicked(onNew: () => _newEvent())
                                    : _EventPanel(o: picked, data: data, onEdit: () => _edit(picked)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A chip per calendar (tap to show or hide it), and Connect.
class _CalendarChips extends ConsumerWidget {
  const _CalendarChips({required this.data, required this.onConnect});

  final CalendarData data;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return SizedBox(
      height: 44,
      child: Semantics(
        container: true,
        label: 'Calendars shown',
        explicitChildNodes: true,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final cal in data.calendars) ...[
              Center(
                child: _CalendarChip(cal: cal, onTap: () => ref.read(calendarProvider.notifier).toggle(cal.id)),
              ),
              const SizedBox(width: 8),
            ],
            Center(
              child: Semantics(
                button: true,
                label: 'Connect calendars',
                excludeSemantics: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: onConnect,
                  child: DashedBorder(
                    color: c.lineDashed,
                    radius: 999,
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 6,
                        children: [
                          EIcon(EIcons.plus, size: 14, color: c.text),
                          Text(
                            'Connect',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarChip extends StatelessWidget {
  const _CalendarChip({required this.cal, required this.onTap});

  final CalendarInfo cal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final k = hueColors(cal.hue, c);
    return Semantics(
      button: true,
      toggled: cal.shown,
      label: '${cal.name}${cal.source.isEmpty ? '' : ', ${cal.source}'}',
      excludeSemantics: true,
      child: Material(
        color: cal.shown ? c.surface : Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: c.line)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: cal.shown ? k.dot : Colors.transparent,
                    border: Border.all(color: k.dot, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Text(
                  cal.name,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cal.shown ? c.text : c.textMuted),
                ),
                if (cal.source.isNotEmpty)
                  Text(
                    cal.source,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.textMuted),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NothingPicked extends StatelessWidget {
  const _NothingPicked({required this.onNew});

  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        Text(
          'Nothing picked',
          style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 26, height: 1.1, color: c.text),
        ),
        Text('Tap an event to see its notes, or an empty time to add one.', style: TextStyle(fontSize: 14, height: 1.4, color: c.textMuted)),
        const SizedBox(height: 4),
        PrimaryButton(label: 'New event', icon: EIcons.plus, height: 44, onPressed: onNew),
      ],
    );
  }
}

/// The event picked (Calendar.dc.html's aside).
class _EventPanel extends ConsumerWidget {
  const _EventPanel({required this.o, required this.data, required this.onEdit});

  final Occurrence o;
  final CalendarData data;
  final VoidCallback onEdit;

  Future<void> _startNotes(BuildContext context, WidgetRef ref) async {
    final id = await ref.read(libraryProvider.notifier).createNotebook(title: o.event.title.isEmpty ? 'Untitled notebook' : o.event.title);
    ref.read(calendarProvider.notifier).put(o.event.copyWith(notes: () => NoteLink(id)));
    if (context.mounted) context.push(Routes.notebook(id, page: 0));
  }

  void _fromTemplate(BuildContext context, WidgetRef ref) => showTemplatesDialog(
    context,
    title: o.event.title.isEmpty ? null : o.event.title,
    onCreated: (id) => ref.read(calendarProvider.notifier).put(o.event.copyWith(notes: () => NoteLink(id))),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final cal = data.calendar(o.event.calendarId);
    final k = eventColors(o, data, c);
    final link = o.event.notes;
    final lib = ref.watch(libraryProvider);
    final nb = link == null ? null : lib.byId(link.notebookId);
    final hasNotes = nb != null && !nb.trashed;
    final editable = cal?.editable ?? false;
    final now = ref.read(clockProvider)();

    // Flashcards due from these notes, in the deck with the most.
    DeckSummary? deck;
    if (hasNotes) {
      final study = ref.watch(studyProvider);
      final decks = ref.watch(decksProvider);
      if (study != null) {
        for (final s in deckSummaries(study, decks, now.toUtc())) {
          final due = s.items.where((i) => i.card.notebookId == nb.id && i.dueAt(now.toUtc())).length;
          if (due > 0 && (deck == null || due > deck.due)) {
            deck = DeckSummary(s.deck, [
              for (final i in s.items)
                if (i.card.notebookId == nb.id) i,
            ], now: now.toUtc());
          }
        }
      }
    }

    String meta() {
      if (!hasNotes) return '';
      final when = dayWhen(nb.updatedAt, now).toLowerCase();
      if (link!.pageId != null) {
        final pages = ref.watch(pageIdsProvider(nb.id)).value;
        final i = pages?.indexOf(link.pageId!) ?? -1;
        if (i >= 0) return 'Page ${i + 1} · $when';
      }
      return '${pagesLabel(nb.pageCount)} · $when';
    }

    void open() {
      if (link?.pageId != null) {
        openSpot(context, ref, link!.notebookId, link.pageId!, null);
      } else {
        openNotebook(context, ref, link!.notebookId);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 14,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 6,
          children: [
            Row(
              spacing: 8,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: k.dot, borderRadius: BorderRadius.circular(3)),
                ),
                Expanded(
                  child: Text(
                    cal?.fullName ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textMuted),
                  ),
                ),
                if (editable)
                  Transform.translate(
                    offset: const Offset(10, 0),
                    child: ChromeButton(label: 'Change event', icon: EIcons.edit, iconSize: 18, foreground: c.textMuted, onPressed: onEdit),
                  ),
              ],
            ),
            Text(
              o.event.title,
              style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 26, height: 1.1, color: c.text),
            ),
            Text(whenLabel(o), style: TextStyle(fontSize: 14, color: c.textMuted)),
          ],
        ),
        Container(height: 1, color: c.lineSoft),
        const CardLabel('NOTES FOR THIS EVENT'),
        if (hasNotes)
          Semantics(
            button: true,
            label: 'Open ${nb.title}, ${meta()}',
            excludeSemantics: true,
            child: Material(
              color: Colors.transparent,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: c.line),
                borderRadius: BorderRadius.circular(12),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: open,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    spacing: 12,
                    children: [
                      const _NotesThumb(),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 1,
                          children: [
                            Text(
                              nb.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text),
                            ),
                            Text(meta(), style: TextStyle(fontSize: 12, color: c.textMuted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else
          Text('No notes yet.', style: TextStyle(fontSize: 14, color: c.textMuted)),
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: PrimaryButton(
                label: hasNotes ? 'Open notes' : 'Start notes',
                height: 44,
                expand: true,
                padding: 12,
                onPressed: hasNotes ? open : (editable ? () => _startNotes(context, ref) : null),
              ),
            ),
            if (!hasNotes && editable) SecondaryButton(label: 'Template', height: 44, padding: 12, onPressed: () => _fromTemplate(context, ref)),
          ],
        ),
        if (deck != null)
          Semantics(
            button: true,
            label: 'Review before class, ${deck.deck.name}, ${cardsLabel(deck.due)} due',
            excludeSemantics: true,
            child: Material(
              color: c.clayTint,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => context.go(Routes.flashcards(deck!.deck.id)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    spacing: 10,
                    children: [
                      EIcon(EIcons.flashcards, size: 18, color: c.clayDeep),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Review before class',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.clayDeep),
                            ),
                            Text('${deck.deck.name} · ${cardsLabel(deck.due)} due', style: TextStyle(fontSize: 12, color: c.clayDeep)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const Spacer(),
        Text(switch (cal?.kind) {
          CalendarKind.google || CalendarKind.outlook => 'Changes here also update ${cal!.updates}.',
          CalendarKind.deadlines => 'From your notes. Change the date there to move it.',
          _ => 'Kept on this tablet.',
        }, style: TextStyle(fontSize: 12, color: c.textMuted)),
      ],
    );
  }
}

/// A little dotted page with "notes" on it (Calendar.dc.html).
class _NotesThumb extends StatelessWidget {
  const _NotesThumb();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: 56,
      height: 44,
      decoration: BoxDecoration(
        color: c.bg,
        border: Border.all(color: c.cardLine),
        borderRadius: BorderRadius.circular(6),
      ),
      child: CustomPaint(
        painter: _Dots(c.dot),
        child: Center(
          child: Text(
            'notes',
            style: TextStyle(fontFamily: FontFamilies.handwritingSample, fontSize: 15, color: c.accent),
          ),
        ),
      ),
    );
  }
}

class _Dots extends CustomPainter {
  _Dots(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    for (var y = 4.0; y < size.height; y += 8) {
      for (var x = 4.0; x < size.width; x += 8) {
        canvas.drawCircle(Offset(x, y), 1, p);
      }
    }
  }

  @override
  bool shouldRepaint(_Dots old) => old.color != color;
}

/// Calendars: the accounts connected, and adding one (Calendar.dc.html's
/// connect panel).
class _ConnectPanel extends ConsumerWidget {
  const _ConnectPanel({required this.onClose});

  final VoidCallback onClose;

  Future<void> _addLocal(BuildContext context, WidgetRef ref) async {
    final name = await showNamePrompt(context, title: 'New calendar', hint: 'School', action: 'Add');
    if (name == null) return;
    final used = {for (final cal in ref.read(calendarProvider).calendars) cal.hue};
    final hue = CalendarHue.values.where((h) => !used.contains(h)).firstOrNull ?? CalendarHue.values[used.length % CalendarHue.values.length];
    ref.read(calendarProvider.notifier).addCalendar(name, hue);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final data = ref.watch(calendarProvider);
    final local = [
      for (final cal in data.calendars)
        if (cal.kind == CalendarKind.local) cal.name,
    ];
    final accounts = <String, List<CalendarInfo>>{};
    for (final cal in data.calendars) {
      if (cal.synced) (accounts['${cal.source}|${cal.account ?? ''}'] ??= []).add(cal);
    }
    Widget card(String title, String sub, String names) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text),
          ),
          if (sub.isNotEmpty) Text(sub, style: TextStyle(fontSize: 12, color: c.textMuted)),
          Text(names, style: TextStyle(fontSize: 13, color: c.textMuted)),
        ],
      ),
    );
    void soon() => showNote(context, 'Connecting accounts comes in the next update. Events you add now stay on this tablet.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Calendars',
                style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 24, color: c.text),
              ),
            ),
            Transform.translate(
              offset: const Offset(10, 0),
              child: DialogCloseButton(onPressed: onClose),
            ),
          ],
        ),
        for (final e in accounts.entries)
          card('${e.key.split('|').first} · connected', e.value.first.account ?? '', e.value.map((x) => x.name).join(', ')),
        if (local.isNotEmpty) card('On this tablet', '', local.join(', ')),
        SecondaryButton(label: 'Add a Google account', height: 44, expand: true, onPressed: soon),
        SecondaryButton(label: 'Add Outlook / Microsoft 365', height: 44, expand: true, onPressed: soon),
        SecondaryButton(label: 'New calendar on this tablet', height: 44, expand: true, onPressed: () => _addLocal(context, ref)),
        const Spacer(),
        Text(
          'Syncs both ways. Note deadlines come from dates you write in notes and task boards.',
          style: TextStyle(fontSize: 12, height: 1.45, color: c.textMuted),
        ),
      ],
    );
  }
}
