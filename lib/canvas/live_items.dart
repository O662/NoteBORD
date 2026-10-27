import 'dart:math' as math;
import 'dart:ui' show Brightness, FontFeature;

import 'package:flutter/painting.dart';

import '../board/ids.dart';
import '../board/model.dart';
import '../theme/colors.dart';
import '../theme/tokens.g.dart';
import '../ui/icons.dart';
import '../ui/library/format.dart' show longDate;
import 'page_runtime.dart' show paintStroke;

// Live items (LiveItems.png, LiveItems.dc.html): a clock in the device's
// time zone, today's date, time stamps showing clock time or how long ago,
// and checklists with a progress bar. Clocks, the date and "time ago"
// change by themselves: they're drawn for the time they're drawn at, and
// the canvas draws them again when what they show changes ([liveKey]).
// Everything is in the design's units, scaled by the item's `unit`.

/// The time live items show. Tests set it.
DateTime Function() liveNow = DateTime.now;

/// The device's time zone by name ("America/Chicago"), once the platform
/// has said (Android); until then, or elsewhere, the zone's abbreviation.
String? deviceTimeZone;

String timeZoneLabel(DateTime now) => (deviceTimeZone ?? now.timeZoneName).replaceAll('_', ' ');

String _two(int n) => n < 10 ? '0$n' : '$n';

/// "9:23:53 PM", or "9:23 PM" without [seconds].
String clockText(DateTime t, {bool seconds = true}) =>
    '${t.hour % 12 == 0 ? 12 : t.hour % 12}:${_two(t.minute)}${seconds ? ':${_two(t.second)}' : ''} ${t.hour < 12 ? 'AM' : 'PM'}';

/// "just now", "12 min ago", "3 h ago", "2 days ago".
String agoText(DateTime at, DateTime now) {
  final mins = math.max(0, (now.difference(at).inSeconds / 60).round());
  if (mins < 1) return 'just now';
  if (mins < 60) return '$mins min ago';
  if (mins < 24 * 60) return '${mins ~/ 60} h ago';
  final days = mins ~/ (24 * 60);
  return days == 1 ? '1 day ago' : '$days days ago';
}

/// What a time stamp says at [now].
String stampLabel(StampData s, DateTime now) => s.ago ? agoText(s.at, now) : clockText(s.at.toLocal(), seconds: false);

/// What live items among [items] show at [now], at the finest grain any
/// of them changes: '' when none changes with time. The canvas draws them
/// again when it changes.
String liveKey(Iterable<Item> items, DateTime now) {
  var minutes = false;
  for (final i in items) {
    switch (i) {
      case LiveItem(data: ClockData _):
        return '${now.day} ${now.hour}:${now.minute}:${now.second}';
      case LiveItem(data: DateData _) || LiveItem(data: StampData(ago: true)):
        minutes = true;
      default:
        break;
    }
  }
  return minutes ? '${now.day} ${now.hour}:${now.minute}' : '';
}

/// What a live item says, for an exported PDF's text layer.
String liveText(LiveItem item, DateTime now) => switch (item.data) {
      ClockData _ => '${clockText(now)} ${timeZoneLabel(now)}',
      DateData _ => longDate(now),
      final StampData s => stampLabel(s, now),
    };

/// Everything a checklist says that's typed, for search and exports.
String checklistText(ChecklistItem l) => [
      checklistTitle(l),
      for (final e in l.entries)
        if (e.text.trim().isNotEmpty) e.text.trim(),
    ].join('\n');

String checklistTitle(ChecklistItem l) => l.title.trim().isEmpty ? 'Checklist' : 'Checklist · ${l.title.trim()}';

// New ones.

LiveItem newLiveItem(LiveData data, Offset at, {required int z, required DateTime now}) =>
    LiveItem(id: newId('it', now: now), x: at.dx, y: at.dy, z: z, createdAt: now, data: data);

