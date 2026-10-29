import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../board/model.dart';
import '../../calendar/calendar_format.dart';
import '../../calendar/calendar_model.dart';
import '../../calendar/calendar_state.dart';
import '../../library/library.dart';
import '../../planner/planner_model.dart';
import '../../planner/planner_state.dart';
import '../../recognition/handwriting_index.dart' show handwritingLanguage;
import '../../recognition/recognizer.dart';
import '../../state/settings.dart';
import '../../study/study_state.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../common.dart';
import '../dialogs.dart';
import '../library/sidebar.dart';
import '../routes.dart';
import 'calendar_grid.dart' show layoutDay;
import 'calendar_widgets.dart';
import 'ink_pad.dart';

// The planner (Planner.png): Today (top 3, to-dos, the day's schedule with
// the calendar's events and the time blocked for to-dos, notes for today,
// and tomorrow), 3 days and Week. It's all kept on the tablet and needs no
// account. To-dos are dragged by their handle onto the schedule to block
// time, or onto a day.

enum PlanRange { today, three, week }

class PlannerScreen extends ConsumerStatefulWidget {
  const PlannerScreen({super.key, this.range = PlanRange.today});

  final PlanRange range;

  @override
  ConsumerState<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends ConsumerState<PlannerScreen> {
  late PlanRange _range = widget.range;
  late DateTime _day = dayOf(ref.read(clockProvider)());
  Timer? _minute;

  @override
  void initState() {
    super.initState();
    _minute = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _minute?.cancel();
    super.dispose();
  }

  DateTime get _first => _range == PlanRange.week ? weekStart(_day) : _day;

  void _step(int n) => setState(
    () => _day = addDays(
      _day,
      n *
          switch (_range) {
            PlanRange.today => 1,
            PlanRange.three => 3,
            PlanRange.week => 7,
          },
    ),
  );

  String get _title => switch (_range) {
    PlanRange.today => dayTitle(_day),
    PlanRange.three => '${dayShort(_day)} – ${dayShort(addDays(_day, 2))}',
    PlanRange.week => 'Week of ${shortMonth(_first)} ${_first.day}',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
                    spacing: 14,
                    children: [
                      Row(
                        spacing: 10,
                        children: [
                          const CalendarPlannerSwitch(planner: true),
                          Expanded(child: CalendarTitle(_title)),
                          if (_day != dayOf(ref.read(clockProvider)()))
                            SecondaryButton(
                              label: 'Today',
                              height: 44,
                              filled: true,
                              onPressed: () => setState(() => _day = dayOf(ref.read(clockProvider)())),
                            ),
                          StepButtons(onStep: _step, unit: ''),
                          Segmented<PlanRange>(
                            label: 'Plan range',
                            values: PlanRange.values,
                            labels: const ['Today', '3 days', 'Week'],
                            value: _range,
                            padding: 14,
                            onChanged: (v) => setState(() => _range = v),
                          ),
                        ],
                      ),
                      Expanded(
                        child: switch (_range) {
                          PlanRange.today => _TodayView(day: _day),
                          PlanRange.three => _ThreeDays(first: _day),
                          PlanRange.week => _WeekView(first: _first),
                        },
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

// Shared.

DateTime _today(WidgetRef ref) => dayOf(ref.read(clockProvider)());

/// [day]'s to-dos, live.
List<Todo> _todos(WidgetRef ref, DateTime day) {
  final now = ref.read(clockProvider)();
  return todosFor(ref.watch(plannerProvider), ref.watch(studyProvider), ref.watch(decksProvider), day, dayOf(now), now.toUtc());
}

/// The to-do itself, made for a deck's "Review flashcards" the first time
/// it's ticked or planned.
PlanTask _real(WidgetRef ref, Todo t) => ref.read(plannerProvider.notifier).real(t);

void _tick(WidgetRef ref, Todo t, bool done) => ref.read(plannerProvider.notifier).tick(_real(ref, t), done);

/// A planned block's colors: clay for flashcards, plum for the rest
/// (Planner.dc.html).
({Color dot, Color bg, Color fg}) _plannedColors(PlanTask t, EndlessColors c) => hueColors(t.deckId != null ? CalendarHue.clay : CalendarHue.plum, c);

String _taskLabel(PlanTask t) => t.text.isNotEmpty ? t.text : (t.deckId != null ? 'Review flashcards' : 'To-do');

/// The calendar's timed and all-day events on [day].
List<Occurrence> _events(WidgetRef ref, DateTime day) =>
    occurrencesIn(ref.watch(calendarProvider), ref.watch(deadlinesProvider), day, addDays(day, 1));

/// Reads handwriting written as a to-do, or null where it can't be read.
Future<String?> readHandwriting(WidgetRef ref, List<StrokeItem> ink) async {
  final r = ref.read(inkRecognizerProvider);
  if (!r.available || ink.isEmpty) return null;
  final language = handwritingLanguage(ref.read(settingsProvider));
  try {
    if (!await r.hasModel(language)) return null;
    final read = await r.recognize([for (final s in ink) samplesOf(s)], language: language);
    final best = read.firstOrNull?.trim();
    return best == null || best.isEmpty ? null : best;
  } on RecognitionFailed {
    return null;
  }
}

/// Ink fitted into a label's height.
class _InkLabel extends StatelessWidget {
  const _InkLabel(this.ink, {this.height = 22, this.faded = false});

  final List<StrokeItem> ink;
  final double height;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    Rect? r;
    for (final s in ink) {
      r = r == null ? s.bounds : r.expandToInclude(s.bounds);
    }
    if (r == null) return SizedBox(height: height);
    final k = math.min(1.0, height / math.max(1, r.height));
    final shifted = [
      for (final s in ink) s.copyWith(pagePoints: [for (final p in s.pageInk) InkPoint(p.x - r.left, p.y - r.top, p.pressure, p.t)]),
    ];
    return SizedBox(
      height: height,
      width: r.width * k,
      child: InkPreview(strokes: shifted, scale: k, faded: faded),
    );
  }
}

// Today.

class _TodayView extends ConsumerWidget {
  const _TodayView({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 14,
    children: [
      SizedBox(
        width: 290,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 14,
          children: [
            _TopThree(day: day),
            Expanded(child: _TodoCard(day: day)),
          ],
        ),
      ),
      Expanded(child: _Schedule(day: day)),
      SizedBox(
        width: 280,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 14,
          children: [
            Expanded(child: _NotesToday(day: day)),
            _Tomorrow(day: addDays(day, 1)),
          ],
        ),
      ),
    ],
  );
}

/// TOP 3 TODAY: three lines to write on, each ticked off by its number.
class _TopThree extends ConsumerWidget {
  const _TopThree({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final plan = ref.watch(plannerProvider).day(day);
    final notifier = ref.read(plannerProvider.notifier);
    final isToday = day == _today(ref);
    return CalendarCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          CardLabel(isToday ? 'TOP 3 TODAY' : 'TOP 3'),
          for (final (i, line) in plan.top.indexed)
            Container(
              height: 44,
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.paperLine)),
              ),
              child: Row(
                spacing: 10,
                children: [
                  Semantics(
                    button: true,
                    toggled: line.done,
                    label: 'Priority ${i + 1}${line.done ? ', done' : ''}',
                    excludeSemantics: true,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => notifier.setTop(day, i, line.copyWith(done: !line.done)),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: line.done ? c.green : c.side, shape: BoxShape.circle),
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: line.done ? c.onAccent : c.text),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        InkPad(
                          label: 'Write priority ${i + 1}',
                          strokes: line.ink,
                          faded: line.done,
                          onChanged: (ink) => notifier.setTop(day, i, line.copyWith(ink: ink)),
                        ),
                        if (line.done && line.ink.isNotEmpty) IgnorePointer(child: CustomPaint(painter: _StrikeInk(line.ink, c.textMuted))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A line through the middle of what's written (done).
class _StrikeInk extends CustomPainter {
  _StrikeInk(this.ink, this.color);

  final List<StrokeItem> ink;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    Rect? r;
    for (final s in ink) {
      r = r == null ? s.bounds : r.expandToInclude(s.bounds);
    }
    if (r == null) return;
    canvas.drawLine(
      Offset(r.left - 2, r.center.dy),
      Offset(r.right + 2, r.center.dy),
      Paint()
        ..color = color
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_StrikeInk old) => old.ink != ink || old.color != color;
}

/// TO-DO: the day's to-dos, and "write a task…".
class _TodoCard extends ConsumerWidget {
  const _TodoCard({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todos = _todos(ref, day);
    return CalendarCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(padding: EdgeInsets.only(bottom: 4), child: CardLabel('TO-DO')),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final t in todos) TodoRow(todo: t),
                const SizedBox(height: 6),
                _WriteTask(day: day),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A to-do: its box, what it says and where it's from, and a handle to
/// drag it onto the schedule.
class TodoRow extends ConsumerWidget {
  const TodoRow({super.key, required this.todo, this.compact = false});

  final Todo todo;

  /// The 3-day view's rows: no second line, no handle.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = todo.task;
    final label = todoLabel(todo);
    final done = todo.done;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 1,
      children: [
        if (label.isEmpty && t != null && t.ink.isNotEmpty)
          _InkLabel(t.ink, faded: done)
        else
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: done ? c.textMuted : c.text,
              decoration: done ? TextDecoration.lineThrough : null,
              decorationColor: c.textMuted,
            ),
          ),
        if (!compact) Text(todoFrom(todo), style: TextStyle(fontSize: 11, color: c.textMuted)),
      ],
    );
    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: compact ? 40 : 44),
      child: Row(
        spacing: 10,
        children: [
          Semantics(
            container: true,
            checked: done,
            label: label.isEmpty ? 'Handwritten to-do' : label,
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _tick(ref, todo, !done),
              child: SizedBox(
                width: 32,
                height: 44,
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: done,
                      onChanged: (v) => _tick(ref, todo, v ?? false),
                      activeColor: c.accent,
                      side: BorderSide(color: c.lineStrong, width: 1.5),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(behavior: HitTestBehavior.opaque, onLongPress: t == null ? null : () => _taskMenu(context, ref, t), child: text),
          ),
          if (!compact)
            Draggable<Todo>(
              data: todo,
              feedback: Material(
                color: Colors.transparent,
                child: _DragChip(label: label.isEmpty ? 'To-do' : label),
              ),
              childWhenDragging: Opacity(opacity: 0.3, child: _Handle(color: c.lineDashed)),
              child: Semantics(
                container: true,
                label: 'Drag ${label.isEmpty ? 'this to-do' : label} onto the schedule',
                child: _Handle(color: c.lineDashed),
              ),
            ),
        ],
      ),
    );
    return row;
  }
}

class _Handle extends StatelessWidget {
  const _Handle({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 32,
    height: 44,
    child: CustomPaint(painter: _Grip(color)),
  );
}

/// Six dots, two by three (Planner.dc.html's ⋮⋮).
class _Grip extends CustomPainter {
  _Grip(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final c = size.center(Offset.zero);
    for (final dx in const [-3.0, 3.0]) {
      for (final dy in const [-6.0, 0.0, 6.0]) {
        canvas.drawCircle(c + Offset(dx, dy), 1.6, p);
      }
    }
  }

  @override
  bool shouldRepaint(_Grip old) => old.color != color;
}

/// What follows the finger while a to-do is dragged.
class _DragChip extends StatelessWidget {
  const _DragChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.plum, width: 1.5),
        boxShadow: c.dialogShadow,
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.plumDeep),
      ),
    );
  }
}

