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
import 'start_screen.dart' show newNote;
import 'widgets.dart';

const _sortLabels = {
  LibrarySort.edited: 'Last edited',
  LibrarySort.title: 'Title',
  LibrarySort.created: 'Date created',
};

/// The library: a folder (design/screens/Main.png), All notebooks, or Trash.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key, this.folder = const [], this.trash = false});

  /// The folder shown; `[]` is All notebooks.
  final List<String> folder;
  final bool trash;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final lib = ref.watch(libraryProvider);
    final settings = ref.watch(settingsProvider);
    final now = ref.watch(clockProvider)();
    final inFolder = folder.isNotEmpty;
    final exists = !inFolder || lib.folder(folder) != null;

    final List<NotebookEntry> notebooks;
    if (trash) {
      notebooks = lib.trash;
    } else {
      notebooks = [...(inFolder ? lib.notebooksIn(folder) : lib.active)];
      switch (settings.librarySort) {
        case LibrarySort.edited:
          notebooks.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        case LibrarySort.title:
          notebooks.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        case LibrarySort.created:
          notebooks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }
    }

    String meta(NotebookEntry n) {
      if (trash) return 'Deleted ${dayWhen(n.trashedAt!, now).toLowerCase()}';
      return [
        pagesLabel(n.pageCount),
        shortWhen(n.updatedAt, now),
        if (!inFolder && n.folder.isNotEmpty) n.folder.last,
      ].join(' · ');
    }

    final title = trash ? 'Trash' : (inFolder ? folder.last : 'All notebooks');
    return Scaffold(
      body: SafeArea(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppSidebar(
            selected: trash ? SidebarItem.trash : (inFolder ? null : SidebarItem.all),
            folder: inFolder ? folder : null,
            folderTree: true,
          ),
          Expanded(
            child: CustomScrollView(slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(40, 30, 40, 0),
                sliver: SliverToBoxAdapter(
                  child: _Header(folder: folder, trash: trash, title: title, emptyTrash: lib.trash.isNotEmpty),
                ),
              ),
              if (!exists)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text('This folder no longer exists.', style: TextStyle(fontSize: 15, color: c.textMuted)),
                  ),
                )
              else ...[
                if (inFolder)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(40, 26, 40, 0),
                    sliver: SliverToBoxAdapter(child: _Folders(parent: folder)),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(40, 26, 40, 14),
                  sliver: SliverToBoxAdapter(
                    child: Row(children: [
                      Expanded(child: SectionLabel(trash ? 'In the Trash' : 'Notebooks')),
                      if (trash)
                        Text(
                          'Deleted after 30 days',
                          style: TextStyle(fontSize: 14, color: c.textMuted),
                        )
                      else
                        const _SortButton(),
                    ]),
                  ),
                ),
                if (notebooks.isEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    sliver: SliverToBoxAdapter(child: _Empty(trash: trash, folder: folder)),
                  )
                else if (settings.libraryView == LibraryView.grid || trash)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(40, 0, 40, 40),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 20,
                        mainAxisSpacing: 22,
                        mainAxisExtent: 206,
                      ),
                      delegate: SliverChildListDelegate([
                        for (final n in notebooks) _NotebookCard(entry: n, meta: meta(n)),
                      ]),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(40, 0, 40, 40),
                    sliver: SliverList.separated(
                      itemCount: notebooks.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => _NotebookRow(entry: notebooks[i], meta: meta(notebooks[i])),
                    ),
                  ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.folder, required this.trash, required this.title, required this.emptyTrash});

  final List<String> folder;
  final bool trash;
  final String title;
  final bool emptyTrash;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final view = ref.watch(settingsProvider.select((s) => s.libraryView));
    final crumbs = trash ? 'Library' : (folder.isEmpty ? 'Library' : 'Folders');
    return Row(crossAxisAlignment: CrossAxisAlignment.end, spacing: 24, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
          // "Folders › School › Physics": each part opens that folder.
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(crumbs, style: TextStyle(fontSize: 13, color: c.textMuted)),
            for (var i = 0; i < folder.length; i++) ...[
              Text(' › ', style: TextStyle(fontSize: 13, color: c.textMuted)),
              if (i == folder.length - 1)
                Text(folder[i], style: TextStyle(fontSize: 13, color: c.textMuted))
              else
                Semantics(
                  link: true,
                  label: folder[i],
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: () => context.go(Routes.library(folder.sublist(0, i + 1))),
                    child: Text(folder[i], style: TextStyle(fontSize: 13, color: c.accent)),
                  ),
                ),
            ],
          ]),
          Semantics(
            header: true,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 46, letterSpacing: -0.92, height: 1.05, color: c.text),
            ),
          ),
        ]),
      ),
      if (trash)
        SecondaryButton(
          label: 'Empty trash',
          icon: EIcons.trash,
          height: 46,
          filled: true,
          onPressed: !emptyTrash
              ? null
              : () async {
                  final ok = await showConfirm(
                    context,
                    title: 'Empty the Trash?',
                    message: 'Everything in the Trash will be deleted from this tablet. This can’t be undone.',
                    action: 'Empty trash',
                  );
                  if (ok) await ref.read(libraryProvider.notifier).emptyTrash();
                },
        )
      else ...[
        _ViewToggle(view: view),
        SecondaryButton(
          label: 'Import',
          icon: EIcons.download,
          height: 46,
          filled: true,
          onPressed: () => showComingSoon(context, 'Importing PDFs and files'),
        ),
        SecondaryButton(
          label: 'New notebook',
          icon: EIcons.notebook,
          height: 46,
          filled: true,
          onPressed: () => showTemplatesDialog(context, target: TemplateTarget.newNotebook, initial: 'dots', folder: folder),
        ),
        PrimaryButton(label: 'New note', icon: EIcons.plus, height: 46, onPressed: () => newNote(context, ref, folder: folder)),
      ],
    ]);
  }
}

