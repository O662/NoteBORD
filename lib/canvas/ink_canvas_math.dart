part of 'ink_canvas.dart';

// Math on the canvas (Math.png): in math mode the ink just written is
// picked up when the pen rests, with "Convert to math", "Graph it" and
// "Copy as LaTeX" and a live preview; math on the page is edited with the
// math keyboard.

/// How long the pen rests before what it wrote is picked up.
const mathPickUpDelay = Duration(milliseconds: 1200);

/// The math just written: [last] and the strokes near it (and near those),
/// out of [strokes]. Near is within a symbol's height.
List<StrokeItem> mathGroup(List<StrokeItem> strokes, StrokeItem last) {
  final heights = [
    for (final s in strokes)
      if (s.bounds.height >= s.bounds.width * 0.5) s.bounds.height,
  ]..sort();
  final gap = math.max(12.0, heights.isEmpty ? 24.0 : heights[heights.length ~/ 2] * 0.9);
  final group = <StrokeItem>{last};
  var area = last.bounds;
  var grew = true;
  while (grew) {
    grew = false;
    for (final s in strokes) {
      if (!group.contains(s) && s.bounds.inflate(gap).overlaps(area)) {
        group.add(s);
        area = area.expandToInclude(s.bounds);
        grew = true;
      }
    }
  }
  return [for (final s in strokes) if (group.contains(s)) s];
}

extension _CanvasMath on InkCanvasState {
  MathMode get _math => pane.math;

  MathReader get _reader => ref.read(mathReaderProvider);

  MathPictures get _pictures => ref.read(mathPicturesProvider);