/// A to-do's menu (a long press): change, take off the schedule, delete.
Future<void> _taskMenu(BuildContext context, WidgetRef ref, PlanTask t) async {
  final notifier = ref.read(plannerProvider.notifier);
  final what = await showEndlessDialog<String>(
    context,
    builder: (context) => DialogFrame(
      title: _taskLabel(t),
      width: 420,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          if (t.ink.isEmpty) SecondaryButton(label: 'Change', expand: true, onPressed: () => Navigator.of(context).pop('rename')),
          if (t.scheduled) SecondaryButton(label: 'Take off the schedule', expand: true, onPressed: () => Navigator.of(context).pop('unschedule')),
          if (t.day != null && !t.scheduled) SecondaryButton(label: 'No day', expand: true, onPressed: () => Navigator.of(context).pop('noday')),
          SecondaryButton(label: 'Delete', expand: true, onPressed: () => Navigator.of(context).pop('delete')),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  switch (what) {
    case 'rename':
      final text = await showNamePrompt(context, title: 'Change to-do', initial: t.text, label: 'To-do');
      if (text != null) notifier.put(t.copyWith(text: text.trim()));
    case 'unschedule':
      notifier.unschedule(t);
    case 'noday':
      notifier.moveTo(t, null);
    case 'delete':
      notifier.remove(t.id);
      if (context.mounted) showNote(context, 'Deleted “${_taskLabel(t)}”', onUndo: () => notifier.put(t));
  }
}

/// "write a task…": write it with the pen (read once the pen rests), or
/// tap to type it.
class _WriteTask extends ConsumerStatefulWidget {
  const _WriteTask({required this.day});

  final DateTime day;

  @override
  ConsumerState<_WriteTask> createState() => _WriteTaskState();
}

class _WriteTaskState extends ConsumerState<_WriteTask> {
  List<StrokeItem> _ink = const [];
  bool _typing = false;
  bool _reading = false;
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  DateTime? get _taskDay => widget.day == _today(ref) ? null : widget.day;

  Future<void> _read() async {
    final ink = _ink;
    if (ink.isEmpty || _reading) return;
    setState(() => _reading = true);
    final text = await readHandwriting(ref, ink);
    if (!mounted) return;
    // Written while it was read: wait for the pen to rest again.
    if (!identical(ink, _ink)) {
      setState(() => _reading = false);
      return;
    }
    ref.read(plannerProvider.notifier).add(text: text ?? '', ink: text == null ? ink : const [], day: _taskDay);
    setState(() {
      _ink = const [];
      _reading = false;
    });
  }

  void _addTyped() {
    final v = _text.text.trim();
    if (v.isNotEmpty) ref.read(plannerProvider.notifier).add(text: v, day: _taskDay);
    _text.clear();
    setState(() => _typing = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hint = TextStyle(fontFamily: FontFamilies.handwritingSample, fontSize: 22, color: c.textMuted);
    return DashedBorder(
      color: c.lineStrong,
      radius: 10,
      child: SizedBox(
        height: 48,
        child: _typing
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Center(
                  child: TextField(
                    controller: _text,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(fontSize: 15, color: c.text),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isCollapsed: true,
                      hintText: 'Type a to-do',
                      hintStyle: TextStyle(fontSize: 15, color: c.textMuted),
                    ),
                    onSubmitted: (_) => _addTyped(),
                    onTapOutside: (_) => _addTyped(),
                  ),
                ),
              )
            : InkPad(
                label: 'Write a task',
                strokes: _ink,
                onChanged: (ink) => setState(() => _ink = ink),
                onPause: _read,
                onTap: () => setState(() => _typing = true),
                child: _ink.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('write a task…', style: hint),
                        ),
                      )
                    : const SizedBox.expand(),
              ),
      ),
    );
  }
}

