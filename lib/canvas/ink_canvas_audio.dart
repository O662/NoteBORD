part of 'ink_canvas.dart';

// Recordings on the canvas (Audio.png): putting a finished recording's card
// on the page, the card's buttons, moving it by its grip, a finger on ink
// written while recording playing from that moment, and, while one plays,
// the rest of the page dimmed with the ink written at that moment lit and
// "written at 12:40" beside it.

/// Ink written within this long of the stroke before is one group: what
/// lights up together.
const _inkGroupGap = 4000;

/// A group stays lit this long after its last stroke was written.
const _inkGroupStays = 15000;

/// Tapping ink plays from a little before it was written: it's written
/// after it's heard.
const _inkLeadIn = 2000;

extension _CanvasAudio on InkCanvasState {
  // Putting recordings on the page.

  void _audioChanged() {
    if (!mounted) return;
    final waiting = pane.audio.takeToPlace();
    for (final r in waiting) {
      unawaited(_placeRecording(r));
    }
    _rebuild();
  }

  /// The notebook was opened: carries on with unfinished transcripts, and
  /// puts back recordings that were cut off (the app was stopped while
  /// recording).
  Future<void> _audioOpened() async {
    final nbId = pane.notebookId;
    ref.read(transcriptionProvider.notifier).resume(nbId);
    final found = await ref.read(recordingProvider.notifier).recover(nbId);
    if (!mounted || pane.notebookId != nbId) return;
    for (final r in found) {
      await _placeRecording(r);
    }
  }

  /// Stores [r] in the notebook and puts its card on a free spot of the
  /// page shown (a recovered one goes on the page it was recorded on), and
  /// starts its transcript. One undo step.
  Future<void> _placeRecording(FinishedRecording r) async {
    final nb = ref.read(notebookProvider(pane.notebookId));
    if (r.notebookId != pane.notebookId) return;
    final recordedOn = nb.pages.where((p) => p.id == r.pageId).firstOrNull;
    final target = r.recovered && recordedOn != null && !nb.isSealed(recordedOn.id) ? recordedOn : _page;
    if (_notebook.audioClip(r.audioId) != null) {
      // Already on a page (found twice).
      await ref.read(recordingProvider.notifier).stored(r);
      return;
    }
    final asset = await _notebook.storeAudio(target.id, r.bytes, r.extension);
    if (asset == null || !mounted) {
      // Kept with the recordings in progress: it's put back when the page
      // can be written to.
      _toast('This page is locked · the recording goes on it once it’s unlocked', undo: false);
      return;
    }
    final size = AudioItem.size;
    final spot = target.id == _page.id ? _freeSpot(size, aboveKeyboard: false) : null;
    final at = spot ?? _vp.toPage(Offset(widget.chrome.left + 16, _vp.size.height - widget.chrome.bottom - size.height * _vp.scale - 60));
    final name = recordingName(target.page, _notebook.audioClips.length);
    final item = AudioItem(
      id: r.audioId,
      x: at.dx,
      y: at.dy,
      z: target.nextZ,
      createdAt: DateTime.now().toUtc(),
      asset: asset,
      name: r.recovered ? '$name (cut off)' : name,
      recordedAt: r.recordedAt,
      durationMs: r.durationMs,
      wave: r.wave,
      inkTimeline: r.ink,
    );
    _notebook.insertItems(target.id, [item]);
    ref.read(transcriptionProvider.notifier).add(pane.notebookId, item.id);
    if (r.recovered) {
      final number = nb.pages.indexWhere((p) => p.id == target.id) + 1;
      _toast('Found a recording that was cut off · it’s on page $number', undo: false);
    } else {
      _toast('Added the recording · its transcript is being made on this tablet');
    }
    // It's in the notebook now: the files it was recorded to can go.
    await ref.read(recordingProvider.notifier).stored(r);
  }

  // The card's buttons.

