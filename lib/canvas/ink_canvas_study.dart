part of 'ink_canvas.dart';

// Need to remember and flashcards on the canvas (RememberMark.png,
// FlashMake.png): Remember this for a selection, a star drawn next to
// something, the yellow wash and chips on what's remembered, and circling
// the front and back of a flashcard.

extension _CanvasStudy on InkCanvasState {
  void _cardsChanged() {
    if (mounted) _rebuild();
  }

  /// The topmost stroke or object under [at] (a tap with the lasso).
  Item? _topAt(Offset at) {
    final page = _page;
    final r = 10 * _unit;
    final ids = page.index.query(Rect.fromCircle(center: at, radius: r));
    for (final item in page.items.reversed) {
      if (!ids.contains(item.id)) continue;
      switch (item) {
        case StrokeItem s when strokeHit(s, at, at, r):
          return s;
        case BoxItem b when boxHit(b, at, slop: 4 * _unit):
          return b;
        default:
          continue;
      }
    }
    return null;
  }

  /// Making flashcards: what was circled (or tapped) is the front, then
  /// the back.
  void _circleForCard(List<Offset> loop) {
    if (loop.isEmpty) return;
    if (loop.length < 3 || pathLength(loop) < 20 * _unit) {
      final top = _topAt(loop.first);
      if (top != null) pane.cards.circled(CircledSide([top.id]));
      return;
    }
    final picked = itemsInPolygon(loop, _selectable(InkCanvasState._boundsOf(loop)));
    if (picked.isEmpty) return;
    pane.cards.circled(CircledSide([for (final i in picked) i.id], Path()..addPolygon(loop, true)));
  }

  /// The Remember toolbar's Flashcard: making flashcards, with what's
  /// selected as the front.
  void _flashcardFromSelection() {
    final ids = [for (final i in _selected) i.id];
    final loop = _selection.outlineAt(_nb.revision);
    widget.onFlashcards?.call(CircledSide(ids, loop));
  }

  // Remember this.

  /// Opens Remember this for what's selected, or (from its chip) for the
  /// thing remembered as [group].
  void _openRemember({String? group}) {
    final List<String> ids;
    if (group != null) {
      final g = rememberGroups(_page.items).where((g) => g.mark.id == group).firstOrNull;
      if (g == null) return;
      ids = [for (final i in g.items) i.id, if (g.star != null) g.star!.id];
    } else {
      ids = [for (final i in _selected) i.id];
      if (ids.isEmpty) return;
      // Already remembered together: change it rather than start again.
      final marks = {for (final id in ids) RememberMark.of(_page[id]!)?.id};
      if (marks.length == 1 && marks.first != null) group = marks.first;
    }
    _colorsOpen = false;
    _rebuild(() {
      _rememberIds = ids;
      _rememberGroup = group;
      _convertIds = null;
    });
    pane.panel.value = true;
  }

  void _closeRemember() {
    _rebuild(() {
      _rememberIds = null;
      _rememberGroup = null;
    });
    pane.panel.value = false;
  }

  RememberGroup? get _editedGroup {
    final id = _rememberGroup;
    if (id == null) return null;
    return rememberGroups(_page.items).where((g) => g.mark.id == id).firstOrNull;
  }

  /// What Remember this is about, without a drawn star.
  List<Item> get _rememberItems => [
        for (final id in _rememberIds ?? const <String>[])
          if (_page[id] case final Item i when !(RememberMark.of(i)?.star ?? false)) i,
      ];

  void _saveRemember(RememberChoice choice) {
    final page = _page;
    final ids = [for (final id in _rememberIds ?? const <String>[]) if (page[id] != null) id];
    if (ids.isEmpty) return _closeRemember();
    final old = _editedGroup?.mark;
    final now = ref.read(clockProvider)().toUtc();
    final content = _rememberItems;
    // "Also make it a flashcard": the front is what's remembered, the back
    // why it matters.
    FlashcardItem? card;
    var cardId = old?.flashcard;
    if (cardId != null && page[cardId] is! FlashcardItem) cardId = null;
    if (choice.flashcard && cardId == null && content.isNotEmpty) {
      final title = ref.read(libraryProvider).byId(pane.notebookId)?.title ?? '';
      final deck = ref.read(decksProvider.notifier).current(title);
      final at = itemsBounds(content)?.topLeft ?? Offset.zero;
      card = FlashcardItem(
        id: newId('fc', now: now),
        x: at.dx,
        y: at.dy,
        z: page.nextZ,
        createdAt: now,
        deck: deck.id,
        deckName: deck.name,
        front: CardSide(ids: [for (final i in content) i.id]),
        back: CardSide(text: choice.why),
      );
      cardId = card.id;
    }
    final mark = RememberMark(
      id: old?.id ?? newId('rm', now: now),
      why: choice.why,
      remind: choice.remind,
      remindAt: choice.remindAt,
      flashcard: cardId,
      drawn: old?.drawn ?? false,
      at: old?.at ?? now,
    );
    _notebook.edit(page.id, replace: [
      for (final id in ids)
        withRemember(page[id]!, (RememberMark.of(page[id]!)?.star ?? false ? mark.copyWith(star: true) : mark).toJson()),
    ], insert: [?card]);
    _selection.clear();
    _closeRemember();
    final at = choice.remindAt;
    final cardNote = card == null ? '' : ' · flashcard made';
    _toast(
      'Saved to Need to remember${at == null ? '' : ' · reminder ${reminderShort(at, now)}'}$cardNote',
      action: ('Open', () => context.push(Routes.remember)),
    );
    if (at != null) ref.read(reminderServiceProvider).askPermission();
  }

