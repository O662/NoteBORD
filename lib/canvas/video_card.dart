import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../audio/transcript_lines.dart' show clockOf;
import '../board/model.dart';
import '../theme/colors.dart';
import '../theme/tokens.g.dart';
import '../ui/icons.dart';
import 'items.dart' show ImageLookup;

// A video's card on the page (Video.png, Video.dc.html's section at 700 px):
// the picture (a still until it plays), the timeline with an orange dot for
// each note pinned to a moment, and play, the time, speed, "Note at 0:18",
// Grab frame, Pop out and Full screen. And the "▶ 0:12" chips the notes are
// written beside. Drawn at the card's unit, with its top-left at the origin.

/// How the card shows now: where it's playing, its speed, its pins.
class VideoCardLive {
  const VideoCardLive({this.positionMs, this.playing = false, this.speed = 1, this.pins = const [], this.loading = false});

  /// Null until it's loaded: shown at its start.
  final int? positionMs;
  final bool playing;
  final double speed;

  /// The moments notes are pinned to (ms into the video).
  final List<int> pins;
  final bool loading;
}

enum VideoPart { screen, play, timeline, pin, playSmall, speed, note, grab, popOut, fullScreen }

class VideoHit {
  const VideoHit(this.part, {this.share = 0, this.pinMs});

  final VideoPart part;

  /// On the timeline: how far along (0–1) of the part that plays.
  final double share;

  /// On a pin's dot: its moment.
  final int? pinMs;
}

// Layout at 100% (Video.dc.html).
const _screen = VideoItem.screen;
const _trackLeft = 12.0, _trackRight = 688.0, _trackY = 405.0;
const _rowY = 456.0;
const _playCenter = Offset(350, 197);

double _textWidth(String s, double size, FontWeight w) {
  final p = _label(s, size, const Color(0xFF000000), weight: w);
  final width = p.width;
  p.dispose();
  return width;
}

TextPainter _label(String s, double size, Color color, {FontWeight weight = FontWeight.w400, double? maxWidth}) => TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontFamily: FontFamilies.ui,
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

void _put(Canvas canvas, TextPainter p, double x, double cy) {
  p.paint(canvas, Offset(x, cy - p.height / 2));
  p.dispose();
}

/// The control row's buttons, right to left from Full screen.
Rect get _fullRect => const Rect.fromLTWH(644, _rowY - 22, 44, 44);
Rect get _popRect => const Rect.fromLTWH(596, _rowY - 22, 44, 44);
final _grabWidth = 24 + _textWidth('Grab frame', 13, FontWeight.w600);
Rect get _grabRect => Rect.fromLTWH(_popRect.left - 8 - _grabWidth, _rowY - 18, _grabWidth, 36);

/// "Note at 0:18" is as wide as "Note at 00:00" (so it doesn't jiggle).
final _noteWidth = 14 + 14 + 6 + _textWidth('Note at 00:00', 13, FontWeight.w700) + 14;
Rect get _noteRect => Rect.fromLTWH(_grabRect.left - 8 - _noteWidth, _rowY - 18, _noteWidth, 36);
Rect get _speedRect => Rect.fromLTWH(_noteRect.left - 8 - 36, _rowY - 18, 36, 36);
const _playSmall = Rect.fromLTWH(12, _rowY - 22, 44, 44);

/// Where [part] is on the card at 100% (for tests and touch targets).
Rect videoPartRect(VideoPart part) => switch (part) {
      VideoPart.screen => _screen,
      VideoPart.play => Rect.fromCircle(center: _playCenter, radius: 38),
      VideoPart.timeline || VideoPart.pin => const Rect.fromLTRB(_trackLeft, 394, _trackRight, 416),
      VideoPart.playSmall => _playSmall,
      VideoPart.speed => _speedRect,
      VideoPart.note => _noteRect,
      VideoPart.grab => _grabRect,
      VideoPart.popOut => _popRect,
      VideoPart.fullScreen => _fullRect,
    };

/// Where moment [ms] is on the timeline (x at 100%).
double _xOf(VideoItem v, int ms) {
  final span = math.max(1, v.to - v.from);
  return _trackLeft + (_trackRight - _trackLeft) * ((ms - v.from) / span).clamp(0.0, 1.0);
}

/// What's under [local] (relative to the card's top-left, at its unit).
VideoHit? videoHitAt(VideoItem v, Offset local, {List<int> pins = const []}) {
  final p = local / v.unit;
  if (!(Offset.zero & VideoItem.size).contains(p)) return null;
  if (p.dy >= 384 && p.dy <= 426) {
    // A pin's dot (within 12 px) before the timeline under it.
    for (final ms in pins) {
      if (ms < v.from || ms > v.to) continue;
      if ((p.dx - _xOf(v, ms)).abs() <= 12) return VideoHit(VideoPart.pin, pinMs: ms);
    }
    if (p.dx >= _trackLeft - 8 && p.dx <= _trackRight + 8) {
      return VideoHit(VideoPart.timeline, share: ((p.dx - _trackLeft) / (_trackRight - _trackLeft)).clamp(0.0, 1.0));
    }
  }
  if (_screen.contains(p)) {
    return (p - _playCenter).distance <= 44 ? const VideoHit(VideoPart.play) : const VideoHit(VideoPart.screen);
  }
  for (final part in [VideoPart.playSmall, VideoPart.speed, VideoPart.note, VideoPart.grab, VideoPart.popOut, VideoPart.fullScreen]) {
    if (videoPartRect(part).inflate(4).contains(p)) return VideoHit(part);
  }
  return null;
}

