import 'dart:async';
import 'dart:ui' show PlatformDispatcher, Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/model.dart';
import '../board/store.dart';
import '../library/index_db.dart';
import '../library/library.dart';
import '../canvas/math_tools.dart' show mathToolText;
import '../math/linear.dart' show mathSearchText;
import '../search/search_text.dart';
import '../state/settings.dart';
import '../study/remember.dart';
import '../study/study_rows.dart';
import '../transfer/pdf_export.dart' show HandwritingText, RecognizedHandwriting, cardText;
import 'models.dart';
import 'reader.dart';
import 'recognized.dart';
import 'recognizer.dart';

/// One page of an open notebook, as the index sees it.
typedef OpenPage = ({BoardPage page, bool private});

/// What an open notebook shows the index: its pages as they are in memory
/// (newer than the files while unsaved).
abstract interface class IndexSource {
  List<String> get pageIds;

  /// The page, or null while it is locked (its contents aren't loaded).
  /// `private` when a password protects it, even while it's unlocked.
  OpenPage? page(String pageId);
}

/// How long the pen rests before a page's handwriting is read. Null turns
/// reading as you write off (most tests; the index is then updated only
/// when asked).
final recognitionIdleProvider = Provider<Duration?>((ref) => const Duration(milliseconds: 1500));

/// How soon after a change what's remembered and the flashcards on a page
/// reach the index (the Remember and Flashcards screens read it). Null
/// leaves it to the next full read of the page.
final studyIdleProvider = Provider<Duration?>((ref) => const Duration(milliseconds: 300));

/// Whether the app goes through older notebooks after it starts, reading
/// what hasn't been read. Tests turn it off.
final catchUpOnStartProvider = Provider<bool>((ref) => true);

/// How search rows are made. Bumping it re-indexes every notebook (from
/// recognition.json, so nothing is recognized twice). 3: things to
/// remember and flashcards (Phase 7a).
const indexVersion = 3;

/// The handwriting language in use.
String handwritingLanguage(AppSettings s) =>
    s.handwritingLanguage ?? inkLanguageFor(PlatformDispatcher.instance.locale);

/// Keeps handwriting recognized and everything searchable.
///
/// - A page's handwriting is read about 1.5 s after the pen stops
///   ([pageChanged]); lines read before are reused, so only new writing
///   goes to the recognizer. The ink is never changed.
/// - What it says is kept in the notebook's `index/recognition.json`, and
///   with typed text and text inside PDFs in the search index.
/// - [catchUp] goes through notebooks changed since they were last read.
/// - Pages and notebooks with a password are never read into either, and
///   anything already there is dropped when they are locked.
class HandwritingIndex {
  HandwritingIndex(this.ref) {
    _store = ref.read(boardStoreProvider);
    _db = ref.read(indexDbProvider);
    _idle = ref.read(recognitionIdleProvider);
    _studyIdle = ref.read(studyIdleProvider);
    // Once a model arrives, what couldn't be read before is read.
    ref.listen(inkModelsProvider, (_, note) {
      if (note?.phase == ModelPhase.ready) catchUp();
    });
  }

  final Ref ref;
  late final BoardStore _store;
  late final IndexDb _db;
  late final Duration? _idle;
  late final Duration? _studyIdle;
  bool _disposed = false;

  final _sources = <String, IndexSource>{};
  final _timers = <String, Timer>{};

  /// Pages (`notebook/page`) whose things to remember and flashcards are
  /// about to be written to the index, and pages that have some there.
  final _studyTimers = <String, Timer>{};
  final _studyPages = <String>{};

  /// Notebooks whose recognition.json is behind.
  final _dirty = <String>{};

  /// What each notebook's handwriting says, page by page (loaded from
  /// recognition.json when first needed).
  final _read = <String, Map<String, PageRecognition>>{};
  final _loading = <String, Future<Map<String, PageRecognition>>>{};

  /// Work runs one task at a time, in order.
  Future<void> _tail = Future.value();

  /// How many tasks are waiting or running (the Search screen says
  /// "Reading handwriting…" meanwhile).
  final pending = ValueNotifier<int>(0);

