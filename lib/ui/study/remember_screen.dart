import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../board/model.dart';
import '../../library/library.dart';
import '../../recognition/handwriting_index.dart';
import '../../study/remember_edits.dart';
import '../../study/study_rows.dart';
import '../../study/study_state.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../common.dart';
import '../dialogs.dart' show showConfirm;
import '../icons.dart';
import '../library/sidebar.dart';
import '../routes.dart';
import 'item_preview.dart';
import 'study_format.dart';

/// A filter chip: everything, things with a reminder, or a folder's.
@immutable
class _Filter {
  const _Filter(this.id, this.label);

  static const all = _Filter('all', 'All');
  static const reminders = _Filter('reminders', 'Has a reminder');

  final String id;
  final String label;

  @override
  bool operator ==(Object other) => other is _Filter && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Need to remember (Remember.png): everything starred, across notebooks,
/// with filters and Review all.
class RememberScreen extends ConsumerStatefulWidget {
  const RememberScreen({super.key});

  @override
  ConsumerState<RememberScreen> createState() => _RememberScreenState();
}

class _RememberScreenState extends ConsumerState<RememberScreen> {
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    // Anything not read into the index yet (as Search does): a notebook
    // imported or changed elsewhere shows here too.
    final index = ref.read(handwritingIndexProvider);
    if (ref.read(catchUpOnStartProvider)) index.catchUp();
  }

  /// Unstarred while this screen is open: shown faded, with their marks as
  /// they were, so a second tap stars them again.
  final _off = <String, (RememberedThing, Map<String, Json>)>{};

  /// Review all: which one is showing.
  int? _review;

  static String _key(RememberedThing t) => '${t.notebookId}/${t.id}';

  String _folderOf(LibraryState lib, RememberedThing t) {
    final folder = lib.byId(t.notebookId)?.folder ?? const [];
    return folder.isEmpty ? 'No folder' : folder.last;
  }

  bool _takes(_Filter f, LibraryState lib, RememberedThing t) => switch (f.id) {
        'all' => true,
        'reminders' => t.hasReminder,
        _ => _folderOf(lib, t) == f.label,
      };

  Future<void> _toggle(RememberedThing t) async {
    final key = _key(t);
    final off = _off[key];
    if (off == null) {
      // Asked first: it's easy to tap a star by accident.
      final sure = await showConfirm(
        context,
        title: 'Remove from Need to remember?',
        message: t.hasReminder || t.why.isNotEmpty
            ? 'It stays in your notes, but loses its star${t.why.isNotEmpty ? ', why it matters' : ''}'
                '${t.hasReminder ? ' and its reminder' : ''}. Tap its star again before you leave this screen to bring it back.'
            : 'It stays in your notes, without its star. Tap its star again before you leave this screen to bring it back.',
        action: 'Remove',
      );
      if (!sure || !mounted) return;
      final was = await forgetThing(ref, t);
      if (mounted && was.isNotEmpty) setState(() => _off[key] = (t, was));
    } else {
      await restoreThing(ref, off.$1, off.$2);
      if (mounted) setState(() => _off.remove(key));
    }
  }

  void _open(RememberedThing t) => openSpot(context, ref, t.notebookId, t.pageId, t.rect);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lib = ref.watch(libraryProvider);
    final snapshot = ref.watch(studyProvider);
    final live = snapshot?.remembered ?? const <RememberedThing>[];
    final liveKeys = {for (final t in live) _key(t)};
    // Newest first, with the ones just unstarred where they were.
    final things = [
      ...live,
      for (final o in _off.values)
        if (!liveKeys.contains(_key(o.$1))) o.$1,
    ]..sort((a, b) => b.at.compareTo(a.at));
    final starred = [for (final t in things) if (!_off.containsKey(_key(t))) t];
    final notebooks = {for (final t in starred) t.notebookId}.length;

