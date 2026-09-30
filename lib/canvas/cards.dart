import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../board/ids.dart';
import '../board/model.dart';
import '../theme/colors.dart';
import '../theme/tokens.g.dart';
import '../ui/icons.dart';

// Cards built on the board: Kanban, timeline, diagram, table and website
// (design/source/Board.dc.html). They are drawn in the design's own px and
// scaled by the card's `unit`, so everything on a card grows together.

/// Height of a card's header, with its icon, name and chip.
const _header = 38.0;

/// The chip in the header: "Kanban", "Timeline"… (a website has none).
String? cardChip(CardData d) => switch (d) {
      KanbanData _ => 'Kanban',
      TimelineData _ => 'Timeline',
      DiagramData _ => 'Diagram',
      TableData _ => 'Table',
      EmbedData _ => null,
    };

/// What a card is called in a sentence: "Added a Kanban board to the page".
String cardNoun(CardData d) => switch (d) {
      KanbanData _ => 'Kanban board',
      TimelineData _ => 'timeline',
      DiagramData _ => 'diagram',
      TableData _ => 'table',
      EmbedData _ => 'website',
    };

/// The name in a card's header: its own, or what it is.
String cardTitle(CardItem card) {
  if (card.title.isNotEmpty) return card.title;
  return switch (card.data) {
    KanbanData _ => 'Kanban board',
    TimelineData _ => 'Timeline',
    DiagramData _ => 'Diagram',
    TableData _ => 'Table',
    EmbedData e => e.host,
  };
}

TextPainter _text(
  String text, {
  required double size,
  FontWeight weight = FontWeight.w400,
  Color color = const Color(0xFF000000),
  double maxWidth = double.infinity,
  int? maxLines,
  double? spacing,
  bool struck = false,
  bool tabular = false,
}) =>
    TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: FontFamilies.ui,
          fontSize: size,
          fontWeight: weight,
          height: 1.2,
          color: color,
          letterSpacing: spacing,
          decoration: struck ? TextDecoration.lineThrough : null,
          decorationColor: color,
          fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: maxLines == null ? null : '…',
    )..layout(maxWidth: math.max(maxWidth, 0));

void _draw(Canvas canvas, TextPainter text, Offset at) {
  text.paint(canvas, at);
  text.dispose();
}

/// Draws a card in page space (after the item's own move and rotation),
/// its top-left corner at the origin.
void paintCard(Canvas canvas, CardItem card, EndlessColors c) {
  final u = card.unit;
  final size = Size(card.w / u, card.h / u);
  final shape = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12));
  canvas
    ..save()
    ..scale(u);
  // 0 12px 24px -18px shadow
  if (size.shortestSide > 40) {
    canvas.drawRRect(
      shape.deflate(18).shift(const Offset(0, 12)),
      Paint()
        ..color = c.shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
  }
  canvas
    ..drawRRect(shape, Paint()..color = c.surface)
    ..save()
    ..clipRRect(shape);

  final data = card.data;
  final build = c.plumDeep;
  switch (data) {
    case KanbanData d:
      _paintHeader(canvas, size.width, c, EIcons.kanban, build, cardTitle(card), chip: cardChip(d));
      _kanban(canvas, d, size, c);
    case TimelineData d:
      _paintHeader(canvas, size.width, c, EIcons.timelineDots, build, cardTitle(card), chip: cardChip(d));
      _timeline(canvas, d, size, c);
    case DiagramData d:
      _paintHeader(canvas, size.width, c, EIcons.diagram, build, cardTitle(card), chip: cardChip(d));
      _diagram(canvas, d, size, c);
    case TableData d:
      _paintHeader(canvas, size.width, c, EIcons.table, c.accentDeep, cardTitle(card), chip: cardChip(d), blue: true);
      _table(canvas, d, size, c);
    case EmbedData d:
      _paintHeader(canvas, size.width, c, EIcons.globe, c.accentDeep, cardTitle(card), pad: 10);
      _embed(canvas, d, size, c);
  }

  canvas
    ..restore()
    ..drawRRect(
      shape.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = c.line,
    )
    ..restore();
}

