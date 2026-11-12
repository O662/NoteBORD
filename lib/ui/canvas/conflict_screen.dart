import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../board/model.dart';
import '../../canvas/clusters.dart';
import '../../canvas/live_items.dart' show clockText;
import '../../canvas/page_runtime.dart';
import '../../canvas/pane.dart';
import '../../library/library.dart' show clockProvider;
import '../../state/notebook.dart';
import '../../sync/conflicts.dart';
import '../../sync/versions.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart' show FontFamilies, Radii, TypeScale;
import '../dialogs.dart';
import '../icons.dart';
import '../library/format.dart';
import '../shell.dart' show LayoutWidth;
import 'page_bar.dart' show pageTitle;
import 'version_history.dart' show paintDashedRRect, paintTag;

// This page changed on two devices (design/screens/Conflict.png, Update
// 04): sync already merged it (it never waits for this), and both sides
// are in version history. Here the student sees the two versions side by
// side, what's only on each (green: this tablet, blue: the other device),
// and picks: Merge both (keep what's on the page), Keep this tablet's, Keep
// the other's, or Keep both as pages. Decide later keeps the merge and the
// "pages to check" chip.

extension on NotebookState {
  PageRuntime? pageById(String id) {
    final i = indexOf(id);
    return i < 0 ? null : pages[i];
  }
}

/// What to keep.
enum ConflictChoice { merge, ours, theirs, both }

/// Opens the page to check [conflict] (the canvas's chip).
Future<void> showConflict(BuildContext context, Pane pane, PageConflict conflict) => Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => ConflictScreen(pane: pane, conflict: conflict),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 180),
      ),
    );

/// "the phone" for "Kieth’s phone"; the name as it is otherwise.
String shortDevice(String name) {
  final m = RegExp(r"^.+[’']s (.+)$").firstMatch(name);
  return m == null ? name : 'the ${m[1]}';
}

/// "Kieth’s phone" → a phone; anything else, a tablet.
bool _isPhone(String name) => name.toLowerCase().contains('phone');

class ConflictScreen extends ConsumerStatefulWidget {
  const ConflictScreen({super.key, required this.pane, required this.conflict});

  final Pane pane;
  final PageConflict conflict;

  @override
  ConsumerState<ConflictScreen> createState() => _ConflictScreenState();
}

class _ConflictScreenState extends ConsumerState<ConflictScreen> {
  ConflictChoice _choice = ConflictChoice.merge;
  BoardPage? _ours;
  BoardPage? _theirs;
  bool _missing = false;
  bool _busy = false;

