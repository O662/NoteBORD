import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:cryptography/cryptography.dart' show SecretBoxAuthenticationError;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/codec.dart';
import '../board/ids.dart';
import '../board/lock.dart';
import '../board/model.dart';
import '../board/store.dart';
import '../canvas/connectors.dart';
import '../canvas/page_runtime.dart';
import '../library/library.dart';
import 'assets.dart';
import 'biometric.dart';
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

/// A new version of an item with the same id (moved, recolored, straightened…).
class ReplaceStep extends EditStep {
  const ReplaceStep(super.at, super.item, this.before);

  final Item before;

  @override
  EditStep get inverse => ReplaceStep(at, before, item);
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
    required this.revision,
    required this.saveStatus,
    required this.sealed,
    required this.lock,
  });

  final Notebook notebook;
  final List<PageRuntime> pages;

  /// Bumped on every change (content, undo history, locks).
  final int revision;
  final SaveStatus saveStatus;

  /// Pages still locked: their contents are encrypted and not loaded.
  final Set<String> sealed;
  final LockFile lock;

  /// The page at [index], clamped to the notebook.
  PageRuntime pageAt(int index) => pages[index.clamp(0, pages.length - 1)];

  int indexOf(String pageId) => pages.indexWhere((p) => p.id == pageId);

  bool isSealed(String pageId) => sealed.contains(pageId);

  /// Whether the page has its own password.
  bool hasPageLock(String pageId) => lock.pages.containsKey(pageId);

  bool get notebookLocked => lock.notebook != null;

  /// The password that protects the page, if any.
  LockEntry? lockFor(String pageId) => lock.entryFor(pageId);

  NotebookState copyWith({int? revision, SaveStatus? saveStatus, Set<String>? sealed}) => NotebookState(
        notebook: notebook,
        pages: pages,
        revision: revision ?? this.revision,
        saveStatus: saveStatus ?? this.saveStatus,
        sealed: sealed ?? this.sealed,
        lock: lock,
      );
}

/// Every file write goes through one queue, so writes land in order and a
/// notebook reopened right after closing waits for its last save.
class WriteQueue {
  Future<void> _tail = Future.value();

  Future<void> run(Future<void> Function() task) {
    final next = _tail.then((_) => task());
    _tail = next.catchError((Object _) {});
    return next;
  }

  Future<void> get idle => _tail;
}

final writeQueueProvider = Provider<WriteQueue>((ref) => WriteQueue());

final lockCryptoProvider = Provider<LockCrypto>((ref) => LockCrypto());

class NotebookNotFound implements Exception {
  const NotebookNotFound(this.id);

  final String id;

  @override
  String toString() => 'Notebook $id was not found';
}

/// Reads a notebook from storage (after any pending writes).
final loadedNotebookProvider = FutureProvider.autoDispose.family<LoadedNotebook, String>((ref, id) async {
  final store = ref.read(boardStoreProvider);
  await ref.read(writeQueueProvider).idle;
  final loaded = await store.loadNotebook(id);
  if (loaded == null) throw NotebookNotFound(id);
  return loaded;
});

/// An open notebook. Watch [loadedNotebookProvider] first; this one reads
/// its result. It is disposed (and flushed) once nothing shows the notebook.
final notebookProvider =
    NotifierProvider.autoDispose.family<NotebookNotifier, NotebookState, String>(NotebookNotifier.new);

class NotebookNotifier extends Notifier<NotebookState> {
  NotebookNotifier(this.id);

  final String id;

  static const maxUndo = 200;

  /// Changes are written this long after the first unsaved change, so
  /// everything is on disk within about half a second.
  static const saveDelay = Duration(milliseconds: 400);

  final _undo = <String, List<Command>>{};
  final _redo = <String, List<Command>>{};
  final _dirtyPages = <String>{};
  bool _metaDirty = false;
  bool _contentChanged = false;
  Timer? _saveTimer;
  List<EditStep>? _erasing;
  String? _erasePage;

  late BoardStore _store;
  late WriteQueue _queue;
  late LockCrypto _crypto;
  late BiometricUnlock _biometric;
  late LibraryNotifier _library;
  late DateTime Function() _clock;
  late LiveEditor _editor;
  late ImageDecoder _decode;
  late NotebookImages _images;