void _paintHeader(
  Canvas canvas,
  double width,
  EndlessColors c,
  EIconData icon,
  Color iconColor,
  String title, {
  String? chip,
  bool blue = false,
  double pad = 12,
}) {
  paintEIcon(canvas, icon, Offset(pad, 11), 16, iconColor);
  var right = width - pad;
  if (chip != null) {
    final label = _text(chip, size: 11, weight: FontWeight.w600, color: blue ? c.accentDeep : c.plumDeep);
    final box = Rect.fromLTWH(right - label.width - 16, (_header - label.height - 4) / 2, label.width + 16, label.height + 4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, Radius.circular(box.height / 2)),
      Paint()..color = blue ? c.accentTint : c.plumTint,
    );
    _draw(canvas, label, box.topLeft + const Offset(8, 2));
    right = box.left - 8;
  }
  final name = _text(title, size: 13, weight: FontWeight.w600, color: c.text, maxWidth: right - pad - 24, maxLines: 1);
  final at = Offset(pad + 24, (_header - name.height) / 2);
  _draw(canvas, name, at);
  canvas.drawRect(Rect.fromLTWH(0, _header, width, 1), Paint()..color = c.lineSoft);
}

/// Draws the columns and their cards (with a [canvas]) and returns the
/// height the card needs to show them all.
double _kanban(Canvas? canvas, KanbanData d, Size size, EndlessColors c) {
  const pad = 10.0, gap = 8.0;
  final n = math.max(d.columns.length, 1);
  final colW = (size.width - 2 * pad - gap * (n - 1)) / n;
  var tallest = 0.0;
  for (final (i, col) in d.columns.indexed) {
    final left = pad + i * (colW + gap);
    final column = Rect.fromLTRB(left, _header + pad, left + colW, size.height - pad);
    if (canvas != null) {
      canvas
        ..drawRRect(RRect.fromRectAndRadius(column, const Radius.circular(8)), Paint()..color = c.menuTile)
        ..save()
        ..clipRect(column);
    }
    final label = _text(
      '${col.title} · ${col.cards.length}'.toUpperCase(),
      size: 11,
      weight: FontWeight.w700,
      color: c.textMuted,
      spacing: 0.66,
      maxWidth: colW - 16,
      maxLines: 1,
    );
    var y = column.top + 8;
    final labelHeight = label.height;
    if (canvas != null) {
      _draw(canvas, label, Offset(left + 8, y));
    } else {
      label.dispose();
    }
    y += labelHeight + 6;
    // The last column is what's done; the ones between are in progress.
    final done = n > 1 && i == n - 1;
    final doing = i > 0 && !done;
    for (final card in col.cards) {
      final text = _text(card.text, size: 12, color: done ? c.textMuted : c.text, struck: done, maxWidth: colW - 32);
      final box = Rect.fromLTWH(left + 8, y, colW - 16, text.height + 16 + (doing ? 3 : 0));
      if (canvas != null) {
        final r = RRect.fromRectAndRadius(box, const Radius.circular(6));
        canvas
          ..drawRRect(
            r.shift(const Offset(0, 1)),
            Paint()
              ..color = c.shadow.withValues(alpha: c.shadow.a * 0.27)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1),
          )
          ..drawRRect(r, Paint()..color = c.surface);
        if (doing) {
          canvas
            ..save()
            ..clipRRect(r)
            ..drawRect(Rect.fromLTWH(box.left, box.top, box.width, 3), Paint()..color = c.accent)
            ..restore();
        }
        _draw(canvas, text, box.topLeft + Offset(8, doing ? 11 : 8));
      } else {
        text.dispose();
      }
      y += box.height + 6;
    }
    tallest = math.max(tallest, y + 2 - column.top);
    canvas?.restore();
  }
  return _header + pad + tallest + pad;
}

void _timeline(Canvas canvas, TimelineData d, Size size, EndlessColors c) {
  const pad = 24.0;
  final y = _header + 30;
  canvas.drawRect(Rect.fromLTWH(pad, y, size.width - 2 * pad, 2), Paint()..color = c.lineStrong);
  if (d.events.isEmpty) return;
  final colW = (size.width - 2 * pad) / d.events.length;
  for (final (i, e) in d.events.indexed) {
    final x = pad + i * colW;
    final dot = Offset(x + 8, y);
    // Done and up next are filled dots with a ring of paper around them;
    // what's still to come is an open ring.
    final (outer, inner) = switch (e.state) {
      EventState.done => (c.surface, c.green),
      EventState.now => (c.surface, c.accent),
      EventState.later => (c.accent, c.surface),
    };
    canvas
      ..drawCircle(dot, 8, Paint()..color = outer)
      ..drawCircle(dot, 5, Paint()..color = inner);
    final date = _text(e.date, size: 12, weight: FontWeight.w700, color: c.text, maxWidth: colW - 8, maxLines: 1);
    final dateBottom = _header + 46 + date.height;
    _draw(canvas, date, Offset(x, _header + 46));
    _draw(
      canvas,
      _text(e.label, size: 12, color: c.textMuted, maxWidth: colW - 8, maxLines: 1),
      Offset(x, dateBottom + 8),
    );
  }
}

