import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show Matrix4;
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';

import '../board/model.dart';
import '../canvas/cards.dart';
import '../canvas/items.dart';
import '../canvas/pens.dart';
import '../canvas/stroke_geometry.dart';
import '../templates/templates.dart';
import '../theme/colors.dart';
import '../theme/tokens.g.dart';

// Exported PDFs (Export.dc.html). One page px is one PDF point, so an
// imported PDF page goes out at its own size. Ink, shapes, paper and sticky
// notes are vectors and typed text is real text; pictures, imported pages
// and cards are images. Colors are the light palette and the ink as it was
// written, whatever the app's mode.

/// "Endless pages": the whole page on one sheet, or cut into paper sheets.
enum EndlessPages { fit, split }

enum PaperSize {
  a4('A4', Size(595.28, 841.89)),
  letter('Letter', Size(612, 792));

  const PaperSize(this.label, this.size);

  final String label;
  final Size size;
}

/// Letter where it is the usual paper (US, Canada, Mexico and a few more),
/// A4 elsewhere.
PaperSize paperForLocale(ui.Locale? locale) =>
    const {'US', 'CA', 'MX', 'PH', 'CL', 'CO', 'VE', 'GT', 'CR', 'PA', 'DO', 'PR', 'SV'}.contains(locale?.countryCode)
        ? PaperSize.letter
        : PaperSize.a4;

class PdfOptions {
  const PdfOptions({
    this.pages = EndlessPages.fit,
    this.paper = PaperSize.a4,
    this.searchable = true,
    this.background = false,
  });

  final EndlessPages pages;
  final PaperSize paper;

  /// Add the invisible text layer (handwriting, cards, imported pages).
  final bool searchable;

  /// Draw the page's dots, lines or grid.
  final bool background;
}

/// Text laid invisibly over a rectangle of the page (page px), so a PDF
/// reader can find and select it.
class TextRun {
  const TextRun(this.text, this.rect);

  final String text;
  final Rect rect;
}

/// What the handwriting on a page says. Recognition comes in Phase 5;
/// until then there is none.
abstract class HandwritingText {
  const HandwritingText();

  List<TextRun> runsFor(BoardPage page);
}

class NoHandwritingText extends HandwritingText {
  const NoHandwritingText();

  @override
  List<TextRun> runsFor(BoardPage page) => const [];
}

/// The fonts typed text is written with, as TTF bytes.
abstract class PdfFontSource {
  Future<ByteData> load(String family, {bool semiBold = false});
}

/// The app's bundled fonts.
class BundledFonts implements PdfFontSource {
  const BundledFonts();

  @override
  Future<ByteData> load(String family, {bool semiBold = false}) => rootBundle.load(switch (family) {
        FontFamilies.serif => 'assets/fonts/Newsreader-Regular.ttf',
        FontFamilies.handwritingSample => 'assets/fonts/Caveat-Regular.ttf',
        _ => semiBold ? 'assets/fonts/Figtree-SemiBold.ttf' : 'assets/fonts/Figtree-Regular.ttf',
      });
}

/// Space left around the ink when a page is fitted to it.
const fitMargin = 32.0;

/// The biggest PDF page readers handle (200 inches).
const maxSheet = 14400.0;

/// Everything drawn on [page], or null if it is empty.
Rect? pageContent(BoardPage page) {
  Rect? r = layoutBounds(page.template);
  for (final i in page.items) {
    r = r == null ? i.bounds : r.expandToInclude(i.bounds);
  }
  return r;
}