  /// Bumped whenever the search index changes.
  final revision = ValueNotifier<int>(0);

  Future<void>? _catchingUp;

  /// Every notebook has been read since the app started (or catching up
  /// is off): the index has everything.
  bool get caughtUp => _caughtUp || !ref.read(catchUpOnStartProvider);
  bool _caughtUp = false;

  String get language => handwritingLanguage(ref.read(settingsProvider));

  InkRecognizer get _recognizer => ref.read(inkRecognizerProvider);

  /// Whether handwriting can be read on this device at all.
  bool get canRecognize => _recognizer.available;

  void attach(String notebookId, IndexSource source) => _sources[notebookId] = source;

  void detach(String notebookId, IndexSource source) {
    if (_sources[notebookId] != source) return;
    _sources.remove(notebookId);
    // Closing a notebook locks its pages again: what they said goes too.
    _forgetUnlocked(notebookId);
  }

  // Unlocked pages with a password: searchable while they're open, from
  // memory only. Never written to the index or recognition.json, and gone
  // when they lock again or their notebook closes.

  /// Search rows by notebook and page.
  final _unlockedRows = <String, Map<String, List<SearchRow>>>{};

  /// What their handwriting says, so a page isn't read twice while open.
  final _unlockedRead = <String, Map<String, PageRecognition>>{};

  /// The rows of every unlocked page with a password, for Search.
  List<SearchRow> get unlockedRows => [
        for (final pages in _unlockedRows.values)
          for (final rows in pages.values) ...rows,
      ];

  /// A page of an open notebook as it is now (for drawing a match on an
  /// unlocked page, whose file is sealed), or null.
  BoardPage? openPage(String notebookId, String pageId) => _sources[notebookId]?.page(pageId)?.page;

  void _forgetUnlocked(String notebookId, [Set<String>? pageIds]) {
    final rows = _unlockedRows[notebookId];
    final before = rows?.length ?? 0;
    if (pageIds == null) {
      _unlockedRows.remove(notebookId);
      _unlockedRead.remove(notebookId);
    } else {
      rows?.removeWhere((id, _) => pageIds.contains(id));
      _unlockedRead[notebookId]?.removeWhere((id, _) => pageIds.contains(id));
    }
    final after = pageIds == null ? 0 : rows?.length ?? 0;
    if (after != before) _changed();
  }

  /// A notebook's pages were unlocked or locked: unlocked pages with a
  /// password are read into memory, and locked ones forgotten.
  void locksChanged(String notebookId) {
    final source = _sources[notebookId];
    if (source == null) return _forgetUnlocked(notebookId);
    final gone = {
      for (final id in [...?_unlockedRows[notebookId]?.keys])
        if (source.page(id) case final open when open == null || !open.private) id,
    };
    if (gone.isNotEmpty) _forgetUnlocked(notebookId, gone);
    for (final id in source.pageIds) {
      final open = source.page(id);
      if (open != null && open.private && !(_unlockedRows[notebookId]?.containsKey(id) ?? false)) {
        _run(() => _indexUnlocked(notebookId, id));
      }
    }
  }

  Future<void> _indexUnlocked(String notebookId, String pageId) async {
    final open = _sources[notebookId]?.page(pageId);
    if (open == null || !open.private) return;
    final page = open.page;
    final previous = _unlockedRead[notebookId]?[pageId];
    final lang = language;
    final canRead = hasHandwriting(page) && await ref.read(inkModelsProvider.notifier).ensure(lang);
    final read = await readPage(page, language: lang, recognizer: canRead ? _recognizer : null, previous: previous);
    // Locked or closed while it was being read: nothing is kept.
    final still = _sources[notebookId]?.page(pageId);
    if (_disposed || still == null || !still.private) return;
    (_unlockedRead[notebookId] ??= {})[pageId] = read;
    (_unlockedRows[notebookId] ??= {})[pageId] = [
      for (final r in rowsFor(notebookId, page, read)) r.unlocked(),
    ];
    _changed();
  }

