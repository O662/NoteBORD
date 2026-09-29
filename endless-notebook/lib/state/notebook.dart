import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../board/ids.dart';
import '../board/model.dart';
import '../board/store.dart';
import '../canvas/page_runtime.dart';
import 'settings.dart';

enum SaveStatus { saved, saving, failed }

/// One step of an edit. Undo/redo replays steps backwards, and the same
/// steps will become CRDT ops for sync and collaboration.
sealed class EditStep {
  const EditStep(this.at, this.item);

  final int at;
  final Item item;

  EditStep get inverse;
}

class InsertStep extends EditStep {
  const InsertStep(super.at, super.item);

  @override
  EditStep get inverse => RemoveStep(at, item);
}

class RemoveStep extends EditStep {
  const RemoveStep(super.at, super.item);

  @override
  EditStep get inverse => InsertStep(at, item);
}

class Command {
  const Command(this.pageId, this.steps);

  final String pageId;
  final List<EditStep> steps;

  Command get inverse => Command(pageId, [for (final s in steps.reversed) s.inverse]);
}

@immutable
class NotebookState {
  const NotebookState({
    required this.notebook,
    required this.pages,
    required this.current,
    required this.revision,
    required this.saveStatus,
    required this.canUndo,
    required this.canRedo,
  });

  final Notebook notebook;
  final List<PageRuntime> pages;
  final int current;

  /// Bumped on every content change.
  final int revision;
  final SaveStatus saveStatus;
  final bool canUndo;
  final bool canRedo;

  PageRuntime get page => pages[current];

  NotebookState copyWith({int? current, int? revision, SaveStatus? saveStatus, bool? canUndo, bool? canRedo}) =>
      NotebookState(
        notebook: notebook,
        pages: pages,
        current: current ?? this.current,
        revision: revision ?? this.revision,
        saveStatus: saveStatus ?? this.saveStatus,
        canUndo: canUndo ?? this.canUndo,
        canRedo: canRedo ?? this.canRedo,
      );
}

final initialNotebookProvider =
    Provider<LoadedNotebook>((ref) => throw UnimplementedError('Override in bootstrap'));

final notebookProvider = NotifierProvider<NotebookNotifier, NotebookState>(NotebookNotifier.new);

class NotebookNotifier extends Notifier<NotebookState> {
  static const maxUndo = 200;

  /// Changes are written this long after the first unsaved change, so
  /// everything is on disk within about half a second.
  static const saveDelay = Duration(milliseconds: 400);

  final _undo = <String, List<Command>>{};
  final _redo = <String, List<Command>>{};
  final _dirtyPages = <String>{};
  bool _metaDirty = false;
  Timer? _saveTimer;
  Future<void> _saving = Future.value();
  List<EditStep>? _erasing;

  BoardStore get _store => ref.read(boardStoreProvider);

  @override
  NotebookState build() {
    final loaded = ref.read(initialNotebookProvider);
    final pages = [for (final p in loaded.pages) PageRuntime(p)];
    ref.onDispose(() {
      if (_saveTimer?.isActive ?? false) flush();
      for (final p in pages) {
        p.dispose();
      }
    });
    return NotebookState(
      notebook: loaded.notebook,
      pages: pages,
      current: 0,
      revision: 0,
      saveStatus: SaveStatus.saved,
      canUndo: false,
      canRedo: false,
    );
  }

  PageRuntime? _pageById(String id) => state.pages.where((p) => p.id == id).firstOrNull;

  void _apply(Command c) {
    final page = _pageById(c.pageId);
    if (page == null) return;
    for (final s in c.steps) {
      switch (s) {
        case InsertStep():
          page.insert(s.item, s.at);
        case RemoveStep():
          page.remove(s.item.id);
      }
    }
  }

  void _changed(String pageId) {
    _dirtyPages.add(pageId);
    _scheduleSave();
    final id = state.page.id;
    state = state.copyWith(
      revision: state.revision + 1,
      saveStatus: SaveStatus.saving,
      canUndo: _undo[id]?.isNotEmpty ?? false,
      canRedo: _redo[id]?.isNotEmpty ?? false,
    );
  }

  void _push(Command c) {
    final stack = _undo[c.pageId] ??= [];
    stack.add(c);
    if (stack.length > maxUndo) stack.removeAt(0);
    _redo[c.pageId]?.clear();
  }

  /// Adds a finished stroke to the current page.
  void addStroke(StrokeItem stroke) {
    final page = state.page;
    final c = Command(page.id, [InsertStep(page.items.length, stroke)]);
    _apply(c);
    _push(c);
    _changed(page.id);
  }

