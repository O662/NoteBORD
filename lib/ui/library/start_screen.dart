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
import '../templates/templates_dialog.dart';
import 'format.dart';
import 'sidebar.dart';
import 'widgets.dart';

/// Creates a notebook in [folder] and opens it on its first page.
Future<void> newNote(BuildContext context, WidgetRef ref, {List<String> folder = const []}) async {
  final id = await ref.read(libraryProvider.notifier).createNotebook(title: 'Untitled note', folder: folder);
  if (context.mounted) context.push(Routes.notebook(id, page: 0));
}

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

    return Scaffold(
      body: SafeArea(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const AppSidebar(selected: SidebarItem.home),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 34),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 28, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
                  Text(longDate(now), style: TextStyle(fontSize: 14, color: c.textMuted)),
                  Semantics(
                    header: true,
                    child: Text(
                      greeting,
                      style: TextStyle(
                        fontFamily: FontFamilies.serif,
                        fontSize: 46,
                        letterSpacing: -0.92,
                        height: 1.05,
                        color: c.text,
                      ),
                    ),
                  ),
                ]),
                _Actions(),
                IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
                    Expanded(flex: 2, child: _ContinueCard(entry: cont)),
                    Expanded(child: _PinnedCard(pinned: lib.pinned)),
                  ]),
                ),
                _Recent(entries: lib.recent(except: cont?.id)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Actions extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Row(spacing: 12, children: [
      Expanded(
        child: _ActionCard(
          label: 'New note',
          icon: EIcons.plus,
          iconColor: c.onInverse,
          dark: true,
          onTap: () => newNote(context, ref),
        ),
      ),
      Expanded(
        child: _ActionCard(
          label: 'New notebook',
          icon: EIcons.notebook,
          iconColor: c.accent,
          onTap: () => showTemplatesDialog(context, target: TemplateTarget.newNotebook, initial: 'dots'),
        ),
      ),
      Expanded(
        child: _ActionCard(
          label: 'From a template',
          icon: EIcons.templates,
          iconColor: c.plum,
          onTap: () => showTemplatesDialog(context, target: TemplateTarget.newNotebook),
        ),
      ),
      Expanded(
        child: _ActionCard(
          label: 'Import PDF or file',
          icon: EIcons.download,
          iconColor: c.clay,
          onTap: () => showComingSoon(context, 'Importing PDFs and files'),
        ),
      ),
      Expanded(
        child: _ActionCard(
          label: 'Scan paper notes',
          icon: EIcons.scan,
          iconColor: c.green,
          onTap: () => showComingSoon(context, 'Scanning paper notes'),
        ),
      ),
    ]);
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.label, required this.icon, required this.iconColor, required this.onTap, this.dark = false});

  final String label;
  final EIconData icon;
  final Color iconColor;
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
          side: dark ? BorderSide.none : BorderSide(color: c.line),
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.pill),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 100),
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              EIcon(icon, size: 24, color: iconColor),
              const SizedBox(height: 12),
              Text(
                label,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: dark ? c.onInverse : c.text),
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
  const _ContinueCard({required this.entry});

  final NotebookEntry? entry;

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
    return _Card(
      label: 'Continue writing',
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 20, children: [
        NotebookCover(
          entry: e,
          color: lib.coverOf(e),
          width: 300,
          height: 212,
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
            constraints: const BoxConstraints(minHeight: 212),
            child: IntrinsicHeight(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
              const Padding(padding: EdgeInsets.only(top: 4), child: SectionLabel('Continue writing')),
              Text(
                e.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 28, height: 1.1, color: c.text),
              ),
              Text(
                [
                  'Page ${page + 1} of ${e.pageCount} · edited ${agoPhrase(e.updatedAt, now)}',
                  if (e.folder.isNotEmpty) folderLabel(e.folder),
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

class _Recent extends ConsumerWidget {
  const _Recent({required this.entries});

  final List<NotebookEntry> entries;

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
          Row(spacing: 16, children: [
            for (var i = 0; i < 4; i++)
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
