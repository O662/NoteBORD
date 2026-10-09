import 'dart:math' as math;
import 'dart:ui' as ui show Picture;
import 'dart:ui' show Brightness;

import 'package:flutter/painting.dart';

import '../board/ids.dart';
import '../board/model.dart';
import '../office/office_model.dart';
import '../office/office_render.dart';
import '../theme/colors.dart';
import '../theme/tokens.g.dart';
import '../ui/icons.dart';
import 'page_runtime.dart' show paintStroke;

// Word, PowerPoint and Excel files on the board (Board.dc.html: the DOCX,
// PPTX and XLSX cards). A header with the file-type badge, the name and
// Open; the page, slide or sheet; and, when there's more than one, a
// footer with where you are and arrows to step through.

/// What can be tapped on an Office card.
enum OfficeButton { open, previous, next }

/// Where the decoded files of an open notebook come from.
abstract interface class OfficeSource {
  /// The file ready to show, or null while it's read (or if it can't be).
  OfficePreview? preview(String asset, OfficeKind kind);

  /// The file is missing, locked or can't be read.
  bool unreadable(String asset);
}

/// Excel's pixels to the card's: a 64 px column is 55 wide, as on Board.png.
const _excelPx = 0.86;
const _rowHeight = 29.0;

TextPainter _text(String text, {required double size, FontWeight weight = FontWeight.w400, required Color color, double maxWidth = double.infinity, bool tabular = false}) =>
    TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: FontFamilies.ui,
          fontSize: size,
          fontWeight: weight,
          height: 1.2,
          color: color,
          fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(maxWidth, 0));

void _draw(Canvas canvas, TextPainter text, Offset at) {
  text.paint(canvas, at);
  text.dispose();
}

(Color, Color) _badgeColors(OfficeKind? kind, EndlessColors c) => switch (kind) {
      OfficeKind.pptx => (c.clayDeep, c.clayTint),
      OfficeKind.xlsx => (c.greenDeep, c.greenTint),
      _ => (c.accentDeep, c.accentTint),
    };

double? _openWidth;

/// The header's Open button and the footer's arrows, in the card's
/// unscaled px.
Map<OfficeButton, Rect> _buttons(OfficeItem f) {
  final u = f.unit;
  final w = f.w / u, h = f.h / u;
  final openW = _openWidth ??= () {
    final t = _text('Open', size: 12, weight: FontWeight.w600, color: const Color(0xFF000000));
    final width = t.width.ceilToDouble() + 20;
    t.dispose();
    return width;
  }();
  return {
    OfficeButton.open: Rect.fromLTWH(w - 8 - openW, 6, openW, 26),
    if (f.hasFooter) ...{
      OfficeButton.next: Rect.fromLTWH(w - 8 - 34, h - OfficeItem.footer + 4, 34, 28),
      OfficeButton.previous: Rect.fromLTWH(w - 8 - 34 - 2 - 34, h - OfficeItem.footer + 4, 34, 28),
    },
  };
}

/// The button at [local] (relative to the card's top-left corner, before
/// its rotation, in page px), or null. The areas reach a little past what's
/// drawn, so they're easy to hit.
OfficeButton? officeButtonAt(OfficeItem f, Offset local) {
  final u = f.unit;
  final p = local / u;
  for (final e in _buttons(f).entries) {
    if (e.value.inflate(5).contains(p)) return e.key;
  }
  return null;
}

/// "Slide 3 of 24", "Page 2 of 5", "Sheet1 · 2 of 3".
String officePlace(OfficeItem f, {OfficePreview? preview}) {
  final count = preview?.pageCount ?? f.pages;
  final page = f.page.clamp(1, math.max(count, 1)).toInt();
  return switch (f.kind) {
    OfficeKind.pptx => 'Slide $page of $count',
    OfficeKind.xlsx => '${preview?.sheet(page)?.name ?? 'Sheet'} · $page of $count',
    _ => 'Page $page of $count',
  };
}

/// The name in the header: the file's, or what it is.
String officeTitle(OfficeItem f) => f.name.isNotEmpty ? f.name : (f.kind?.noun ?? 'File');

