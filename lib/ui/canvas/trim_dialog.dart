import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../audio/transcript_lines.dart' show clockOf;
import '../../theme/colors.dart';
import '../dialogs.dart';

/// Trim (Video.png's Video selected bar): where the video starts and stops
/// playing, with its frames in a strip and the frame at the end being moved
/// shown large. The file isn't cut: "Whole video" puts it back. Returns
/// (from, to) in ms, or null when cancelled.
Future<(int, int)?> showTrimDialog(
  BuildContext context, {
  required int durationMs,
  required int from,
  required int to,
  Future<List<Uint8List>> Function()? strip,
  Future<Uint8List?> Function(int ms)? frame,
}) =>
    showEndlessDialog<(int, int)>(
      context,
      builder: (context) => _TrimDialog(durationMs: durationMs, from: from, to: to, strip: strip, frame: frame),
    );

class _TrimDialog extends StatefulWidget {
  const _TrimDialog({required this.durationMs, required this.from, required this.to, this.strip, this.frame});

  final int durationMs;
  final int from;
  final int to;
  final Future<List<Uint8List>> Function()? strip;
  final Future<Uint8List?> Function(int ms)? frame;

  @override
  State<_TrimDialog> createState() => _TrimDialogState();
}

class _TrimDialogState extends State<_TrimDialog> {
  late RangeValues _range = RangeValues(widget.from.toDouble(), widget.to.toDouble());
  List<Uint8List>? _strip;
  Uint8List? _frame;
  int _asked = 0;
  RangeValues? _dragFrom;

  /// At least a second plays.
  static const _least = 1000.0;

  @override
  void initState() {
    super.initState();
    widget.strip?.call().then((s) {
      if (mounted) setState(() => _strip = s);
    });
    _show(widget.from);
  }

  Future<void> _show(int ms) async {
    final ask = ++_asked;
    final f = await widget.frame?.call(ms);
    if (mounted && ask == _asked && f != null) setState(() => _frame = f);
  }

  void _changed(RangeValues r) {
    if (r.end - r.start < _least) return;
    setState(() => _range = r);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final duration = widget.durationMs.toDouble().clamp(_least, double.infinity);
    final from = _range.start.round(), to = _range.end.round();
    return DialogFrame(
      title: 'Trim',
      width: 720,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
        Text(
          'Choose where it starts and stops playing. The video itself isn’t cut: Whole video brings back the rest.',
          style: TextStyle(fontSize: 14, height: 1.4, color: c.textMuted),
        ),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            decoration: BoxDecoration(color: c.videoScreen, borderRadius: BorderRadius.circular(12)),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: _frame == null
                ? Text('The frame shows here', style: TextStyle(color: c.videoMuted, fontSize: 13))
                : Image.memory(_frame!, fit: BoxFit.contain, gaplessPlayback: true),
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
          ExcludeSemantics(
            child: Container(
              height: 52,
              decoration: BoxDecoration(color: c.videoScreen, borderRadius: BorderRadius.circular(8)),
              clipBehavior: Clip.antiAlias,
              child: Stack(fit: StackFit.expand, children: [
                if (_strip case final s? when s.isNotEmpty)
                  Row(children: [for (final f in s) Expanded(child: Image.memory(f, fit: BoxFit.cover, gaplessPlayback: true))]),
                // What doesn't play is dimmed.
                LayoutBuilder(builder: (context, box) {
                  final a = box.maxWidth * from / duration, b = box.maxWidth * to / duration;
                  return Stack(children: [
                    Positioned(left: 0, top: 0, bottom: 0, width: a, child: ColoredBox(color: c.scrim)),
                    Positioned(left: b, top: 0, bottom: 0, right: 0, child: ColoredBox(color: c.scrim)),
                    Positioned(
                      left: a,
                      width: b - a,
                      top: 0,
                      bottom: 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(border: Border.all(color: c.videoPin, width: 3), borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  ]);
                }),
              ]),
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: c.videoPin,
              inactiveTrackColor: c.lineStrong,
              thumbColor: c.text,
              overlayColor: c.videoPin.withValues(alpha: 0.2),
              rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 11),
            ),
            child: RangeSlider(
              values: _range,
              max: duration,
              labels: RangeLabels(clockOf(from), clockOf(to)),
              semanticFormatterCallback: (v) => clockOf(v.round()),
              onChanged: _changed,
              onChangeStart: (r) => _dragFrom = r,
              // The frame at the end that was moved.
              onChangeEnd: (r) => _show((_dragFrom != null && r.end != _dragFrom!.end ? r.end : r.start).round()),
            ),
          ),
          Semantics(
            liveRegion: true,
            child: Text(
              'Starts ${clockOf(from)} · Stops ${clockOf(to)} · Plays ${clockOf(to - from)}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        ]),
        Row(spacing: 10, children: [
          SecondaryButton(
            label: 'Whole video',
            onPressed: () {
              setState(() => _range = RangeValues(0, duration));
              _show(0);
            },
          ),
          const Spacer(),
          SecondaryButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
          PrimaryButton(label: 'Trim', onPressed: () => Navigator.of(context).pop((from, to))),
        ]),
      ]),
    );
  }
}
