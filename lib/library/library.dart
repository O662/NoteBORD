import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/ids.dart';
import '../board/model.dart';
import '../board/store.dart';
import '../state/settings.dart';
import '../theme/tokens.g.dart' as tokens;
import 'index_db.dart';
import 'thumbs.dart';

/// Notebooks in the Trash for longer than this are deleted on startup.
const trashDays = Duration(days: 30);

/// One notebook as the library lists it.
@immutable
class NotebookEntry {
  const NotebookEntry({
    required this.id,
    required this.title,
    required this.folder,
    this.cover,
    required this.createdAt,
    required this.updatedAt,
    required this.pageCount,
    this.locked = false,
    this.lockedPages = 0,
    this.pinned = false,
    this.trashedAt,
    this.lastPage = 0,
    this.openedAt,
    this.thumb,
  });

  final String id;
  final String title;
  final List<String> folder;
  final Color? cover;
  final DateTime createdAt;

  /// Last time its pages changed ("Last edited").
  final DateTime updatedAt;
  final int pageCount;

  /// The whole notebook has a password.
  final bool locked;

  /// Pages with their own password.
  final int lockedPages;
  final bool pinned;
  final DateTime? trashedAt;

  /// Where this device last had it open.
  final int lastPage;
  final DateTime? openedAt;

  /// Ink for the cover; null when empty or locked.
  final InkThumb? thumb;

  bool get trashed => trashedAt != null;

  NotebookEntry copyWith({
    String? title,
    List<String>? folder,
    Color? cover,
    DateTime? updatedAt,
    int? pageCount,
    bool? locked,
    int? lockedPages,
    bool? pinned,
    DateTime? Function()? trashedAt,
    int? lastPage,
    DateTime? openedAt,
    InkThumb? Function()? thumb,
  }) =>
      NotebookEntry(
        id: id,
        title: title ?? this.title,
        folder: folder ?? this.folder,
        cover: cover ?? this.cover,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        pageCount: pageCount ?? this.pageCount,
        locked: locked ?? this.locked,
        lockedPages: lockedPages ?? this.lockedPages,
        pinned: pinned ?? this.pinned,
        trashedAt: trashedAt == null ? this.trashedAt : trashedAt(),
        lastPage: lastPage ?? this.lastPage,
        openedAt: openedAt ?? this.openedAt,
        thumb: thumb == null ? this.thumb : thumb(),
      );

  /// Refreshes the fields that live in notebook.json.
  NotebookEntry withMeta(Notebook nb) => NotebookEntry(
        id: id,
        title: nb.title,
        folder: List.unmodifiable(nb.folderPath),
        cover: nb.coverColor == null ? null : colorFromHex(nb.coverColor!),
        createdAt: nb.createdAt,
        updatedAt: nb.updatedAt,
        pageCount: nb.pageIds.length,
        locked: nb.locked,
        lockedPages: lockedPages,
        pinned: nb.pinned,
        trashedAt: nb.trashedAt,
        lastPage: lastPage.clamp(0, nb.pageIds.isEmpty ? 0 : nb.pageIds.length - 1),
        openedAt: openedAt,
        thumb: nb.locked ? null : thumb,
      );

  /// Builds an entry from a loaded notebook, keeping this device's reading
  /// position from [previous].
  static NotebookEntry fromLoaded(LoadedNotebook loaded, {NotebookEntry? previous}) {
    final nb = loaded.notebook;
    final base = (previous ??
            NotebookEntry(
              id: nb.id,
              title: nb.title,
              folder: const [],
              createdAt: nb.createdAt,
              updatedAt: nb.updatedAt,
              pageCount: nb.pageIds.length,
            ))
        .withMeta(nb);
    return base.copyWith(
      lockedPages: loaded.pages.where((p) => p.locked).length,
      thumb: () => nb.locked ? null : coverThumb(loaded.pages, base.lastPage, loaded.sealed.keys.toSet()),
    );
  }
}

/// The cover shows the page last open on this device, or else the first page
/// with ink. Locked pages never appear on a cover.
InkThumb? coverThumb(List<BoardPage> pages, int lastPage, Set<String> sealed) {
  bool usable(BoardPage p) => !p.locked && !sealed.contains(p.id) && p.items.isNotEmpty;
  if (lastPage >= 0 && lastPage < pages.length && usable(pages[lastPage])) {
    final t = InkThumb.fromPage(pages[lastPage]);
    if (t != null) return t;
  }
  for (final p in pages) {
    if (!usable(p)) continue;
    final t = InkThumb.fromPage(p);
    if (t != null) return t;
  }
  return null;
}

