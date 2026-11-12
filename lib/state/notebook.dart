import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Color, Offset, Size;

import 'package:cryptography/cryptography.dart' show SecretBoxAuthenticationError;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/codec.dart';
import '../board/ids.dart';
import '../board/lock.dart';
import '../audio/ink_moments.dart';
import '../board/model.dart';
import '../board/store.dart';
import '../canvas/charts.dart' show refreshedChart;
import '../canvas/connectors.dart';
import '../canvas/office_cards.dart';
import '../canvas/page_runtime.dart';
import '../library/library.dart';
import '../math/math_pictures.dart';
import '../office/office_model.dart';
import '../office/office_reader.dart';
import '../office/office_render.dart';
import '../recognition/handwriting_index.dart';
import '../sync/doc.dart';
import '../sync/stamps.dart' show hashJson;
import '../sync/versions.dart';
import 'assets.dart';
import 'biometric.dart';
import 'changes.dart';
import 'office_docs.dart';
import 'settings.dart';
import 'diag.dart';

enum SaveStatus { saved, saving, failed }

/// A card that now shows a newer version of its file. [lostPages] is how
/// many pages with ink on them aren't in the new version (their ink went
/// with them; Undo brings it back).
class OfficeUpdate {
  const OfficeUpdate(this.item, {this.lostPages = 0});

  final OfficeItem item;
  final int lostPages;
}

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

/// A page's own settings: what version history puts back along with the
/// items.
typedef PageHead = ({String title, Color? color, Paper paper, Object? template});

PageHead _headOf(BoardPage p) => (title: p.title, color: p.color, paper: p.paper, template: p.template);

class Command {
  const Command(this.pageId, this.steps, {this.head});

  final String pageId;
  final List<EditStep> steps;

  /// The page's own settings before and after, when the command changes
  /// them (restoring a version); null when they stay as they are.
  final (PageHead, PageHead)? head;

  Command get inverse => Command(
        pageId,
        [for (final s in steps.reversed) s.inverse],
        head: switch (head) {
          (final before, final after) => (after, before),
          null => null,
        },
      );
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

  /// The library's cover of the notebook is made again on an autosave at
  /// most this often (and always on [flush] from elsewhere: leaving the
  /// notebook, the app going to the background). Making it reads all the
  /// ink on the page, which slowed the pen when it happened after every
  /// stroke.
  static const coverEvery = Duration(seconds: 30);

  final _undo = <String, List<Command>>{};
  final _redo = <String, List<Command>>{};
  final _dirtyPages = <String>{};
  bool _metaDirty = false;
  bool _contentChanged = false;
  Timer? _saveTimer;

  /// When the cover was last made (see [coverEvery]); null: not yet.
  DateTime? _coverAt;

  /// While the pen is on the page, an autosave waits for it to lift, so the
  /// work never lands in the middle of a stroke.
  bool _inking = false;
  bool _saveWhenLifted = false;
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
  late NotebookDocs _docs;
  late MathPictures _math;
  late HandwritingIndex _index;
  late InkMoments _inkMoments;
  late LocalChanges _changes;
  late VersionStore _versions;

  /// The furthest each recording's transcript has got, by item id, so Undo
  /// and Redo (which put back items as they were) don't lose it.
  final _clips = <String, Transcribed>{};

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
    _inkMoments = ref.read(inkMomentsProvider);
    _changes = ref.read(localChangesProvider);
    _versions = ref.read(versionStoreProvider);
    final loaded = ref.watch(loadedNotebookProvider(id)).requireValue;
    _lock = loaded.lock == null ? LockFile() : LockFile.fromJson(loaded.lock!);
    _sealed
      ..clear()
      ..addAll(loaded.sealed);
    _decode = ref.read(imageDecoderProvider);
    final images = _images = NotebookImages(read: _readAsset, decode: _decode, onLoaded: _imageLoaded);
    final docs = _docs = NotebookDocs(read: _readAsset, parse: ref.read(officeParserProvider), decode: _decode, onLoaded: _imageLoaded);
    final pictures = _math = ref.read(mathPicturesProvider)..addListener(_mathTypeset);
    final pages = _pages = [for (final p in loaded.pages) _runtime(p)];
    _notebook = loaded.notebook;

    _editor = (change) {
      change(state.notebook);
      _metaDirty = true;
      _scheduleSave();
      state = state.copyWith(revision: state.revision + 1, saveStatus: SaveStatus.saving);
      return state.notebook;
    };
    _library.attach(id, _editor);
    final index = _index = ref.read(handwritingIndexProvider);
    final source = _IndexSource(this);
    index.attach(id, source);