final _localInk = Expando<List<StrokeItem>>('officeInk');

/// The ink on the page showing, relative to the card's top-left corner.
List<StrokeItem> officeInk(OfficeItem f) => _localInk[f] ??= () {
      final fit = f.contentFit;
      return [for (final s in f.ink) s.mapped((p) => fit.origin + p * fit.scale, widthScale: fit.scale)];
    }();

/// Where ink on a card shows: between its header and footer.
Rect officeInkArea(OfficeItem f) =>
    Rect.fromLTRB(0, OfficeItem.header * f.unit, f.w, f.h - (f.hasFooter ? OfficeItem.footer * f.unit : 0));

/// One file, already read, as an [OfficeSource] (for exports).
class SingleOffice implements OfficeSource {
  const SingleOffice(this.file);

  final OfficePreview? file;

  @override
  OfficePreview? preview(String asset, OfficeKind kind) => file;

  @override
  bool unreadable(String asset) => file == null;
}

/// Draws an Office card with its top-left corner at the origin (after the
/// item's move and rotation), and the ink on it unless [ink] is false.
void paintOfficeCard(Canvas canvas, OfficeItem f, Brightness brightness, EndlessColors c, OfficeSource? docs, {bool ink = true}) {
  final u = f.unit;
  final kind = f.kind;
  final preview = kind == null ? null : docs?.preview(f.asset, kind);
  final unreadable = preview == null && (docs?.unreadable(f.asset) ?? false);
  final card = RRect.fromRectAndRadius(Offset.zero & Size(f.w, f.h), Radius.circular(12 * u));
  if (math.min(f.w, f.h) > 40 * u) {
    // 0 12px 24px -18px shadow
    canvas.drawRRect(
      card.deflate(18 * u).shift(Offset(0, 12 * u)),
      Paint()
        ..color = c.shadow
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12 * u),
    );
  }
  canvas
    ..drawRRect(card, Paint()..color = c.surface)
    ..save()
    ..clipRRect(card);

  // The page, slide or sheet.
  final area = f.previewArea;
  switch (kind) {
    case OfficeKind.docx:
      canvas.drawRect(area, Paint()..color = c.menuTile);
      final page = f.pageRect;
      final picture = preview?.picture(f.page);
      canvas.drawRect(
        page.shift(Offset(0, 2 * u)),
        Paint()
          ..color = c.shadow.withValues(alpha: c.shadow.a * 0.5)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * u),
      );
      if (picture != null) {
        _drawPage(canvas, picture, f);
      } else {
        canvas.drawRect(page, Paint()..color = const Color(0xFFFFFFFF));
        _waiting(canvas, page, c, unreadable, u, onPaper: true);
      }
    case OfficeKind.pptx:
      final page = f.pageRect;
      final picture = preview?.picture(f.page);
      final round = RRect.fromRectAndRadius(page, Radius.circular(4 * u));
      canvas
        ..save()
        ..clipRRect(round);
      if (picture != null) {
        _drawPage(canvas, picture, f);
      } else {
        canvas.drawRect(page, Paint()..color = c.previewBg);
        _waiting(canvas, page, c, unreadable, u);
      }
      canvas.restore();
    case OfficeKind.xlsx:
      final sheet = preview?.sheet(f.page);
      if (sheet != null) {
        canvas
          ..save()
          ..clipRect(area)
          ..translate(area.left, area.top)
          ..scale(u);
        _sheet(canvas, sheet, Size(area.width / u, area.height / u), c);
        canvas.restore();
      } else {
        _waiting(canvas, area, c, unreadable, u);
      }
    case null:
      break;
  }

  // Ink on the page showing. Paper keeps its own colors in dark mode, so
  // ink on a document or slide does too; ink on a sheet follows the theme.
  final strokes = ink ? officeInk(f) : const <StrokeItem>[];
  if (strokes.isNotEmpty) {
    canvas
      ..save()
      ..clipRect(officeInkArea(f));
    for (final s in strokes) {
      paintStroke(canvas, s, kind == OfficeKind.xlsx ? displayInk(s.color, brightness) : s.color);
    }
    canvas.restore();
  }

  // Header and footer, in the card's unscaled px.
  canvas
    ..save()
    ..scale(u);
  final size = Size(f.w / u, f.h / u);
  canvas.drawRect(Offset.zero & Size(size.width, OfficeItem.header), Paint()..color = c.surface);
  final buttons = _buttons(f);
  final (ink0, tint) = _badgeColors(kind, c);
  final badge = _text(kind?.badge ?? 'FILE', size: 10, weight: FontWeight.w800, color: ink0);
  final badgeBox = Rect.fromLTWH(10, (OfficeItem.header - badge.height - 6) / 2, badge.width + 10, badge.height + 6);
  canvas.drawRRect(RRect.fromRectAndRadius(badgeBox, const Radius.circular(4)), Paint()..color = tint);
  _draw(canvas, badge, badgeBox.topLeft + const Offset(5, 3));
  final open = buttons[OfficeButton.open]!;
  final name = _text(officeTitle(f), size: 13, weight: FontWeight.w600, color: c.text, maxWidth: open.left - 8 - badgeBox.right - 8);
  _draw(canvas, name, Offset(badgeBox.right + 8, (OfficeItem.header - name.height) / 2));
  _button(canvas, open, c, label: 'Open');
  canvas.drawRect(Rect.fromLTWH(0, OfficeItem.header, size.width, 1), Paint()..color = c.lineSoft);

  if (f.hasFooter) {
    final top = size.height - OfficeItem.footer;
    canvas
      ..drawRect(Rect.fromLTWH(0, top, size.width, OfficeItem.footer), Paint()..color = c.surface)
      ..drawRect(Rect.fromLTWH(0, top, size.width, 1), Paint()..color = c.lineSoft);
    final count = preview?.pageCount ?? f.pages;
    final prev = buttons[OfficeButton.previous]!, next = buttons[OfficeButton.next]!;
    final place = _text(officePlace(f, preview: preview), size: 12, color: c.textMuted, maxWidth: prev.left - 20, tabular: true);
    _draw(canvas, place, Offset(12, top + (OfficeItem.footer - place.height) / 2));
    _button(canvas, prev, c, icon: EIcons.chevronLeft, enabled: f.page > 1);
    _button(canvas, next, c, icon: EIcons.chevronRight, enabled: f.page < count);
  }
  canvas
    ..restore()
    ..restore()
    ..drawRRect(
      card.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = c.line,
    );
}

