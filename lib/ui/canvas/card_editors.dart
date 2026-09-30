import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../board/ids.dart';
import '../../board/model.dart';
import '../../canvas/cards.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../common.dart';
import '../dialogs.dart';
import '../icons.dart';

// Editors for the cards built on the board: Kanban, timeline, diagram,
// table and website. Each opens from Select → Edit, works on a copy, and
// hands back the changed card (one undo step) or null for Cancel.

const _maxColumns = 5;
const _maxTableColumns = 8;
const _maxTableRows = 30;
const _maxEvents = 8;
const _maxSteps = 12;

/// Opens the editor for [card]. Returns the edited card, grown if it needs
/// more room for what it holds now, or null if nothing should change.
Future<CardItem?> showCardEditor(BuildContext context, CardItem card) async {
  final edited = await showEndlessDialog<CardItem>(
    context,
    builder: (context) => switch (card.data) {
      KanbanData _ => _KanbanEditor(card),
      TimelineData _ => _TimelineEditor(card),
      DiagramData _ => _DiagramEditor(card),
      TableData _ => _TableEditor(card),
      EmbedData _ => _WebsiteEditor(card: card),
    },
  );
  return edited == null ? null : fitCard(edited);
}

/// Asks for a web address (and a name) for a new website card.
Future<({String url, String title})?> showWebsitePrompt(BuildContext context) async {
  final card = await showEndlessDialog<CardItem>(context, builder: (context) => const _WebsiteEditor());
  final data = card?.data;
  return data is EmbedData ? (url: data.url, title: card!.title) : null;
}

/// The dialog around an editor: title, close, a body that scrolls when the
/// keyboard takes the room, and Cancel / Save.
class _EditorFrame extends StatelessWidget {
  const _EditorFrame({
    required this.title,
    required this.body,
    required this.onSave,
    this.width = 620,
    this.leading = const [],
    this.saveLabel = 'Save',
  });

  final String title;
  final Widget body;

  /// Null while what's typed can't be saved.
  final VoidCallback? onSave;
  final double width;

  /// Buttons at the left of the footer ("Add column").
  final List<Widget> leading;
  final String saveLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = MediaQuery.sizeOf(context);
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: title,
      explicitChildNodes: true,
      child: Container(
        width: math.min(width, size.width - 48),
        padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(22), boxShadow: c.modalShadow),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
          Row(children: [
            Expanded(
              child: Text(title, style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 30, height: 1.2, color: c.text)),
            ),
            DialogCloseButton(onPressed: () => Navigator.of(context).pop()),
          ]),
          Flexible(child: SingleChildScrollView(child: body)),
          Row(spacing: 10, children: [
            ...leading,
            const Spacer(),
            SecondaryButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
            PrimaryButton(label: saveLabel, onPressed: onSave),
          ]),
        ]),
      ),
    );
  }
}

/// A compact text field for one value in an editor.
class _Field extends StatelessWidget {
  const _Field({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.bold = false,
    this.plain = false,
    this.lines = 1,
    this.fill,
  });

  final TextEditingController controller;

  /// What the field is for (read out; not shown).
  final String label;
  final String? hint;
  final bool bold;

  /// No outline (inside a Kanban card, which has its own).
  final bool plain;
  final int lines;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.key),
          borderSide: plain ? BorderSide.none : BorderSide(color: color, width: width),
        );
    return Semantics(
      label: label,
      child: TextField(
        controller: controller,
        minLines: 1,
        maxLines: lines,
        textCapitalization: TextCapitalization.sentences,
        cursorColor: c.accent,
        style: TextStyle(fontSize: 15, height: 1.25, fontWeight: bold ? FontWeight.w600 : FontWeight.w400, color: c.text),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: TextStyle(fontSize: 15, height: 1.25, fontWeight: FontWeight.w400, color: c.textFaint),
          filled: true,
          fillColor: fill ?? c.surface,
          // 44 dp tall: 19 dp of text plus 12.5 above and below.
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12.5),
          enabledBorder: border(c.lineStrong, 1),
          focusedBorder: border(c.accent, 1.5),
        ),
      ),
    );
  }
}

