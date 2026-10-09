import 'dart:convert';
import 'dart:math' as math;

import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import 'office_model.dart';
import 'ooxml.dart';

// Excel (.xlsx): each visible sheet's cells as Excel shows them, read from
// the cached values (formulas aren't recalculated).

/// Rows and columns read from each sheet; the card shows what fits.
const maxSheetRows = 200;
const maxSheetColumns = 40;

Workbook readXlsx(OoxmlPackage pkg) {
  const book = 'xl/workbook.xml';
  final workbook = pkg.xml(book);
  if (workbook == null) throw const OfficeReadError('This Excel file has no sheets Endless can read.');
  final date1904 = workbook.rootElement.child('workbookPr')?.flag('date1904') ?? false;
  final strings = _sharedStrings(pkg.xml(pkg.relOfType(book, 'sharedStrings') ?? 'xl/sharedStrings.xml'));
  final styles = _Styles.read(pkg.xml(pkg.relOfType(book, 'styles') ?? 'xl/styles.xml'));
  final rels = pkg.rels(book);
  final sheets = <Sheet>[];
  for (final s in workbook.rootElement.child('sheets')?.kids('sheet') ?? const <XmlElement>[]) {
    if (s.attr('state') == 'hidden' || s.attr('state') == 'veryHidden') continue;
    final target = rels[s.relAttr('id')]?.target;
    final bytes = target == null ? null : pkg.bytes(target);
    if (bytes == null) continue;
    final name = s.attr('name') ?? 'Sheet${sheets.length + 1}';
    sheets.add(_readSheet(name, utf8.decode(bytes, allowMalformed: true), strings, styles, date1904));
  }
  if (sheets.isEmpty) throw const OfficeReadError('This Excel file has no sheets Endless can read.');
  return Workbook(sheets);
}

List<String> _sharedStrings(XmlDocument? doc) => [
      for (final si in doc?.rootElement.kids('si') ?? const <XmlElement>[])
        // Plain text, or rich text runs (phonetic guides left out).
        si.child('t')?.innerText ?? si.kids('r').map((r) => r.child('t')?.innerText ?? '').join(),
    ];

/// Number formats and bold fonts by cell style index.
class _Styles {
  _Styles(this.formats, this.bold);

  factory _Styles.read(XmlDocument? doc) {
    final root = doc?.rootElement;
    if (root == null) return _Styles(const [], const []);
    final custom = {
      for (final f in root.child('numFmts')?.kids('numFmt') ?? const <XmlElement>[])
        f.integer('numFmtId') ?? -1: f.attr('formatCode') ?? 'General',
    };
    final fonts = [for (final f in root.child('fonts')?.kids('font') ?? const <XmlElement>[]) f.onOff('b') ?? false];
    final formats = <String>[], bold = <bool>[];
    for (final xf in root.child('cellXfs')?.kids('xf') ?? const <XmlElement>[]) {
      final id = xf.integer('numFmtId') ?? 0;
      formats.add(custom[id] ?? _builtInFormats[id] ?? 'General');
      final font = xf.integer('fontId') ?? 0;
      bold.add(font < fonts.length && fonts[font]);
    }
    return _Styles(formats, bold);
  }

  final List<String> formats;
  final List<bool> bold;

  String format(int style) => style >= 0 && style < formats.length ? formats[style] : 'General';

  bool isBold(int style) => style >= 0 && style < bold.length && bold[style];
}

const _builtInFormats = {
  0: 'General',
  1: '0',
  2: '0.00',
  3: '#,##0',
  4: '#,##0.00',
  9: '0%',
  10: '0.00%',
  11: '0.00E+00',
  12: '# ?/?',
  13: '# ??/??',
  14: 'm/d/yyyy',
  15: 'd-mmm-yy',
  16: 'd-mmm',
  17: 'mmm-yy',
  18: 'h:mm AM/PM',
  19: 'h:mm:ss AM/PM',
  20: 'h:mm',
  21: 'h:mm:ss',
  22: 'm/d/yyyy h:mm',
  37: '#,##0 ;(#,##0)',
  38: '#,##0 ;(#,##0)',
  39: '#,##0.00;(#,##0.00)',
  40: '#,##0.00;(#,##0.00)',
  45: 'mm:ss',
  46: '[h]:mm:ss',
  47: 'mm:ss.0',
  48: '##0.0E+0',
  49: '@',
};

class _Cell {
  _Cell(this.row, this.col, this.text, {this.number = false, this.bold = false});

  final int row;
  final int col;
  final String text;
  final bool number;
  final bool bold;
}