  PageConflict get c => widget.conflict;
  NotebookNotifier get _nb => ref.read(notebookProvider(c.notebookId).notifier);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final versions = await _nb.versionsOf(c.pageId);
    PageVersion? find(String name) => versions.where((v) => v.name == name).firstOrNull;
    final ours = find(c.ours), theirs = find(c.theirs);
    final o = ours == null ? null : await _nb.loadVersion(c.pageId, ours);
    final t = theirs == null ? null : await _nb.loadVersion(c.pageId, theirs);
    if (!mounted) return;
    setState(() {
      _ours = o;
      _theirs = t;
      _missing = o == null || t == null;
    });
  }

  String get _other => shortDevice(c.device);

  String _choiceLabel(ConflictChoice ch) => switch (ch) {
        ConflictChoice.merge => 'Merge both',
        ConflictChoice.ours => 'Keep this tablet’s',
        ConflictChoice.theirs => 'Keep $_other’s',
        ConflictChoice.both => 'Keep both as pages',
      };

  String _choiceDesc(ConflictChoice ch) => switch (ch) {
        ConflictChoice.merge => 'Every stroke from both devices, on one page. Nothing is lost. Moved items use the newest spot.',
        ConflictChoice.ours => '${_capital(_other)}’s changes are set aside in version history.',
        ConflictChoice.theirs => 'This tablet’s changes are set aside in version history.',
        ConflictChoice.both => '${_capital(_other)}’s version becomes a new page right after this one.',
      };

  static String _capital(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Future<void> _apply() async {
    if (_busy) return;
    setState(() => _busy = true);
    final pane = widget.pane;
    final notebook = ref.read(notebookProvider(c.notebookId));
    final title = pageTitle(notebook.pageById(c.pageId)?.page ?? BoardPage(id: c.pageId));
    String done;
    switch (_choice) {
      case ConflictChoice.merge:
        done = 'Merged · both versions are on the page';
      case ConflictChoice.ours:
        await _nb.restoreVersion(c.pageId, _ours!);
        done = 'Kept this tablet’s version';
      case ConflictChoice.theirs:
        await _nb.restoreVersion(c.pageId, _theirs!);
        done = 'Kept $_other’s version';
      case ConflictChoice.both:
        await _nb.restoreVersion(c.pageId, _ours!);
        final at = _nb.insertPageCopy(c.pageId, _theirs!, title: '$title (${c.device})');
        done = at == null ? 'Kept this tablet’s version' : 'Added $_other’s version as page ${at + 1}';
    }
    await ref.read(conflictsProvider.notifier).resolve(c.notebookId, c.pageId);
    if (!mounted) return;
    Navigator.of(context).pop();
    pane.toast(done, undoPageId: _choice == ConflictChoice.merge ? null : c.pageId);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final nb = ref.watch(notebookProvider(c.notebookId));
    final all = ref.watch(conflictsProvider.select((list) => [for (final x in list) if (x.notebookId == c.notebookId) x]));
    final index = all.indexWhere((x) => x.pageId == c.pageId);
    final page = nb.pageById(c.pageId)?.page;
    final now = ref.read(clockProvider)().toUtc();
    final narrow = context.narrow;

    String edited(DateTime at) => 'Edited ${dayWhen(at, now).toLowerCase()} at ${clockText(at.toLocal(), seconds: false)}';

    // What's only on each side; a moved item shows on the side whose spot
    // the merge kept.
    final ours = _ours, theirs = _theirs;
    var oursOnly = const <Item>[], theirsOnly = const <Item>[], movedHere = const <Item>[], movedThere = const <Item>[];
    if (ours != null && theirs != null) {
      oursOnly = itemChanges(theirs, ours).added;
      theirsOnly = itemChanges(ours, theirs).added;
      final inTheirs = {for (final i in theirs.items) i.id: i};
      final now = {for (final i in page?.items ?? const <Item>[]) i.id: i};
      final moved = [
        for (final i in ours.items)
          if (inTheirs[i.id] case final t? when t.bounds != i.bounds) (i, t),
      ];
      movedThere = [for (final (o, t) in moved) if (now[o.id]?.bounds == t.bounds) t];
      movedHere = [for (final (o, t) in moved) if (now[o.id]?.bounds != t.bounds) o];
    }

    String onlyHere(List<Item> only, List<Item> moved) {
      final parts = <String>[];
      final s = changeSummary(only, const []);
      if (s != null) parts.add(s.replaceFirst('+', ''));
      if (moved.isNotEmpty) parts.add(moved.length == 1 ? '1 item moved' : '${moved.length} items moved');
      return parts.isEmpty ? 'Nothing that isn’t on the other' : 'Only here: ${parts.join(', and ')}';
    }

    final keepsOurs = _choice != ConflictChoice.theirs, keepsTheirs = _choice != ConflictChoice.ours;

    Widget card({required bool mine}) => _VersionCard(
          device: mine ? 'This tablet' : c.device,
          phone: !mine && _isPhone(c.device),
          when: mine ? edited(c.oursAt) : '${edited(c.theirsAt)} · was offline',
          page: mine ? ours : theirs,
          only: mine ? oursOnly : theirsOnly,
          moved: mine ? movedHere : movedThere,
          green: mine,
          keeping: mine ? keepsOurs : keepsTheirs,
          summary: (mine ? ours : theirs) == null ? '' : onlyHere(mine ? oursOnly : theirsOnly, mine ? movedHere : movedThere),
        );

    final panel = _ChoicePanel(
      choice: _choice,
      label: _choiceLabel,
      desc: _choiceDesc,
      enabled: !_missing && ours != null && theirs != null,
      busy: _busy,
      onPick: (ch) => setState(() => _choice = ch),
      onApply: _apply,
      onLater: () => Navigator.of(context).pop(),
    );

    final header = Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 14, children: [
      _BackButton(onTap: () => Navigator.of(context).pop()),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
          Semantics(
            header: true,
            child: Text('This page changed on two devices',
                style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 32, height: 1.15, color: colors.text)),
          ),
          Text(
            '${nb.notebook.title} › ${page == null ? '' : pageTitle(page)} · ${c.device} was offline while you wrote on this tablet',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: colors.textMuted),
          ),
        ]),
      ),
      if (all.isNotEmpty)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: colors.stickyYellow, borderRadius: BorderRadius.circular(999)),
          child: Text('${index < 0 ? 1 : index + 1} of ${all.length} ${all.length == 1 ? 'page' : 'pages'} to check',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colors.goldDeep)),
        ),
    ]);

    final cards = _missing
        ? Center(
            child: Text('One of the versions isn’t in version history any more. The page stays merged.',
                style: TextStyle(fontSize: 15, color: colors.textMuted)),
          )
        : Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
            Expanded(child: card(mine: true)),
            Expanded(child: card(mine: false)),
          ]);

    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(narrow ? 16 : 24, 20, narrow ? 16 : 24, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
            header,
            Expanded(
              child: narrow
                  ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
                      Expanded(child: cards),
                      panel,
                    ])
                  : Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
                      Expanded(child: cards),
                      SizedBox(width: 340, child: panel),
                    ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'Back',
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(side: BorderSide(color: c.line), borderRadius: BorderRadius.circular(Radii.button)),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.button),
          onTap: onTap,
          child: SizedBox(width: 44, height: 44, child: Center(child: EIcon(EIcons.back, color: c.text))),
        ),
      ),
    );
  }
}

