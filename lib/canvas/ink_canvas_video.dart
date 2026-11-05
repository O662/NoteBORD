part of 'ink_canvas.dart';

// Videos on the canvas (Video.png): putting one on the page, its card's
// buttons and timeline, the "▶ 0:12" chips of notes pinned to moments, and,
// over the card, the video itself while it's loaded, with the card's
// timeline, time and pins drawn as they are now.

extension _CanvasVideo on InkCanvasState {
  void _videoChanged() {
    if (!mounted) return;
    for (final v in pane.video.takeToPlace()) {
      _placeVideo(v);
    }
    _rebuild();
  }

  /// Puts [v] on a free spot of the page (one undo step), selected.
  void _placeVideo(VideoItem v) {
    if (!_canInk) return;
    final size = Size(v.w, v.h);
    final at = _freeSpot(size, aboveKeyboard: false) ?? _vp.toPage(Offset(widget.chrome.left + 16, widget.chrome.top + 16));
    _dismissToast();
    _notebook.insertItems(_page.id, [v.withBox(x: at.dx, y: at.dy, w: v.w, h: v.h)]);
    pane.video.select(v.id);
    _toast(v.link != null
        ? 'Added the video · it’s big, so it stays on this tablet and the page keeps a link'
        : 'Added the video · Note at pins a note to a moment');
  }

  /// The moments notes are pinned to on [v] (its chips on this page).
  List<int> _pinsOf(String videoId) => [for (final c in pinsOf(_page.items, videoId)) c.tMs]..sort();

  /// A tap (pen or finger) on a video's card or a pin chip. True if it was
  /// on one.
  bool _pressVideo(Offset at) {
    final top = topBoxAt(_page.items, at);
    final nbId = pane.notebookId;
    final playback = ref.read(videoPlaybackProvider.notifier);
    void said(Future<bool> done) => unawaited(done.then((ok) {
          if (!ok && mounted) _toast('This video can’t be played here', undo: false);
        }));
    switch (top) {
      case final VideoPinItem pin:
        final v = _page[pin.video];
        if (v is! VideoItem) {
          _toast('Its video is gone from this page', undo: false);
          return true;
        }
        pane.video.select(v.id);
        said(playback.seek(nbId, v, pin.tMs));
        return true;
      case final VideoItem v:
        final hit = videoHitAt(v, v.toLocal(at), pins: _pinsOf(v.id));
        pane.video.select(v.id);
        switch (hit?.part) {
          case VideoPart.screen || VideoPart.play || VideoPart.playSmall:
            said(playback.toggle(nbId, v));
          case VideoPart.timeline:
            said(playback.seek(nbId, v, v.from + ((v.to - v.from) * hit!.share).round(), play: ref.read(videoPlaybackProvider)?.playing ?? false));
          case VideoPart.pin:
            said(playback.seek(nbId, v, hit!.pinMs!));
          case VideoPart.speed:
            unawaited(playback.nextSpeed(v.id));
          case VideoPart.note:
            pinNote(ref, pane, v);
          case VideoPart.grab:
            unawaited(grabFrame(ref, pane, v));
          case VideoPart.popOut:
            _toast('Pop out comes later · for now the video plays on the page', undo: false);
          case VideoPart.fullScreen:
            unawaited(playback.toggle(nbId, v).then((ok) async {
              if (!ok || !mounted) return;
              // Full screen plays it; leaving goes back to the page.
              if (!(ref.read(videoPlaybackProvider)?.playing ?? false)) await playback.toggle(nbId, v);
              if (mounted) await showVideoFullScreen(context, nbId, v);
            }));
          case null:
            break;
        }
        return true;
      default:
        // A tap elsewhere: the video's bar goes.
        pane.video.select(null);
        return false;
    }
  }

  // Dragging along a timeline (a video's, or a recording's waveform).

  /// Whether [page] on [box] is on its timeline.
  bool _scrubbable(BoxItem box, Offset page) => switch (box) {
        final VideoItem v => switch (videoHitAt(v, v.toLocal(page), pins: _pinsOf(v.id))?.part) {
            VideoPart.timeline || VideoPart.pin => true,
            _ => false,
          },
        final AudioItem a => audioHitAt(a, a.toLocal(page))?.part == AudioPart.wave,
        _ => false,
      };