  /// The notebook and its pages, as in [state]. Saving reads these, since
  /// the last save runs while the provider is being disposed, when [state]
  /// can't be read any more.
  late Notebook _notebook;
  late List<PageRuntime> _pages;

  late LockFile _lock;
  Uint8List? _notebookKey;
  final _pageKeys = <String, Uint8List>{};

  /// Encrypted contents of pages that are still locked.
  final _sealed = <String, Uint8List>{};

  @override
  NotebookState build() {
    _store = ref.read(boardStoreProvider);
    _queue = ref.read(writeQueueProvider);
    _crypto = ref.read(lockCryptoProvider);
    _biometric = ref.read(biometricProvider);
    _library = ref.read(libraryProvider.notifier);
    _clock = ref.read(clockProvider);
    final loaded = ref.watch(loadedNotebookProvider(id)).requireValue;
    _lock = loaded.lock == null ? LockFile() : LockFile.fromJson(loaded.lock!);
    _sealed
      ..clear()
      ..addAll(loaded.sealed);
    _decode = ref.read(imageDecoderProvider);
    final images = _images = NotebookImages(read: _readAsset, decode: _decode, onLoaded: _imageLoaded);
    final pages = _pages = [for (final p in loaded.pages) PageRuntime(p, images: images.lookup)];
    _notebook = loaded.notebook;

    _editor = (change) {
      change(state.notebook);
      _metaDirty = true;
      _scheduleSave();
      state = state.copyWith(revision: state.revision + 1, saveStatus: SaveStatus.saving);
      return state.notebook;
    };
    _library.attach(id, _editor);

    ref.onDispose(() {
      _library.detach(id, _editor);
      if (_saveTimer?.isActive ?? false) flush();
      _saveTimer?.cancel();
      for (final p in pages) {
        p.dispose();
      }
      images.dispose();
    });
    return NotebookState(
      notebook: loaded.notebook,
      pages: pages,
      revision: 0,
      saveStatus: SaveStatus.saved,
      sealed: {..._sealed.keys},
      lock: _lock,
    );
  }

  PageRuntime? _pageById(String pageId) => state.pages.where((p) => p.id == pageId).firstOrNull;

  bool canUndo(String pageId) => _undo[pageId]?.isNotEmpty ?? false;

  bool canRedo(String pageId) => _redo[pageId]?.isNotEmpty ?? false;

  void _apply(Command c) {
    final page = _pageById(c.pageId);
    if (page == null) return;
    for (final s in c.steps) {
      switch (s) {
        case InsertStep():
          page.insert(s.item, s.at);
        case RemoveStep():
          page.remove(s.item.id);
        case ReplaceStep():
          page.replace(s.item);
      }
    }
  }

  void _changed(String pageId) {
    _dirtyPages.add(pageId);
    _contentChanged = true;
    _scheduleSave();
    state = state.copyWith(revision: state.revision + 1, saveStatus: SaveStatus.saving);
  }

  void _push(Command c) {
    final stack = _undo[c.pageId] ??= [];
    stack.add(c);
    if (stack.length > maxUndo) stack.removeAt(0);
    _redo[c.pageId]?.clear();
  }

  /// Adds a finished stroke to a page.
  void addStroke(String pageId, StrokeItem stroke) {
    final page = _pageById(pageId);
    if (page == null || state.isSealed(pageId)) return;
    final c = Command(page.id, [InsertStep(page.items.length, stroke)]);
    _apply(c);
    _push(c);
    _changed(page.id);
  }

  bool _editable(String pageId) => _pageById(pageId) != null && !state.isSealed(pageId);

  /// Replaces items with new versions of themselves, as one undo step.
  void replaceItems(String pageId, Iterable<Item> updated) {
    if (!_editable(pageId)) return;
    final page = _pageById(pageId)!;
    final steps = <EditStep>[
      for (final item in updated)
        if (page[item.id] case final before?) ReplaceStep(page.items.indexOf(before), item, before),
    ];
    _commit(page, steps);
  }

  /// Removes items, as one undo step.
  void removeItems(String pageId, Iterable<String> ids) {
    if (!_editable(pageId)) return;
    final page = _pageById(pageId)!;
    final wanted = ids.toSet();
    // Highest index first, so each recorded position is right when replayed.
    final steps = <EditStep>[
      for (final (i, item) in page.items.indexed.toList().reversed)
        if (wanted.contains(item.id)) RemoveStep(i, item),
    ];
    _commit(page, steps);
  }