/// The card's name, above what it holds.
class _NameField extends StatelessWidget {
  const _NameField(this.controller, this.hint);

  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        Text('Name', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: context.colors.text)),
        _Field(key: const ValueKey('card-name'), controller: controller, label: 'Name', hint: hint, bold: true),
      ]);
}

Widget _iconButton(String label, EIconData icon, VoidCallback? onPressed, {Key? key}) => ChromeButton(
      key: key,
      label: label,
      icon: icon,
      iconSize: 16,
      width: 40,
      height: 40,
      radius: Radii.key,
      enabled: onPressed != null,
      onPressed: onPressed,
    );

/// "Add card", "Add event"…: a quiet, outlined button at the end of a list.
class _AddButton extends StatelessWidget {
  const _AddButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: c.lineStrong),
          borderRadius: BorderRadius.circular(Radii.key),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.key),
          onTap: onPressed,
          child: SizedBox(
            height: 44,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 6, children: [
              EIcon(EIcons.plus, size: 16, color: enabled ? c.text : c.textFaint),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: enabled ? c.text : c.textFaint),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// Kanban.

class _CardEdit {
  _CardEdit(String text, [this.extra = const {}]) : text = TextEditingController(text: text);

  final TextEditingController text;
  final Json extra;
}

class _ColumnEdit {
  _ColumnEdit(String title, [List<_CardEdit>? cards, this.extra = const {}])
      : title = TextEditingController(text: title),
        cards = cards ?? [];

  final TextEditingController title;
  final List<_CardEdit> cards;
  final Json extra;

  void dispose() {
    title.dispose();
    for (final c in cards) {
      c.text.dispose();
    }
  }
}

class _KanbanEditor extends StatefulWidget {
  const _KanbanEditor(this.card);

  final CardItem card;

  @override
  State<_KanbanEditor> createState() => _KanbanEditorState();
}

class _KanbanEditorState extends State<_KanbanEditor> {
  late final _name = TextEditingController(text: widget.card.title);
  late final List<_ColumnEdit> _columns = [
    for (final col in (widget.card.data as KanbanData).columns)
      _ColumnEdit(col.title, [for (final card in col.cards) _CardEdit(card.text, card.extra)], col.extra),
  ];

  @override
  void dispose() {
    _name.dispose();
    for (final c in _columns) {
      c.dispose();
    }
    super.dispose();
  }

  void _move(int column, int index, int by) => setState(() {
        final card = _columns[column].cards.removeAt(index);
        _columns[column + by].cards.add(card);
      });

  void _save() {
    final data = KanbanData([
      for (final col in _columns)
        KanbanColumn(
          col.title.text.trim(),
          [
            for (final card in col.cards)
              if (card.text.text.trim().isNotEmpty) KanbanCard(card.text.text.trim(), extra: card.extra),
          ],
          col.extra,
        ),
    ]);
    Navigator.of(context).pop(widget.card.copyWith(title: _name.text.trim(), data: data));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _EditorFrame(
      title: 'Kanban board',
      width: 920,
      onSave: _save,
      leading: [
        SecondaryButton(
          label: 'Add column',
          icon: EIcons.plus,
          onPressed: _columns.length >= _maxColumns
              ? null
              : () => setState(() => _columns.add(_ColumnEdit(''))),
        ),
      ],
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
        _NameField(_name, 'Kanban board'),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
            for (final (i, col) in _columns.indexed)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: c.menuTile, borderRadius: BorderRadius.circular(Radii.button)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
                    Row(spacing: 4, children: [
                      Expanded(
                        child: _Field(
                          key: ValueKey('kanban-column-$i'),
                          controller: col.title,
                          label: 'Column ${i + 1} name',
                          hint: 'Column',
                          bold: true,
                        ),
                      ),
                      if (_columns.length > 1)
                        _iconButton(
                          'Remove column ${i + 1}',
                          EIcons.trash,
                          () => setState(() => _columns.removeAt(i).dispose()),
                        ),
                    ]),
                    for (final (j, card) in col.cards.indexed)
                      Container(
                        key: ObjectKey(card),
                        decoration: BoxDecoration(
                          color: c.surface,
                          border: Border.all(color: c.line),
                          borderRadius: BorderRadius.circular(Radii.key),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          _Field(
                            key: ValueKey('kanban-card-$i-$j'),
                            controller: card.text,
                            label: 'Card ${j + 1} in column ${i + 1}',
                            hint: 'What needs doing?',
                            plain: true,
                            lines: 4,
                          ),
                          Row(children: [
                            _iconButton(
                              'Move card left',
                              EIcons.chevronLeft,
                              i == 0 ? null : () => _move(i, j, -1),
                              key: ValueKey('kanban-left-$i-$j'),
                            ),
                            _iconButton(
                              'Move card right',
                              EIcons.chevronRight,
                              i == _columns.length - 1 ? null : () => _move(i, j, 1),
                              key: ValueKey('kanban-right-$i-$j'),
                            ),
                            const Spacer(),
                            _iconButton(
                              'Delete card',
                              EIcons.close,
                              () => setState(() => col.cards.removeAt(j).text.dispose()),
                              key: ValueKey('kanban-delete-$i-$j'),
                            ),
                          ]),
                        ]),
                      ),
                    _AddButton(
                      key: ValueKey('kanban-add-$i'),
                      label: 'Add card',
                      onPressed: () => setState(() => col.cards.add(_CardEdit(''))),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

// Timeline.

class _EventEdit {
  _EventEdit(TimelineEvent e)
      : date = TextEditingController(text: e.date),
        label = TextEditingController(text: e.label),
        state = e.state,
        extra = e.extra;

  final TextEditingController date;
  final TextEditingController label;
  EventState state;
  final Json extra;

  void dispose() {
    date.dispose();
    label.dispose();
  }
}

const _stateNames = {EventState.done: 'Done', EventState.now: 'Up next', EventState.later: 'To come'};

class _TimelineEditor extends StatefulWidget {
  const _TimelineEditor(this.card);

  final CardItem card;

  @override
  State<_TimelineEditor> createState() => _TimelineEditorState();
}

class _TimelineEditorState extends State<_TimelineEditor> {
  late final _name = TextEditingController(text: widget.card.title);
  late final List<_EventEdit> _events = [for (final e in (widget.card.data as TimelineData).events) _EventEdit(e)];

  @override
  void dispose() {
    _name.dispose();
    for (final e in _events) {
      e.dispose();
    }
    super.dispose();
  }

  void _swap(int i, int j) => setState(() {
        final e = _events[i];
        _events[i] = _events[j];
        _events[j] = e;
      });

  void _save() {
    final data = TimelineData([
      for (final e in _events)
        if (e.date.text.trim().isNotEmpty || e.label.text.trim().isNotEmpty)
          TimelineEvent(date: e.date.text.trim(), label: e.label.text.trim(), state: e.state, extra: e.extra),
    ]);
    Navigator.of(context).pop(widget.card.copyWith(title: _name.text.trim(), data: data));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _EditorFrame(
      title: 'Timeline',
      width: 680,
      onSave: _save,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        _NameField(_name, 'Timeline'),
        const SizedBox(height: 2),
        for (final (i, e) in _events.indexed)
          Row(key: ObjectKey(e), spacing: 6, children: [
            // The dot as it shows on the card; tap to step through the three.
            ChromeButton(
              key: ValueKey('timeline-state-$i'),
              label: '${_stateNames[e.state]}. Tap to change',
              width: 44,
              radius: Radii.key,
              background: c.menuTile,
              onPressed: () => setState(() => e.state = EventState.values[(e.state.index + 1) % 3]),
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: switch (e.state) {
                    EventState.done => c.green,
                    EventState.now => c.accent,
                    EventState.later => c.surface,
                  },
                  border: e.state == EventState.later ? Border.all(color: c.accent, width: 3) : null,
                ),
              ),
            ),
            SizedBox(
              width: 120,
              child: _Field(
                key: ValueKey('timeline-date-$i'),
                controller: e.date,
                label: 'When, event ${i + 1}',
                hint: 'When',
                bold: true,
              ),
            ),
            Expanded(
              child: _Field(
                key: ValueKey('timeline-label-$i'),
                controller: e.label,
                label: 'What, event ${i + 1}',
                hint: 'What happens',
              ),
            ),
            _iconButton('Move earlier', EIcons.chevronUp, i == 0 ? null : () => _swap(i, i - 1)),
            _iconButton('Move later', EIcons.chevronDown, i == _events.length - 1 ? null : () => _swap(i, i + 1)),
            _iconButton(
              'Delete event',
              EIcons.close,
              () => setState(() => _events.removeAt(i).dispose()),
              key: ValueKey('timeline-delete-$i'),
            ),
          ]),
        _AddButton(
          label: 'Add event',
          onPressed: _events.length >= _maxEvents
              ? null
              : () => setState(() => _events.add(_EventEdit(const TimelineEvent(date: '', label: '')))),
        ),
        Text(
          'Tap a dot to mark it done, up next or still to come.',
          style: TextStyle(fontSize: 13, color: c.textMuted),
        ),
      ]),
    );
  }
}

