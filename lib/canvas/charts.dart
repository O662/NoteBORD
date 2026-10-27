import 'dart:math' as math;
import 'dart:ui' show Brightness, FontFeature;

import 'package:flutter/painting.dart';

import '../board/ids.dart';
import '../board/model.dart';
import '../office/office_model.dart' show Workbook;
import '../office/xlsx_reader.dart' show cellRef;
import '../theme/colors.dart';
import '../theme/tokens.g.dart';
import '../ui/icons.dart';
import 'cards.dart' show cardTitle;
import 'graph_card.dart' show graphColors;

// Charts linked to tables and Excel (Charts.png, Charts.dc.html): bar,
// line, area or scatter charts of a table on the page or a range of an
// Excel card's sheet. A chart keeps a copy of its range (`cells`), which is
// what's drawn; the notebook reads it again whenever its source changes,
// in the same undo step. Everything is drawn in the design's units, scaled
// by the chart's `unit`. A tall chart has the design's first header (the
// chart type and Data); a short one its second (where the numbers come
// from and their total).

// Ranges.

/// A block of cells, from 0, both ends included.
typedef CellBlock = ({int top, int left, int bottom, int right});

/// "A" for column 0, "AA" for 26.
String columnName(int i) {
  var n = i + 1;
  var s = '';
  while (n > 0) {
    s = String.fromCharCode(65 + (n - 1) % 26) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

/// "A1:C7" or "B2" as a block of cells, or null if it isn't one.
CellBlock? parseRange(String range) {
  final parts = range.trim().replaceAll(r'$', '').split(':');
  if (parts.length > 2 || parts.first.isEmpty) return null;
  final a = cellRef(parts.first.trim()), b = cellRef(parts.last.trim());
  if (a == null || b == null) return null;
  return (
    top: math.min(a.$1, b.$1),
    left: math.min(a.$2, b.$2),
    bottom: math.max(a.$1, b.$1),
    right: math.max(a.$2, b.$2),
  );
}

/// "A1:C7".
String rangeLabel(CellBlock b) => '${columnName(b.left)}${b.top + 1}:${columnName(b.right)}${b.bottom + 1}';

/// The cells of [grid] in [range] (all of it when empty or not a range),
/// without the empty rows and columns at the end, every row as long.
List<List<String>> cellsIn(List<List<String>> grid, String range) {
  final b = parseRange(range);
  final top = b?.top ?? 0, left = b?.left ?? 0;
  final bottom = b?.bottom ?? grid.length - 1;
  var right = b?.right ?? grid.fold<int>(0, (m, r) => math.max(m, r.length)) - 1;
  final rows = <List<String>>[
    for (var r = top; r <= bottom && r < grid.length; r++)
      [for (var col = left; col <= right; col++) col < grid[r].length ? grid[r][col].trim() : ''],
  ];
  while (rows.isNotEmpty && rows.last.every((s) => s.isEmpty)) {
    rows.removeLast();
  }
  right = rows.fold<int>(-1, (m, r) => math.max(m, r.lastIndexWhere((s) => s.isNotEmpty)));
  return [for (final r in rows) r.sublist(0, right + 1)];
}

// Reading the source.

/// The cells [source] points at, read from [item] (the table or Excel card
/// it names) and, for Excel, its [book]. Null when they can't be read: the
/// item isn't the right kind, or the file isn't read yet.
List<List<String>>? sourceCells(ChartSource source, Item? item, {Workbook? book}) {
  switch (item) {
    case CardItem(data: final TableData t) when !source.isExcel:
      return cellsIn(t.cells, source.range);
    case OfficeItem f when source.isExcel && f.mime == 'xlsx':
      final sheet = book?.sheets.where((s) => s.name == source.sheet).firstOrNull ??
          (source.sheet == null ? book?.sheets.firstOrNull : null);
      return sheet == null ? null : cellsIn(sheet.cells, source.range);
    default:
      return null;
  }
}

/// What a source is called on the chart: a table's name, an Excel file's.
String sourceName(Item item) => switch (item) {
      final CardItem c => cardTitle(c),
      final OfficeItem f => f.name,
      _ => '',
    };

/// [chart] with its numbers read again from [item] (and [book]), or null
/// when it isn't following it, nothing changed, or they can't be read.
ChartItem? refreshedChart(ChartItem chart, Item? item, {Workbook? book}) {
  final s = chart.source;
  if (!chart.live || s == null || item == null || item.id != s.ref) return null;
  final cells = sourceCells(s, item, book: book);
  if (cells == null) return null;
  final name = sourceName(item);
  if (_sameCells(cells, chart.cells) && name == s.name) return null;
  return chart.copyWith(cells: cells, source: () => s.copyWith(name: name));
}

bool _sameCells(List<List<String>> a, List<List<String>> b) {
  if (a.length != b.length) return false;
  for (var r = 0; r < a.length; r++) {
    if (a[r].length != b[r].length) return false;
    for (var c = 0; c < a[r].length; c++) {
      if (a[r][c] != b[r][c]) return false;
    }
  }
  return true;
}

/// A new chart of [cells] from [source], with its top-left at [at].
ChartItem newChart(ChartSource source, List<List<String>> cells, {required Offset at, required int z, required DateTime now}) =>
    ChartItem(
      id: newId('it', now: now),
      x: at.dx,
      y: at.dy,
      z: z,
      createdAt: now,
      w: ChartItem.size.width,
      h: ChartItem.size.height,
      source: source,
      cells: cells,
    );

// Series.

final _number = RegExp(r'^([+\-−]?)\s*[$€£¥]?\s*(\d[\d,]*\.?\d*|\.\d+)(?:[eE]([+\-]?\d+))?\s*%?\s*[A-Za-z·/]{0,6}$');

/// A cell as a number ("1.00", "1,234", "45%", "$3.20", "2 h"), or null.
double? chartNumber(String cell) {
  final m = _number.firstMatch(cell.trim());
  if (m == null) return null;
  var v = double.tryParse(m[2]!.replaceAll(',', ''));
  if (v == null) return null;
  if (m[3] != null) v *= math.pow(10, int.parse(m[3]!));
  return m[1] == '-' || m[1] == '−' ? -v : v;
}

class ChartSeries {
  const ChartSeries(this.name, this.values, {this.column});

  final String name;

  /// One per category; null where a cell has no number.
  final List<double?> values;

  /// Which column of the range it is (from 0), when series are columns.
  final int? column;
}

/// What a chart shows: the categories along the bottom and a series of
/// numbers for each.
class ChartData {
  const ChartData(this.categories, this.series);

  final List<String> categories;
  final List<ChartSeries> series;

  bool get isEmpty => series.isEmpty;

  /// The smallest and largest numbers, or null when there are none.
  (double, double)? get extent {
    double? lo, hi;
    for (final s in series) {
      for (final v in s.values) {
        if (v == null) continue;
        lo = lo == null ? v : math.min(lo, v);
        hi = hi == null ? v : math.max(hi, v);
      }
    }
    return lo == null ? null : (lo, hi!);
  }
}

/// The series in [cells]. A first row with words in it names the columns.
/// The first column labels the rows (a column of words, or of numbers under
/// a name: "Trial" over 1, 2, 3 reads "Trial 1"…). With more columns of
/// numbers than rows (a week's hours across), each row is a series;
/// otherwise each column is. [name] names a series nothing else names.
ChartData readChart(List<List<String>> cells, {String name = ''}) {
  final rows = [for (final r in cells) if (r.any((s) => s.trim().isNotEmpty)) r];
  if (rows.isEmpty) return const ChartData([], []);
  final cols = rows.fold<int>(0, (m, r) => math.max(m, r.length));
  String at(List<String> r, int c) => c < r.length ? r[c].trim() : '';
  bool isNum(String s) => chartNumber(s) != null;
  final header = rows.length > 1 && rows.first.any((s) => s.trim().isNotEmpty && !isNum(s));
  final data = header ? rows.skip(1).toList() : rows;
  final head = header ? rows.first : const <String>[];
  final firstIsNumbers = data.every((r) => at(r, 0).isEmpty || isNum(at(r, 0)));
  final labels = cols >= 2 && (!firstIsNumbers || (header && data.length >= cols - 1));
  final first = labels ? 1 : 0;
  final byRows = data.length < cols - first;

  final List<String> categories;
  final List<ChartSeries> series;
  if (byRows) {
    categories = [for (var c = first; c < cols; c++) header && at(head, c).isNotEmpty ? at(head, c) : '${c - first + 1}'];
    series = [
      for (final (i, r) in data.indexed)
        ChartSeries(
          labels && at(r, 0).isNotEmpty ? at(r, 0) : (data.length == 1 && name.isNotEmpty ? name : 'Row ${i + 1}'),
          [for (var c = first; c < cols; c++) chartNumber(at(r, c))],
        ),
    ];
  } else {
    final lead = at(head, 0);
    categories = [
      for (final (i, r) in data.indexed)
        if (!labels)
          '${i + 1}'
        else if (isNum(at(r, 0)) && lead.isNotEmpty)
          '$lead ${at(r, 0)}'
        else
          at(r, 0),
    ];
    series = [
      for (var c = first; c < cols; c++)
        ChartSeries(
          at(head, c).isNotEmpty ? at(head, c) : (cols - first == 1 && name.isNotEmpty ? name : 'Column ${columnName(c)}'),
          [for (final r in data) chartNumber(at(r, c))],
          column: c,
        ),
    ];
  }
  return ChartData(categories, [for (final s in series) if (s.values.any((v) => v != null)) s]);
}

final _data = Expando<ChartData>('chartData');

ChartData chartDataOf(ChartItem c) => _data[c] ??= readChart(c.cells, name: c.source?.name ?? '');

/// Series [i]'s color, as stored.
Color chartColor(ChartItem c, int i) => i < c.colors.length ? c.colors[i] : graphColors[i % graphColors.length];

/// The chart's name: its title, or what its series are, or its source.
String chartTitle(ChartItem c) {
  if (c.title.trim().isNotEmpty) return c.title.trim();
  final s = chartDataOf(c).series;
  if (s.length >= 2 && s.length <= 3) return s.map((x) => x.name).join(' vs. ');
  final name = c.source?.name ?? '';
  return name.isEmpty ? 'Chart' : name;
}

/// The range shown in the link: as given, or the whole of what was read.
String _rangeShown(ChartItem c) {
  final given = parseRange(c.source?.range ?? '');
  if (given != null) return rangeLabel(given);
  final cols = c.cells.fold<int>(0, (m, r) => math.max(m, r.length));
  if (c.cells.isEmpty || cols == 0) return 'A1';
  return rangeLabel((top: 0, left: 0, bottom: c.cells.length - 1, right: cols - 1));
}

/// Where its numbers come from: "Lab data.xlsx › Sheet1 › A1:C7 · live",
/// "Study hours table · live", or "Snapshot of …" once unlinked.
String chartLinkLabel(ChartItem c) {
  final s = c.source;
  if (s == null) return 'Snapshot';
  final String where;
  if (s.isExcel) {
    where = [if (s.name.isNotEmpty) s.name else 'Excel sheet', ?s.sheet, _rangeShown(c)].join(' › ');
  } else {
    final name = s.name.isEmpty ? 'Table' : s.name;
    where = s.range.isEmpty ? '$name table' : '$name › ${_rangeShown(c)}';
  }
  return c.linked ? '$where · live' : 'Snapshot of $where';
}

/// A number on an axis or a total: whole numbers as they are, others to
/// [decimals] places (two at most when not given); minus signs as −.
String chartNumberText(double v, {int? decimals}) {
  final String s;
  if (decimals != null) {
    s = v.toStringAsFixed(decimals);
  } else {
    final r = (v * 100).round() / 100;
    s = r == r.roundToDouble() ? '${r.round()}' : r.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
  }
  return (s == '-0' || RegExp(r'^-0\.0*$').hasMatch(s) ? s.substring(1) : s).replaceFirst('-', '−');
}

/// The total of a chart with one series ("10 h"), or null.
String? chartTotal(ChartItem c) {
  final d = chartDataOf(c);
  if (d.series.length != 1 || c.chartType == ChartType.scatter) return null;
  final sum = d.series.single.values.fold<double>(0, (a, v) => a + (v ?? 0));
  return [chartNumberText(sum), if (c.suffix.isNotEmpty) c.suffix].join(' ');
}

/// Everything a chart says, for search.
String chartText(ChartItem c) {
  final d = chartDataOf(c);
  return [
    chartTitle(c),
    chartLinkLabel(c),
    for (final s in d.series) s.name,
    d.categories.join(' '),
  ].where((s) => s.trim().isNotEmpty).join('\n');
}

// The axes.

double _niceStep(double raw) {
  if (!(raw > 0) || !raw.isFinite) return 1;
  final e = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final f = raw / e;
  return (f < 1.5 ? 1 : (f < 3 ? 2 : (f < 7 ? 5 : 10))) * e;
}

/// An axis over [lo]…[hi] with about one line per [spacing] of [room]:
/// from zero for bars, lines and areas; a step's headroom above the top
/// (Charts.dc.html's 0–1.4 for numbers up to 1.2).
({double lo, double hi, double step, int decimals}) chartAxis(double lo, double hi, double room, {required bool fromZero, double spacing = 55}) {
  if (fromZero) {
    lo = math.min(lo, 0);
    hi = math.max(hi, 0);
  }
  if (hi - lo < 1e-12) {
    if (fromZero) {
      hi = lo == 0 ? 1 : hi + lo.abs();
    } else {
      lo -= 1;
      hi += 1;
    }
  }
  final step = _niceStep((hi - lo) / math.max(2, room / spacing));
  final top = hi > 0 || !fromZero ? ((hi / step + 1e-9).floorToDouble() + 1) * step : 0.0;
  final bottom = fromZero && lo >= 0 ? 0.0 : ((lo / step - 1e-9).ceilToDouble() - 1) * step;
  final decimals = math.max(0, -((math.log(step) / math.ln10) + 1e-9).floor());
  return (lo: bottom, hi: top, step: step, decimals: decimals);
}

// Layout and buttons.

/// What's under a point on a chart: a chart type, or Data.
sealed class ChartHit {
  const ChartHit();
}

class ChartTypeHit extends ChartHit {
  const ChartTypeHit(this.type);

  final ChartType type;

  @override
  bool operator ==(Object other) => other is ChartTypeHit && other.type == type;

  @override
  int get hashCode => type.hashCode;
}

class ChartDataHit extends ChartHit {
  const ChartDataHit();

  @override
  bool operator ==(Object other) => other is ChartDataHit;

  @override
  int get hashCode => 0;
}

String chartTypeName(ChartType t) => switch (t) {
      ChartType.bar => 'Bar',
      ChartType.line => 'Line',
      ChartType.area => 'Area',
      ChartType.scatter => 'Scatter',
    };

double _textWidth(String s, double size, FontWeight weight) {
  final p = TextPainter(
    text: TextSpan(text: s, style: TextStyle(fontFamily: FontFamilies.ui, fontSize: size, fontWeight: weight)),
    textDirection: TextDirection.ltr,
  )..layout();
  final w = p.width;
  p.dispose();
  return w;
}

class _ChartLayout {
  _ChartLayout(ChartItem c)
      : size = Size(c.w / c.unit, c.h / c.unit),
        compact = c.h / c.unit < 300 {
    final w = size.width, h = size.height;
    if (compact) {
      header = 48;
      plot = Rect.fromLTRB(56, 62, math.max(96, w - 34), math.max(102, h - 30));
      return;
    }
    header = 56;
    // Right to left: Data, then the chart type switch.
    final dw = _textWidth('Data', 13, FontWeight.w600) + 26;
    data = Rect.fromLTWH(w - 12 - dw, 8, dw, 40);
    final widths = [
      for (final t in ChartType.values) _textWidth(chartTypeName(t), 13, t == c.chartType ? FontWeight.w700 : FontWeight.w500) + 24,
    ];
    final segWidth = widths.fold<double>(0, (a, b) => a + b) + 2 * (widths.length - 1) + 6;
    seg = Rect.fromLTWH(data!.left - 10 - segWidth, 6, segWidth, 44);
    var x = seg!.left + 3;
    for (final width in widths) {
      types.add(Rect.fromLTWH(x, 9, width, 38));
      x += width + 2;
    }
    plot = Rect.fromLTRB(56, 97, math.max(96, w - 34), math.max(137, h - 57));
  }

  final Size size;
  final bool compact;
  late final double header;
  late final Rect plot;
  Rect? data, seg;
  final types = <Rect>[];
}

final _layouts = Expando<_ChartLayout>('chartLayout');

_ChartLayout _layoutOf(ChartItem c) => _layouts[c] ??= _ChartLayout(c);

/// The smallest a chart can be stretched to.
Size chartMinSize(ChartItem c) => Size(420 * c.unit, 180 * c.unit);

/// What's under [local] (relative to the chart's top-left, unrotated): its
/// type switch and Data button, on a tall chart.
ChartHit? chartHitAt(ChartItem c, Offset local) {
  final l = _layoutOf(c);
  final p = local / c.unit;
  if (l.data?.contains(p) ?? false) return const ChartDataHit();
  for (final (i, r) in l.types.indexed) {
    if (r.inflate(1).contains(p)) return ChartTypeHit(ChartType.values[i]);
  }
  return null;
}

// Painting.

TextPainter _text(String s, double size, Color color, {FontWeight weight = FontWeight.w400, double? maxWidth}) => TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontFamily: FontFamilies.ui,
          fontSize: size,
          fontWeight: weight,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(0, maxWidth ?? double.infinity));

/// Draws [p] with its left edge at [x], centered on [cy]; returns its width.
double _put(Canvas canvas, TextPainter p, double x, double cy) {
  p.paint(canvas, Offset(x, cy - p.height / 2));
  final w = p.width;
  p.dispose();
  return w;
}

/// The link's color: blue for Excel, green for a table (Charts.dc.html).
Color chartLinkColor(ChartItem chart, EndlessColors c) =>
    !chart.live ? c.textMuted : (chart.source!.isExcel ? c.accentDeep : c.greenDeep);

/// Draws [chart] with its top-left at the origin.
void paintChart(Canvas canvas, ChartItem chart, Brightness brightness, EndlessColors c) {
  final l = _layoutOf(chart);
  final size = l.size;
  canvas
    ..save()
    ..scale(chart.unit);
  final rect = Offset.zero & size;
  final card = RRect.fromRectAndRadius(rect, const Radius.circular(16));
  // 0 18px 36px -22px shadow/50%
  final shade = rect.inflate(-22).shift(const Offset(0, 18));
  if (!shade.isEmpty) {
    canvas.drawRect(shade, Paint()
      ..color = c.shadow.withValues(alpha: c.shadow.a * 0.7)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
  }
  canvas
    ..drawRRect(card, Paint()..color = c.surface)
    ..save()
    ..clipRRect(card)
    ..drawLine(Offset(0, l.header - 0.5), Offset(size.width, l.header - 0.5), Paint()
      ..color = c.lineSoft
      ..strokeWidth = 1);
  final data = chartDataOf(chart);
  if (l.compact) {
    _compactHeader(canvas, chart, l, c);
  } else {
    _header(canvas, chart, l, c);
    _legend(canvas, chart, data, l, c, brightness);
  }
  _plot(canvas, chart, data, l, c, brightness);
  canvas
    ..restore()
    ..drawRRect(card.deflate(0.5), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = c.line)
    ..restore();
}

/// The link icon and where the numbers come from, from [x]; its width.
double _link(Canvas canvas, ChartItem chart, EndlessColors c, double x, double cy, double maxWidth) {
  final color = chartLinkColor(chart, c);
  if (chart.live) paintEIcon(canvas, EIcons.link, Offset(x, cy - 6), 12, color);
  final dx = chart.live ? 18.0 : 0.0;
  return dx + _put(canvas, _text(chartLinkLabel(chart), 12, color, weight: FontWeight.w600, maxWidth: maxWidth - dx), x + dx, cy);
}

void _header(Canvas canvas, ChartItem chart, _ChartLayout l, EndlessColors c) {
  final room = l.seg!.left - 16 - 12;
  _put(canvas, _text(chartTitle(chart), 15, c.text, weight: FontWeight.w700, maxWidth: room), 16, 19);
  _link(canvas, chart, c, 16, 38, room);

  // The chart type switch: the one showing is raised.
  canvas.drawRRect(RRect.fromRectAndRadius(l.seg!, const Radius.circular(10)), Paint()..color = c.side);
  for (final (i, r) in l.types.indexed) {
    final type = ChartType.values[i];
    final on = type == chart.chartType;
    if (on) {
      final b = RRect.fromRectAndRadius(r, const Radius.circular(8));
      canvas
        ..drawRRect(b.shift(const Offset(0, 1)), Paint()
          ..color = c.shadow.withValues(alpha: c.shadow.a * 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5))
        ..drawRRect(b, Paint()..color = c.surface);
    }
    final t = _text(chartTypeName(type), 13, c.text, weight: on ? FontWeight.w700 : FontWeight.w500);
    _put(canvas, t, r.center.dx - t.width / 2, r.center.dy);
  }
  final d = l.data!;
  canvas.drawRRect(RRect.fromRectAndRadius(d.deflate(0.5), const Radius.circular(10)), Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = c.lineStrong);
  final t = _text('Data', 13, c.text, weight: FontWeight.w600);
  _put(canvas, t, d.center.dx - t.width / 2, d.center.dy);
}

void _compactHeader(Canvas canvas, ChartItem chart, _ChartLayout l, EndlessColors c) {
  final w = l.size.width;
  var right = w - 16;
  final total = chartTotal(chart);
  if (total != null) {
    final t = _text('Total $total', 13, c.text, weight: FontWeight.w700);
    right -= t.width;
    _put(canvas, t, right, 24);
    right -= 10;
  }
  final label = _text(chartLinkLabel(chart), 12, c.text, weight: FontWeight.w600, maxWidth: w * 0.45);
  final linkWidth = label.width + (chart.live ? 18 : 0);
  label.dispose();
  _link(canvas, chart, c, right - linkWidth, 24, w * 0.45 + 18);
  _put(canvas, _text(chartTitle(chart), 14, c.text, weight: FontWeight.w700, maxWidth: right - linkWidth - 16 - 12), 16, 24);
}

void _legend(Canvas canvas, ChartItem chart, ChartData data, _ChartLayout l, EndlessColors c, Brightness brightness) {
  final scatter = chart.chartType == ChartType.scatter;
  final excel = chart.source?.isExcel ?? false;
  final left = parseRange(chart.source?.range ?? '')?.left ?? 0;
  var x = 16.0;
  for (final (i, s) in data.series.indexed) {
    if (x > l.size.width - 40) break;
    final name = scatter
        ? '${i == 0 ? 'x' : 'y'} = ${s.name}'
        : (excel && s.column != null ? '${s.name} (column ${columnName(left + s.column!)})' : s.name);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x, 66 + 1.5, 12, 12), const Radius.circular(3)),
      Paint()..color = displayInk(chartColor(chart, i), brightness),
    );
    x += 18 + _put(canvas, _text(name, 12, c.text, weight: FontWeight.w600, maxWidth: l.size.width - x - 34), x + 18, 66 + 7.5) + 16;
  }
}