/// SCHEDULE: the day's hours with its events and the time blocked for
/// to-dos. A to-do dropped here is blocked from where it's let go.
class _Schedule extends ConsumerStatefulWidget {
  const _Schedule({required this.day});

  final DateTime day;

  @override
  ConsumerState<_Schedule> createState() => _ScheduleState();
}

class _ScheduleState extends ConsumerState<_Schedule> {
  static const hour = 58.0;
  static const head = 44.0;
  final _scroll = ScrollController(initialScrollOffset: 8 * hour);
  final _area = GlobalKey();

  /// A block being stretched: its id and new length.
  (String, int)? _stretch;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Minutes after midnight at [global], to the quarter hour.
  int _minutesAt(Offset global) {
    final box = _area.currentContext!.findRenderObject()! as RenderBox;
    final y = box.globalToLocal(global).dy;
    return ((y / hour * 60 / 15).round() * 15).clamp(0, 24 * 60 - 15);
  }

  void _drop(Todo t, Offset global) {
    final task = _real(ref, t);
    final start = _minutesAt(global);
    final minutes = task.scheduled ? task.minutes : (task.deckId != null ? 30 : 60);
    ref.read(plannerProvider.notifier).schedule(task, widget.day, start, minutes: math.min(minutes, 24 * 60 - start));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final data = ref.watch(calendarProvider);
    final events = [
      for (final o in _events(ref, widget.day))
        if (!o.allDay && !o.long) o,
    ];
    final allDay = [
      for (final o in _events(ref, widget.day))
        if (o.allDay || o.long) o,
    ];
    final blocks = ref.watch(plannerProvider).blocksOn(widget.day);
    final now = ref.read(clockProvider)();
    final isToday = widget.day == dayOf(now);
    // Blocked to-dos are laid out with the events, as stand-in occurrences.
    final stand = {
      for (final t in blocks)
        t.id: Occurrence(
          CalEvent(id: t.id, calendarId: '', title: _taskLabel(t), start: t.block!.$1, end: t.block!.$2),
          t.block!.$1,
          t.block!.$1.add(Duration(minutes: _stretch?.$1 == t.id ? _stretch!.$2 : t.minutes)),
        ),
    };
    final placed = layoutDay([...events, ...stand.values]);
    double y(DateTime t) => t.difference(widget.day).inMinutes.clamp(0, 24 * 60) / 60 * hour;

    return CalendarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: head,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.lineSoft)),
            ),
            child: Row(
              children: [
                const Expanded(child: CardLabel('SCHEDULE')),
                if (allDay.isNotEmpty)
                  Flexible(
                    child: Text(
                      allDay.map((o) => o.event.title).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.plumDeep),
                    ),
                  )
                else
                  Text('Drag a to-do here to block time', style: TextStyle(fontSize: 12, color: c.textMuted)),
              ],
            ),
          ),
          Expanded(
            child: DragTarget<Todo>(
              onAcceptWithDetails: (d) => _drop(d.data, d.offset + const Offset(0, 12)),
              builder: (context, wanted, _) => Container(
                color: wanted.isEmpty ? null : c.accentWash,
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: SizedBox(
                    key: _area,
                    height: 24 * hour,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (var h = 0; h < 24; h++)
                          Positioned(
                            left: 0,
                            right: 0,
                            top: h * hour,
                            height: hour,
                            child: Container(
                              decoration: h == 0
                                  ? null
                                  : BoxDecoration(
                                      border: Border(top: BorderSide(color: c.lineSoft.withValues(alpha: 0.7))),
                                    ),
                              padding: const EdgeInsets.only(left: 10, top: 3),
                              alignment: Alignment.topLeft,
                              child: h == 0 ? null : Text(hourLabel(h), style: TextStyle(fontSize: 11, color: c.textMuted)),
                            ),
                          ),
                        LayoutBuilder(
                          builder: (context, box) {
                            final width = box.maxWidth - 62 - 12;
                            return Stack(
                              children: [
                                for (final p in placed)
                                  Positioned(
                                    left: 62 + p.lane * width / p.lanes,
                                    width: width / p.lanes - (p.lanes > 1 ? 4 : 0),
                                    top: y(p.o.start) + 2,
                                    height: math.max(30, y(p.o.end) - y(p.o.start) - 4),
                                    child: stand.containsKey(p.o.event.id)
                                        ? _PlannedBlock(
                                            task: blocks.firstWhere((t) => t.id == p.o.event.id),
                                            o: p.o,
                                            onStretch: (minutes) => setState(() => _stretch = minutes == null ? null : (p.o.event.id, minutes)),
                                          )
                                        : _EventBlock(o: p.o, data: data),
                                  ),
                              ],
                            );
                          },
                        ),
                        if (isToday) ...[
                          Positioned(
                            left: 56,
                            right: 0,
                            top: y(now) - 1,
                            height: 2,
                            child: IgnorePointer(
                              child: Semantics(
                                label: 'Now, ${hmAmPm(now)}',
                                child: ColoredBox(color: c.danger),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 52,
                            top: y(now) - 5,
                            width: 10,
                            height: 10,
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(color: c.danger, shape: BoxShape.circle),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// An event from the calendar on the schedule, with where it's from.
class _EventBlock extends ConsumerWidget {
  const _EventBlock({required this.o, required this.data});

  final Occurrence o;
  final CalendarData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final k = eventColors(o, data, c);
    final cal = data.calendar(o.event.calendarId);
    final tag = cal == null ? '' : (cal.synced ? cal.source : cal.name);
    return Semantics(
      button: true,
      label: '${o.event.title}, ${spanLabel(o, dash: ' to ')}, $tag',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => context.go(Routes.calendar),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: k.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.transparent, width: 1.5),
          ),
          child: _BlockText(
            title: o.event.title,
            time: spanLabel(o, dash: ' – '),
            tag: tag,
            color: k.fg,
          ),
        ),
      ),
    );
  }
}

class _BlockText extends StatelessWidget {
  const _BlockText({required this.title, required this.time, required this.tag, required this.color, this.done = false});

  final String title;
  final String time;
  final String tag;
  final Color color;

  /// Ticked off: struck through.
  final bool done;

  // A short block shows what fits.
  @override
  Widget build(BuildContext context) => ClipRect(
    child: OverflowBox(
      alignment: Alignment.topLeft,
      maxHeight: double.infinity,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: 1,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: color,
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: color,
                  ),
                ),
                Text(time, maxLines: 1, style: TextStyle(fontSize: 11, height: 1.2, color: color)),
              ],
            ),
          ),
          Text(
            tag,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    ),
  );
}

