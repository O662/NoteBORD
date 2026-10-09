import 'dart:math' as math;

import 'package:xml/xml.dart';

import 'office_model.dart';
import 'ooxml.dart';
import 'pptx_reader.dart' show roman;

// Word (.docx): the body's paragraphs, lists, tables and pictures, with
// their styles resolved, ready to be laid out into pages. Headers, footers,
// footnotes and comments aren't read.

const _twip = 20.0; // twentieths of a point

WordDoc readDocx(OoxmlPackage pkg) {
  final main = pkg.relOfType('_rels/.rels', 'officeDocument') ?? 'word/document.xml';
  final doc = pkg.xml(main);
  final body = doc?.rootElement.child('body');
  if (body == null) throw const OfficeReadError('This Word file has no text Endless can read.');
  final themePath = pkg.relOfType(main, 'theme');
  final reader = _DocReader(
    pkg,
    main,
    _Styles.read(pkg.xml(pkg.relOfType(main, 'styles') ?? 'word/styles.xml')),
    _Numbering.read(pkg.xml(pkg.relOfType(main, 'numbering') ?? 'word/numbering.xml')),
    Theme.read(themePath == null ? null : pkg.xml(themePath)),
  );
  final blocks = reader.blocks(body);
  final sect = body.child('sectPr');
  final size = sect?.child('pgSz'), margin = sect?.child('pgMar');
  double tw(XmlElement? e, String n, double fallback) => (e?.number(n) ?? fallback * _twip) / _twip;
  final bg = doc!.rootElement.child('background')?.attr('color');
  return WordDoc(
    blocks: blocks,
    pageWidth: tw(size, 'w', 612),
    pageHeight: tw(size, 'h', 792),
    marginLeft: tw(margin, 'left', 72),
    marginTop: tw(margin, 'top', 72),
    marginRight: tw(margin, 'right', 72),
    marginBottom: tw(margin, 'bottom', 72),
    background: bg == null || bg == 'auto' ? null : hexColor(bg),
  );
}

class _Style {
  _Style(this.basedOn, this.pPr, this.rPr);

  final String? basedOn;
  final XmlElement? pPr;
  final XmlElement? rPr;
}

class _Styles {
  _Styles(this.paragraph, this.character, this.defaultParagraph, this.docP, this.docR);

  factory _Styles.read(XmlDocument? doc) {
    final root = doc?.rootElement;
    final paragraph = <String, _Style>{}, character = <String, _Style>{};
    String? fallback;
    for (final s in root?.kids('style') ?? const <XmlElement>[]) {
      final id = s.attr('styleId');
      if (id == null) continue;
      final style = _Style(s.val('basedOn'), s.child('pPr'), s.child('rPr'));
      switch (s.attr('type')) {
        case 'paragraph':
          paragraph[id] = style;
          if (s.flag('default') == true) fallback = id;
        case 'character':
          character[id] = style;
      }
    }
    final defaults = root?.child('docDefaults');
    return _Styles(paragraph, character, fallback, defaults?.at(['pPrDefault', 'pPr']), defaults?.at(['rPrDefault', 'rPr']));
  }

  final Map<String, _Style> paragraph;
  final Map<String, _Style> character;
  final String? defaultParagraph;
  final XmlElement? docP;
  final XmlElement? docR;

  /// [id] and the styles it's based on, nearest first.
  List<_Style> chain(Map<String, _Style> styles, String? id) {
    final out = <_Style>[];
    final seen = <String>{};
    while (id != null && seen.add(id)) {
      final s = styles[id];
      if (s == null) break;
      out.add(s);
      id = s.basedOn;
    }
    return out;
  }
}

class _Level {
  _Level(this.format, this.text, this.start, this.pPr, this.rPr);

  final String format;
  final String text;
  final int start;
  final XmlElement? pPr;
  final XmlElement? rPr;
}

class _Numbering {
  _Numbering(this.abstracts, this.nums, this.overrides);

