import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../audio/playback.dart' show speedLabel;
import '../audio/transcript_lines.dart' show clockOf;
import '../board/model.dart';
import '../theme/colors.dart';
import '../theme/tokens.g.dart';
import '../ui/icons.dart';
import 'live_items.dart' show liveNow;

// A recording's card on the page (Audio.png, Audio.dc.html's section at
// 560 px): the grip and the name with the day and length, play/pause, the
// waveform with the playhead and the time, then speed, −10 s, +10 s and
// Transcript. Drawn at the card's unit, with its top-left at the origin.

/// How the card shows when it's the recording playing (or loaded).
class AudioCardLive {
  const AudioCardLive({this.positionMs = 0, this.playing = false, this.speed = 1, this.transcriptOpen = false, this.percent});

  final int positionMs;
  final bool playing;
  final double speed;
  final bool transcriptOpen;

  /// While its transcript is being made.
  final int? percent;
}

/// The card's buttons.
enum AudioPart { grip, play, wave, speed, back, forward, transcript }

class AudioHit {
  const AudioHit(this.part, {this.share = 0});

  final AudioPart part;

  /// On the waveform: how far along (0–1).
  final double share;
}

// Layout at 100%.
const _pad = 14.0;
const _headerY = 21.0;
const _playCenter = Offset(38, 64);
const _playRadius = 24.0;
const _wave = Rect.fromLTWH(72, 44, 330, 40);
const _rowY = 118.0;

Rect _speedRect(double speed) => Rect.fromLTWH(_pad, _rowY - 18, _pillWidth(speedLabel(speed), FontWeight.w700), 36);
Rect _backRect(double speed) => Rect.fromLTWH(_speedRect(speed).right + 8, _rowY - 18, _pillWidth('−10 s', FontWeight.w600, pad: 10), 36);
Rect _forwardRect(double speed) => Rect.fromLTWH(_backRect(speed).right + 8, _rowY - 18, _pillWidth('+10 s', FontWeight.w600, pad: 10), 36);

final _transcriptWidth = 14 + 16 + 6 + _textWidth('Transcript', 13, FontWeight.w700) + 14;
Rect get _transcriptRect => Rect.fromLTWH(AudioItem.size.width - _pad - _transcriptWidth, _rowY - 20, _transcriptWidth, 40);

double _pillWidth(String s, FontWeight w, {double pad = 12}) => pad * 2 + _textWidth(s, 13, w);

final _widths = <(String, double, FontWeight), double>{};

double _textWidth(String s, double size, FontWeight weight) => _widths[(s, size, weight)] ??= () {
      final p = _label(s, size, const Color(0xFF000000), weight: weight);
      final w = p.width;
      p.dispose();
      return w;
    }();

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

/// Where [part] is on the card at 100% (relative to its top-left).
Rect audioPartRect(AudioPart part, {double speed = 1}) => switch (part) {
      AudioPart.grip => const Rect.fromLTWH(_pad - 4, _headerY - 12, 24, 24),
      AudioPart.play => Rect.fromCircle(center: _playCenter, radius: _playRadius),
      AudioPart.wave => _wave,
      AudioPart.speed => _speedRect(speed),
      AudioPart.back => _backRect(speed),
      AudioPart.forward => _forwardRect(speed),
      AudioPart.transcript => _transcriptRect,
    };

/// What's under [local] (relative to the card's top-left, at its unit).
AudioHit? audioHitAt(AudioItem a, Offset local, {double speed = 1}) {
  final p = local / a.unit;
  if (!(Offset.zero & AudioItem.size).contains(p)) return null;
  if ((p - _playCenter).distance <= _playRadius + 4) return const AudioHit(AudioPart.play);
  if (_wave.inflate(4).contains(p)) {
    return AudioHit(AudioPart.wave, share: ((p.dx - _wave.left) / _wave.width).clamp(0.0, 1.0));
  }
  // The pills are 36 high: their touch targets are 44.
  if (_speedRect(speed).inflate(4).contains(p)) return const AudioHit(AudioPart.speed);
  if (_backRect(speed).inflate(4).contains(p)) return const AudioHit(AudioPart.back);
  if (_forwardRect(speed).inflate(4).contains(p)) return const AudioHit(AudioPart.forward);
  if (_transcriptRect.inflate(2).contains(p)) return const AudioHit(AudioPart.transcript);
  if (p.dy < 40 && p.dx < 44) return const AudioHit(AudioPart.grip);
  return null;
}

/// "Fri · 48:20": the day it was recorded (a date after a week) and its
/// length.
String audioWhen(AudioItem a, {DateTime? now}) {
  final at = a.recordedAt.toLocal();
  final today = now ?? liveNow();
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final age = DateTime(today.year, today.month, today.day).difference(DateTime(at.year, at.month, at.day)).inDays;
  final day = age >= 0 && age < 7 ? days[at.weekday - 1] : '${months[at.month - 1]} ${at.day}';
  return '$day · ${clockOf(a.durationMs)}';
}

/// The design's waveform: 60 bars from the recording's loudness.
List<double> _bars(AudioItem a) {
  const n = 60;
  if (a.wave.isEmpty) return List.filled(n, 0);
  return [
    for (var i = 0; i < n; i++)
      () {
        final from = i * a.wave.length ~/ n;
        final to = math.max(from + 1, (i + 1) * a.wave.length ~/ n);
        var m = 0;
        for (var k = from; k < to && k < a.wave.length; k++) {
          m = math.max(m, a.wave[k]);
        }
        return m / 100;
      }(),
  ];
}