    ref.onDispose(() {
      _library.detach(id, _editor);
      diag('notebook $id closing: saveDue=${_saveTimer?.isActive ?? false} whenLifted=$_saveWhenLifted coverStale=$_coverStale');
      index.detach(id, source);
      if ((_saveTimer?.isActive ?? false) || _saveWhenLifted) {
        flush();
      } else if (_coverStale) {
        _refreshCover();
      }
      _saveTimer?.cancel();
      for (final p in pages) {
        p.dispose();
      }
      images.dispose();
      docs.dispose();
      pictures.removeListener(_mathTypeset);
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

  PageRuntime _runtime(BoardPage page) => PageRuntime(page, images: _images.lookup, docs: _docs, math: _math);

  /// Math typeset for drawing, here and in exports.
  MathPictures get mathPictures => _math;

  /// The notebook's Word, PowerPoint and Excel files, for drawing their cards.
  OfficeSource get docs => _docs;

  /// An Office file ready to show (read now if it isn't yet), or null if it
  /// is missing, locked or can't be read. For exports and opening.
  Future<OfficePreview?> loadOffice(String asset, OfficeKind kind) => _docs.load(asset, kind);

  bool canUndo(String pageId) => _undo[pageId]?.isNotEmpty ?? false;

  bool canRedo(String pageId) => _redo[pageId]?.isNotEmpty ?? false;

  void _apply(Command c) {
    final page = _pageById(c.pageId);
    if (page == null) return;
    for (final s in c.steps) {
      switch (s) {
        case InsertStep():
          page.insert(_freshest(s.item), s.at);
        case RemoveStep():
          page.remove(s.item.id);
        case ReplaceStep():
          page.replace(_freshest(s.item));
      }
    }
    if (c.head case (_, final to)?) {
      page.page
        ..title = to.title
        ..color = to.color
        ..paper = to.paper
        ..template = to.template;
      // The paper and the template's layout are drawn again.
      page.invalidate();
    }
  }

  /// [item], with the furthest transcript its recording has had: its
  /// transcript is made in the background, not as an undo step, so an
  /// older copy of the card (from Undo) gets it back.
  Item _freshest(Item item) {
    if (item is! Transcribed) return item;
    final clip = item as Transcribed;
    final known = _clips[item.id];
    if (known == null || !_ahead(known, clip)) {
      _clips[item.id] = clip;
      return item;
    }
    // The lines this copy has stay as they are (they may have been edited:
    // Undo puts them back as they were), with the speakers found since;
    // the lines heard after them follow.
    final cut = clip.transcript.lastOrNull?.endMs ?? -1;
    final speakers = {for (final l in known.transcript) l.tMs: l.speaker};
    final transcript = [
      for (final l in clip.transcript) l.speaker == null && speakers[l.tMs] != null ? l.copyWith(speaker: speakers[l.tMs]) : l,
      for (final l in known.transcript)
        if (l.tMs >= cut) l,
    ];
    return clip.withTranscript(transcript: transcript, state: known.state, upToMs: known.upToMs, language: known.language) as Item;
  }

  static int _rank(Transcribed a) => switch (a.state) {
        TranscriptState.none => -1,
        TranscriptState.failed => 0,
        TranscriptState.waiting => 1,
        TranscriptState.working => 2,
        TranscriptState.done => 3,
      };

  /// Whether [a]'s transcript has got further than [b]'s. Two finished
  /// ones are even: a difference between them is an edit (an undo step).
  static bool _ahead(Transcribed a, Transcribed b) {
    final ra = _rank(a), rb = _rank(b);
    if (ra != rb) return ra > rb;
    if (a.state == TranscriptState.done) return false;
    if (a.upToMs != b.upToMs) return a.upToMs > b.upToMs;
    return a.transcript.length > b.transcript.length;
  }

  /// Every recording in the notebook, with the page it's on.
  Iterable<(String, AudioItem)> get audioClips sync* {
    for (final p in state.pages) {
      if (state.isSealed(p.id)) continue;
      for (final i in p.items) {
        if (i is AudioItem) yield (p.id, i);
      }
    }
  }

  /// The recording [itemId] and the page it's on, if it's on one.
  (String, AudioItem)? audioClip(String itemId) => switch (mediaClip(itemId)) {
        (final page, final AudioItem a) => (page, a),
        _ => null,
      };

  /// Every recording and video in the notebook, with the page it's on.
  Iterable<(String, Transcribed)> get mediaClips sync* {
    for (final p in state.pages) {
      if (state.isSealed(p.id)) continue;
      for (final i in p.items) {
        if (i is Transcribed) yield (p.id, i as Transcribed);
      }
    }
  }

  /// The recording or video [itemId] and the page it's on.
  (String, Transcribed)? mediaClip(String itemId) {
    for (final c in mediaClips) {
      if (c.$2.id == itemId) return c;
    }
    return null;
  }

  /// The video [itemId] and the page it's on.
  (String, VideoItem)? videoClip(String itemId) => switch (mediaClip(itemId)) {
        (final page, final VideoItem v) => (page, v),
        _ => null,
      };

  /// Updates recording [clip]'s transcript where it is now, without an undo
  /// step. Its other fields (name, place) stay as they are on the page.
  /// False if it isn't on a page any more (deleted, or its page locked).
  bool setTranscript(Transcribed clip) {
    final found = mediaClip(clip.id);
    if (found == null) return false;
    final (pageId, now) = found;
    final updated = now.withTranscript(
      transcript: clip.transcript,
      state: clip.state,
      upToMs: clip.upToMs,
      language: clip.language,
    );
    _clips[clip.id] = updated;
    setQuietly(pageId, updated as Item);
    return true;
  }

  /// Stores a recording in the notebook's assets (sealed on a page with a
  /// password) and returns its asset name; null if the page can't be
  /// written to.
  Future<String?> storeAudio(String pageId, Uint8List bytes, String extension) => storeMedia(pageId, bytes, extension);

  /// Stores a recording, video or still in the notebook's assets (sealed
  /// on a page with a password) and returns its asset name; null if the
  /// page can't be written to.
  Future<String?> storeMedia(String pageId, Uint8List bytes, String extension) async {
    if (!_editable(pageId)) return null;
    final key = _keyFor(pageId);
    if (key == null && _needsKey(pageId)) return null;
    final name = assetNameFor(bytes, ext: extension);
    await _queue.run(() async => key == null
        ? _store.saveAsset(id, name, bytes)
        : _store.saveAsset(id, '$name.enc', await _crypto.sealBytes(key, bytes)));
    return ref.mounted && _editable(pageId) ? name : null;
  }

  /// Whether [pageId] is kept sealed (it has a password).
  bool isProtected(String pageId) => _keyFor(pageId) != null || _needsKey(pageId);

  /// Where asset [name] is stored in the clear, as a file (to play or read
  /// without loading it); null if it's sealed or the store keeps no files.
  Future<String?> assetPath(String name) async {
    await _queue.idle;
    return _store.assetPath(id, name);
  }

  void _changed(String pageId) {
    _dirtyPages.add(pageId);
    _contentChanged = true;
    _scheduleSave();
    // Its handwriting is read once the pen rests.
    _index.pageChanged(id, pageId);
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
    _inkMoments.wrote(id, [stroke]);
  }

  bool _editable(String pageId) => _pageById(pageId) != null && !state.isSealed(pageId);

  /// Swaps in a new version of an item without an undo step: which page of
  /// an Office file shows. Undo still puts back the item as it was before
  /// an edit, page and all, so you see what was undone.
  void setQuietly(String pageId, Item item) {
    if (!_editable(pageId)) return;
    final page = _pageById(pageId)!;
    if (page[item.id] == null) return;
    page.replace(item);
    _changed(page.id);
  }

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

  /// Sets the words spell check ignores on a page. Not an undo step, and
  /// not an edit of the page's content.
  void setSpellIgnore(String pageId, List<String> words) {
    if (!_editable(pageId)) return;
    _pageById(pageId)!.page.spellIgnore
      ..clear()
      ..addAll(words);
    _dirtyPages.add(pageId);
    _scheduleSave();
    state = state.copyWith(revision: state.revision + 1, saveStatus: SaveStatus.saving);
  }

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
    _inkMoments.wrote(id, insert.whereType<StrokeItem>());
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

  /// Stores a Word, PowerPoint or Excel file in the notebook's assets and
  /// puts its card on the page, centered on [center] (one undo step).
  /// Returns null if the page can't be written to; throws
  /// [OfficeReadError] if [bytes] isn't a file the board can show.
  Future<OfficeItem?> addOffice(String pageId, Uint8List bytes, {required String name, required Offset center}) async {
    if (!_editable(pageId)) return null;
    final key = _keyFor(pageId);
    if (key == null && _needsKey(pageId)) return null;
    final kind = officeKindOf(bytes);
    if (kind == null) throw const OfficeReadError('This file isn’t a Word, PowerPoint or Excel file.');
    final doc = await ref.read(officeParserProvider)(bytes, kind);
    final preview = OfficePreview(doc, bytes, decode: _decode);
    final asset = assetNameFor(bytes, ext: kind.name);
    try {
      await _queue.run(() async => key == null
          ? _store.saveAsset(id, asset, bytes)
          : _store.saveAsset(id, '$asset.enc', await _crypto.sealBytes(key, bytes)));
    } on Object {
      preview.dispose();
      rethrow;
    }
    if (!ref.mounted || !_editable(pageId)) {
      preview.dispose();
      return null;
    }
    _docs.put(asset, preview);
    final item = newOfficeCard(
      kind,
      preview,
      asset: asset,
      name: name,
      center: center,
      z: _pageById(pageId)!.nextZ,
      now: _clock().toUtc(),
    );
    insertItems(pageId, [item]);
    return item;
  }

  /// Puts [bytes], a newer version of the file on card [itemId], in the
  /// notebook and shows it on the card (one undo step). Each page's ink
  /// goes where that page is now: slides and sheets are followed by their
  /// ids, however they were moved. Returns null when there's nothing to do
  /// (the same file, the card or page gone or locked); throws
  /// [OfficeReadError] if [bytes] isn't a file of the card's kind.
  Future<OfficeUpdate?> updateOffice(String pageId, String itemId, Uint8List bytes) async {
    if (!_editable(pageId)) return null;
    final key = _keyFor(pageId);
    if (key == null && _needsKey(pageId)) return null;
    final card = _pageById(pageId)![itemId];
    if (card is! OfficeItem || card.kind == null) return null;
    final kind = card.kind!;
    if (officeKindOf(bytes) != kind) throw OfficeReadError('This isn’t a ${kind.noun} any more.');
    final asset = assetNameFor(bytes, ext: kind.name);
    if (asset == card.asset) return null;
    final doc = await ref.read(officeParserProvider)(bytes, kind);
    final preview = OfficePreview(doc, bytes, decode: _decode);
    final old = await _docs.load(card.asset, kind);
    try {
      await _queue.run(() async => key == null
          ? _store.saveAsset(id, asset, bytes)
          : _store.saveAsset(id, '$asset.enc', await _crypto.sealBytes(key, bytes)));
    } on Object {
      preview.dispose();
      rethrow;
    }
    // The card as it is now (it may have changed while the file was read).
    final now = _editable(pageId) ? _pageById(pageId)![itemId] : null;
    if (!ref.mounted || now is! OfficeItem) {
      preview.dispose();
      return null;
    }
    final count = math.max(1, preview.pageCount);
    final moves = pageMoves(old?.doc, doc, {...now.inkByPage.keys, now.page});
    final ink = <int, List<StrokeItem>>{};
    var lost = 0;
    for (final e in now.inkByPage.entries) {
      final to = moves[e.key];
      if (to == null) {
        lost++;
      } else {
        ink[to] = [...?ink[to], ...e.value];
      }
    }
    _docs.put(asset, preview);
    final updated = now.withFile(
      asset: asset,
      pages: count,
      pageSize: preview.pageSize,
      page: (moves[now.page] ?? now.page).clamp(1, count).toInt(),
      inkByPage: ink,
    );
    replaceItems(pageId, [updated]);
    return OfficeUpdate(updated, lostPages: lost);
  }

  /// Adds [pages] after page [after] (default: at the end), storing [files]
  /// (asset name → bytes) first, and returns the first new page's index.
  /// In a notebook with a password the files are sealed with its key; null
  /// if it is locked right now.
  Future<int?> addPagesWithFiles(List<BoardPage> pages, Map<String, Uint8List> files, {int? after}) async {
    final key = _notebookKey;
    if (key == null && _lock.notebook != null) return null;
    await _queue.run(() async {
      for (final e in files.entries) {
        if (key == null) {
          await _store.saveAsset(id, e.key, e.value);
        } else {
          await _store.saveAsset(id, '${e.key}.enc', await _crypto.sealBytes(key, e.value));
        }
      }
    });
    if (!ref.mounted) return null;
    final nb = state.notebook;
    final at = after == null ? state.pages.length : (after + 1).clamp(0, state.pages.length);
    for (final (i, page) in pages.indexed) {
      nb.pageIds.insert(at + i, page.id);
      state.pages.insert(at + i, _runtime(page));
      _changed(page.id);
    }
    _metaDirty = true;
    return at;
  }

  /// An `assets/` file in the clear (opened with a key held now), or null
  /// if it is missing or locked. For exports.
  Future<Uint8List?> readAsset(String name) => _readAsset(name);

  // Image files.

  /// A formula is typeset: pages with math are drawn again.
  void _mathTypeset() {
    if (!ref.mounted) return;
    var any = false;
    for (final p in state.pages) {
      if (p.items.any((i) => i is MathItem || i is GraphItem)) {
        p.invalidate();
        any = true;
      }
    }
    if (any) state = state.copyWith(revision: state.revision + 1);
  }

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

  /// Applies [steps] as one undo step; with [head], the page's own settings
  /// change in the same step.
  void _commit(PageRuntime page, List<EditStep> steps, {(PageHead, PageHead)? head}) {
    if (steps.isEmpty && head == null) return;
    final c = Command(page.id, _withCharts(page, _withConnectors(page, steps)), head: head);
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

  /// [steps] plus what they do to charts, in the same undo step: a chart
  /// following a table or Excel card that changed reads its numbers again,
  /// and one whose source is removed keeps them, as a snapshot.
  List<EditStep> _withCharts(PageRuntime page, List<EditStep> steps) {
    final changed = <String, Item>{};
    final removed = <String>{};
    final inserted = <String>{};
    final charts = <String, int>{}; // replaced charts: where their step is
    for (final (i, s) in steps.indexed) {
      switch (s) {
        case ReplaceStep(item: final ChartItem chart):
          charts[chart.id] = i;
        case ReplaceStep(item: final CardItem card) when card.data is TableData:
          changed[card.id] = card;
        case ReplaceStep(item: final OfficeItem f) when f.mime == 'xlsx':
          changed[f.id] = f;
        case RemoveStep(item: final item):
          removed.add(item.id);
        case InsertStep(item: final item):
          inserted.add(item.id);
        default:
          break;
      }
    }
    // Moved in the z-order (To front, To back), not gone.
    removed.removeAll(inserted);
    if (changed.isEmpty && removed.isEmpty) return steps;
    final out = [...steps];
    for (final (at, item) in page.items.indexed) {
      if (item is! ChartItem || removed.contains(item.id) || inserted.contains(item.id)) continue;
      final step = charts[item.id];
      final now = step == null ? item : out[step].item as ChartItem;
      final ref = now.live ? now.source!.ref : null;
      if (ref == null) continue;
      final ChartItem? next;
      if (removed.contains(ref)) {
        next = now.copyWith(linked: false);
      } else if (changed[ref] case final source?) {
        next = refreshedChart(now, source, book: _workbookOf(source));
      } else {
        next = null;
      }
      if (next == null) continue;
      if (step != null) {
        final s = out[step] as ReplaceStep;
        out[step] = ReplaceStep(s.at, next, s.before);
      } else {
        out.add(ReplaceStep(at, next, item));
      }
    }
    return out;
  }

  /// An Excel card's workbook, if it has been read.
  Workbook? _workbookOf(Item item) => item is OfficeItem && item.kind == OfficeKind.xlsx
      ? switch (_docs.preview(item.asset, OfficeKind.xlsx)?.doc) {
          final Workbook book => book,
          _ => null,
        }
      : null;

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

  /// Rubs ink off a sticky note or an Office file's page during an eraser
  /// drag.
  void eraseInk(String holderId, Set<String> inkIds) {
    final steps = _erasing;
    final page = _erasePage == null ? null : _pageById(_erasePage!);
    if (steps == null || page == null) return;
    if (page[holderId] case final BoxItem before when before is InkHolder) {
      final holder = before as InkHolder;
      if (!holder.ink.any((s) => inkIds.contains(s.id))) return;
      final after = holder.withoutInk(inkIds);
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
    // A checklist's entries rubbed out go once the eraser lifts.
    final page = _pageById(pageId);
    for (final id in {for (final s in steps) if (s.item is ChecklistItem) s.item.id}) {
      if (page?[id] case final ChecklistItem list when !identical(list.pruned, list)) {
        steps.add(ReplaceStep(page!.items.indexOf(list), list.pruned, list));
        page.replace(list.pruned);
      }
    }
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
    state.pages.insert(at, _runtime(page));
    _metaDirty = true;
    _changed(page.id);
    return at;
  }

  // Pages (the page bar, Canvas.dc.html).

  /// Renames page [pageId]. Not an undo step (the page bar's Rename).
  void renamePage(String pageId, String title) {
    final page = _pageById(pageId);
    if (page == null || state.isSealed(pageId) || page.page.title == title) return;
    page.page.title = title;
    _changed(pageId);
  }

  /// Sets page [pageId]'s color (null for none). Not an undo step.
  void setPageColor(String pageId, Color? color) {
    final page = _pageById(pageId);
    if (page == null || state.isSealed(pageId) || page.page.color == color) return;
    page.page.color = color;
    _changed(pageId);
  }

  /// Sets page [pageId]'s paper and template (Edit page). Not an undo step.
  void setPagePaper(String pageId, {Paper? paper, Object? Function()? template}) {
    final page = _pageById(pageId);
    if (page == null || state.isSealed(pageId)) return;
    if (paper != null) page.page.paper = paper;
    if (template != null) page.page.template = template();
    page.invalidate();
    _changed(pageId);
  }

  /// When page [pageId] was last changed: now if it has changes not
  /// written yet, otherwise when its file was written.
  Future<DateTime?> pageEdited(String pageId) async {
    if (_dirtyPages.contains(pageId)) return _clock();
    return _store.pageWritten(id, pageId);
  }

  /// Why page [pageId] can't be copied or moved out, or null if it can. A
  /// page with its own password would lose it, and a page of a notebook
  /// with a password would leave its protection.
  String? cantCopyOut(String pageId, {bool moving = false}) {
    if (state.isSealed(pageId)) return 'Unlock this page first.';
    if (state.hasPageLock(pageId)) return 'Remove this page’s password first.';
    if (moving && state.notebookLocked) return 'Pages of a notebook with a password stay in it.';
    return null;
  }

  /// Why page [pageId] can't be deleted, or null if it can.
  String? cantDelete(String pageId) {
    if (state.pages.length < 2) return 'A notebook keeps at least one page.';
    if (state.isSealed(pageId)) return 'Unlock this page to delete it.';
    if (state.hasPageLock(pageId)) return 'Remove this page’s password first.';
    return null;
  }

  /// Adds a copy of page [pageId] after it ("… (copy)", new item ids) and
  /// returns its index, or null if it can't be copied ([cantCopyOut]).
  int? duplicatePage(String pageId) {
    final i = state.indexOf(pageId);
    if (i < 0 || cantCopyOut(pageId) != null) return null;
    final copy = copyPage(state.pages[i].page);
    copy.title = state.pages[i].page.title.isEmpty ? '' : '${state.pages[i].page.title} (copy)';
    final nb = state.notebook;
    nb.pageIds.insert(i + 1, copy.id);
    state.pages.insert(i + 1, _runtime(copy));
    _metaDirty = true;
    _changed(copy.id);
    return i + 1;
  }

  /// Takes page [pageId] out of the notebook and returns it with its index,
  /// to put back with [restorePage] (Undo), or null if it can't go
  /// ([cantDelete]).
  (BoardPage, int)? removePage(String pageId, {bool force = false}) {
    final i = state.indexOf(pageId);
    if (i < 0 || (!force && cantDelete(pageId) != null)) return null;
    final runtime = state.pages.removeAt(i);
    state.notebook.pageIds.remove(pageId);
    _dirtyPages.remove(pageId);
    _undo.remove(pageId);
    _redo.remove(pageId);
    final page = runtime.page;
    runtime.dispose();
    _metaDirty = true;
    _contentChanged = true;
    _scheduleSave();
    _index.pageChanged(id, pageId);
    state = state.copyWith(revision: state.revision + 1, saveStatus: SaveStatus.saving);
    return (page, i);
  }

  /// Puts back a page taken out with [removePage] (or moved here), at [at].
  void restorePage(BoardPage page, int at) {
    if (state.indexOf(page.id) >= 0) return;
    final to = at.clamp(0, state.pages.length);
    state.notebook.pageIds.insert(to, page.id);
    state.pages.insert(to, _runtime(page));
    _metaDirty = true;
    _changed(page.id);
  }

  /// Moves the page at [from] to index [to] (the All pages strip).
  void movePage(int from, int to) {
    final n = state.pages.length;
    if (from < 0 || from >= n) return;
    final dest = to.clamp(0, n - 1);
    if (dest == from) return;
    final page = state.pages.removeAt(from);
    state.pages.insert(dest, page);
    final ids = state.notebook.pageIds
      ..remove(page.id)
      ..insert(dest, page.id);
    assert(ids.length == n);
    _metaDirty = true;
    _scheduleSave();
    state = state.copyWith(revision: state.revision + 1, saveStatus: SaveStatus.saving);
  }

  /// The files page [pageId] shows (pictures, PDFs, Office files,
  /// recordings), in the clear, for copying it to another notebook. Null if
  /// one can't be read.
  Future<Map<String, Uint8List>?> filesOf(String pageId) async {
    final page = _pageById(pageId);
    if (page == null) return null;
    final out = <String, Uint8List>{};
    for (final name in _assetsOn(page.page)) {
      final bytes = await _readAsset(name);
      if (bytes == null) return null;
      out[name] = bytes;
    }
    return out;
  }

  // Sync and version history.

  /// Takes changes from another device (cloud sync): the notebook was
  /// [from] when sync read it from the disk, and is to become [to]. Only
  /// what changed between them is applied, so anything written here since
  /// stays. It isn't an undo step, and this device's undo history stays:
  /// steps find their items by id, so Undo still takes back what was done
  /// here (a page deleted on the other device loses its history with it).
  /// False if this notebook can't take them now.
  bool applyRemote(BoardDoc from, BoardDoc to) {
    if (!ref.mounted) return false;
    final nb = state.notebook;
    final nbFrom = decodeNotebook(jsonEncode(from.notebook));
    final nbTo = decodeNotebook(jsonEncode(to.notebook));
    if (nbFrom.title != nbTo.title) nb.title = nbTo.title;
    if (!listEquals(nbFrom.folderPath, nbTo.folderPath)) nb.folderPath = [...nbTo.folderPath];
    if (nbFrom.coverColor != nbTo.coverColor) nb.coverColor = nbTo.coverColor;
    if (nbFrom.pinned != nbTo.pinned) nb.pinned = nbTo.pinned;
    if (nbFrom.trashedAt != nbTo.trashedAt) nb.trashedAt = nbTo.trashedAt;
    if (nbFrom.defaultPaper != nbTo.defaultPaper) nb.defaultPaper = nbTo.defaultPaper;
    if (nbFrom.theme != nbTo.theme) nb.theme = nbTo.theme;
    if (nbFrom.saveTo != nbTo.saveTo) nb.saveTo = nbTo.saveTo;
    if (nbTo.updatedAt.isAfter(nb.updatedAt)) nb.updatedAt = nbTo.updatedAt;

    // Pages removed on the other device.
    for (final pid in from.pageIds.difference(to.pageIds)) {
      final i = state.indexOf(pid);
      if (i < 0 || state.isSealed(pid)) continue;
      state.pages.removeAt(i).dispose();
      _undo.remove(pid);
      _redo.remove(pid);
    }
    // Pages added there.
    for (final pid in to.pageIds.difference(from.pageIds)) {
      final json = to.pages[pid];
      if (json == null || state.indexOf(pid) >= 0) continue;
      state.pages.add(_runtime(decodePage(jsonEncode(json))));
      _dirtyPages.add(pid);
    }
    // The order: the other device's, with pages added here since after the
    // one before them.
    final here = [for (final p in state.pages) p.id];
    final order = mergeOrder(to.pageOrder, here, here.toSet());
    state.pages.sort((a, b) => order.indexOf(a.id).compareTo(order.indexOf(b.id)));
    nb.pageIds
      ..clear()
      ..addAll(order);

    // Pages changed there: item by item.
    for (final e in to.pages.entries) {
      final pid = e.key;
      final before = from.pages[pid];
      if (before == null || hashJson(before) == hashJson(e.value)) continue;
      final page = _pageById(pid);
      if (page == null || state.isSealed(pid)) continue;
      final was = {for (final i in (before['items'] as List? ?? const [])) (i as Map)['id'] as String: i};
      final now = [for (final i in (e.value['items'] as List? ?? const [])) (i as Map).cast<String, dynamic>()];
      final nowIds = {for (final i in now) i['id'] as String};
      for (final id in was.keys) {
        if (!nowIds.contains(id)) page.remove(id);
      }
      String? prev;
      for (final json in now) {
        final itemId = json['id'] as String;
        final old = was[itemId];
        if (old == null) {
          if (page[itemId] == null) {
            final after = prev == null ? -1 : page.items.indexWhere((i) => i.id == prev);
            page.insert(decodeItem(json), prev == null ? 0 : (after < 0 ? null : after + 1));
          }
        } else if (hashJson(old) != hashJson(json) && page[itemId] != null) {
          page.replace(_freshest(decodeItem(json)));
        }
        prev = itemId;
      }
      final head = decodePage(jsonEncode({...e.value, 'items': const []}));
      final headBefore = decodePage(jsonEncode({...before, 'items': const []}));
      if (head.title != headBefore.title) page.page.title = head.title;
      if (head.color != headBefore.color) page.page.color = head.color;
      if (head.paper != headBefore.paper) page.page.paper = head.paper;
      if (head.template != headBefore.template) page.page.template = head.template;
      if (!listEquals(head.spellIgnore, headBefore.spellIgnore)) {
        page.page.spellIgnore
          ..clear()
          ..addAll(head.spellIgnore);
      }
      _dirtyPages.add(pid);
      _index.pageChanged(id, pid);
    }
    _metaDirty = true;
    _scheduleSave();
    state = state.copyWith(revision: state.revision + 1, saveStatus: SaveStatus.saving);
    return true;
  }

  /// Whether there are changes not written to the disk yet.
  bool get hasUnsaved => _dirtyPages.isNotEmpty || _metaDirty;

  /// Earlier versions of page [pageId], newest first.
  Future<List<PageVersion>> versionsOf(String pageId) => _versions.list(id, pageId);

  /// Version [v] of page [pageId], or null if it can't be read (gone, or
  /// sealed with a key that isn't open).
  Future<BoardPage?> loadVersion(String pageId, PageVersion v) async {
    final bytes = await _versions.load(id, pageId, v.name);
    if (bytes == null) return null;
    try {
      if (!v.sealed) return decodePage(utf8.decode(bytes));
      for (final key in [?_keyFor(pageId), ?_notebookKey, ..._pageKeys.values]) {
        try {
          return decodePage(await _crypto.unseal(key, bytes));
        } on SecretBoxAuthenticationError {
          continue;
        }
      }
    } on Object catch (e) {
      debugPrint('Version ${v.name} unreadable: $e');
    }
    return null;
  }

  /// Puts page [pageId] back as [version] was: its items and its title,
  /// color, paper and template, all as one undo step. (The words spell
  /// check ignores stay as they are now: they're not what the page shows.)
  /// The page as it is now is kept in version history first.
  Future<bool> restoreVersion(String pageId, BoardPage version) async {
    if (!_editable(pageId)) return false;
    final page = _pageById(pageId)!;
    final key = _keyFor(pageId);
    final text = encodePage(page.page);
    await _versions.keep(id, pageId, key == null ? Uint8List.fromList(utf8.encode(text)) : await _crypto.seal(key, text),
        reason: VersionReason.restore, sealed: key != null);
    if (!ref.mounted || !_editable(pageId)) return false;
    final steps = <EditStep>[
      for (final (i, item) in page.items.indexed.toList().reversed) RemoveStep(i, item),
      for (final (i, item) in version.items.indexed) InsertStep(i, item),
    ];
    final before = _headOf(page.page), after = _headOf(version);
    _commit(page, steps, head: before == after ? null : (before, after));
    return true;
  }

  // Saving.

  void _scheduleSave() {
    if (_saveTimer?.isActive ?? false) return;
    _saveTimer = Timer(saveDelay, _autosave);
  }

  /// The pen (or a finger drawing) went down on, or came up from, a page
  /// of this notebook. An autosave due meanwhile happens as it lifts.
  set inking(bool on) {
    if (_inking == on || !ref.mounted) return;
    _inking = on;
    if (!on && _saveWhenLifted) {
      _saveWhenLifted = false;
      _autosave();
    }
  }

  void _autosave() {
    if (_inking) {
      _saveWhenLifted = true;
      diag('autosave $id waits for the pen');
      return;
    }
    final now = _clock();
    final cover = _coverAt == null || now.difference(_coverAt!) >= coverEvery;
    diag('autosave $id cover=$cover');
    flush(cover: cover);
  }

  /// The key a page is written with: its own, else the notebook's.
  Uint8List? _keyFor(String pageId) => _lock.pages.containsKey(pageId) ? _pageKeys[pageId] : _notebookKey;

  bool _needsKey(String pageId) => _lock.entryFor(pageId) != null;

  /// Writes every unsaved change now (also called when the app is
  /// backgrounded and when the notebook closes). [cover]: make the
  /// library's cover again too (see [coverEvery]).
  Future<void> flush({bool cover = true}) {
    if (kDiag) {
      final from = StackTrace.current.toString().split('\n').skip(1).take(2).map((l) => l.replaceAll(RegExp(r'\s+'), ' '));
      diagStep('flush cover=$cover dirty=${_dirtyPages.length} from ${from.join(' < ')}');
    }
    _saveTimer?.cancel();
    _saveWhenLifted = false;
    if (_dirtyPages.isEmpty && !_metaDirty) {
      // An autosave left the cover behind: catch it up.
      if (cover && _coverStale) _refreshCover();
      return _queue.idle;
    }
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
    if (cover) {
      _coverAt = _clock();
      _coverStale = false;
    } else {
      _coverStale = true;
    }
    return _queue.run(() => _write(nb, pages, allPages, sealed, written, cover: cover));
  }

  /// Whether an autosave skipped the cover since it was last made.
  bool _coverStale = false;

  void _refreshCover() {
    diag('refreshCover $id');
    _coverAt = _clock();
    _coverStale = false;
    final nb = _notebook;
    final pages = [for (final p in _pages) p.page];
    final sealed = {..._sealed.keys};
    // Queued like a save: it may come as the notebook closes.
    _queue.run(() async => _library.notebookSaved(nb, pages, sealed));
  }

  Future<void> _write(
    Notebook nb,
    List<(BoardPage, Uint8List?)> pages,
    List<BoardPage> allPages,
    Set<String> sealed,
    Set<String> written, {
    bool cover = true,
  }) async {
    try {
      // Page files first: notebook.json never lists a page that isn't written.
      // Each page is encoded once; its bytes for version history only when
      // a version is due (every 10 minutes).
      final kept = <(String, Uint8List Function(), bool)>[];
      for (final (page, key) in pages) {
        if (key == null) {
          final text = diagTime('encodePage ${page.items.length} items', () => encodePage(page));
          await diagTimeAsync('store.savePage', () => _store.savePage(nb.id, page, encoded: text));
          kept.add((page.id, () => utf8.encode(text), false));
        } else {
          final bytes = await _crypto.seal(key, encodePage(page));
          await _store.saveSealedPage(nb.id, page.id, bytes);
          kept.add((page.id, () => bytes, true));
        }
      }
      await _store.saveNotebook(nb);
      diagTime('library.notebookSaved cover=$cover', () => _library.notebookSaved(nb, allPages, sealed, cover: cover));
      _changes.changed(nb.id);
      // Version history: the page as it is now, at most every 10 minutes.
      for (final (pageId, bytes, isSealed) in kept) {
        await _versions.keepWhileEditing(nb.id, pageId, bytes, sealed: isSealed);
      }
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
    state.pages[i] = _runtime(page);
    _undo.remove(pageId);
    _redo.remove(pageId);
  }

  void _lockChanged() {
    if (!ref.mounted) return;
    state = state.copyWith(revision: state.revision + 1, sealed: {..._sealed.keys});
    // Unlocked pages become searchable (from memory only); locked ones stop.
    _index.locksChanged(id);
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
    // Pictures and files on the pages that just opened can be read now.
    _images.retryMissing();
    _docs.retryMissing();
    _lockChanged();
  }

  /// Sets a password on one page, then locks it.
  Future<void> lockPage(String pageId, String password, {String? hint, bool biometric = false}) async {
    final page = _pageById(pageId);
    if (page == null || _sealed.containsKey(pageId)) return;
    final (entry, key) = await _crypto.create(password, hint: hint, biometric: biometric);
    _lock.pages[pageId] = entry;
    // What its handwriting said leaves the search index and recognition.json.
    await _index.locked(id, pageIds: [pageId]);
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
    await _index.locked(id);
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
    _docs.evict(pictures);
    _notebookKey = null;
    _pageKeys.clear();
    _lockChanged();
  }

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
    if (_lock.entryFor(pageId) == null) _index.pageChanged(id, pageId);
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
    for (final p in uncovered) {
      _index.pageChanged(id, p.id);
    }
  }
}

/// The open notebook's pages, for the handwriting index.
class _IndexSource implements IndexSource {
  _IndexSource(this.n);

  final NotebookNotifier n;

  @override
  List<String> get pageIds => [for (final p in n._pages) p.id];

  @override
  OpenPage? page(String pageId) {
    if (n._sealed.containsKey(pageId)) return null;
    final p = n._pages.where((p) => p.id == pageId).firstOrNull;
    if (p == null) return null;
    return (page: p.page, private: n._needsKey(pageId));
  }
}
