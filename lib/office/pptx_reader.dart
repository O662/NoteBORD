import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'office_model.dart';
import 'ooxml.dart';

// PowerPoint (.pptx): each slide as shapes, pictures and tables in slide
// points. Placeholders take their place and text styles from the slide's
// layout and master, as PowerPoint does; shapes on the master and layout
// are drawn behind the slide's own.

Deck readPptx(OoxmlPackage pkg) {
  const pres = 'ppt/presentation.xml';
  final doc = pkg.xml(pres);
  if (doc == null) throw const OfficeReadError('This PowerPoint file has no slides Endless can read.');
  final root = doc.rootElement;
  final size = root.child('sldSz');
  final width = (size?.number('cx') ?? 9144000) / emuPerPoint;
  final height = (size?.number('cy') ?? 6858000) / emuPerPoint;
  final reader = _DeckReader(pkg, _ListStyle.read(root.child('defaultTextStyle')));
  final rels = pkg.rels(pres);
  final slides = <Slide>[];
  for (final id in root.child('sldIdLst')?.kids('sldId') ?? const <XmlElement>[]) {
    final path = rels[id.relAttr('id')]?.target;
    if (path == null || !pkg.has(path)) continue;
    if (pkg.xml(path)?.rootElement.attr('show') == '0') continue; // hidden slide
    slides.add(reader.slide(path, slides.length + 1, id: id.integer('id')));
  }
  if (slides.isEmpty) throw const OfficeReadError('This PowerPoint file has no slides Endless can read.');
  return Deck(width, height, slides);
}

// Text styles.

enum _BulletKind { none, char, number }

class _Bullet {
  const _Bullet(this.kind, {this.char = '•', this.scheme = 'arabicPeriod', this.start = 1});

  final _BulletKind kind;
  final String char;
  final String scheme;
  final int start;
}

/// One level of a list style, or a paragraph's or run's own properties.
/// Unset fields fall through to the next style down.
class _Level {
  const _Level({
    this.size,
    this.bold,
    this.italic,
    this.underline,
    this.strike,
    this.color,
    this.font,
    this.align,
    this.marL,
    this.indent,
    this.bullet,
    this.bulletColor,
    this.spcBefPts,
    this.spcBefPct,
    this.spcAftPts,
    this.spcAftPct,
    this.lnSpcPct,
    this.lnSpcPts,
    this.caps,
  });

  final double? size;
  final bool? bold;
  final bool? italic;
  final bool? underline;
  final bool? strike;
  final int? color;
  final String? font;
  final String? align;
  final double? marL;
  final double? indent;
  final _Bullet? bullet;
  final int? bulletColor;
  final double? spcBefPts;
  final double? spcBefPct;
  final double? spcAftPts;
  final double? spcAftPct;
  final double? lnSpcPct;
  final double? lnSpcPts;
  final bool? caps;

  static const empty = _Level();

  /// This, with what it leaves unset taken from [under].
  _Level over(_Level under) => _Level(
        size: size ?? under.size,
        bold: bold ?? under.bold,
        italic: italic ?? under.italic,
        underline: underline ?? under.underline,
        strike: strike ?? under.strike,
        color: color ?? under.color,
        font: font ?? under.font,
        align: align ?? under.align,
        marL: marL ?? under.marL,
        indent: indent ?? under.indent,
        bullet: bullet ?? under.bullet,
        bulletColor: bulletColor ?? under.bulletColor,
        spcBefPts: spcBefPts ?? (spcBefPct == null ? under.spcBefPts : null),
        spcBefPct: spcBefPct ?? (spcBefPts == null ? under.spcBefPct : null),
        spcAftPts: spcAftPts ?? (spcAftPct == null ? under.spcAftPts : null),
        spcAftPct: spcAftPct ?? (spcAftPts == null ? under.spcAftPct : null),
        lnSpcPct: lnSpcPct ?? (lnSpcPts == null ? under.lnSpcPct : null),
        lnSpcPts: lnSpcPts ?? (lnSpcPct == null ? under.lnSpcPts : null),
        caps: caps ?? under.caps,
      );

  /// A run's properties (`a:rPr`, `a:defRPr`).
  static _Level run(XmlElement? r, _Ctx ctx) {
    if (r == null) return empty;
    final u = r.attr('u');
    final strike = r.attr('strike');
    final link = r.child('hlinkClick') != null;
    final fill = r.child('solidFill');
    return _Level(
      size: r.number('sz') == null ? null : r.number('sz')! / 100,
      bold: r.flag('b'),
      italic: r.flag('i'),
      underline: u == null ? (link ? true : null) : u != 'none',
      strike: strike == null ? null : strike != 'noStrike',
      color: fill != null ? readColor(fill, ctx.theme, map: ctx.map) : (link ? ctx.theme.colors['hlink'] : null),
      font: r.child('latin')?.attr('typeface'),
      caps: r.attr('cap') == null ? null : r.attr('cap') == 'all',
    );
  }

