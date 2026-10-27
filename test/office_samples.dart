import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

// Small Word, PowerPoint and Excel files built by hand, for what the
// generated files in test/fixtures/office don't cover: fields, groups,
// hidden and deleted text, a slide number, a page break.

/// The generated sample files (python-docx, python-pptx and openpyxl, which
/// use Office's own templates): "Lab 4 report.docx", "Ch 9 slides.pptx",
/// "Lab data.xlsx".
Uint8List officeFixture(String name) => File('test/fixtures/office/$name').readAsBytesSync();

Uint8List _zip(Map<String, String> parts) {
  final archive = Archive();
  for (final e in parts.entries) {
    final bytes = utf8.encode(e.value);
    archive.addFile(ArchiveFile.bytes(e.key, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

const _xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
const _rel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _pkgRel = 'http://schemas.openxmlformats.org/package/2006/relationships';

String _rels(Map<String, (String, String)> rels) => '$_xml<Relationships xmlns="$_pkgRel">'
    '${rels.entries.map((e) => '<Relationship Id="${e.key}" Type="$_rel/${e.value.$1}" Target="${e.value.$2}"/>').join()}'
    '</Relationships>';

/// "Lab data.xlsx" as on Board.png, plus a sheet of dates.
Uint8List sampleXlsx() {
  const s = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  String cell(String ref, Object v, {int style = 0}) => v is String
      ? '<c r="$ref" t="s"><v>${_strings.indexOf(v)}</v></c>'
      : '<c r="$ref"${style == 0 ? '' : ' s="$style"'}><v>$v</v></c>';
  final sheet1 = '$_xml<worksheet xmlns="$s" xmlns:r="$_rel"><sheetData>'
      '<row r="1">${cell('A1', 'Trial')}${cell('B1', 'm')}${cell('C1', 'v')}${cell('D1', 'p')}</row>'
      '<row r="2">${cell('A2', 1)}${cell('B2', 0.5, style: 1)}${cell('C2', 2, style: 2)}${cell('D2', 1, style: 1)}</row>'
      '<row r="3">${cell('A3', 2)}${cell('B3', 0.5, style: 1)}${cell('C3', 1.6, style: 2)}${cell('D3', 0.8, style: 1)}</row>'
      '<row r="4">${cell('A4', 3)}${cell('B4', 1, style: 1)}${cell('C4', 1, style: 2)}<c r="D4" s="1"><f>B4*C4</f><v>1</v></c></row>'
      '</sheetData></worksheet>';
  final sheet2 = '$_xml<worksheet xmlns="$s" xmlns:r="$_rel"><cols><col min="2" max="2" width="20" customWidth="1"/></cols><sheetData>'
      '<row r="1">${cell('A1', 'When')}${cell('B1', 'What')}${cell('C1', 'Share')}</row>'
      '<row r="2">${cell('A2', 46295, style: 3)}${cell('B2', 'Lab report')}${cell('C2', 0.25, style: 4)}</row>'
      '<row r="3">${cell('A3', 46309, style: 3)}<c r="B3" t="inlineStr"><is><t>Midterm</t></is></c>${cell('C3', 0.4, style: 4)}</row>'
      '<row r="4"><c r="A4"/></row>'
      '</sheetData></worksheet>';
  return _zip({
    '[Content_Types].xml': '$_xml<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>',
    '_rels/.rels': _rels({'rId1': ('officeDocument', 'xl/workbook.xml')}),
    'xl/workbook.xml': '$_xml<workbook xmlns="$s" xmlns:r="$_rel"><sheets>'
        '<sheet name="Sheet1" sheetId="1" r:id="rId1"/><sheet name="Hidden" sheetId="3" state="hidden" r:id="rId5"/>'
        '<sheet name="Dates" sheetId="2" r:id="rId2"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels': _rels({
      'rId1': ('worksheet', 'worksheets/sheet1.xml'),
      'rId2': ('worksheet', 'worksheets/sheet2.xml'),
      'rId5': ('worksheet', 'worksheets/sheet1.xml'),
      'rId3': ('sharedStrings', 'sharedStrings.xml'),
      'rId4': ('styles', 'styles.xml'),
    }),
    'xl/sharedStrings.xml': '$_xml<sst xmlns="$s">${_strings.map((t) => '<si><t>$t</t></si>').join()}</sst>',
    'xl/styles.xml': '$_xml<styleSheet xmlns="$s"><numFmts><numFmt numFmtId="164" formatCode="0.0"/></numFmts>'
        '<fonts><font/><font><b/></font></fonts>'
        '<cellXfs><xf numFmtId="0" fontId="0"/><xf numFmtId="2" fontId="0"/><xf numFmtId="164" fontId="0"/>'
        '<xf numFmtId="14" fontId="0"/><xf numFmtId="9" fontId="0"/></cellXfs></styleSheet>',
    'xl/worksheets/sheet1.xml': sheet1,
    'xl/worksheets/sheet2.xml': sheet2,
  });
}

const _strings = ['Trial', 'm', 'v', 'p', 'When', 'What', 'Share', 'Lab report'];

/// Charts.png's "Lab data.xlsx": momentum before and after for six trials
/// (and a seventh, with [seventh]), to two places.
Uint8List momentumXlsx({bool seventh = false}) {
  const s = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  const strings = ['Trial', 'p before', 'p after'];
  const rows = [
    [1, 1.00, 0.97],
    [2, 0.80, 0.78],
    [3, 1.20, 1.15],
    [4, 0.90, 0.88],
    [5, 1.10, 1.06],
    [6, 1.00, 0.95],
    [7, 1.30, 1.24],
  ];
  final sheet = StringBuffer('$_xml<worksheet xmlns="$s" xmlns:r="$_rel"><sheetData><row r="1">');
  for (var i = 0; i < strings.length; i++) {
    sheet.write('<c r="${'ABC'[i]}1" t="s"><v>$i</v></c>');
  }
  sheet.write('</row>');
  for (final (r, row) in rows.take(seventh ? 7 : 6).indexed) {
    sheet.write('<row r="${r + 2}"><c r="A${r + 2}"><v>${row[0]}</v></c>'
        '<c r="B${r + 2}" s="1"><v>${row[1]}</v></c><c r="C${r + 2}" s="1"><v>${row[2]}</v></c></row>');
  }
  sheet.write('</sheetData></worksheet>');
  return _zip({
    '[Content_Types].xml': '$_xml<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>',
    '_rels/.rels': _rels({'rId1': ('officeDocument', 'xl/workbook.xml')}),
    'xl/workbook.xml': '$_xml<workbook xmlns="$s" xmlns:r="$_rel"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels': _rels({
      'rId1': ('worksheet', 'worksheets/sheet1.xml'),
      'rId3': ('sharedStrings', 'sharedStrings.xml'),
      'rId4': ('styles', 'styles.xml'),
    }),
    'xl/sharedStrings.xml': '$_xml<sst xmlns="$s">${strings.map((t) => '<si><t>$t</t></si>').join()}</sst>',
    'xl/styles.xml': '$_xml<styleSheet xmlns="$s"><fonts><font/></fonts>'
        '<cellXfs><xf numFmtId="0" fontId="0"/><xf numFmtId="2" fontId="0"/></cellXfs></styleSheet>',
    'xl/worksheets/sheet1.xml': sheet.toString(),
  });
}

/// Three slides drawn without a layout: a title (id 256), bullets (257),
/// and a dark slide with a slide number and a group (258). [order] lists the
/// slides' ids in the order the deck shows them: a newer version can move
/// and drop slides.
Uint8List samplePptx({List<int> order = const [256, 257, 258]}) {
  const a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
  const p = 'http://schemas.openxmlformats.org/presentationml/2006/main';
  String pt(num v) => '${(v * 12700).round()}';
  String box(int id, num x, num y, num w, num h, String body) => '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="Box $id"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
      '<p:spPr><a:xfrm><a:off x="${pt(x)}" y="${pt(y)}"/><a:ext cx="${pt(w)}" cy="${pt(h)}"/></a:xfrm><a:prstGeom prst="rect"/></p:spPr>'
      '<p:txBody><a:bodyPr/><a:lstStyle/>$body</p:txBody></p:sp>';
  String run(String t, {int size = 1800, String color = '000000', bool bold = false}) =>
      '<a:r><a:rPr lang="en-US" sz="$size"${bold ? ' b="1"' : ''}><a:solidFill><a:srgbClr val="$color"/></a:solidFill></a:rPr><a:t>$t</a:t></a:r>';
  String slide(String tree, {String bg = ''}) => '$_xml<p:sld xmlns:a="$a" xmlns:p="$p" xmlns:r="$_rel"><p:cSld>$bg<p:spTree>'
      '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>$tree</p:spTree></p:cSld></p:sld>';
  final s1 = slide(box(2, 80, 200, 800, 120, '<a:p><a:pPr algn="ctr"/>${run('Chapter 9: Momentum', size: 4400, bold: true)}</a:p>'));
  final s2 = slide(box(2, 60, 40, 840, 80, '<a:p>${run('Impulse', size: 3600, bold: true)}</a:p>') +
      box(3, 60, 140, 840, 340,
          '<a:p><a:pPr marL="342900" indent="-342900"><a:buChar char="•"/></a:pPr>${run('Impulse = force × time', size: 2800)}</a:p>'
          '<a:p><a:pPr marL="742950" lvl="1" indent="-285750"><a:buChar char="–"/></a:pPr>${run('Same as the change in momentum', size: 2400)}</a:p>'
          '<a:p><a:pPr marL="342900" indent="-342900"><a:buAutoNum type="arabicPeriod"/></a:pPr>${run('Measured in N·s', size: 2800)}</a:p>'));
  final group = '<p:grpSp><p:nvGrpSpPr><p:cNvPr id="9" name="Group"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
      '<p:grpSpPr><a:xfrm><a:off x="${pt(100)}" y="${pt(100)}"/><a:ext cx="${pt(100)}" cy="${pt(100)}"/>'
      '<a:chOff x="0" y="0"/><a:chExt cx="${pt(200)}" cy="${pt(200)}"/></a:xfrm></p:grpSpPr>'
      '${box(10, 50, 0, 100, 50, '<a:p>${run('In a group', color: 'F6F1E7')}</a:p>')}</p:grpSp>';
  final s3 = slide(
    box(2, 60, 40, 600, 60, '<a:p>${run('Elastic vs. inelastic', size: 3200, color: 'F6F1E7', bold: true)}</a:p>') +
        box(3, 760, 480, 160, 40, '<a:p><a:pPr algn="r"/>${run('Slide ', size: 1400, color: '8E96A5')}<a:fld id="{1}" type="slidenum"><a:rPr lang="en-US" sz="1400"><a:solidFill><a:srgbClr val="8E96A5"/></a:solidFill></a:rPr><a:t>‹#›</a:t></a:fld></a:p>') +
        group,
    bg: '<p:bg><p:bgPr><a:solidFill><a:srgbClr val="2E3440"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>',
  );
  return _zip({
    '[Content_Types].xml': '$_xml<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>',
    '_rels/.rels': _rels({'rId1': ('officeDocument', 'ppt/presentation.xml')}),
    'ppt/presentation.xml': '$_xml<p:presentation xmlns:a="$a" xmlns:p="$p" xmlns:r="$_rel">'
        '<p:sldIdLst>${order.map((id) => '<p:sldId id="$id" r:id="rId${id - 254}"/>').join()}</p:sldIdLst>'
        '<p:sldSz cx="12192000" cy="6858000"/></p:presentation>',
    'ppt/_rels/presentation.xml.rels': _rels({
      'rId2': ('slide', 'slides/slide1.xml'),
      'rId3': ('slide', 'slides/slide2.xml'),
      'rId4': ('slide', 'slides/slide3.xml'),
    }),
    'ppt/slides/slide1.xml': s1,
    'ppt/slides/slide2.xml': s2,
    'ppt/slides/slide3.xml': s3,
  });
}

/// A short A4 document with a field, hidden and deleted text, and a page
/// break.
Uint8List sampleDocx() {
  const w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
  String para(String runs, {String pPr = ''}) => '<w:p>${pPr.isEmpty ? '' : '<w:pPr>$pPr</w:pPr>'}$runs</w:p>';
  String run(String t, {String rPr = ''}) => '<w:r>${rPr.isEmpty ? '' : '<w:rPr>$rPr</w:rPr>'}<w:t xml:space="preserve">$t</w:t></w:r>';
  final body = [
    para(run('Collisions', rPr: '<w:b/><w:sz w:val="40"/>'), pPr: '<w:jc w:val="center"/>'),
    para('${run('Page ')}<w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>'
        '<w:r><w:fldChar w:fldCharType="separate"/></w:r>${run('7')}<w:r><w:fldChar w:fldCharType="end"/></w:r>${run(' of the report')}'),
    para('${run('Shown')}${run(' hidden', rPr: '<w:vanish/>')}<w:del w:id="1" w:author="x"><w:r><w:delText>deleted</w:delText></w:r></w:del>'
        '<w:ins w:id="2" w:author="x">${run(' and inserted')}</w:ins>'),
    para('${run('Before the break')}<w:r><w:br w:type="page"/></w:r>${run('After the break')}'),
    para(run('Momentum before equals momentum after. ' * 6)),
  ].join();
  return _zip({
    '[Content_Types].xml': '$_xml<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>',
    '_rels/.rels': _rels({'rId1': ('officeDocument', 'word/document.xml')}),
    'word/document.xml': '$_xml<w:document xmlns:w="$w" xmlns:r="$_rel"><w:body>$body'
        '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr>'
        '</w:body></w:document>',
  });
}
