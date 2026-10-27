import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../library/library.dart';
import '../../recognition/handwriting_index.dart';
import '../../study/fsrs.dart';
import '../../study/session.dart';
import '../../study/study_rows.dart';
import '../../study/study_state.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../common.dart';
import '../dialogs.dart';
import '../icons.dart';
import '../routes.dart';
import 'item_preview.dart';
import 'study_format.dart';

/// Flashcards (Study.png): the decks on the left; on the right the cards due
/// in the one picked, to flip (or answer in writing) and rate.
class StudyScreen extends ConsumerStatefulWidget {
  const StudyScreen({super.key, this.deck});

  /// The deck to open on.
  final String? deck;

  @override
  ConsumerState<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends ConsumerState<StudyScreen> {
  @override
  void initState() {
    super.initState();
    // Anything not read into the index yet (as Search does): a notebook
    // imported or changed elsewhere shows here too.
    final index = ref.read(handwritingIndexProvider);
    if (ref.read(catchUpOnStartProvider)) index.catchUp();
  }
  late String? _deck = widget.deck;

  /// All cards: every card of the deck at once, instead of studying.
  bool _browse = false;
  StudySession? _session;
  String? _sessionDeck;
  bool _flipped = false;
  bool _write = false;

  /// "Write the answer": what's written on the card's pad.
  final _answer = <List<Offset>>[];
  List<Offset>? _drawing;
  int? _pointer;

  DateTime get _now => ref.read(clockProvider)().toUtc();

  void _pick(String deck) => setState(() {
        _deck = deck;
        _session = null;
        _flipped = false;
        _answer.clear();
      });

  /// A round of the cards due in [deck] (all of them with [all]).
  void _startSession(DeckSummary deck, {bool all = false}) {
    final now = _now;
    final items = [
      for (final i in deck.items)
        if (all || i.dueAt(now)) i,
    ]..sort((a, b) {
        // Cards being reviewed by when they were due, then new ones in the order made.
        final da = a.state?.due, db = b.state?.due;
        if (da != null && db != null) return da.compareTo(db);
        if (da != null) return -1;
        if (db != null) return 1;
        return a.card.at.compareTo(b.card.at);
      });
    _session = StudySession(items);
    _sessionDeck = deck.deck.id;
    _flipped = false;
    _answer.clear();
  }

  void _flip() => setState(() => _flipped = !_flipped);

  void _rate(StudyItem item, Rating rating) {
    final session = _session;
    if (session == null) return;
    final state = session.answer(item, rating, _now);
    ref.read(studyProvider.notifier).record(item, state);
    setState(() {
      _flipped = false;
      _answer.clear();
    });
  }

  Future<void> _newDeck() async {
    final name = await showNamePrompt(context, title: 'New deck', action: 'Create');
    if (name == null || name.trim().isEmpty) return;
    final deck = ref.read(decksProvider.notifier).add(name);
    _pick(deck.id);
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.start);
    }
  }

  /// "Make cards from your notes": the notebook open last, to make cards in.
  void _makeCards() {
    final lib = ref.read(libraryProvider);
    final last = lib.recent(count: 1).firstOrNull;
    if (last == null) {
      showNote(context, 'Make a notebook first, then circle the front and back of a card in it');
      return;
    }
    openNotebook(context, ref, last.id);
    showNote(context, 'Study & math → Make flashcards, then circle the front and the back');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final snapshot = ref.watch(studyProvider);
    final list = snapshot == null ? const <DeckSummary>[] : deckSummaries(snapshot, ref.watch(decksProvider), _now);
    // The deck asked for, else the first with cards due, else the first.
    final picked = list.where((d) => d.deck.id == _deck).firstOrNull ??
        list.where((d) => d.due > 0).firstOrNull ??
        list.firstOrNull;
    if (picked != null && (_session == null || _sessionDeck != picked.deck.id)) {
      if (picked.due > 0) {
        _startSession(picked);
      } else {
        _session = null;
        _sessionDeck = null;
      }
    }

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _DeckList(
            decks: list,
            picked: picked?.deck.id,
            onPick: _pick,
            onNewDeck: _newDeck,
            onBack: _back,
            onMakeCards: _makeCards,
          ),
          Expanded(
            child: snapshot == null
                ? const SizedBox.shrink()
                : picked == null
                    ? _Empty(onMakeCards: _makeCards)
                    : _main(context, picked),
          ),
        ]),
      ),
    );
  }

  Widget _main(BuildContext context, DeckSummary deck) {
    final c = context.colors;
    final now = _now;
    final session = _sessionDeck == deck.deck.id ? _session : null;
    final item = session?.current(now);
    final finished = session != null && session.finished;
    final total = session?.total ?? 0;
    final done = session?.done ?? 0;
    final label = _browse
        ? cardsLabel(deck.cards)
        : session == null
            ? (deck.items.isEmpty ? 'No cards yet' : 'All caught up')
            : finished
                ? 'Done for today'
                : 'Card ${done + 1} of $total due';

    Widget body;
    if (_browse && deck.items.isNotEmpty) {
      body = _AllCards(deck: deck, now: now);
    } else if (deck.items.isEmpty) {
      body = _Note(
        title: 'No cards in this deck yet',
        text: 'In a notebook, pick Study & math → Make flashcards, then circle the front and the back.',
        action: ('Make cards from your notes', _makeCards),
      );
    } else if (session == null) {
      final next = _nextReview(deck, now);
      body = _Note(
        title: 'All caught up',
        text: next == null ? 'Nothing is due in this deck.' : 'Nothing is due in this deck. Next review: $next.',
        action: ('Study anyway', () => setState(() => _startSession(deck, all: true))),
      );
    } else if (finished || item == null) {
      final next = _nextReview(deck, now);
      body = Column(mainAxisSize: MainAxisSize.min, spacing: 10, children: [
        Text(
          'All ${total == 1 ? '1 due card' : '$total due cards'} done.${next == null ? '' : ' Next review: $next.'}',
          style: TextStyle(fontSize: 16, color: c.text),
        ),
        SecondaryButton(label: 'Study again', onPressed: () => setState(() => _startSession(deck, all: true))),
      ]);
    } else {
      body = Column(mainAxisSize: MainAxisSize.min, spacing: 20, children: [
        _card(context, item),
        if (_flipped) _ratings(context, session, item) else _actions(context, item),
      ]);
    }

    return CallbackShortcuts(
      bindings: {
        if (item != null && !finished && !_browse) ...{
          const SingleActivator(LogicalKeyboardKey.space): _flip,
          if (_flipped) ...{
            const SingleActivator(LogicalKeyboardKey.digit1): () => _rate(item, Rating.again),
            const SingleActivator(LogicalKeyboardKey.digit2): () => _rate(item, Rating.hard),
            const SingleActivator(LogicalKeyboardKey.digit3): () => _rate(item, Rating.good),
            const SingleActivator(LogicalKeyboardKey.digit4): () => _rate(item, Rating.easy),
          },
        },
      },
      child: Focus(
        autofocus: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 26),
          child: Column(crossAxisAlignment: CrossAxisAlignment.center, spacing: 20, children: [
            Row(spacing: 16, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, spacing: 12, children: [
                    Flexible(
                      child: Text(
                        deck.deck.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 26, color: c.text),
                      ),
                    ),
                    Text(label, style: TextStyle(fontSize: 14, color: c.textMuted)),
                  ]),
                  if (!_browse)
                    Semantics(
                    label: 'Progress',
                    value: '$done of $total',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: SizedBox(
                        height: 8,
                        child: LinearProgressIndicator(
                          value: total == 0 ? (session == null ? 0 : 1) : done / total,
                          backgroundColor: c.cardLine,
                          color: c.accent,
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
              if (!_browse)
                _ModePicker(write: _write, onPick: (w) => setState(() {
                      _write = w;
                      _flipped = false;
                      _answer.clear();
                    })),
              // Every card of the deck, or back to studying.
              if (deck.items.isNotEmpty)
                SecondaryButton(
                  label: _browse ? 'Study' : 'All cards',
                  icon: _browse ? EIcons.play : EIcons.flashcards,
                  height: 50,
                  onPressed: () => setState(() {
                    _browse = !_browse;
                    _flipped = false;
                    _answer.clear();
                  }),
                ),
            ]),
            Expanded(child: _browse ? body : Align(alignment: Alignment.topCenter, child: body)),
          ]),
        ),
      ),
    );
  }

  /// "tomorrow", "in 3 days", or null when nothing is waiting.
  String? _nextReview(DeckSummary deck, DateTime now) {
    final states = ref.read(studyProvider)?.states ?? const {};
    DateTime? soonest;
    for (final i in deck.items) {
      final due = states[i.key]?.due;
      if (due != null && due.isAfter(now) && (soonest == null || due.isBefore(soonest))) soonest = due;
    }
    if (soonest == null) return null;
    return _when(soonest, now);
  }

  Widget _card(BuildContext context, StudyItem item) {
    final c = context.colors;
    final back = _flipped;
    var side = back ? item.answer : item.question;
    String? note;
    if (back && side.isEmpty) {
      // A card from Need to remember with nothing on the back.
      side = item.question;
      note = 'Rate how well you remembered it';
    } else if (side.isEmpty && side.missing > 0) {
      note = 'This side was erased from your notes';
    }
    final pages = ref.watch(pageIdsProvider(item.card.notebookId)).value;
    final page = pages == null ? null : pages.indexOf(item.card.pageId) + 1;
    final notebook = ref.watch(libraryProvider).byId(item.card.notebookId)?.title ?? '';
    final from = 'From $notebook${page == null || page < 1 ? '' : ' · page $page'}';
    final writing = _write && !back;

    return Semantics(
      button: true,
      label: back
          ? 'Card back: ${side.label}. Tap to see the front'
          : 'Card front: ${side.label}. ${writing ? 'Write the answer below' : 'Tap to flip'}',
      // The answer pad stays reachable while writing.
      excludeSemantics: !writing,
      child: GestureDetector(
        onTap: _flip,
        child: Container(
          width: 660,
          height: 400,
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(color: c.shadow.withValues(alpha: c.shadow.a * 0.09), offset: const Offset(0, 2)),
              BoxShadow(color: c.shadow, offset: const Offset(0, 24), blurRadius: 40, spreadRadius: -24),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: CustomPaint(
              painter: _Dots(c.cardLine, 22),
              child: Stack(children: [
                Positioned(
                  left: 20,
                  top: 16,
                  child: Text(
                    back ? 'BACK' : 'FRONT',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.96, color: back ? c.clayDeep : c.accentDeep),
                  ),
                ),
                Positioned.fill(
                  left: 40,
                  right: 40,
                  top: 48,
                  bottom: 48,
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, spacing: 14, children: [
                    if (side.items.isNotEmpty)
                      Flexible(
                        child: ItemsPreview(
                          items: side.items,
                          notebookId: item.card.notebookId,
                          maxScale: 3,
                          label: side.said,
                        ),
                      ),
                    if (side.text.isNotEmpty)
                      Text(
                        side.text,
                        textAlign: TextAlign.center,
                        maxLines: side.items.isEmpty ? 6 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: FontFamilies.serif, fontSize: side.items.isEmpty ? 34 : 24, height: 1.25, color: c.text),
                      ),
                    if (note != null) Text(note, style: TextStyle(fontSize: 14, color: c.textMuted)),
                    if (writing) _writePad(context),
                    if (back && _write && _answer.isNotEmpty) _yourAnswer(context),
                  ]),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 16,
                  child: Text(
                    back ? from : (writing ? '' : 'Tap the card to flip'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: c.textMuted),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  /// "Write your answer here with the S Pen".
  Widget _writePad(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      label: 'Write your answer here with the S Pen',
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          if (_pointer != null) return;
          _pointer = e.pointer;
          setState(() => _drawing = [e.localPosition]);
        },
        onPointerMove: (e) {
          if (e.pointer != _pointer) return;
          setState(() => _drawing?.add(e.localPosition));
        },
        onPointerUp: (e) {
          if (e.pointer != _pointer) return;
          _pointer = null;
          setState(() {
            if (_drawing case final d? when d.isNotEmpty) _answer.add(d);
            _drawing = null;
          });
        },
        onPointerCancel: (e) {
          if (e.pointer != _pointer) return;
          _pointer = null;
          setState(() => _drawing = null);
        },
        // The pad takes the pen; the card doesn't flip under it.
        child: GestureDetector(
          onTap: () {},
          child: DashedBorder(
            color: c.lineDashed,
            radius: 14,
            width: 2,
            child: SizedBox(
              width: 520,
              height: 110,
              child: CustomPaint(
                painter: _Ink([..._answer, ?_drawing], c.text),
                child: _answer.isEmpty && _drawing == null
                    ? Center(child: Text('Write your answer here with the S Pen', style: TextStyle(fontSize: 15, color: c.textMuted)))
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// On the back, what was written, to compare.
  Widget _yourAnswer(BuildContext context) {
    final c = context.colors;
    return Container(
      width: 360,
      height: 76,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(color: c.surfaceSunk, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('YOUR ANSWER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.88, color: c.textMuted)),
        Expanded(child: CustomPaint(size: Size.infinite, painter: _Ink(_answer, c.text, fit: true))),
      ]),
    );
  }

  Widget _actions(BuildContext context, StudyItem item) {
    final c = context.colors;
    return SizedBox(
      width: 660,
      child: Row(spacing: 10, children: [
        Semantics(
          button: true,
          label: 'Open in notes',
          excludeSemantics: true,
          child: Material(
            color: Colors.transparent,
            shape: RoundedRectangleBorder(side: BorderSide(color: c.lineStrong), borderRadius: BorderRadius.circular(14)),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => openSpot(context, ref, item.card.notebookId, item.card.pageId, item.card.rect),
              child: Container(
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                alignment: Alignment.center,
                child: Text('Open in notes', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.text)),
              ),
            ),
          ),
        ),
        Expanded(
          child: Semantics(
            button: true,
            label: _write ? 'Check my answer' : 'Show answer',
            excludeSemantics: true,
            child: Material(
              color: c.inverse,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _flip,
                child: Container(
                  height: 64,
                  alignment: Alignment.center,
                  child: Text(
                    _write ? 'Check my answer' : 'Show answer',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.onInverse),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _ratings(BuildContext context, StudySession session, StudyItem item) {
    final c = context.colors;
    final now = _now;
    final looks = {
      Rating.again: ('Again', c.clayTint, c.clayDeep, c.clayLine),
      Rating.hard: ('Hard', c.surface, c.text, c.lineStrong),
      Rating.good: ('Good', c.accentTint, c.accentDeep, c.accentLine),
      Rating.easy: ('Easy', c.greenTint, c.greenDeep, c.greenLine),
    };
    return Semantics(
      container: true,
      label: 'How well did you know it?',
      explicitChildNodes: true,
      child: SizedBox(
        width: 660,
        child: Row(spacing: 10, children: [
          for (final e in looks.entries)
            Expanded(
              child: Builder(builder: (context) {
                final (label, bg, fg, border) = e.value;
                final wait = waitLabel(session.waitFor(item, e.key, now));
                return Semantics(
                  button: true,
                  label: '$label, next $wait',
                  excludeSemantics: true,
                  child: Material(
                    color: bg,
                    shape: RoundedRectangleBorder(side: BorderSide(color: border), borderRadius: BorderRadius.circular(14)),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _rate(item, e.key),
                      child: SizedBox(
                        height: 64,
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, spacing: 2, children: [
                          Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: fg)),
                          Text(wait, style: TextStyle(fontSize: 12, color: fg)),
                        ]),
                      ),
                    ),
                  ),
                );
              }),
            ),
        ]),
      ),
    );
  }
}

/// When [due] comes, from [now]: "later today", "tomorrow", "in 3 days",
/// or "Oct 30".
String _when(DateTime due, DateTime now) {
  final local = due.toLocal(), today = now.toLocal();
  final days = DateTime(local.year, local.month, local.day).difference(DateTime(today.year, today.month, today.day)).inDays;
  if (days <= 0) return 'later today';
  if (days == 1) return 'tomorrow';
  if (days < 7) return 'in $days days';
  return monthDay(due);
}

/// All cards: every card of a deck, its front and back as they are in the
/// notes, when it's next asked, and where it is.
class _AllCards extends StatelessWidget {
  const _AllCards({required this.deck, required this.now});

  final DeckSummary deck;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    // One tile per card (back to front is the same card), oldest first.
    final byCard = <String, List<StudyItem>>{};
    for (final i in deck.items) {
      (byCard['${i.card.notebookId}/${i.card.id}'] ??= []).add(i);
    }
    final cards = byCard.values.toList()..sort((a, b) => a.first.card.at.compareTo(b.first.card.at));
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 360,
        mainAxisExtent: 300,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
      ),
      itemCount: cards.length,
      itemBuilder: (context, i) => _CardTile(ways: cards[i], now: now),
    );
  }
}

class _CardTile extends ConsumerWidget {
  const _CardTile({required this.ways, required this.now});

  /// The card asked front to back, and back to front too when it is.
  final List<StudyItem> ways;
  final DateTime now;

  /// "New", "Due now", or "Next: tomorrow": the soonest way of asking it.
  String get _status {
    if (ways.any((w) => w.state == null)) return 'New';
    final due = ways.map((w) => w.state!.due).reduce((a, b) => a.isBefore(b) ? a : b);
    return due.isAfter(now) ? 'Next: ${_when(due, now)}' : 'Due now';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final card = ways.first.card;
    final status = _status;
    final due = status == 'Due now' || status == 'New';
    final pages = ref.watch(pageIdsProvider(card.notebookId)).value;
    final page = pages == null ? 0 : pages.indexOf(card.pageId) + 1;
    final source = '${ref.watch(libraryProvider).byId(card.notebookId)?.title ?? 'A notebook'}${page > 0 ? ' · p. $page' : ''}';

    Widget side(String label, SideView view, Color color) => Expanded(
          child: Container(
            decoration: BoxDecoration(color: c.surfaceSunk, borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.88, color: color)),
              Expanded(
                child: view.isEmpty
                    ? Center(
                        child: Text(
                          view.missing > 0 ? 'Erased from your notes' : 'Nothing on this side',
                          style: TextStyle(fontSize: 13, color: c.textMuted),
                        ),
                      )
                    : Column(spacing: 4, children: [
                        if (view.items.isNotEmpty)
                          Expanded(child: ItemsPreview(items: view.items, notebookId: card.notebookId, maxScale: 1.5, label: view.said)),
                        if (view.text.isNotEmpty)
                          Text(
                            view.text,
                            textAlign: TextAlign.center,
                            maxLines: view.items.isEmpty ? 3 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 17, height: 1.25, color: c.text),
                          ),
                      ]),
              ),
            ]),
          ),
        );

    Widget chip(String text, {bool strong = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: strong ? c.clayTint : c.side, borderRadius: BorderRadius.circular(999)),
          child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: strong ? c.clayDeep : c.inverseRaised)),
        );

    final front = card.front.label.isEmpty ? 'a picture or drawing' : card.front.label;
    final back = card.back.label.isEmpty ? 'a picture or drawing' : card.back.label;
    return Semantics(
      container: true,
      label: 'Card. Front: $front. Back: $back. $status${card.reverse ? '. Asked both ways' : ''}',
      explicitChildNodes: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          side('FRONT', card.front, c.accentDeep),
          side('BACK', card.back, c.clayDeep),
          Row(spacing: 6, children: [
            chip(status, strong: due),
            if (card.reverse) chip('Both ways'),
          ]),
          Semantics(
            link: true,
            label: 'Open $source',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => openSpot(context, ref, card.notebookId, card.pageId, card.rect),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(spacing: 6, children: [
                  EIcon(EIcons.notebook, size: 16, color: c.accent),
                  Expanded(
                    child: Text(source, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.accent)),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Flip · Write the answer.
class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.write, required this.onPick});

  final bool write;
  final ValueChanged<bool> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget option(String label, bool on, VoidCallback onTap) => Semantics(
          button: true,
          inMutuallyExclusiveGroup: true,
          checked: on,
          label: label,
          excludeSemantics: true,
          child: Material(
            color: on ? c.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            elevation: 0,
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: onTap,
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: on
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: [BoxShadow(color: c.shadow.withValues(alpha: c.shadow.a * 0.33), offset: const Offset(0, 1), blurRadius: 2)],
                        color: c.surface,
                      )
                    : null,
                child: Text(label, style: TextStyle(fontSize: 14, fontWeight: on ? FontWeight.w600 : FontWeight.w500, color: c.text)),
              ),
            ),
          ),
        );
    return Semantics(
      container: true,
      label: 'Study mode',
      explicitChildNodes: true,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: c.side, borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 2, children: [
          option('Flip', !write, () => onPick(false)),
          option('Write the answer', write, () => onPick(true)),
        ]),
      ),
    );
  }
}