/// "B12" as (11, 1), from 0; or null.
(int, int)? cellRef(String ref) {
  var col = 0, i = 0;
  while (i < ref.length) {
    final c = ref.codeUnitAt(i);
    if (c >= 65 && c <= 90) {
      col = col * 26 + c - 64;
    } else if (c >= 97 && c <= 122) {
      col = col * 26 + c - 96;
    } else {
      break;
    }
    i++;
  }
  final row = int.tryParse(ref.substring(i));
  if (col == 0 || row == null) return null;
  return (row - 1, col - 1);
}

/// The sheet's cells, read as a stream so a huge sheet isn't held whole.
Sheet _readSheet(String name, String xml, List<String> strings, _Styles styles, bool date1904) {
  final widths = <int, double>{};
  var defaultWidth = 64.0;
  final cells = <_Cell>[];
  var totalRows = 0, totalCols = 0;

  // The cell being read.
  int? row, col;
  var type = '', style = 0, reading = false, inline = false, rowIndex = -1;
  final buffer = StringBuffer();

  void finishCell() {
    final r = row, c = col;
    if (r == null || c == null) return;
    final raw = buffer.toString();
    String text;
    var number = false;
    switch (type) {
      case 's':
        final i = int.tryParse(raw.trim());
        text = i != null && i >= 0 && i < strings.length ? strings[i] : '';
      case 'str' || 'inlineStr':
        text = raw;
      case 'b':
        text = raw.trim() == '1' ? 'TRUE' : 'FALSE';
      case 'e':
        text = raw.trim();
      default:
        final v = double.tryParse(raw.trim());
        if (v == null) {
          text = raw.trim();
        } else {
          text = formatNumber(v, styles.format(style), date1904: date1904);
          number = true;
        }
    }
    if (text.isEmpty) return;
    totalRows = math.max(totalRows, r + 1);
    totalCols = math.max(totalCols, c + 1);
    if (r < maxSheetRows && c < maxSheetColumns) {
      cells.add(_Cell(r, c, text, number: number, bold: styles.isBold(style)));
    }
  }

  try {
    for (final e in parseEvents(xml)) {
      switch (e) {
        case XmlStartElementEvent(:final localName, :final attributes, :final isSelfClosing):
          String? a(String n) => attributes.where((x) => x.localName == n).firstOrNull?.value;
          switch (localName) {
            case 'sheetFormatPr':
              final w = double.tryParse(a('defaultColWidth') ?? '');
              final base = double.tryParse(a('baseColWidth') ?? '');
              if (w != null) {
                defaultWidth = _px(w);
              } else if (base != null) {
                defaultWidth = _px(base + 0.71);
              }
            case 'col':
              final lo = int.tryParse(a('min') ?? ''), hi = int.tryParse(a('max') ?? '');
              final w = double.tryParse(a('width') ?? '');
              final hidden = a('hidden') == '1' || a('hidden') == 'true';
              if (lo != null && hi != null) {
                for (var i = lo; i <= math.min(hi, maxSheetColumns); i++) {
                  widths[i - 1] = hidden ? 0 : (w == null ? defaultWidth : _px(w));
                }
              }
            case 'row':
              rowIndex = (int.tryParse(a('r') ?? '') ?? rowIndex + 2) - 1;
              col = null;
            case 'c':
              final ref = a('r');
              final at = ref == null ? null : cellRef(ref);
              row = at?.$1 ?? rowIndex;
              col = at?.$2 ?? (col == null ? 0 : col + 1);
              type = a('t') ?? 'n';
              style = int.tryParse(a('s') ?? '') ?? 0;
              buffer.clear();
              if (isSelfClosing) row = null;
            case 'v':
              reading = !isSelfClosing;
            case 'is':
              inline = !isSelfClosing;
            case 't' when inline:
              reading = !isSelfClosing;
          }
        case XmlTextEvent(:final value) when reading:
          buffer.write(value);
        case XmlCDATAEvent(:final value) when reading:
          buffer.write(value);
        case XmlEndElementEvent(:final localName):
          switch (localName) {
            case 'v' || 't':
              reading = false;
            case 'is':
              inline = false;
            case 'c':
              finishCell();
              row = null;
          }
        default:
          break;
      }
    }
  } on Object {
    // A damaged sheet: show what was read.
  }
  return _sheetFrom(name, cells, widths, defaultWidth, totalRows, totalCols);
}

/// Excel's column width (in characters of its default font) in pixels.
double _px(double chars) => (chars * 7 + 5).roundToDouble();