  Future<void> _run(Future<void> Function() task) {
    pending.value++;
    final done = _tail.then((_) => _disposed ? null : task());
    _tail = done.then<void>((_) {}, onError: (Object e, StackTrace st) {
      debugPrint('Handwriting index: $e\n$st');
    }).whenComplete(() {
      if (!_disposed) pending.value--;
    });
    return done;
  }

  /// Waits until everything asked for so far is done.
  Future<void> get idle => _tail;

  // Open notebooks.

  /// A page of an open notebook changed: read it once the pen has rested.
  void pageChanged(String notebookId, String pageId) {
    _studyChanged(notebookId, pageId);
    final idle = _idle;
    if (idle == null) return;
    final key = '$notebookId/$pageId';
    _timers.remove(key)?.cancel();
    _timers[key] = Timer(idle, () {
      _timers.remove(key);
      _run(() => _indexOpenPage(notebookId, pageId));
    });
  }

  /// What's remembered and the flashcards on a page go to the index soon
  /// after it changes, without waiting for its handwriting to be read.
  /// Pages with none (and none before) are left alone.
  void _studyChanged(String notebookId, String pageId) {
    final idle = _studyIdle;
    if (idle == null || _disposed) return;
    final key = '$notebookId/$pageId';
    final open = _sources[notebookId]?.page(pageId);
    if (open == null || open.private) return;
    if (!_studyPages.contains(key) && !hasStudyItems(open.page)) return;
    _studyTimers.remove(key)?.cancel();
    _studyTimers[key] = Timer(idle, () {
      _studyTimers.remove(key);
      _run(() => _studyOpenPage(notebookId, pageId));
    });
  }

  Future<void> _studyOpenPage(String notebookId, String pageId) async {
    final open = _sources[notebookId]?.page(pageId);
    if (open == null || open.private || _isPrivate(notebookId, pageId)) return;
    final read = (await _recognition(notebookId))[pageId];
    if (_disposed || _isPrivate(notebookId, pageId)) return;
    await _writeStudy(notebookId, open.page, read);
    _changed();
  }

  Future<void> _writeStudy(String notebookId, BoardPage page, PageRecognition? read) async {
    final rows = studyRowsFor(notebookId, page, read);
    final key = '$notebookId/${page.id}';
    // Even with none here now, there may be rows from before the app started.
    await _db.replacePageStudy(notebookId, page.id, rows);
    if (rows.isEmpty) {
      _studyPages.remove(key);
    } else {
      _studyPages.add(key);
    }
  }

  /// Writes what's remembered and the flashcards of pages changed just now,
  /// then waits for everything asked for so far. The Remember and
  /// Flashcards screens call this before reading the index.
  Future<void> studyNow() {
    for (final key in [..._studyTimers.keys]) {
      _studyTimers.remove(key)?.cancel();
      final at = key.indexOf('/');
      final notebookId = key.substring(0, at), pageId = key.substring(at + 1);
      _run(() => _studyOpenPage(notebookId, pageId));
    }
    return idle;
  }

  /// Reads a page of an open notebook now (no waiting for the pen).
  Future<void> indexNow(String notebookId, String pageId) {
    _timers.remove('$notebookId/$pageId')?.cancel();
    return _run(() => _indexOpenPage(notebookId, pageId));
  }

  Future<void> _indexOpenPage(String notebookId, String pageId) async {
    final source = _sources[notebookId];
    if (source == null) return;
    final open = source.page(pageId);
    if (open == null) {
      _forgetUnlocked(notebookId, {pageId});
      return _forgetPages(notebookId, {pageId});
    }
    if (open.private) {
      // Written on while unlocked: read again, into memory only.
      await _forgetPages(notebookId, {pageId});
      return _indexUnlocked(notebookId, pageId);
    }
    _forgetUnlocked(notebookId, {pageId});
    // Its password (or the notebook's) was removed.
    _private
      ..remove('$notebookId/$pageId')
      ..remove('$notebookId/*');
    await _indexPage(notebookId, open.page);
  }

