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
import '../../state/settings.dart';
import '../../sync/versions.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart' show FontFamilies, Radii, TypeScale;
import '../calendar/calendar_widgets.dart' show Segmented;
import '../common.dart';
import '../dialogs.dart';
import '../icons.dart';
import '../library/format.dart';
import '../shell.dart' show LayoutWidth;
import 'page_bar.dart' show pageTitle;

// Version history (design/screens/History.png, History-naming.png; Update
// 04): the page's earlier versions, kept on this tablet as you write
// (lib/sync/versions.dart), grouped by day with what changed; a preview
// with Show changes (what that version added, what was erased later);
// Restore (today's page is kept as a version first, with Undo), Save as a
// new page, and Name this version (named versions are kept until deleted,
// the others for 30 days). All versions / Named only.

/// Opens Version history for the page [pane] shows (⋯ → Version history).
Future<void> showVersionHistory(BuildContext context, Pane pane) => Navigator.of(context).push(PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => VersionHistoryScreen(pane: pane),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      transitionDuration: const Duration(milliseconds: 180),
    ));

/// "Before changes from Kim's tablet", "While writing", …
String versionReason(PageVersion v) => switch (v.reason) {
      VersionReason.edit => 'While writing',
      VersionReason.sync => v.device == null ? 'Before changes from another device' : 'Before changes from ${v.device}',
      VersionReason.restore => 'Before an earlier version was restored',
      VersionReason.remote => v.device == null ? 'Another device’s version' : '${v.device}’s version',
    };

class VersionHistoryScreen extends ConsumerStatefulWidget {
  const VersionHistoryScreen({super.key, required this.pane});

  final Pane pane;

  @override
  ConsumerState<VersionHistoryScreen> createState() => _VersionHistoryState();
}

class _VersionHistoryState extends ConsumerState<VersionHistoryScreen> {
  List<PageVersion>? _versions;

  /// Each version's page, as they load (null: can't be read).
  final _pages = <String, BoardPage?>{};
  PageVersion? _picked;
  PageRuntime? _preview;
  bool _showChanges = true;
  bool _namedOnly = false;
  bool _naming = false;
  final _name = TextEditingController();
  late final String _pageId;
  late final String _pageTitle;

  NotebookNotifier get _nb => ref.read(notebookProvider(widget.pane.notebookId).notifier);

  @override
  void initState() {
    super.initState();
    final nb = ref.read(notebookProvider(widget.pane.notebookId));
    final i = widget.pane.page.clamp(0, nb.pages.length - 1);
    _pageId = nb.pages[i].id;
    _pageTitle = pageTitle(nb.pages[i].page);
    _load(pick: true);
  }