ChecklistItem newChecklist(Offset at, {required int z, required DateTime now, String title = ''}) => ChecklistItem(
      id: newId('it', now: now),
      x: at.dx,
      y: at.dy,
      z: z,
      createdAt: now,
      w: ChecklistItem.width,
      title: title,
    );

// Buttons.

/// What's under a point on a live item.
enum LivePart { analog, digital, stamp }

/// The Analog and Digital buttons on a clock, at 100%: right-aligned in a
/// switch with 2 px around them.
(Rect, Rect) clockButtons(ClockData d) {
  final wa = _textWidth('Analog', 12, d.analog ? FontWeight.w700 : FontWeight.w500) + 20;
  final wd = _textWidth('Digital', 12, d.analog ? FontWeight.w500 : FontWeight.w700) + 20;
  final a = Rect.fromLTWH(d.size.width - 16 - 2 - wd - 2 - wa, 18, wa, 32);
  return (a, Rect.fromLTWH(a.right + 2, 18, wd, 32));
}

/// What's under [local] (relative to the item's top-left, unrotated).
LivePart? liveHitAt(LiveItem item, Offset local) {
  final p = local / item.unit;
  switch (item.data) {
    case final ClockData d:
      final (analog, digital) = clockButtons(d);
      // At least 44 px tall to the finger.
      if (analog.inflate(6).contains(p)) return LivePart.analog;
      if (digital.inflate(6).contains(p)) return LivePart.digital;
      return null;
    case StampData _:
      return (Offset.zero & item.data.size).inflate(9).contains(p) ? LivePart.stamp : null;
    case DateData _:
      return null;
  }
}

/// The entry whose box is under [local] on [l] (relative to its top-left,
/// unrotated), or null. A box takes a 44 px square.
int? checklistBoxAt(ChecklistItem l, Offset local) {
  final p = local / l.unit;
  for (var i = 0; i < l.entries.length; i++) {
    if (Rect.fromCenter(center: l.boxRect(i).center, width: 44, height: 44).contains(p)) return i;
  }
  return null;
}

// Painting.

double _textWidth(String s, double size, FontWeight weight) {
  final p = _label(s, size, const Color(0xFF000000), weight: weight);
  final w = p.width;
  p.dispose();
  return w;
}

TextPainter _label(String s, double size, Color color, {FontWeight weight = FontWeight.w400, String family = FontFamilies.ui, double? maxWidth}) =>
    TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontFamily: family,
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: 1.15,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(0, maxWidth ?? double.infinity));

/// Draws [p] with its left edge at [x], centered on [cy].
void _put(Canvas canvas, TextPainter p, double x, double cy) {
  p.paint(canvas, Offset(x, cy - p.height / 2));
  p.dispose();
}

void _put1(Canvas canvas, TextPainter p, double cx, double cy) => _put(canvas, p, cx - p.width / 2, cy);

/// The design's cards: 18 radius, 1 px border, 0 14px 28px -18px shadow.
void _card(Canvas canvas, Size size, EndlessColors c) {
  final rect = Offset.zero & size;
  final shade = rect.inflate(-18).shift(const Offset(0, 14));
  if (!shade.isEmpty) {
    canvas.drawRect(shade, Paint()
      ..color = c.shadow.withValues(alpha: c.shadow.a * 0.65)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
  }
  final card = RRect.fromRectAndRadius(rect, const Radius.circular(18));
  canvas
    ..drawRRect(card, Paint()..color = c.surface)
    ..drawRRect(card.deflate(0.5), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = c.line);
}

/// Draws a clock, the date or a time stamp with its top-left at the origin.
void paintLiveItem(Canvas canvas, LiveItem item, Brightness brightness, EndlessColors c) {
  final now = liveNow();
  canvas
    ..save()
    ..scale(item.unit);
  switch (item.data) {
    case final ClockData d:
      _clock(canvas, d, now, c);
    case DateData _:
      _chip(canvas, EIcons.dateChip, longDate(now), 14, 32, 12, 6, c.accentTint, c.accentDeep);
    case final StampData s:
      _chip(canvas, EIcons.stamp, stampLabel(s, now), 12, 26, 9, 5, c.plumTint, c.plumDeep);
  }
  canvas.restore();
}

void _chip(Canvas canvas, EIconData icon, String text, double size, double height, double pad, double gap, Color fill, Color ink) {
  final t = _label(text, size, ink, weight: FontWeight.w700);
  final iconSize = size;
  final width = pad + iconSize + gap + t.width + pad;
  canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, width, height), Radius.circular(height / 2)), Paint()..color = fill);
  paintEIcon(canvas, icon, Offset(pad, (height - iconSize) / 2), iconSize, ink);
  _put(canvas, t, pad + iconSize + gap, height / 2);
}