/// A folder. Paths are names from the top, e.g. `['School', 'Physics']`.
@immutable
class FolderEntry {
  const FolderEntry(this.path, this.color);

  final List<String> path;
  final Color color;

  String get name => path.last;
  String get key => folderKey(path);
}

String folderKey(List<String> path) => path.join('\u001f');

bool isInside(List<String> folder, List<String> ancestor) =>
    folder.length >= ancestor.length && listEquals(folder.sublist(0, ancestor.length), ancestor);

@immutable
class LibraryState {
  LibraryState({required List<NotebookEntry> notebooks, required List<FolderEntry> explicitFolders})
      : notebooks = List.unmodifiable(notebooks),
        explicitFolders = List.unmodifiable(explicitFolders);

  /// Every notebook, including those in the Trash.
  final List<NotebookEntry> notebooks;

  /// Folders from library.json (with their colors), including empty ones.
  final List<FolderEntry> explicitFolders;

  late final List<NotebookEntry> active = notebooks.where((n) => !n.trashed).toList();
  late final List<NotebookEntry> trash = notebooks.where((n) => n.trashed).toList()
    ..sort((a, b) => b.trashedAt!.compareTo(a.trashedAt!));

  /// Every folder: the saved ones in the order they were made, then any
  /// other folder a notebook sits in (e.g. from another device), by name.
  late final List<FolderEntry> folders = () {
    final byKey = {for (final f in explicitFolders) f.key: f};
    final found = <FolderEntry>[];
    for (final n in active) {
      for (var i = 1; i <= n.folder.length; i++) {
        final path = n.folder.sublist(0, i);
        if (byKey.containsKey(folderKey(path))) continue;
        final f = FolderEntry(path, _inheritedColor(path, byKey));
        byKey[f.key] = f;
        found.add(f);
      }
    }
    found.sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return [...explicitFolders, ...found];
  }();

  static Color _inheritedColor(List<String> path, Map<String, FolderEntry> byKey) {
    for (var i = path.length - 1; i > 0; i--) {
      final parent = byKey[folderKey(path.sublist(0, i))];
      if (parent != null) return parent.color;
    }
    return tokens.coverColors[path.first.hashCode.abs() % 4];
  }

  NotebookEntry? byId(String id) => notebooks.where((n) => n.id == id).firstOrNull;

  FolderEntry? folder(List<String> path) => folders.where((f) => listEquals(f.path, path)).firstOrNull;

  /// Direct subfolders of [path] (top-level folders for `[]`).
  List<FolderEntry> childrenOf(List<String> path) => [
        for (final f in folders)
          if (f.path.length == path.length + 1 && isInside(f.path, path)) f,
      ];

  /// Notebooks directly in [path].
  List<NotebookEntry> notebooksIn(List<String> path) => [
        for (final n in active)
          if (listEquals(n.folder, path)) n,
      ];

  /// Notebooks in [path] or any folder inside it.
  int countUnder(List<String> path) => active.where((n) => isInside(n.folder, path)).length;

  /// The spine color for a notebook: its own, else its folder's, else blue.
  Color coverOf(NotebookEntry n) =>
      n.cover ?? (n.folder.isEmpty ? tokens.coverColors.first : folder(n.folder)?.color ?? tokens.coverColors.first);

  /// The notebook for "Continue writing": the one opened most recently (one
  /// that was opened wins a tie with one that was only edited).
  NotebookEntry? get continueWriting {
    if (active.isEmpty) return null;
    return active.reduce((a, b) {
      final ta = a.openedAt ?? a.updatedAt, tb = b.openedAt ?? b.updatedAt;
      if (ta.isAtSameMomentAs(tb)) return b.openedAt != null && a.openedAt == null ? b : a;
      return ta.isAfter(tb) ? a : b;
    });
  }

  List<NotebookEntry> get pinned => active.where((n) => n.pinned).toList()..sort((a, b) => a.title.compareTo(b.title));

  /// Most recently edited, newest first.
  List<NotebookEntry> recent({String? except, int count = 4}) => (active.where((n) => n.id != except).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)))
      .take(count)
      .toList();
}

final indexDbProvider = Provider<IndexDb>((ref) => throw UnimplementedError('Override in bootstrap'));

/// "Now", overridable so tests and goldens show fixed dates.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final initialLibraryProvider = Provider<LibraryState>((ref) => throw UnimplementedError('Override in bootstrap'));

final libraryProvider = NotifierProvider<LibraryNotifier, LibraryState>(LibraryNotifier.new);

/// Changes a notebook that is open in an editor, returning it after the change.
typedef LiveEditor = Notebook Function(void Function(Notebook nb) change);