  /// Pages of a notebook got a password (or the whole notebook did, with
  /// [pageIds] null): what they said leaves the index and the notebook's
  /// recognition.json right away.
  ///
  /// This doesn't wait for other work: anything being read right now checks
  /// [_private] before it writes.
  Future<void> locked(String notebookId, {Iterable<String>? pageIds}) async {
    for (final key in [..._timers.keys]) {
      if (key.startsWith('$notebookId/')) _timers.remove(key)?.cancel();
    }
    for (final key in [..._studyTimers.keys]) {
      if (key.startsWith('$notebookId/')) _studyTimers.remove(key)?.cancel();
    }
    if (pageIds == null) {
      _private.add('$notebookId/*');
      _read[notebookId] = {};
      _dirty.remove(notebookId);
      await _store.saveRecognition(notebookId, null);
      await _db.removeNotebookText(notebookId);
      _changed();
    } else {
      _private.addAll([for (final id in pageIds) '$notebookId/$id']);
      await _forgetPages(notebookId, pageIds.toSet());
    }
  }

  /// Pages (`notebook/page`) and notebooks (`notebook/*`) that got a
  /// password while the app was open: never written to the index or
  /// recognition.json, whatever was being read when it happened.
  final _private = <String>{};

  bool _isPrivate(String notebookId, String pageId) =>
      _private.contains('$notebookId/*') || _private.contains('$notebookId/$pageId');

  Future<void> _forgetPages(String notebookId, Set<String> pageIds) async {
    final read = await _recognition(notebookId);
    for (final id in pageIds) {
      if (read.remove(id) != null) _dirty.add(notebookId);
      await _db.replacePageText(notebookId, id, const []);
      await _db.replacePageStudy(notebookId, id, const []);
      _studyPages.remove('$notebookId/$id');
      _studyTimers.remove('$notebookId/$id')?.cancel();
    }
    await _save(notebookId);
    _changed();
  }

  // Reading.

  Future<Map<String, PageRecognition>> _recognition(String notebookId) async {
    final have = _read[notebookId];
    if (have != null) return have;
    return _loading[notebookId] ??= () async {
      final json = await _store.loadRecognition(notebookId);
      final pages = <String, PageRecognition>{};
      final raw = json?['pages'];
      if (raw is Map) {
        for (final e in raw.entries) {
          if (e.key is String) {
            if (PageRecognition.fromJson(e.value) case final r?) pages[e.key as String] = r;
          }
        }
      }
      _loading.remove(notebookId);
      return _read[notebookId] = pages;
    }();
  }

  /// Reads [page]'s handwriting (what's new on it) and updates the search
  /// index and, unless [save] is off, recognition.json. Never call this for
  /// a private page.
  Future<void> _indexPage(String notebookId, BoardPage page, {bool download = true, bool save = true}) async {
    final read = await _recognition(notebookId);
    final previous = read[page.id];
    final lang = language;
    final canRead = hasHandwriting(page) && await ref.read(inkModelsProvider.notifier).ensure(lang, download: download);
    if (_disposed) return;
    // Without a recognizer, what was read before (on a tablet, or in a
    // board file) is kept for the strokes still here.
    // Ink on the page, on sticky notes and on every page of Office cards.
    final now = await readPage(
      page,
      language: canRead ? lang : previous?.language ?? lang,
      recognizer: canRead ? _recognizer : null,
      previous: previous,
    );
    // Locked while it was being read: it stays out.
    if (_disposed || _isPrivate(notebookId, page.id)) return;
    if (!_same(previous, now)) {
      if (now.lines.isEmpty) {
        read.remove(page.id);
      } else {
        read[page.id] = now;
      }
      _dirty.add(notebookId);
    }
    if (save) await _save(notebookId);
    await _db.replacePageText(notebookId, page.id, rowsFor(notebookId, page, now));
    await _writeStudy(notebookId, page, now);
    _changed();
  }

