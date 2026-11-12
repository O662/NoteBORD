import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../board/model.dart';
import '../canvas/clusters.dart';
import 'pdf_export.dart';

// Print layout (Update 04, PrintLayout.png): page-shaped boxes over the
// endless page. What's inside a box prints on that sheet, in the boxes'
// order. A box is the whole sheet; one page px is one point at 100%, so a
// bigger box prints the ink smaller ("prints your ink at 107% of its real
// size"). Saved per page in notebook.json (`print`), so printing again
// reuses it.

/// One sheet: its top-left and width on the page (page px), and which way
/// the paper is turned. Its height follows from the paper's shape.
@immutable
class PrintBox {
  const PrintBox(this.left, this.top, this.width, {this.landscape = false});

  final double left;
  final double top;
  final double width;
  final bool landscape;

  /// The paper's height over its width, turned as this box is.
  double aspect(PaperSize paper) {
    final s = paper.size;
    return landscape ? s.width / s.height : s.height / s.width;
  }

  Rect rect(PaperSize paper) => Rect.fromLTWH(left, top, width, width * aspect(paper));

  /// The sheet (points), turned as this box is.
  Size sheet(PaperSize paper) => landscape ? Size(paper.size.height, paper.size.width) : paper.size;

  /// How big the ink prints, against its real size (1 = 100%).
  double scale(PaperSize paper) => sheet(paper).width / width;

  PrintBox moved(Offset by) => PrintBox(left + by.dx, top + by.dy, width, landscape: landscape);

  /// [width] kept to 25%–400% of real size.
  PrintBox sized(double width, PaperSize paper) {
    final real = sheet(paper).width;
    return PrintBox(left, top, width.clamp(real / 4, real * 4).toDouble(), landscape: landscape);
  }

  /// Turned, around its middle, keeping its scale.
  PrintBox turned(PaperSize paper) {
    final r = rect(paper);
    final w = landscape ? paper.size.width / scale(paper) : paper.size.height / scale(paper);
    final h = w * (landscape ? paper.size.height / paper.size.width : paper.size.width / paper.size.height);
    return PrintBox(r.center.dx - w / 2, r.center.dy - h / 2, w, landscape: !landscape);
  }

  Map<String, Object> toJson() => {
        'x': double.parse(left.toStringAsFixed(1)),
        'y': double.parse(top.toStringAsFixed(1)),
        'w': double.parse(width.toStringAsFixed(1)),
        if (landscape) 'landscape': true,
      };

  static PrintBox? fromJson(Object? j) {
    if (j is! Map) return null;
    final x = j['x'], y = j['y'], w = j['w'];
    if (x is! num || y is! num || w is! num || w <= 0) return null;
    return PrintBox(x.toDouble(), y.toDouble(), w.toDouble(), landscape: j['landscape'] == true);
  }

  @override
  bool operator ==(Object other) =>
      other is PrintBox && other.left == left && other.top == top && other.width == width && other.landscape == landscape;

  @override
  int get hashCode => Object.hash(left, top, width, landscape);
}

@immutable
class PrintLayout {
  const PrintLayout({
    this.paper = PaperSize.a4,
    this.boxes = const [],
    this.header = true,
    this.numbers = true,
    this.background = false,
  });

  final PaperSize paper;
  final List<PrintBox> boxes;

  /// On every page: the notebook's title and the date, page numbers, and
  /// the dot grid.
  final bool header;
  final bool numbers;
  final bool background;

  PrintLayout copyWith({PaperSize? paper, List<PrintBox>? boxes, bool? header, bool? numbers, bool? background}) => PrintLayout(
        paper: paper ?? this.paper,
        boxes: boxes ?? this.boxes,
        header: header ?? this.header,
        numbers: numbers ?? this.numbers,
        background: background ?? this.background,
      );

  /// What's on [page] that no box covers (an item is on a sheet when its
  /// middle is inside the box).
  List<Item> notCovered(BoardPage page) => [
        for (final i in page.items)
          if (_printable(i) && !boxes.any((b) => b.rect(paper).contains(i.bounds.center))) i,
      ];