  /// "Forget it": no longer remembered (a flashcard made from it stays).
  void _forgetRemember() {
    final page = _page;
    final ids = [for (final id in _rememberIds ?? const <String>[]) if (page[id] != null) id];
    _notebook.replaceItems(page.id, [for (final id in ids) withRemember(page[id]!, null)]);
    _closeRemember();
    _toast('No longer remembered');
  }

  /// A star drawn next to something marks it to remember: the star goes on
  /// the page as drawn (one undo step), then it and what it's next to are
  /// marked (another). False when [raw] isn't a star next to something.
  bool _rememberStar(StrokeItem raw, AppSettings settings) {
    if (!settings.starRemember || pane.math.on || pane.cards.on || _targetNote != null) return false;
    if (raw.tool != InkTool.pen || _rulerEdge != null || !looksLikeStar(active.points, unit: _unit)) return false;
    final page = _page;
    final beside = besideStar(raw, page.items, unit: _unit);
    if (beside.isEmpty) return false;
    _putStroke(raw);
    final now = DateTime.now().toUtc();
    final mark = RememberMark(id: newId('rm', now: now), drawn: true, at: now);
    _notebook.replaceItems(page.id, [
      for (final i in beside) withRemember(i, mark.toJson()),
      if (page[raw.id] case final Item star) withRemember(star, mark.copyWith(star: true).toJson()),
    ]);
    _toast('Drawn star · remembered', action: ('Open', () => context.push(Routes.remember)));
    return true;
  }

  // Flashcards on the page.

  /// Deletes card [card] (one undo step).
  void _deleteCard(FlashcardItem card) {
    _notebook.removeItems(_page.id, [card.id]);
    _toast('Deleted the card');
  }

  /// The loop around a side being circled, or a box around its items.
  Path? _sidePath(CircledSide? side) {
    if (side == null) return null;
    if (side.loop case final loop?) return loop;
    final r = itemsBounds([for (final id in side.ids) ?_page[id]]);
    if (r == null) return null;
    return Path()..addRRect(RRect.fromRectAndRadius(r.inflate(12), const Radius.circular(18)));
  }

  // What's drawn for them.