  static bool _same(PageRecognition? a, PageRecognition b) {
    if (a == null) return b.lines.isEmpty;
    if (a.language != b.language || a.lines.length != b.lines.length) return false;
    for (var i = 0; i < a.lines.length; i++) {
      if (a.lines[i].key != b.lines[i].key || a.lines[i].block != b.lines[i].block) return false;
    }
    return true;
  }

  void _changed() {
    if (!_disposed) revision.value++;
  }

  Future<void> _save(String notebookId) async {
    if (!_dirty.remove(notebookId)) return;
    final read = _read[notebookId];
    if (read == null) return;
    read.removeWhere((pageId, _) => _isPrivate(notebookId, pageId));
    await _store.saveRecognition(
      notebookId,
      read.isEmpty
          ? null
          : {
              'version': 1,
              'pages': {for (final e in read.entries) e.key: e.value.toJson()},
            },
    );
  }

  /// Waits for work in hand, then writes any recognition.json still behind.
  Future<void> flush() => _run(() async {
        for (final id in [..._dirty]) {
          await _save(id);
        }
      });

  /// Notebook [notebookId] was written over (a board file replaced it):
  /// what was known about it goes, and [catchUp] reads it again.
  Future<void> forgetNotebook(String notebookId) => _run(() async {
        bool ours(String key) => key == notebookId || key.startsWith('$notebookId/');
        for (final timers in [_timers, _studyTimers]) {
          for (final key in [...timers.keys.where(ours)]) {
            timers.remove(key)!.cancel();
          }
        }
        _studyPages.removeWhere(ours);
        _dirty.remove(notebookId);
        _read.remove(notebookId);
        _loading.remove(notebookId);
        await _db.removeNotebookText(notebookId);
        _changed();
      });

  // Catching up.

  /// Goes through every notebook changed since it was last indexed (or
  /// indexed in another language), and drops notebooks that are gone.
  /// Returns when done; calls while one is running share it.
  Future<void> catchUp() {
    if (_catchingUp != null) {
      // Asked again while running (a model just arrived): once more after.
      _again = true;
      return _catchingUp!;
    }
    return _catchingUp = () async {
      do {
        _again = false;
        await _catchUp();
      } while (_again && !_disposed);
    }()
        .whenComplete(() => _catchingUp = null);
  }

  bool _again = false;

  Future<void> _catchUp() async {
    final library = ref.read(libraryProvider);
    final ids = {for (final n in library.notebooks) n.id};
    for (final gone in await _db.indexedNotebooks()) {
      if (!ids.contains(gone)) await _run(() => _db.removeNotebookText(gone));
    }
    final lang = language;
    // Notebooks indexed without the model are read again once it's here.
    final reads = canRecognize && await ref.read(inkModelsProvider.notifier).ensure(lang, download: false);
    for (final entry in library.active) {
      if (_disposed) return;
      final state = await _db.indexedState(entry.id);
      final stale = state == null ||
          !state.$1.isAtSameMomentAs(entry.updatedAt) ||
          state.$3 != indexVersion ||
          (reads && state.$2 != lang);
      if (stale) await _run(() => _indexNotebook(entry.id));
    }
    _caughtUp = true;
    _changed();
  }

  Future<void> _indexNotebook(String notebookId) async {
    final entry = ref.read(libraryProvider).byId(notebookId);
    if (entry == null) return;
    final lang = language;
    // Recorded with the index: '' when the handwriting couldn't be read.
    final readIn =
        canRecognize && await ref.read(inkModelsProvider.notifier).ensure(lang, download: false) ? lang : '';
    if (entry.locked) {
      await _store.saveRecognition(notebookId, null);
      _read[notebookId] = {};
      await _db.removeNotebookText(notebookId);
      await _db.setIndexedState(notebookId, entry.updatedAt, readIn, indexVersion);
      return;
    }
    final clear = <BoardPage>[];
    final private = <String>{};
    final source = _sources[notebookId];
    if (source != null) {
      for (final id in source.pageIds) {
        final open = source.page(id);
        if (open == null || open.private) {
          private.add(id);
        } else {
          clear.add(open.page);
        }
      }
    } else {
      final loaded = await _store.loadNotebook(notebookId);
      if (loaded == null) return;
      final lockedPages = ((loaded.lock?['pages'] as Map?) ?? const {}).keys.toSet();
      for (final p in loaded.pages) {
        if (p.locked || loaded.sealed.containsKey(p.id) || lockedPages.contains(p.id)) {
          private.add(p.id);
        } else {
          clear.add(p);
        }
      }
    }
    for (final page in clear) {
      // Old notebooks don't download a model; open ones and searches do.
      await _indexPage(notebookId, page, download: false, save: false);
    }
    final read = await _recognition(notebookId);
    final keep = {for (final p in clear) p.id};
    if (read.keys.any((id) => !keep.contains(id))) {
      read.removeWhere((id, _) => !keep.contains(id));
      _dirty.add(notebookId);
    }
    await _save(notebookId);
    await _db.removeNotebookText(notebookId, keepPages: keep);
    await _db.setIndexedState(notebookId, entry.updatedAt, readIn, indexVersion);
  }

