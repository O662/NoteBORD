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

  /// "Graph it": a graph of the function beside it. One undo step; the ink
  /// stays.
  Future<void> _graphIt() async {
    final pageId = _page.id;
    final latex = await _selectedLatex();
    if (!mounted || _page.id != pageId) return;
    if (latex == null) return _cantRead();
    final area = _outline()?.getBounds() ?? _vp.toPage(_vp.size.center(Offset.zero)) & Size.zero;
    if (!_addGraph(latex, Offset(area.right + 40, area.top))) return;
    _selection.clear();
    _rebuild(() {});
  }

  /// A graph of [latex] with its top-left at [at]; false (with a message)
  /// when it isn't a function of x.
  bool _addGraph(String latex, Offset at) {
    final f = graphFunction(latex);
    if (f == null) {
      _toast('Only a function of x can be graphed, like y = x²', undo: false);
      return false;
    }
    final view = graphView([f]);
    final now = DateTime.now().toUtc();
    _pictures.load(latex);
    _notebook.insertItems(_page.id, [
      GraphItem(
        id: newId('it', now: now),
        x: at.dx,
        y: at.dy,
        z: _page.nextZ,
        createdAt: now,
        w: 560,
        h: 380,
        functions: [GraphLine(latex, inkDefaults[1])],
        view: Rect.fromLTRB(view.xMin, view.yMin, view.xMax, view.yMax),
      ),
    ]);
    _toast('Graphed it');
    return true;
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
    if (draft.graph || latex.trim().isEmpty || !isDrawable(latex)) {
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
            child: MathKeyboard(
              key: ObjectKey(draft),
              math: _math,
              draft: draft,
              width: math.min(1060.0, math.max(320.0, room)),
              onInsert: _insertDraft,
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
