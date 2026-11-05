import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/transcript_lines.dart' show clockOf;
import '../../board/model.dart';
import '../../theme/colors.dart';
import '../../video/video_playback.dart';
import '../common.dart';
import '../icons.dart';

/// Full screen (Video.png's control row): the video playing, filling the
/// screen, with play/pause, the timeline and the time. The same player as
/// on the page, so it carries on there when this closes.
Future<void> showVideoFullScreen(BuildContext context, String notebookId, VideoItem v) =>
    Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, _, _) => VideoFullScreen(notebookId: notebookId, video: v),
      transitionsBuilder: (context, a, _, child) => FadeTransition(opacity: a, child: child),
    ));

class VideoFullScreen extends ConsumerWidget {
  const VideoFullScreen({super.key, required this.notebookId, required this.video});

  final String notebookId;
  final VideoItem video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final s = ref.watch(videoPlaybackProvider);
    final playback = ref.read(videoPlaybackProvider.notifier);
    final handle = s != null && s.isOf(notebookId, video.id) ? playback.handle : null;
    final pos = s?.positionMs ?? video.from;
    return Scaffold(
      backgroundColor: c.video,
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Center(
              child: handle == null
                  ? Text('Opening…', style: TextStyle(color: c.videoMuted))
                  : AspectRatio(aspectRatio: handle.aspect, child: handle.view()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(spacing: 8, children: [
              ChromeButton(
                label: s?.playing ?? false ? 'Pause' : 'Play',
                icon: s?.playing ?? false ? EIcons.pause : EIcons.play,
                foreground: c.videoText,
                onPressed: () => playback.toggle(notebookId, video),
              ),
              Text(
                '${clockOf(pos)} / ${clockOf(video.to)}',
                style: TextStyle(color: c.videoText, fontSize: 13, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: c.videoPlayed,
                    inactiveTrackColor: c.videoTrack,
                    thumbColor: c.videoText,
                  ),
                  child: Slider(
                    value: pos.clamp(video.from, video.to).toDouble(),
                    min: video.from.toDouble(),
                    max: video.to.toDouble().clamp(video.from + 1.0, double.infinity),
                    semanticFormatterCallback: (v) => clockOf(v.round()),
                    onChanged: (v) => playback.seek(notebookId, video, v.round(), play: s?.playing ?? false),
                  ),
                ),
              ),
              ChromeButton(
                label: 'Leave full screen',
                icon: EIcons.close,
                foreground: c.videoText,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