  /// Adds items on top of the page (or at [at] in the z-order: 0 is the
  /// bottom), as one undo step.
  void insertItems(String pageId, Iterable<Item> items, {int? at}) => edit(pageId, insert: items, insertAt: at);

  /// Replaces, removes and adds items as one undo step. [insertAt] is where
  /// the new items go in the z-order once the removed ones are gone
  /// (default: on top).
  void edit(
    String pageId, {
    Iterable<Item> replace = const [],
    Iterable<String> remove = const [],
    Iterable<Item> insert = const [],
    int? insertAt,
  }) {
    if (!_editable(pageId)) return;
    final page = _pageById(pageId)!;
    final gone = remove.toSet();
    final steps = <EditStep>[
      for (final item in replace)
        if (page[item.id] case final before? when !gone.contains(item.id))
          ReplaceStep(page.items.indexOf(before), item, before),
      // Highest index first, so each recorded position is right when replayed.
      for (final (i, item) in page.items.indexed.toList().reversed)
        if (gone.contains(item.id)) RemoveStep(i, item),
    ];
    final left = page.items.length - steps.whereType<RemoveStep>().length;
    final base = insertAt == null ? left : insertAt.clamp(0, left);
    steps.addAll([for (final (i, item) in insert.indexed) InsertStep(base + i, item)]);
    _commit(page, steps);
  }

  /// Moves items to the top or the bottom of the z-order, keeping their
  /// order among themselves. One undo step.
  void reorder(String pageId, Iterable<String> ids, {required bool toFront}) {
    if (!_editable(pageId)) return;
    final page = _pageById(pageId)!;
    final wanted = ids.toSet();
    final moving = [for (final i in page.items) if (wanted.contains(i.id)) i];
    if (moving.isEmpty) return;
    final base = toFront ? page.items.length - moving.length : 0;
    _commit(page, [
      for (final (i, item) in page.items.indexed.toList().reversed)
        if (wanted.contains(item.id)) RemoveStep(i, item),
      for (final (i, item) in moving.indexed) InsertStep(base + i, item),
    ]);
  }

  /// Stores an image file in the notebook's assets and puts it on the page,
  /// centered on [center] and no bigger than [fit] (one undo step). Returns
  /// null if the page can't be written to; throws if [bytes] isn't an image.
  Future<ImageItem?> addImage(
    String pageId,
    Uint8List bytes, {
    required Offset center,
    Size fit = const Size(480, 360),
  }) async {
    if (!_editable(pageId)) return null;
    final key = _keyFor(pageId);
    if (key == null && _needsKey(pageId)) return null;
    final image = await _decode(bytes);
    final name = assetNameFor(bytes);
    // On a page with a password the file is sealed like the page itself.
    await _queue.run(() async => key == null
        ? _store.saveAsset(id, name, bytes)
        : _store.saveAsset(id, '$name.enc', await _crypto.sealBytes(key, bytes)));
    if (!ref.mounted || !_editable(pageId)) {
      image.dispose();
      return null;
    }
    _images.put(name, image);
    final scale = math.min(1.0, math.min(fit.width / image.width, fit.height / image.height));
    final w = image.width * scale, h = image.height * scale;
    final item = ImageItem(
      id: newId('it'),
      x: center.dx - w / 2,
      y: center.dy - h / 2,
      z: _pageById(pageId)!.nextZ,
      createdAt: _clock().toUtc(),
      w: w,
      h: h,
      asset: name,
    );
    insertItems(pageId, [item]);
    return item;
  }

  // Image files.

  void _imageLoaded(String asset) {
    if (!ref.mounted) return;
    for (final p in state.pages) {
      if (_assetsOn(p.page).contains(asset)) p.invalidate();
    }
    state = state.copyWith(revision: state.revision + 1);
  }

  static Set<String> _assetsOn(BoardPage page) => {
        for (final item in page.items)
          if (item is! StrokeItem) ...assetRefs(item.toJson()),
      };

  Future<Uint8List?> _readAsset(String name) async {
    await _queue.idle;
    return _assetBytes(name);
  }