/// The parts of [page] that become PDF pages, in reading order (page px).
List<Rect> pdfSheets(BoardPage page, PdfOptions options) {
  final content = pageContent(page);
  final paper = options.paper.size;
  if (content == null) return [Offset.zero & paper];
  if (options.pages == EndlessPages.fit) {
    // An imported page with everything written inside it goes out as it came in.
    for (final f in page.items.whereType<FileItem>()) {
      if (f.rotation == 0 && page.items.every((i) => identical(i, f) || _inside(i.bounds, f.extent))) {
        return [f.extent];
      }
    }
    return [content.inflate(fitMargin)];
  }
  final area = content.inflate(fitMargin / 2);
  final cols = math.max(1, (area.width / paper.width).ceil());
  final rows = math.max(1, (area.height / paper.height).ceil());
  final origin = area.center - Offset(cols * paper.width / 2, rows * paper.height / 2);
  final sheets = <Rect>[
    for (var r = 0; r < rows; r++)
      for (var c = 0; c < cols; c++) (origin + Offset(c * paper.width, r * paper.height)) & paper,
  ];
  final layout = layoutBounds(page.template);
  final used = [
    for (final s in sheets)
      if (page.items.any((i) => i.bounds.overlaps(s)) || (layout?.overlaps(s) ?? false)) s,
  ];
  return used.isEmpty ? [sheets.first] : used;
}

bool _inside(Rect a, Rect b) => a.left >= b.left - 0.5 && a.top >= b.top - 0.5 && a.right <= b.right + 0.5 && a.bottom <= b.bottom + 0.5;

/// Reads a file from the notebook's `assets/`, or null if it is missing or
/// locked.
typedef AssetReader = Future<Uint8List?> Function(String name);

/// Writes [pages] as a PDF. [onProgress] hears after each page.
Future<Uint8List> buildPdf({
  required String title,
  required List<BoardPage> pages,
  required AssetReader readAsset,
  PdfOptions options = const PdfOptions(),
  HandwritingText handwriting = const NoHandwritingText(),
  PdfFontSource fonts = const BundledFonts(),
  void Function(int done, int total)? onProgress,
  bool compress = true,
}) async {
  final doc = PdfDocument(compress: compress);
  PdfInfo(doc, title: title, creator: 'Endless', producer: 'Endless');
  final writer = _PdfWriter(doc, readAsset, fonts, options);
  for (final (i, page) in pages.indexed) {
    final runs = options.searchable ? handwriting.runsFor(page) : const <TextRun>[];
    for (final sheet in pdfSheets(page, options)) {
      await writer.sheet(page, sheet, runs);
    }
    onProgress?.call(i + 1, pages.length);
    // Let the progress show between pages.
    await Future<void>.delayed(Duration.zero);
  }
  return doc.save();
}

class _PdfWriter {
  _PdfWriter(this.doc, this.readAsset, this.fontSource, this.options);

  final PdfDocument doc;
  final AssetReader readAsset;
  final PdfFontSource fontSource;
  final PdfOptions options;
  final EndlessColors c = paperLight;

  final _fonts = <String, PdfFont>{};
  final _images = <String, PdfImage?>{};
  final _states = <double, PdfGraphicState>{};
  late PdfGraphics g;

  Future<PdfFont> _font(String family, {bool semiBold = false}) async {
    final key = '$family$semiBold';
    return _fonts[key] ??= PdfTtfFont(doc, await fontSource.load(family, semiBold: semiBold));
  }

  void _color(Color color) {
    g.setFillColor(PdfColor.fromInt(color.toARGB32() | 0xFF000000));
    g.setStrokeColor(PdfColor.fromInt(color.toARGB32() | 0xFF000000));
  }

  void _alpha(double a) => g.setGraphicState(_states[a] ??= PdfGraphicState(opacity: a));

  void _transform(Matrix4 m) => g.setTransform(m);

