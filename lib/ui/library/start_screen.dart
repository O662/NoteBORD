import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../library/library.dart';
import '../../state/settings.dart';
import '../../templates/templates.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../common.dart';
import '../dialogs.dart';
import '../icons.dart';
import '../routes.dart';
import '../transfer/transfer_dialog.dart';
import '../templates/templates_dialog.dart';
import 'format.dart';
import 'new_note_dialog.dart';
import 'new_notebook_dialog.dart';
import 'sidebar.dart';
import 'widgets.dart';
import '../shell.dart';

/// The Start page (design/screens/Start.png).
class StartScreen extends ConsumerWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final lib = ref.watch(libraryProvider);
    final now = ref.watch(clockProvider)();
    final name = ref.watch(settingsProvider.select((s) => s.userName))?.trim();
    final greeting = lib.notebooks.isEmpty
        ? 'Welcome to Endless'
        : (name == null || name.isEmpty ? 'Welcome back' : 'Welcome back, $name');
    final cont = lib.continueWriting;
    final collapsed = ref.watch(settingsProvider.select((s) => s.startCollapsed));

    return Scaffold(
      body: SafeArea(
        child: AppShell(children: [
          const AppSidebar(selected: SidebarItem.home),
          Expanded(
            child: Builder(builder: (context) {
              final narrow = context.narrow;
              // Collapsed, Recent gets the room the header had (StartCollapsed.png):
              // two rows instead of one; in portrait, two columns.
              final columns = narrow ? 2 : 4;
              final rows = narrow ? (collapsed ? 6 : 5) : (collapsed ? 2 : 1);
              return SingleChildScrollView(
                padding: narrow
                    ? const EdgeInsets.symmetric(horizontal: 24, vertical: 22)
                    : EdgeInsets.symmetric(horizontal: 40, vertical: collapsed ? 22 : 34),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: collapsed || narrow ? 22 : 28, children: [
                  if (collapsed)
                    _SlimHeader(greeting: narrow ? _short(greeting, name) : greeting, narrow: narrow)
                  else ...[
                    Row(crossAxisAlignment: CrossAxisAlignment.end, spacing: 12, children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
                          Text(longDate(now), style: TextStyle(fontSize: 14, color: c.textMuted)),
                          Semantics(
                            header: true,
                            child: Text(
                              greeting,
                              style: TextStyle(
                                fontFamily: FontFamilies.serif,
                                fontSize: narrow ? 40 : 46,
                                letterSpacing: narrow ? -0.8 : -0.92,
                                height: 1.05,
                                color: c.text,
                              ),
                            ),
                          ),
                        ]),
                      ),
                      _CollapseButton(narrow: narrow),
                    ]),
                    _Actions(narrow: narrow),
                  ],
                  if (narrow) ...[
                    _ContinueCard(entry: cont, narrow: true),
                    if (lib.pinned.isNotEmpty) _PinnedRow(pinned: lib.pinned),
                  ] else
                    IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
                        Expanded(flex: 2, child: _ContinueCard(entry: cont)),
                        Expanded(child: _PinnedCard(pinned: lib.pinned)),
                      ]),
                    ),
                  _Recent(entries: lib.recent(except: cont?.id, count: columns * rows), columns: columns),
                ]),
              );
            }),
          ),
        ]),
      ),
    );
  }

  /// Portrait's slim bar says "Hi, Kieth".
  static String _short(String greeting, String? name) =>
      name == null || name.isEmpty || !greeting.startsWith('Welcome back') ? greeting : 'Hi, $name';
}

/// Folds the greeting and tiles into the slim bar, or opens them again.
void _toggleHeader(WidgetRef ref) =>
    ref.read(settingsProvider.notifier).apply((s) => s.withPref('startCollapsed', !s.startCollapsed));

class _CollapseButton extends ConsumerWidget {
  const _CollapseButton({required this.narrow});