/// Time blocked for a to-do: dashed, "Planned". Drag it to move it, or its
/// bottom edge to change how long; a tap ticks it off or takes it off.
class _PlannedBlock extends ConsumerStatefulWidget {
  const _PlannedBlock({required this.task, required this.o, required this.onStretch});

  final PlanTask task;
  final Occurrence o;

  /// The new length while the bottom edge is dragged; null when let go.
  final ValueChanged<int?> onStretch;

  @override
  ConsumerState<_PlannedBlock> createState() => _PlannedBlockState();
}

class _PlannedBlockState extends ConsumerState<_PlannedBlock> {
  double _drag = 0;

  int get _minutes => math.max(15, ((widget.task.minutes + _drag / _ScheduleState.hour * 60) / 15).round() * 15);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = widget.task;
    final k = _plannedColors(t, c);
    final label = _taskLabel(t);
    final content = Container(
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(8)),
      child: DashedBorder(
        color: k.fg,
        radius: 8,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
          child: _BlockText(title: label, done: t.done, time: spanLabel(widget.o, dash: ' – '), tag: 'Planned', color: k.fg),
        ),
      ),
    );
    return Semantics(
      label: 'Planned: $label, ${spanLabel(widget.o, dash: ' to ')}',
      child: Stack(
        fit: StackFit.expand,
        children: [
          Draggable<Todo>(
            data: Todo(t),
            feedback: Material(
              color: Colors.transparent,
              child: _DragChip(label: label),
            ),
            childWhenDragging: Opacity(opacity: 0.35, child: content),
            child: GestureDetector(onTap: () => _taskMenu(context, ref, t), child: content),
          ),
          // The bottom edge: how long.
          Positioned(
            left: 0,
            right: 0,
            bottom: -6,
            height: 16,
            child: Semantics(
              label: 'Change how long',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (_) => _drag = 0,
                onVerticalDragUpdate: (d) {
                  _drag += d.delta.dy;
                  widget.onStretch(_minutes);
                },
                onVerticalDragEnd: (_) {
                  final m = math.min(_minutes, 24 * 60 - t.start!);
                  widget.onStretch(null);
                  ref.read(plannerProvider.notifier).put(t.copyWith(minutes: m));
                },
                child: Center(
                  child: Container(
                    width: 24,
                    height: 3,
                    decoration: BoxDecoration(color: k.fg.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// NOTES FOR TODAY, on ruled lines.
class _NotesToday extends ConsumerWidget {
  const _NotesToday({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final notes = ref.watch(plannerProvider).day(day).notes;
    return CalendarCard(
      child: CustomPaint(
        painter: _Rules(c.paperLine, first: 73, every: 32),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              CardLabel(day == _today(ref) ? 'NOTES FOR TODAY' : 'NOTES'),
              Expanded(
                child: InkPad(
                  label: 'Notes for ${dayTitle(day)}',
                  strokes: notes,
                  onChanged: (ink) => ref.read(plannerProvider.notifier).setNotes(day, ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ruled lines from [first], every [every] px.
class _Rules extends CustomPainter {
  _Rules(this.color, {required this.first, required this.every});

  final Color color;
  final double first;
  final double every;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var y = first; y < size.height; y += every) {
      canvas.drawLine(Offset(0, y - 0.5), Offset(size.width, y - 0.5), p);
    }
  }

  @override
  bool shouldRepaint(_Rules old) => old.color != color || old.first != first || old.every != every;
}

/// TOMORROW · SAT 26: its events and what's planned.
class _Tomorrow extends ConsumerWidget {
  const _Tomorrow({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final data = ref.watch(calendarProvider);
    final planner = ref.watch(plannerProvider);
    final lines = <(Color, String)>[
      for (final o in _events(ref, day)) (eventColors(o, data, c).dot, o.allDay ? o.event.title : '${hm(o.start)} ${o.event.title}'),
      for (final t in planner.tasks)
        if (t.day == day && !t.done) (_plannedColors(t, c).dot, t.scheduled ? '${_taskLabel(t)} · ${t.minutes} min' : _taskLabel(t)),
    ];
    return CalendarCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          CardLabel('TOMORROW · ${shortWeekday(day).toUpperCase()} ${day.day}'),
          if (lines.isEmpty) Text('Nothing planned yet', style: TextStyle(fontSize: 13, color: c.textMuted)),
          for (final (color, text) in lines.take(4))
            Row(
              spacing: 8,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                ),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: c.text),
                  ),
                ),
              ],
            ),
          if (lines.length > 4) Text('and ${lines.length - 4} more', style: TextStyle(fontSize: 12, color: c.textMuted)),
        ],
      ),
    );
  }
}

// 3 days.

/// A schedule line: an event or planned to-do, with its time.
typedef _Line = ({String time, String label, Color bg, Color fg, bool planned, DateTime sort});

List<_Line> _linesFor(WidgetRef ref, DateTime day, EndlessColors c) {
  final data = ref.watch(calendarProvider);
  final out = <_Line>[
    for (final o in _events(ref, day))
      (
        time: o.allDay ? 'all day' : hm(o.start),
        label: o.event.title,
        bg: eventColors(o, data, c).bg,
        fg: eventColors(o, data, c).fg,
        planned: false,
        sort: o.allDay ? day : o.start,
      ),
    for (final t in ref.watch(plannerProvider).blocksOn(day))
      (
        time: hm(t.block!.$1),
        label: t.deckId != null ? 'Flashcards · ${t.minutes} min' : _taskLabel(t),
        bg: c.surface,
        fg: _plannedColors(t, c).fg,
        planned: true,
        sort: t.block!.$1,
      ),
  ];
  out.sort((a, b) => a.sort.compareTo(b.sort));
  return out;
}

class _ThreeDays extends ConsumerWidget {
  const _ThreeDays({required this.first});

  final DateTime first;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 14,
    children: [for (var i = 0; i < 3; i++) Expanded(child: _DayColumn(day: addDays(first, i)))],
  );
}

class _DayColumn extends ConsumerWidget {
  const _DayColumn({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final today = day == _today(ref);
    final lines = _linesFor(ref, day, c);
    final todos = [
      for (final t in _todos(ref, day))
        if (!(t.task?.scheduled ?? false)) t,
    ];
    final notes = ref.watch(plannerProvider).day(day).notes;
    return DragTarget<Todo>(
      onAcceptWithDetails: (d) => ref.read(plannerProvider.notifier).moveTo(_real(ref, d.data), day),
      builder: (context, wanted, _) => CalendarCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        color: wanted.isEmpty ? null : c.accentWash,
        border: today ? Border.all(color: c.accent, width: 2) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    dayShort(day),
                    style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 24, color: c.text),
                  ),
                ),
                if (today)
                  Text(
                    'TODAY',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.accentDeep),
                  ),
              ],
            ),
            const CardLabel('SCHEDULE', size: 11),
            if (lines.isEmpty) Text('Nothing yet', style: TextStyle(fontSize: 13, color: c.textMuted)),
            for (final l in lines.take(5))
              Row(
                spacing: 8,
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(l.time, style: TextStyle(fontSize: 12, color: c.textMuted)),
                  ),
                  Expanded(
                    child: _Chip(label: l.label, bg: l.bg, fg: l.fg, planned: l.planned),
                  ),
                ],
              ),
            const Padding(padding: EdgeInsets.only(top: 6), child: CardLabel('TO-DO', size: 11)),
            for (final t in todos.take(4)) TodoRow(todo: t, compact: true),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 90),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(10)),
                child: CustomPaint(
                  painter: _Rules(c.paperLine, first: 40, every: 32),
                  child: InkPad(
                    label: 'Notes for ${dayTitle(day)}',
                    strokes: notes,
                    onChanged: (ink) => ref.read(plannerProvider.notifier).setNotes(day, ink),
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

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.bg, required this.fg, required this.planned, this.small = false});

  final String label;
  final Color bg;
  final Color fg;
  final bool planned;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: small ? 11 : 13, fontWeight: FontWeight.w600, height: 1.25, color: fg),
    );
    final pad = small ? const EdgeInsets.symmetric(horizontal: 7, vertical: 6) : const EdgeInsets.symmetric(horizontal: 10, vertical: 7);
    final r = small ? 7.0 : 8.0;
    if (planned) {
      // The fill, then the dashes over it.
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(r)),
        child: DashedBorder(
          color: fg,
          radius: r,
          child: Padding(padding: pad, child: text),
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: pad,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(r)),
      child: text,
    );
  }
}