class LibraryNotifier extends Notifier<LibraryState> {
  late BoardStore _store;
  late IndexDb _index;
  final _live = <String, LiveEditor>{};

  @override
  LibraryState build() {
    _store = ref.read(boardStoreProvider);
    _index = ref.read(indexDbProvider);
    return ref.read(initialLibraryProvider);
  }

  DateTime get _now => ref.read(clockProvider)().toUtc();

  /// An open notebook registers here, so library changes (rename, move, pin…)
  /// go through its editor instead of racing its autosave.
  void attach(String id, LiveEditor editor) => _live[id] = editor;

  void detach(String id, LiveEditor editor) {
    if (identical(_live[id], editor)) _live.remove(id);
  }

  void _put(NotebookEntry e) {
    final list = [...state.notebooks];
    final i = list.indexWhere((n) => n.id == e.id);
    if (i < 0) {
      list.add(e);
    } else {
      list[i] = e;
    }
    state = LibraryState(notebooks: list, explicitFolders: state.explicitFolders);
    _index.upsert(e);
  }

  Future<void> _editMeta(String id, void Function(Notebook nb) change) async {
    final entry = state.byId(id);
    if (entry == null) return;
    final live = _live[id];
    final Notebook nb;
    if (live != null) {
      nb = live(change);
    } else {
      final meta = await _store.loadNotebookMeta(id);
      if (meta == null) return;
      change(meta);
      await _store.saveNotebook(meta);
      nb = meta;
    }
    _put(state.byId(id)!.withMeta(nb));
  }

  // Notebooks.

  /// Creates a notebook with one page and returns its id.
  Future<String> createNotebook({
    String title = 'Untitled notebook',
    List<String> folder = const [],
    Paper paper = Paper.dots,
    String? template,
    List<Item> items = const [],
    Color? cover,
  }) async {
    final now = _now;
    final page = BoardPage(id: newId('pg', now: now), paper: paper, template: template, items: [...items]);
    final nb = Notebook(
      id: newId('nb', now: now),
      title: title,
      folderPath: [...folder],
      coverColor: cover == null ? null : colorToHex(cover),
      createdAt: now,
      updatedAt: now,
      pageIds: [page.id],
      defaultPaper: paper,
    );
    await _store.savePage(nb.id, page);
    await _store.saveNotebook(nb);
    if (folder.isNotEmpty) await _ensureFolder(folder);
    _put(NotebookEntry.fromLoaded(LoadedNotebook(nb, [page])));
    return nb.id;
  }

  Future<void> rename(String id, String title) {
    final t = title.trim();
    if (t.isEmpty) return Future.value();
    return _editMeta(id, (nb) => nb.title = t);
  }

  Future<void> move(String id, List<String> folder) async {
    if (folder.isNotEmpty) await _ensureFolder(folder);
    await _editMeta(id, (nb) => nb.folderPath = [...folder]);
  }

  Future<void> setCover(String id, Color color) => _editMeta(id, (nb) => nb.coverColor = colorToHex(color));

  Future<void> setPinned(String id, bool pinned) => _editMeta(id, (nb) => nb.pinned = pinned);

  Future<void> trash(String id) {
    final now = _now;
    return _editMeta(id, (nb) => nb.trashedAt = now);
  }

  Future<void> restore(String id) async {
    final folder = state.byId(id)?.folder ?? const [];
    if (folder.isNotEmpty) await _ensureFolder(folder);
    await _editMeta(id, (nb) => nb.trashedAt = null);
  }

  Future<void> deleteForever(String id) async {
    await _store.deleteNotebook(id);
    await _index.remove(id);
    state = LibraryState(
      notebooks: state.notebooks.where((n) => n.id != id).toList(),
      explicitFolders: state.explicitFolders,
    );
  }

  Future<void> emptyTrash() async {
    for (final n in [...state.trash]) {
      await deleteForever(n.id);
    }
  }

  /// Remembers where this device is in a notebook (Continue writing, covers).
  void recordOpened(String id, int page) {
    final e = state.byId(id);
    if (e == null) return;
    _put(e.copyWith(lastPage: page, openedAt: _now));
  }

  /// Called by an open notebook after each save.
  void notebookSaved(Notebook nb, List<BoardPage> pages, Set<String> sealed) {
    final previous = state.byId(nb.id);
    if (previous == null) return;
    final e = previous.withMeta(nb);
    _put(e.copyWith(
      lockedPages: pages.where((p) => p.locked).length,
      thumb: () => nb.locked ? null : coverThumb(pages, e.lastPage, sealed),
    ));
  }

  // Folders.