class _VersionCard extends StatelessWidget {
  const _VersionCard({
    required this.device,
    required this.phone,
    required this.when,
    required this.page,
    required this.only,
    required this.moved,
    required this.green,
    required this.keeping,
    required this.summary,
  });

  final String device;
  final bool phone;
  final String when;
  final BoardPage? page;
  final List<Item> only;
  final List<Item> moved;

  /// This tablet's side: green highlights (the other's are blue).
  final bool green;
  final bool keeping;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = green ? c.green : c.accent;
    return Semantics(
      container: true,
      label: '$device version. ${keeping ? 'Keeping' : 'Set aside'}. $summary',
      explicitChildNodes: true,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: keeping ? 1 : 0.5,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: keeping ? c.accent : c.line, width: keeping ? 2 : 1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
            Row(spacing: 12, children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: c.side, borderRadius: BorderRadius.circular(Radii.key)),
                child: Center(child: EIcon(phone ? EIcons.phone : EIcons.tablet, color: c.text)),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                  Text(device, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
                  Text(when, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.textMuted)),
                ]),
              ),
              if (keeping)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: c.greenTint, borderRadius: BorderRadius.circular(999)),
                  child: Text('KEEPING', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: c.greenDeep)),
                ),
            ]),
            Expanded(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: c.bg,
                  border: Border.all(color: c.lineSoft),
                  borderRadius: BorderRadius.circular(Radii.card),
                ),
                child: page == null
                    ? const Center(child: CircularProgressIndicator())
                    : _SidePreview(page: page!, only: only, moved: moved, tint: tint, fill: green ? c.greenTint : c.accentTint),
              ),
            ),
            Row(spacing: 8, children: [
              DashedBox(color: tint, fill: green ? c.greenTint : c.accentTint),
              Expanded(child: Text(summary, style: TextStyle(fontSize: 13, color: c.text))),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// The small dashed square beside "Only here".
class DashedBox extends StatelessWidget {
  const DashedBox({super.key, required this.color, required this.fill});

  final Color color;
  final Color fill;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size.square(16),
        painter: _DashedBoxPainter(color, fill),
      );
}

class _DashedBoxPainter extends CustomPainter {
  _DashedBoxPainter(this.color, this.fill);

  final Color color;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4));
    canvas.drawRRect(rr, Paint()..color = fill);
    paintDashedRRect(canvas, rr, color, width: 1.2);
  }

  @override
  bool shouldRepaint(_DashedBoxPainter old) => old.color != color || old.fill != fill;
}

class _SidePreview extends StatefulWidget {
  const _SidePreview({required this.page, required this.only, required this.moved, required this.tint, required this.fill});

  final BoardPage page;
  final List<Item> only;
  final List<Item> moved;
  final Color tint;
  final Color fill;

  @override
  State<_SidePreview> createState() => _SidePreviewState();
}

class _SidePreviewState extends State<_SidePreview> {
  late PageRuntime _runtime = PageRuntime(widget.page);

  @override
  void didUpdateWidget(_SidePreview old) {
    super.didUpdateWidget(old);
    if (old.page != widget.page) {
      _runtime.dispose();
      _runtime = PageRuntime(widget.page);
    }
  }