void _clock(Canvas canvas, ClockData d, DateTime now, EndlessColors c) {
  final size = d.size;
  _card(canvas, size, c);
  _put(canvas, _label('Clock', 13, c.text, weight: FontWeight.w700), 16, 34);

  // Analog · Digital.
  final (analog, digital) = clockButtons(d);
  canvas.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTRB(analog.left - 2, 16, digital.right + 2, 52), const Radius.circular(9)),
    Paint()..color = c.side,
  );
  for (final (r, label, on) in [(analog, 'Analog', d.analog), (digital, 'Digital', !d.analog)]) {
    if (on) canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(7)), Paint()..color = c.surface);
    _put1(canvas, _label(label, 12, c.text, weight: on ? FontWeight.w700 : FontWeight.w500), r.center.dx, r.center.dy);
  }

  var top = 62.0;
  if (d.analog) {
    _face(canvas, Offset(size.width / 2, top + 95), 0.95, now, c);
    top += 190 + 10;
  }
  final big = d.analog ? 26.0 : 44.0;
  final time = _label(clockText(now), big, c.text, family: FontFamilies.serif);
  _put1(canvas, time, size.width / 2, top + big / 2);
  top += big + 10;
  _put1(canvas, _label(timeZoneLabel(now), 13, c.textMuted, maxWidth: size.width - 32), size.width / 2, top + 8);
}

/// The face, 200 across at [k] = 1 (LiveItems.dc.html's viewBox).
void _face(Canvas canvas, Offset center, double k, DateTime now, EndlessColors c) {
  Offset at(double degrees, double length) {
    final a = (degrees - 90) * math.pi / 180;
    return center + Offset(math.cos(a), math.sin(a)) * length * k;
  }

  canvas
    ..drawCircle(center, 92 * k, Paint()..color = c.bg)
    ..drawCircle(center, 92 * k, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * k
      ..color = c.text);
  Paint line(double width, Color color) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width * k
    ..strokeCap = StrokeCap.round
    ..color = color;
  final tick = line(2.5, c.text);
  for (var i = 0; i < 12; i++) {
    canvas.drawLine(at(i * 30.0, 86), at(i * 30.0, i % 3 == 0 ? 72 : 78), tick);
  }
  final h = now.hour, m = now.minute, s = now.second;
  canvas
    ..drawLine(center, at((h % 12) * 30 + m * 0.5, 48), line(6, c.text))
    ..drawLine(center, at(m * 6 + s * 0.1, 70), line(4, c.text))
    ..drawLine(center, at(s * 6.0, 78), line(2, c.danger))
    ..drawCircle(center, 5 * k, Paint()..color = c.danger);
}