  Future<void> sheet(BoardPage page, Rect sheet, List<TextRun> runs) async {
    final k = math.min(1.0, maxSheet / math.max(sheet.width, sheet.height));
    final format = PdfPageFormat(sheet.width * k, sheet.height * k);
    final pdfPage = PdfPage(doc, pageFormat: format);
    g = pdfPage.getGraphics();
    g.saveContext();
    // Page px, y down, onto PDF points, y up.
    _transform(Matrix4.identity()
      ..translateByDouble(-sheet.left * k, format.height + sheet.top * k, 0, 1)
      ..scaleByDouble(k, -k, 1, 1));
    g
      ..drawRect(sheet.left, sheet.top, sheet.width, sheet.height)
      ..clipPath();

    if (options.background) _paper(page.paper, sheet);
    final layout = layoutBounds(page.template);
    if (layout != null && layout.overlaps(sheet)) {
      final picture = layoutPicture(page.template, c);
      if (picture != null) await _raster(layout, (canvas) => canvas.drawPicture(picture));
    }

    final text = <TextRun>[...runs];
    for (final item in page.items) {
      if (!item.bounds.overlaps(sheet)) continue;
      switch (item) {
        case StrokeItem s:
          _stroke(s, s.color);
        case BoxItem b:
          await _box(b, text);
        case UnknownItem _:
          break;
      }
    }

    if (options.searchable) {
      final font = await _font(FontFamilies.ui);
      for (final run in text) {
        if (run.rect.overlaps(sheet)) _invisible(font, run);
      }
    }
    g.restoreContext();
  }

  // Ink.

  void _shape(InkShape shape) {
    if (shape.dot != null) {
      final d = shape.dot!;
      g.drawEllipse(d.center.dx, d.center.dy, d.width / 2, d.height / 2);
    }
    for (final poly in shape.polygons) {
      if (poly.isEmpty) continue;
      g.moveTo(poly.first.dx, poly.first.dy);
      for (final p in poly.skip(1)) {
        g.lineTo(p.dx, p.dy);
      }
      g.closePath();
    }
  }

  void _stroke(StrokeItem s, Color color) {
    if (s.points.isEmpty) return;
    final alpha = inkOpacity(s.tool, s.penType);
    g.saveContext();
    _color(color);
    if (alpha < 1) _alpha(alpha);
    // The line, its heads and its dots in one fill, so translucent ink
    // doesn't darken where they meet.
    _shape(inkShapeFor(s));
    for (final head in arrowHeadShapes(s)) {
      _shape(head);
    }
    final dots = <Offset>[
      if (s.startItemId != null && !(s.arrow?.start ?? false) && s.points.isNotEmpty) s.pagePoints.first,
      if (s.endItemId != null && !(s.arrow?.end ?? false) && s.points.isNotEmpty) s.pagePoints.last,
    ];
    for (final d in dots) {
      g.drawEllipse(d.dx, d.dy, s.attachDotRadius, s.attachDotRadius);
    }
    g.fillPath();
    g.restoreContext();
  }

  // Boxes, drawn in their own turned frame with the origin at the top-left.

  Future<void> _box(BoxItem item, List<TextRun> text) async {
    g.saveContext();
    final m = Matrix4.identity()..translateByDouble(item.center.dx, item.center.dy, 0, 1);
    if (item.rotation != 0) m.rotateZ(item.angle);
    m.translateByDouble(-item.w / 2, -item.h / 2, 0, 1);
    _transform(m);
    switch (item) {
      case TextItem t:
        await _text(t, t.color);
      case StickyItem s:
        await _sticky(s);
      case FrameItem f:
        await _frame(f);
      case ImageItem i:
        await _image(i);
        if (i is FileItem && i.text.trim().isNotEmpty) text.add(TextRun(i.text, i.extent));
      case CardItem card:
        await _raster(card.paintRect, (canvas) => paintCard(canvas, card, c));
        final words = cardText(card);
        if (words.isNotEmpty) text.add(TextRun(words, card.extent));
      case ShapeItem s:
        _shapeItem(s);
    }
    g.restoreContext();
  }