  /// A paragraph's properties (`a:pPr`, `a:lvl1pPr`…), with its default
  /// run properties.
  static _Level para(XmlElement? e, _Ctx ctx) {
    if (e == null) return empty;
    double? pts(XmlElement? spacing) => spacing?.child('spcPts')?.number('val') == null ? null : spacing!.child('spcPts')!.number('val')! / 100;
    double? pct(XmlElement? spacing) => spacing?.child('spcPct')?.number('val') == null ? null : spacing!.child('spcPct')!.number('val')! / 100000;
    _Bullet? bullet;
    if (e.child('buNone') != null) {
      bullet = const _Bullet(_BulletKind.none);
    } else if (e.child('buChar') case final ch?) {
      bullet = _Bullet(_BulletKind.char, char: drawableText(ch.attr('char') ?? '•'));
    } else if (e.child('buAutoNum') case final n?) {
      bullet = _Bullet(_BulletKind.number, scheme: n.attr('type') ?? 'arabicPeriod', start: n.integer('startAt') ?? 1);
    }
    final run = _Level.run(e.child('defRPr'), ctx);
    final marL = e.number('marL'), indent = e.number('indent');
    return _Level(
      align: e.attr('algn'),
      marL: marL == null ? null : marL / emuPerPoint,
      indent: indent == null ? null : indent / emuPerPoint,
      bullet: bullet,
      bulletColor: readColor(e.child('buClr'), ctx.theme, map: ctx.map),
      spcBefPts: pts(e.child('spcBef')),
      spcBefPct: pct(e.child('spcBef')),
      spcAftPts: pts(e.child('spcAft')),
      spcAftPct: pct(e.child('spcAft')),
      lnSpcPct: pct(e.child('lnSpc')),
      lnSpcPts: pts(e.child('lnSpc')),
    ).over(run);
  }
}

/// A list style: levels 1 to 9, plus `defPPr` under them all.
class _ListStyle {
  const _ListStyle(this.levels, this.base);

  static _ListStyle read(XmlElement? e, [_Ctx ctx = _Ctx.plain]) {
    if (e == null) return none;
    return _ListStyle({
      for (var l = 1; l <= 9; l++)
        if (e.child('lvl${l}pPr') case final lvl?) l: _Level.para(lvl, ctx),
    }, _Level.para(e.child('defPPr'), ctx));
  }

  final Map<int, _Level> levels;
  final _Level base;

  static const none = _ListStyle({}, _Level.empty);

  _Level at(int level) => (levels[level] ?? _Level.empty).over(base);
}

/// Colors and fonts in force: the master's theme and color map.
class _Ctx {
  const _Ctx(this.theme, this.map);

  final Theme theme;
  final ColorMap map;

  static const plain = _Ctx(Theme(), defaultColorMap);
}

// Layouts and masters.

/// A placeholder on a layout or master: where it is and how its text looks.
class _Placeholder {
  _Placeholder(this.type, this.idx, this.frame, this.list, this.body, this.spPr);

  final String type;
  final String? idx;
  final ORect? frame;
  final _ListStyle list;
  final XmlElement? body;
  final XmlElement? spPr;
}

class _Template {
  _Template({
    required this.path,
    required this.ctx,
    required this.placeholders,
    required this.shapes,
    this.background,
    this.showMasterShapes = true,
    this.title = _ListStyle.none,
    this.body = _ListStyle.none,
    this.other = _ListStyle.none,
  });

  final String path;
  final _Ctx ctx;
  final List<_Placeholder> placeholders;

  /// Shapes that aren't placeholders: drawn on every slide using this.
  final List<XmlElement> shapes;
  final XmlElement? background;
  final bool showMasterShapes;

  /// The master's text styles.
  final _ListStyle title;
  final _ListStyle body;
  final _ListStyle other;

  _Placeholder? byIdx(String? idx) => idx == null ? null : placeholders.where((p) => p.idx == idx).firstOrNull;

  _Placeholder? byType(String type) => placeholders.where((p) => _sameType(p.type, type)).firstOrNull;
}

/// Placeholder types that stand for each other when looking one up.
bool _sameType(String a, String b) {
  String norm(String t) => switch (t) {
        'ctrTitle' => 'title',
        'subTitle' || 'obj' || '' => 'body',
        _ => t,
      };
  return norm(a) == norm(b);
}