  final bool narrow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Semantics(
      button: true,
      expanded: true,
      label: 'Collapse the header',
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(side: BorderSide(color: c.line), borderRadius: BorderRadius.circular(Radii.button)),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.button),
          onTap: () => _toggleHeader(ref),
          child: Container(
            height: narrow ? 48 : 44,
            width: narrow ? 48 : null,
            padding: EdgeInsets.symmetric(horizontal: narrow ? 0 : 12),
            alignment: Alignment.center,
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
              EIcon(EIcons.chevronUp, size: narrow ? 20 : 18, color: c.textMuted),
              if (!narrow) Text('Collapse', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.textMuted)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The header folded down (StartCollapsed.png): the greeting, New note,
/// Notebook, the Template, Import and Scan icons, and the expand chevron.
class _SlimHeader extends ConsumerWidget {
  const _SlimHeader({required this.greeting, required this.narrow});

  final String greeting;
  final bool narrow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    Widget icon(String label, EIconData i, Color tint, VoidCallback onTap) =>
        ChromeButton(label: label, icon: i, foreground: tint, radius: 11, onPressed: onTap);
    return Container(
      padding: EdgeInsets.fromLTRB(narrow ? 14 : 16, 6, 6, 6),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(spacing: narrow ? 6 : 8, children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              greeting,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: FontFamilies.serif, fontSize: narrow ? 20 : 22, color: c.text),
            ),
          ),
        ),
        PrimaryButton(label: 'New note', icon: EIcons.plus, height: 44, onPressed: () => newNote(context, ref)),
        if (narrow)
          icon('New notebook', EIcons.notebook, c.accent, () => newNotebook(context, ref))
        else
          Semantics(
            button: true,
            label: 'New notebook',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(11),
              onTap: () => newNotebook(context, ref),
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
                  EIcon(EIcons.notebook, size: 18, color: c.accent),
                  Text('Notebook', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
                ]),
              ),
            ),
          ),
        icon('From a template', EIcons.templates, c.plum, () => showTemplatesDialog(context, target: TemplateTarget.newNotebook)),
        icon('Import PDF or file', EIcons.download, c.clay, () => showTransferDialog(context, mode: TransferMode.import)),
        if (!narrow) ...[
          icon('Scan paper notes', EIcons.scan, c.green, () => showComingSoon(context, 'Scanning paper notes')),
          Container(width: 1, height: 28, margin: const EdgeInsets.symmetric(horizontal: 2), color: c.lineSoft),
        ],
        ChromeButton(
          label: 'Expand the header',
          icon: EIcons.chevronDown,
          iconSize: 18,
          radius: 11,
          expanded: false,
          background: c.side,
          foreground: c.textMuted,
          onPressed: () => _toggleHeader(ref),
        ),
      ]),
    );
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({required this.narrow});

  /// Portrait: still 5 across, shorter, with short labels (StartPortrait.png).
  final bool narrow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    Widget card(String label, String short, EIconData icon, Color tint, VoidCallback onTap, {bool dark = false}) => Expanded(
          child: _ActionCard(
            label: narrow ? short : label,
            said: label,
            icon: icon,
            iconColor: tint,
            dark: dark,
            compact: narrow,
            onTap: onTap,
          ),
        );
    return Row(spacing: narrow ? 10 : 12, children: [
      card('New note', 'New note', EIcons.plus, c.onInverse, () => newNote(context, ref), dark: true),
      card('New notebook', 'Notebook', EIcons.notebook, c.accent, () => newNotebook(context, ref)),
      card('From a template', 'Template', EIcons.templates, c.plum,
          () => showTemplatesDialog(context, target: TemplateTarget.newNotebook)),
      card('Import PDF or file', 'Import', EIcons.download, c.clay, () => showTransferDialog(context, mode: TransferMode.import)),
      card('Scan paper notes', 'Scan', EIcons.scan, c.green, () => showComingSoon(context, 'Scanning paper notes')),
    ]);
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.onTap,
    this.dark = false,
    this.compact = false,
    this.said,
  });

  final String label;
  final EIconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  final bool dark;

  /// 92 dp tall, smaller type (portrait).
  final bool compact;

  /// What it says aloud, when [label] is shortened.
  final String? said;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: said ?? label,
      excludeSemantics: true,
      child: Material(
        color: dark ? c.inverse : c.surface,
        shape: RoundedRectangleBorder(
          side: dark ? BorderSide.none : BorderSide(color: c.line),
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.pill),
          onTap: onTap,
          child: Container(
            constraints: BoxConstraints(minHeight: compact ? 92 : 100),
            padding: EdgeInsets.all(compact ? 14 : 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              EIcon(icon, size: compact ? 22 : 24, color: iconColor),
              SizedBox(height: compact ? 10 : 12),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: compact ? 15 : 16, fontWeight: FontWeight.w600, color: dark ? c.onInverse : c.text),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.label, required this.child, this.padding = const EdgeInsets.all(16)});

  final String label;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      label: label,
      explicitChildNodes: true,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(18),
        ),
        child: child,
      ),
    );
  }
}