  @override
  void dispose() {
    _preview?.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _load({bool pick = false}) async {
    final v = await _nb.versionsOf(_pageId);
    if (!mounted) return;
    setState(() => _versions = v);
    if (pick && v.isNotEmpty) await _pick(v.first);
    // Every version's page, for what changed in each (newest first).
    for (final x in v) {
      if (_pages.containsKey(x.name)) continue;
      final page = await _nb.loadVersion(_pageId, x);
      if (!mounted) return;
      setState(() => _pages[x.name] = page);
    }
  }

  Future<void> _pick(PageVersion v) async {
    setState(() {
      _picked = v;
      _naming = false;
    });
    final page = _pages.containsKey(v.name) ? _pages[v.name] : await _nb.loadVersion(_pageId, v);
    if (!mounted || _picked != v) return;
    setState(() {
      _pages[v.name] = page;
      _preview?.dispose();
      _preview = page == null ? null : PageRuntime(page);
    });
  }

  /// The version before [v] (older), if there is one.
  PageVersion? _older(PageVersion v) {
    final all = _versions ?? const [];
    final i = all.indexOf(v);
    return i >= 0 && i + 1 < all.length ? all[i + 1] : null;
  }

  /// "+12 strokes · 1 image", "Before changes from Kim's phone", …
  String _summary(PageVersion v) {
    final page = _pages[v.name];
    final older = _older(v);
    final String? changes;
    if (page == null) {
      changes = _pages.containsKey(v.name) ? 'Can’t be opened' : null;
    } else if (older == null) {
      changes = 'First notes on this page';
    } else if (!_pages.containsKey(older.name)) {
      changes = null;
    } else {
      final (:added, :removed) = itemChanges(_pages[older.name], page);
      changes = changeSummary(added, removed) ?? 'Moved or changed things';
    }
    return switch (v.reason) {
      VersionReason.sync || VersionReason.remote => [versionReason(v), ?changes].join(' · '),
      VersionReason.restore => [ 'Before a restore', ?changes].join(' · '),
      VersionReason.edit => changes ?? '…',
    };
  }

  /// What version [v] ([page]) added since the one before it, and what of
  /// it has been erased since (it's not on the page now).
  ({List<Item> added, List<Item> erased}) _changes(NotebookState nb, PageVersion v, BoardPage page) {
    final older = _older(v);
    final i = nb.indexOf(_pageId);
    final now = i < 0 ? const <String>{} : {for (final x in nb.pages[i].page.items) x.id};
    return (
      added: itemChanges(older == null ? null : _pages[older.name], page).added,
      erased: [for (final x in page.items) if (!now.contains(x.id)) x],
    );
  }

  String _when(PageVersion v) {
    final now = ref.read(clockProvider)().toUtc();
    return '${dayWhen(v.at, now)}, ${clockText(v.at.toLocal(), seconds: false)}';
  }

  Future<void> _restore() async {
    final page = _preview?.page;
    final v = _picked;
    if (page == null || v == null) return;
    final ok = await _nb.restoreVersion(_pageId, page);
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.pane.toast(ok ? 'Restored the version from ${_when(v)}' : 'This page can’t be changed now', undoPageId: ok ? _pageId : null);
  }

  void _saveAsPage() {
    final page = _preview?.page;
    final v = _picked;
    if (page == null || v == null) return;
    final at = _nb.insertPageCopy(_pageId, page, title: '$_pageTitle (${_when(v)})');
    if (at == null) return;
    Navigator.of(context).pop();
    final pane = widget.pane;
    final newId = ref.read(notebookProvider(pane.notebookId)).pages[at].id;
    pane.goTo(at);
    pane.toast('Saved the version from ${_when(v)} as page ${at + 1}', action: ('Undo', () {
      final nb = ref.read(notebookProvider(pane.notebookId).notifier);
      nb.removePage(newId, force: true);
    }));
  }

  Future<void> _saveName() async {
    final v = _picked;
    if (v == null) return;
    await _nb.nameVersion(_pageId, v, _name.text);
    if (!mounted) return;
    setState(() => _naming = false);
    await _load();
    final again = _versions?.where((x) => x.name == v.name).firstOrNull;
    if (again != null && mounted) setState(() => _picked = again);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final nb = ref.watch(notebookProvider(widget.pane.notebookId));
    final sealed = nb.isSealed(_pageId);
    final keepDays = ref.watch(settingsProvider.select((s) => s.versionDays));
    final all = _versions;
    final shown = all == null ? null : [for (final v in all) if (!_namedOnly || v.label != null) v];
    final narrow = context.narrow;

    final header = Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 14, children: [
      _BoxButton(label: 'Back', icon: EIcons.back, onTap: () => Navigator.of(context).pop()),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
          Semantics(
            header: true,
            child: Text('Version history', style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 32, height: 1.15, color: c.text)),
          ),
          Text(
            '${nb.notebook.title} › $_pageTitle · saved automatically as you write, kept for $keepDays days',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: c.textMuted),
          ),
        ]),
      ),
      Segmented<bool>(
        values: const [false, true],
        labels: const ['All versions', 'Named only'],
        value: _namedOnly,
        label: 'Which versions',
        height: 44,
        onChanged: (v) => setState(() => _namedOnly = v),
      ),
    ]);

    final Widget preview;
    if (sealed) {
      preview = _Empty('Unlock the page to see its versions.');
    } else if (all == null) {
      preview = const Center(child: CircularProgressIndicator());
    } else if (all.isEmpty) {
      preview = _Empty('No earlier versions of this page yet. They’re saved as you write.');
    } else {
      preview = _PreviewCard(
        version: _picked,
        when: _picked == null ? '' : _when(_picked!),
        summary: _picked == null ? '' : 'This tablet · ${_summary(_picked!)}',
        preview: _preview,
        unreadable: _picked != null && _pages.containsKey(_picked!.name) && _pages[_picked!.name] == null,
        changes: _showChanges && _picked != null && _preview != null ? _changes(nb, _picked!, _preview!.page) : null,
        firstVersion: _picked != null && _older(_picked!) == null,
        showChanges: _showChanges,
        onShowChanges: (v) => setState(() => _showChanges = v),
        naming: _naming,
        name: _name,
        onName: () => setState(() {
          _naming = true;
          _name.text = _picked?.label ?? '';
        }),
        onSaveName: _saveName,
        onCancelName: () => setState(() => _naming = false),
        onSaveAsPage: _saveAsPage,
        onRestore: _restore,
      );
    }

    final list = _VersionList(
      versions: shown,
      total: shown?.length ?? 0,
      picked: _picked,
      keepDays: keepDays,
      summary: _summary,
      onPick: _pick,
      now: ref.read(clockProvider)().toUtc(),
    );

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(narrow ? 16 : 24, 20, narrow ? 16 : 24, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
            header,
            Expanded(
              child: narrow
                  ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
                      Expanded(flex: 3, child: preview),
                      Expanded(flex: 2, child: list),
                    ])
                  : Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
                      Expanded(child: preview),
                      SizedBox(width: 358, child: list),
                    ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _Card(child: Center(child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: c.textMuted))));
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(20)),
      child: child,
    );
  }
}