/// A placeholder's type ('' when it has none) and index, or null.
(String, String?)? _placeholderOf(XmlElement shape) {
  final nv = shape.childElements.where((e) => e.name.local.startsWith('nv')).firstOrNull;
  final ph = nv?.child('nvPr')?.child('ph');
  if (ph == null) return null;
  return (ph.attr('type') ?? '', ph.attr('idx'));
}

class _DeckReader {
  _DeckReader(this.pkg, this.defaults);

  final OoxmlPackage pkg;
  final _ListStyle defaults;
  final _templates = <String, _Template>{};

  _Template _template(String path, {_Template? master}) => _templates.putIfAbsent(path, () {
        final root = pkg.xml(path)?.rootElement;
        final themePath = master == null ? pkg.relOfType(path, 'theme') : null;
        final theme = master?.ctx.theme ?? Theme.read(themePath == null ? null : pkg.xml(themePath));
        var map = master?.ctx.map ?? defaultColorMap;
        if (root?.child('clrMap') case final m?) {
          map = {for (final a in m.attributes) a.name.local: a.value};
        }
        if (root?.child('clrMapOvr')?.child('overrideClrMapping') case final m?) {
          map = {for (final a in m.attributes) a.name.local: a.value};
        }
        final ctx = _Ctx(theme, map);
        final tree = root?.at(['cSld', 'spTree']);
        final placeholders = <_Placeholder>[];
        final shapes = <XmlElement>[];
        for (final s in tree?.open() ?? const <XmlElement>[]) {
          final ph = _placeholderOf(s);
          if (ph == null) {
            if (const {'sp', 'pic', 'grpSp', 'cxnSp', 'graphicFrame'}.contains(s.name.local)) shapes.add(s);
            continue;
          }
          final spPr = s.child('spPr');
          placeholders.add(_Placeholder(
            ph.$1,
            ph.$2,
            _frame(spPr?.child('xfrm')),
            _ListStyle.read(s.at(['txBody', 'lstStyle']), ctx),
            s.at(['txBody', 'bodyPr']),
            spPr,
          ));
        }
        final styles = root?.child('txStyles');
        return _Template(
          path: path,
          ctx: ctx,
          placeholders: placeholders,
          shapes: shapes,
          background: root?.at(['cSld', 'bg']),
          showMasterShapes: root?.flag('showMasterSp') ?? true,
          title: _ListStyle.read(styles?.child('titleStyle'), ctx),
          body: _ListStyle.read(styles?.child('bodyStyle'), ctx),
          other: _ListStyle.read(styles?.child('otherStyle'), ctx),
        );
      });

  Slide slide(String path, int number, {int? id}) {
    final layoutPath = pkg.relOfType(path, 'slideLayout');
    final masterPath = layoutPath == null ? null : pkg.relOfType(layoutPath, 'slideMaster');
    final master = masterPath == null ? null : _template(masterPath);
    final layout = layoutPath == null ? null : _template(layoutPath, master: master);
    final own = _template(path, master: master);
    final ctx = own.ctx;
    final slide = _SlideReader(this, path, number, ctx, layout, master);
    final nodes = <SlideNode>[];
    final showMaster = own.showMasterShapes && (layout?.showMasterShapes ?? true);
    if (master != null && showMaster) {
      nodes.addAll(_SlideReader(this, master.path, number, master.ctx, null, master, decoration: true).nodes(master.shapes));
    }
    if (layout != null && own.showMasterShapes) {
      nodes.addAll(_SlideReader(this, layout.path, number, layout.ctx, null, master, decoration: true).nodes(layout.shapes));
    }
    final tree = pkg.xml(path)?.rootElement.at(['cSld', 'spTree']);
    nodes.addAll(slide.nodes(tree?.open().toList() ?? const []));
    final bg = own.background ?? layout?.background ?? master?.background;
    final bgOwner = own.background != null ? path : (layout?.background != null ? layout!.path : master?.path ?? path);
    return Slide(nodes, background: _background(bg, bgOwner, ctx) ?? const OFill(color: 0xFFFFFFFF), id: id);
  }

  OFill? _background(XmlElement? bg, String owner, _Ctx ctx) {
    if (bg == null) return null;
    if (bg.child('bgPr') case final pr?) return _fill(pr, owner, ctx);
    if (bg.child('bgRef') case final ref?) {
      final color = readColor(ref, ctx.theme, map: ctx.map);
      return color == null ? null : OFill(color: color);
    }
    return null;
  }