  /// The file in the clear: as stored, or opened with a key we hold.
  Future<Uint8List?> _assetBytes(String name, {List<Uint8List> oldKeys = const []}) async {
    final clear = await _store.loadAsset(id, name);
    if (clear != null) return clear;
    final sealed = await _store.loadAsset(id, '$name.enc');
    if (sealed == null) return null;
    for (final key in [?_notebookKey, ..._pageKeys.values, ...oldKeys]) {
      try {
        return await _crypto.unsealBytes(key, sealed);
      } on SecretBoxAuthenticationError {
        continue;
      }
    }
    return null;
  }

  /// A page with no password (and not locked), whose images are stored in
  /// the clear.
  bool _storedClear(String pageId) => !_sealed.containsKey(pageId) && !_needsKey(pageId);

  /// Rewrites the image files of [pages] the way each page is stored now:
  /// sealed with its key, or in the clear. [oldKeys] open files that were
  /// sealed under a password that has just been removed.
  Future<void> _rewriteAssets(Iterable<PageRuntime> pages, {List<Uint8List> oldKeys = const []}) async {
    final usedClear = {
      for (final p in state.pages)
        if (_storedClear(p.id)) ..._assetsOn(p.page),
    };
    for (final p in pages) {
      final key = _keyFor(p.id);
      if (key == null && _needsKey(p.id)) continue;
      for (final name in _assetsOn(p.page)) {
        await _queue.run(() async {
          final bytes = await _assetBytes(name, oldKeys: oldKeys);
          if (bytes == null) return;
          if (key == null) {
            await _store.saveAsset(id, name, bytes);
            await _store.deleteAsset(id, '$name.enc');
          } else {
            await _store.saveAsset(id, '$name.enc', await _crypto.sealBytes(key, bytes));
            if (!usedClear.contains(name)) await _store.deleteAsset(id, name);
          }
        });
      }
    }
  }

  /// Deletes image files left in the clear that no unprotected page uses
  /// (or could bring back with Undo), so a picture deleted from a page
  /// before it was locked doesn't stay readable.
  Future<void> _dropUnusedClearAssets() async {
    final used = <String>{};
    for (final p in state.pages) {
      if (!_storedClear(p.id)) continue;
      used.addAll(_assetsOn(p.page));
      for (final c in [...?_undo[p.id], ...?_redo[p.id]]) {
        for (final s in c.steps) {
          used.addAll(assetRefs(s.item.toJson()));
          if (s is ReplaceStep) used.addAll(assetRefs(s.before.toJson()));
        }
      }
    }
    await _queue.run(() async {
      for (final name in await _store.listAssets(id)) {
        if (!name.endsWith('.enc') && !used.contains(name)) await _store.deleteAsset(id, name);
      }
    });
  }

  void _commit(PageRuntime page, List<EditStep> steps) {
    if (steps.isEmpty) return;
    final c = Command(page.id, _withConnectors(page, steps));
    _apply(c);
    _push(c);
    _changed(page.id);
  }