  factory _Numbering.read(XmlDocument? doc) {
    final root = doc?.rootElement;
    final abstracts = <String, Map<int, _Level>>{};
    for (final a in root?.kids('abstractNum') ?? const <XmlElement>[]) {
      final id = a.attr('abstractNumId');
      if (id == null) continue;
      abstracts[id] = {
        for (final l in a.kids('lvl'))
          l.integer('ilvl') ?? 0: _Level(
            l.val('numFmt') ?? 'decimal',
            l.val('lvlText') ?? '',
            int.tryParse(l.val('start') ?? '') ?? 1,
            l.child('pPr'),
            l.child('rPr'),
          ),
      };
    }
    final nums = <String, String>{}, overrides = <String, Map<int, int>>{};
    for (final n in root?.kids('num') ?? const <XmlElement>[]) {
      final id = n.attr('numId'), abs = n.val('abstractNumId');
      if (id == null || abs == null) continue;
      nums[id] = abs;
      overrides[id] = {
        for (final o in n.kids('lvlOverride'))
          o.integer('ilvl') ?? 0: ?int.tryParse(o.val('startOverride') ?? ''),
      };
    }
    return _Numbering(abstracts, nums, overrides);
  }

  final Map<String, Map<int, _Level>> abstracts;
  final Map<String, String> nums;
  final Map<String, Map<int, int>> overrides;
  final _counters = <String, List<int>>{};

  _Level? level(String numId, int ilvl) => abstracts[nums[numId]]?[ilvl];

  /// The label of the next item at [ilvl] of list [numId] ("2.", "b)", "•").
  String? next(String numId, int ilvl) {
    final lvl = level(numId, ilvl);
    if (lvl == null || lvl.format == 'none') return null;
    final counts = _counters.putIfAbsent(numId, () => List.filled(9, 0));
    final start = overrides[numId]?[ilvl] ?? lvl.start;
    counts[ilvl] = counts[ilvl] == 0 ? start : counts[ilvl] + 1;
    for (var l = ilvl + 1; l < 9; l++) {
      counts[l] = 0;
    }
    if (lvl.format == 'bullet') return drawableText(lvl.text.isEmpty ? '•' : lvl.text);
    return lvl.text.replaceAllMapped(RegExp(r'%(\d)'), (m) {
      final l = int.parse(m.group(1)!) - 1;
      final value = l >= 0 && l < 9 ? math.max(counts[l], level(numId, l)?.start ?? 1) : 0;
      return _format(level(numId, l)?.format ?? 'decimal', value);
    });
  }

  static String _format(String fmt, int n) => switch (fmt) {
        'lowerLetter' => String.fromCharCode(97 + (n - 1) % 26) * ((n - 1) ~/ 26 + 1),
        'upperLetter' => String.fromCharCode(65 + (n - 1) % 26) * ((n - 1) ~/ 26 + 1),
        'lowerRoman' => roman(n).toLowerCase(),
        'upperRoman' => roman(n),
        'decimalZero' => n.toString().padLeft(2, '0'),
        _ => '$n',
      };
}

const _highlights = {
  'yellow': 0xFFFFFF00,
  'green': 0xFF00FF00,
  'cyan': 0xFF00FFFF,
  'magenta': 0xFFFF00FF,
  'blue': 0xFF0000FF,
  'red': 0xFFFF0000,
  'darkBlue': 0xFF000080,
  'darkCyan': 0xFF008080,
  'darkGreen': 0xFF008000,
  'darkMagenta': 0xFF800080,
  'darkRed': 0xFF800000,
  'darkYellow': 0xFF808000,
  'darkGray': 0xFF808080,
  'lightGray': 0xFFC0C0C0,
  'black': 0xFF000000,
};

class _DocReader {
  _DocReader(this.pkg, this.part, this.styles, this.numbering, this.theme);

  final OoxmlPackage pkg;
  final String part;
  final _Styles styles;
  final _Numbering numbering;
  final Theme theme;

  List<WordBlock> blocks(XmlElement container) {
    final out = <WordBlock>[];
    for (final e in container.open(preferChoice: true)) {
      try {
        switch (e.name.local) {
          case 'p':
            _paragraph(e, out);
          case 'tbl':
            out.add(_table(e));
          case 'sdt':
            if (e.child('sdtContent') case final c?) out.addAll(blocks(c));
          case 'customXml':
            out.addAll(blocks(e));
        }
      } on Object {
        // Something this version can't read is left out; the rest still shows.
      }
    }
    return out;
  }