  void _mathChanged() {
    if (!mounted) return;
    if (_math.takeWantedTool() case final kind?) {
      // After this notification is over: adding changes the page.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _addTool(kind);
      });
    }
    if (!_math.on) {
      _mathIdle?.cancel();
      _mathInk.clear();
      if (_selection.menu == SelectionMenu.math) {
        _selection
          ..clear()
          ..menu = SelectionMenu.convert;
      }
    }
    _watchDraft();
    _rebuild(() {});
  }

  // Writing math: what the pen wrote is picked up when it rests.

  void _wroteMath(StrokeItem stroke) {
    if (!_math.on || _inkTarget != null) return;
    _mathInk.add(stroke.id);
    _mathIdle?.cancel();
    _mathIdle = Timer(mathPickUpDelay, _pickUpMath);
  }

  void _pickUpMath() {
    if (!mounted || !_math.on || _drawPointer != null || _math.draft != null) return;
    final ink = [
      for (final i in _page.items)
        if (i is StrokeItem && _mathInk.contains(i.id)) i,
    ];
    if (ink.isEmpty) return;
    final group = mathGroup(ink, ink.last);
    final area = group.map((s) => s.bounds).reduce((a, b) => a.expandToInclude(b)).inflate(14 * _unit);
    _selection
      ..menu = SelectionMenu.math
      ..select(
        [for (final s in group) s.id],
        outline: Path()..addRRect(RRect.fromRectAndRadius(area, Radius.circular(math.min(area.shortestSide / 2, 40 * _unit)))),
        revision: _nb.revision,
      );
  }

  /// The selected strokes on the page (what Convert to math reads).
  List<StrokeItem> _selectedInk() => [
        for (final i in _page.items)
          if (i is StrokeItem && _selection.ids.contains(i.id)) i,
      ];

  /// A math selection changed: read it for the preview.
  void _mathSelectionChanged() {
    final ink = _selection.menu == SelectionMenu.math ? _selectedInk() : const <StrokeItem>[];
    final ids = {for (final s in ink) s.id};
    if (setEquals(ids, _previewFor)) return;
    _previewFor = ids;
    final run = ++_previewRun;
    if (ink.isEmpty) {
      if (_preview != null) _rebuild(() => _preview = null);
      return;
    }
    _rebuild(() {
      _preview = PreviewState.reading;
      _previewLatex = null;
    });
    final reader = _reader;
    reader.read(ink).then((reading) {
      if (!mounted || run != _previewRun) return;
      if (reading != null) _pictures.load(reading.latex);
      _rebuild(() {
        _previewLatex = reading?.latex;
        _preview = reading != null
            ? PreviewState.read
            : (reader.available ? PreviewState.unreadable : PreviewState.unavailable);
      });
    });
  }

  /// The LaTeX for what's selected: the reading of selected ink, or the
  /// math item selected.
  Future<String?> _selectedLatex() async {
    final items = _selected;
    if (items.length == 1 && items.single is MathItem) return (items.single as MathItem).latex;
    if (items.length == 1 && items.single is GraphItem) {
      final g = items.single as GraphItem;
      return g.functions.isEmpty ? null : g.functions.first.expr;
    }
    final ink = _selectedInk();
    if (ink.isEmpty) return null;
    return (await _reader.read(ink))?.latex;
  }

  void _cantRead() {
    _toast(
      _reader.available ? 'Couldn’t read that as math. Try writing it again' : 'Math can’t be read on this device',
      undo: false,
    );
  }

  /// "Convert to math": the ink goes, typeset math goes where it was. One
  /// undo step.
  Future<void> _convertToMath() async {
    final pageId = _page.id;
    final ink = _selectedInk();
    if (ink.isEmpty) return;
    final reading = await _reader.read(ink);
    if (!mounted || _page.id != pageId) return;
    if (reading == null) return _cantRead();
    final strokes = [for (final s in ink) [for (final p in s.pageInk) Offset(p.x, p.y)]];
    final size = (writingSize(strokes) * 1.1).clamp(16.0, 120.0);
    final typeset = await _pictures.load(reading.latex);
    if (!mounted || _page.id != pageId) return;
    final box = MathItem.boxFor(typeset?.size ?? Size(reading.latex.length * 18.0, 56), mathReferenceSize, size);
    final area = ink.map((s) => s.bounds).reduce((a, b) => a.expandToInclude(b));
    final now = DateTime.now().toUtc();
    final item = MathItem(
      id: newId('it', now: now),
      x: area.left - MathItem.padding(size).left,
      y: area.center.dy - box.height / 2,
      z: _page.nextZ,
      createdAt: now,
      latex: reading.latex,
      w: box.width,
      h: box.height,
      size: size,
      color: ink.first.color,
    );
    _notebook.edit(pageId, remove: [for (final s in ink) s.id], insert: [item]);
    _mathInk.removeAll(ink.map((s) => s.id));
    _selection.clear();
    _rebuild(() {});
    _toast('Converted to math — tap to edit');
  }

  Future<void> _copyLatex() async {
    final latex = await _selectedLatex();
    if (!mounted) return;
    if (latex == null) return _cantRead();
    await Clipboard.setData(ClipboardData(text: latex));
    _toast('Copied the LaTeX', undo: false);
  }

  /// "Graph it": the function goes on the graph showing beside it (Graph.png:
  /// "from your handwriting"), or on a new graph to the right of the ink.
  /// One undo step; the ink stays.
  Future<void> _graphIt() async {
    final pageId = _page.id;
    final ink = _selectedInk();
    final latex = await _selectedLatex();
    if (!mounted || _page.id != pageId) return;
    if (latex == null) return _cantRead();
    final area = _outline()?.getBounds() ?? _vp.toPage(_vp.size.center(Offset.zero)) & Size.zero;
    if (!_addGraph(latex, Offset(area.right + 40, area.top), ink: ink, near: area)) return;
    _selection.clear();
    _rebuild(() {});
  }

  /// Graphs [latex]: on the 2D graph on screen nearest [near] (if there is
  /// one), otherwise on a new graph with its top-left at [at]. [ink] is the
  /// handwriting it was read from. False (with a message) when it isn't a
  /// function of x.
  bool _addGraph(String latex, Offset at, {List<StrokeItem> ink = const [], Rect? near}) {
    final f = graphFunction(latex);
    if (f == null) {
      _toast('Only a function of x can be graphed, like y = x²', undo: false);
      return false;
    }
    _pictures.load(latex);
    final copy = _inkCopy(ink);
    Color colorFor(Iterable<Color> used) {
      final written = ink.isEmpty ? null : ink.first.color;
      final taken = {for (final c in used) c.toARGB32()};
      // Written in a color (not black) that's free: the curve takes it.
      if (written != null && written.toARGB32() != inkDefaults.first.toARGB32() && !taken.contains(written.toARGB32())) {
        return written;
      }
      return nextGraphColor(used);
    }

    if (near != null) {
      final screen = Rect.fromPoints(_vp.toPage(Offset.zero), _vp.toPage(_vp.size.bottomRight(Offset.zero)));
      GraphItem? target;
      var best = double.infinity;
      for (final i in _page.items) {
        if (i is! GraphItem || i.is3d || !i.extent.overlaps(screen)) continue;
        final d = (i.extent.center - near.center).distance;
        if (d < best) {
          best = d;
          target = i;
        }
      }
      if (target != null) {
        final lines = target.functions;
        final added = GraphLine(latex, colorFor(lines.map((l) => l.color)), ink: copy);
        var g = target.copyWith(functions: [...lines, added]);
        if (lines.isEmpty) g = g.copyWith(view: _viewFor(f));
        _notebook.replaceItems(_page.id, [g]);
        _toast('Added ${latexToLinear(latex)} to the graph');
        return true;
      }
    }
    final now = DateTime.now().toUtc();
    const size = Size(GraphItem.designWidth, GraphItem.designHeight);
    final place = near == null ? (_freeSpot(size, aboveKeyboard: false) ?? at) : at;
    _notebook.insertItems(_page.id, [
      GraphItem(
        id: newId('it', now: now),
        x: place.dx,
        y: place.dy,
        z: _page.nextZ,
        createdAt: now,
        w: size.width,
        h: size.height,
        unit: 1,
        functions: [GraphLine(latex, colorFor(const []), ink: copy)],
        view: _viewFor(f),
      ),
    ]);
    _toast('Graphed it');
    return true;
  }

  static Rect _viewFor(GraphFunction f) {
    final v = graphView([f]);
    return Rect.fromLTRB(v.xMin, v.yMin, v.xMax, v.yMax);
  }

  /// A small copy of [ink] (each stroke at most 40 points, from the
  /// writing's top-left) for "from your handwriting".
  static List<List<Offset>> _inkCopy(List<StrokeItem> ink) {
    if (ink.isEmpty) return const [];
    final area = ink.map((s) => s.bounds).reduce((a, b) => a.expandToInclude(b));
    return [
      for (final s in ink)
        () {
          final pts = [for (final p in s.pageInk) Offset(p.x, p.y)];
          final step = math.max(1, (pts.length / 40).ceil());
          return [
            for (var i = 0; i < pts.length; i += step) pts[i] - area.topLeft,
            if ((pts.length - 1) % step != 0) pts.last - area.topLeft,
          ];
        }(),
    ];
  }

  // Graphs and math tools on the page: their buttons and plots.

  /// Whether a press at [page] on [top] lands on one of its buttons.
  bool _controlAt(BoxItem? top, Offset page) => switch (top) {
        final GraphItem g => switch (graphHitAt(g, g.toLocal(page))) {
            null || GraphHit(part: GraphPart.plot) => false,
            _ => true,
          },
        final MathToolItem t => mathToolHitAt(t, t.toLocal(page)) != null,
        _ => false,
      };

  /// Starts tracing (or turning) [top]'s plot, if [page] is on it.
  bool _startGraphDrag(BoxItem? top, Offset page) {
    if (top is! GraphItem || graphHitAt(top, top.toLocal(page))?.part != GraphPart.plot) return false;
    _selection.clear();
    _drag = _Drag.graph;
    _graphId = top.id;
    _graphLast = top.toLocal(page);
    _dragGraph(page);
    return true;
  }

  /// The pen moved on a graph's plot: the trace follows it (2D), or the
  /// view turns (3D). Not undo steps: it's where you're looking.
  void _dragGraph(Offset page) {
    final g = _graphId == null ? null : _page[_graphId!];
    if (g is! GraphItem) return;
    final local = g.toLocal(page);
    if (g.is3d) {
      if (local != _graphLast) _notebook.setQuietly(_page.id, graphDragged(g, local - _graphLast));
    } else if (graphTracedAt(g, local) case final traced? when traced.trace != g.trace) {
      _notebook.setQuietly(_page.id, traced);
    }
    _graphLast = local;
  }

  /// The selected graph, if [page] is on its plot.
  GraphItem? _onSelectedPlot(Offset page) {
    if (_selection.ids.length != 1) return null;
    final g = _page[_selection.ids.single];
    if (g is! GraphItem || graphHitAt(g, g.toLocal(page))?.part != GraphPart.plot) return null;
    return g;
  }

  /// Fingers on a selected graph's plot: they drag its window (or turn it)
  /// and pinch to zoom it.
  void _touchGraph(Offset before, Offset after, double factor) {
    final g = _graphId == null ? null : _page[_graphId!];
    if (g is! GraphItem) return;
    final from = g.toLocal(_vp.toPage(before)), to = g.toLocal(_vp.toPage(after));
    var next = graphDragged(g, to - from);
    if (factor != 1) next = graphZoomed(next, factor, local: to);
    _notebook.setQuietly(_page.id, next);
  }

  /// A tap on a graph's or math tool's button (or a graph's plot).
  bool _pressMathControl(Offset at) {
    switch (topBoxAt(_page.items, at)) {
      case final GraphItem g:
        final hit = graphHitAt(g, g.toLocal(at));
        if (hit == null) return false;
        _pressGraph(g, hit, g.toLocal(at));
        return true;
      case final MathToolItem t:
        final hit = mathToolHitAt(t, t.toLocal(at));
        if (hit == null) return false;
        _pressTool(t, hit);
        return true;
      default:
        return false;
    }
  }

  void _quietly(Item item) => _notebook.setQuietly(_page.id, item);

  void _pressGraph(GraphItem g, GraphHit hit, Offset local) {
    final lines = g.is3d ? g.surfaces : g.functions;
    switch (hit.part) {
      case GraphPart.mode2d:
        _quietly(g.copyWith(mode: GraphMode.d2));
      case GraphPart.mode3d:
        _quietly(g.copyWith(mode: GraphMode.d3));
      case GraphPart.zoomOut || GraphPart.zoomIn:
        _quietly(graphZoomed(g, hit.part == GraphPart.zoomIn ? 1.5 : 1 / 1.5));
      case GraphPart.turnLeft || GraphPart.turnRight:
        _quietly(graphTurned(g, hit.part == GraphPart.turnRight ? 20 : -20));
      case GraphPart.wireframe || GraphPart.surface:
        _quietly(g.copyWith(view3d: g.view3d.copyWith(surface: hit.part == GraphPart.surface)));
      case GraphPart.toggle:
        final line = lines[hit.index];
        final next = [...lines]..[hit.index] = line.copyWith(hidden: !line.hidden);
        _quietly(g.is3d ? g.copyWith(surfaces: next) : g.copyWith(functions: next));
      case GraphPart.edit:
        _openKeyboard(MathDraft(
          itemId: g.id,
          at: g.toPage(Offset.zero),
          purpose: DraftFor.graphLine,
          index: hit.index,
          text: latexToLinear(lines[hit.index].expr),
        ));
      case GraphPart.add:
        _openKeyboard(MathDraft(
          itemId: g.id,
          at: g.toPage(Offset.zero),
          purpose: DraftFor.graphLine,
          hint: g.is3d ? 'z = (x² − y²) / 4, or a point (1, 2, 3)' : 'y = x² / 2',
          write: _tapPen,
        ));
      case GraphPart.plot:
        if (graphTracedAt(g, local) case final traced?) _quietly(traced);
    }
  }

  void _pressTool(MathToolItem t, MathToolHit hit) {
    switch ((t.data, hit.part)) {
      case (UnitCircleData _, MathToolPart.previous || MathToolPart.next):
        _quietly(unitCircleStepped(t, hit.part == MathToolPart.next ? 1 : -1));
      case (final NumberLineData d, MathToolPart.chip):
        final s = d.spans[hit.index];
        _quietly(t.copyWith(data: d.copyWith(spans: [...d.spans]..[hit.index] = s.copyWith(hidden: !s.hidden))));
      case (final NumberLineData d, MathToolPart.spanFrom || MathToolPart.spanTo):
        // An end opens or closes: a change to the page.
        final s = d.spans[hit.index];
        final turned = hit.part == MathToolPart.spanFrom ? s.copyWith(openFrom: !s.openFrom) : s.copyWith(openTo: !s.openTo);
        _dismissToast();
        _notebook.replaceItems(_page.id, [fitMathTool(t.copyWith(data: d.copyWith(spans: [...d.spans]..[hit.index] = turned)))]);
      case (NumberLineData _, MathToolPart.add):
        _openKeyboard(MathDraft(
          itemId: t.id,
          at: t.toPage(Offset.zero),
          purpose: DraftFor.numberLine,
          hint: '√2, or an interval like [1, π)',
          write: _tapPen,
        ));
      case (final NumberLineData d, MathToolPart.item):
        _openKeyboard(MathDraft(
          itemId: t.id,
          at: t.toPage(Offset.zero),
          purpose: DraftFor.numberLine,
          index: hit.index,
          text: numberLabel(d.points[hit.index].value),
        ));
      case (final NumberLineData d, MathToolPart.span):
        _openKeyboard(MathDraft(
          itemId: t.id,
          at: t.toPage(Offset.zero),
          purpose: DraftFor.numberLine,
          index: hit.index,
          span: true,
          text: intervalLabel(d.spans[hit.index]),
        ));
      case (final PolarData d, MathToolPart.chip):
        final curve = d.curves[hit.index];
        _quietly(t.copyWith(data: PolarData(curves: [...d.curves]..[hit.index] = curve.copyWith(hidden: !curve.hidden), rest: d.rest)));
      case (PolarData _, MathToolPart.add):
        _openKeyboard(MathDraft(
          itemId: t.id,
          at: t.toPage(Offset.zero),
          purpose: DraftFor.polarCurve,
          hint: 'r = 1 + cos θ',
          write: _tapPen,
        ));
      case (final PolarData d, MathToolPart.item):
        _openKeyboard(MathDraft(
          itemId: t.id,
          at: t.toPage(Offset.zero),
          purpose: DraftFor.polarCurve,
          index: hit.index,
          text: latexToLinear(d.curves[hit.index].expr),
        ));
      default:
        break;
    }
  }

  void _openKeyboard(MathDraft draft) {
    _selection.clear();
    _math.type(draft);
  }

  // Adding to the page from Math tools.

  /// Where a box of [size] fits on screen without covering anything: the
  /// first free spot from the top-left, above the keyboard if
  /// [aboveKeyboard] (and it's open). Null when there's none.
  Offset? _freeSpot(Size size, {bool aboveKeyboard = true}) {
    final chrome = widget.chrome;
    final keyboard = aboveKeyboard ? (_keyboardKey.currentContext?.findRenderObject() as RenderBox?)?.size.height : null;
    final bottom = _vp.size.height - (keyboard != null ? keyboard + 20 : chrome.bottom);
    final area = Rect.fromPoints(
      _vp.toPage(Offset(chrome.left + 16, chrome.top + 16)),
      _vp.toPage(Offset(_vp.size.width - chrome.right - 16, bottom - 16)),
    );
    if (area.width < size.width || area.height < size.height) return null;
    final step = 24 / _vp.scale, gap = 16 / _vp.scale;
    for (var y = area.top; y + size.height <= area.bottom; y += step) {
      for (var x = area.left; x + size.width <= area.right; x += step) {
        final r = (Offset(x, y) & size).inflate(gap);
        final near = _page.index.query(r);
        if (near.every((id) => !(_page[id]?.bounds.overlaps(r) ?? false))) return Offset(x, y);
      }
    }
    return null;
  }

  /// Math tools' Number line, Unit circle and Polar grid: the tool goes on
  /// a free spot on screen (above the keyboard if there's room). One undo
  /// step.
  void _addTool(MathToolKind kind) {
    if (!_canInk) return;
    final now = DateTime.now().toUtc();
    final tool = newMathTool(kind.widget, Offset.zero, z: _page.nextZ, now: now);
    final size = Size(tool.w, tool.h);
    final at = _freeSpot(size) ??
        _freeSpot(size, aboveKeyboard: false) ??
        _vp.toPage(Offset(widget.chrome.left + 16, widget.chrome.top + 16));
    _dismissToast();
    _notebook.insertItems(_page.id, [tool.withBox(x: at.dx, y: at.dy, w: tool.w, h: tool.h)]);
    _toast('Added ${mathToolName(tool.data)} to the page');
  }

  /// A formula from the library, straight onto the page (MathKit.png's "Tap
  /// to add to the page"). One undo step.
  Future<void> _addFormula(Formula f) async {
    final pageId = _page.id;
    final latex = linearToLatex(f.text);
    final typeset = await _pictures.load(latex);
    if (!mounted || _page.id != pageId || !_canInk) return;
    const size = 32.0;
    final box = MathItem.boxFor(typeset?.size ?? Size(latex.length * 18.0, 56), mathReferenceSize, size);
    final at = _freeSpot(box) ?? _freeSpot(box, aboveKeyboard: false) ?? _typingSpot();
    final now = DateTime.now().toUtc();
    _dismissToast();
    _notebook.insertItems(pageId, [
      MathItem(
        id: newId('it', now: now),
        x: at.dx,
        y: at.dy,
        z: _page.nextZ,
        createdAt: now,
        latex: latex,
        w: box.width,
        h: box.height,
        size: size,
        color: ref.read(settingsProvider).penColor,
      ),
    ]);
    _toast('Added ${formulaLabel(f.text)} to the page');
  }

  Offset _typingSpot() => _vp.toPage(Offset(_vp.size.width * 0.25, _vp.size.height * 0.3));

  // Insert, for graphs and math tools.

  /// What the keyboard typed, for a graph: a function added or changed (a
  /// surface or point, in 3D); an empty line takes it off.
  void _insertGraphLine(MathDraft draft) {
    final g = _page[draft.itemId ?? ''];
    if (g is! GraphItem) return _math.closeKeyboard();
    final text = draft.text.text.trim();
    final latex = linearToLatex(text);
    final lines = g.is3d ? g.surfaces : g.functions;
    GraphItem withLines(List<GraphLine> next) => g.is3d ? g.copyWith(surfaces: next) : g.copyWith(functions: next);
    if (latex.trim().isEmpty || const {'y =', 'z =', 'y=', 'z='}.contains(text)) {
      _math.closeKeyboard();
      if (draft.index case final i? when i < lines.length) {
        _notebook.replaceItems(_page.id, [withLines([...lines]..removeAt(i)).copyWith(trace: () => null)]);
        _toast('Took it off the graph');
      }
      return;
    }
    final f = g.is3d ? null : graphFunction(latex);
    if (g.is3d ? !graphable3d(latex) : f == null) {
      _toast(
        g.is3d ? 'Type a surface like z = x² − y², or a point like (1, 2, 3)' : 'Only a function of x can be graphed, like y = x²',
        undo: false,
      );
      return;
    }
    _pictures.load(latex);
    final index = draft.index;
    final changing = index != null && index < lines.length;
    var next = changing
        ? withLines([...lines]..[index] = lines[index].copyWith(expr: latex))
        : withLines([...lines, GraphLine(latex, nextGraphColor(lines.map((l) => l.color)))]);
    if (f != null && g.functions.isEmpty) next = next.copyWith(view: _viewFor(f));
    _math.closeKeyboard();
    if (changing && lines[index].expr == latex) return;
    _notebook.replaceItems(_page.id, [next]);
    _toast(changing ? 'Changed the graph' : 'Added $text to the graph');
  }

  /// A point or interval on a number line, added or changed; an empty line
  /// takes it off.
  void _insertNumber(MathDraft draft) {
    final t = _page[draft.itemId ?? ''];
    if (t is! MathToolItem || t.data is! NumberLineData) return _math.closeKeyboard();
    final d = t.data as NumberLineData;
    final text = draft.text.text.trim();
    final index = draft.index;
    // What's being changed comes off; what's typed takes its place.
    final points = [...d.points], spans = [...d.spans];
    Color? color;
    if (index != null) {
      if (draft.span && index < spans.length) {
        color = spans.removeAt(index).color;
      } else if (!draft.span && index < points.length) {
        color = points.removeAt(index).color;
      }
    }
    if (text.isEmpty) {
      _math.closeKeyboard();
      if (index != null) {
        _notebook.replaceItems(_page.id, [fitMathTool(t.copyWith(data: d.copyWith(points: points, spans: spans)))]);
        _toast('Took it off the number line');
      }
      return;
    }
    final read = readNumberLine(text, linearToLatex, color ?? nextNumberColor(d));
    if (read == null) {
      _toast('Type a number like √2, or an interval like [1, π)', undo: false);
      return;
    }
    if (read.point case final p?) {
      points.insert(index != null && !draft.span ? math.min(index, points.length) : points.length, NumberPoint(p, color ?? nextNumberColor(d)));
    }
    if (read.span case final s?) {
      spans.insert(index != null && draft.span ? math.min(index, spans.length) : spans.length, s);
    }
    _math.closeKeyboard();
    _notebook.replaceItems(_page.id, [fitMathTool(t.copyWith(data: d.copyWith(points: points, spans: spans)))]);
    final what = read.span != null ? intervalLabel(read.span!) : numberLabel(read.point!);
    _toast(index == null ? 'Added $what to the number line' : 'Changed the number line');
  }

  /// A curve on a polar grid, added or changed; an empty line takes it off.
  void _insertCurve(MathDraft draft) {
    final t = _page[draft.itemId ?? ''];
    if (t is! MathToolItem || t.data is! PolarData) return _math.closeKeyboard();
    final d = t.data as PolarData;
    final text = draft.text.text.trim();
    final latex = linearToLatex(text);
    final index = draft.index;
    final changing = index != null && index < d.curves.length;
    final curves = [...d.curves];
    PolarData data(List<GraphLine> c) => PolarData(curves: c, rest: d.rest);
    if (latex.trim().isEmpty || text == 'r =') {
      _math.closeKeyboard();
      if (changing) {
        _notebook.replaceItems(_page.id, [fitMathTool(t.copyWith(data: data(curves..removeAt(index))))]);
        _toast('Took it off the polar grid');
      }
      return;
    }
    if (polarCurve(latex) == null) {
      _toast('Type a polar curve like r = 1 + cos θ', undo: false);
      return;
    }
    if (changing) {
      curves[index] = curves[index].copyWith(expr: latex, hidden: false);
    } else {
      curves.add(GraphLine(latex, nextGraphColor(curves.map((c) => c.color))));
    }
    _math.closeKeyboard();
    _notebook.replaceItems(_page.id, [fitMathTool(t.copyWith(data: data(curves)))]);
    _toast(changing ? 'Changed the polar grid' : 'Added $text to the polar grid');
  }

  // The math keyboard.

  /// Opens the keyboard on [m].
  void _editMath(MathItem m) {
    _selection.clear();
    _math.type(MathDraft(itemId: m.id, at: Offset(m.x, m.center.dy), text: latexToLinear(m.latex)));
  }

  /// Opens the keyboard for new math at [at] (its left middle).
  void _typeMathAt(Offset at) {
    _selection.clear();
    _math.type(MathDraft(at: at));
  }

  /// Keeps [_draftItem] (the math being typed, as it would look on the
  /// page) up to date with the keyboard.
  void _watchDraft() {
    final draft = _math.draft;
    if (draft == _draftFor) return;
    _draftFor?.text.removeListener(_draftChanged);
    _draftFor = draft;
    _draftItem = null;
    draft?.text.addListener(_draftChanged);
    if (draft != null) _draftChanged();
  }

  void _draftChanged() {
    final draft = _draftFor;
    if (draft == null || !mounted) return;
    final latex = linearToLatex(draft.text.text);
    final run = ++_draftRun;
    if (draft.purpose != DraftFor.math || latex.trim().isEmpty || !isDrawable(latex)) {
      // Nothing that can be drawn yet: the item keeps its last look.
      if (latex.trim().isEmpty && _draftItem != null) _rebuild(() => _draftItem = null);
      return;
    }
    _pictures.load(latex).then((typeset) {
      if (!mounted || run != _draftRun || _draftFor != draft || typeset == null) return;
      _rebuild(() => _draftItem = _mathFor(draft, latex, typeset.size));
    });
  }

  /// The item [draft] makes, with [latex] typeset at [natural].
  MathItem _mathFor(MathDraft draft, String latex, Size natural) {
    final was = draft.itemId == null ? null : _page[draft.itemId!];
    if (was is MathItem) {
      final box = MathItem.boxFor(natural, mathReferenceSize, was.size);
      // It grows from its left edge, staying on its line.
      return was.copyWith(latex: latex, w: box.width, h: box.height, y: was.center.dy - box.height / 2);
    }
    const size = 32.0;
    final box = MathItem.boxFor(natural, mathReferenceSize, size);
    final now = DateTime.now().toUtc();
    return MathItem(
      id: newId('it', now: now),
      x: draft.at.dx,
      y: draft.at.dy - box.height / 2,
      z: _page.nextZ,
      createdAt: now,
      latex: latex,
      w: box.width,
      h: box.height,
      size: size,
      color: ref.read(settingsProvider).penColor,
    );
  }

  /// Insert: the math goes on the page (or replaces what was there), as one
  /// undo step; a graph, for "Add a graph".
  Future<void> _insertDraft() async {
    final draft = _math.draft;
    if (draft == null) return;
    switch (draft.purpose) {
      case DraftFor.graphLine:
        return _insertGraphLine(draft);
      case DraftFor.numberLine:
        return _insertNumber(draft);
      case DraftFor.polarCurve:
        return _insertCurve(draft);
      case DraftFor.math || DraftFor.newGraph:
        break;
    }
    final pageId = _page.id;
    final latex = linearToLatex(draft.text.text);
    final was = draft.itemId == null ? null : _page[draft.itemId!];
    if (latex.trim().isEmpty) {
      _math.closeKeyboard();
      if (was != null) {
        _notebook.removeItems(pageId, [was.id]);
        _toast('Deleted the math');
      }
      return;
    }
    if (!isDrawable(latex)) {
      _toast('That can’t be typeset yet. Check its brackets', undo: false);
      return;
    }
    if (draft.graph) {
      if (_addGraph(latex, draft.at)) _math.closeKeyboard();
      return;
    }
    final typeset = await _pictures.load(latex);
    if (!mounted || _page.id != pageId || _math.draft != draft) return;
    final item = _mathFor(draft, latex, typeset?.size ?? Size(latex.length * 18.0, 56));
    _math.closeKeyboard();
    if (was is MathItem) {
      if (was.latex != latex) {
        _notebook.replaceItems(pageId, [item]);
        _toast('Changed the math');
      }
    } else {
      _notebook.insertItems(pageId, [item]);
      _toast('Added the math to the page');
    }
  }

  // On screen.

  Widget _mathPreview() => ListenableBuilder(
        listenable: Listenable.merge([_selection, _vp]),
        builder: (context, _) {
          final state = _preview;
          final box = _screenBox();
          if (state == null || box == null || _selection.menu != SelectionMenu.math || _selection.live != null) {
            return const SizedBox.shrink();
          }
          return CustomSingleChildLayout(
            // Under the toolbar when it can't go to the right.
            delegate: _PreviewLayout(box, widget.chrome, box.bottom + 54),
            child: IgnorePointer(child: MathPreview(state: state, latex: _previewLatex)),
          );
        },
      );

  Widget _mathKeyboard(MathDraft draft) => LayoutBuilder(builder: (context, box) {
        final room = box.maxWidth - widget.chrome.left - widget.chrome.right + 60;
        return Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: KeyedSubtree(
              key: _keyboardKey,
              child: MathKeyboard(
                key: ObjectKey(draft),
                math: _math,
                draft: draft,
                width: math.min(1060.0, math.max(320.0, room)),
                onInsert: _insertDraft,
                onFormula: _addFormula,
              ),
            ),
          ),
        );
      });
}

