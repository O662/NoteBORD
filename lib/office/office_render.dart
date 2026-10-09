import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/painting.dart';

import '../theme/tokens.g.dart' show FontFamilies;
import 'office_model.dart';
import 'ooxml.dart';

// Drawing what was read from an Office file: slides and Word pages as
// pictures in their own points, and the paging of a Word document.

/// Decodes a picture file from inside an Office file.
typedef MediaDecoder = Future<ui.Image> Function(Uint8List bytes);

/// An Office file ready to show: its pages, their pictures and their text.
/// Pictures inside the file are decoded as pages need them; [onChanged]
/// says when a page can be drawn more fully than before.
class OfficePreview {
  OfficePreview(this.doc, Uint8List bytes, {required this.decode, this.onChanged}) : _pkg = OoxmlPackage(bytes) {
    if (doc case final WordDoc w) _layout = WordLayout(w);
  }

  final OfficeDoc doc;
  final MediaDecoder decode;
  void Function()? onChanged;
  final OoxmlPackage _pkg;
  WordLayout? _layout;

  final _images = <String, ui.Image>{};
  final _loading = <String>{};
  final _failed = <String>{};
  final _pictures = <int, ui.Picture>{};
  bool _disposed = false;

  /// Pictures of this many pages are kept.
  static const keepPictures = 6;

  int get pageCount => switch (doc) {
        Deck d => d.slides.length,
        WordDoc _ => _layout!.pages.length,
        Workbook b => b.sheets.length,
      };

  /// A Word page or slide in points; null for a workbook.
  Size? get pageSize => switch (doc) {
        Deck d => Size(d.width, d.height),
        WordDoc w => Size(w.pageWidth, w.pageHeight),
        Workbook _ => null,
      };

  /// Sheet [page] (from 1) of a workbook.
  Sheet? sheet(int page) => switch (doc) {
        Workbook b => b.sheets[(page - 1).clamp(0, b.sheets.length - 1)],
        _ => null,
      };

  /// What page [page] (from 1) says, for search and exported PDFs.
  String text(int page) {
    final i = (page - 1).clamp(0, pageCount - 1);
    return switch (doc) {
      Deck d => d.slides[i].text,
      WordDoc _ => _layout!.text(i),
      Workbook b => b.sheets[i].text,
    };
  }