  /// Where on [box]'s timeline [screen] is (ms), snapping to a pin's dot.
  (int, bool) _scrubMoment(BoxItem box, Offset screen) {
    final local = box.toLocal(_vp.toPage(screen));
    switch (box) {
      case final VideoItem v:
        final hit = videoHitAt(v, Offset(local.dx, videoPartRect(VideoPart.timeline).center.dy * v.unit), pins: _pinsOf(v.id));
        if (hit?.pinMs case final ms?) return (ms, true);
        final share = ((local.dx / v.unit - 12) / 676).clamp(0.0, 1.0);
        return (v.from + ((v.to - v.from) * share).round(), false);
      case final AudioItem a:
        final wave = audioPartRect(AudioPart.wave);
        final share = ((local.dx / a.unit - wave.left) / wave.width).clamp(0.0, 1.0);
        return ((a.durationMs * share).round(), false);
      default:
        return (0, false);
    }
  }

  void _startScrub(Offset screen, BoxItem box) {
    _drag = _Drag.scrub;
    _scrubId = box.id;
    _tapDown = screen;
    _tapMoved = false;
    final nbId = pane.notebookId;
    if (box is VideoItem) {
      pane.video.select(box.id);
      final s = ref.read(videoPlaybackProvider);
      _scrubWasPlaying = s != null && s.isOf(nbId, box.id) && s.playing;
    } else {
      final s = ref.read(playbackProvider);
      _scrubWasPlaying = s != null && s.isOf(nbId, box.id) && s.playing;
    }
    final (ms, onPin) = _scrubMoment(box, screen);
    _scrubOnPin = onPin;
    _sendScrub(box, ms, play: false);
  }

  void _scrubTo(Offset screen) {
    final box = _scrubId == null ? null : _page[_scrubId!];
    if (box is! BoxItem) return;
    if (!_tapMoved && (screen - _tapDown).distance > 4) _tapMoved = true;
    if (!_tapMoved) return;
    _sendScrub(box, _scrubMoment(box, screen).$1, play: false);
  }

  /// Let go: it stays where it was dragged to, playing if it was (a tap on
  /// a pin's dot, or on a recording's waveform, plays from there).
  void _finishScrub() {
    final id = _scrubId;
    _scrubId = null;
    final box = id == null ? null : _page[id];
    if (box is! BoxItem) return;
    final play = _scrubWasPlaying || (!_tapMoved && (_scrubOnPin || box is AudioItem));
    // Where it was dragged to (or tapped).
    _sendScrub(box, _scrubAt, play: play);
  }

  /// Seeks [box] to [ms], one seek at a time (the latest wanted wins).
  /// The first one pauses it, so the picture follows the finger.
  void _sendScrub(BoxItem box, int ms, {required bool play}) {
    _scrubWant = (ms, play);
    _scrubAt = ms;
    if (_scrubBusy) return;
    _scrubBusy = true;
    final nbId = pane.notebookId;
    unawaited(() async {
      try {
        var paused = false;
        while (_scrubWant != null && mounted) {
          final (to, go) = _scrubWant!;
          _scrubWant = null;
          bool ok;
          switch (box) {
            case final VideoItem v:
              final video = ref.read(videoPlaybackProvider.notifier);
              if (!paused) {
                await video.pause();
                paused = true;
              }
              ok = await video.seek(nbId, _page[v.id] is VideoItem ? _page[v.id]! as VideoItem : v, to, play: go);
            case final AudioItem a:
              final audio = ref.read(playbackProvider.notifier);
              if (!paused) {
                await audio.pause();
                paused = true;
              }
              ok = await audio.seek(nbId, a.id, a.durationMs, to, audioLoader(ref, nbId, a), play: go);
            default:
              ok = true;
          }
          if (!ok && mounted) {
            _scrubWant = null;
            _toast(box is VideoItem ? 'This video can’t be played here' : cantPlay, undo: false);
          }
        }
      } finally {
        _scrubBusy = false;
      }
    }());
  }