class _ViewToggle extends ConsumerWidget {
  const _ViewToggle({required this.view});

  final LibraryView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    Widget button(LibraryView v, String label, EIconData icon) {
      final on = view == v;
      return Semantics(
        button: true,
        toggled: on,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: () => ref.read(settingsProvider.notifier).apply((s) => s.copyWith(libraryView: v)),
          child: Container(
            width: 44,
            height: 40,
            decoration: BoxDecoration(
              color: on ? c.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              boxShadow: on ? [BoxShadow(color: c.shadow.withValues(alpha: 0.12), blurRadius: 2, offset: const Offset(0, 1))] : null,
            ),
            child: Center(child: EIcon(icon, size: 18, color: on ? c.text : c.textMuted)),
          ),
        ),
      );
    }

    return Semantics(
      label: 'View',
      container: true,
      explicitChildNodes: true,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: c.side, borderRadius: BorderRadius.circular(Radii.button)),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 2, children: [
          button(LibraryView.grid, 'Grid view', EIcons.gridView),
          button(LibraryView.list, 'List view', EIcons.listView),
        ]),
      ),
    );
  }
}

class _SortButton extends ConsumerWidget {
  const _SortButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final sort = ref.watch(settingsProvider.select((s) => s.librarySort));
    return PopupMenuButton<LibrarySort>(
      tooltip: '',
      initialValue: sort,
      color: c.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.pill), side: BorderSide(color: c.line)),
      onSelected: (s) => ref.read(settingsProvider.notifier).apply((st) => st.copyWith(librarySort: s)),
      itemBuilder: (context) => [
        for (final s in LibrarySort.values)
          PopupMenuItem(
            value: s,
            height: 44,
            child: Text(_sortLabels[s]!, style: TextStyle(fontSize: 15, fontWeight: s == sort ? FontWeight.w600 : FontWeight.w400, color: c.text)),
          ),
      ],
      child: Semantics(
        button: true,
        label: 'Sort by ${_sortLabels[sort]}',
        excludeSemantics: true,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
            Text(_sortLabels[sort]!, style: TextStyle(fontSize: 14, color: c.textMuted)),
            EIcon(EIcons.chevronDown, size: 16, color: c.textMuted),
          ]),
        ),
      ),
    );
  }
}

class _Folders extends ConsumerWidget {
  const _Folders({required this.parent});