void _plot(Canvas canvas, ChartItem chart, ChartData data, _ChartLayout l, EndlessColors c, Brightness brightness) {
  final p = l.plot;
  final axis = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = c.textFaint;
  final extent = data.extent;
  if (data.isEmpty || extent == null || data.categories.isEmpty) {
    canvas.drawPath(Path()
      ..moveTo(p.left, p.top)
      ..lineTo(p.left, p.bottom)
      ..lineTo(p.right, p.bottom), axis);
    final t = _text('No numbers here yet', 13, c.textMuted);
    _put(canvas, t, p.center.dx - t.width / 2, p.center.dy);
    return;
  }
  final scatter = chart.chartType == ChartType.scatter;
  final xs = scatter ? _scatterX(data) : null;
  final ys = scatter ? data.series.skip(data.series.length > 1 ? 1 : 0).toList() : data.series;
  var (lo, hi) = extent;
  if (scatter) {
    final yValues = [for (final s in ys) ...s.values.whereType<double>()];
    if (yValues.isEmpty) return;
    lo = yValues.reduce(math.min);
    hi = yValues.reduce(math.max);
  }
  final y = chartAxis(lo, hi, p.height, fromZero: !scatter);
  double sy(double v) => p.bottom - (v - y.lo) / (y.hi - y.lo) * p.height;

  // Grid lines and their numbers; a short chart numbers every other one.
  final grid = Paint()
    ..color = c.lineSoft
    ..strokeWidth = 1;
  final ticks = ((y.hi - y.lo) / y.step).round();
  for (var i = 0; i <= ticks; i++) {
    final v = y.lo + i * y.step;
    final at = sy(v);
    if (i > 0) canvas.drawLine(Offset(p.left, at), Offset(p.right, at), grid);
    if (l.compact && (ticks - i).isOdd) continue;
    if (l.compact && v == 0 && ticks > 2) continue;
    final label = [chartNumberText(v, decimals: y.decimals), if (chart.suffix.isNotEmpty) chart.suffix].join(' ');
    final t = _text(label, 11, c.textMuted);
    _put(canvas, t, p.left - 10 - t.width, at);
  }

  final labelSize = l.compact ? 12.0 : 11.0;
  if (scatter) {
    final x = chartAxis(xs!.whereType<double>().reduce(math.min), xs.whereType<double>().reduce(math.max), p.width,
        fromZero: false, spacing: 120);
    double sx(double v) => p.left + (v - x.lo) / (x.hi - x.lo) * p.width;
    final count = ((x.hi - x.lo) / x.step).round();
    for (var i = 1; i <= count; i++) {
      final v = x.lo + i * x.step;
      final t = _text(chartNumberText(v, decimals: x.decimals), labelSize, c.textMuted);
      _put(canvas, t, sx(v) - t.width / 2, p.bottom + 14.5);
    }
    for (final (k, s) in ys.indexed) {
      final color = displayInk(chartColor(chart, data.series.length > 1 ? k + 1 : k), brightness);
      for (var i = 0; i < s.values.length && i < xs.length; i++) {
        final vx = xs[i], vy = s.values[i];
        if (vx == null || vy == null) continue;
        _dot(canvas, Offset(sx(vx), sy(vy)), 7, color, c.surface);
      }
    }
  } else {
    final n = data.categories.length;
    final gw = p.width / n;
    for (var i = 0; i < n; i++) {
      final t = _text(data.categories[i], labelSize, c.textMuted, maxWidth: gw - 4);
      _put(canvas, t, p.left + gw * i + gw / 2 - t.width / 2, p.bottom + 14.5);
    }
    final single = data.series.length == 1;
    final base = sy(math.max(y.lo, math.min(0, y.hi)));
    switch (chart.chartType) {
      case ChartType.bar:
        final count = data.series.length;
        final bw = single ? math.min(64.0, gw * 0.55) : math.min(34.0, gw * 0.6 / count);
        final group = count * bw + (count - 1) * 4;
        for (final (k, s) in data.series.indexed) {
          final color = displayInk(chartColor(chart, k), brightness);
          for (var i = 0; i < n && i < s.values.length; i++) {
            final v = s.values[i];
            if (v == null) continue;
            final left = p.left + gw * i + gw / 2 - group / 2 + k * (bw + 4);
            final top = sy(v);
            final bar = Rect.fromLTRB(left, math.min(top, base), left + bw, math.max(top, base));
            canvas.drawRRect(
              RRect.fromRectAndCorners(
                bar,
                topLeft: Radius.circular(v >= 0 ? (single ? 4 : 3) : 0),
                topRight: Radius.circular(v >= 0 ? (single ? 4 : 3) : 0),
                bottomLeft: Radius.circular(v < 0 ? 3 : 0),
                bottomRight: Radius.circular(v < 0 ? 3 : 0),
              ),
              Paint()..color = color,
            );
            if (single) {
              final t = _text(chartNumberText(v), 12, Color.lerp(color, c.text, 0.3)!, weight: FontWeight.w700);
              _put(canvas, t, left + bw / 2 - t.width / 2, bar.top - 6 - t.height / 2);
            }
          }
        }
      case ChartType.line || ChartType.area:
        for (final (k, s) in data.series.indexed) {
          final color = displayInk(chartColor(chart, k), brightness);
          final points = [
            for (var i = 0; i < n && i < s.values.length; i++)
              if (s.values[i] case final v?) Offset(p.left + gw * i + gw / 2, sy(v)),
          ];
          if (points.isEmpty) continue;
          if (chart.chartType == ChartType.area && points.length > 1) {
            final area = Path()..moveTo(points.first.dx, base);
            for (final pt in points) {
              area.lineTo(pt.dx, pt.dy);
            }
            area
              ..lineTo(points.last.dx, base)
              ..close();
            canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.18));
          }
          final line = Path()..moveTo(points.first.dx, points.first.dy);
          for (final pt in points.skip(1)) {
            line.lineTo(pt.dx, pt.dy);
          }
          canvas.drawPath(line, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round
            ..color = color);
          for (final pt in points) {
            _dot(canvas, pt, 5, color, c.surface);
          }
        }
      case ChartType.scatter:
        break;
    }
  }
  canvas.drawPath(Path()
    ..moveTo(p.left, p.top - 16)
    ..lineTo(p.left, p.bottom)
    ..lineTo(p.right, p.bottom), axis);
}