  /// [steps] plus what they do to connectors, in the same undo step: an
  /// end attached to a box that moved, turned or was resized goes with it;
  /// an end whose box was removed lets go; and a connector moved on its own
  /// lets go of a box its end is no longer on (moved with the box at its
  /// other end, it bends back onto the one that stayed).
  List<EditStep> _withConnectors(PageRuntime page, List<EditStep> steps) {
    final changed = <String, (BoxItem, BoxItem)>{};
    final removed = <String>{};
    final strokes = <String, int>{}; // replaced strokes: where their step is
    for (final (i, s) in steps.indexed) {
      switch (s) {
        case ReplaceStep(item: final BoxItem after, before: final BoxItem before):
          changed[after.id] = (before, after);
        case ReplaceStep(item: StrokeItem _):
          strokes[s.item.id] = i;
        case RemoveStep(item: final item):
          removed.add(item.id);
        default:
          break;
      }
    }
    final out = [...steps];
    for (final (at, item) in page.items.indexed) {
      if (item is! StrokeItem || !item.isAttached || removed.contains(item.id)) continue;
      final step = strokes[item.id];
      final was = item;
      var now = step == null ? item : out[step].item as StrokeItem;
      for (final atStart in [true, false]) {
        final id = atStart ? now.startItemId : now.endItemId;
        if (id == null) continue;
        String? Function() none() => () => null;
        if (removed.contains(id)) {
          now = atStart ? now.copyWith(startItemId: none()) : now.copyWith(endItemId: none());
        } else if (changed[id] case (final before, final after)) {
          // Only this end: [followBox] moves each end attached to the box.
          final single = atStart ? now.copyWith(endItemId: none()) : now.copyWith(startItemId: none());
          final followed = followBox(single, before, after, was: was);
          now = followed.copyWith(startItemId: () => now.startItemId, endItemId: () => now.endItemId);
        } else if (step != null) {
          if (page[id] case final BoxItem box when !endOnEdge(now, box, atStart: atStart, tolerance: 2)) {
            final withABox = changed.containsKey(was.startItemId) || changed.containsKey(was.endItemId);
            if (withABox) {
              // Moved along with the box at its other end: this end bends
              // back to the box it's on, which stayed.
              final old = atStart ? was.pagePoints.first : was.pagePoints.last;
              final cur = atStart ? now.pagePoints.first : now.pagePoints.last;
              now = now.copyWith(
                pagePoints: rubberBand(now.pageInk, atStart ? old - cur : Offset.zero, atStart ? Offset.zero : old - cur),
              );
            } else {
              // The connector moved on its own: an end that left its box lets go.
              now = atStart ? now.copyWith(startItemId: none()) : now.copyWith(endItemId: none());
            }
          }
        }
      }
      if (step != null) {
        final s = out[step] as ReplaceStep;
        out[step] = ReplaceStep(s.at, now, s.before);
      } else if (!identical(now, item)) {
        out.add(ReplaceStep(at, now, item));
      }
    }
    return out;
  }

  /// Starts an eraser drag. Everything erased until [endErase] is one undo step.
  void beginErase(String pageId) {
    if (state.isSealed(pageId)) return;
    _erasing = [];
    _erasePage = pageId;
  }

  void erase(Iterable<String> ids) {
    final steps = _erasing;
    final page = _erasePage == null ? null : _pageById(_erasePage!);
    if (steps == null || page == null) return;
    var any = false;
    for (final id in ids) {
      final removed = page.remove(id);
      if (removed != null) {
        steps.add(RemoveStep(removed.$1, removed.$2));
        any = true;
      }
    }
    if (any) state = state.copyWith(revision: state.revision + 1);
  }

  /// Rubs ink off a sticky note during an eraser drag.
  void eraseInk(String stickyId, Set<String> inkIds) {
    final steps = _erasing;
    final page = _erasePage == null ? null : _pageById(_erasePage!);
    if (steps == null || page == null) return;
    if (page[stickyId] case final StickyItem before) {
      final after = before.withoutInk(inkIds);
      if (after.items.length == before.items.length) return;
      steps.add(ReplaceStep(page.items.indexOf(before), after, before));
      page.replace(after);
      state = state.copyWith(revision: state.revision + 1);
    }
  }

  void endErase() {
    final steps = _erasing;
    final pageId = _erasePage;
    _erasing = null;
    _erasePage = null;
    if (steps == null || pageId == null || steps.isEmpty) return;
    _push(Command(pageId, steps));
    _changed(pageId);
  }

  void undo(String pageId) {
    final c = _pop(_undo[pageId]);
    if (c == null) return;
    _apply(c.inverse);
    (_redo[pageId] ??= []).add(c);
    _changed(pageId);
  }

  void redo(String pageId) {
    final c = _pop(_redo[pageId]);
    if (c == null) return;
    _apply(c);
    (_undo[pageId] ??= []).add(c);
    _changed(pageId);
  }

  static Command? _pop(List<Command>? stack) => stack == null || stack.isEmpty ? null : stack.removeLast();

  /// Adds a page after [after] (default: at the end) and returns its index.
  int addPage({int? after, Paper? paper, String? template, List<Item> items = const []}) {
    final nb = state.notebook;
    final page = BoardPage(
      id: newId('pg'),
      paper: paper ?? nb.defaultPaper,
      template: template,
      items: [...items],
    );
    final at = after == null ? state.pages.length : (after + 1).clamp(0, state.pages.length);
    nb.pageIds.insert(at, page.id);
    state.pages.insert(at, PageRuntime(page, images: _images.lookup));
    _metaDirty = true;
    _changed(page.id);
    return at;
  }

  // Saving.

  void _scheduleSave() {
    if (_saveTimer?.isActive ?? false) return;
    _saveTimer = Timer(saveDelay, flush);
  }