// Diagram.

class _StepEdit {
  _StepEdit(DiagramNode n)
      : id = n.id,
        text = TextEditingController(text: n.text),
        shape = n.shape,
        color = n.color,
        extra = n.extra;

  final String id;
  final TextEditingController text;
  NodeShape shape;
  NodeColor color;
  final Json extra;
}

const _shapeNames = {NodeShape.box: 'Box', NodeShape.pill: 'Rounded', NodeShape.diamond: 'Decision'};
const _colorNames = {NodeColor.blue: 'Blue', NodeColor.clay: 'Terracotta', NodeColor.green: 'Green', NodeColor.plum: 'Plum'};

/// A step's shape in its colors, as small as a button.
class _ShapeSwatch extends CustomPainter {
  _ShapeSwatch(this.shape, this.fill, this.stroke);

  final NodeShape shape;
  final Color fill;
  final Color stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (Offset.zero & size).deflate(1);
    final path = Path();
    switch (shape) {
      case NodeShape.box:
        path.addRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)));
      case NodeShape.pill:
        path.addRRect(RRect.fromRectAndRadius(r, Radius.circular(r.height / 2)));
      case NodeShape.diamond:
        path.addPolygon([r.topCenter, r.centerRight, r.bottomCenter, r.centerLeft], true);
    }
    canvas
      ..drawPath(path, Paint()..color = fill)
      ..drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeJoin = StrokeJoin.round
          ..color = stroke,
      );
  }

  @override
  bool shouldRepaint(_ShapeSwatch old) => old.shape != shape || old.fill != fill || old.stroke != stroke;
}