  /// A tap (pen or finger) on a recording's card. True if it was on one.
  bool _pressAudio(Offset at) {
    final top = topBoxAt(_page.items, at);
    if (top is! AudioItem) return false;
    final playback = ref.read(playbackProvider.notifier);
    final hit = audioHitAt(top, top.toLocal(at), speed: playback.speedOf(top.id));
    final nbId = pane.notebookId;
    void said(Future<bool> played) => unawaited(played.then((ok) {
          if (!ok && mounted) _toast(cantPlay, undo: false);
        }));
    switch (hit?.part) {
      case AudioPart.play:
        said(toggleClip(ref, nbId, top));
      case AudioPart.wave:
        said(playClipAt(ref, nbId, top, (hit!.share * top.durationMs).round()));
      case AudioPart.speed:
        unawaited(playback.nextSpeed(top.id));
      case AudioPart.back || AudioPart.forward:
        final delta = hit!.part == AudioPart.back ? -10000 : 10000;
        final play = ref.read(playbackProvider);
        if (play != null && play.isOf(nbId, top.id)) {
          unawaited(playback.skip(delta));
        } else {
          said(playback.seek(nbId, top.id, top.durationMs, math.max(0, delta), audioLoader(ref, nbId, top), play: false));
        }
      case AudioPart.transcript:
        pane.audio.toggleTranscript(top.id);
      case AudioPart.grip:
        _toast('Drag ⋮⋮ to move the recording', undo: false);
      case null:
        break;
    }
    return true;
  }

  /// A finger on ink written while a recording was made plays it from then.
  bool _jumpToInk(Offset at) {
    final clips = _notebook.audioClips.toList();
    if (clips.isEmpty) return false;
    final r = 10 * _unit;
    final ids = _page.index.query(Rect.fromCircle(center: at, radius: r));
    for (final item in _page.items.reversed) {
      if (item is! StrokeItem || !ids.contains(item.id) || !strokeHit(item, at, at, r)) continue;
      for (final (_, clip) in clips) {
        final t = clip.momentOf(item.id);
        if (t == null) continue;
        unawaited(playClipAt(ref, pane.notebookId, clip, math.max(0, t - _inkLeadIn)).then((ok) {
          if (!ok && mounted) _toast(cantPlay, undo: false);
        }));
        return true;
      }
    }
    return false;
  }

  // Moving a card by its grip (the pen or a finger; Select moves it too).

  void _startAudioMove(Offset screen, AudioItem card) {
    _drag = _Drag.audioMove;
    _audioMoving = card;
    _audioGrab = _vp.toPage(screen) - Offset(card.x, card.y);
    _tapDown = screen;
    _tapMoved = false;
  }

  void _audioMoveTo(Offset screen) {
    final card = _audioMoving;
    if (card == null) return;
    if (!_tapMoved) {
      if ((screen - _tapDown).distance <= 8) return;
      _tapMoved = true;
    }
    final at = _vp.toPage(screen) - _audioGrab;
    _overlay.ghost = card.withBox(x: at.dx, y: at.dy, w: card.w, h: card.h);
  }

  void _finishAudioMove() {
    final card = _audioMoving;
    final moved = _overlay.ghost;
    _audioMoving = null;
    _overlay.ghost = null;
    if (card == null) return;
    if (!_tapMoved || moved is! AudioItem) {
      _toast('Drag ⋮⋮ to move the recording', undo: false);
      return;
    }
    _notebook.replaceItems(_page.id, [moved]);
  }

  // While a recording plays.