  /// The key a page is written with: its own, else the notebook's.
  Uint8List? _keyFor(String pageId) => _lock.pages.containsKey(pageId) ? _pageKeys[pageId] : _notebookKey;

  bool _needsKey(String pageId) => _lock.entryFor(pageId) != null;

  /// Writes every unsaved change now (also called when the app is
  /// backgrounded and when the notebook closes).
  Future<void> flush() {
    _saveTimer?.cancel();
    if (_dirtyPages.isEmpty && !_metaDirty) return _queue.idle;
    final nb = _notebook;
    final pages = <(BoardPage, Uint8List?)>[];
    for (final pageId in _dirtyPages) {
      final page = _pages.where((p) => p.id == pageId).firstOrNull;
      // Never write over a page that is still locked.
      if (page == null || _sealed.containsKey(pageId)) continue;
      final key = _keyFor(pageId);
      if (key == null && _needsKey(pageId)) continue;
      pages.add((page.page, key));
    }
    if (_contentChanged) nb.updatedAt = _clock().toUtc();
    final written = {..._dirtyPages};
    _dirtyPages.clear();
    _metaDirty = false;
    _contentChanged = false;
    final allPages = [for (final p in _pages) p.page];
    final sealed = {..._sealed.keys};
    return _queue.run(() => _write(nb, pages, allPages, sealed, written));
  }

  Future<void> _write(
    Notebook nb,
    List<(BoardPage, Uint8List?)> pages,
    List<BoardPage> allPages,
    Set<String> sealed,
    Set<String> written,
  ) async {
    try {
      // Page files first: notebook.json never lists a page that isn't written.
      for (final (page, key) in pages) {
        if (key == null) {
          await _store.savePage(nb.id, page);
        } else {
          await _store.saveSealedPage(nb.id, page.id, await _crypto.seal(key, encodePage(page)));
        }
      }
      await _store.saveNotebook(nb);
      _library.notebookSaved(nb, allPages, sealed);
      if (ref.mounted && _dirtyPages.isEmpty && !_metaDirty) {
        state = state.copyWith(saveStatus: SaveStatus.saved);
      }
    } catch (e, st) {
      debugPrint('Autosave failed: $e\n$st');
      if (ref.mounted) {
        _dirtyPages.addAll(written);
        _metaDirty = true;
        state = state.copyWith(saveStatus: SaveStatus.failed);
        _saveTimer = Timer(const Duration(seconds: 2), flush);
      }
    }
  }

  // Locks.

  void _replacePage(String pageId, BoardPage page) {
    final i = state.indexOf(pageId);
    if (i < 0) return;
    state.pages[i].dispose();
    state.pages[i] = PageRuntime(page, images: _images.lookup);
    _undo.remove(pageId);
    _redo.remove(pageId);
  }

  void _lockChanged() {
    if (!ref.mounted) return;
    state = state.copyWith(revision: state.revision + 1, sealed: {..._sealed.keys});
  }

  /// Unlocks the page with [password] (and, for a notebook password, every
  /// page it protects). Returns false for a wrong password.
  Future<bool> unlock(String pageId, String password) async {
    final entry = _lock.entryFor(pageId);
    if (entry == null) return true;
    final key = await _crypto.open(entry, password);
    if (key == null) return false;
    await _applyKey(pageId, key);
    return true;
  }

  /// Unlocks with the key saved for fingerprint or face unlock.
  Future<bool> unlockWithBiometrics(String pageId, {required String reason}) async {
    final entry = _lock.entryFor(pageId);
    if (entry == null) return true;
    final own = _lock.pages.containsKey(pageId);
    final key = await _biometric.read(biometricSlot(id, own ? pageId : null), reason: reason);
    if (key == null || !await _crypto.verify(entry, key)) return false;
    await _applyKey(pageId, key);
    return true;
  }

  Future<void> _applyKey(String pageId, Uint8List key) async {
    final own = _lock.pages.containsKey(pageId);
    if (own) {
      _pageKeys[pageId] = key;
    } else {
      _notebookKey = key;
    }
    for (final pid in [..._sealed.keys]) {
      final opens = own ? pid == pageId : !_lock.pages.containsKey(pid);
      if (!opens) continue;
      try {
        final page = decodePage(await _crypto.unseal(key, _sealed[pid]!));
        _sealed.remove(pid);
        _replacePage(pid, page);
      } on Object catch (e) {
        debugPrint('Could not open page $pid: $e');
      }
    }
    // Pictures on the pages that just opened can be read now.
    _images.retryMissing();
    _lockChanged();
  }