/// Where each point is along x on a scatter chart: the first series, or
/// the categories when they're numbers (or their order).
List<double?> _scatterX(ChartData d) {
  if (d.series.length > 1) return d.series.first.values;
  final asNumbers = [for (final c in d.categories) chartNumber(c)];
  return asNumbers.every((v) => v != null) ? asNumbers : [for (var i = 0; i < d.categories.length; i++) i + 1.0];
}

void _dot(Canvas canvas, Offset at, double r, Color color, Color ring) {
  canvas
    ..drawCircle(at, r + 1, Paint()..color = ring)
    ..drawCircle(at, r - 1, Paint()..color = color);
}

// The link between a chart and its source (drawn by the canvas, under the
// ink, not into the page).

/// The ends of the dashed link from [source] to [chart] in page space, and
/// the direction both leave in: from the source's side facing the chart
/// to the chart's side facing it.
(Offset, Offset, Offset) chartLinkEnds(BoxItem source, ChartItem chart) {
  final a = source.extent, b = chart.extent;
  if (b.left >= a.right) return (Offset(a.right, a.center.dy), Offset(b.left, b.center.dy), const Offset(1, 0));
  if (a.left >= b.right) return (Offset(a.left, a.center.dy), Offset(b.right, b.center.dy), const Offset(-1, 0));
  if (b.top >= a.bottom) return (Offset(a.center.dx, a.bottom), Offset(b.center.dx, b.top), const Offset(0, 1));
  return (Offset(a.center.dx, a.top), Offset(b.center.dx, b.bottom), const Offset(0, -1));
}