  /// The wash under what's remembered (under the ink).
  Widget _rememberWash(PageRuntime page, EndlessColors colors) {
    final groups = rememberGroups(page.items);
    if (groups.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(child: CustomPaint(painter: RememberWashPainter(_vp, groups, colors)));
  }

  /// Chips on what's remembered, and, while making flashcards, the sides
  /// being circled and the cards already made.
  Widget _studyMarks(PageRuntime page) => ListenableBuilder(
        listenable: Listenable.merge([_vp, pane.cards]),
        builder: (context, _) {
          final c = context.colors;
          final cards = pane.cards;
          final children = <Widget>[];
          Offset screen(Offset p) => _vp.toScreen(p);

          if (!cards.on) {
            for (final g in rememberGroups(page.items)) {
              final star = g.star;
              final tap = _canInk ? () => _openRemember(group: g.mark.id) : null;
              if (g.mark.drawn && star != null) {
                children.add(OnPage(
                  at: screen(star.extent.centerRight) + const Offset(10, 0),
                  anchor: Alignment.centerLeft,
                  child: MarkChip(
                    text: 'Drawn star · remembered',
                    background: c.stickyYellow,
                    foreground: c.goldDeep,
                    onTap: tap,
                    semantics: 'Remembered with a drawn star. Change or forget it',
                  ),
                ));
              } else {
                final r = g.content.inflate(washPad);
                children.add(OnPage(
                  at: Offset(screen(r.topRight).dx - 4, screen(r.topLeft).dy),
                  anchor: Alignment.centerRight,
                  child: MarkChip(
                    text: 'Remembered',
                    icon: EIcons.star,
                    background: c.stickyYellow,
                    foreground: c.goldDeep,
                    onTap: tap,
                    semantics: 'Remembered. Change or forget it',
                  ),
                ));
              }
            }
          } else {
            // The cards made on this page, numbered in order.
            final made = page.items.whereType<FlashcardItem>().toList();
            for (final (i, card) in made.indexed) {
              final front = itemsBounds([for (final id in card.front.ids) ?page[id]]);
              final back = itemsBounds([for (final id in card.back.ids) ?page[id]]);
              final apart = front != null && back != null && front.inflate(60).overlaps(back) == false;
              void add(Rect r, String text) => children.add(OnPage(
                    at: screen(r.topRight) + const Offset(16, 0),
                    child: MarkChip(
                      text: text,
                      icon: EIcons.flashcardsBold,
                      background: c.plumTint,
                      foreground: c.plumDeep,
                      onTap: _canInk ? () => _cardMenu(card, screen(r.topRight) + const Offset(16, 24)) : null,
                      semantics: '$text. Delete it',
                    ),
                  ));
              if (front != null) add(front, apart ? 'Card ${i + 1} · front' : 'Card ${i + 1}');
              if (back != null && apart) add(back, 'Card ${i + 1} · back');
            }
            for (final (side, label, bg) in [
              (cards.front, 'FRONT', c.accent),
              (cards.back, 'BACK', c.clayDeep),
            ]) {
              final path = _sidePath(side);
              if (path == null) continue;
              children.add(OnPage(
                at: screen(path.getBounds().topLeft),
                anchor: Alignment.bottomLeft,
                child: MarkChip(text: label, background: bg, foreground: c.onAccent, caps: true),
              ));
            }
          }
          if (children.isEmpty) return const SizedBox.shrink();
          return Stack(clipBehavior: Clip.none, children: children);
        },
      );

  /// The outlines of the sides being circled (FlashMake.png).
  Widget _cardOutlines(EndlessColors c) => ListenableBuilder(
        listenable: pane.cards,
        builder: (context, _) {
          final cards = pane.cards;
          if (!cards.on) return const SizedBox.shrink();
          final sides = [
            if (_sidePath(cards.front) case final p?) CardSideOutline(p, c.accent),
            if (_sidePath(cards.back) case final p?) CardSideOutline(p, c.clay),
          ];
          if (sides.isEmpty) return const SizedBox.shrink();
          return IgnorePointer(child: CustomPaint(painter: CardOutlinePainter(_vp, sides)));
        },
      );

  Future<void> _cardMenu(FlashcardItem card, Offset at) async {
    final picked = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx + 1, at.dy + 1),
      items: const [PopupMenuItem(value: 'delete', child: Text('Delete card'))],
    );
    if (picked == 'delete' && mounted && _page[card.id] != null) _deleteCard(card);
  }

  /// Remember this, beside what it's about: right of it if there's room
  /// (RememberMark.png), else left, else in the middle.
  Widget _rememberPanel() => ListenableBuilder(
        listenable: _vp,
        builder: (context, _) {
          final items = _rememberItems;
          final all = [for (final id in _rememberIds ?? const <String>[]) ?_page[id]];
          final area = itemsBounds(all);
          final box = area == null ? null : Rect.fromPoints(_vp.toScreen(area.topLeft), _vp.toScreen(area.bottomRight));
          final group = _editedGroup;
          final cardId = group?.mark.flashcard;
          return CustomSingleChildLayout(
            delegate: _RememberLayout(box, widget.chrome),
            child: RememberPanel(
              key: ValueKey(_rememberIds),
              items: items,
              images: _page.images,
              initial: group?.mark,
              hasCard: cardId != null && _page[cardId] is FlashcardItem,
              onSave: _saveRemember,
              onCancel: _closeRemember,
              onForget: group == null ? null : _forgetRemember,
            ),
          );
        },
      );
}

class _RememberLayout extends SingleChildLayoutDelegate {
  _RememberLayout(this.box, this.chrome);

  final Rect? box;
  final EdgeInsets chrome;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size child) {
    final top = chrome.top + 12;
    final b = box;
    if (b == null) return Offset((size.width - child.width) / 2, top);
    // Beside it, at the top (RememberMark.png), clear of the messages and
    // notes along the bottom. The pages rail and map make way meanwhile
    // (Pane.panel).
    final right = b.right + 40;
    if (right + child.width <= size.width - chrome.right) return Offset(right, top);
    final left = b.left - 40 - child.width;
    if (left >= chrome.left) return Offset(left, top);
    // Neither side: under it, or over it.
    final under = b.bottom + 70;
    final x = ((size.width - child.width) / 2).clamp(chrome.left, math.max(chrome.left, size.width - child.width - chrome.right)).toDouble();
    if (under + child.height <= size.height - 16) return Offset(x, under);
    return Offset(x, top);
  }

  @override
  bool shouldRelayout(_RememberLayout old) => old.box != box || old.chrome != chrome;
}