class _BoxButton extends StatelessWidget {
  const _BoxButton({required this.label, required this.icon, required this.onTap});

  final String label;
  final EIconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(side: BorderSide(color: c.line), borderRadius: BorderRadius.circular(Radii.button)),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.button),
          onTap: onTap,
          child: SizedBox(width: 44, height: 44, child: Center(child: EIcon(icon, color: c.text))),
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.version,
    required this.when,
    required this.summary,
    required this.preview,
    required this.unreadable,
    required this.changes,
    required this.firstVersion,
    required this.showChanges,
    required this.onShowChanges,
    required this.naming,
    required this.name,
    required this.onName,
    required this.onSaveName,
    required this.onCancelName,
    required this.onSaveAsPage,
    required this.onRestore,
  });

  final PageVersion? version;
  final String when;
  final String summary;
  final PageRuntime? preview;
  final bool unreadable;
  final ({List<Item> added, List<Item> erased})? changes;
  final bool firstVersion;
  final bool showChanges;
  final ValueChanged<bool> onShowChanges;
  final bool naming;
  final TextEditingController name;
  final VoidCallback onName;
  final VoidCallback onSaveName;
  final VoidCallback onCancelName;
  final VoidCallback onSaveAsPage;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ready = preview != null;
    final toggle = Row(mainAxisSize: MainAxisSize.min, spacing: 10, children: [
      Text('Show changes', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.text)),
      Semantics(
        label: 'Show changes',
        toggled: showChanges,
        excludeSemantics: true,
        child: Switch(
          value: showChanges,
          activeThumbColor: c.surface,
          activeTrackColor: c.accent,
          inactiveThumbColor: c.surface,
          inactiveTrackColor: c.switchOff,
          trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
          onChanged: onShowChanges,
        ),
      ),
    ]);
    final top = naming
        ? Row(spacing: 8, children: [
            Expanded(
              child: TextField(
                controller: name,
                autofocus: true,
                onSubmitted: (_) => onSaveName(),
                style: TextStyle(fontSize: 15, color: c.text),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'e.g. Before the midterm',
                  hintStyle: TextStyle(fontSize: 15, color: c.textFaint),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.button),
                    borderSide: BorderSide(color: c.accent, width: 2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.button),
                    borderSide: BorderSide(color: c.accent, width: 2),
                  ),
                ),
              ),
            ),
            PrimaryButton(label: 'Save name', height: 44, color: c.accent, onPressed: onSaveName),
            _TextButton(label: 'Cancel', onTap: onCancelName),
            const SizedBox(width: 8),
            toggle,
          ])
        : Row(spacing: 12, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                Text(when, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.text)),
                Text(summary, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.textMuted)),
              ]),
            ),
            toggle,
          ]);

    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.lineSoft))),
          child: top,
        ),
        Expanded(
          child: ColoredBox(
            color: c.bg,
            child: unreadable
                ? Center(
                    child: Text('This version can’t be opened (it was sealed with an older password).',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: c.textMuted)),
                  )
                : !ready
                    ? const SizedBox.shrink()
                    : Stack(children: [
                        Positioned.fill(
                          child: Semantics(
                            label: 'Preview of the version from $when',
                            child: CustomPaint(
                              painter: _VersionPainter(
                                preview!,
                                Theme.of(context).brightness,
                                c,
                                added: firstVersion ? const [] : changes?.added ?? const [],
                                erased: changes?.erased ?? const [],
                              ),
                            ),
                          ),
                        ),
                        if (showChanges)
                          Positioned(
                            left: 16,
                            bottom: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: c.surface,
                                border: Border.all(color: c.lineSoft),
                                borderRadius: BorderRadius.circular(Radii.key),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, spacing: 14, children: [
                                _Legend(fill: c.greenTint, line: c.green, label: 'Added in this version'),
                                _Legend(fill: c.clayTint, line: c.clay, label: 'Erased later'),
                              ]),
                            ),
                          ),
                      ]),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.lineSoft))),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  'Restoring keeps today’s page as a version, so you can always come back.',
                  style: TextStyle(fontSize: 13, color: c.textMuted),
                ),
              ),
              DialogActions(spacing: 8, children: [
                SecondaryButton(label: 'Name this version', height: 44, onPressed: ready && !naming ? onName : null),
                SecondaryButton(label: 'Save as a new page', height: 44, onPressed: ready ? onSaveAsPage : null),
                PrimaryButton(label: 'Restore this version', height: 44, onPressed: ready ? onRestore : null),
              ]),
            ],
          ),
        ),
      ]),
    );
  }
}