  /// The fill in [pr] (`spPr`, `bgPr`, `tcPr`): solid, the first stop of a
  /// gradient, a picture, or a pattern's color. Null when it says nothing;
  /// a fill with no color when it says no fill.
  OFill? _fill(XmlElement pr, String owner, _Ctx ctx, {int? placeholder}) {
    for (final e in pr.childElements) {
      switch (e.name.local) {
        case 'noFill':
          return const OFill();
        case 'solidFill':
          return OFill(color: readColor(e, ctx.theme, map: ctx.map, placeholder: placeholder));
        case 'gradFill':
          final stops = e.child('gsLst')?.kids('gs').toList() ?? const [];
          if (stops.isEmpty) return const OFill();
          // The middle of the gradient stands in for it.
          final mid = stops[stops.length ~/ 2];
          return OFill(color: readColor(mid, ctx.theme, map: ctx.map, placeholder: placeholder));
        case 'blipFill':
          final media = _media(owner, e.child('blip'));
          return media == null ? const OFill() : OFill(media: media);
        case 'pattFill':
          return OFill(color: readColor(e.child('fgClr'), ctx.theme, map: ctx.map, placeholder: placeholder));
      }
    }
    return null;
  }

  String? _media(String owner, XmlElement? blip) {
    final id = blip?.relAttr('embed');
    if (id == null) return null;
    final target = pkg.rels(owner)[id]?.target;
    return target == null || target.isEmpty || !pkg.has(target) ? null : target;
  }
}

/// How a group maps its children's coordinates onto the slide.
class _Transform {
  const _Transform(this.sx, this.sy, this.tx, this.ty);

  final double sx;
  final double sy;
  final double tx;
  final double ty;

  static const identity = _Transform(1, 1, 0, 0);

  ORect apply(ORect r) => ORect(tx + r.x * sx, ty + r.y * sy, r.w * sx, r.h * sy);

  _Transform then(_Transform inner) => _Transform(sx * inner.sx, sy * inner.sy, tx + inner.tx * sx, ty + inner.ty * sy);
}

ORect? _frame(XmlElement? xfrm) {
  final off = xfrm?.child('off'), ext = xfrm?.child('ext');
  if (off == null || ext == null) return null;
  return ORect(
    (off.number('x') ?? 0) / emuPerPoint,
    (off.number('y') ?? 0) / emuPerPoint,
    (ext.number('cx') ?? 0) / emuPerPoint,
    (ext.number('cy') ?? 0) / emuPerPoint,
  );
}

class _SlideReader {
  _SlideReader(this.deck, this.path, this.number, this.ctx, this.layout, this.master, {this.decoration = false});

  final _DeckReader deck;
  final String path;
  final int number;
  final _Ctx ctx;
  final _Template? layout;
  final _Template? master;

  /// Reading the master's or layout's own shapes, drawn behind the slide.
  final bool decoration;

  /// Numbered lists count on from paragraph to paragraph.
  final _numbers = <int, int>{};

  List<SlideNode> nodes(List<XmlElement> shapes, [_Transform t = _Transform.identity]) {
    final out = <SlideNode>[];
    for (final s in shapes) {
      try {
        _node(s, t, out);
      } on Object {
        // A shape this version can't read is left out; the rest still shows.
      }
    }
    return out;
  }

  void _node(XmlElement s, _Transform t, List<SlideNode> out) {
    switch (s.name.local) {
      case 'sp' || 'cxnSp':
        if (_shape(s, t) case final shape?) out.add(shape);
      case 'pic':
        if (_picture(s, t) case final pic?) out.add(pic);
      case 'grpSp':
        final xfrm = s.at(['grpSpPr', 'xfrm']);
        final frame = _frame(xfrm);
        final chOff = xfrm?.child('chOff'), chExt = xfrm?.child('chExt');
        var inner = _Transform.identity;
        if (frame != null && chOff != null && chExt != null) {
          final cw = (chExt.number('cx') ?? 0) / emuPerPoint, ch = (chExt.number('cy') ?? 0) / emuPerPoint;
          final sx = cw == 0 ? 1.0 : frame.w / cw, sy = ch == 0 ? 1.0 : frame.h / ch;
          inner = _Transform(sx, sy, frame.x - (chOff.number('x') ?? 0) / emuPerPoint * sx, frame.y - (chOff.number('y') ?? 0) / emuPerPoint * sy);
        }
        out.addAll(nodes(s.open().toList(), t.then(inner)));
      case 'graphicFrame':
        _graphicFrame(s, t, out);
      case 'contentPart':
        break;
    }
  }