/// Draws [a] with its top-left at the origin.
void paintAudioCard(Canvas canvas, AudioItem a, EndlessColors c, {AudioCardLive live = const AudioCardLive()}) {
  canvas
    ..save()
    ..scale(a.unit);
  final size = AudioItem.size;
  final rect = Offset.zero & size;
  // 0 16px 30px -20px shadow, 16 radius, 1 px border.
  final shade = rect.inflate(-20).shift(const Offset(0, 16));
  canvas.drawRect(
    shade,
    Paint()
      ..color = c.shadow.withValues(alpha: c.shadow.a * 0.7)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15),
  );
  final card = RRect.fromRectAndRadius(rect, const Radius.circular(16));
  canvas
    ..drawRRect(card, Paint()..color = c.surface)
    ..drawRRect(
      card.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = c.line,
    );

  // The header: grip, microphone, name, and when.
  // The grip (Audio.dc.html's ⋮⋮): six dots.
  final dot = Paint()..color = c.lineDashed;
  for (final x in [_pad + 2.5, _pad + 8.5]) {
    for (final dy in [-5.0, 0.0, 5.0]) {
      canvas.drawCircle(Offset(x, _headerY + dy), 1.6, dot);
    }
  }
  paintEIcon(canvas, EIcons.mic, const Offset(_pad + 22, _headerY - 9), 18, c.clayDeep);
  final when = live.percent == null ? audioWhen(a) : 'Transcript ${live.percent}% · ${clockOf(a.durationMs)}';
  final whenText = _label(when, 12, live.percent == null ? c.textMuted : c.accent, weight: live.percent == null ? FontWeight.w400 : FontWeight.w600);
  final whenX = size.width - _pad - whenText.width;
  _put(canvas, _label(a.name.isEmpty ? 'Recording' : a.name, 14, c.text, weight: FontWeight.w700, maxWidth: whenX - 10 - 64), 64, _headerY);
  _put(canvas, whenText, whenX, _headerY);

  // Play or pause.
  canvas.drawCircle(_playCenter, _playRadius, Paint()..color = c.inverse);
  final glyph = Paint()..color = c.onInverse;
  if (live.playing) {
    // M7 5h3v14H7zM14 5h3v14h-3z at 18 px.
    const k = 18 / 24;
    final o = _playCenter - const Offset(9, 9);
    canvas
      ..drawRect(Rect.fromLTWH(o.dx + 7 * k, o.dy + 5 * k, 3 * k, 14 * k), glyph)
      ..drawRect(Rect.fromLTWH(o.dx + 14 * k, o.dy + 5 * k, 3 * k, 14 * k), glyph);
  } else {
    const k = 18 / 24;
    final o = _playCenter - const Offset(9, 9);
    canvas.drawPath(
      Path()
        ..moveTo(o.dx + 8 * k, o.dy + 5 * k)
        ..lineTo(o.dx + 8 * k, o.dy + 19 * k)
        ..lineTo(o.dx + 19 * k, o.dy + 12 * k)
        ..close(),
      glyph,
    );
  }

  // The waveform: played bars in the accent, the rest in the line color.
  final duration = math.max(1, a.durationMs);
  final share = (live.positionMs / duration).clamp(0.0, 1.0);
  final bars = _bars(a);
  for (final (i, v) in bars.indexed) {
    final h = math.min(36.0, 6 + v * 30);
    final x = _wave.left + i * 5.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x, _wave.center.dy - h / 2, 3, h), const Radius.circular(1.5)),
      Paint()..color = (i / bars.length) <= share && live.positionMs > 0 ? c.accent : c.lineStrong,
    );
  }
  canvas.drawRect(Rect.fromLTWH(_wave.left + (share * _wave.width).roundToDouble(), _wave.top, 2, _wave.height), Paint()..color = c.accent);
  _put(canvas, _label('${clockOf(live.positionMs)} / ${clockOf(a.durationMs)}', 12, c.inverseRaised, weight: FontWeight.w600), _wave.right + 10, _playCenter.dy);

  // Speed, −10 s, +10 s.
  void pill(Rect r, String text, FontWeight w) {
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(999));
    canvas.drawRRect(
      rr.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = c.lineStrong,
    );
    final t = _label(text, 13, c.text, weight: w);
    _put(canvas, t, r.center.dx - t.width / 2, r.center.dy);
  }

  pill(_speedRect(live.speed), speedLabel(live.speed), FontWeight.w700);
  pill(_backRect(live.speed), '−10 s', FontWeight.w600);
  pill(_forwardRect(live.speed), '+10 s', FontWeight.w600);

  // Transcript: dark while its panel is open.
  final tr = _transcriptRect;
  final on = live.transcriptOpen;
  canvas.drawRRect(RRect.fromRectAndRadius(tr, const Radius.circular(10)), Paint()..color = on ? c.inverse : c.side);
  final fg = on ? c.onInverse : c.text;
  paintEIcon(canvas, EIcons.transcript, Offset(tr.left + 14, tr.center.dy - 8), 16, fg);
  _put(canvas, _label('Transcript', 13, fg, weight: FontWeight.w700), tr.left + 14 + 16 + 6, tr.center.dy);
  canvas.restore();
}

/// The card's text for a PDF's text layer and search: its name and
/// transcript.
String audioText(AudioItem a) => [
      a.name,
      for (final l in a.transcript) l.text,
    ].where((s) => s.trim().isNotEmpty).join('\n');