class _TextButton extends StatelessWidget {
  const _TextButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.key),
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.fill, required this.line, required this.label});

  final Color fill;
  final Color line;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
      DashedBorder(
        color: line,
        radius: 3,
        width: 1,
        child: Container(width: 14, height: 14, color: fill),
      ),
      Text(label, style: TextStyle(fontSize: 12, color: c.text)),
    ]);
  }
}

class _VersionList extends StatelessWidget {
  const _VersionList({
    required this.versions,
    required this.total,
    required this.picked,
    required this.keepDays,
    required this.summary,
    required this.onPick,
    required this.now,
  });

  final DateTime now;
  final List<PageVersion>? versions;
  final int total;
  final PageVersion? picked;
  final int keepDays;
  final String Function(PageVersion v) summary;
  final ValueChanged<PageVersion> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = <Widget>[];
    String? day;
    final vs = versions ?? const <PageVersion>[];
    for (final (i, v) in vs.indexed) {
      final d = dayWhen(v.at, now);
      if (d != day) {
        day = d;
        items.add(Padding(
          padding: EdgeInsets.fromLTRB(18, items.isEmpty ? 4 : 14, 18, 6),
          child: Text(d, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.text)),
        ));
      }
      final last = i == vs.length - 1 || dayWhen(vs[i + 1].at, now) != d;
      items.add(_VersionRow(
        version: v,
        time: clockText(v.at.toLocal(), seconds: false),
        summary: summary(v),
        selected: v.name == picked?.name,
        lineBelow: !last,
        onTap: () => onPick(v),
      ));
    }
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
          child: Row(children: [
            Expanded(
              child: Text(
                (total == 1 ? '1 version' : '$total versions').toUpperCase(),
                style: TypeScale.sectionLabel.copyWith(fontWeight: FontWeight.w700, color: c.textMuted),
              ),
            ),
            Text('Newest first', style: TextStyle(fontSize: 12, color: c.textMuted)),
          ]),
        ),
        Expanded(
          child: Semantics(
            container: true,
            label: 'Versions',
            explicitChildNodes: true,
            child: versions != null && versions!.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text('No named versions yet. Pick one and tap Name this version.',
                        style: TextStyle(fontSize: 14, color: c.textMuted)),
                  )
                : ListView(padding: const EdgeInsets.only(bottom: 12), children: items),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.lineSoft))),
          child: Text(
            'Named versions are kept until you delete them. Others are kept for $keepDays days. '
            'Change this in Settings › Notebooks & pages.',
            style: TextStyle(fontSize: 12, height: 1.4, color: c.textMuted),
          ),
        ),
      ]),
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({
    required this.version,
    required this.time,
    required this.summary,
    required this.selected,
    required this.lineBelow,
    required this.onTap,
  });

  final PageVersion version;
  final String time;
  final String summary;
  final bool selected;
  final bool lineBelow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final named = version.label != null;
    final dotColor = selected ? c.accent : (named ? c.gold : c.textFaint);
    return Semantics(
      button: true,
      selected: selected,
      label: '$time. This tablet. ${named ? 'Named ${version.label}. ' : ''}$summary',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Material(
          color: selected ? c.accentWash : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.button),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.button),
            onTap: onTap,
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(
                  width: 30,
                  child: Stack(alignment: Alignment.topCenter, children: [
                    if (lineBelow) Positioned(top: 20, bottom: -2, child: Container(width: 1.5, color: c.lineStrong)),
                    Positioned(
                      top: 13,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: selected ? c.accent : c.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: dotColor, width: 2),
                        ),
                      ),
                    ),
                  ]),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 10, 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, spacing: 8, children: [
                        Text(time, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
                        Text('This tablet', style: TextStyle(fontSize: 12, color: c.textMuted)),
                      ]),
                      if (named)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: c.stickyYellow, borderRadius: BorderRadius.circular(Radii.small)),
                          child: Row(mainAxisSize: MainAxisSize.min, spacing: 5, children: [
                            EIcon(EIcons.bookmark, size: 12, color: c.goldDeep),
                            Text(version.label!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.goldDeep)),
                          ]),
                        ),
                      Text(summary, style: TextStyle(fontSize: 13, color: c.text)),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A version's page fitted to the preview, with Show changes: what it added