  ({ORect frame, double rotation, bool flipH, bool flipV}) _place(XmlElement? xfrm, ORect fallback, _Transform t) {
    final frame = t.apply(_frame(xfrm) ?? fallback);
    return (
      frame: frame,
      rotation: (xfrm?.number('rot') ?? 0) / 60000,
      flipH: xfrm?.flag('flipH') ?? false,
      flipV: xfrm?.flag('flipV') ?? false,
    );
  }

  SlideShape? _shape(XmlElement s, _Transform t) {
    final ph = _placeholderOf(s);
    final layoutPh = ph == null ? null : (layout?.byIdx(ph.$2) ?? layout?.byType(ph.$1));
    final masterPh = ph == null ? null : (master?.byType(ph.$1) ?? (layoutPh == null ? null : master?.byType(layoutPh.type)));
    final spPr = s.child('spPr');
    final frame = _frame(spPr?.child('xfrm')) ?? layoutPh?.frame ?? masterPh?.frame;
    if (frame == null) return null;
    final place = _place(spPr?.child('xfrm'), frame, t);
    final style = s.child('style');

    // Fill and line: the shape's own, else its style's references.
    final fillRef = style?.child('fillRef');
    var fill = spPr == null ? null : deck._fill(spPr, path, ctx);
    fill ??= layoutPh?.spPr == null ? null : deck._fill(layoutPh!.spPr!, layout!.path, ctx);
    if (fill == null && fillRef != null && (fillRef.integer('idx') ?? 0) > 0) {
      fill = OFill(color: readColor(fillRef, ctx.theme, map: ctx.map));
    }
    int? line;
    var lineWidth = 0.75;
    final ln = spPr?.child('ln');
    final lnRef = style?.child('lnRef');
    if (ln != null && ln.child('noFill') != null) {
      line = null;
    } else if (ln?.child('solidFill') case final f?) {
      line = readColor(f, ctx.theme, map: ctx.map);
    } else if (ln?.child('gradFill') case final g?) {
      line = readColor(g.child('gsLst')?.kids('gs').firstOrNull, ctx.theme, map: ctx.map);
    } else if (lnRef != null && (lnRef.integer('idx') ?? 0) > 0) {
      line = readColor(lnRef, ctx.theme, map: ctx.map);
    }
    if (ln?.number('w') case final w?) lineWidth = w / emuPerPoint;

    final geom = spPr?.child('prstGeom')?.attr('prst') ?? (spPr?.child('custGeom') != null ? 'custom' : 'rect');
    final connector = s.name.local == 'cxnSp' || geom == 'line' || geom.contains('Connector');
    var heads = 0;
    if (ln?.child('headEnd')?.attr('type') case final h? when h != 'none') heads |= 1;
    if (ln?.child('tailEnd')?.attr('type') case final h? when h != 'none') heads |= 2;

    final fontColor = readColor(style?.child('fontRef'), ctx.theme, map: ctx.map);
    final text = s.child('txBody') == null ? null : _text(s.child('txBody')!, ph, layoutPh, masterPh, fontColor);
    // An empty placeholder shows nothing on a slide (its prompt text is
    // only for editing).
    final hasText = text != null && text.paragraphs.any((p) => p.text.trim().isNotEmpty);
    final visibleFill = fill?.color != null || fill?.media != null;
    if (ph != null && !hasText && !visibleFill && line == null) return null;
    if (decoration && ph != null) return null;
    return SlideShape(
      place.frame,
      rotation: place.rotation,
      flipH: place.flipH,
      flipV: place.flipV,
      geometry: connector ? 'line' : geom,
      fill: connector ? null : fill,
      line: line,
      lineWidth: lineWidth,
      text: hasText ? text : null,
      paths: geom == 'custom' ? _paths(spPr!.child('custGeom')!) : const [],
      heads: heads,
    );
  }

  SlidePicture? _picture(XmlElement s, _Transform t) {
    final blipFill = s.child('blipFill');
    final media = deck._media(path, blipFill?.child('blip'));
    final ph = _placeholderOf(s);
    final layoutPh = ph == null ? null : (layout?.byIdx(ph.$2) ?? layout?.byType(ph.$1));
    final xfrm = s.at(['spPr', 'xfrm']);
    final frame = _frame(xfrm) ?? layoutPh?.frame;
    if (media == null || frame == null) return null;
    final place = _place(xfrm, frame, t);
    final src = blipFill?.child('srcRect');
    double cut(String n) => ((src?.number(n) ?? 0) / 100000).clamp(-1.0, 1.0);
    return SlidePicture(
      place.frame,
      media,
      rotation: place.rotation,
      flipH: place.flipH,
      flipV: place.flipV,
      crop: [cut('l'), cut('t'), cut('r'), cut('b')],
    );
  }

