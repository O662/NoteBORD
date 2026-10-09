import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'docx_reader.dart';
import 'office_model.dart';
import 'ooxml.dart';
import 'pptx_reader.dart';
import 'xlsx_reader.dart';

/// Reads [bytes] as a [kind] file. Throws [OfficeReadError] if it can't.
OfficeDoc readOffice(Uint8List bytes, OfficeKind kind) {
  final pkg = OoxmlPackage(bytes);
  try {
    return switch (kind) {
      OfficeKind.docx => readDocx(pkg),
      OfficeKind.pptx => readPptx(pkg),
      OfficeKind.xlsx => readXlsx(pkg),
    };
  } on OfficeReadError {
    rethrow;
  } on Object {
    throw OfficeReadError('This ${kind.noun} can’t be read. It may be damaged.');
  }
}

/// [readOffice] on a background isolate, so a big file doesn't hold up
/// the pen.
Future<OfficeDoc> readOfficeInBackground(Uint8List bytes, OfficeKind kind) =>
    Isolate.run(() => readOffice(bytes, kind), debugName: 'read ${kind.badge}');

/// What kind of Office file [bytes] is, from what's inside the zip (Word,
/// PowerPoint and Excel files are zips with their own main part), or null.
OfficeKind? officeKindOf(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) return null;
  try {
    final zip = ZipDecoder().decodeBytes(bytes);
    bool has(String path) => zip.findFile(path) != null;
    if (has('word/document.xml')) return OfficeKind.docx;
    if (has('ppt/presentation.xml')) return OfficeKind.pptx;
    if (has('xl/workbook.xml')) return OfficeKind.xlsx;
    // A main part somewhere else: the package's own relationships say.
    final rels = zip.findFile('_rels/.rels')?.readBytes();
    if (rels == null) return null;
    final text = String.fromCharCodes(rels);
    if (text.contains('word/')) return OfficeKind.docx;
    if (text.contains('ppt/')) return OfficeKind.pptx;
    if (text.contains('xl/')) return OfficeKind.xlsx;
  } on Object {
    return null;
  }
  return null;
}

/// The extensions of the Office files the board shows.
const officeExtensions = ['docx', 'pptx', 'xlsx'];