  /// A picture of page [page] (from 1) in its own points, or null for a
  /// workbook (drawn as cells, in the app's colors). Pictures inside the
  /// file that aren't decoded yet are boxes until they are.
  ui.Picture? picture(int page) {
    if (_disposed || doc is Workbook) return null;
    final i = (page - 1).clamp(0, pageCount - 1);
    final kept = _pictures.remove(i);
    if (kept != null) {
      _pictures[i] = kept; // most recent last
      return kept;
    }
    final media = _mediaOn(i);
    final waiting = media.where((m) => !_images.containsKey(m) && !_failed.contains(m)).toList();
    for (final m in waiting) {
      _load(m);
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    switch (doc) {
      case Deck d:
        paintSlide(canvas, d, d.slides[i], _images);
      case WordDoc w:
        _layout!.paintPage(canvas, i, w, _images);
      case Workbook _:
        break;
    }
    final picture = recorder.endRecording();
    if (waiting.isNotEmpty) return picture;
    _pictures[i] = picture;
    while (_pictures.length > keepPictures) {
      final oldest = _pictures.keys.first;
      _pictures.remove(oldest)!.dispose();
    }
    return picture;
  }

  /// Waits until the pictures page [page] needs are decoded (or failed).
  Future<void> ready(int page) async {
    if (doc is Workbook) return;
    final i = (page - 1).clamp(0, pageCount - 1);
    await Future.wait([for (final m in _mediaOn(i)) _load(m)]);
  }

  Set<String> _mediaOn(int i) => switch (doc) {
        Deck d => {
            ?d.slides[i].background?.media,
            for (final n in d.slides[i].nodes)
              ...switch (n) {
                SlidePicture p => [p.media],
                SlideShape s => [?s.fill?.media],
                _ => const <String>[],
              },
          },
        WordDoc _ => _layout!.mediaOn(i),
        Workbook _ => const {},
      };

  final _pending = <String, Future<void>>{};

  Future<void> _load(String media) {
    if (_images.containsKey(media) || _failed.contains(media)) return Future.value();
    return _pending[media] ??= _decodeMedia(media);
  }

  Future<void> _decodeMedia(String media) async {
    _loading.add(media);
    ui.Image? image;
    try {
      final bytes = _pkg.bytes(media);
      if (bytes != null) image = await decode(bytes);
    } on Object catch (e) {
      // EMF, WMF, SVG and TIFF pictures stay boxes.
      debugPrint('Could not draw $media: $e');
    }
    _loading.remove(media);
    _pending.remove(media);
    if (_disposed) {
      image?.dispose();
      return;
    }
    if (image == null) {
      _failed.add(media);
    } else {
      _images[media] = image;
    }
    if (_loading.isEmpty) onChanged?.call();
  }

  void dispose() {
    _disposed = true;
    for (final p in _pictures.values) {
      p.dispose();
    }
    _pictures.clear();
    for (final i in _images.values) {
      i.dispose();
    }
    _images.clear();
    _layout?.dispose();
  }
}

// Text.

TextStyle _style(ORun r, double lineHeight) {
  final deco = [if (r.underline) TextDecoration.underline, if (r.strike) TextDecoration.lineThrough];
  return TextStyle(
    fontFamily: r.serif ? FontFamilies.serif : FontFamilies.ui,
    fontSize: math.max(r.size, 0.5),
    fontWeight: r.bold ? FontWeight.w700 : FontWeight.w400,
    fontStyle: r.italic ? FontStyle.italic : FontStyle.normal,
    color: Color(r.color),
    height: lineHeight,
    decoration: deco.isEmpty ? null : TextDecoration.combine(deco),
    decorationColor: Color(r.color),
    backgroundColor: r.highlight == null ? null : Color(r.highlight!),
  );
}

TextAlign _align(String a) => switch (a) {
      'ctr' => TextAlign.center,
      'r' => TextAlign.right,
      'just' || 'dist' => TextAlign.justify,
      _ => TextAlign.left,
    };

/// A paragraph laid out at a width: its text, its bullet, and how tall it
/// is (without the space around it).
class LaidParagraph {
  LaidParagraph(this.para, this.text, this.bullet, this.textLeft, this.height);

  final OPara para;
  final TextPainter? text;
  final TextPainter? bullet;
  final double textLeft;
  final double height;

  double get before => para.spaceBefore;
  double get after => para.spaceAfter;

  /// Draws it with its frame's top-left corner at [at]; [clipTop] and
  /// [clipBottom] cut it to part of its height (for a page break).
  void paint(Canvas canvas, Offset at, {double clipTop = 0, double? clipBottom}) {
    final cut = clipTop > 0 || clipBottom != null;
    if (cut) {
      canvas
        ..save()
        ..clipRect(Rect.fromLTRB(-1e5, at.dy, 1e5, at.dy + (clipBottom ?? height) - clipTop));
    }
    final text = this.text, bullet = this.bullet;
    if (text != null) text.paint(canvas, Offset(at.dx + textLeft, at.dy - clipTop));
    if (bullet != null && clipTop == 0) {
      // On the first line's baseline.
      final base = text == null ? bullet.height : text.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      final own = bullet.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      bullet.paint(canvas, Offset(at.dx + para.bulletIndent, at.dy + base - own));
    }
    if (cut) canvas.restore();
  }