class _Step {
  _Step(this.node, this.text, this.box, this.row);

  final DiagramNode node;
  final TextPainter text;
  final Rect box;
  final int row;
}

/// Lays the steps out left to right, wrapping into rows [width] wide.
/// Positions are relative to the top of the first row.
List<_Step> _steps(DiagramData d, double width, Color color) {
  const side = 14.0, gap = 20.0, rowHeight = 52.0, rowGap = 28.0;
  final out = <_Step>[];
  var x = side, row = 0;
  for (final node in d.nodes) {
    final text = _text(node.text, size: 12, weight: FontWeight.w600, color: color, maxLines: 1, maxWidth: 220);
    final diamond = node.shape == NodeShape.diamond;
    final w = diamond ? math.max(60.0, text.width + 26) : math.max(84.0, text.width + 24);
    final h = diamond ? 52.0 : 44.0;
    if (x > side && x + w > width - side) {
      x = side;
      row++;
    }
    out.add(_Step(node, text, Rect.fromLTWH(x, row * (rowHeight + rowGap) + (rowHeight - h) / 2, w, h), row));
    x += w + gap;
  }
  return out;
}

double _stepsHeight(List<_Step> steps) => steps.isEmpty ? 0 : (steps.last.row + 1) * 52.0 + steps.last.row * 28.0;