  void _shapeItem(ShapeItem s) {
    void outline() {
      switch (s.kind) {
        case ShapeType.rect:
          g.drawRect(0, 0, s.w, s.h);
        case ShapeType.ellipse:
          g.drawEllipse(s.w / 2, s.h / 2, s.w / 2, s.h / 2);
        case ShapeType.triangle:
          g
            ..moveTo(s.w / 2, 0)
            ..lineTo(s.w, s.h)
            ..lineTo(0, s.h)
            ..closePath();
        case ShapeType.line || ShapeType.arrow:
          final y = s.h / 2;
          g
            ..moveTo(0, y)
            ..lineTo(s.w, y);
          if (s.kind == ShapeType.arrow) {
            final len = math.min(arrowHeadLength(s.strokeWidth), s.w);
            final dx = len * math.cos(math.pi / 6), dy = len * math.sin(math.pi / 6);
            g
              ..moveTo(s.w - dx, y - dy)
              ..lineTo(s.w, y)
              ..lineTo(s.w - dx, y + dy);
          }
      }
    }

    if (s.fill != null && !s.isLine) {
      _color(s.fill!);
      if (s.fill!.a < 1) _alpha(s.fill!.a);
      outline();
      g.fillPath();
    }
    _color(s.stroke);
    if (s.stroke.a < 1) _alpha(s.stroke.a);
    g
      ..setLineWidth(s.strokeWidth)
      ..setLineCap(PdfLineCap.round)
      ..setLineJoin(PdfLineJoin.round);
    outline();
    g.strokePath();
  }

  Future<void> _text(TextItem t, Color color) async {
    final font = await _font(textFonts[t.font] ?? FontFamilies.ui);
    final painter = layoutText(t.text, t.font, t.size, t.wrap);
    _color(color);
    for (final line in textLines(painter, t.text)) {
      _string(font, t.size, line.text, line.left, line.baseline);
    }
    painter.dispose();
  }

  /// [s] with its baseline at ([x], [y]), upright.
  void _string(PdfFont font, double size, String s, double x, double y, {PdfTextRenderingMode mode = PdfTextRenderingMode.fill}) {
    if (s.trim().isEmpty) return;
    g.saveContext();
    _transform(Matrix4.identity()
      ..translateByDouble(x, y, 0, 1)
      ..scaleByDouble(1, -1, 1, 1));
    g.drawString(font, size, s, 0, 0, mode: mode);
    g.restoreContext();
  }

  void _invisible(PdfFont font, TextRun run) {
    final lines = [for (final l in run.text.split('\n')) if (l.trim().isNotEmpty) l.trim()];
    if (lines.isEmpty) return;
    final step = run.rect.height / lines.length;
    for (final (i, line) in lines.indexed) {
      final unit = font.stringMetrics(line).advanceWidth;
      if (unit <= 0) continue;
      final size = math.max(0.5, math.min(step * 0.9, run.rect.width / unit));
      _string(font, size, line, run.rect.left, run.rect.top + step * i + size * 0.85, mode: PdfTextRenderingMode.invisible);
    }
  }

  Future<void> _sticky(StickyItem s) async {
    final k = s.w / 176;
    for (var i = math.min(s.count - 1, 2); i >= 1; i--) {
      g.saveContext();
      _transform(Matrix4.identity()
        ..translateByDouble(s.w / 2 + 5 * i * k, s.h / 2 + 5 * i * k, 0, 1)
        ..rotateZ(2 * i * math.pi / 180));
      _color(i - 1 < s.under.length ? s.under[i - 1].color : s.color);
      g
        ..drawRect(-s.w / 2, -s.h / 2, s.w, s.h)
        ..fillPath();
      g.restoreContext();
    }
    _color(s.color);
    g
      ..drawRect(0, 0, s.w, s.h)
      ..fillPath();
    g.saveContext();
    g
      ..drawRect(0, 0, s.w, s.h)
      ..clipPath();
    for (final item in s.items) {
      switch (item) {
        case StrokeItem ink:
          _stroke(ink, ink.color);
        case TextItem t:
          g.saveContext();
          _transform(Matrix4.identity()..translateByDouble(t.x, t.y, 0, 1));
          await _text(t, t.color);
          g.restoreContext();
        case BoxItem box:
          await _box(box, []);
        case UnknownItem _:
          break;
      }
    }
    g.restoreContext();
    if (s.isStack) {
      final badge = stackBadgeRect(s);
      _color(c.inverse);
      g
        ..drawRRect(badge.left, badge.top, badge.width, badge.height, badge.height / 2, badge.height / 2)
        ..fillPath();
      final font = await _font(FontFamilies.ui, semiBold: true);
      final label = stackLabel(s.count);
      final size = 12 * k;
      final width = font.stringMetrics(label).advanceWidth * size;
      _color(c.onInverse);
      _string(font, size, label, badge.center.dx - width / 2, badge.center.dy + size * 0.35);
    }
  }