    final folders = <String, int>{};
    for (final t in starred) {
      folders.update(_folderOf(lib, t), (n) => n + 1, ifAbsent: () => 1);
    }
    final filters = [
      _Filter.all,
      _Filter.reminders,
      for (final f in (folders.keys.toList()..sort((a, b) => folders[b]!.compareTo(folders[a]!)))) _Filter('folder:$f', f),
    ];
    if (!filters.contains(_filter)) _filter = _Filter.all;
    final shown = [for (final t in things) if (_takes(_filter, lib, t)) t];
    final review = _review;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const AppSidebar(selected: SidebarItem.remember),
          Expanded(
            child: Stack(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(36, 28, 36, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 18, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.end, spacing: 16, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
                        Row(spacing: 12, children: [
                          EIcon(EIcons.star, size: 32, color: c.gold),
                          Text(
                            'Need to remember',
                            style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 40, letterSpacing: -0.8, color: c.text),
                          ),
                        ]),
                        Text(
                          '${thingsLabel(starred.length)} from ${notebooks == 1 ? '1 notebook' : '$notebooks notebooks'}'
                          ' · lasso anything and tap Remember, or draw a star next to it',
                          style: TextStyle(fontSize: 14, color: c.textMuted),
                        ),
                      ]),
                    ),
                    if (starred.isNotEmpty)
                      Semantics(
                        button: true,
                        label: 'Review all',
                        excludeSemantics: true,
                        child: Material(
                          color: c.inverse,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => setState(() => _review = 0),
                            child: Container(
                              height: 48,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
                                EIcon(EIcons.play, size: 18, color: c.onInverse),
                                Text('Review all', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.onInverse)),
                              ]),
                            ),
                          ),
                        ),
                      ),
                  ]),
                  if (things.isNotEmpty)
                    Semantics(
                      container: true,
                      label: 'Filter',
                      explicitChildNodes: true,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(spacing: 8, children: [
                          for (final f in filters)
                            _Chip(
                              label: f.label,
                              count: [for (final t in starred) if (_takes(f, lib, t)) t].length,
                              on: f == _filter,
                              onTap: () => setState(() => _filter = f),
                            ),
                        ]),
                      ),
                    ),
                  Expanded(
                    child: things.isEmpty
                        ? (snapshot == null ? const SizedBox.shrink() : const _Empty())
                        : LayoutBuilder(builder: (context, box) {
                            final columns = box.maxWidth >= 880 ? 4 : (box.maxWidth >= 640 ? 3 : 2);
                            return GridView.builder(
                              padding: const EdgeInsets.only(bottom: 28),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                mainAxisSpacing: 16,
                                crossAxisSpacing: 16,
                                // Remember.dc.html's cards are 224 tall; the source link is a 44 dp target.
                                mainAxisExtent: 250,
                              ),
                              itemCount: shown.length,
                              itemBuilder: (context, i) {
                                final t = shown[i];
                                return _ThingCard(
                                  thing: t,
                                  starred: !_off.containsKey(_key(t)),
                                  onStar: () => _toggle(t),
                                  onOpen: () => _open(t),
                                );
                              },
                            );
                          }),
                  ),
                ]),
              ),
              if (review != null && starred.isNotEmpty)
                Positioned.fill(
                  child: _Review(
                    things: starred,
                    index: review.clamp(0, starred.length - 1),
                    onIndex: (i) => setState(() => _review = i),
                    onDone: () => setState(() => _review = null),
                    onOpen: _open,
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.count, required this.on, required this.onTap});

  final String label;
  final int count;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = on ? c.onInverse : c.text;
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: on,
      label: '$label, $count',
      excludeSemantics: true,
      child: Material(
        color: on ? c.inverse : c.surface,
        shape: StadiumBorder(side: BorderSide(color: on ? c.inverse : c.line)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
              Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: fg)),
              Text('$count', style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.8))),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The yellow dotted paper things are shown on (Remember.dc.html).
class _Paper extends StatelessWidget {
  const _Paper({required this.child, this.radius = 10, this.spacing = 12, this.border = false});

  final Widget child;
  final double radius;
  final double spacing;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.rememberPaper,
        borderRadius: BorderRadius.circular(radius),
        border: border ? Border.all(color: c.rememberLine) : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: CustomPaint(painter: _PaperDots(c.rememberDot, spacing), child: child),
      ),
    );
  }
}

class _PaperDots extends CustomPainter {
  _PaperDots(this.color, this.spacing);

  final Color color;
  final double spacing;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var y = spacing / 2; y < size.height; y += spacing) {
      for (var x = spacing / 2; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_PaperDots old) => old.color != color || old.spacing != spacing;
}

/// What's remembered, drawn (or typed text, in type).
class _Content extends StatelessWidget {
  const _Content({required this.thing, required this.big});

  final RememberedThing thing;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (thing.typedOnly) {
      final text = thing.items.whereType<TextItem>().map((t) => t.text.trim()).join('\n');
      return Align(
        alignment: big ? Alignment.center : Alignment.centerLeft,
        child: Text(
          text,
          maxLines: big ? 6 : 4,
          overflow: TextOverflow.ellipsis,
          textAlign: big ? TextAlign.center : TextAlign.start,
          style: big
              ? TextStyle(fontFamily: FontFamilies.serif, fontSize: 32, height: 1.25, color: c.text)
              : TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.35, color: c.text),
        ),
      );
    }
    return ItemsPreview(
      items: thing.items,
      notebookId: thing.notebookId,
      maxScale: big ? 2.5 : 1,
      alignment: big ? Alignment.center : Alignment.centerLeft,
      label: thing.said.isEmpty ? 'Handwriting' : thing.said,
    );
  }
}

/// "Physics — Lecture notes · p. 3", with the notebook's color.
class _Source extends ConsumerWidget {
  const _Source({required this.thing, required this.onOpen});