  void _graphicFrame(XmlElement s, _Transform t, List<SlideNode> out) {
    final frame = _frame(s.child('xfrm'));
    if (frame == null) return;
    final place = t.apply(frame);
    final data = s.at(['graphic', 'graphicData']);
    final uri = data?.attr('uri') ?? '';
    if (data?.child('tbl') case final tbl?) {
      out.add(_table(tbl, place));
      return;
    }
    if (uri.endsWith('/diagram')) {
      final drawing = _diagramDrawing(data!);
      if (drawing != null) {
        final tree = deck.pkg.xml(drawing)?.rootElement.child('spTree');
        if (tree != null) {
          final reader = _SlideReader(deck, drawing, number, ctx, null, null);
          out.addAll(reader.nodes(tree.open().toList(), t.then(_Transform(1, 1, frame.x, frame.y))));
          return;
        }
      }
    }
    // An embedded object often carries a picture of itself.
    final blip = data?.descendantElements.where((e) => e.name.local == 'blip').firstOrNull;
    final media = blip == null ? null : deck._media(path, blip);
    if (media != null) {
      out.add(SlidePicture(place, media));
      return;
    }
    final label = uri.endsWith('/chart') || uri.contains('chartex') ? 'Chart' : 'Object';
    out.add(SlideStandIn(place, label));
  }

  /// The drawing PowerPoint saved for a SmartArt graphic, if any.
  String? _diagramDrawing(XmlElement data) {
    final rels = deck.pkg.rels(path);
    final ids = data.child('relIds');
    final dataPart = rels[ids?.relAttr('dm')]?.target;
    if (dataPart != null) {
      final ext = deck.pkg.xml(dataPart)?.rootElement.descendantElements.where((e) => e.name.local == 'dataModelExt').firstOrNull;
      final drawing = rels[ext?.attr('relId')]?.target;
      if (drawing != null && deck.pkg.has(drawing)) return drawing;
    }
    final drawings = rels.values.where((r) => r.type.endsWith('/diagramDrawing')).toList();
    return drawings.length == 1 ? drawings.single.target : null;
  }

  SlideTable _table(XmlElement tbl, ORect frame) {
    final columns = [
      for (final c in tbl.child('tblGrid')?.kids('gridCol') ?? const <XmlElement>[]) (c.number('w') ?? 0) / emuPerPoint,
    ];
    final pr = tbl.child('tblPr');
    final firstRow = pr?.flag('firstRow') ?? false;
    final banded = pr?.flag('bandRow') ?? false;
    final accent = ctx.theme.colors['accent1'] ?? 0xFF4472C4;
    final rows = <SlideRow>[];
    for (final (r, tr) in (tbl.kids('tr').toList()).indexed) {
      final head = firstRow && r == 0;
      // Like PowerPoint's default table style: an accent header row, and
      // light tints of it under, banded.
      final band = banded && (r - (firstRow ? 1 : 0)).isOdd;
      final styleFill = head ? accent : _tint(accent, band ? 0.4 : 0.2);
      final cells = <SlideCell>[];
      for (final tc in tr.kids('tc')) {
        final tcPr = tc.child('tcPr');
        final own = tcPr == null ? null : deck._fill(tcPr, path, ctx);
        final text = _text(
          tc.child('txBody') ?? XmlElement(XmlName('txBody')),
          null,
          null,
          null,
          head ? ctx.theme.colors['lt1'] : null,
          table: true,
          bold: head,
          insets: (
            (tcPr?.number('marL') ?? 91440) / emuPerPoint,
            (tcPr?.number('marT') ?? 45720) / emuPerPoint,
            (tcPr?.number('marR') ?? 91440) / emuPerPoint,
            (tcPr?.number('marB') ?? 45720) / emuPerPoint,
          ),
          anchor: tcPr?.attr('anchor'),
        );
        cells.add(SlideCell(
          text,
          fill: own == null ? styleFill : own.color,
          span: tc.integer('gridSpan') ?? 1,
          hidden: tc.flag('hMerge') == true || tc.flag('vMerge') == true,
        ));
      }
      rows.add(SlideRow((tr.number('h') ?? 0) / emuPerPoint, cells));
    }
    return SlideTable(frame, columns, rows);
  }

  static int _tint(int argb, double keep) {
    int ch(int shift) => (255 - (255 - (argb >> shift & 0xFF)) * keep).round();
    return 0xFF000000 | ch(16) << 16 | ch(8) << 8 | ch(0);
  }

