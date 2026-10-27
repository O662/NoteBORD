part of 'ink_canvas.dart';

// Charts and live items on the canvas (Charts.png, LiveItems.png): what the
// Live items bar adds, drawing clocks, the date and "time ago" again as
// they change, the dashed links between charts and their tables and
// sheets, and the buttons on them: a chart's type and Data, a clock's
// Analog and Digital, a time stamp, and a checklist's boxes.

extension _CanvasLive on InkCanvasState {
  bool _isLive(BoxItem? item) => item is ChartItem || item is LiveItem || item is ChecklistItem;

  // Adding from the Live items bar.

  void _liveChanged() {
    if (!mounted) return;
    final wanted = pane.live.takeWanted();
    if (wanted.isEmpty) return;
    // After this notification is over: adding changes the page. Nothing
    // else may be drawing, so a frame is asked for.
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (!mounted) return;
        for (final kind in wanted) {
          _addLive(kind);
        }
      })
      ..scheduleFrame();
  }

  /// Puts [kind] on a free spot on screen (a time stamp under the last one
  /// showing). One undo step each.
  void _addLive(LiveKind kind) {
    if (!_canInk) return;
    final page = _page;
    final now = DateTime.now().toUtc();
    final BoxItem item = switch (kind) {
      LiveKind.clock => newLiveItem(const ClockData(), Offset.zero, z: page.nextZ, now: now),
      LiveKind.date => newLiveItem(const DateData(), Offset.zero, z: page.nextZ, now: now),
      LiveKind.stamp => newLiveItem(StampData(liveNow().toUtc()), Offset.zero, z: page.nextZ, now: now),
      LiveKind.checklist => newChecklist(Offset.zero, z: page.nextZ, now: now),
    };
    final size = Size(item.w, item.h);
    final corner = _vp.toPage(Offset(widget.chrome.left + 16, widget.chrome.top + 16));
    // A checklist needs room to grow.
    final at = kind == LiveKind.stamp
        ? _stampSpot(size)
        : (_freeSpot(kind == LiveKind.checklist ? Size(size.width, size.height + 140) : size, aboveKeyboard: false) ?? corner);
    _dismissToast();
    _notebook.insertItems(page.id, [item.withBox(x: at.dx, y: at.dy, w: item.w, h: item.h)]);
    if (item case LiveItem(data: final StampData s)) {
      _toast('Stamped ${clockText(s.at.toLocal(), seconds: false)} · write beside it');
    } else {
      _toast(kind == LiveKind.checklist ? 'Added a checklist · write an item in it' : 'Added ${kind.noun} to the page');
    }
  }

  /// Where a new time stamp goes: under the latest one on screen, below
  /// what's written beside it (LiveItems.png's notes), or a free spot
  /// with room to write beside it.
  Offset _stampSpot(Size size) {
    final view = _vp.visiblePage;
    LiveItem? last;
    for (final i in _page.items) {
      if (i case LiveItem(data: final StampData s) when view.overlaps(i.extent)) {
        if (last == null || s.at.isAfter((last.data as StampData).at)) last = i;
      }
    }
    if (last != null) {
      final r = last.extent;
      final line = Rect.fromLTRB(r.left, r.top - 4, r.right + 600 * last.unit, r.bottom + 4);
      var next = r.bottom + 17 * last.unit;
      for (final id in _page.index.query(line)) {
        if (_page[id] case final StrokeItem s when s.bounds.overlaps(line)) next = math.max(next, s.bounds.bottom + 8 * last.unit);
      }
      final at = Offset(last.x, next);
      if (view.contains(at + Offset(size.width, size.height))) return at;
    }
    return _freeSpot(Size(size.width + 360, size.height + 8), aboveKeyboard: false) ??
        _vp.toPage(Offset(widget.chrome.left + 16, widget.chrome.top + 16));
  }

  // Clocks, the date and "time ago" change by themselves.

  /// Keeps a once-a-second check going while [page] has anything that
  /// changes with time.
  void _watchLive(PageRuntime page) {
    final any = liveKey(page.items, liveNow()).isNotEmpty;
    if (any && _liveTimer == null) {
      _liveShown = '';
      _liveTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickLive());
    } else if (!any && _liveTimer != null) {
      _liveTimer!.cancel();
      _liveTimer = null;
    }
  }

  /// Draws the items near the view again when what they show has changed.
  void _tickLive() {
    if (!mounted) return;
    final page = _page;
    final view = _vp.visiblePage;
    final near = page.index.query(view.inflate(view.longestSide / 2));
    final key = liveKey([for (final id in near) ?page[id]], liveNow());
    if (key == _liveShown) return;
    _liveShown = key;
    page.refreshLive();
    _liveTick.value++;
  }

  // Charts' links.

  /// The dashed lines from each live chart's table or sheet to the chart,
  /// with the link badge (Charts.png). Not part of the page: never in
  /// thumbnails or exports.
  Widget _chartLinks(PageRuntime page, EndlessColors colors) {
    final links = <_ChartLink>[];
    for (final i in page.items) {
      if (i is! ChartItem || !i.live) continue;
      if (page[i.source!.ref] case final BoxItem source) {
        final (a, b, across) = chartLinkEnds(source, i);
        links.add(_ChartLink(a, b, across, i.source!.isExcel ? colors.accent : colors.green, chartLinkColor(i, colors)));
      }
    }
    if (links.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(child: CustomPaint(painter: _ChartLinkPainter(_vp, links, colors)));
  }

  // Buttons on charts and live items.

  /// A tap on a chart's or live item's button.
  bool _pressLiveControl(Offset at) {
    switch (topBoxAt(_page.items, at)) {
      case final ChartItem chart:
        switch (chartHitAt(chart, chart.toLocal(at))) {
          case ChartTypeHit(:final type):
            // Not an undo step: how it's shown, like a graph's view.
            if (type != chart.chartType) _quietly(chart.copyWith(chartType: type));
          case ChartDataHit():
            _editChartData(chart);
          case null:
            return false;
        }
        return true;
      case final LiveItem live:
        switch ((live.data, liveHitAt(live, live.toLocal(at)))) {
          case (final ClockData d, final LivePart part?) when part != LivePart.stamp:
            final analog = part == LivePart.analog;
            if (d.analog != analog) _quietly(live.copyWith(data: ClockData(analog: analog, rest: d.rest)));
          case (final StampData s, LivePart.stamp):
            _turnStamps(!s.ago);
          default:
            return false;
        }
        return true;
      case final ChecklistItem list:
        final i = checklistBoxAt(list, list.toLocal(at));
        if (i == null) return false;
        _tick(list, i, !list.entries[i].done);
        return true;
      default:
        return false;
    }
  }

  /// Every time stamp on the page shows clock time, or how long ago
  /// (LiveItems.png's one switch for the notes). Not an undo step.
  void _turnStamps(bool ago) {
    for (final i in [..._page.items]) {
      if (i case LiveItem(data: final StampData s) when s.ago != ago) _quietly(i.copyWith(data: StampData(s.at, ago: ago)));
    }
    _toast(ago ? 'Time stamps show how long ago' : 'Time stamps show the time', undo: false);
  }

  void _tick(ChecklistItem list, int i, bool done) {
    if (list.entries[i].done == done) return;
    _dismissToast();
    _notebook.replaceItems(_page.id, [list.copyWith(entries: [...list.entries]..[i] = list.entries[i].copyWith(done: done))]);
  }

  /// The pen drew from [screen] instead of tapping: on a checklist's box,
  /// that's a tick.
  void _tickDrawn(Offset screen) {
    final at = _vp.toPage(screen);
    if (topBoxAt(_page.items, at) case final ChecklistItem list) {
      if (checklistBoxAt(list, list.toLocal(at)) case final i?) _tick(list, i, true);
    }
  }

  // Editing them.

  void _editChartData(ChartItem chart) => editChartData(context, ref, pane, chart);

  Future<void> _editChecklist(ChecklistItem list) async {
    final pageId = _page.id;
    final edited = await showChecklistEditor(context, list);
    if (edited == null || !mounted || _page.id != pageId) return;
    _notebook.replaceItems(pageId, [edited]);
    _toast('Changed the checklist');
  }
}