/// (green, ADDED) and what's been erased since (clay, struck through,
/// ERASED LATER).
class _VersionPainter extends CustomPainter {
  _VersionPainter(this.page, this.brightness, this.colors, {this.added = const [], this.erased = const []});

  final PageRuntime page;
  final Brightness brightness;
  final EndlessColors colors;
  final List<Item> added;
  final List<Item> erased;

  @override
  void paint(Canvas canvas, Size size) {
    final content = page.contentBounds;
    if (content == null) return;
    final padded = content.inflate(math.max(content.width, content.height) * 0.06 + 24);
    final area = (Offset.zero & size).deflate(16);
    final scale = math.min(area.width / padded.width, area.height / padded.height);
    final dx = area.center.dx - padded.center.dx * scale, dy = area.center.dy - padded.center.dy * scale;
    Rect toScreen(Rect r) => Rect.fromLTRB(r.left * scale + dx, r.top * scale + dy, r.right * scale + dx, r.bottom * scale + dy);
    // Fills under the ink, outlines and tags over it.
    final addedBoxes = [for (final r in clustersOf(added)) toScreen(r).inflate(10)];
    final erasedBoxes = [for (final r in clustersOf(erased)) toScreen(r).inflate(10)];
    for (final (boxes, fill) in [(addedBoxes, colors.greenTint), (erasedBoxes, colors.clayTint)]) {
      for (final b in boxes) {
        canvas.drawRRect(RRect.fromRectAndRadius(b, const Radius.circular(10)), Paint()..color = fill.withValues(alpha: 0.8));
      }
    }
    canvas.save();
    canvas.clipRect(area);
    canvas.translate(dx, dy);
    canvas.scale(scale);
    canvas.drawPicture(page.fullPicture(brightness, colors));
    canvas.restore();
    for (final b in erasedBoxes) {
      canvas.drawLine(Offset(b.left + 12, b.center.dy), Offset(b.right - 12, b.center.dy),
          Paint()
            ..color = colors.text.withValues(alpha: 0.55)
            ..strokeWidth = 1.5);
    }
    for (final (boxes, line, tag) in [(addedBoxes, colors.green, 'ADDED'), (erasedBoxes, colors.clay, 'ERASED LATER')]) {
      for (final b in boxes) {
        paintDashedRRect(canvas, RRect.fromRectAndRadius(b, const Radius.circular(10)), line);
        paintTag(canvas, tag, Offset(b.right - 8, b.top), line, colors.onAccent);
      }
    }
  }

  @override
  bool shouldRepaint(_VersionPainter old) =>
      old.page != page || old.brightness != brightness || old.added != added || old.erased != erased;
}

/// A dashed rounded box (the highlights' outline).
void paintDashedRRect(Canvas canvas, RRect rr, Color color, {double width = 1.5}) {
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..color = color;
  for (final m in (Path()..addRRect(rr)).computeMetrics()) {
    for (var d = 0.0; d < m.length; d += 9) {
      canvas.drawPath(m.extractPath(d, d + 5), paint);
    }
  }
}

/// A small filled tag ("ADDED") whose top-right corner sits over [topRight]'s
/// line.
void paintTag(Canvas canvas, String text, Offset topRight, Color fill, Color ink) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontFamily: FontFamilies.ui, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: ink),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final r = Rect.fromLTWH(topRight.dx - tp.width - 16, topRight.dy - 9, tp.width + 16, 18);
  canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(999)), Paint()..color = fill);
  tp.paint(canvas, Offset(r.left + 8, r.top + (18 - tp.height) / 2));
  tp.dispose();
}

/// A version's page, for tests.
@visibleForTesting
BoardPage? previewOf(State s) => s is _VersionHistoryState ? s._preview?.page : null;