void _drawPage(Canvas canvas, ui.Picture picture, OfficeItem f) {
  final fit = f.contentFit;
  canvas
    ..save()
    ..clipRect(f.pageRect)
    ..translate(fit.origin.dx, fit.origin.dy)
    ..scale(fit.scale)
    ..drawPicture(picture)
    ..restore();
}

/// While the file is read, or when it can't be.
void _waiting(Canvas canvas, Rect area, EndlessColors c, bool unreadable, double u, {bool onPaper = false}) {
  final color = onPaper ? const Color(0xFF7A7365) : c.textMuted;
  final note = _text(unreadable ? 'No preview · Open it to see it' : 'Opening…', size: 13 * u, color: color, maxWidth: area.width - 24 * u);
  _draw(canvas, note, area.center - Offset(note.width / 2, note.height / 2));
}

void _button(Canvas canvas, Rect r, EndlessColors c, {String? label, EIconData? icon, bool enabled = true}) {
  canvas.drawRRect(
    RRect.fromRectAndRadius(r.deflate(0.5), const Radius.circular(7)),
    Paint()
      ..style = PaintingStyle.stroke
      ..color = enabled ? c.lineStrong : c.lineSoft,
  );
  if (label != null) {
    final t = _text(label, size: 12, weight: FontWeight.w600, color: c.text);
    _draw(canvas, t, r.center - Offset(t.width / 2, t.height / 2));
  }
  if (icon != null) paintEIcon(canvas, icon, r.center - const Offset(8, 8), 16, enabled ? c.text : c.textFaint);
}