Sheet _sheetFrom(String name, List<_Cell> cells, Map<int, double> widths, double defaultWidth, int totalRows, int totalCols) {
  var rows = 0, cols = 0;
  for (final c in cells) {
    rows = math.max(rows, c.row + 1);
    cols = math.max(cols, c.col + 1);
  }
  final grid = [for (var r = 0; r < rows; r++) List.filled(cols, '')];
  final numbers = <int>{}, bold = <int>{};
  for (final c in cells) {
    grid[c.row][c.col] = c.text;
    if (c.number) numbers.add(c.row * 1000 + c.col);
    if (c.bold) bold.add(c.row * 1000 + c.col);
  }
  // The first row names the columns when it's all words and the row under
  // it has a number in it, or when it's all bold.
  final firstRow = [
    for (var c = 0; c < cols; c++)
      if (rows > 0 && grid[0][c].isNotEmpty) c,
  ];
  final words = firstRow.isNotEmpty && firstRow.every((c) => !numbers.contains(c));
  final belowHasNumbers = rows > 1 && List.generate(cols, (c) => c).any((c) => numbers.contains(1000 + c));
  final boldRow = firstRow.isNotEmpty && firstRow.every(bold.contains);
  return Sheet(
    name: name,
    cells: grid,
    columnWidths: [for (var c = 0; c < cols; c++) widths[c] ?? defaultWidth],
    bold: bold,
    header: words && (belowHasNumbers || boldRow),
    moreRows: math.max(0, totalRows - rows),
    moreColumns: math.max(0, totalCols - cols),
  );
}

// Number formats.

/// [v] as Excel shows it with the number format [code]: the common cases
/// (decimals, thousands, percent, currency, scientific, dates and times).
String formatNumber(double v, String code, {bool date1904 = false}) {
  final sections = _splitSections(code);
  var section = sections.first;
  var sign = '';
  if (v < 0 && sections.length > 1) {
    // The negative section says how to show it (often in brackets).
    section = sections[1];
    v = -v;
  } else if (v == 0 && sections.length > 2) {
    section = sections[2];
  } else if (v < 0) {
    sign = '-';
    v = -v;
  }
  final plain = section.replaceAll(RegExp(r'\[(?!h+\]|m+\]|s+\])[^\]]*\]'), '').trim();
  if (plain.isEmpty || plain.toLowerCase() == 'general') return sign + _general(v);
  if (plain == '@') return sign + _general(v);
  if (_isDate(plain)) return _date(v, section, date1904);
  return sign + _numeric(v, section);
}

List<String> _splitSections(String code) {
  final out = <String>[];
  var start = 0, quoted = false;
  for (var i = 0; i < code.length; i++) {
    final ch = code[i];
    if (ch == '"') quoted = !quoted;
    if (ch == '\\') {
      i++;
      continue;
    }
    if (ch == ';' && !quoted) {
      out.add(code.substring(start, i));
      start = i + 1;
    }
  }
  out.add(code.substring(start));
  return out;
}

/// What Excel's General format shows: up to 10 significant digits.
String _general(double v) {
  if (v == v.roundToDouble() && v.abs() < 1e11) return v.toInt().toString();
  if (v.abs() >= 1e11 || v.abs() < 1e-9) {
    final parts = v.toStringAsExponential(5).split('e');
    final mantissa = parts[0].replaceFirst(RegExp(r'\.?0+$'), '');
    final power = int.parse(parts[1]);
    return '${mantissa}E${power < 0 ? '-' : '+'}${power.abs().toString().padLeft(2, '0')}';
  }
  var s = v.toStringAsPrecision(10);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s;
}

/// The format's literal text with quotes, escapes and padding taken out.
String _literals(String s) =>
    s.replaceAllMapped(RegExp(r'"([^"]*)"|\\(.)|_.|\*.'), (m) => m.group(1) ?? m.group(2) ?? '');

bool _isDate(String code) {
  final bare = code.replaceAll(RegExp(r'"[^"]*"|\\.'), '').toLowerCase();
  if (bare.contains('0') || bare.contains('#')) return bare.contains('h') || bare.contains('s') && bare.contains(':');
  return RegExp(r'[ydhms]').hasMatch(bare);
}

