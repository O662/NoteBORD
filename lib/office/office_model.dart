// What Endless reads out of a Word, PowerPoint or Excel file to draw its
// preview on the board (docs/SPEC.md Phase 4b). Plain values only (colors
// are ARGB ints, sizes are points), so a file can be read on a background
// isolate and handed back.

/// The three Office file types the board shows.
enum OfficeKind {
  docx('DOCX', 'Word document'),
  pptx('PPTX', 'PowerPoint'),
  xlsx('XLSX', 'Excel sheet');

  const OfficeKind(this.badge, this.noun);

  /// The letters on the card's badge.
  final String badge;

  /// What it is called in a sentence.
  final String noun;

  /// The file's MIME type, for opening it in its own app.
  String get mimeType => switch (this) {
        OfficeKind.docx => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        OfficeKind.pptx => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        OfficeKind.xlsx => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      };

  /// From a `file` item's `mime` (`docx`, `pptx`, `xlsx`), or null.
  static OfficeKind? of(String mime) => switch (mime) {
        'docx' => OfficeKind.docx,
        'pptx' => OfficeKind.pptx,
        'xlsx' => OfficeKind.xlsx,
        _ => null,
      };
}

/// A rectangle in points.
class ORect {
  const ORect(this.x, this.y, this.w, this.h);

  final double x;
  final double y;
  final double w;
  final double h;

  static const zero = ORect(0, 0, 0, 0);
}

/// A run of text with one look. [size] is in points.
class ORun {
  const ORun(
    this.text, {
    this.size = 11,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.color = 0xFF000000,
    this.serif = false,
    this.highlight,
    this.raised = false,
  });

  final String text;
  final double size;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final int color;

  /// Set in a serif typeface in the file (Times, Georgia, Cambria…): drawn
  /// in Newsreader. Everything else is drawn in Figtree.
  final bool serif;

  /// A background color behind the text (Word's highlighter), or null.
  final int? highlight;

  /// Superscript.
  final bool raised;
}

/// A paragraph: its runs and how it sits.
class OPara {
  const OPara(
    this.runs, {
    this.align = 'l',
    this.indent = 0,
    this.rightIndent = 0,
    this.bullet,
    this.bulletIndent = 0,
    this.spaceBefore = 0,
    this.spaceAfter = 0,
    this.lineHeight = 1.2,
    this.emptySize = 11,
    this.bulletColor,
  });

  final List<ORun> runs;

  /// `l`, `ctr`, `r` or `just`.
  final String align;

  /// Where the text starts, from the left edge of its frame (points).
  final double indent;
  final double rightIndent;

  /// The bullet or number before it ("•", "3."), or null.
  final String? bullet;

  /// Where the bullet starts, from the left edge of its frame.
  final double bulletIndent;
  final int? bulletColor;
  final double spaceBefore;
  final double spaceAfter;

  /// Line height as a multiple of the font size.
  final double lineHeight;

  /// The font size of an empty paragraph (its height).
  final double emptySize;

  String get text => runs.map((r) => r.text).join();
}

/// Text inside a box: insets, where it sits, and its paragraphs.
class OText {
  const OText(
    this.paragraphs, {
    this.left = 7.2,
    this.top = 3.6,
    this.right = 7.2,
    this.bottom = 3.6,
    this.anchor = 't',
    this.wrap = true,
  });

  final List<OPara> paragraphs;
  final double left;
  final double top;
  final double right;
  final double bottom;

  /// `t`, `ctr` or `b`.
  final String anchor;
  final bool wrap;

  String get text => paragraphs.map((p) => p.text).join('\n');
}

/// A document the board can show.
sealed class OfficeDoc {
  const OfficeDoc();

  OfficeKind get kind;
}

// PowerPoint.

/// A fill: a color, or a picture from the file stretched over the box.
class OFill {
  const OFill({this.color, this.media});

  final int? color;

  /// A picture's path inside the file (`ppt/media/image1.png`).
  final String? media;
}

/// Something on a slide, in slide points.
sealed class SlideNode {
  const SlideNode(this.frame, {this.rotation = 0, this.flipH = false, this.flipV = false});

  final ORect frame;

  /// Degrees, clockwise.
  final double rotation;
  final bool flipH;
  final bool flipV;
}

/// A path of a custom shape, in the shape's own units (`w` × `h`).
class OPath {
  const OPath(this.w, this.h, this.commands, {this.filled = true, this.stroked = true});

  final double w;
  final double h;

  /// `M x y`, `L x y`, `C x1 y1 x2 y2 x y`, `Q x1 y1 x y` and `Z`, as a flat
  /// list: a command letter's code unit, then its numbers.
  final List<double> commands;
  final bool filled;
  final bool stroked;
}

/// A shape: its outline ([geometry]: `rect`, `roundRect`, `ellipse`,
/// `triangle`, `line`, `custom`…), fill, line and text.
class SlideShape extends SlideNode {
  const SlideShape(
    super.frame, {
    super.rotation,
    super.flipH,
    super.flipV,
    this.geometry = 'rect',
    this.fill,
    this.line,
    this.lineWidth = 0.75,
    this.text,
    this.paths = const [],
    this.heads = 0,
  });

  final String geometry;
  final OFill? fill;
  final int? line;
  final double lineWidth;
  final OText? text;