  void dispose() {
    text?.dispose();
    bullet?.dispose();
  }
}

/// Lays [p] out [width] wide (no wrapping when [wrap] is false).
LaidParagraph layoutParagraph(OPara p, double width, {bool wrap = true}) {
  final runs = [for (final r in p.runs) if (r.text.isNotEmpty) r];
  TextPainter? bullet;
  var left = p.indent;
  if (p.bullet != null && runs.isNotEmpty) {
    final first = runs.first;
    bullet = TextPainter(
      text: TextSpan(
        text: p.bullet,
        style: _style(
          ORun(p.bullet!, size: first.size, color: p.bulletColor ?? first.color, bold: first.bold, serif: first.serif),
          p.lineHeight,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Room for the bullet before the text.
    left = math.max(left, p.bulletIndent + bullet.width + first.size * 0.35);
  }
  if (runs.isEmpty) {
    return LaidParagraph(p, null, null, left, p.emptySize * p.lineHeight);
  }
  final text = TextPainter(
    text: TextSpan(children: [for (final r in runs) TextSpan(text: r.text, style: _style(r, p.lineHeight))]),
    textAlign: _align(p.align),
    textDirection: TextDirection.ltr,
  );
  if (wrap) {
    // As wide as the frame, so centered and right-aligned lines sit across
    // all of it.
    final w = math.max(1.0, width - left - p.rightIndent);
    text.layout(minWidth: w, maxWidth: w);
  } else {
    text.layout();
  }
  return LaidParagraph(p, text, bullet, left, text.height);
}

// Slides.

/// Draws [slide] in slide points, its top-left corner at the origin.
void paintSlide(Canvas canvas, Deck deck, Slide slide, Map<String, ui.Image> images) {
  final page = Rect.fromLTWH(0, 0, deck.width, deck.height);
  canvas
    ..save()
    ..clipRect(page);
  _fillRect(canvas, page, slide.background ?? const OFill(color: 0xFFFFFFFF), images);
  for (final n in slide.nodes) {
    canvas.save();
    final r = Rect.fromLTWH(n.frame.x, n.frame.y, n.frame.w, n.frame.h);
    if (n.rotation != 0) {
      canvas
        ..translate(r.center.dx, r.center.dy)
        ..rotate(n.rotation * math.pi / 180)
        ..translate(-r.center.dx, -r.center.dy);
    }
    switch (n) {
      case SlideShape s:
        _shape(canvas, s, r, images);
      case SlidePicture p:
        _picture(canvas, p, r, images);
      case SlideTable t:
        _slideTable(canvas, t, r);
      case SlideStandIn s:
        _standIn(canvas, r, s.label);
    }
    canvas.restore();
  }
  canvas.restore();
}

void _fillRect(Canvas canvas, Rect r, OFill fill, Map<String, ui.Image> images, {Path? clip}) {
  if (fill.media case final m?) {
    final image = images[m];
    if (image != null) {
      canvas.save();
      if (clip != null) canvas.clipPath(clip);
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        r,
        Paint()..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
      return;
    }
  }
  if (fill.color case final c?) {
    final paint = Paint()..color = Color(c);
    if (clip != null) {
      canvas.drawPath(clip, paint);
    } else {
      canvas.drawRect(r, paint);
    }
  }
}

Path _outline(SlideShape s, Rect r) {
  final path = Path();
  final w = r.width, h = r.height, x = r.left, y = r.top;
  Offset at(double fx, double fy) => Offset(x + w * fx, y + h * fy);
  void poly(List<Offset> pts) => path.addPolygon(pts, true);
  switch (s.geometry) {
    case 'ellipse':
      path.addOval(r);
    case 'roundRect':
      path.addRRect(RRect.fromRectAndRadius(r, Radius.circular(math.min(w, h) * 0.1667)));
    case 'triangle':
      poly([at(0.5, 0), at(1, 1), at(0, 1)]);
    case 'rtTriangle':
      poly([at(0, 0), at(1, 1), at(0, 1)]);
    case 'diamond':
      poly([at(0.5, 0), at(1, 0.5), at(0.5, 1), at(0, 0.5)]);
    case 'parallelogram':
      poly([at(0.25, 0), at(1, 0), at(0.75, 1), at(0, 1)]);
    case 'trapezoid':
      poly([at(0.25, 0), at(0.75, 0), at(1, 1), at(0, 1)]);
    case 'pentagon' || 'homePlate':
      poly([at(0, 0), at(0.8, 0), at(1, 0.5), at(0.8, 1), at(0, 1)]);
    case 'chevron':
      poly([at(0, 0), at(0.8, 0), at(1, 0.5), at(0.8, 1), at(0, 1), at(0.2, 0.5)]);
    case 'hexagon':
      poly([at(0.25, 0), at(0.75, 0), at(1, 0.5), at(0.75, 1), at(0.25, 1), at(0, 0.5)]);
    case 'octagon':
      poly([at(0.29, 0), at(0.71, 0), at(1, 0.29), at(1, 0.71), at(0.71, 1), at(0.29, 1), at(0, 0.71), at(0, 0.29)]);
    case 'rightArrow':
      poly([at(0, 0.25), at(0.6, 0.25), at(0.6, 0), at(1, 0.5), at(0.6, 1), at(0.6, 0.75), at(0, 0.75)]);
    case 'leftArrow':
      poly([at(1, 0.25), at(0.4, 0.25), at(0.4, 0), at(0, 0.5), at(0.4, 1), at(0.4, 0.75), at(1, 0.75)]);
    case 'custom':
      for (final p in s.paths) {
        final sx = p.w == 0 ? 1.0 : w / p.w, sy = p.h == 0 ? 1.0 : h / p.h;
        final c = p.commands;
        var i = 0;
        Offset pt(int k) => Offset(x + c[k] * sx, y + c[k + 1] * sy);
        while (i < c.length) {
          switch (c[i].toInt()) {
            case 0:
              final q = pt(i + 1);
              path.moveTo(q.dx, q.dy);
              i += 3;
            case 1:
              final q = pt(i + 1);
              path.lineTo(q.dx, q.dy);
              i += 3;
            case 2:
              final a = pt(i + 1), b = pt(i + 3), e = pt(i + 5);
              path.cubicTo(a.dx, a.dy, b.dx, b.dy, e.dx, e.dy);
              i += 7;
            case 3:
              final a = pt(i + 1), e = pt(i + 3);
              path.quadraticBezierTo(a.dx, a.dy, e.dx, e.dy);
              i += 5;
            default:
              path.close();
              i += 1;
          }
        }
      }
    default:
      path.addRect(r);
  }
  return path;
}

void _shape(Canvas canvas, SlideShape s, Rect r, Map<String, ui.Image> images) {
  if (s.flipH || s.flipV) {
    canvas
      ..save()
      ..translate(r.center.dx, r.center.dy)
      ..scale(s.flipH ? -1 : 1, s.flipV ? -1 : 1)
      ..translate(-r.center.dx, -r.center.dy);
  }
  if (s.geometry == 'line') {
    if (s.line != null) {
      final paint = Paint()
        ..color = Color(s.line!)
        ..strokeWidth = math.max(0.5, s.lineWidth)
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(r.topLeft, r.bottomRight, paint);
      final len = math.max(4.0, s.lineWidth * 4);
      void head(Offset tip, Offset from) {
        final d = tip - from;
        if (d.distance < 0.01) return;
        final v = d / d.distance, n = Offset(-v.dy, v.dx);
        canvas.drawPath(
          Path()
            ..addPolygon([tip, tip - v * len + n * len * 0.5, tip - v * len - n * len * 0.5], true),
          Paint()..color = Color(s.line!),
        );
      }

      if (s.heads & 1 != 0) head(r.topLeft, r.bottomRight);
      if (s.heads & 2 != 0) head(r.bottomRight, r.topLeft);
    }
  } else {
    final path = _outline(s, r);
    final fill = s.fill;
    if (fill != null && (s.paths.isEmpty || s.paths.any((p) => p.filled))) _fillRect(canvas, r, fill, images, clip: path);
    if (s.line != null && (s.paths.isEmpty || s.paths.any((p) => p.stroked))) {
      canvas.drawPath(
        path,
        Paint()
          ..color = Color(s.line!)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.5, s.lineWidth)
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }
  if (s.flipH || s.flipV) canvas.restore();
  if (s.text case final t?) paintTextFrame(canvas, t, r);
}

/// Draws [text] inside [frame], placed at the top, middle or bottom.
void paintTextFrame(Canvas canvas, OText text, Rect frame) {
  final inner = Rect.fromLTRB(frame.left + text.left, frame.top + text.top, frame.right - text.right, frame.bottom - text.bottom);
  final width = math.max(1.0, inner.width);
  final laid = [for (final p in text.paragraphs) layoutParagraph(p, width, wrap: text.wrap)];
  var total = 0.0;
  for (final (i, l) in laid.indexed) {
    total += (i == 0 ? 0 : l.before) + l.height + (i == laid.length - 1 ? 0 : l.after);
  }
  var y = switch (text.anchor) {
    'ctr' => inner.center.dy - total / 2,
    'b' => inner.bottom - total,
    _ => inner.top,
  };
  for (final (i, l) in laid.indexed) {
    if (i > 0) y += l.before;
    var x = inner.left;
    // Unwrapped text grows from where its alignment holds it.
    if (!text.wrap && l.text != null) {
      final w = l.text!.width + l.textLeft;
      x = switch (l.para.align) {
        'ctr' => inner.center.dx - w / 2,
        'r' => inner.right - w,
        _ => inner.left,
      };
    }
    l.paint(canvas, Offset(x, y));
    y += l.height + l.after;
    l.dispose();
  }
}

void _picture(Canvas canvas, SlidePicture p, Rect r, Map<String, ui.Image> images) {
  final image = images[p.media];
  if (image == null) {
    _standIn(canvas, r, '');
    return;
  }
  final iw = image.width.toDouble(), ih = image.height.toDouble();
  final src = Rect.fromLTRB(iw * p.crop[0], ih * p.crop[1], iw * (1 - p.crop[2]), ih * (1 - p.crop[3]));
  canvas.save();
  if (p.flipH || p.flipV) {
    canvas
      ..translate(r.center.dx, r.center.dy)
      ..scale(p.flipH ? -1 : 1, p.flipV ? -1 : 1)
      ..translate(-r.center.dx, -r.center.dy);
  }
  canvas
    ..clipRect(r)
    ..drawImageRect(image, src, r, Paint()..filterQuality = FilterQuality.medium)
    ..restore();
}

void _standIn(Canvas canvas, Rect r, String label) {
  canvas
    ..drawRect(r, Paint()..color = const Color(0xFFEDEBE6))
    ..drawRect(
      r.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0xFFCFC9BC),
    );
  if (label.isEmpty || r.width < 20 || r.height < 12) return;
  final text = TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(fontFamily: FontFamilies.ui, fontSize: math.min(18, r.height / 3), color: const Color(0xFF7A7365)),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout(maxWidth: r.width);
  text.paint(canvas, r.center - Offset(text.width / 2, text.height / 2));
  text.dispose();
}

void _slideTable(Canvas canvas, SlideTable t, Rect r) {
  final total = t.columns.fold<double>(0, (s, w) => s + w);
  final k = total <= 0 ? 1.0 : r.width / total;
  final lefts = <double>[r.left];
  for (final w in t.columns) {
    lefts.add(lefts.last + w * k);
  }
  var y = r.top;
  final border = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..style = PaintingStyle.stroke;
  for (final row in t.rows) {
    // Rows grow to fit their text.
    var height = row.height;
    var col = 0;
    final cells = <(Rect, SlideCell)>[];
    for (final cell in row.cells) {
      final from = col.clamp(0, t.columns.length), to = (col + cell.span).clamp(0, t.columns.length);
      col += cell.span;
      if (from >= to) continue;
      final rect = Rect.fromLTRB(lefts[from], y, lefts[to], y + height);
      cells.add((rect, cell));
      if (cell.hidden) continue;
      final need = _textHeight(cell.text, rect.width);
      height = math.max(height, need);
    }
    for (final (rect, cell) in cells) {
      final cr = Rect.fromLTRB(rect.left, y, rect.right, y + height);
      if (cell.hidden) continue;
      if (cell.fill != null) canvas.drawRect(cr, Paint()..color = Color(cell.fill!));
      canvas.drawRect(cr, border);
      paintTextFrame(canvas, cell.text, cr);
    }
    y += height;
  }
}

double _textHeight(OText text, double width) {
  var total = text.top + text.bottom;
  for (final (i, p) in text.paragraphs.indexed) {
    final l = layoutParagraph(p, math.max(1, width - text.left - text.right));
    total += l.height + (i == 0 ? 0 : l.before) + (i == text.paragraphs.length - 1 ? 0 : l.after);
    l.dispose();
  }
  return total;
}

// Word pages.

sealed class _Op {
  const _Op();
}

class _TextOp extends _Op {
  const _TextOp(this.para, this.at, this.clipTop, this.clipBottom);

  final LaidParagraph para;
  final Offset at;
  final double clipTop;
  final double? clipBottom;
}

class _ImageOp extends _Op {
  const _ImageOp(this.media, this.rect);

  final String media;
  final Rect rect;
}

class _BoxOp extends _Op {
  const _BoxOp(this.rect, {this.fill, this.label = ''});

  final Rect rect;
  final int? fill;
  final String label;
}

/// A Word document cut into pages: its own layout, in the Figtree and
/// Newsreader faces, so page breaks fall near (not exactly) where Word
/// puts them.
class WordLayout {
  WordLayout(WordDoc doc) {
    _layout(doc);
  }

  final pages = <List<_Op>>[[]];
  final _texts = <List<String>>[[]];
  final _painters = <LaidParagraph>[];

  String text(int page) => _texts[page].where((t) => t.trim().isNotEmpty).join('\n');

  Set<String> mediaOn(int page) => {
        for (final op in pages[page])
          if (op is _ImageOp) op.media,
      };

  void _layout(WordDoc doc) {
    final top = doc.marginTop, bottom = doc.pageHeight - doc.marginBottom;
    final left = doc.marginLeft, width = math.max(36.0, doc.pageWidth - doc.marginLeft - doc.marginRight);
    var y = top;
    final height = math.max(36.0, bottom - top);

    void newPage() {
      pages.add([]);
      _texts.add([]);
      y = top;
    }

    bool fresh() => y <= top + 0.01;

    void place(LaidParagraph laid, double x, double w) {
      _painters.add(laid);
      if (!fresh()) y += laid.before;
      var shown = 0.0;
      final lines = laid.text?.computeLineMetrics() ?? const <ui.LineMetrics>[];
      while (true) {
        final room = bottom - y;
        final rest = laid.height - shown;
        if (rest <= room + 0.5) {
          pages.last.add(_TextOp(laid, Offset(x, y), shown, null));
          y += rest;
          break;
        }
        // Cut after the last line that fits.
        var cut = shown;
        var bottomOfLine = 0.0;
        for (final m in lines) {
          bottomOfLine += m.height;
          if (bottomOfLine <= shown + 0.01) continue;
          if (bottomOfLine - shown > room) break;
          cut = bottomOfLine;
        }
        if (cut <= shown) {
          if (fresh()) {
            // Taller than a page and not even a line fits: clip it.
            pages.last.add(_TextOp(laid, Offset(x, y), shown, shown + room));
            shown += room;
          }
          newPage();
          if (shown >= laid.height - 0.5) break;
          continue;
        }
        pages.last.add(_TextOp(laid, Offset(x, y), shown, cut));
        shown = cut;
        newPage();
      }
      y += laid.after;
      _texts.last.add(laid.para.text);
    }

    for (final block in doc.blocks) {
      switch (block) {
        case WordPageBreak():
          newPage();
        case WordParagraph(:final para, :final pageBreakBefore):
          if (pageBreakBefore && !fresh()) newPage();
          place(layoutParagraph(para, width), left, width);
        case WordPicture p:
          final k = math.min(1.0, math.min(width / math.max(p.width, 1), height / math.max(p.height, 1)));
          final w = p.width * k, h = p.height * k;
          if (y + h > bottom + 0.5 && !fresh()) newPage();
          final x = switch (p.align) {
            'ctr' => left + (width - w) / 2,
            'r' => left + width - w,
            _ => left,
          };
          pages.last.add(_ImageOp(p.media, Rect.fromLTWH(x, y, w, h)));
          y += h + 4;
        case WordStandIn s:
          final k = math.min(1.0, math.min(width / math.max(s.width, 1), height / math.max(s.height, 1)));
          final w = s.width * k, h = s.height * k;
          if (y + h > bottom + 0.5 && !fresh()) newPage();
          pages.last.add(_BoxOp(Rect.fromLTWH(left, y, w, h), fill: 0xFFEDEBE6, label: s.label));
          y += h + 4;
        case WordTable t:
          _table(t, left, width, () => y, (v) => y = v, bottom, newPage, fresh);
      }
    }
  }

  void _table(
    WordTable t,
    double left,
    double width,
    double Function() getY,
    void Function(double) setY,
    double bottom,
    void Function() newPage,
    bool Function() fresh,
  ) {
    final total = t.columns.fold<double>(0, (s, w) => s + w);
    final k = total <= 0 ? 1.0 : math.min(1.0, width / total);
    final lefts = <double>[left];
    for (final w in t.columns) {
      lefts.add(lefts.last + w * k);
    }
    const padX = 5.4, padY = 2.0;
    for (final row in t.rows) {
      var col = 0;
      final cells = <(double, double, WordCell, List<LaidParagraph>)>[];
      var height = 14.0;
      for (final cell in row.cells) {
        final from = col.clamp(0, t.columns.length), to = (col + cell.span).clamp(0, t.columns.length);
        col += cell.span;
        if (from >= to) continue;
        final x0 = lefts[from], x1 = lefts[to];
        final laid = cell.hidden ? <LaidParagraph>[] : [for (final p in cell.paragraphs) layoutParagraph(p, math.max(1, x1 - x0 - 2 * padX))];
        var h = 2 * padY;
        for (final (i, l) in laid.indexed) {
          h += l.height + (i == 0 ? 0 : l.before) + (i == laid.length - 1 ? 0 : l.after);
        }
        height = math.max(height, h);
        cells.add((x0, x1, cell, laid));
      }
      if (getY() + height > bottom + 0.5 && !fresh()) newPage();
      final y = getY();
      for (final (x0, x1, cell, laid) in cells) {
        final rect = Rect.fromLTRB(x0, y, x1, y + height);
        pages.last.add(_BoxOp(rect, fill: cell.fill));
        var cy = y + padY;
        for (final (i, l) in laid.indexed) {
          if (i > 0) cy += l.before;
          _painters.add(l);
          final room = y + height - cy;
          pages.last.add(_TextOp(l, Offset(x0 + padX, cy), 0, l.height > room ? math.max(0, room) : null));
          _texts.last.add(l.para.text);
          cy += l.height + l.after;
        }
      }
      setY(y + height);
    }
    setY(getY() + 6);
  }

  void paintPage(Canvas canvas, int page, WordDoc doc, Map<String, ui.Image> images) {
    final sheet = Rect.fromLTWH(0, 0, doc.pageWidth, doc.pageHeight);
    canvas
      ..save()
      ..clipRect(sheet)
      ..drawRect(sheet, Paint()..color = Color(doc.background ?? 0xFFFFFFFF));
    for (final op in pages[page.clamp(0, pages.length - 1)]) {
      switch (op) {
        case _TextOp t:
          t.para.paint(canvas, t.at, clipTop: t.clipTop, clipBottom: t.clipBottom);
        case _ImageOp i:
          final image = images[i.media];
          if (image == null) {
            _standIn(canvas, i.rect, '');
          } else {
            canvas.drawImageRect(
              image,
              Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
              i.rect,
              Paint()..filterQuality = FilterQuality.medium,
            );
          }
        case _BoxOp b:
          if (b.label.isNotEmpty) {
            _standIn(canvas, b.rect, b.label);
            break;
          }
          if (b.fill != null) canvas.drawRect(b.rect, Paint()..color = Color(b.fill!));
          canvas.drawRect(
            b.rect,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.5
              ..color = const Color(0xFF9A9A9A),
          );
      }
    }
    canvas.restore();
  }

  void dispose() {
    for (final p in _painters) {
      p.dispose();
    }
    _painters.clear();
  }
}