/// A sheet's cells, like the table card: the header row tinted, then rows
/// 29 px tall, columns as wide as in Excel.
void _sheet(Canvas canvas, Sheet s, Size size, EndlessColors c) {
  final lefts = <double>[0];
  for (final w in s.columnWidths) {
    lefts.add(lefts.last + w * _excelPx);
  }
  final right = math.max(size.width, lefts.last);
  for (final (r, row) in s.cells.indexed) {
    final y = r * _rowHeight;
    if (y > size.height) break;
    final head = s.header && r == 0;
    if (head) canvas.drawRect(Rect.fromLTWH(0, y, right, _rowHeight), Paint()..color = c.menuTile);
    canvas.drawRect(Rect.fromLTWH(0, y + _rowHeight - 1, right, 1), Paint()..color = head ? c.cardLine : c.lineSoft);
    for (final (i, cell) in row.indexed) {
      if (cell.isEmpty || i >= s.columns) continue;
      final colW = lefts[i + 1] - lefts[i];
      if (lefts[i] > size.width || colW <= 0) continue;
      _draw(
        canvas,
        _text(
          cell,
          size: 12,
          weight: head || s.bold.contains(r * 1000 + i) ? FontWeight.w700 : FontWeight.w400,
          color: c.text,
          maxWidth: colW - 16,
          tabular: true,
        ),
        Offset(lefts[i] + 8, y + 7),
      );
    }
  }
  if (s.cells.isEmpty) {
    final t = _text('This sheet is empty', size: 13, color: c.textMuted, maxWidth: size.width - 24);
    _draw(canvas, t, Offset((size.width - t.width) / 2, 24));
  }
}

/// The card's size for a file: Word pages and slides big enough to read at
/// 100% (Board.png's cards are a zoomed-out overview), a sheet as wide as
/// its columns.
Size officeCardSize(OfficeKind kind, OfficePreview preview, {double unit = CardItem.defaultUnit}) {
  final footer = preview.pageCount > 1 || kind == OfficeKind.pptx ? OfficeItem.footer : 0.0;
  switch (kind) {
    case OfficeKind.pptx:
      const width = 360.0;
      final page = preview.pageSize ?? const Size(960, 540);
      final slide = (width - 24) * page.height / page.width;
      return Size(width, OfficeItem.header + 10 + slide + 4 + footer) * unit;
    case OfficeKind.docx:
      const width = 320.0;
      final page = preview.pageSize ?? const Size(612, 792);
      final sheet = (width - 24) * page.height / page.width;
      return Size(width, OfficeItem.header + 1 + 12 + sheet + 12 + footer) * unit;
    case OfficeKind.xlsx:
      final sheet = preview.sheet(1);
      final columns = sheet == null ? 0.0 : sheet.columnWidths.fold<double>(0, (s, w) => s + w * _excelPx);
      final rows = sheet?.rows ?? 0;
      final width = columns.clamp(220.0, 720.0);
      final height = (OfficeItem.header + 1 + rows * _rowHeight + 10 + footer).clamp(200.0, 520.0);
      return Size(width, height) * unit;
  }
}

/// A new card for a file, centered on [center].
OfficeItem newOfficeCard(
  OfficeKind kind,
  OfficePreview preview, {
  required String asset,
  required String name,
  required Offset center,
  required int z,
  required DateTime now,
}) {
  final size = officeCardSize(kind, preview);
  final w = size.width.roundToDouble(), h = size.height.roundToDouble();
  return OfficeItem(
    id: newId('it', now: now),
    x: center.dx - w / 2,
    y: center.dy - h / 2,
    z: z,
    createdAt: now,
    w: w,
    h: h,
    asset: asset,
    mime: kind.name,
    name: name,
    pages: preview.pageCount,
    pageSize: preview.pageSize,
  );
}

/// The least size a card can be stretched to, in page px.
Size officeMinSize(OfficeItem f) =>
    Size(170 * f.unit, (OfficeItem.header + (f.hasFooter ? OfficeItem.footer : 0) + 60) * f.unit);