  /// [get] of the first of [chain] that says.
  static T? _first<T>(List<XmlElement?> chain, T? Function(XmlElement e) get) {
    for (final e in chain) {
      if (e == null) continue;
      final v = get(e);
      if (v != null) return v;
    }
    return null;
  }

  List<XmlElement?> _pChain(XmlElement? pPr, {XmlElement? list}) {
    final id = pPr?.val('pStyle') ?? styles.defaultParagraph;
    return [pPr, list, for (final s in styles.chain(styles.paragraph, id)) s.pPr, styles.docP];
  }

  List<XmlElement?> _rChain(XmlElement? rPr, XmlElement? pPr) {
    final pid = pPr?.val('pStyle') ?? styles.defaultParagraph;
    return [
      rPr,
      for (final s in styles.chain(styles.character, rPr?.val('rStyle'))) s.rPr,
      for (final s in styles.chain(styles.paragraph, pid)) s.rPr,
      styles.docR,
    ];
  }

  ORun _run(String text, List<XmlElement?> chain) {
    final caps = _first(chain, (e) => e.onOff('caps')) ?? false;
    final vert = _first(chain, (e) => e.val('vertAlign'));
    final color = _first(chain, (e) => e.val('color'));
    final hl = _first(chain, (e) => e.val('highlight'));
    final shd = _first(chain, (e) => e.child('shd')?.attr('fill'));
    final fonts = _first(chain, (e) => e.child('rFonts'));
    final face = fonts?.attr('ascii') ?? theme.font(fonts?.attr('asciiTheme') ?? 'minor');
    final size = (_first(chain, (e) => double.tryParse(e.val('sz') ?? '')) ?? 20) / 2;
    final small = vert == 'superscript' || vert == 'subscript';
    return ORun(
      drawableText(caps ? text.toUpperCase() : text),
      size: small ? size * 0.65 : size,
      bold: _first(chain, (e) => e.onOff('b')) ?? false,
      italic: _first(chain, (e) => e.onOff('i')) ?? false,
      underline: (_first(chain, (e) => e.val('u')) ?? 'none') != 'none',
      strike: (_first(chain, (e) => e.onOff('strike')) ?? false) || (_first(chain, (e) => e.onOff('dstrike')) ?? false),
      color: color == null || color == 'auto' ? 0xFF000000 : hexColor(color) ?? 0xFF000000,
      serif: isSerifFont(face),
      highlight: hl != null && hl != 'none' ? _highlights[hl] : (shd == null || shd == 'auto' ? null : hexColor(shd)),
      raised: vert == 'superscript',
    );
  }