/// "0.5×", "1×", "2×".
String videoSpeedLabel(double s) => s == s.roundToDouble() ? '${s.toStringAsFixed(0)}×' : '${s.toString().replaceFirst(RegExp(r'0+$'), '')}×';

/// The pinned note near [positionMs] (within 1 s), if any.
int? pinNear(List<int> pins, int positionMs) {
  for (final ms in pins) {
    if ((ms - positionMs).abs() <= 1000) return ms;
  }
  return null;
}

void _stripes(Canvas canvas, Rect r, Color color, double band) {
  canvas
    ..save()
    ..clipRect(r);
  final paint = Paint()
    ..color = color
    ..strokeWidth = band * 0.7;
  for (var x = r.left - r.height; x < r.right + r.height; x += band * 2) {
    canvas.drawLine(Offset(x, r.bottom), Offset(x + r.height, r.top), paint);
  }
  canvas.restore();
}

/// Draws [v] with its top-left at the origin. [screen] false leaves the
/// picture's part alone (the playing video is shown there).
void paintVideoCard(
  Canvas canvas,
  VideoItem v,
  EndlessColors c, {
  ImageLookup? images,
  VideoCardLive live = const VideoCardLive(),
  bool screen = true,
}) {
  canvas
    ..save()
    ..scale(v.unit);
  final size = VideoItem.size;
  final card = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16));
  if (screen) {
    // 0 18px 36px -22px shadow.
    canvas.drawRect(
      (Offset.zero & size).inflate(-22).shift(const Offset(0, 18)),
      Paint()
        ..color = c.shadow.withValues(alpha: c.shadow.a * 0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas
      ..save()
      ..clipRRect(card)
      ..drawRect(Offset.zero & size, Paint()..color = c.video)
      ..drawRect(_screen, Paint()..color = c.videoScreen);
    final still = v.preview == null ? null : images?.call(v.preview!);
    if (still != null) {
      final src = Offset.zero & Size(still.width.toDouble(), still.height.toDouble());
      final fit = applyBoxFit(BoxFit.contain, src.size, _screen.size);
      final dst = Alignment.center.inscribe(fit.destination, _screen);
      canvas.drawImageRect(still, Alignment.center.inscribe(fit.source, src), dst, Paint()..filterQuality = FilterQuality.medium);
    } else {
      _stripes(canvas, _screen, c.videoText.withValues(alpha: 0.05), 12);
      final t = _label('${v.name} · ${clockOf(v.to)}', 14, c.videoMuted, maxWidth: 520);
      _put(canvas, t, _screen.center.dx - t.width / 2, _screen.center.dy + 60);
    }
    canvas.restore();
  } else {
    // Only the rows under the picture are drawn again.
    canvas
      ..save()
      ..clipRRect(card)
      ..drawRect(Rect.fromLTRB(0, _screen.bottom, size.width, size.height), Paint()..color = c.video)
      ..restore();
  }

  final pos = (live.positionMs ?? v.from).clamp(v.from, v.to);
  final shown = live.positionMs != null;

  // On the picture: the big play button while it isn't playing, the speed
  // when it isn't 1×, and the hint or the note pinned near here.
  if (!live.playing) {
    canvas.drawCircle(_playCenter, 38, Paint()..color = c.videoText.withValues(alpha: 0.92));
    canvas.drawPath(
      Path()
        ..moveTo(_playCenter.dx - 9, _playCenter.dy - 14)
        ..lineTo(_playCenter.dx - 9, _playCenter.dy + 14)
        ..lineTo(_playCenter.dx + 15, _playCenter.dy)
        ..close(),
      Paint()..color = c.video,
    );
  }
  void chip(String text, {required bool left, FontWeight weight = FontWeight.w600}) {
    final t = _label(text, 12, c.videoText, weight: weight, maxWidth: 330);
    final r = left ? Rect.fromLTWH(12, 12, t.width + 20, 24) : Rect.fromLTWH(size.width - 12 - t.width - 20, 12, t.width + 20, 24);
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(999)), Paint()..color = c.video.withValues(alpha: 0.75));
    _put(canvas, t, r.left + 10, r.center.dy);
  }

  if (live.speed < 1) chip('${videoSpeedLabel(live.speed)} slow motion', left: true, weight: FontWeight.w700);
  if (live.speed > 1) chip('${videoSpeedLabel(live.speed)} fast', left: true, weight: FontWeight.w700);
  if (live.loading) {
    chip('Opening…', left: false);
  } else if (live.pins.isNotEmpty) {
    final near = shown ? pinNear(live.pins, pos) : null;
    chip(near == null ? 'Tap an orange dot to jump to a note' : 'Note at ${clockOf(near)}', left: false);
  }

  // The timeline: played part, pins, playhead.
  final track = RRect.fromLTRBR(_trackLeft, _trackY - 2, _trackRight, _trackY + 2, const Radius.circular(999));
  canvas.drawRRect(track, Paint()..color = c.videoTrack);
  final head = _xOf(v, pos);
  if (head > _trackLeft) {
    canvas.drawRRect(RRect.fromLTRBR(_trackLeft, _trackY - 2, head, _trackY + 2, const Radius.circular(999)), Paint()..color = c.videoPlayed);
  }
  for (final ms in live.pins) {
    if (ms < v.from || ms > v.to) continue;
    final at = Offset(_xOf(v, ms), _trackY);
    canvas
      ..drawCircle(at, 7, Paint()..color = c.video)
      ..drawCircle(at, 5, Paint()..color = c.videoPin);
  }
  canvas.drawCircle(Offset(head, _trackY), 8, Paint()..color = c.videoText);

  // The control row.
  final glyph = Paint()..color = c.videoText;
  final pc = _playSmall.center;
  if (live.playing) {
    canvas
      ..drawRect(Rect.fromLTWH(pc.dx - 6, pc.dy - 7, 4, 14), glyph)
      ..drawRect(Rect.fromLTWH(pc.dx + 2, pc.dy - 7, 4, 14), glyph);
  } else {
    canvas.drawPath(Path()..moveTo(pc.dx - 5, pc.dy - 7)..lineTo(pc.dx - 5, pc.dy + 7)..lineTo(pc.dx + 7, pc.dy)..close(), glyph);
  }
  _put(canvas, _label('${clockOf(pos)} / ${clockOf(v.to)}', 13, c.videoText, weight: FontWeight.w600), 64, _rowY);

  final speed = _speedRect;
  canvas.drawCircle(speed.center, 17.5, Paint()
    ..style = PaintingStyle.stroke
    ..color = c.videoTrack);
  final st = _label(videoSpeedLabel(live.speed), 12, c.videoText, weight: FontWeight.w700);
  _put(canvas, st, speed.center.dx - st.width / 2, speed.center.dy);

  final note = _noteRect;
  canvas.drawRRect(RRect.fromRectAndRadius(note, const Radius.circular(999)), Paint()..color = c.videoPin);
  paintEIcon(canvas, EIcons.pen, Offset(note.left + 14, note.center.dy - 7), 14, c.video);
  _put(canvas, _label('Note at ${clockOf(pos)}', 13, c.video, weight: FontWeight.w700), note.left + 14 + 14 + 6, note.center.dy);

  final grab = _grabRect;
  canvas.drawRRect(
    RRect.fromRectAndRadius(grab, const Radius.circular(999)).deflate(0.5),
    Paint()
      ..style = PaintingStyle.stroke
      ..color = c.videoTrack,
  );
  _put(canvas, _label('Grab frame', 13, c.videoText, weight: FontWeight.w600), grab.left + 12, grab.center.dy);
  paintEIcon(canvas, EIcons.popOut, _popRect.center - const Offset(9, 9), 18, c.videoText);
  paintEIcon(canvas, EIcons.fullScreen, _fullRect.center - const Offset(9, 9), 18, c.videoText);
  canvas.restore();
}

