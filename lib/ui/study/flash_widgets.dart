import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../board/model.dart';
import '../../canvas/flashcard_mode.dart';
import '../../canvas/pane.dart';
import '../../state/notebook.dart';
import '../../study/study_state.dart';
import '../../theme/colors.dart';
import '../common.dart';
import '../dialogs.dart';
import '../icons.dart';
import 'flash_actions.dart';
import 'item_preview.dart';
import 'study_format.dart';

// Making flashcards' chrome (FlashMake.png): the dark bar in the tool
// pill's place, the hint over the page, and the New card panel.

/// "Making flashcards · Deck: Physics — Momentum ▾ · Done".
class FlashBar extends ConsumerWidget {
  const FlashBar({super.key, required this.pane, required this.onDone, this.compact = false});

  final Pane pane;
  final VoidCallback onDone;

  /// Narrow screens: no "Making flashcards" title.
  final bool compact;

  Future<void> _pickDeck(BuildContext context, WidgetRef ref, Offset at) async {
    final decks = ref.read(decksProvider);
    final picked = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx + 1, at.dy + 1),
      items: [
        for (final d in decks)
          CheckedPopupMenuItem(value: d.id, checked: d.id == pane.cards.deckId, child: Text(d.name)),
        const PopupMenuDivider(),
        const PopupMenuItem(value: '', child: Text('New deck…')),
      ],
    );
    if (picked == null || !context.mounted) return;
    if (picked.isEmpty) {
      final name = await showNamePrompt(context, title: 'New deck', action: 'Create');
      if (name == null || name.trim().isEmpty || !context.mounted) return;
      pickDeck(ref, pane, ref.read(decksProvider.notifier).add(name));
      return;
    }
    final deck = ref.read(decksProvider.notifier).byId(picked);
    if (deck != null) pickDeck(ref, pane, deck);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: pane.cards,
      builder: (context, _) => Semantics(
        container: true,
        label: 'Flashcard mode',
        explicitChildNodes: true,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
          decoration: BoxDecoration(
            color: c.inverse,
            borderRadius: BorderRadius.circular(16),
            boxShadow: c.pillShadow,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
            EIcon(EIcons.flashcards, size: 20, color: c.onInverse),
            if (!compact) Text('Making flashcards', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.onInverse)),
            Builder(
              builder: (context) => Semantics(
                button: true,
                label: 'Deck: ${pane.cards.deckName}. Change deck',
                excludeSemantics: true,
                child: Material(
                  color: c.inverseRaised,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      final box = context.findRenderObject() as RenderBox;
                      _pickDeck(context, ref, box.localToGlobal(Offset(0, box.size.height + 6)));
                    },
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                        Flexible(
                          child: Text(
                            'Deck: ${pane.cards.deckName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.onInverse),
                          ),
                        ),
                        EIcon(EIcons.chevronDown, size: 14, color: c.onInverse),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
            Semantics(
              button: true,
              label: 'Done making flashcards',
              excludeSemantics: true,
              child: Material(
                color: c.surface,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onDone,
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    child: Text('Done', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text)),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Over the page: what to circle next, or "Card added to … · Study now".
class FlashHint extends StatelessWidget {
  const FlashHint({super.key, required this.mode, required this.onStudy});

  final FlashcardMode mode;
  final VoidCallback onStudy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: mode,
      builder: (context, _) {
        final added = mode.addedTo;
        if (added != null) {
          return Semantics(
            liveRegion: true,
            explicitChildNodes: true,
            child: Container(
              key: ValueKey(mode.serial),
              padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
              decoration: BoxDecoration(color: c.inverse, borderRadius: BorderRadius.circular(999)),
              child: Row(mainAxisSize: MainAxisSize.min, spacing: 12, children: [
                Text('Card added to $added', style: TextStyle(fontSize: 14, color: c.onInverse)),
                Semantics(
                  button: true,
                  label: 'Study now',
                  excludeSemantics: true,
                  child: Material(
                    color: c.inverseRaised,
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: onStudy,
                      child: Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.center,
                        child: Text('Study now', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.onInverse)),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          );
        }
        return Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${flashHint(mode)} · images, typed text and ink all work',
              style: TextStyle(fontSize: 14, color: c.text),
            ),
          ),
        );
      },
    );
  }
}

/// "New card 4" (FlashMake.png): the front and back as circled, "Also quiz
/// me back to front", Clear and Add card.
class NewCardPanel extends ConsumerWidget {
  const NewCardPanel({super.key, required this.pane, required this.onAdd});

  static const width = 620.0;

  final Pane pane;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final nb = ref.watch(notebookProvider(pane.notebookId));
    final page = nb.pageAt(pane.page);
    final snapshot = ref.watch(studyProvider) ?? StudySnapshot.empty;
    final summaries = deckSummaries(snapshot, ref.watch(decksProvider), DateTime.now().toUtc());
    return ListenableBuilder(
      listenable: pane.cards,
      builder: (context, _) {
        final mode = pane.cards;
        // Cards in the deck: the index's from other notebooks, and this
        // notebook's as they are now.
        final elsewhere = {
          for (final s in summaries)
            if (s.deck.id == mode.deckId)
              for (final i in s.items)
                if (i.card.notebookId != pane.notebookId) i.card.id,
        }.length;
        final here = [
          for (final p in nb.pages)
            for (final i in p.items)
              if (i is FlashcardItem && i.deck == mode.deckId) i,
        ].length;
        final count = elsewhere + here;

        List<Item> items(CircledSide? side) => [for (final id in side?.ids ?? const <String>[]) ?page[id]];

        Widget side(String label, CircledSide? s, Color border, Color labelColor, String waiting) {
          final shown = items(s);
          final box = SizedBox(
            height: 118,
            child: Stack(children: [
              Positioned(
                left: 10,
                top: 8,
                child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.88, color: labelColor)),
              ),
              Positioned.fill(
                top: 24,
                left: 14,
                right: 14,
                bottom: 10,
                child: shown.isEmpty
                    ? Center(child: Text(waiting, style: TextStyle(fontSize: 14, color: c.textMuted)))
                    : ItemsPreview(items: shown, images: page.images, maxScale: 1.2, label: '$label of the new card'),
              ),
            ]),
          );
          if (shown.isEmpty) {
            return DecoratedBox(
              decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(12)),
              child: DashedBorder(color: c.lineStrong, radius: 12, child: box),
            );
          }
          return DecoratedBox(
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: border, width: 1.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: box,
          );
        }

        return Semantics(
          container: true,
          label: 'New flashcard',
          explicitChildNodes: true,
          child: Container(
            width: NewCardPanel.width,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(18),
              boxShadow: c.dialogShadow,
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
              Row(spacing: 10, children: [
                Expanded(child: Text('New card ${count + 1}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.text))),
                Text('${cardsLabel(count)} in this deck so far', style: TextStyle(fontSize: 13, color: c.textMuted)),
              ]),
              Row(spacing: 12, children: [
                Expanded(child: side('FRONT', mode.front, c.accent, c.accentDeep, 'Circle the front')),
                Expanded(
                  child: side('BACK', mode.back, c.clay, c.clayDeep, mode.front == null ? 'Then the back' : 'Now circle the back'),
                ),
              ]),
              Row(spacing: 8, children: [
                Expanded(
                  child: Semantics(
                    checked: mode.reverse,
                    label: 'Also quiz me back to front',
                    excludeSemantics: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => mode.reverse = !mode.reverse,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Row(spacing: 10, children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: Checkbox(
                              value: mode.reverse,
                              onChanged: (v) => mode.reverse = v ?? false,
                              activeColor: c.accent,
                              side: BorderSide(color: c.lineStrong, width: 1.5),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          Text('Also quiz me back to front', style: TextStyle(fontSize: 14, color: c.text)),
                        ]),
                      ),
                    ),
                  ),
                ),
                SecondaryButton(label: 'Clear', height: 44, onPressed: mode.front == null ? null : mode.clear),
                PrimaryButton(label: 'Add card', height: 44, onPressed: mode.ready ? onAdd : null),
              ]),
            ]),
          ),
        );
      },
    );
  }
}