  // For Convert to text and exports.

  /// What [strokes] say in [language], reading them now (the model is
  /// downloaded if need be). Throws [RecognitionFailed] when they can't be
  /// read on this device.
  Future<PageRecognition> read(Iterable<StrokeItem> strokes, {required String language}) async {
    if (!canRecognize) throw const RecognitionFailed('Handwriting recognition isn’t available on this device');
    if (!await ref.read(inkModelsProvider.notifier).ensure(language)) {
      throw RecognitionFailed('The ${inkLanguage(language).name} handwriting model isn’t on this tablet yet');
    }
    return readInk(strokes, language: language, recognizer: _recognizer);
  }

  /// The handwriting on [pages] for a PDF's text layer, read now where
  /// it's new (when the model is on the device; nothing is downloaded).
  /// [private] pages are read but never stored.
  Future<HandwritingText> pdfText(String notebookId, List<BoardPage> pages, {Set<String> private = const {}}) async {
    final out = <String, PageRecognition>{};
    for (final page in pages) {
      if (private.contains(page.id)) {
        if (!canRecognize || !await ref.read(inkModelsProvider.notifier).ensure(language, download: false)) continue;
        out[page.id] = await readPage(page, language: language, recognizer: _recognizer);
      } else {
        await _run(() => _indexPage(notebookId, page, download: false));
        final r = (await _recognition(notebookId))[page.id];
        if (r != null) out[page.id] = r;
      }
    }
    return RecognizedHandwriting(out);
  }

  /// What's known of a page's handwriting (nothing is read).
  Future<PageRecognition?> recognitionOf(String notebookId, String pageId) async =>
      (await _recognition(notebookId))[pageId];

  /// What a page of an open notebook says as far as it's been read: from
  /// memory for an unlocked page with a password, else as indexed. For
  /// spell check.
  Future<PageRecognition?> pageRecognition(String notebookId, String pageId) async =>
      _unlockedRead[notebookId]?[pageId] ?? (await _recognition(notebookId))[pageId];

  /// The notebook's recognition.json as it would be written, for a board
  /// file of [pageIds] (all pages when null).
  Future<Json?> recognitionJson(String notebookId, {Set<String>? pageIds}) async {
    await flush();
    final read = await _recognition(notebookId);
    final pages = {
      for (final e in read.entries)
        if (pageIds == null || pageIds.contains(e.key)) e.key: e.value.toJson(),
    };
    return pages.isEmpty ? null : {'version': 1, 'pages': pages};
  }

  void dispose() {
    _disposed = true;
    for (final t in [..._timers.values, ..._studyTimers.values]) {
      t.cancel();
    }
    _timers.clear();
    _studyTimers.clear();
    pending.dispose();
    revision.dispose();
  }
}

final handwritingIndexProvider = Provider<HandwritingIndex>((ref) {
  final index = HandwritingIndex(ref);
  ref.onDispose(index.dispose);
  return index;
});