/// The preview sits right of the selection, a little lower than its top
/// (Math.dc.html), or under it (below the toolbar's handles) when there's
/// no room on the right.
class _PreviewLayout extends SingleChildLayoutDelegate {
  _PreviewLayout(this.box, this.chrome, this.below);

  final Rect box;
  final EdgeInsets chrome;
  final double below;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size child) {
    final right = box.right + 46;
    final maxTop = math.max(chrome.top, size.height - child.height - chrome.bottom);
    if (right + child.width <= size.width - chrome.right) {
      return Offset(right, (box.top + 8).clamp(chrome.top, maxTop).toDouble());
    }
    final left = box.left.clamp(chrome.left, math.max(chrome.left, size.width - child.width - chrome.right)).toDouble();
    return Offset(left, (below + 12).clamp(chrome.top, maxTop).toDouble());
  }

  @override
  bool shouldRelayout(_PreviewLayout old) => old.box != box || old.chrome != chrome || old.below != below;
}

/// The math being typed, where it will go, outlined in the accent color
/// (Math.png's "typing it now").
class _MathDraftPainter extends CustomPainter {
  _MathDraftPainter(this.view, this.item, this.brightness, this.colors, this.math) : super(repaint: view);

  final CanvasView view;
  final MathItem item;
  final Brightness brightness;
  final EndlessColors colors;
  final MathSource math;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..translate(view.translation.dx, view.translation.dy)
      ..scale(view.scale);
    paintItem(canvas, item, brightness, colors, math: math);
    final k = item.size / 32;
    canvas
      ..translate(item.center.dx, item.center.dy)
      ..rotate(item.angle)
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: item.w, height: item.h),
          Radius.circular(12 * k),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 / view.scale
          ..color = colors.accent,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_MathDraftPainter old) => old.item != item || old.colors != colors || old.brightness != brightness;
}