/// Draws a checklist with its top-left at the origin. Without [ink], its
/// rows are drawn without their writing (exports draw it as vectors).
void paintChecklist(Canvas canvas, ChecklistItem l, Brightness brightness, EndlessColors c, {bool ink = true}) {
  final w = l.w / l.unit;
  canvas
    ..save()
    ..scale(l.unit);
  _card(canvas, Size(w, l.h / l.unit), c);

  // The title, how many are done, and the bar.
  const pad = ChecklistItem.pad;
  final count = _label('${l.doneCount}/${l.entries.length}', 13, c.greenDeep, weight: FontWeight.w700);
  final countWidth = count.width;
  _put(canvas, count, w - pad - countWidth, pad + 8.5);
  _put(canvas, _label(checklistTitle(l), 13, c.text, weight: FontWeight.w700, maxWidth: w - 2 * pad - countWidth - 12), pad, pad + 8.5);
  final bar = Rect.fromLTWH(pad, pad + 23 + ChecklistItem.gap, w - 2 * pad, 6);
  canvas.drawRRect(RRect.fromRectAndRadius(bar, const Radius.circular(3)), Paint()..color = c.side);
  if (l.entries.isNotEmpty && l.doneCount > 0) {
    final done = Rect.fromLTWH(bar.left, bar.top, bar.width * l.doneCount / l.entries.length, bar.height);
    canvas.drawRRect(RRect.fromRectAndRadius(done, const Radius.circular(3)), Paint()..color = c.green);
  }

  // The rows.
  final rule = Paint()
    ..color = c.lineSoft
    ..strokeWidth = 1;
  for (final (i, e) in l.entries.indexed) {
    final row = l.rowRect(i);
    canvas.drawLine(Offset(row.left, row.bottom + 0.5), Offset(row.right, row.bottom + 0.5), rule);
    _box(canvas, l.boxRect(i), e.done, c);
    final faint = c.textFaint;
    final origin = Offset(ChecklistItem.writeLeft, row.top);
    Rect? written;
    if (e.text.trim().isNotEmpty) {
      final t = _label(e.text.trim(), 17, e.done ? faint : c.text, maxWidth: row.right - origin.dx - 4);
      written = Rect.fromLTWH(origin.dx, row.center.dy - t.height / 2, t.width, t.height);
      _put(canvas, t, origin.dx, row.center.dy);
    }
    if (e.ink.isNotEmpty) {
      canvas
        ..save()
        ..translate(origin.dx, origin.dy);
      for (final s in e.ink) {
        if (ink) paintStroke(canvas, s, e.done ? faint : displayInk(s.color, brightness));
        final b = s.bounds.shift(origin);
        written = written == null ? b : written.expandToInclude(b);
      }
      canvas.restore();
    }
    // Done: struck through (LiveItems.dc.html's line-through).
    if (e.done && written != null) {
      final y = written.center.dy;
      canvas.drawLine(Offset(written.left - 2, y), Offset(written.right + 2, y), Paint()
        ..color = faint
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round);
    }
  }

  // Where the next one is written.
  final slot = l.slot;
  _dashed(canvas, Path()..addRRect(RRect.fromRectAndRadius(slot.deflate(0.75), const Radius.circular(10))), Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = c.lineStrong);
  _put(canvas, _label('write another item…', 22, c.textMuted, family: FontFamilies.handwritingSample), slot.left + 13, slot.center.dy);
  canvas.restore();
}

void _box(Canvas canvas, Rect r, bool done, EndlessColors c) {
  final box = RRect.fromRectAndRadius(r, const Radius.circular(4));
  if (!done) {
    canvas
      ..drawRRect(box, Paint()..color = c.surface)
      ..drawRRect(box.deflate(0.75), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = c.lineStrong);
    return;
  }
  canvas
    ..drawRRect(box, Paint()..color = c.green)
    ..drawPath(
      Path()
        ..moveTo(r.left + 5.5, r.top + 11.5)
        ..lineTo(r.left + 9.5, r.top + 15.5)
        ..lineTo(r.left + 16.5, r.top + 7),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = c.onAccent,
    );
}

/// [path] drawn in dashes (6 on, 5 off).
void _dashed(Canvas canvas, Path path, Paint paint, {double on = 6, double off = 5}) {
  for (final m in path.computeMetrics()) {
    for (var d = 0.0; d < m.length; d += on + off) {
      canvas.drawPath(m.extractPath(d, math.min(d + on, m.length)), paint);
    }
  }
}
