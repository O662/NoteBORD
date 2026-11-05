import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/recording.dart';
import '../../audio/transcript_lines.dart' show clockOf;
import '../../theme/colors.dart';
import '../common.dart';

/// Audio.png's recording pill under the top bar: a red dot, "Recording ·
/// 0:42", the last moments' loudness, Pause (Resume) and Stop. It shows
/// whichever notebook is open, since the recording keeps going.
class RecordingPill extends ConsumerWidget {
  const RecordingPill({super.key, required this.onStop});

  final VoidCallback onStop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(recordingProvider);
    if (s == null) return const SizedBox.shrink();
    final c = context.colors;
    final rec = ref.read(recordingProvider.notifier);
    final word = s.stopping ? 'Saving' : (s.paused ? 'Paused' : 'Recording');
    return Semantics(
      container: true,
      liveRegion: false,
      label: '$word, ${clockOf(s.elapsedMs)}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 3, 4, 3),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.clayLine),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: c.shadow.withValues(alpha: c.shadow.a * 0.7), offset: const Offset(0, 8), blurRadius: 18, spreadRadius: -12)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 10, children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: s.paused ? c.textFaint : c.record,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: (s.paused ? c.textFaint : c.record).withValues(alpha: 0.18), spreadRadius: 4)],
            ),
          ),
          ExcludeSemantics(
            child: Text(
              '$word · ${clockOf(s.elapsedMs)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: c.recordDeep,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          ExcludeSemantics(
            child: CustomPaint(size: const Size(70, 20), painter: _LevelsPainter(s.paused ? const [] : s.recent, c.record)),
          ),
          ChromeButton(
            label: s.paused ? 'Resume recording' : 'Pause recording',
            onPressed: s.stopping ? null : (s.paused ? rec.resume : rec.pause),
            background: c.clayTint,
            foreground: c.recordDeep,
            radius: 10,
            child: CustomPaint(size: const Size(16, 16), painter: _GlyphPainter(paused: s.paused, color: c.recordDeep)),
          ),
          ChromeButton(
            label: 'Stop recording',
            onPressed: s.stopping ? null : onStop,
            width: null,
            padding: 14,
            background: c.record,
            foreground: c.onAccent,
            radius: 10,
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
              Container(
                width: 10.5,
                height: 10.5,
                decoration: BoxDecoration(color: c.onAccent, borderRadius: BorderRadius.circular(1.5)),
              ),
              Text('Stop', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.onAccent)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// The last dozen loudness readings as rounded bars (Audio.dc.html's 70×20
/// waveform).
class _LevelsPainter extends CustomPainter {
  _LevelsPainter(this.levels, this.color);

  final List<double> levels;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      final v = i < 12 - levels.length ? 0.0 : levels[i - (12 - levels.length)];
      final h = (v * 16).clamp(0.0, 16.0);
      final x = 2 + i * 6.0;
      canvas.drawLine(Offset(x, 10 - h / 2), Offset(x, 10 + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_LevelsPainter old) => old.levels != levels || old.color != color;
}

/// Pause bars, or a play triangle when paused.
class _GlyphPainter extends CustomPainter {
  _GlyphPainter({required this.paused, required this.color});

  final bool paused;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    final p = Paint()..color = color;
    if (paused) {
      canvas.drawPath(Path()..moveTo(8 * k, 5 * k)..lineTo(8 * k, 19 * k)..lineTo(19 * k, 12 * k)..close(), p);
    } else {
      canvas
        ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(6 * k, 5 * k, 4 * k, 14 * k), Radius.circular(k)), p)
        ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(14 * k, 5 * k, 4 * k, 14 * k), Radius.circular(k)), p);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.paused != paused || old.color != color;
}