  /// A paragraph's text, split at page breaks and pictures.
  void _paragraph(XmlElement p, List<WordBlock> out) {
    final pPr = p.child('pPr');
    final numId = pPr?.at(['numPr', 'numId'])?.attr('val') ?? _styleNum(pPr, 'numId');
    final ilvl = int.tryParse(pPr?.at(['numPr', 'ilvl'])?.attr('val') ?? _styleNum(pPr, 'ilvl') ?? '') ?? 0;
    final listLevel = numId == null || numId == '0' ? null : numbering.level(numId, ilvl);
    final chain = _pChain(pPr, list: listLevel?.pPr);
    final runs = <ORun>[];
    final pending = <WordBlock>[];
    var label = listLevel == null ? null : numbering.next(numId!, ilvl);
    var breakBefore = _first(chain, (e) => e.onOff('pageBreakBefore')) ?? false;
    // Fields being read: true while in a field's instructions (hidden),
    // false once its result (shown) starts.
    final fields = <bool>[];

    void flush({bool always = false}) {
      if (runs.isEmpty && !always && pending.isNotEmpty) {
        out.addAll(pending);
        pending.clear();
        return;
      }
      if (runs.isNotEmpty || always) {
        out.add(WordParagraph(_para(runs.toList(), chain, pPr, label, listLevel), pageBreakBefore: breakBefore));
        label = null;
        breakBefore = false;
      }
      out.addAll(pending);
      pending.clear();
      runs.clear();
    }

    void walk(XmlElement parent) {
      for (final e in parent.open(preferChoice: true)) {
        switch (e.name.local) {
          case 'r':
            final rChain = _rChain(e.child('rPr'), pPr);
            if (_first(rChain, (x) => x.onOff('vanish')) ?? false) continue;
            final text = StringBuffer();
            void addText() {
              if (text.isEmpty) return;
              runs.add(_run(text.toString(), rChain));
              text.clear();
            }

            for (final c in e.open(preferChoice: true)) {
              switch (c.name.local) {
                case 'fldChar':
                  switch (c.attr('fldCharType')) {
                    case 'begin':
                      fields.add(true);
                    case 'separate' when fields.isNotEmpty:
                      fields.last = false;
                    case 'end' when fields.isNotEmpty:
                      fields.removeLast();
                  }
                case 't' when !fields.contains(true):
                  text.write(c.innerText);
                case 'tab' when !fields.contains(true):
                  text.write('    ');
                case 'br' || 'cr':
                  if (c.attr('type') == 'page') {
                    addText();
                    flush();
                    out.add(const WordPageBreak());
                  } else {
                    text.write('\n');
                  }
                case 'noBreakHyphen':
                  text.write('-');
                case 'sym':
                  text.write('•');
                case 'drawing':
                  addText();
                  _drawing(c, pending, chain);
                case 'pict':
                  addText();
                  _vml(c, pending);
              }
            }
            addText();
          case 'hyperlink' || 'ins' || 'smartTag' || 'fldSimple' || 'customXml' || 'moveTo' || 'dir' || 'bdo':
            walk(e);
          case 'sdt':
            if (e.child('sdtContent') case final c?) walk(c);
        }
      }
    }

    walk(p);
    if (runs.isEmpty && pending.isEmpty) {
      // An empty paragraph still takes a line.
      flush(always: true);
    } else {
      flush();
    }
  }

  /// A list number given by the paragraph's style rather than the paragraph.
  String? _styleNum(XmlElement? pPr, String what) {
    for (final s in styles.chain(styles.paragraph, pPr?.val('pStyle') ?? styles.defaultParagraph)) {
      final v = s.pPr?.at(['numPr', what])?.attr('val');
      if (v != null) return v;
    }
    return null;
  }

  OPara _para(List<ORun> runs, List<XmlElement?> chain, XmlElement? pPr, String? label, _Level? list) {
    final jc = _first(chain, (e) => e.val('jc'));
    final spacing = [for (final e in chain) e?.child('spacing')];
    double? sp(String n) => _first(spacing, (e) => e.number(n));
    final ind = [for (final e in chain) e?.child('ind')];
    double tw(String a, [String? b]) => (_first(ind, (e) => e.number(a) ?? (b == null ? null : e.number(b))) ?? 0) / _twip;
    final left = tw('left', 'start'), right = tw('right', 'end');
    final hanging = tw('hanging');
    final markChain = _rChain(pPr?.child('rPr'), pPr);
    final size = (_first(markChain, (e) => double.tryParse(e.val('sz') ?? '')) ?? 20) / 2;
    final first = runs.where((r) => r.text.trim().isNotEmpty).firstOrNull;
    final lineSize = first?.size ?? size;
    final line = sp('line');
    final rule = _first(spacing, (e) => e.attr('lineRule')) ?? 'auto';
    final lineHeight = line == null
        ? 1.17
        : rule == 'auto'
            ? 1.17 * line / 240
            : math.max(line / _twip / math.max(lineSize, 1), rule == 'atLeast' ? 1.17 : 0.5);
    final before = (_first(spacing, (e) => e.flag('beforeAutospacing')) ?? false) ? 14.0 : (sp('before') ?? 0) / _twip;
    final after = (_first(spacing, (e) => e.flag('afterAutospacing')) ?? false) ? 14.0 : (sp('after') ?? 0) / _twip;
    final labelColor = label == null ? null : list?.rPr?.val('color');
    final bulletColor = labelColor == null ? null : hexColor(labelColor);
    return OPara(
      runs,
      align: switch (jc) {
        'center' => 'ctr',
        'right' || 'end' => 'r',
        'both' || 'distribute' => 'just',
        _ => 'l',
      },
      indent: math.max(0, left),
      rightIndent: math.max(0, right),
      bullet: label,
      bulletIndent: math.max(0, left - hanging),
      bulletColor: bulletColor,
      spaceBefore: before,
      spaceAfter: after,
      lineHeight: lineHeight,
      emptySize: size,
    );
  }

