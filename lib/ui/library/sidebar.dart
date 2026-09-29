import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../library/library.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../canvas/top_bar.dart' show showQuickSettings;
import '../common.dart';
import '../icons.dart';
import '../routes.dart';
import 'widgets.dart';

enum SidebarItem { home, all, trash }

/// Folders expanded in the sidebar tree (kept while moving between screens).
final expandedFoldersProvider = NotifierProvider<ExpandedFolders, Set<String>>(ExpandedFolders.new);

class ExpandedFolders extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void toggle(String key) => state = state.contains(key) ? ({...state}..remove(key)) : {...state, key};
}

/// The app sidebar (Start.dc.html and Main.dc.html `nav`): logo, search,
/// Home · All notebooks · Calendar · Flashcards · Remember · Trash, folders,
/// and the save status with Settings.
class AppSidebar extends ConsumerWidget {
  const AppSidebar({super.key, this.selected, this.folder, this.folderTree = false});

  final SidebarItem? selected;

  /// The folder shown, highlighted in the tree.
  final List<String>? folder;

  /// Library style: nested folders with chevrons and a "New folder" button.
  /// The Start page lists top-level folders only.
  final bool folderTree;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final lib = ref.watch(libraryProvider);
    final current = folder;
    // The open folder's parents are always expanded, so it shows.
    final expanded = {
      ...ref.watch(expandedFoldersProvider),
      if (current != null)
        for (var i = 1; i < current.length; i++) folderKey(current.sublist(0, i)),
    };

    List<Widget> tree(List<String> parent) => [
          for (final f in lib.childrenOf(parent)) ...[
            _FolderRow(
              folder: f,
              selected: current != null && listEquals(current, f.path),
              tree: folderTree,
              hasChildren: folderTree && lib.childrenOf(f.path).isNotEmpty,
              expanded: expanded.contains(f.key),
            ),
            if (folderTree && expanded.contains(f.key)) ...tree(f.path),
          ],
        ];

    return Semantics(
      container: true,
      label: 'Library',
      explicitChildNodes: true,
      child: Container(
        width: 272,
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: folderTree ? 20 : 22),
        decoration: BoxDecoration(color: c.side, border: Border(right: BorderSide(color: c.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: folderTree ? 14 : 18, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(spacing: 10, children: [
              EIcon(EIcons.logo, size: 30, color: c.text),
              Text(
                'Endless',
                style: TextStyle(
                  fontFamily: FontFamilies.serif,
                  fontSize: 26,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.26,
                  color: c.text,
                ),
              ),
            ]),
          ),
          _SearchBox(onTap: () => showComingSoon(context, 'Handwriting search')),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 2, children: [
            _NavRow(
              icon: EIcons.home,
              label: 'Home',
              selected: selected == SidebarItem.home,
              onTap: () => context.go(Routes.start),
            ),
            _NavRow(
              icon: EIcons.notebook,
              label: 'All notebooks',
              selected: selected == SidebarItem.all,
              count: '${lib.active.length}',
              onTap: () => context.go(Routes.all),
            ),
            _NavRow(icon: EIcons.calendar, label: 'Calendar', onTap: () => showComingSoon(context, 'The calendar')),
            _NavRow(icon: EIcons.flashcards, label: 'Flashcards', onTap: () => showComingSoon(context, 'Flashcards')),
            _NavRow(icon: EIcons.star, label: 'Remember', onTap: () => showComingSoon(context, 'Need to remember')),
            _NavRow(
              icon: EIcons.trash,
              label: 'Trash',
              selected: selected == SidebarItem.trash,
              count: lib.trash.isEmpty ? null : '${lib.trash.length}',
              onTap: () => context.go(Routes.trash),
            ),
          ]),
          Expanded(
            child: ListView(padding: EdgeInsets.zero, children: [
              if (folderTree)
                Padding(
                  padding: const EdgeInsets.only(left: 12, right: 4),
                  child: Row(children: [
                    const Expanded(child: SectionLabel('Folders')),
                    ChromeButton(
                      label: 'New folder',
                      icon: EIcons.plus,
                      radius: Radii.key,
                      onPressed: () => createFolderFlow(context, ref, const []),
                    ),
                  ]),
                )
              else
                const Padding(padding: EdgeInsets.fromLTRB(12, 0, 12, 6), child: SectionLabel('Folders')),
              ...tree(const []),
            ]),
          ),
          Row(spacing: 8, children: [
            Expanded(child: _SaveCard(onTap: () => showComingSoon(context, 'Cloud sync'))),
            ChromeButton(
              label: 'Settings',
              icon: EIcons.gear,
              iconSize: 22,
              width: 52,
              height: 52,
              onPressed: () => showQuickSettings(context),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'Search notes & handwriting',
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: c.line),
          borderRadius: BorderRadius.circular(Radii.button),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.button),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 46),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(spacing: 10, children: [
              EIcon(EIcons.search, color: c.textMuted),
              Expanded(
                child: Text('Search notes & handwriting', style: TextStyle(fontSize: 15, color: c.textMuted)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.icon, required this.label, required this.onTap, this.selected = false, this.count});

  final EIconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  /// Shown on the right (All notebooks, Trash).
  final String? count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      value: count,
      excludeSemantics: true,
      child: Material(
        color: selected ? c.sideSelected : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.key),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.key),
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(spacing: 12, children: [
              EIcon(icon, color: c.text),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 15, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: c.text),
                ),
              ),
              if (count != null) Text(count!, style: TextStyle(fontSize: 13, color: c.textMuted)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _FolderRow extends ConsumerWidget {
  const _FolderRow({
    required this.folder,
    required this.selected,
    required this.tree,
    required this.hasChildren,
    required this.expanded,
  });

  final FolderEntry folder;
  final bool selected;
  final bool tree;
  final bool hasChildren;
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final indent = (folder.path.length - 1) * 20.0;
    return Semantics(
      button: true,
      selected: selected,
      expanded: hasChildren ? expanded : null,
      label: 'Folder ${folder.name}',
      excludeSemantics: true,
      child: ContextTarget(
        onMenu: (at) => showFolderMenu(context, ref, folder, at),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Material(
            color: selected ? c.sideSelected : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.key),
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.key),
              onTap: () => context.go(Routes.library(folder.path)),
              child: Container(
                height: 44,
                padding: EdgeInsets.only(left: 12 + indent, right: 12),
                child: Row(spacing: tree ? 10 : 12, children: [
                  if (tree)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: hasChildren ? () => ref.read(expandedFoldersProvider.notifier).toggle(folder.key) : null,
                      child: Transform.rotate(
                        angle: expanded ? 1.5708 : 0,
                        child: EIcon(EIcons.chevronRight, size: 16, color: hasChildren ? c.text : c.textFaint),
                      ),
                    ),
                  FolderIcon(color: folder.color),
                  Expanded(
                    child: Text(
                      folder.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: c.text),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Saved on this tablet" until cloud sync arrives (Phase 7).
class _SaveCard extends StatelessWidget {
  const _SaveCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'Saved on this tablet. Cloud sync is not set up.',
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: c.line),
          borderRadius: BorderRadius.circular(Radii.button),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.button),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(spacing: 10, children: [
              EIcon(EIcons.deviceSaved, size: 22, color: c.green),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                  Text('Saved on this tablet', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
                  Text('Sync isn’t set up', style: TextStyle(fontSize: 12, color: c.textMuted)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