/// The decks (Study.dc.html's nav).
class _DeckList extends StatelessWidget {
  const _DeckList({
    required this.decks,
    required this.picked,
    required this.onPick,
    required this.onNewDeck,
    required this.onBack,
    required this.onMakeCards,
  });

  final List<DeckSummary> decks;
  final String? picked;
  final ValueChanged<String> onPick;
  final VoidCallback onNewDeck;
  final VoidCallback onBack;
  final VoidCallback onMakeCards;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      label: 'Decks',
      explicitChildNodes: true,
      child: Container(
        width: 290,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: BoxDecoration(color: c.side, border: Border(right: BorderSide(color: c.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
          Row(spacing: 6, children: [
            ChromeButton(label: 'Back', icon: EIcons.back, iconSize: 22, onPressed: onBack),
            Text('Flashcards', style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 28, color: c.text)),
          ]),
          Flexible(
            child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
              for (final d in decks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _DeckButton(deck: d, selected: d.deck.id == picked, onTap: () => onPick(d.deck.id)),
                ),
            ]),
          ),
          Semantics(
            button: true,
            label: 'New deck',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onNewDeck,
              child: DashedBorder(
                color: c.lineDashed,
                radius: 14,
                child: SizedBox(
                  height: 46,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 8, children: [
                    EIcon(EIcons.plus, size: 16, color: c.text),
                    Text('New deck', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
                  ]),
                ),
              ),
            ),
          ),
          const Spacer(),
          Semantics(
            button: true,
            label: 'Make cards from your notes. Circle the front, then the back. Ink, images and text all work.',
            excludeSemantics: true,
            child: Material(
              color: c.surface,
              shape: RoundedRectangleBorder(side: BorderSide(color: c.line), borderRadius: BorderRadius.circular(14)),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onMakeCards,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
                    EIcon(EIcons.lasso, size: 22, color: c.accent),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                        Text('Make cards from your notes', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
                        Text(
                          'Circle the front, then the back. Ink, images and text all work.',
                          style: TextStyle(fontSize: 13, height: 1.4, color: c.textMuted),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _DeckButton extends StatelessWidget {
  const _DeckButton({required this.deck, required this.selected, required this.onTap});

  final DeckSummary deck;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sub = TextStyle(fontSize: 13, color: c.textMuted);
    final rest = [
      cardsLabel(deck.cards),
      if (deck.notebooks > 1) 'from ${deck.notebooks} notebooks',
    ].join(' · ');
    final summary = deck.cards == 0
        ? 'No cards yet'
        : deck.due > 0
            ? '${deck.due} due · $rest'
            : 'All caught up · $rest';
    return Semantics(
      button: true,
      selected: selected,
      label: '${deck.deck.name}, $summary',
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: selected ? c.accent : c.line, width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: selected ? 13 : 14, vertical: selected ? 11 : 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
              Text(deck.deck.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
              if (deck.due > 0)
                Text.rich(TextSpan(children: [
                  TextSpan(text: '${deck.due} due', style: TextStyle(fontWeight: FontWeight.w700, color: c.clayDeep)),
                  TextSpan(text: '  · $rest'),
                ]), style: sub)
              else
                Text(summary, style: sub),
            ]),
          ),
        ),
      ),
    );
  }
}