  /// Starts an eraser drag. Everything erased until [endErase] is one undo step.
  void beginErase() => _erasing = [];

  void erase(Iterable<String> ids) {
    final steps = _erasing;
    if (steps == null) return;
    final page = state.page;
    var any = false;
    for (final id in ids) {
      final removed = page.remove(id);
      if (removed != null) {
        steps.add(RemoveStep(removed.$1, removed.$2));
        any = true;
      }
    }
    if (any) {
      state = state.copyWith(revision: state.revision + 1);
    }
  }

  void endErase() {
    final steps = _erasing;
    _erasing = null;
    if (steps == null || steps.isEmpty) return;
    _push(Command(state.page.id, steps));
    _changed(state.page.id);
  }

  void undo() {
    final id = state.page.id;
    final c = _pop(_undo[id]);
    if (c == null) return;
    _apply(c.inverse);
    (_redo[id] ??= []).add(c);
    _changed(id);
  }

  void redo() {
    final id = state.page.id;
    final c = _pop(_redo[id]);
    if (c == null) return;
    _apply(c);
    (_undo[id] ??= []).add(c);
    _changed(id);
  }

  static Command? _pop(List<Command>? stack) =>
      stack == null || stack.isEmpty ? null : stack.removeLast();

  void goToPage(int index) {
    if (index < 0 || index >= state.pages.length || index == state.current) return;
    final id = state.pages[index].id;
    state = state.copyWith(
      current: index,
      canUndo: _undo[id]?.isNotEmpty ?? false,
      canRedo: _redo[id]?.isNotEmpty ?? false,
    );
  }

  void addPage() {
    final nb = state.notebook;
    final page = BoardPage(id: newId('pg'), paper: nb.defaultPaper);
    nb.pageIds.add(page.id);
    state.pages.add(PageRuntime(page));
    _metaDirty = true;
    _changed(page.id);
    goToPage(state.pages.length - 1);
  }

  void _scheduleSave() {
    if (_saveTimer?.isActive ?? false) return;
    _saveTimer = Timer(saveDelay, flush);
  }

  /// Writes every unsaved change now (also called when the app is backgrounded).
  Future<void> flush() {
    _saveTimer?.cancel();
    _saving = _saving.then((_) => _write());
    return _saving;
  }

  Future<void> _write() async {
    if (_dirtyPages.isEmpty && !_metaDirty) return;
    final nb = state.notebook;
    final pages = [for (final id in _dirtyPages) ?_pageById(id)];
    _dirtyPages.clear();
    _metaDirty = false;
    try {
      // Page files first: notebook.json never lists a page that isn't written.
      for (final p in pages) {
        await _store.savePage(nb.id, p.page);
      }
      nb.updatedAt = DateTime.now().toUtc();
      await _store.saveNotebook(nb);
      if (ref.mounted && _dirtyPages.isEmpty) {
        state = state.copyWith(saveStatus: SaveStatus.saved);
      }
    } catch (e, st) {
      debugPrint('Autosave failed: $e\n$st');
      _dirtyPages.addAll(pages.map((p) => p.id));
      _metaDirty = true;
      if (ref.mounted) {
        state = state.copyWith(saveStatus: SaveStatus.failed);
        _saveTimer = Timer(const Duration(seconds: 2), flush);
      }
    }
  }
}

/// Loads settings and the last notebook (creating one on first run), and
/// returns the provider overrides the app starts with.
Future<List<Override>> bootstrap(BoardStore store) async {
  final json = await store.loadSettings();
  var settings = json == null ? AppSettings() : AppSettings.fromJson(json);

  LoadedNotebook? loaded;
  final last = settings.lastNotebookId;
  if (last != null) loaded = await store.loadNotebook(last);
  if (loaded == null) {
    for (final id in await store.listNotebookIds()) {
      loaded = await store.loadNotebook(id);
      if (loaded != null) break;
    }
  }
  if (loaded == null) {
    final now = DateTime.now().toUtc();
    final page = BoardPage(id: newId('pg'));
    final nb = Notebook(
      id: newId('nb'),
      title: 'Untitled notebook',
      createdAt: now,
      updatedAt: now,
      pageIds: [page.id],
    );
    await store.savePage(nb.id, page);
    await store.saveNotebook(nb);
    loaded = LoadedNotebook(nb, [page]);
  }
  if (settings.lastNotebookId != loaded.notebook.id) {
    settings = settings.copyWith(lastNotebookId: loaded.notebook.id);
    await store.saveSettings(settings.toJson());
  }

  return [
    boardStoreProvider.overrideWithValue(store),
    initialSettingsProvider.overrideWithValue(settings),
    initialNotebookProvider.overrideWithValue(loaded),
  ];
}