class _DiagramEditor extends StatefulWidget {
  const _DiagramEditor(this.card);

  final CardItem card;

  @override
  State<_DiagramEditor> createState() => _DiagramEditorState();
}

class _DiagramEditorState extends State<_DiagramEditor> {
  late final _name = TextEditingController(text: widget.card.title);
  late final List<_StepEdit> _steps = [for (final n in (widget.card.data as DiagramData).nodes) _StepEdit(n)];

  DiagramData get _original => widget.card.data as DiagramData;

  @override
  void dispose() {
    _name.dispose();
    for (final s in _steps) {
      s.text.dispose();
    }
    super.dispose();
  }

  void _swap(int i, int j) => setState(() {
        final s = _steps[i];
        _steps[i] = _steps[j];
        _steps[j] = s;
      });

  /// Whether the arrows simply join each step to the next, the only kind of
  /// diagram made here. Arrows from elsewhere are kept as they are.
  bool get _wasFlow {
    final flow = DiagramData.flow(_original.nodes).edges;
    return flow.length == _original.edges.length && flow.every(_original.edges.contains);
  }

  void _save() {
    final nodes = [
      for (final s in _steps)
        if (s.text.text.trim().isNotEmpty)
          DiagramNode(id: s.id, text: s.text.text.trim(), shape: s.shape, color: s.color, extra: s.extra),
    ];
    final ids = {for (final n in nodes) n.id};
    final data = _wasFlow
        ? DiagramData.flow(nodes)
        : DiagramData(nodes, [
            for (final (from, to) in _original.edges)
              if (ids.contains(from) && ids.contains(to)) (from, to),
          ]);
    Navigator.of(context).pop(widget.card.copyWith(title: _name.text.trim(), data: data));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    (Color, Color) tones(NodeColor color) => switch (color) {
          NodeColor.blue => (c.accentTint, c.accent),
          NodeColor.clay => (c.clayTint, c.clay),
          NodeColor.green => (c.greenTint, c.green),
          NodeColor.plum => (c.plumTint, c.plum),
        };
    return _EditorFrame(
      title: 'Diagram',
      width: 620,
      onSave: _save,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        _NameField(_name, 'Diagram'),
        const SizedBox(height: 2),
        for (final (i, s) in _steps.indexed)
          Row(key: ObjectKey(s), spacing: 6, children: [
            ChromeButton(
              key: ValueKey('diagram-shape-$i'),
              label: 'Shape: ${_shapeNames[s.shape]}. Tap to change',
              width: 52,
              radius: Radii.key,
              background: c.menuTile,
              onPressed: () => setState(() => s.shape = NodeShape.values[(s.shape.index + 1) % 3]),
              child: CustomPaint(
                size: s.shape == NodeShape.diamond ? const Size(30, 24) : const Size(32, 18),
                painter: _ShapeSwatch(s.shape, tones(s.color).$1, tones(s.color).$2),
              ),
            ),
            ChromeButton(
              key: ValueKey('diagram-color-$i'),
              label: 'Color: ${_colorNames[s.color]}. Tap to change',
              width: 44,
              radius: Radii.key,
              onPressed: () => setState(() => s.color = NodeColor.values[(s.color.index + 1) % 4]),
              child: ColorDot(color: tones(s.color).$2, size: 20),
            ),
            Expanded(
              child: _Field(
                key: ValueKey('diagram-step-$i'),
                controller: s.text,
                label: 'Step ${i + 1}',
                hint: 'Step',
              ),
            ),
            _iconButton('Move earlier', EIcons.chevronUp, i == 0 ? null : () => _swap(i, i - 1)),
            _iconButton('Move later', EIcons.chevronDown, i == _steps.length - 1 ? null : () => _swap(i, i + 1)),
            _iconButton(
              'Delete step',
              EIcons.close,
              () => setState(() => _steps.removeAt(i).text.dispose()),
              key: ValueKey('diagram-delete-$i'),
            ),
          ]),
        _AddButton(
          label: 'Add step',
          onPressed: _steps.length >= _maxSteps
              ? null
              : () => setState(() => _steps.add(_StepEdit(DiagramNode(id: newId('n'), text: '')))),
        ),
        Text(
          'Each step points to the next. Tap a shape or a color to change it.',
          style: TextStyle(fontSize: 13, color: c.textMuted),
        ),
      ]),
    );
  }
}