  /// Sets a password on one page, then locks it.
  Future<void> lockPage(String pageId, String password, {String? hint, bool biometric = false}) async {
    final page = _pageById(pageId);
    if (page == null || _sealed.containsKey(pageId)) return;
    final (entry, key) = await _crypto.create(password, hint: hint, biometric: biometric);
    _lock.pages[pageId] = entry;
    // lock.json first, so a sealed page is never on disk without its salt.
    await _queue.run(() => _store.saveLock(id, _lock.toJson()));
    _pageKeys[pageId] = key;
    page.page.locked = true;
    if (biometric) await _biometric.save(biometricSlot(id, pageId), key);
    _dirtyPages.add(pageId);
    await _rewriteAssets([page]);
    await _dropUnusedClearAssets();
    await lockNow();
  }

  /// Sets a password on the whole notebook, then locks it.
  Future<void> lockNotebook(String password, {String? hint, bool biometric = false}) async {
    final (entry, key) = await _crypto.create(password, hint: hint, biometric: biometric);
    _lock.notebook = entry;
    await _queue.run(() => _store.saveLock(id, _lock.toJson()));
    _notebookKey = key;
    state.notebook.locked = true;
    if (biometric) await _biometric.save(biometricSlot(id, null), key);
    final covered = [
      for (final p in state.pages)
        if (!_lock.pages.containsKey(p.id) && !_sealed.containsKey(p.id)) p,
    ];
    _dirtyPages.addAll([for (final p in covered) p.id]);
    _metaDirty = true;
    await _rewriteAssets(covered);
    await _dropUnusedClearAssets();
    await lockNow();
  }

  /// Saves, then locks every unlocked page that has a password again.
  Future<void> lockNow() async {
    await flush();
    final pictures = <String>{};
    for (final p in [...state.pages]) {
      if (_sealed.containsKey(p.id)) continue;
      final key = _keyFor(p.id);
      if (key == null) continue;
      pictures.addAll(_assetsOn(p.page));
      _sealed[p.id] = await _crypto.seal(key, encodePage(p.page));
      _replacePage(p.id, BoardPage(id: p.id, locked: true));
    }
    _images.evict(pictures);
    _notebookKey = null;
    _pageKeys.clear();
    _lockChanged();
  }

  /// Whether any page with a password is open right now.
  bool get hasOpenLocks => state.pages.any((p) => !_sealed.containsKey(p.id) && _keyFor(p.id) != null);

  /// Removes the page's own password (it must be unlocked).
  Future<void> removePageLock(String pageId) async {
    final page = _pageById(pageId);
    if (page == null || _sealed.containsKey(pageId) || !_lock.pages.containsKey(pageId)) return;
    _lock.pages.remove(pageId);
    final old = _pageKeys.remove(pageId);
    page.page.locked = false;
    await _biometric.delete(biometricSlot(id, pageId));
    _dirtyPages.add(pageId);
    // The page is rewritten first; lock.json loses the entry only after.
    await flush();
    await _rewriteAssets([page], oldKeys: [?old]);
    await _queue.run(() => _store.saveLock(id, _lock.isEmpty ? null : _lock.toJson()));
    _lockChanged();
  }

  /// Removes the notebook's password (it must be unlocked).
  Future<void> removeNotebookLock() async {
    final old = _notebookKey;
    if (_lock.notebook == null || old == null) return;
    _lock.notebook = null;
    _notebookKey = null;
    state.notebook.locked = false;
    await _biometric.delete(biometricSlot(id, null));
    final uncovered = [
      for (final p in state.pages)
        if (!_lock.pages.containsKey(p.id) && !_sealed.containsKey(p.id)) p,
    ];
    _dirtyPages.addAll([for (final p in uncovered) p.id]);
    _metaDirty = true;
    await flush();
    await _rewriteAssets(uncovered, oldKeys: [old]);
    await _queue.run(() => _store.saveLock(id, _lock.isEmpty ? null : _lock.toJson()));
    _lockChanged();
  }
}