  Widget _audioLayer(PageRuntime page, Brightness brightness, EndlessColors colors) => Consumer(
        builder: (context, ref, _) {
          final play = ref.watch(playbackProvider);
          final making = ref.watch(transcriptionProvider);
          return ListenableBuilder(
            listenable: pane.audio,
            builder: (context, _) {
              final mine = play != null && play.notebookId == pane.notebookId ? play : null;
              final hidden = _audioMoving?.id;
              final cards = <(AudioItem, AudioCardLive)>[
                for (final i in page.items)
                  if (i is AudioItem && i.id != hidden && (mine?.itemId == i.id || making.containsKey(i.id) || pane.audio.transcriptOf == i.id))
                    (
                      i,
                      AudioCardLive(
                        positionMs: mine?.itemId == i.id ? mine!.positionMs : 0,
                        playing: mine?.itemId == i.id && mine!.playing,
                        speed: ref.read(playbackProvider.notifier).speedOf(i.id),
                        transcriptOpen: pane.audio.transcriptOf == i.id,
                        percent: making[i.id]?.percent,
                      ),
                    ),
              ];
              _InkLight? light;
              if (mine != null) {
                final clip = _notebook.audioClip(mine.itemId)?.$2;
                if (clip == null) {
                  // Its card was deleted.
                  WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(playbackProvider.notifier).stop());
                } else if (mine.playing) {
                  light = _inkLight(page, clip, mine.positionMs);
                }
              }
              if (cards.isEmpty && light == null) return const SizedBox.shrink();
              return IgnorePointer(
                child: CustomPaint(painter: _AudioPainter(_vp, cards, light, brightness, colors)),
              );
            },
          );
        },
      );

  /// While [clip] plays at [ms]: the ink on [page] written around then.
  _InkLight _inkLight(PageRuntime page, AudioItem clip, int ms) {
    final moments = [
      for (final m in clip.inkTimeline)
        if (page[m.strokeId] case final StrokeItem s) (s, m.tMs),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    // Groups of strokes written close together.
    final groups = <List<(StrokeItem, int)>>[];
    for (final m in moments) {
      if (groups.isEmpty || m.$2 - groups.last.last.$2 > _inkGroupGap) {
        groups.add([m]);
      } else {
        groups.last.add(m);
      }
    }
    List<(StrokeItem, int)>? current;
    for (final g in groups) {
      if (g.first.$2 <= ms) current = g;
    }
    if (current != null && ms > current.last.$2 + _inkGroupStays) current = null;
    final lit = [for (final (s, t) in current ?? const <(StrokeItem, int)>[]) if (t <= ms + 300) s];
    return _InkLight(lit, current?.first.$2);
  }
}

/// The ink lit while a recording plays, and when its group was written.
class _InkLight {
  const _InkLight(this.strokes, this.writtenAt);

  final List<StrokeItem> strokes;
  final int? writtenAt;
}

/// Over the page while a recording plays: the page dimmed, the ink written
/// at that moment lit with a glow around it and "written at 12:40" above;
/// and the cards of recordings playing, being transcribed or with their
/// transcript open, as they are now.
class _AudioPainter extends CustomPainter {
  _AudioPainter(this.vp, this.cards, this.light, this.brightness, this.colors) : super(repaint: vp);

  final CanvasView vp;
  final List<(AudioItem, AudioCardLive)> cards;
  final _InkLight? light;
  final Brightness brightness;
  final EndlessColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final c = colors;
    if (light case final light?) {
      // Everything not being reached is dimmed (Audio.dc.html: 0.4).
      canvas.drawRect(Offset.zero & size, Paint()..color = c.bg.withValues(alpha: 0.6));
      if (light.strokes.isNotEmpty) {
        canvas
          ..save()
          ..translate(vp.translation.dx, vp.translation.dy)
          ..scale(vp.scale);
        var area = light.strokes.first.bounds;
        for (final s in light.strokes) {
          paintStroke(canvas, s, displayInk(s.color, brightness));
          area = area.expandToInclude(s.bounds);
        }
        canvas.restore();
        final box = Rect.fromPoints(vp.toScreen(area.topLeft), vp.toScreen(area.bottomRight)).inflate(8);
        canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(10)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = c.accent.withValues(alpha: 0.35),
        );
        if (light.writtenAt case final t?) {
          final text = TextPainter(
            text: TextSpan(
              text: 'written at ${clockOf(t)}',
              style: TextStyle(fontFamily: FontFamilies.ui, fontSize: 12, fontWeight: FontWeight.w700, color: c.onAccent),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          final pill = Rect.fromLTWH(box.right - text.width - 18 - 4, box.top - 18, text.width + 18, 22);
          canvas.drawRRect(RRect.fromRectAndRadius(pill, const Radius.circular(999)), Paint()..color = c.accent);
          text
            ..paint(canvas, Offset(pill.left + 9, pill.center.dy - text.height / 2))
            ..dispose();
        }
      }
    }
    for (final (card, live) in cards) {
      canvas
        ..save()
        ..translate(vp.translation.dx, vp.translation.dy)
        ..scale(vp.scale)
        ..translate(card.center.dx, card.center.dy);
      if (card.rotation != 0) canvas.rotate(card.angle);
      canvas.translate(-card.w / 2, -card.h / 2);
      paintAudioCard(canvas, card, c, live: live);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_AudioPainter old) => true;
}