/// The "▶ 0:12" label of a pin to [tMs] (times are the video file's own):
/// the triangle is drawn, the time is text.
String videoPinLabel(int tMs) => '▶ ${clockOf(tMs)}';

/// A new pin chip's size for the moment [tMs].
Size videoPinSize(int tMs) => Size((12 + 9 + 6 + _textWidth(clockOf(tMs), 13, FontWeight.w700) + 12).ceilToDouble(), 36);

/// Draws a "▶ 0:12" chip, orange while the video is at its moment.
void paintVideoPin(Canvas canvas, VideoPinItem pin, EndlessColors c, {bool near = false}) {
  final r = Offset.zero & Size(pin.w, pin.h);
  canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(pin.h / 2)), Paint()..color = near ? c.videoPin : c.clayTint);
  final k = pin.h / 36;
  final fg = near ? c.video : c.clayDeep;
  final t = _label(clockOf(pin.tMs), 13 * k, fg, weight: FontWeight.w700, maxWidth: pin.w);
  final width = 9 * k + 6 * k + t.width;
  final x = r.center.dx - width / 2, cy = r.center.dy;
  canvas.drawPath(
    Path()
      ..moveTo(x, cy - 5 * k)
      ..lineTo(x, cy + 5 * k)
      ..lineTo(x + 9 * k, cy)
      ..close(),
    Paint()..color = fg,
  );
  _put(canvas, t, x + 15 * k, cy);
}

/// The card's text for a PDF's text layer: its name and transcript.
String videoText(VideoItem v) => [
      v.name,
      for (final l in v.transcript) l.text,
    ].where((s) => s.trim().isNotEmpty).join('\n');