String _numeric(double v, String code) {
  // Currency like [$€-407] keeps its symbol; other brackets ([Red]) go.
  final currency = RegExp(r'\[\$([^\]\-]*)[^\]]*\]').firstMatch(code)?.group(1) ?? '';
  final bare = code.replaceAll(RegExp(r'\[[^\]]*\]'), '');
  if (bare.contains('%')) v *= 100;
  final digits = RegExp(r'[0#?]+(?:[.,][0#?]+)*(?:E[+-][0#]+)?', caseSensitive: false).firstMatch(bare);
  if (digits == null) return _literals(bare).trim();
  final pattern = digits.group(0)!;
  final decimals = RegExp(r'\.([0#?]+)').firstMatch(pattern)?.group(1) ?? '';
  String body;
  if (pattern.toUpperCase().contains('E')) {
    final parts = v.toStringAsExponential(decimals.length).toUpperCase().split('E');
    final power = int.parse(parts[1]);
    body = '${parts[0]}E${power < 0 ? '-' : '+'}${power.abs().toString().padLeft(2, '0')}';
  } else {
    body = v.toStringAsFixed(decimals.length);
    final parts = body.split('.');
    var whole = parts[0];
    var frac = parts.length > 1 ? parts[1] : '';
    if (pattern.contains(',')) whole = whole.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    // "#" decimals drop trailing zeros; "0" decimals keep them.
    final keep = decimals.contains('0') ? decimals.lastIndexOf('0') + 1 : 0;
    while (frac.length > keep && frac.endsWith('0')) {
      frac = frac.substring(0, frac.length - 1);
    }
    // A pattern with only "#" before the point shows no leading zero.
    if (whole == '0' && !pattern.split('.').first.contains('0') && frac.isNotEmpty) whole = '';
    body = frac.isEmpty ? whole : '$whole.$frac';
  }
  final before = _literals(bare.substring(0, digits.start));
  final after = _literals(bare.substring(digits.end));
  return '$currency$before$body$after'.trim();
}

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// An Excel serial date (days since 1899-12-30, or 1904-01-01) shown with
/// the date format [code].
String _date(double serial, String code, bool date1904) {
  final base = date1904 ? DateTime.utc(1904) : DateTime.utc(1899, 12, 30);
  final d = base.add(Duration(milliseconds: (serial * 86400000).round()));
  final lower = code.toLowerCase();
  final twelve = lower.contains('am/pm') || lower.contains('a/p');
  String two(int n) => n.toString().padLeft(2, '0');

  // An "m" is minutes right after hours or right before seconds.
  bool minutesAt(int at, int run) {
    final before = lower.substring(0, at).replaceAll(RegExp(r'"[^"]*"|[^hms]'), '');
    final after = lower.substring(at + run).replaceAll(RegExp(r'"[^"]*"|[^hms]'), '');
    return before.endsWith('h') || after.startsWith('s');
  }

  final out = StringBuffer();
  var i = 0;
  while (i < code.length) {
    final ch = code[i];
    final low = ch.toLowerCase();
    if (ch == '"') {
      final end = code.indexOf('"', i + 1);
      out.write(code.substring(i + 1, end < 0 ? code.length : end));
      i = end < 0 ? code.length : end + 1;
      continue;
    }
    if (ch == '\\' && i + 1 < code.length) {
      out.write(code[i + 1]);
      i += 2;
      continue;
    }
    if (ch == '_' || ch == '*') {
      i += 2;
      continue;
    }
    if (ch == '[') {
      final end = code.indexOf(']', i);
      final inner = end < 0 ? '' : lower.substring(i + 1, end);
      if (inner.startsWith('h')) out.write((serial * 24).floor());
      if (inner.startsWith('m')) out.write((serial * 1440).floor());
      i = end < 0 ? code.length : end + 1;
      continue;
    }
    if (lower.startsWith('am/pm', i)) {
      out.write(d.hour < 12 ? 'AM' : 'PM');
      i += 5;
      continue;
    }
    if (lower.startsWith('a/p', i)) {
      out.write(d.hour < 12 ? 'A' : 'P');
      i += 3;
      continue;
    }
    var run = 1;
    if ('ymdhs'.contains(low)) {
      while (i + run < code.length && code[i + run].toLowerCase() == low) {
        run++;
      }
    }
    switch (low) {
      case 'y':
        out.write(run <= 2 ? two(d.year % 100) : '${d.year}');
      case 'm':
        if (run <= 2 && minutesAt(i, run)) {
          out.write(run == 2 ? two(d.minute) : '${d.minute}');
        } else {
          out.write(switch (run) {
            1 => '${d.month}',
            2 => two(d.month),
            3 => _monthNames[d.month - 1].substring(0, 3),
            5 => _monthNames[d.month - 1][0],
            _ => _monthNames[d.month - 1],
          });
        }
      case 'd':
        out.write(switch (run) {
          1 => '${d.day}',
          2 => two(d.day),
          3 => _dayNames[d.weekday - 1].substring(0, 3),
          _ => _dayNames[d.weekday - 1],
        });
      case 'h':
        final h = twelve ? (d.hour % 12 == 0 ? 12 : d.hour % 12) : d.hour;
        out.write(run >= 2 ? two(h) : '$h');
      case 's':
        out.write(run >= 2 ? two(d.second) : '${d.second}');
      default:
        out.write(ch);
    }
    i += run;
  }
  return out.toString().trim();
}