/// A link from a chart's source to the chart, in page space: its ends, the
/// direction it leaves in, its color and its badge's.
class _ChartLink {
  const _ChartLink(this.from, this.to, this.across, this.color, this.ink);

  final Offset from, to, across;
  final Color color, ink;
}

class _ChartLinkPainter extends CustomPainter {
  _ChartLinkPainter(this.vp, this.links, this.colors) : super(repaint: vp);

  final CanvasView vp;
  final List<_ChartLink> links;
  final EndlessColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..translate(vp.translation.dx, vp.translation.dy)
      ..scale(vp.scale);
    for (final l in links) {
      final a = l.from, b = l.to;
      // Charts.dc.html's curve: out level from one, in level to the other.
      final path = Path()..moveTo(a.dx, a.dy);
      if (l.across.dy == 0) {
        final mid = (a.dx + b.dx) / 2;
        path.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
      } else {
        final mid = (a.dy + b.dy) / 2;
        path.cubicTo(a.dx, mid, b.dx, mid, b.dx, b.dy);
      }
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = l.color;
      final metric = path.computeMetrics().firstOrNull;
      if (metric == null) continue;
      for (var d = 0.0; d < metric.length; d += 11) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 6, metric.length)), line);
      }
      final mid = metric.getTangentForOffset(metric.length / 2)?.position ?? (a + b) / 2;
      canvas
        ..drawCircle(mid, 15, Paint()..color = colors.surface)
        ..drawCircle(mid, 14.25, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = l.color);
      paintEIcon(canvas, EIcons.link, mid - const Offset(7.5, 7.5), 15, l.ink);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ChartLinkPainter old) => true;
}