class _ContinueCard extends ConsumerWidget {
  const _ContinueCard({required this.entry, this.narrow = false});

  final NotebookEntry? entry;

  /// Portrait: a 250×176 preview (StartPortrait.png).
  final bool narrow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final e = entry;
    final now = ref.watch(clockProvider)();
    if (e == null) {
      return _Card(
        label: 'Continue writing',
        child: SizedBox(
          height: 212,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
            const SectionLabel('Continue writing'),
            Text('Nothing here yet', style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 28, color: c.text)),
            Text(
              'Start with a new note. Every page grows as you write.',
              style: TextStyle(fontSize: 14, color: c.textMuted),
            ),
            const Spacer(),
            PrimaryButton(label: 'New note', icon: EIcons.plus, height: 46, onPressed: () => newNote(context, ref)),
          ]),
        ),
      );
    }
    final lib = ref.read(libraryProvider);
    final page = e.lastPage.clamp(0, e.pageCount - 1);
    final coverH = narrow ? 176.0 : 212.0;
    return _Card(
      label: 'Continue writing',
      padding: EdgeInsets.all(narrow ? 14 : 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: narrow ? 18 : 20, children: [
        NotebookCover(
          entry: e,
          color: lib.coverOf(e),
          width: narrow ? 250 : 300,
          height: coverH,
          spine: 0,
          dotSpacing: 16,
          shadow: false,
          background: c.bg,
          inkScale: 0.45,
          inkPadding: 18,
        ),
        Expanded(
          // At least as tall as the preview; taller with large text.
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: coverH),
            child: IntrinsicHeight(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
              const Padding(padding: EdgeInsets.only(top: 4), child: SectionLabel('Continue writing')),
              Text(
                e.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: FontFamilies.serif, fontSize: narrow ? 24 : 28, height: 1.1, color: c.text),
              ),
              Text(
                [
                  'Page ${page + 1} of ${e.pageCount} · edited ${agoPhrase(e.updatedAt, now)}',
                  if (e.folder.isNotEmpty && !narrow) folderLabel(e.folder),
                ].join('\n'),
                style: TextStyle(fontSize: 14, height: 1.4, color: c.textMuted),
              ),
              const Spacer(),
              Wrap(spacing: 8, runSpacing: 8, children: [
                PrimaryButton(label: 'Open', height: 46, onPressed: () => openNotebook(context, ref, e.id)),
                SecondaryButton(
                  label: 'Split view',
                  icon: EIcons.split,
                  height: 46,
                  onPressed: () {
                    final other = lib.recent(except: e.id, count: 1).firstOrNull;
                    context.push(Routes.split(
                      (e.id, page),
                      other == null ? (e.id, (page + 1) % e.pageCount) : (other.id, other.lastPage),
                    ));
                  },
                ),
              ]),
            ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _PinnedCard extends ConsumerWidget {
  const _PinnedCard({required this.pinned});

  final List<NotebookEntry> pinned;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final lib = ref.read(libraryProvider);
    return _Card(
      label: 'Pinned',
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
        const Padding(padding: EdgeInsets.fromLTRB(8, 0, 8, 6), child: SectionLabel('Pinned')),
        if (pinned.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Long-press a notebook in the library and choose “Pin to Start” to keep it here.',
              style: TextStyle(fontSize: 13, height: 1.4, color: c.textMuted),
            ),
          ),
        for (final n in pinned.take(4))
          Semantics(
            button: true,
            label: n.title,
            excludeSemantics: true,
            child: ContextTarget(
              onMenu: (at) => showNotebookMenu(context, ref, n, at),
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.key),
                onTap: () => openNotebook(context, ref, n.id),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 56),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(spacing: 12, children: [
                    Container(
                      width: 8,
                      height: 32,
                      decoration: BoxDecoration(
                        color: displayInk(lib.coverOf(n), Theme.of(context).brightness),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, spacing: 1, children: [
                        Text(
                          n.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text),
                        ),
                        Text(
                          [if (n.folder.isNotEmpty) folderLabel(n.folder), pagesLabel(n.pageCount)].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: c.textMuted),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Portrait's Pinned: a row of 3 (StartPortrait.png).
class _PinnedRow extends ConsumerWidget {
  const _PinnedRow({required this.pinned});

  final List<NotebookEntry> pinned;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final lib = ref.read(libraryProvider);
    final shown = pinned.take(3).toList();
    return Semantics(
      container: true,
      label: 'Pinned',
      explicitChildNodes: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        const SectionLabel('Pinned'),
        Row(spacing: 10, children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              child: i >= shown.length
                  ? const SizedBox()
                  : Semantics(
                      button: true,
                      label: shown[i].title,
                      excludeSemantics: true,
                      child: ContextTarget(
                        onMenu: (at) => showNotebookMenu(context, ref, shown[i], at),
                        child: Material(
                          color: c.surface,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(color: c.line),
                            borderRadius: BorderRadius.circular(Radii.card),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(Radii.card),
                            onTap: () => openNotebook(context, ref, shown[i].id),
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 60),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Row(spacing: 10, children: [
                                Container(
                                  width: 6,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: displayInk(lib.coverOf(shown[i]), Theme.of(context).brightness),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                                    Text(
                                      shown[i].title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text),
                                    ),
                                    Text(
                                      pagesLabel(shown[i].pageCount),
                                      maxLines: 1,
                                      style: TextStyle(fontSize: 12, color: c.textMuted),
                                    ),
                                  ]),
                                ),
                              ]),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
        ]),
      ]),
    );
  }
}

class _Recent extends ConsumerWidget {
  const _Recent({required this.entries, this.columns = 4});

  final List<NotebookEntry> entries;

  /// Cards across; as many rows as [entries] fill.
  final int columns;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final lib = ref.read(libraryProvider);
    final now = ref.watch(clockProvider)();
    return Semantics(
      container: true,
      label: 'Recent',
      explicitChildNodes: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        Row(children: [
          const Expanded(child: SectionLabel('Recent')),
          Semantics(
            link: true,
            label: 'See all notebooks',
            excludeSemantics: true,
            child: InkWell(
              onTap: () => context.go(Routes.all),
              child: SizedBox(
                height: 36,
                child: Center(
                  child: Text('See all notebooks', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.accent)),
                ),
              ),
            ),
          ),
        ]),
        if (entries.isEmpty)
          Text('Notebooks you edit show up here.', style: TextStyle(fontSize: 14, color: c.textMuted))
        else
          for (var row = 0; row * columns < entries.length; row++)
            Row(spacing: 16, children: [
              for (var i = row * columns; i < (row + 1) * columns; i++)
                Expanded(
                  child: i < entries.length
                      ? _RecentCard(
                          entry: entries[i],
                          color: lib.coverOf(entries[i]),
                          meta: [
                            dayWhen(entries[i].updatedAt, now),
                            if (entries[i].folder.isNotEmpty) entries[i].folder.last,
                          ].join(' · '),
                        )
                      : const SizedBox(),
                ),
            ]),
      ]),
    );
  }
}

class _RecentCard extends ConsumerWidget {
  const _RecentCard({required this.entry, required this.color, required this.meta});

  final NotebookEntry entry;
  final Color color;
  final String meta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: '${entry.title}, $meta',
      excludeSemantics: true,
      child: ContextTarget(
        onMenu: (at) => showNotebookMenu(context, ref, entry, at),
        child: Material(
          color: c.surface,
          shape: RoundedRectangleBorder(side: BorderSide(color: c.line), borderRadius: BorderRadius.circular(Radii.card)),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.card),
            onTap: () => openNotebook(context, ref, entry.id),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(spacing: 12, children: [
                NotebookCover(
                  entry: entry,
                  color: color,
                  width: 64,
                  height: 64,
                  spine: 6,
                  dotSpacing: 10,
                  radius: Radii.small,
                  shadow: false,
                  showInk: false,
                  background: c.bg,
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text),
                    ),
                    Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.textMuted)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