  /// The video loaded (over its card), and every video's timeline and
  /// chips as they are now.
  Widget _videoLayer(PageRuntime page, EndlessColors colors) => Consumer(
        builder: (context, ref, _) {
          final play = ref.watch(videoPlaybackProvider);
          return ListenableBuilder(
            listenable: Listenable.merge([pane.video, _vp]),
            builder: (context, _) {
              final videos = [for (final i in page.items) if (i is VideoItem) i];
              final chips = [for (final i in page.items) if (i is VideoPinItem) i];
              if (videos.isEmpty && chips.isEmpty) return const SizedBox.shrink();
              final mine = play != null && play.notebookId == pane.notebookId ? play : null;
              if (mine != null && !mine.loading && _notebook.videoClip(mine.itemId) == null) {
                // Its card was deleted.
                WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(videoPlaybackProvider.notifier).stop());
              }
              final hidden = _hidden();
              final playing = mine == null ? null : page[mine.itemId];
              final handle = ref.read(videoPlaybackProvider.notifier).handle;
              final showPicture = playing is VideoItem && !hidden.contains(playing.id) && handle != null && !mine!.loading;
              return IgnorePointer(
                child: Stack(fit: StackFit.expand, children: [
                  if (showPicture)
                    Positioned.fill(
                      child: ClipRect(
                        child: Transform(
                          transform: _vp.matrix,
                          child: Stack(clipBehavior: Clip.none, children: [
                            Positioned(
                              left: playing.x,
                              top: playing.y,
                              width: playing.w,
                              height: VideoItem.screen.height * playing.unit,
                              child: Transform.rotate(
                                angle: playing.angle,
                                origin: Offset(0, playing.h / 2 - VideoItem.screen.height * playing.unit / 2),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(16 * playing.unit)),
                                  child: ColoredBox(
                                    color: colors.videoScreen,
                                    child: Center(child: AspectRatio(aspectRatio: handle.aspect, child: handle.view())),
                                  ),
                                ),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  CustomPaint(
                    painter: _VideoPainter(
                      _vp,
                      [
                        for (final v in videos)
                          if (!hidden.contains(v.id))
                            (
                              v,
                              VideoCardLive(
                                positionMs: mine?.itemId == v.id ? mine!.positionMs : null,
                                playing: mine?.itemId == v.id && mine!.playing,
                                speed: ref.read(videoPlaybackProvider.notifier).speedOf(v.id),
                                pins: _pinsOf(v.id),
                                loading: mine?.itemId == v.id && mine!.loading,
                              ),
                              showPicture && v.id == playing.id,
                              pane.video.selected == v.id,
                            ),
                      ],
                      [
                        for (final c in chips)
                          if (!hidden.contains(c.id))
                            (c, mine != null && mine.itemId == c.video && (c.tMs - mine.positionMs).abs() <= 1000),
                      ],
                      colors,
                    ),
                  ),
                ]),
              );
            },
          );
        },
      );
}

/// Each video's card as it is now (over the still in the page's picture,
/// or around the playing video), its selection outline, and the chips of
/// the one playing, orange at their moment.
class _VideoPainter extends CustomPainter {
  _VideoPainter(this.vp, this.cards, this.chips, this.colors);

  final CanvasView vp;

  /// (video, how it is, its picture is playing over it, selected).
  final List<(VideoItem, VideoCardLive, bool, bool)> cards;
  final List<(VideoPinItem, bool)> chips;
  final EndlessColors colors;

  void _at(Canvas canvas, BoxItem item, void Function() paint) {
    canvas
      ..save()
      ..translate(vp.translation.dx, vp.translation.dy)
      ..scale(vp.scale)
      ..translate(item.center.dx, item.center.dy);
    if (item.rotation != 0) canvas.rotate(item.angle);
    canvas.translate(-item.w / 2, -item.h / 2);
    paint();
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final view = Offset.zero & size;
    for (final (v, live, _, selected) in cards) {
      final r = Rect.fromPoints(vp.toScreen(v.bounds.topLeft), vp.toScreen(v.bounds.bottomRight));
      if (!r.overlaps(view)) continue;
      _at(canvas, v, () {
        paintVideoCard(canvas, v, colors, live: live, screen: false);
        if (selected) {
          canvas.drawRRect(
            RRect.fromRectAndRadius((Offset.zero & Size(v.w, v.h)).inflate(5 * v.unit), Radius.circular(20 * v.unit)),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2 * v.unit
              ..color = colors.accent,
          );
        }
      });
    }
    for (final (c, near) in chips) {
      if (!near) continue;
      _at(canvas, c, () => paintVideoPin(canvas, c, colors, near: true));
    }
  }

  @override
  bool shouldRepaint(_VideoPainter old) => true;
}