  final List<String> parent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final lib = ref.watch(libraryProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      const SectionLabel('Folders'),
      Wrap(spacing: 14, runSpacing: 14, children: [
        for (final f in lib.childrenOf(parent))
          Semantics(
            button: true,
            label: 'Folder ${f.name}, ${notebooksLabel(lib.countUnder(f.path))}',
            excludeSemantics: true,
            child: ContextTarget(
              onMenu: (at) => showFolderMenu(context, ref, f, at),
              child: Material(
                color: c.surface,
                shape: RoundedRectangleBorder(side: BorderSide(color: c.line), borderRadius: BorderRadius.circular(Radii.card)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(Radii.card),
                  onTap: () => context.go(Routes.library(f.path)),
                  child: Container(
                    width: 214,
                    height: 68,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(spacing: 12, children: [
                      FolderIcon(color: f.color, size: 28, fillOpacity: 0.14),
                      Expanded(
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                          Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                          Text(notebooksLabel(lib.countUnder(f.path)), style: TextStyle(fontSize: 13, color: c.textMuted)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        Semantics(
          button: true,
          label: 'New folder',
          excludeSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.card),
            onTap: () => createFolderFlow(context, ref, parent),
            child: DashedBorder(
              color: c.lineDashed,
              radius: Radii.card,
              child: SizedBox(
                width: 214,
                height: 68,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 10, children: [
                  EIcon(EIcons.plus, size: 18, color: c.textMuted),
                  Text('New folder', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.textMuted)),
                ]),
              ),
            ),
          ),
        ),
      ]),
    ]);
  }
}

void _open(BuildContext context, WidgetRef ref, NotebookEntry n, Offset at) {
  if (n.trashed) {
    showNotebookMenu(context, ref, n, at);
  } else {
    openNotebook(context, ref, n.id);
  }
}

class _NotebookCard extends ConsumerWidget {
  const _NotebookCard({required this.entry, required this.meta});

  final NotebookEntry entry;
  final String meta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final lib = ref.watch(libraryProvider);
    return Semantics(
      button: true,
      label: '${entry.title}${entry.locked ? ', locked' : ''}, $meta',
      onLongPressHint: 'Notebook options',
      excludeSemantics: true,
      child: ContextTarget(
        onMenu: (at) => showNotebookMenu(context, ref, entry, at),
        child: GestureDetector(
          onTapUp: (d) => _open(context, ref, entry, d.globalPosition),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
            NotebookCover(entry: entry, color: lib.coverOf(entry)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
                Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.textMuted)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _NotebookRow extends ConsumerWidget {
  const _NotebookRow({required this.entry, required this.meta});

  final NotebookEntry entry;
  final String meta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final lib = ref.watch(libraryProvider);
    return Semantics(
      button: true,
      label: '${entry.title}${entry.locked ? ', locked' : ''}, $meta',
      excludeSemantics: true,
      child: ContextTarget(
        onMenu: (at) => showNotebookMenu(context, ref, entry, at),
        child: Material(
          color: c.surface,
          shape: RoundedRectangleBorder(side: BorderSide(color: c.line), borderRadius: BorderRadius.circular(Radii.card)),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.card),
            onTapUp: (d) => _open(context, ref, entry, d.globalPosition),
            onTap: () {},
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(spacing: 14, children: [
                NotebookCover(
                  entry: entry,
                  color: lib.coverOf(entry),
                  width: 72,
                  height: 56,
                  spine: 6,
                  dotSpacing: 10,
                  radius: Radii.small,
                  shadow: false,
                  inkScale: 0.12,
                  inkPadding: 6,
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
                    Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                    Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.textMuted)),
                  ]),
                ),
                if (entry.pinned) EIcon(EIcons.pin, size: 18, color: c.textMuted),
                if (entry.locked) EIcon(EIcons.lock, size: 18, color: c.textMuted),
                Builder(
                  builder: (context) => ChromeButton(
                    label: 'Options for ${entry.title}',
                    icon: EIcons.more,
                    onPressed: () => showNotebookMenu(context, ref, entry, menuAnchor(context)),
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

class _Empty extends ConsumerWidget {
  const _Empty({required this.trash, required this.folder});

  final bool trash;
  final List<String> folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(spacing: 14, children: [
        Text(
          trash ? 'The Trash is empty' : 'No notebooks here yet',
          style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 28, color: c.text),
        ),
        Text(
          trash
              ? 'Notebooks you delete stay here for 30 days.'
              : 'Start with a new note. Long-press any notebook for more options.',
          style: TextStyle(fontSize: 15, color: c.textMuted),
        ),
        if (!trash) PrimaryButton(label: 'New note', icon: EIcons.plus, height: 46, onPressed: () => newNote(context, ref, folder: folder)),
      ]),
    );
  }
}