void _diagram(Canvas canvas, DiagramData d, Size size, EndlessColors c) {
  final steps = _steps(d, size.width, c.text);
  if (steps.isEmpty) return;
  final top = _header + math.max(12, (size.height - _header - _stepsHeight(steps)) / 2);
  canvas
    ..save()
    ..translate(0, top);

  final line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = c.textMuted;
  void head(Offset tip, Offset along) {
    final v = along / along.distance, n = Offset(-v.dy, v.dx);
    canvas.drawPath(
      Path()
        ..moveTo((tip - v * 4 + n * 4).dx, (tip - v * 4 + n * 4).dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo((tip - v * 4 - n * 4).dx, (tip - v * 4 - n * 4).dy),
      line,
    );
  }

  final at = {for (final (i, s) in steps.indexed) s.node.id: i};
  for (final (from, to) in d.edges) {
    final ia = at[from], ib = at[to];
    if (ia == null || ib == null || ia == ib) continue;
    final a = steps[ia], b = steps[ib];
    if (ib == ia + 1 && a.row == b.row) {
      // The next step on the same row: straight across the gap.
      final tip = Offset(b.box.left - 2, b.box.center.dy);
      canvas.drawLine(Offset(a.box.right, a.box.center.dy), tip, line);
      head(tip, const Offset(1, 0));
    } else if (ib == ia + 1) {
      // The next step starts a new row: down, back across, and down to it.
      final mid = a.row * 80.0 + 52 + 14;
      final tip = Offset(b.box.center.dx, b.box.top - 2);
      canvas.drawPath(
        Path()
          ..moveTo(a.box.center.dx, a.box.bottom)
          ..lineTo(a.box.center.dx, mid)
          ..lineTo(tip.dx, mid)
          ..lineTo(tip.dx, tip.dy),
        line,
      );
      head(tip, const Offset(0, 1));
    } else {
      // Any other pair: a straight arrow from edge to edge.
      final v = b.box.center - a.box.center;
      if (v.distance < 1) continue;
      Offset edge(Rect r, Offset dir) {
        final t = math.min(
          dir.dx == 0 ? double.infinity : r.width / 2 / dir.dx.abs(),
          dir.dy == 0 ? double.infinity : r.height / 2 / dir.dy.abs(),
        );
        return r.center + dir * t;
      }

      final tip = edge(b.box, -v);
      canvas.drawLine(edge(a.box, v), tip, line);
      head(tip, v);
    }
  }

  for (final s in steps) {
    final (fill, stroke) = switch (s.node.color) {
      NodeColor.blue => (c.accentTint, c.accent),
      NodeColor.clay => (c.clayTint, c.clay),
      NodeColor.green => (c.greenTint, c.green),
      NodeColor.plum => (c.plumTint, c.plum),
    };
    final r = s.box;
    final path = Path();
    switch (s.node.shape) {
      case NodeShape.box:
        path.addRRect(RRect.fromRectAndRadius(r, const Radius.circular(8)));
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
    _draw(canvas, s.text, r.center - Offset(s.text.width / 2, s.text.height / 2));
  }
  canvas.restore();
}

const _rowHeight = 29.0;

void _table(Canvas canvas, TableData d, Size size, EndlessColors c) {
  final n = math.max(d.columns, 1);
  final colW = size.width / n;
  for (final (r, row) in d.cells.indexed) {
    final y = _header + 1 + r * _rowHeight;
    if (y > size.height) break;
    final head = d.header && r == 0;
    if (head) canvas.drawRect(Rect.fromLTWH(0, y, size.width, _rowHeight), Paint()..color = c.menuTile);
    canvas.drawRect(
      Rect.fromLTWH(0, y + _rowHeight - 1, size.width, 1),
      Paint()..color = head ? c.cardLine : c.lineSoft,
    );
    for (final (i, cell) in row.indexed) {
      if (cell.isEmpty) continue;
      _draw(
        canvas,
        _text(
          cell,
          size: 12,
          weight: head ? FontWeight.w700 : FontWeight.w400,
          color: c.text,
          maxWidth: colW - 16,
          maxLines: 1,
          tabular: true,
        ),
        Offset(i * colW + 8, y + 7),
      );
    }
  }
}

/// The website card's Open button, in the design's px for a card [size].
Rect _openButton(Size size) {
  final label = _text('Open', size: 12, weight: FontWeight.w600);
  final width = label.width.ceilToDouble() + 20;
  label.dispose();
  return Rect.fromLTWH(size.width - 10 - width, size.height - 35, width, 30);
}

/// Where a website card's Open button is, relative to the card's top-left
/// corner (before its rotation), in page px.
Rect embedOpenRect(CardItem card) {
  final u = card.unit;
  final r = _openButton(Size(card.w / u, card.h / u));
  return Rect.fromLTRB(r.left * u, r.top * u, r.right * u, r.bottom * u);
}

void _embed(Canvas canvas, EmbedData d, Size size, EndlessColors c) {
  final preview = Rect.fromLTRB(0, _header + 1, size.width, size.height - 40);
  if (preview.height > 0) {
    canvas
      ..drawRect(preview, Paint()..color = c.previewBg)
      ..save()
      ..clipRect(preview);
    // Stripes 8 px wide, 8 px apart, running down to the right.
    final stripe = Paint()
      ..color = c.text.withValues(alpha: 0.06)
      ..strokeWidth = 8;
    const step = 16 * math.sqrt2;
    for (var x = -preview.height - step; x < preview.width + step; x += step) {
      canvas.drawLine(Offset(x, preview.top - 8), Offset(x + preview.height + 16, preview.bottom + 8), stripe);
    }
    canvas.restore();
    final note = _text('Open to see this page', size: 13, color: c.textMuted, maxWidth: size.width - 24, maxLines: 1);
    final at = preview.center - Offset(note.width / 2, note.height / 2);
    _draw(canvas, note, at);
  }
  final open = _openButton(size);
  final host = _text(d.host, size: 12, color: c.textMuted, maxWidth: open.left - 18, maxLines: 1);
  final hostAt = Offset(10, size.height - 20 - host.height / 2);
  _draw(canvas, host, hostAt);
  canvas.drawRRect(
    RRect.fromRectAndRadius(open.deflate(0.5), const Radius.circular(8)),
    Paint()
      ..style = PaintingStyle.stroke
      ..color = c.lineStrong,
  );
  final label = _text('Open', size: 12, weight: FontWeight.w600, color: c.text);
  final labelAt = open.center - Offset(label.width / 2, label.height / 2);
  _draw(canvas, label, labelAt);
}

/// The size a card wants for what it holds, in the design's px: the sizes
/// on Board.png for what's shown there, growing with more columns, rows,
/// events or steps.
Size cardNaturalSize(CardData data) {
  switch (data) {
    case KanbanData d:
      final width = (140.0 * d.columns.length).clamp(300.0, 760.0);
      return Size(width, math.max(272, cardNaturalHeight(d, width)));
    case TimelineData d:
      return Size((48 + 154.5 * d.events.length).clamp(360.0, 900.0), 132);
    case DiagramData d:
      final steps = _steps(d, double.infinity, const Color(0xFF000000));
      final width = steps.isEmpty ? 320.0 : (steps.last.box.right + 14).clamp(320.0, 760.0);
      for (final s in steps) {
        s.text.dispose();
      }
      return Size(width, cardNaturalHeight(d, width));
    case TableData d:
      final width = (55.0 * d.columns).clamp(220.0, 720.0);
      return Size(width, math.max(200, cardNaturalHeight(d, width)));
    case EmbedData _:
      return const Size(290, 200);
  }
}

/// The least height that shows everything on a card [width] wide (in the
/// design's px).
double cardNaturalHeight(CardData data, double width) {
  switch (data) {
    case KanbanData d:
      return _kanban(null, d, Size(width, 0), paperLight);
    case TimelineData _:
      return 132;
    case DiagramData d:
      final steps = _steps(d, width, const Color(0xFF000000));
      final height = _stepsHeight(steps);
      for (final s in steps) {
        s.text.dispose();
      }
      return _header + math.max(160, height + 56);
    case TableData d:
      return _header + 1 + d.rows * _rowHeight + 10;
    case EmbedData _:
      return 120;
  }
}

/// The least width a card can be stretched to (in the design's px), so its
/// columns stay readable.
double cardMinWidth(CardData data) => switch (data) {
      KanbanData d => math.max(180, 84.0 * d.columns.length),
      TimelineData d => math.max(200, 48 + 64.0 * d.events.length),
      DiagramData _ => 140,
      TableData d => math.max(140, 40.0 * d.columns),
      EmbedData _ => 170,
    };

/// [card] made tall (and wide) enough for what it holds now. It never
/// shrinks: a card you stretched stays as big as you made it.
CardItem fitCard(CardItem card) {
  final u = card.unit;
  final w = math.max(card.w, cardMinWidth(card.data) * u);
  final h = math.max(card.h, cardNaturalHeight(card.data, w / u) * u);
  if (w == card.w && h == card.h) return card;
  return card.withBox(x: card.x, y: card.y, w: w, h: h);
}

/// A new card holding [data], centered on [center].
CardItem newCard(CardData data, Offset center, {required int z, required DateTime now, String title = ''}) {
  final natural = cardNaturalSize(data) * CardItem.defaultUnit;
  final size = Size(natural.width.roundToDouble(), natural.height.roundToDouble());
  return CardItem(
    id: newId('it'),
    x: center.dx - size.width / 2,
    y: center.dy - size.height / 2,
    z: z,
    createdAt: now,
    w: size.width,
    h: size.height,
    data: data,
    title: title,
  );
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Sep 30": how a timeline shows a day.
String shortDate(DateTime d) => '${_months[d.month - 1]} ${d.day}';

// What each card starts with.

KanbanData starterKanban() =>
    const KanbanData([KanbanColumn('To do'), KanbanColumn('Doing'), KanbanColumn('Done')]);

/// Today, a week on and two weeks on.
TimelineData starterTimeline(DateTime today) => TimelineData([
      TimelineEvent(date: shortDate(today), label: 'Start', state: EventState.now),
      TimelineEvent(date: shortDate(today.add(const Duration(days: 7))), label: 'Next step'),
      TimelineEvent(date: shortDate(today.add(const Duration(days: 14))), label: 'Finish'),
    ]);

DiagramData starterDiagram() => DiagramData.flow([
      DiagramNode(id: newId('n'), text: 'Start', shape: NodeShape.pill, color: NodeColor.clay),
      DiagramNode(id: newId('n'), text: 'Step'),
      DiagramNode(id: newId('n'), text: 'Done?', shape: NodeShape.diamond, color: NodeColor.green),
    ]);

/// Three columns and four rows, the first one for the column names.
TableData starterTable() => TableData([for (var r = 0; r < 4; r++) List.filled(3, '')]);