  /// Arrowheads on a line: 1 at its start, 2 at its end, 3 at both.
  final int heads;

  /// The outline of a `custom` shape.
  final List<OPath> paths;
}

/// A picture. [crop] cuts fractions off each side (left, top, right, bottom).
class SlidePicture extends SlideNode {
  const SlidePicture(super.frame, this.media, {super.rotation, super.flipH, super.flipV, this.crop = const [0, 0, 0, 0]});

  final String media;
  final List<double> crop;
}

/// A table on a slide.
class SlideTable extends SlideNode {
  const SlideTable(super.frame, this.columns, this.rows);

  /// Column widths, in points.
  final List<double> columns;
  final List<SlideRow> rows;
}

class SlideRow {
  const SlideRow(this.height, this.cells);

  final double height;
  final List<SlideCell> cells;
}

class SlideCell {
  const SlideCell(this.text, {this.fill, this.span = 1, this.hidden = false});

  final OText text;
  final int? fill;
  final int span;

  /// Covered by a merged cell.
  final bool hidden;
}

/// Something this version doesn't draw (a chart, a video): a labelled box.
class SlideStandIn extends SlideNode {
  const SlideStandIn(super.frame, this.label);

  final String label;
}

class Slide {
  const Slide(this.nodes, {this.background});

  final List<SlideNode> nodes;
  final OFill? background;

  /// Everything the slide says, for search.
  String get text => [
        for (final n in nodes)
          switch (n) {
            SlideShape s => s.text?.text ?? '',
            SlideTable t => [for (final r in t.rows) for (final c in r.cells) c.text.text].join(' '),
            _ => '',
          },
      ].where((t) => t.trim().isNotEmpty).join('\n');
}

class Deck extends OfficeDoc {
  const Deck(this.width, this.height, this.slides);

  /// Slide size in points (a 16:9 deck is 960 × 540).
  final double width;
  final double height;
  final List<Slide> slides;

  @override
  OfficeKind get kind => OfficeKind.pptx;
}

// Word.

/// What a Word document is made of, top to bottom.
sealed class WordBlock {
  const WordBlock();
}

class WordParagraph extends WordBlock {
  const WordParagraph(this.para, {this.pageBreakBefore = false});

  final OPara para;
  final bool pageBreakBefore;
}

/// A picture on a line of its own, [width] × [height] points.
class WordPicture extends WordBlock {
  const WordPicture(this.media, this.width, this.height, {this.align = 'l'});

  final String media;
  final double width;
  final double height;
  final String align;
}

/// Something this version doesn't draw (a chart): a labelled box.
class WordStandIn extends WordBlock {
  const WordStandIn(this.label, this.width, this.height);

  final String label;
  final double width;
  final double height;
}

class WordPageBreak extends WordBlock {
  const WordPageBreak();
}

class WordTable extends WordBlock {
  const WordTable(this.columns, this.rows);

  /// Column widths, in points.
  final List<double> columns;
  final List<WordRow> rows;
}

class WordRow {
  const WordRow(this.cells);

  final List<WordCell> cells;
}

class WordCell {
  const WordCell(this.paragraphs, {this.span = 1, this.fill, this.hidden = false});

  final List<OPara> paragraphs;
  final int span;
  final int? fill;

  /// Covered by the cell above it (merged down).
  final bool hidden;
}

class WordDoc extends OfficeDoc {
  const WordDoc({
    required this.blocks,
    this.pageWidth = 612,
    this.pageHeight = 792,
    this.marginLeft = 72,
    this.marginTop = 72,
    this.marginRight = 72,
    this.marginBottom = 72,
    this.background,
  });

  final List<WordBlock> blocks;

  /// The page and its margins, in points (Letter with 1" margins by default).
  final double pageWidth;
  final double pageHeight;
  final double marginLeft;
  final double marginTop;
  final double marginRight;
  final double marginBottom;
  final int? background;

  @override
  OfficeKind get kind => OfficeKind.docx;
}

// Excel.

class Sheet {
  const Sheet({
    required this.name,
    required this.cells,
    required this.columnWidths,
    this.bold = const {},
    this.header = false,
    this.moreRows = 0,
    this.moreColumns = 0,
  });

  final String name;

  /// Rows of cells as Excel shows them ("0.50", "9/30/2026"); '' when empty.
  final List<List<String>> cells;

  /// Each column's width, in Excel's pixels at 100%.
  final List<double> columnWidths;

  /// Cells in bold, as `row * 1000 + column`.
  final Set<int> bold;

  /// The first row names the columns.
  final bool header;

  /// Rows and columns past what was read.
  final int moreRows;
  final int moreColumns;

  int get rows => cells.length;
  int get columns => columnWidths.length;

  String get text => cells.map((r) => r.where((c) => c.isNotEmpty).join(' ')).where((r) => r.isNotEmpty).join('\n');
}

class Workbook extends OfficeDoc {
  const Workbook(this.sheets);

  final List<Sheet> sheets;

  @override
  OfficeKind get kind => OfficeKind.xlsx;
}

/// A file that isn't a Word, PowerPoint or Excel file Endless can read.
class OfficeReadError implements Exception {
  const OfficeReadError(this.message);

  final String message;

  @override
  String toString() => message;
}