  Future<void> _saveFolders(List<FolderEntry> explicit) async {
    state = LibraryState(notebooks: state.notebooks, explicitFolders: explicit);
    await _store.saveLibrary({
      'version': 1,
      'folders': [
        for (final f in explicit) {'path': f.path, 'color': colorToHex(f.color)},
      ],
    });
  }

  Future<void> _ensureFolder(List<String> path) async {
    final explicit = [...state.explicitFolders];
    var changed = false;
    for (var i = 1; i <= path.length; i++) {
      final p = path.sublist(0, i);
      if (explicit.any((f) => listEquals(f.path, p))) continue;
      explicit.add(FolderEntry(p, state.folder(p)?.color ?? _nextFolderColor(p)));
      changed = true;
    }
    if (changed) await _saveFolders(explicit);
  }

  Color _nextFolderColor(List<String> path) {
    if (path.length > 1) {
      final parent = state.folder(path.sublist(0, path.length - 1));
      if (parent != null) return parent.color;
    }
    return tokens.coverColors[state.childrenOf(const []).length % 4];
  }

  /// Creates `parent/name`. Returns false if a folder with that name exists.
  Future<bool> createFolder(List<String> parent, String name, {Color? color}) async {
    final n = name.trim();
    if (n.isEmpty) return false;
    final path = [...parent, n];
    if (state.folder(path) != null) return false;
    if (parent.isNotEmpty) await _ensureFolder(parent);
    await _saveFolders([...state.explicitFolders, FolderEntry(path, color ?? _nextFolderColor(path))]);
    return true;
  }

  /// Renames the folder at [path]; notebooks and subfolders move with it.
  Future<bool> renameFolder(List<String> path, String name) async {
    final n = name.trim();
    if (n.isEmpty) return false;
    final to = [...path.sublist(0, path.length - 1), n];
    if (listEquals(to, path)) return true;
    if (state.folder(to) != null) return false;
    List<String> moved(List<String> p) => [...to, ...p.sublist(path.length)];
    await _ensureFolder(path);
    await _saveFolders([
      for (final f in state.explicitFolders) isInside(f.path, path) ? FolderEntry(moved(f.path), f.color) : f,
    ]);
    for (final nb in [...state.notebooks]) {
      if (isInside(nb.folder, path)) await _editMeta(nb.id, (m) => m.folderPath = moved(m.folderPath));
    }
    return true;
  }

  Future<void> setFolderColor(List<String> path, Color color) async {
    await _ensureFolder(path);
    await _saveFolders([
      for (final f in state.explicitFolders) listEquals(f.path, path) ? FolderEntry(f.path, color) : f,
    ]);
  }

  /// Deletes the folder and its subfolders; their notebooks go to the Trash.
  Future<void> deleteFolder(List<String> path) async {
    for (final nb in [...state.active]) {
      if (isInside(nb.folder, path)) await trash(nb.id);
    }
    await _saveFolders([
      for (final f in state.explicitFolders)
        if (!isInside(f.path, path)) f,
    ]);
  }
}

/// Builds the library at startup: reads each notebook.json, refreshes index
/// rows that are missing or out of date, drops rows for deleted notebooks and
/// empties Trash items older than [trashDays].
Future<LibraryState> loadLibrary(BoardStore store, IndexDb index, DateTime now) async {
  final indexed = {for (final e in await index.all()) e.id: e};
  final entries = <NotebookEntry>[];
  for (final id in await store.listNotebookIds()) {
    final meta = await store.loadNotebookMeta(id);
    if (meta == null) continue;
    if (meta.trashedAt != null && now.difference(meta.trashedAt!) > trashDays) {
      await store.deleteNotebook(id);
      continue;
    }
    final previous = indexed.remove(id);
    NotebookEntry entry;
    if (previous == null ||
        !previous.updatedAt.isAtSameMomentAs(meta.updatedAt) ||
        previous.pageCount != meta.pageIds.length ||
        previous.locked != meta.locked) {
      final loaded = await store.loadNotebook(id);
      if (loaded == null) continue;
      entry = NotebookEntry.fromLoaded(loaded, previous: previous);
    } else {
      entry = previous.withMeta(meta);
    }
    await index.upsert(entry);
    entries.add(entry);
  }
  for (final gone in indexed.keys) {
    await index.remove(gone);
  }

  final lib = await store.loadLibrary();
  final folders = <FolderEntry>[
    for (final f in (lib?['folders'] as List?) ?? const [])
      if (f is Map && f['path'] is List && (f['path'] as List).isNotEmpty)
        FolderEntry(
          (f['path'] as List).cast<String>(),
          f['color'] is String ? colorFromHex(f['color'] as String) : tokens.coverColors.first,
        ),
  ];
  return LibraryState(notebooks: entries, explicitFolders: folders);
}