  void _drawing(XmlElement drawing, List<WordBlock> out, List<XmlElement?> chain) {
    final frame = drawing.child('inline') ?? drawing.child('anchor');
    if (frame == null) return;
    final ext = frame.child('extent');
    final w = (ext?.number('cx') ?? 0) / emuPerPoint, h = (ext?.number('cy') ?? 0) / emuPerPoint;
    final data = frame.at(['graphic', 'graphicData']);
    if (data == null) return;
    final blip = data.descendantElements.where((e) => e.name.local == 'blip').firstOrNull;
    final media = _media(blip?.relAttr('embed'));
    if (media != null) {
      final jc = _first(chain, (e) => e.val('jc'));
      out.add(WordPicture(media, w, h, align: jc == 'center' ? 'ctr' : (jc == 'right' || jc == 'end' ? 'r' : 'l')));
      return;
    }
    // A text box: its paragraphs, in the flow.
    final box = data.descendantElements.where((e) => e.name.local == 'txbxContent').firstOrNull;
    if (box != null) {
      out.addAll(blocks(box));
      return;
    }
    if ((data.attr('uri') ?? '').contains('chart')) out.add(WordStandIn('Chart', w, h));
  }

  /// An old-style (VML) picture.
  void _vml(XmlElement pict, List<WordBlock> out) {
    final image = pict.descendantElements.where((e) => e.name.local == 'imagedata').firstOrNull;
    final media = _media(image?.relAttr('id'));
    if (media == null) return;
    final shape = image!.parentElement;
    final style = shape?.attr('style') ?? '';
    double dim(String name) {
      final m = RegExp('$name:\\s*([\\d.]+)(pt|in|px)?').firstMatch(style);
      final v = double.tryParse(m?.group(1) ?? '') ?? 100;
      return switch (m?.group(2)) { 'in' => v * 72, 'px' => v * 0.75, _ => v };
    }

    out.add(WordPicture(media, dim('width'), dim('height')));
  }

  String? _media(String? id) {
    if (id == null) return null;
    final target = pkg.rels(part)[id]?.target;
    return target == null || target.isEmpty || !pkg.has(target) ? null : target;
  }

  WordTable _table(XmlElement tbl) {
    final columns = [
      for (final c in tbl.child('tblGrid')?.kids('gridCol') ?? const <XmlElement>[]) (c.number('w') ?? 0) / _twip,
    ];
    final rows = <WordRow>[];
    for (final tr in tbl.kids('tr')) {
      final cells = <WordCell>[];
      for (final tc in tr.open(preferChoice: true).where((e) => e.name.local == 'tc')) {
        final pr = tc.child('tcPr');
        final merge = pr?.child('vMerge');
        final fill = pr?.child('shd')?.attr('fill');
        // Paragraphs, with any table inside flattened to its paragraphs.
        final paragraphs = <OPara>[];
        for (final b in blocks(tc)) {
          switch (b) {
            case WordParagraph(:final para):
              paragraphs.add(para);
            case WordTable t:
              for (final r in t.rows) {
                for (final c in r.cells) {
                  paragraphs.addAll(c.paragraphs);
                }
              }
            default:
              break;
          }
        }
        cells.add(WordCell(
          paragraphs,
          span: int.tryParse(pr?.val('gridSpan') ?? '') ?? 1,
          fill: fill == null || fill == 'auto' ? null : hexColor(fill),
          hidden: merge != null && merge.attr('val') != 'restart',
        ));
      }
      rows.add(WordRow(cells));
    }
    if (columns.isEmpty && rows.isNotEmpty) {
      final n = rows.map((r) => r.cells.fold<int>(0, (s, c) => s + c.span)).reduce(math.max);
      return WordTable(List.filled(n, 468 / math.max(n, 1)), rows);
    }
    return WordTable(columns, rows);
  }
}