// Table.

class _TableEditor extends StatefulWidget {
  const _TableEditor(this.card);

  final CardItem card;

  @override
  State<_TableEditor> createState() => _TableEditorState();
}

class _TableEditorState extends State<_TableEditor> {
  late final _name = TextEditingController(text: widget.card.title);
  late bool _header = (widget.card.data as TableData).header;
  late final List<List<TextEditingController>> _cells = () {
    final data = widget.card.data as TableData;
    final columns = math.max(data.columns, 1);
    return [
      for (final row in data.cells.isEmpty ? [<String>[]] : data.cells)
        [for (var i = 0; i < columns; i++) TextEditingController(text: i < row.length ? row[i] : '')],
    ];
  }();

  int get _columns => _cells.first.length;

  @override
  void dispose() {
    _name.dispose();
    for (final row in _cells) {
      for (final cell in row) {
        cell.dispose();
      }
    }
    super.dispose();
  }

  void _save() {
    final data = TableData(
      [
        for (final row in _cells) [for (final cell in row) cell.text.trim()],
      ],
      header: _header,
    );
    Navigator.of(context).pop(widget.card.copyWith(title: _name.text.trim(), data: data));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget step(String label, VoidCallback? onPressed) =>
        SecondaryButton(label: label, height: 44, onPressed: onPressed);
    return _EditorFrame(
      title: 'Table',
      width: math.max(620, 170.0 * _columns + 60),
      onSave: _save,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        _NameField(_name, 'Table'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          step('Add row', _cells.length >= _maxTableRows
              ? null
              : () => setState(() => _cells.add([for (var i = 0; i < _columns; i++) TextEditingController()]))),
          step('Add column', _columns >= _maxTableColumns
              ? null
              : () => setState(() {
                    for (final row in _cells) {
                      row.add(TextEditingController());
                    }
                  })),
          step('Remove row', _cells.length <= 1
              ? null
              : () => setState(() {
                    for (final cell in _cells.removeLast()) {
                      cell.dispose();
                    }
                  })),
          step('Remove column', _columns <= 1
              ? null
              : () => setState(() {
                    for (final row in _cells) {
                      row.removeLast().dispose();
                    }
                  })),
        ]),
        for (final (r, row) in _cells.indexed)
          Row(spacing: 6, children: [
            for (final (i, cell) in row.indexed)
              Expanded(
                child: _Field(
                  key: ValueKey('table-cell-$r-$i'),
                  controller: cell,
                  label: _header && r == 0 ? 'Column ${i + 1} name' : 'Row ${r + 1}, column ${i + 1}',
                  bold: _header && r == 0,
                  fill: _header && r == 0 ? c.menuTile : null,
                ),
              ),
          ]),
        Semantics(
          label: 'The first row is the column names',
          checked: _header,
          excludeSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.key),
            onTap: () => setState(() => _header = !_header),
            child: SizedBox(
              height: 44,
              child: Row(spacing: 6, children: [
                IgnorePointer(child: Checkbox(value: _header, onChanged: (_) {})),
                Text('The first row is the column names', style: TextStyle(fontSize: 15, color: c.text)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

// Website.

class _WebsiteEditor extends StatefulWidget {
  const _WebsiteEditor({this.card});

  /// The card being edited, or null for a new one.
  final CardItem? card;

  @override
  State<_WebsiteEditor> createState() => _WebsiteEditorState();
}

class _WebsiteEditorState extends State<_WebsiteEditor> {
  late final _address = TextEditingController(text: (widget.card?.data as EmbedData?)?.url ?? '');
  late final _name = TextEditingController(text: widget.card?.title ?? '');

  @override
  void dispose() {
    _address.dispose();
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final url = EmbedData.normalize(_address.text);
    if (url == null) return;
    final card = widget.card;
    final data = EmbedData(url);
    Navigator.of(context).pop(
      card?.copyWith(title: _name.text.trim(), data: data) ??
          // A stand-in that carries the address and name back to the caller.
          CardItem(id: '', x: 0, y: 0, z: 0, createdAt: DateTime.utc(2026), w: 1, h: 1, data: data, title: _name.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final typed = _address.text.trim();
    final valid = EmbedData.normalize(typed) != null;
    return _EditorFrame(
      title: 'Website',
      width: 520,
      onSave: valid ? _save : null,
      saveLabel: widget.card == null ? 'Add to page' : 'Save',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
        LabeledField(
          label: 'Web address',
          controller: _address,
          hint: 'example.com/page',
          autofocus: widget.card == null,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _save(),
          errorText: typed.isEmpty || valid ? null : 'That doesn’t look like a web address',
        ),
        LabeledField(label: 'Name (optional)', controller: _name, hint: 'What to call it on the page'),
        Text(
          'The card shows the site’s name and opens the page in your browser.',
          style: TextStyle(fontSize: 13, height: 1.45, color: context.colors.textMuted),
        ),
      ]),
    );
  }
}