  // Text.

  OText _text(
    XmlElement body,
    (String, String?)? ph,
    _Placeholder? layoutPh,
    _Placeholder? masterPh,
    int? fontColor, {
    bool table = false,
    bool bold = false,
    (double, double, double, double)? insets,
    String? anchor,
  }) {
    // Body properties: the shape's, then its placeholders'.
    final bodies = [body.child('bodyPr'), layoutPh?.body, masterPh?.body];
    String? bodyAttr(String n) => bodies.map((b) => b?.attr(n)).firstWhere((v) => v != null, orElse: () => null);
    double inset(String n, double fallback) {
      final v = bodyAttr(n);
      return v == null ? fallback : (double.tryParse(v) ?? fallback * emuPerPoint) / emuPerPoint;
    }

    final autofit = body.at(['bodyPr', 'normAutofit']);
    final fontScale = (autofit?.number('fontScale') ?? 100000) / 100000;
    final spacingCut = (autofit?.number('lnSpcReduction') ?? 0) / 100000;

    // Text styles, highest first.
    final type = ph?.$1;
    final masterList = ph == null
        ? master?.other
        : (type == 'title' || type == 'ctrTitle' ? master?.title : master?.body);
    final lists = [
      _ListStyle.read(body.child('lstStyle'), ctx),
      if (fontColor != null) _ListStyle(const {}, _Level(color: fontColor)),
      if (bold) const _ListStyle({}, _Level(bold: true)),
      ?layoutPh?.list,
      ?masterPh?.list,
      ?masterList,
      if (table) const _ListStyle({}, _Level(size: 18)),
      deck.defaults,
    ];

    _numbers.clear();
    final paragraphs = <OPara>[];
    for (final p in body.kids('p')) {
      final pPr = p.child('pPr');
      final level = (pPr?.integer('lvl') ?? 0) + 1;
      var style = _Level.para(pPr, ctx);
      for (final l in lists) {
        style = style.over(l.at(level));
      }
      final runs = <ORun>[];
      for (final r in p.childElements) {
        final String text;
        switch (r.name.local) {
          case 'r':
            text = r.child('t')?.innerText ?? '';
          case 'fld':
            text = r.attr('type') == 'slidenum' ? '$number' : r.child('t')?.innerText ?? '';
          case 'br':
            text = '\n';
          default:
            continue;
        }
        final look = _Level.run(r.child('rPr'), ctx).over(style);
        final baseline = r.child('rPr')?.number('baseline') ?? 0;
        runs.add(ORun(
          drawableText(look.caps == true ? text.toUpperCase() : text),
          size: (look.size ?? 18) * fontScale * (baseline != 0 ? 0.65 : 1),
          bold: look.bold ?? false,
          italic: look.italic ?? false,
          underline: look.underline ?? false,
          strike: look.strike ?? false,
          color: look.color ?? ctx.theme.colors[ctx.map['tx1'] ?? 'dk1'] ?? 0xFF000000,
          serif: isSerifFont(ctx.theme.font(look.font ?? '+mn-lt')),
          highlight: readColor(r.at(['rPr', 'highlight']), ctx.theme, map: ctx.map),
          raised: baseline > 0,
        ));
      }
      final endSize = (_Level.run(p.child('endParaRPr'), ctx).size ?? (style.size ?? 18)) * fontScale;
      final first = runs.where((r) => r.text.trim().isNotEmpty).firstOrNull;
      final lineSize = first?.size ?? endSize;
      final lineHeight = style.lnSpcPts != null
          ? style.lnSpcPts! / math.max(lineSize, 1)
          : 1.2 * (style.lnSpcPct ?? 1) * (1 - spacingCut);
      final marL = style.marL ?? 0, indent = style.indent ?? 0;
      String? bullet;
      final b = style.bullet;
      final empty = runs.every((r) => r.text.trim().isEmpty);
      if (b != null && !empty) {
        switch (b.kind) {
          case _BulletKind.char:
            bullet = b.char;
          case _BulletKind.number:
            final n = _numbers[level] = (_numbers[level] ?? b.start - 1) + 1;
            bullet = autoNumber(b.scheme, n);
          case _BulletKind.none:
            break;
        }
      }
      if (b?.kind != _BulletKind.number) _numbers.remove(level);
      paragraphs.add(OPara(
        runs,
        align: style.align ?? 'l',
        indent: bullet == null ? math.max(0, marL + (indent > 0 ? indent : 0)) : marL,
        bullet: bullet,
        bulletIndent: math.max(0, marL + indent),
        bulletColor: style.bulletColor,
        spaceBefore: style.spcBefPts ?? (style.spcBefPct ?? 0) * lineSize * 1.2,
        spaceAfter: style.spcAftPts ?? (style.spcAftPct ?? 0) * lineSize * 1.2,
        lineHeight: lineHeight,
        emptySize: endSize,
      ));
    }
    final ins = insets;
    return OText(
      paragraphs,
      left: ins?.$1 ?? inset('lIns', 7.2),
      top: ins?.$2 ?? inset('tIns', 3.6),
      right: ins?.$3 ?? inset('rIns', 7.2),
      bottom: ins?.$4 ?? inset('bIns', 3.6),
      anchor: anchor ?? bodyAttr('anchor') ?? 't',
      wrap: bodyAttr('wrap') != 'none',
    );
  }