  final RememberedThing thing;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final nb = ref.watch(libraryProvider).byId(thing.notebookId);
    final pages = ref.watch(pageIdsProvider(thing.notebookId)).value;
    final page = pages == null ? 0 : pages.indexOf(thing.pageId) + 1;
    final text = '${nb?.title ?? 'A notebook'}${page > 0 ? ' · p. $page' : ''}';
    return Semantics(
      link: true,
      label: 'Open $text',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onOpen,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(spacing: 6, children: [
            Container(
              width: 6,
              height: 16,
              decoration: BoxDecoration(color: nb?.cover ?? c.accent, borderRadius: BorderRadius.circular(2)),
            ),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.accent),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, this.reminder = false});

  final String text;
  final bool reminder;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = reminder ? c.goldDeep : c.inverseRaised;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: reminder ? c.stickyYellow : c.side, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
        if (reminder) EIcon(EIcons.bell, size: 11, color: fg),
        Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
      ]),
    );
  }
}

class _ThingCard extends ConsumerWidget {
  const _ThingCard({required this.thing, required this.starred, required this.onStar, required this.onOpen});

  final RememberedThing thing;
  final bool starred;
  final VoidCallback onStar;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final now = ref.read(clockProvider)();
    final t = thing;
    return Opacity(
      opacity: starred ? 1 : 0.5,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          SizedBox(
            height: 104,
            child: Stack(children: [
              Positioned.fill(
                child: _Paper(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 40, 10),
                    child: _Content(thing: t, big: false),
                  ),
                ),
              ),
              Positioned(
                right: -6,
                top: -6,
                child: ChromeButton(
                  label: starred ? 'Remove from Need to remember' : 'Add back to Need to remember',
                  icon: starred ? EIcons.star : EIcons.starOutline,
                  iconSize: 22,
                  selected: false,
                  onPressed: onStar,
                ),
              ),
            ]),
          ),
          if (t.why.isNotEmpty)
            Text(
              '“${t.why}”',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: FontFamilies.handwritingSample, fontSize: 19, height: 1.1, color: c.textMuted),
            ),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (t.hasReminder) _Tag(text: reminderChip(t.remindAt!, now), reminder: true),
            if (t.flashcard != null) const _Tag(text: 'Also a flashcard'),
            if (t.drawn) const _Tag(text: 'Drawn star'),
          ]),
          const Spacer(),
          _Source(thing: t, onOpen: onOpen),
        ]),
      ),
    );
  }
}

/// Review all: one thing at a time, big.
class _Review extends StatelessWidget {
  const _Review({required this.things, required this.index, required this.onIndex, required this.onDone, required this.onOpen});

  final List<RememberedThing> things;
  final int index;
  final ValueChanged<int> onIndex;
  final VoidCallback onDone;
  final ValueChanged<RememberedThing> onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = things[index];
    void next() => onIndex((index + 1) % things.length);
    void previous() => onIndex(index == 0 ? 0 : index - 1);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): next,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): previous,
        const SingleActivator(LogicalKeyboardKey.escape): onDone,
      },
      child: Focus(
        autofocus: true,
        child: Semantics(
          container: true,
          label: 'Review what to remember',
          explicitChildNodes: true,
          child: ColoredBox(
            color: c.bg.withValues(alpha: 0.97),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, spacing: 18, children: [
                Text('${index + 1} of ${things.length}', style: TextStyle(fontSize: 14, color: c.textMuted)),
                SizedBox(
                  width: 640,
                  height: 340,
                  child: _Paper(
                    radius: 22,
                    spacing: 20,
                    border: true,
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(spacing: 14, children: [
                        Expanded(child: _Content(thing: t, big: true)),
                        if (t.why.isNotEmpty)
                          Text(
                            '“${t.why}”',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontFamily: FontFamilies.handwritingSample, fontSize: 26, color: c.textMuted),
                          ),
                        SizedBox(width: 360, child: Center(child: _Source(thing: t, onOpen: () => onOpen(t)))),
                      ]),
                    ),
                  ),
                ),
                Row(mainAxisSize: MainAxisSize.min, spacing: 10, children: [
                  _ReviewButton(label: 'Previous', onTap: previous),
                  _ReviewButton(label: 'Next', onTap: next, dark: true),
                  _ReviewButton(label: 'Done', onTap: onDone),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewButton extends StatelessWidget {
  const _ReviewButton({required this.label, required this.onTap, this.dark = false});

  final String label;
  final VoidCallback onTap;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: dark ? c.inverse : c.surface,
        shape: RoundedRectangleBorder(
          side: dark ? BorderSide.none : BorderSide(color: c.lineStrong),
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            height: 52,
            padding: EdgeInsets.symmetric(horizontal: dark ? 28 : 20),
            alignment: Alignment.center,
            child: Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: dark ? c.onInverse : c.text)),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(spacing: 12, children: [
        Text('Nothing to remember yet', style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 28, color: c.text)),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Text(
            'In a notebook, lasso anything and tap Remember (Study & math → Need to remember), or draw a star next to it.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 1.4, color: c.textMuted),
          ),
        ),
      ]),
    );
  }
}