  Future<void> _frame(FrameItem f) async {
    if (f.template != null) {
      // A template's layout is drawn by the app's own painter.
      final local = FrameItem(id: f.id, x: 0, y: 0, z: f.z, createdAt: f.createdAt, w: f.w, h: f.h, paper: f.paper, title: f.title, template: f.template, unit: f.unit);
      await _raster(f.paintRect, (canvas) => paintBoxItem(canvas, local, ui.Brightness.light, c));
      return;
    }
    final font = await _font(FontFamilies.ui, semiBold: true);
    _color(c.textMuted);
    _string(font, 16, frameLabel(f), 0, -12);
    _color(c.surface);
    g
      ..drawRect(0, 0, f.w, f.h)
      ..fillPath();
    _color(c.line);
    g
      ..setLineWidth(1)
      ..drawRect(0, 0, f.w, f.h)
      ..strokePath();
    final u = f.unit;
    g.saveContext();
    g
      ..drawRect(0, 0, f.w, f.h)
      ..clipPath();
    switch (f.paper) {
      case 'lined-a4':
        _color(c.paperLine);
        g.setLineWidth(1.4 * u);
        var lines = 0;
        for (var y = 96 * u; y < f.h; y += 40 * u) {
          g
            ..moveTo(0, y)
            ..lineTo(f.w, y);
          lines++;
        }
        if (lines > 0) g.strokePath();
        _color(c.paperMargin);
        g
          ..setLineWidth(2 * u)
          ..moveTo(80 * u, 0)
          ..lineTo(80 * u, f.h)
          ..strokePath();
      case 'grid-a4':
        _rules(Offset.zero & Size(f.w, f.h), Paper.grid, 32 * u, Offset(32 * u, 32 * u));
      case 'dots-a4':
        const step = Sizes.paperDotSpacing;
        _rules(Offset.zero & Size(f.w, f.h), Paper.dots, step * u, Offset(step * u / 2, step * u / 2));
    }
    g.restoreContext();
  }

  /// The page's own paper over [sheet], placed as the canvas places it.
  void _paper(Paper paper, Rect sheet) {
    const origin = Sizes.paperDotSpacing / 2;
    switch (paper) {
      case Paper.dots:
        _rules(sheet, paper, Sizes.paperDotSpacing, const Offset(origin, origin));
      case Paper.grid:
        _rules(sheet, paper, Sizes.paperDotSpacing, const Offset(origin, origin));
      case Paper.lines:
        _rules(sheet, paper, 32, const Offset(origin, origin));
        _color(c.paperMargin);
        g
          ..setLineWidth(1.5)
          ..moveTo(80, sheet.top)
          ..lineTo(80, sheet.bottom)
          ..strokePath();
      case Paper.blank:
        break;
    }
  }

  /// Dots, lines or a grid every [step] over [area], through [phase].
  void _rules(Rect area, Paper paper, double step, Offset phase) {
    if (step < 2) return;
    double first(double from, double p) => p + ((from - p) / step).ceil() * step;
    var drawn = 0;
    switch (paper) {
      case Paper.dots:
        _color(c.dot);
        final r = Sizes.paperDotRadius * step / Sizes.paperDotSpacing;
        for (var y = first(area.top, phase.dy); y < area.bottom; y += step) {
          for (var x = first(area.left, phase.dx); x < area.right; x += step) {
            g.drawEllipse(x, y, r, r);
            drawn++;
          }
        }
        if (drawn > 0) g.fillPath();
      case Paper.lines || Paper.grid:
        _color(paper == Paper.lines ? c.paperLine : c.paperGrid);
        g.setLineWidth(math.max(1, step / 32));
        for (var y = first(area.top, phase.dy); y < area.bottom; y += step) {
          g
            ..moveTo(area.left, y)
            ..lineTo(area.right, y);
          drawn++;
        }
        if (paper == Paper.grid) {
          for (var x = first(area.left, phase.dx); x < area.right; x += step) {
            g
              ..moveTo(x, area.top)
              ..lineTo(x, area.bottom);
            drawn++;
          }
        }
        if (drawn > 0) g.strokePath();
      case Paper.blank:
        break;
    }
  }

