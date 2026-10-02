import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show Size;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import 'board_file.dart' show ImportProblem;

// Reading PDFs for import: each page becomes a notebook page with a picture
// of it to write on (Export.dc.html, Import tab).

/// An open PDF.
abstract class PdfSource {
  int get pageCount;

  /// Page [index] (from 0) in points.
  Size pageSize(int index);

  /// A PNG of page [index], [scale] pixels per point, on white.
  Future<Uint8List> renderPng(int index, {required double scale});

  /// The text on page [index], for search ('' if it has none).
  Future<String> text(int index);

  Future<void> close();
}

abstract class PdfReader {
  /// Opens [bytes]; throws [ImportProblem] if it can't.
  Future<PdfSource> open(Uint8List bytes, {String name = ''});
}

/// PDFium, through pdfrx.
class PdfiumReader implements PdfReader {
  const PdfiumReader();

  @override
  Future<PdfSource> open(Uint8List bytes, {String name = ''}) async {
    await pdfrx.pdfrxFlutterInitialize();
    try {
      final doc = await pdfrx.PdfDocument.openData(bytes, sourceName: name.isEmpty ? 'import.pdf' : name);
      return _PdfiumSource(doc);
    } on pdfrx.PdfPasswordException {
      throw const ImportProblem('This PDF has a password. Open it elsewhere, save a copy without one, then import that.');
    } on Object {
      throw const ImportProblem('This PDF can’t be opened. It may be damaged.');
    }
  }
}

class _PdfiumSource implements PdfSource {
  _PdfiumSource(this.doc);

  final pdfrx.PdfDocument doc;

  @override
  int get pageCount => doc.pages.length;

  @override
  Size pageSize(int index) => Size(doc.pages[index].width, doc.pages[index].height);

  @override
  Future<Uint8List> renderPng(int index, {required double scale}) async {
    final page = doc.pages[index];
    final w = (page.width * scale).round(), h = (page.height * scale).round();
    final image = await page.render(fullWidth: w.toDouble(), fullHeight: h.toDouble(), width: w, height: h, backgroundColor: 0xFFFFFFFF);
    if (image == null) throw const ImportProblem('A page of this PDF couldn’t be drawn.');
    try {
      return await pngFromBgra(image.pixels, image.width, image.height);
    } finally {
      image.dispose();
    }
  }

  @override
  Future<String> text(int index) async {
    try {
      return (await doc.pages[index].loadText())?.fullText ?? '';
    } on Object {
      return '';
    }
  }

  @override
  Future<void> close() => doc.dispose();
}

/// Encodes BGRA pixels as a PNG file.
Future<Uint8List> pngFromBgra(Uint8List pixels, int width, int height) async {
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(pixels, width, height, ui.PixelFormat.bgra8888, done.complete);
  final image = await done.future;
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

final pdfReaderProvider = Provider<PdfReader>((ref) => const PdfiumReader());

/// Pixels per point for the picture of an imported page: sharp up to
/// about 200% zoom.
const pdfPreviewScale = 2.0;

/// The longest side of an imported page's picture, in pixels.
const maxPreviewSide = 4096.0;