/// No decks yet.
class _Empty extends StatelessWidget {
  const _Empty({required this.onMakeCards});

  final VoidCallback onMakeCards;

  @override
  Widget build(BuildContext context) => Center(
        child: _Note(
          title: 'No flashcards yet',
          text: 'In a notebook, pick Study & math → Make flashcards. Circle the front, then the back: ink, images and typed text all work.',
          action: ('Make cards from your notes', onMakeCards),
        ),
      );
}

class _Note extends StatelessWidget {
  const _Note({required this.title, required this.text, this.action});

  final String title;
  final String text;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(mainAxisSize: MainAxisSize.min, spacing: 12, children: [
          Text(title, style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 28, color: c.text)),
          Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.4, color: c.textMuted)),
          if (action case (final label, final onTap)) SecondaryButton(label: label, onPressed: onTap),
        ]),
      ),
    );
  }
}

/// The card's dot grid (Study.dc.html: 1.1 px dots every 22 px).
class _Dots extends CustomPainter {
  _Dots(this.color, this.spacing);

  final Color color;
  final double spacing;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var y = spacing / 2; y < size.height; y += spacing) {
      for (var x = spacing / 2; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_Dots old) => old.color != color || old.spacing != spacing;
}

/// Strokes written on the answer pad; [fit] scales them into the box.
class _Ink extends CustomPainter {
  _Ink(this.strokes, this.color, {this.fit = false});

  final List<List<Offset>> strokes;
  final Color color;
  final bool fit;

  @override
  void paint(Canvas canvas, Size size) {
    if (strokes.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.save();
    if (fit) {
      var r = Rect.fromPoints(strokes.first.first, strokes.first.first);
      for (final s in strokes) {
        for (final p in s) {
          r = r.expandToInclude(Rect.fromPoints(p, p));
        }
      }
      final scale = [size.width / (r.width + 6), size.height / (r.height + 6), 1.0].reduce((a, b) => a < b ? a : b);
      canvas
        ..scale(scale)
        ..translate(-r.left + 3, -r.top + 3);
      paint.strokeWidth = 3 / scale;
    }
    for (final s in strokes) {
      if (s.length == 1) {
        canvas.drawCircle(s.first, paint.strokeWidth / 2, paint..style = PaintingStyle.fill);
        paint.style = PaintingStyle.stroke;
        continue;
      }
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (final p in s.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Ink old) => true;
}