  // Pictures.

  /// Draws [image] upright over [rect] (current coordinates, y down).
  void _place(PdfImage image, Rect rect) {
    g.saveContext();
    _transform(Matrix4.identity()
      ..translateByDouble(rect.left, rect.bottom, 0, 1)
      ..scaleByDouble(1, -1, 1, 1));
    g.drawImage(image, 0, 0, rect.width, rect.height);
    g.restoreContext();
  }

  Future<void> _image(ImageItem i) async {
    final name = i.picture;
    final image = name.isEmpty ? null : (_images.containsKey(name) ? _images[name] : _images[name] = await _decode(name));
    final rect = Offset.zero & Size(i.w, i.h);
    if (image == null) {
      // Missing or still locked: show where it goes, as the canvas does.
      _color(c.menuTile);
      g
        ..drawRect(0, 0, i.w, i.h)
        ..fillPath();
      return;
    }
    _place(image, rect);
  }

  Future<PdfImage?> _decode(String name) async {
    final bytes = await readAsset(name);
    if (bytes == null) return null;
    try {
      if (bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) return PdfImage.jpeg(doc, image: bytes);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      final out = PdfImage(doc, image: data!.buffer.asUint8List(), width: image.width, height: image.height);
      image.dispose();
      return out;
    } on Object {
      return null;
    }
  }

  /// Paints [area] (current coordinates) with Flutter at 3× and places it.
  Future<void> _raster(Rect area, void Function(Canvas canvas) paint) async {
    const scale = 3.0;
    final w = (area.width * scale).ceil(), h = (area.height * scale).ceil();
    if (w <= 0 || h <= 0) return;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(scale)
      ..translate(-area.left, -area.top);
    paint(canvas);
    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    image.dispose();
    if (data == null) return;
    _place(PdfImage(doc, image: data.buffer.asUint8List(), width: w, height: h), area);
  }
}

/// A line of laid-out text: what it says, where it starts and its baseline.
class TextLine {
  const TextLine(this.text, this.left, this.baseline);

  final String text;
  final double left;
  final double baseline;
}

/// The lines [painter] broke [text] into.
List<TextLine> textLines(TextPainter painter, String text) {
  final metrics = painter.computeLineMetrics();
  final out = <TextLine>[];
  var start = 0;
  for (final m in metrics) {
    if (start > text.length) break;
    final range = painter.getLineBoundary(TextPosition(offset: math.min(start, text.length)));
    final end = math.max(range.end, start);
    out.add(TextLine(text.substring(math.min(start, text.length), math.min(end, text.length)).trimRight(), m.left, m.baseline));
    start = end;
    // Step over the line break, if the line ended with one.
    if (start < text.length && text[start] == '\n') start++;
  }
  return out;
}

/// Everything a card says, for search.
String cardText(CardItem card) {
  final parts = <String>[cardTitle(card)];
  switch (card.data) {
    case KanbanData d:
      for (final col in d.columns) {
        parts
          ..add(col.title)
          ..addAll(col.cards.map((c) => c.text));
      }
    case TimelineData d:
      for (final e in d.events) {
        parts.add('${e.date} ${e.label}');
      }
    case DiagramData d:
      parts.addAll(d.nodes.map((n) => n.text));
    case TableData d:
      for (final row in d.cells) {
        parts.add(row.join(' '));
      }
    case EmbedData d:
      parts.add(d.url);
  }
  return parts.where((p) => p.trim().isNotEmpty).join('\n');
}