// Week.

class _WeekView extends ConsumerWidget {
  const _WeekView({required this.first});

  final DateTime first;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final planner = ref.watch(plannerProvider);
    final today = _today(ref);
    final loose = planner.unscheduled(first, 7);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 14,
      children: [
        CalendarCard(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            spacing: 16,
            children: [
              const CardLabel('WEEK GOALS'),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: InkPad(
                    label: 'Week goals',
                    strokes: planner.goalsFor(first),
                    onChanged: (ink) => ref.read(plannerProvider.notifier).setGoals(first, ink),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final day = addDays(first, i);
                      final isToday = day == today;
                      final lines = _linesFor(ref, day, c);
                      final onDay = [
                        for (final t in planner.tasks)
                          if (t.day == day && !t.scheduled) t,
                      ];
                      return DragTarget<Todo>(
                        onAcceptWithDetails: (d) => ref.read(plannerProvider.notifier).moveTo(_real(ref, d.data), day),
                        builder: (context, wanted, _) => Container(
                          padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                          decoration: BoxDecoration(
                            color: wanted.isNotEmpty ? c.accentWash : (isToday ? c.surface : c.surfaceSunk),
                            border: isToday ? Border.all(color: c.accent, width: 2) : Border.all(color: c.line),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              spacing: 6,
                              children: [
                                Text(
                                  dayShort(day),
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isToday ? c.accentDeep : c.text),
                                ),
                                for (final l in lines) _Chip(label: l.label, bg: l.bg, fg: l.fg, planned: l.planned, small: true),
                                for (final t in onDay)
                                  _Draggable(
                                    todo: Todo(t),
                                    child: _Chip(label: _taskLabel(t), bg: c.surface, fg: _plannedColors(t, c).fg, planned: true, small: true),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        DragTarget<Todo>(
          onAcceptWithDetails: (d) => ref.read(plannerProvider.notifier).moveTo(_real(ref, d.data), null),
          builder: (context, wanted, _) => DashedBorder(
            color: c.lineDashed,
            radius: 14,
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: wanted.isEmpty ? c.surface : c.accentWash, borderRadius: BorderRadius.circular(14)),
              child: Row(
                spacing: 8,
                children: [
                  const Padding(padding: EdgeInsets.only(right: 4), child: CardLabel('NOT SCHEDULED')),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        spacing: 8,
                        children: [
                          if (loose.isEmpty) Text('Everything has a day', style: TextStyle(fontSize: 13, color: c.textMuted)),
                          for (final t in loose)
                            _Draggable(
                              todo: Todo(t),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(8)),
                                child: t.text.isEmpty && t.ink.isNotEmpty
                                    ? _InkLabel(t.ink, height: 18)
                                    : Text(
                                        _taskLabel(t),
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text),
                                      ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Text('Drag onto a day', style: TextStyle(fontSize: 12, color: c.textMuted)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A to-do that can be picked up and put on a day.
class _Draggable extends StatelessWidget {
  const _Draggable({required this.todo, required this.child});

  final Todo todo;
  final Widget child;

  @override
  Widget build(BuildContext context) => Draggable<Todo>(
    data: todo,
    feedback: Material(
      color: Colors.transparent,
      child: _DragChip(label: todoLabel(todo).isEmpty ? 'To-do' : todoLabel(todo)),
    ),
    childWhenDragging: Opacity(opacity: 0.35, child: child),
    child: Semantics(container: true, label: 'Drag ${todoLabel(todo)} onto a day', excludeSemantics: true, child: child),
  );
}