/// The search rows for [page]: each recognized line of [read], text boxes
/// (and typed text on sticky notes and in cards), and the text of PDF pages.
List<SearchRow> rowsFor(String notebookId, BoardPage page, PageRecognition? read) {
  final rows = <SearchRow>[];
  final visible = visibleInk(page);
  final all = allInk(page);
  final holders = {for (final i in page.items) if (i is StickyItem || i is OfficeItem) i.id: i};
  if (read != null) {
    for (final line in read.lines) {
      if (line.text.isEmpty) continue;
      // Where it shows; else the note or card it's on (a slide not showing).
      final rect = lineRectOn(page, line, visible);
      if (rect == null) continue;
      var at = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      for (final id in line.strokeIds) {
        final s = all[id];
        if (s != null && s.createdAt.isAfter(at)) at = s.createdAt;
      }
      final on = holders[line.holder];
      rows.add(SearchRow(
        notebookId: notebookId,
        pageId: page.id,
        kind: SearchKind.ink,
        ref: line.key,
        text: line.text,
        context: read.blockText(line.block),
        rect: rect,
        at: at,
        data: {
          'strokes': line.strokeIds,
          'words': [
            for (final w in line.words) {'t': w.text, 's': w.strokeIds},
          ],
          if (on != null) ...{
            'holder': on.id,
            'on': on is OfficeItem ? on.mime : 'sticky',
            if (line.sub != null) 'sub': line.sub,
          },
        },
      ));
    }
  }
  SearchRow typed(Item item, String text, Rect rect, {SearchKind kind = SearchKind.typed, Json extra = const {}}) =>
      SearchRow(
        notebookId: notebookId,
        pageId: page.id,
        kind: kind,
        ref: item.id,
        text: text,
        context: text,
        rect: rect,
        at: item.createdAt,
        data: {'item': item.id, ...extra},
      );
  for (final item in page.items) {
    switch (item) {
      case TextItem t when t.text.trim().isNotEmpty:
        rows.add(typed(t, t.text.trim(), t.extent));
      case MathItem m when m.latex.trim().isNotEmpty:
        rows.add(typed(m, mathSearchText(m.latex), m.extent));
      case GraphItem g when g.functions.isNotEmpty || g.surfaces.isNotEmpty:
        rows.add(typed(g, ['Graph', for (final f in [...g.functions, ...g.surfaces]) mathSearchText(f.expr)].join(' '), g.extent));
      case MathToolItem t:
        rows.add(typed(t, mathToolText(t.data), t.extent));
      case StickyItem s:
        final text = [
          for (final i in s.items)
            if (i is TextItem && i.text.trim().isNotEmpty) i.text.trim(),
        ].join('\n');
        if (text.isNotEmpty) rows.add(typed(s, text, s.extent));
      case CardItem c:
        final text = cardText(c).trim();
        if (text.isNotEmpty) rows.add(typed(c, text, c.extent));
      case FileItem f when f.text.trim().isNotEmpty:
        rows.add(typed(f, f.text.trim(), f.extent, kind: SearchKind.pdf, extra: {
          'name': f.name,
          if (f.page != null) 'page': f.page,
        }));
      case FlashcardItem f:
        // Typed sides (a word's definition, a "why it matters").
        final text = [f.front.text, f.back.text].map((t) => t.trim()).where((t) => t.isNotEmpty).join('\n');
        if (text.isNotEmpty) rows.add(typed(f, text, f.extent, extra: {'flashcard': f.id}));
      default:
        break;
    }
  }
  // Why each thing to remember matters.
  for (final g in rememberGroups(page.items)) {
    final why = g.mark.why.trim();
    if (why.isEmpty) continue;
    rows.add(SearchRow(
      notebookId: notebookId,
      pageId: page.id,
      kind: SearchKind.typed,
      ref: 'remember:${g.mark.id}',
      text: why,
      context: why,
      rect: g.area,
      at: g.mark.at ?? g.items.first.createdAt,
      data: {'remember': g.mark.id},
    ));
  }
  return rows;
}

/// Whether [page] has anything remembered or a flashcard on it.
bool hasStudyItems(BoardPage page) => page.items.any((i) => i.remember != null || i is FlashcardItem);
