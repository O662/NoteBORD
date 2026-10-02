import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../board/model.dart';
import '../canvas/page_runtime.dart' show paintItem;
import '../templates/templates.dart';
import '../theme/tokens.g.dart';
import 'pdf_export.dart' show fitMargin, pageContent;

/// The longest side of an exported picture, in pixels.
const maxImageSide = 8192;

/// A PNG of [page] fitted to its ink, at [scale] pixels per page px, on
/// the page's own paper in the light palette. [images] are the decoded
/// pictures on it, by asset name.
Future<Uint8List> renderPagePng(BoardPage page, Map<String, ui.Image> images, {double scale = 2}) async {
  final area = pageContent(page)?.inflate(fitMargin) ?? const Rect.fromLTWH(0, 0, 800, 600);
  final k = math.min(scale, maxImageSide / math.max(area.width, area.height));
  final w = math.max(1, (area.width * k).ceil()), h = math.max(1, (area.height * k).ceil());
  const c = paperLight;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..scale(k)
    ..translate(-area.left, -area.top)
    ..drawRect(area, Paint()..color = c.bg);
  _paper(canvas, page.paper, area);
  final layout = layoutPicture(page.template, c);
  if (layout != null) canvas.drawPicture(layout);
  for (final item in page.items) {
    paintItem(canvas, item, ui.Brightness.light, c, images: (name) => images[name]);
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  picture.dispose();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Dots, lines or a grid, placed as the canvas places them.
void _paper(Canvas canvas, Paper paper, Rect area) {
  const c = paperLight;
  if (paper == Paper.blank) return;
  final step = paper == Paper.lines ? 32.0 : Sizes.paperDotSpacing;
  const origin = Sizes.paperDotSpacing / 2;
  double first(double from) => origin + ((from - origin) / step).ceil() * step;
  switch (paper) {
    case Paper.dots:
      final dot = Paint()..color = c.dot;
      for (var y = first(area.top); y < area.bottom; y += step) {
        for (var x = first(area.left); x < area.right; x += step) {
          canvas.drawCircle(Offset(x, y), Sizes.paperDotRadius, dot);
        }
      }
    case Paper.lines || Paper.grid:
      final line = Paint()
        ..color = paper == Paper.lines ? c.paperLine : c.paperGrid
        ..strokeWidth = 1;
      for (var y = first(area.top); y < area.bottom; y += step) {
        canvas.drawLine(Offset(area.left, y), Offset(area.right, y), line);
      }
      if (paper == Paper.grid) {
        for (var x = first(area.left); x < area.right; x += step) {
          canvas.drawLine(Offset(x, area.top), Offset(x, area.bottom), line);
        }
      } else {
        canvas.drawLine(
          Offset(80, area.top),
          Offset(80, area.bottom),
          Paint()
            ..color = c.paperMargin
            ..strokeWidth = 1.5,
        );
      }
    case Paper.blank:
      break;
  }
}