  /// The items each box prints, in order.
  List<List<Item>> contents(BoardPage page) => [
        for (final b in boxes)
          [
            for (final i in page.items)
              if (_printable(i) && b.rect(paper).contains(i.bounds.center)) i,
          ],
      ];

  /// The PDF's sheets, one a box.
  List<PdfSheet> sheets() => [
        for (final b in boxes) PdfSheet(b.rect(paper), b.sheet(paper)),
      ];

  Map<String, Object> toJson() => {
        'paper': paper.name,
        'boxes': [for (final b in boxes) b.toJson()],
        'header': header,
        'numbers': numbers,
        'background': background,
      };

  static PrintLayout? fromJson(Object? j) {
    if (j is! Map) return null;
    return PrintLayout(
      paper: PaperSize.values.where((p) => p.name == j['paper']).firstOrNull ?? PaperSize.a4,
      boxes: [for (final b in (j['boxes'] as List?) ?? const []) ?PrintBox.fromJson(b)],
      header: j['header'] != false,
      numbers: j['numbers'] != false,
      background: j['background'] == true,
    );
  }

  /// "Lay out pages for me": a box around each group of things on [page],
  /// in reading order, at real size where the group fits (shrunk to fit
  /// where it doesn't), turned sideways for a wide group.
  static PrintLayout auto(BoardPage page, {PaperSize paper = PaperSize.a4, PrintLayout? keep}) {
    final base = keep ?? PrintLayout(paper: paper);
    return base.copyWith(paper: paper, boxes: boxesAround([for (final i in page.items) if (_printable(i)) i], paper));
  }

  /// "Add pages for them": [base]'s boxes, then boxes around what's left out.
  PrintLayout addingFor(BoardPage page) => copyWith(boxes: [...boxes, ...boxesAround(notCovered(page), paper)]);

  /// Boxes around [items]: grouped (things close together on one sheet),
  /// each group at real size or, when it's bigger than the sheet, as big
  /// as it needs.
  static List<PrintBox> boxesAround(List<Item> items, PaperSize paper) {
    if (items.isEmpty) return const [];
    const pad = 36.0;
    final groups = _groups(clustersOf(items, gap: 60), paper, pad);
    return [
      for (final g in groups) _boxFor(g, paper, pad),
    ];
  }

  /// Clusters merged while they still fit on one real-size sheet together,
  /// in reading order (top to bottom, then left to right).
  static List<Rect> _groups(List<Rect> clusters, PaperSize paper, double pad) {
    final list = [...clusters]..sort((a, b) => (a.top - b.top).abs() < 40 ? a.left.compareTo(b.left) : a.top.compareTo(b.top));
    final out = <Rect>[];
    for (final r in list) {
      final i = out.indexWhere((g) => _fits(g.expandToInclude(r), paper, pad));
      if (i >= 0) {
        out[i] = out[i].expandToInclude(r);
      } else {
        out.add(r);
      }
    }
    return out..sort((a, b) => (a.top - b.top).abs() < 40 ? a.left.compareTo(b.left) : a.top.compareTo(b.top));
  }

  static bool _fits(Rect r, PaperSize paper, double pad) {
    final s = paper.size;
    final w = r.width + 2 * pad, h = r.height + 2 * pad;
    return (w <= s.width && h <= s.height) || (w <= s.height && h <= s.width);
  }

  static PrintBox _boxFor(Rect r, PaperSize paper, double pad) {
    final landscape = r.width > r.height;
    final sheet = landscape ? Size(paper.size.height, paper.size.width) : paper.size;
    final aspect = sheet.height / sheet.width;
    final w = math.max(sheet.width, math.max(r.width + 2 * pad, (r.height + 2 * pad) / aspect));
    final h = w * aspect;
    return PrintBox(r.center.dx - w / 2, r.center.dy - h / 2, w, landscape: landscape);
  }
}

/// Things that print (flashcards aren't drawn in a PDF).
bool _printable(Item i) => i is! FlashcardItem && i is! UnknownItem;