  List<OPath> _paths(XmlElement cust) {
    final out = <OPath>[];
    for (final path in cust.child('pathLst')?.kids('path') ?? const <XmlElement>[]) {
      final cmds = <double>[];
      var cur = (0.0, 0.0);
      (double, double) pt(XmlElement e) => (e.number('x') ?? 0, e.number('y') ?? 0);
      for (final c in path.childElements) {
        final pts = c.kids('pt').map(pt).toList();
        switch (c.name.local) {
          case 'moveTo' when pts.isNotEmpty:
            cmds.addAll([0, pts[0].$1, pts[0].$2]);
            cur = pts[0];
          case 'lnTo' when pts.isNotEmpty:
            cmds.addAll([1, pts[0].$1, pts[0].$2]);
            cur = pts[0];
          case 'cubicBezTo' when pts.length >= 3:
            cmds.addAll([2, pts[0].$1, pts[0].$2, pts[1].$1, pts[1].$2, pts[2].$1, pts[2].$2]);
            cur = pts[2];
          case 'quadBezTo' when pts.length >= 2:
            cmds.addAll([3, pts[0].$1, pts[0].$2, pts[1].$1, pts[1].$2]);
            cur = pts[1];
          case 'arcTo':
            // An arc of an ellipse from the current point, as short lines.
            final wr = c.number('wR') ?? 0, hr = c.number('hR') ?? 0;
            final start = (c.number('stAng') ?? 0) / 60000 * math.pi / 180;
            final sweep = (c.number('swAng') ?? 0) / 60000 * math.pi / 180;
            final cx = cur.$1 - wr * math.cos(start), cy = cur.$2 - hr * math.sin(start);
            const steps = 12;
            for (var i = 1; i <= steps; i++) {
              final a = start + sweep * i / steps;
              cur = (cx + wr * math.cos(a), cy + hr * math.sin(a));
              cmds.addAll([1, cur.$1, cur.$2]);
            }
          case 'close':
            cmds.add(4);
        }
      }
      out.add(OPath(
        path.number('w') ?? 0,
        path.number('h') ?? 0,
        cmds,
        filled: path.attr('fill') != 'none',
        stroked: path.flag('stroke') ?? true,
      ));
    }
    return out;
  }
}

/// The [n]th label of a numbered list in PowerPoint's [scheme]
/// (`arabicPeriod` "3.", `alphaLcParenR` "c)", `romanUcPeriod` "III."…).
String autoNumber(String scheme, int n) {
  final s = scheme.toLowerCase();
  String core;
  if (s.startsWith('alphalc')) {
    core = _letters(n);
  } else if (s.startsWith('alphauc')) {
    core = _letters(n).toUpperCase();
  } else if (s.startsWith('romanlc')) {
    core = roman(n).toLowerCase();
  } else if (s.startsWith('romanuc')) {
    core = roman(n);
  } else {
    core = '$n';
  }
  if (s.endsWith('parenboth')) return '($core)';
  if (s.endsWith('parenr')) return '$core)';
  if (s.endsWith('plain')) return core;
  return '$core.';
}

String _letters(int n) {
  var out = '';
  while (n > 0) {
    n--;
    out = String.fromCharCode(97 + n % 26) + out;
    n ~/= 26;
  }
  return out;
}

/// [n] in Roman numerals.
String roman(int n) {
  if (n <= 0) return '$n';
  const values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
  const symbols = ['M', 'CM', 'D', 'CD', 'C', 'XC', 'L', 'XL', 'X', 'IX', 'V', 'IV', 'I'];
  final out = StringBuffer();
  for (var i = 0; i < values.length; i++) {
    while (n >= values[i]) {
      out.write(symbols[i]);
      n -= values[i];
    }
  }
  return out.toString();
}

/// The file name of a part, for messages.
String partName(String path) => p.posix.basename(path);