  @override
  void dispose() {
    _runtime.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _SidePainter(_runtime, Theme.of(context).brightness, context.colors, widget.only, widget.moved, widget.tint, widget.fill),
      );
}

class _SidePainter extends CustomPainter {
  _SidePainter(this.page, this.brightness, this.colors, this.only, this.moved, this.tint, this.fill);

  final PageRuntime page;
  final Brightness brightness;
  final EndlessColors colors;
  final List<Item> only;
  final List<Item> moved;
  final Color tint;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final content = page.contentBounds;
    if (content == null) return;
    final padded = content.inflate(math.max(content.width, content.height) * 0.06 + 24);
    final area = (Offset.zero & size).deflate(12);
    final scale = math.min(area.width / padded.width, area.height / padded.height);
    final dx = area.center.dx - padded.center.dx * scale, dy = area.center.dy - padded.center.dy * scale;
    Rect toScreen(Rect r) => Rect.fromLTRB(r.left * scale + dx, r.top * scale + dy, r.right * scale + dx, r.bottom * scale + dy);
    final boxes = [for (final r in clustersOf(only)) toScreen(r).inflate(8)];
    for (final b in boxes) {
      canvas.drawRRect(RRect.fromRectAndRadius(b, const Radius.circular(10)), Paint()..color = fill.withValues(alpha: 0.85));
    }
    canvas.save();
    canvas.clipRect(area);
    canvas.translate(dx, dy);
    canvas.scale(scale);
    canvas.drawPicture(page.fullPicture(brightness, colors));
    canvas.restore();
    for (final b in boxes) {
      paintDashedRRect(canvas, RRect.fromRectAndRadius(b, const Radius.circular(10)), tint);
    }
    for (final r in clustersOf(moved)) {
      final b = toScreen(r);
      paintTag(canvas, 'moved', Offset(b.left + 70, b.bottom + 16), colors.surface, colors.textMuted);
    }
  }

  @override
  bool shouldRepaint(_SidePainter old) => old.page != page || old.only != only || old.moved != moved || old.brightness != brightness;
}

class _ChoicePanel extends StatelessWidget {
  const _ChoicePanel({
    required this.choice,
    required this.label,
    required this.desc,
    required this.enabled,
    required this.busy,
    required this.onPick,
    required this.onApply,
    required this.onLater,
  });

  final ConflictChoice choice;
  final String Function(ConflictChoice) label;
  final String Function(ConflictChoice) desc;
  final bool enabled;
  final bool busy;
  final ValueChanged<ConflictChoice> onPick;
  final VoidCallback onApply;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
        Text('WHAT SHOULD WE KEEP?', style: TypeScale.sectionLabel.copyWith(fontWeight: FontWeight.w700, color: c.textMuted)),
        for (final ch in ConflictChoice.values)
          Semantics(
            inMutuallyExclusiveGroup: true,
            checked: choice == ch,
            button: true,
            label: label(ch),
            hint: desc(ch),
            excludeSemantics: true,
            child: Material(
              color: choice == ch ? c.accentWash : c.surface,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: choice == ch ? c.accent : c.lineSoft, width: choice == ch ? 2 : 1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onPick(ch),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
                    Container(
                      width: 20,
                      height: 20,
                      margin: const EdgeInsets.only(top: 1),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: choice == ch ? c.accent : c.lineDashed, width: choice == ch ? 6 : 2),
                      ),
                    ),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
                        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          Text(label(ch), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
                          if (ch == ConflictChoice.merge)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(color: c.greenTint, borderRadius: BorderRadius.circular(999)),
                              child: Text('RECOMMENDED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: c.greenDeep)),
                            ),
                        ]),
                        Text(desc(ch), style: TextStyle(fontSize: 13, height: 1.35, color: c.textMuted)),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        const Spacer(),
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
          EIcon(EIcons.history, size: 16, color: c.textMuted),
          Expanded(
            child: Text('Whatever you choose, both versions stay in version history for 30 days.',
                style: TextStyle(fontSize: 12, color: c.textMuted)),
          ),
        ]),
        const SizedBox(height: 4),
        PrimaryButton(
          label: choice == ConflictChoice.merge ? 'Merge and continue' : 'Keep and continue',
          height: 52,
          expand: true,
          onPressed: enabled && !busy ? onApply : null,
        ),
        Center(
          child: Semantics(
            button: true,
            label: 'Decide later',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.key),
              onTap: onLater,
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                child: Text('Decide later', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.accent)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
