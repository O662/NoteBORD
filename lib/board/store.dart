import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'codec.dart';
import 'model.dart';

/// A notebook as loaded from storage: its metadata and pages in order.
class LoadedNotebook {
  LoadedNotebook(this.notebook, this.pages, {Map<String, Uint8List>? sealed, this.lock})
      : sealed = sealed ?? {};

  final Notebook notebook;

  /// A sealed (locked) page appears here as an empty placeholder with
  /// `locked: true`; its encrypted contents are in [sealed].
  final List<BoardPage> pages;
  final Map<String, Uint8List> sealed;

  /// lock.json, if the notebook or any page has a password.
  final Json? lock;
}

/// Local-first storage. Each notebook is a `.board` package laid out as a
/// folder (docs/BOARD_FORMAT.md), so exporting is just zipping the folder.
///
/// ```
/// <root>/settings.json
/// <root>/handwriting.json             the user's handwriting sample (spell check)
/// <root>/library.json                 folders and their colors
/// <root>/decks.json                   flashcard decks (for every notebook)
/// <root>/calendar.json                calendars and events (on this tablet, and synced ones)
/// <root>/planner.json                 the planner: top 3, to-dos, notes for each day
/// <root>/templates/<id>.json          "My templates"
/// <root>/notebooks/<id>.board/        one package per notebook
/// ```
///
/// A package's `assets/` holds its images, named by content
/// (`<sha256>.<ext>`). On a locked page or notebook they are stored sealed,
/// as `<name>.enc`.
abstract class BoardStore {
  Future<Json?> loadSettings();
  Future<void> saveSettings(Json settings);

  /// `handwriting.json`: the user's handwriting sample, for writing
  /// spelling fixes in their hand. Stays on this device: it's in no
  /// notebook and no board file.
  Future<Json?> loadHandwriting();

  /// Writes it ([json] null deletes it).
  Future<void> saveHandwriting(Json? json);

  Future<Json?> loadLibrary();
  Future<void> saveLibrary(Json library);

  Future<List<String>> listNotebookIds();

  /// notebook.json only, for listing without reading pages.
  Future<Notebook?> loadNotebookMeta(String id);
  Future<LoadedNotebook?> loadNotebook(String id);
  Future<void> saveNotebook(Notebook notebook);

  /// Writes a page in the clear (and removes any sealed copy).
  Future<void> savePage(String notebookId, BoardPage page);

  /// Writes a locked page's encrypted contents (and removes any clear copy).
  Future<void> saveSealedPage(String notebookId, String pageId, Uint8List sealed);
  Future<void> saveLock(String notebookId, Json? lock);

  /// Removes the whole package. Used by "Delete forever".
  Future<void> deleteNotebook(String id);

  /// File names in the package's `assets/` folder.
  Future<List<String>> listAssets(String notebookId);
  Future<Uint8List?> loadAsset(String notebookId, String name);
  Future<void> saveAsset(String notebookId, String name, Uint8List bytes);
  Future<void> deleteAsset(String notebookId, String name);

  Future<List<Json>> loadTemplates();
  Future<void> saveTemplate(String id, Json template);
  Future<void> deleteTemplate(String id);

  /// `index/recognition.json`: what the notebook's handwriting says, page by
  /// page. Never holds a locked page.
  Future<Json?> loadRecognition(String notebookId);

  /// Writes it ([json] null removes it). Does nothing if the notebook is
  /// gone, so a late write can't bring back a deleted one.
  Future<void> saveRecognition(String notebookId, Json? json);

  /// `study.json`: how well each of the notebook's flashcards is known.
  Future<Json?> loadStudy(String notebookId);

  /// Writes it. Does nothing if the notebook is gone.
  Future<void> saveStudy(String notebookId, Json json);

  /// `decks.json`: the flashcard decks, for every notebook.
  Future<Json?> loadDecks();
  Future<void> saveDecks(Json decks);

  /// `calendar.json`: the calendars and their events.
  Future<Json?> loadCalendar();
  Future<void> saveCalendar(Json calendar);

  /// `planner.json`: what's planned for each day.
  Future<Json?> loadPlanner();
  Future<void> savePlanner(Json planner);
}

class FileBoardStore implements BoardStore {
  FileBoardStore(this.root);

  /// e.g. `<app documents>/Endless`.
  final Directory root;

  Directory get _notebooks => Directory(p.join(root.path, 'notebooks'));
  Directory get _templates => Directory(p.join(root.path, 'templates'));
  Directory _notebookDir(String id) => Directory(p.join(_notebooks.path, '$id.board'));
  File _pageFile(String nb, String page) => File(p.join(_notebookDir(nb).path, 'pages', '$page.json'));
  File _sealedFile(String nb, String page) => File(p.join(_notebookDir(nb).path, 'pages', '$page.json.enc'));
  File _lockFile(String nb) => File(p.join(_notebookDir(nb).path, 'lock.json'));
  Directory _assetDir(String nb) => Directory(p.join(_notebookDir(nb).path, 'assets'));
  File _recognitionFile(String nb) => File(p.join(_notebookDir(nb).path, 'index', 'recognition.json'));

  /// Asset names never leave the assets folder.
  File _assetFile(String nb, String name) => File(p.join(_assetDir(nb).path, p.basename(name)));

  Future<Json?> _readJson(File f) async {
    if (!await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString()) as Json;
    } on FormatException {
      return null;
    }
  }

  Future<void> _writeJson(File f, Json json) => _writeAtomic(f, const JsonEncoder.withIndent('  ').convert(json));

  @override
  Future<Json?> loadSettings() => _readJson(File(p.join(root.path, 'settings.json')));

  @override
  Future<void> saveSettings(Json settings) => _writeJson(File(p.join(root.path, 'settings.json')), settings);

  File get _handwritingFile => File(p.join(root.path, 'handwriting.json'));

  @override
  Future<Json?> loadHandwriting() => _readJson(_handwritingFile);

  @override
  Future<void> saveHandwriting(Json? json) async {
    if (json == null) return _deleteIfExists(_handwritingFile);
    await _writeAtomic(_handwritingFile, jsonEncode(json));
  }

  @override
  Future<Json?> loadLibrary() => _readJson(File(p.join(root.path, 'library.json')));

  @override
  Future<void> saveLibrary(Json library) => _writeJson(File(p.join(root.path, 'library.json')), library);

  @override
  Future<List<String>> listNotebookIds() async {
    if (!await _notebooks.exists()) return [];
    return [
      await for (final e in _notebooks.list())
        if (e is Directory && e.path.endsWith('.board')) p.basenameWithoutExtension(e.path),
    ];
  }

  @override
  Future<Notebook?> loadNotebookMeta(String id) async {
    final meta = File(p.join(_notebookDir(id).path, 'notebook.json'));
    if (!await meta.exists()) return null;
    try {
      return decodeNotebook(await meta.readAsString());
    } on FormatException {
      return null;
    }
  }

  @override
  Future<LoadedNotebook?> loadNotebook(String id) async {
    final notebook = await loadNotebookMeta(id);
    if (notebook == null) return null;
    final pages = <BoardPage>[];
    final sealed = <String, Uint8List>{};
    for (final pageId in notebook.pageIds) {
      // A sealed copy wins: a crash between writing it and removing the clear
      // copy must never leave a locked page readable.
      final enc = _sealedFile(id, pageId);
      if (await enc.exists()) {
        sealed[pageId] = await enc.readAsBytes();
        pages.add(BoardPage(id: pageId, locked: true));
        continue;
      }
      final f = _pageFile(id, pageId);
      // A page listed but never written (crash before its first save) loads empty.
      pages.add(await f.exists() ? decodePage(await f.readAsString()) : BoardPage(id: pageId));
    }
    return LoadedNotebook(notebook, pages, sealed: sealed, lock: await _readJson(_lockFile(id)));
  }

  @override
  Future<void> saveNotebook(Notebook notebook) =>
      _writeAtomic(File(p.join(_notebookDir(notebook.id).path, 'notebook.json')), encodeNotebook(notebook));

  @override
  Future<void> savePage(String notebookId, BoardPage page) async {
    await _writeAtomic(_pageFile(notebookId, page.id), encodePage(page));
    await _deleteIfExists(_sealedFile(notebookId, page.id));
  }

  @override
  Future<void> saveSealedPage(String notebookId, String pageId, Uint8List sealed) async {
    await _writeAtomicBytes(_sealedFile(notebookId, pageId), sealed);
    await _deleteIfExists(_pageFile(notebookId, pageId));
  }

  @override
  Future<void> saveLock(String notebookId, Json? lock) async {
    if (lock == null) return _deleteIfExists(_lockFile(notebookId));
    await _writeJson(_lockFile(notebookId), lock);
  }

  @override
  Future<void> deleteNotebook(String id) async {
    final dir = _notebookDir(id);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  @override
  Future<List<String>> listAssets(String notebookId) async {
    final dir = _assetDir(notebookId);
    if (!await dir.exists()) return [];
    return [
      await for (final e in dir.list())
        if (e is File && !e.path.endsWith('.tmp')) p.basename(e.path),
    ];
  }

  @override
  Future<Uint8List?> loadAsset(String notebookId, String name) async {
    final f = _assetFile(notebookId, name);
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> saveAsset(String notebookId, String name, Uint8List bytes) =>
      _writeAtomicBytes(_assetFile(notebookId, name), bytes);

  @override
  Future<void> deleteAsset(String notebookId, String name) => _deleteIfExists(_assetFile(notebookId, name));

  @override
  Future<List<Json>> loadTemplates() async {
    if (!await _templates.exists()) return [];
    final out = <Json>[];
    await for (final e in _templates.list()) {
      if (e is File && e.path.endsWith('.json')) {
        final j = await _readJson(e);
        if (j != null) out.add(j);
      }
    }
    return out;
  }

  @override
  Future<void> saveTemplate(String id, Json template) => _writeJson(File(p.join(_templates.path, '$id.json')), template);

  @override
  Future<void> deleteTemplate(String id) => _deleteIfExists(File(p.join(_templates.path, '$id.json')));

  @override
  Future<Json?> loadRecognition(String notebookId) => _readJson(_recognitionFile(notebookId));

  @override
  Future<void> saveRecognition(String notebookId, Json? json) async {
    if (json == null) return _deleteIfExists(_recognitionFile(notebookId));
    if (!await File(p.join(_notebookDir(notebookId).path, 'notebook.json')).exists()) return;
    // Compact: it's a cache, and can be large.
    await _writeAtomic(_recognitionFile(notebookId), jsonEncode(json));
  }

  File _studyFile(String nb) => File(p.join(_notebookDir(nb).path, 'study.json'));

  @override
  Future<Json?> loadStudy(String notebookId) => _readJson(_studyFile(notebookId));

  @override
  Future<void> saveStudy(String notebookId, Json json) async {
    if (!await File(p.join(_notebookDir(notebookId).path, 'notebook.json')).exists()) return;
    await _writeAtomic(_studyFile(notebookId), jsonEncode(json));
  }

  File get _decksFile => File(p.join(root.path, 'decks.json'));

  @override
  Future<Json?> loadDecks() => _readJson(_decksFile);

  @override
  Future<void> saveDecks(Json decks) => _writeJson(_decksFile, decks);

  @override
  Future<Json?> loadCalendar() => _readJson(File(p.join(root.path, 'calendar.json')));

  @override
  Future<void> saveCalendar(Json calendar) => _writeAtomic(File(p.join(root.path, 'calendar.json')), jsonEncode(calendar));

  @override
  Future<Json?> loadPlanner() => _readJson(File(p.join(root.path, 'planner.json')));

  @override
  Future<void> savePlanner(Json planner) => _writeAtomic(File(p.join(root.path, 'planner.json')), jsonEncode(planner));

  static Future<void> _deleteIfExists(File f) async {
    if (await f.exists()) await f.delete();
  }

  /// Write to a temp file, flush, then rename over the target, so a crash
  /// mid-write leaves the previous version intact.
  Future<void> _writeAtomic(File target, String contents) async {
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(contents, flush: true);
    await tmp.rename(target.path);
  }

  Future<void> _writeAtomicBytes(File target, Uint8List bytes) async {
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(target.path);
  }
}

/// In-memory store for tests.
class MemoryBoardStore implements BoardStore {
  Json? settings;
  Json? library;
  final notebooks = <String, String>{};
  final pages = <String, Map<String, String>>{};
  final sealedPages = <String, Map<String, Uint8List>>{};
  final locks = <String, Json>{};
  final templates = <String, Json>{};
  final assets = <String, Map<String, Uint8List>>{};
  final recognition = <String, String>{};
  int pageWrites = 0;

  static Json _copy(Json j) => jsonDecode(jsonEncode(j)) as Json;

  @override
  Future<Json?> loadSettings() async => settings == null ? null : _copy(settings!);

  @override
  Future<void> saveSettings(Json s) async => settings = _copy(s);

  Json? handwriting;

  @override
  Future<Json?> loadHandwriting() async => handwriting == null ? null : _copy(handwriting!);

  @override
  Future<void> saveHandwriting(Json? json) async => handwriting = json == null ? null : _copy(json);

  @override
  Future<Json?> loadLibrary() async => library == null ? null : _copy(library!);

  @override
  Future<void> saveLibrary(Json l) async => library = _copy(l);

  @override
  Future<List<String>> listNotebookIds() async => notebooks.keys.toList();

  @override
  Future<Notebook?> loadNotebookMeta(String id) async {
    final src = notebooks[id];
    return src == null ? null : decodeNotebook(src);
  }

  @override
  Future<LoadedNotebook?> loadNotebook(String id) async {
    final nb = await loadNotebookMeta(id);
    if (nb == null) return null;
    final sealed = <String, Uint8List>{};
    final list = <BoardPage>[];
    for (final pid in nb.pageIds) {
      final enc = sealedPages[id]?[pid];
      if (enc != null) {
        sealed[pid] = enc;
        list.add(BoardPage(id: pid, locked: true));
      } else {
        final src = pages[id]?[pid];
        list.add(src == null ? BoardPage(id: pid) : decodePage(src));
      }
    }
    return LoadedNotebook(nb, list, sealed: sealed, lock: locks[id] == null ? null : _copy(locks[id]!));
  }

  @override
  Future<void> saveNotebook(Notebook notebook) async => notebooks[notebook.id] = encodeNotebook(notebook);

  @override
  Future<void> savePage(String notebookId, BoardPage page) async {
    pageWrites++;
    (pages[notebookId] ??= {})[page.id] = encodePage(page);
    sealedPages[notebookId]?.remove(page.id);
  }

  @override
  Future<void> saveSealedPage(String notebookId, String pageId, Uint8List sealed) async {
    pageWrites++;
    (sealedPages[notebookId] ??= {})[pageId] = sealed;
    pages[notebookId]?.remove(pageId);
  }

  @override
  Future<void> saveLock(String notebookId, Json? lock) async {
    if (lock == null) {
      locks.remove(notebookId);
    } else {
      locks[notebookId] = _copy(lock);
    }
  }

  @override
  Future<void> deleteNotebook(String id) async {
    notebooks.remove(id);
    pages.remove(id);
    sealedPages.remove(id);
    locks.remove(id);
    assets.remove(id);
    recognition.remove(id);
    study.remove(id);
  }

  @override
  Future<List<String>> listAssets(String notebookId) async => [...?assets[notebookId]?.keys];

  @override
  Future<Uint8List?> loadAsset(String notebookId, String name) async => assets[notebookId]?[name];

  @override
  Future<void> saveAsset(String notebookId, String name, Uint8List bytes) async =>
      (assets[notebookId] ??= {})[name] = bytes;

  @override
  Future<void> deleteAsset(String notebookId, String name) async => assets[notebookId]?.remove(name);

  @override
  Future<List<Json>> loadTemplates() async => [for (final t in templates.values) _copy(t)];

  @override
  Future<void> saveTemplate(String id, Json template) async => templates[id] = _copy(template);

  @override
  Future<void> deleteTemplate(String id) async => templates.remove(id);

  @override
  Future<Json?> loadRecognition(String notebookId) async {
    final src = recognition[notebookId];
    return src == null ? null : jsonDecode(src) as Json;
  }

  @override
  Future<void> saveRecognition(String notebookId, Json? json) async {
    if (json == null) {
      recognition.remove(notebookId);
    } else if (notebooks.containsKey(notebookId)) {
      recognition[notebookId] = jsonEncode(json);
    }
  }

  final study = <String, String>{};
  Json? decks;

  @override
  Future<Json?> loadStudy(String notebookId) async {
    final src = study[notebookId];
    return src == null ? null : jsonDecode(src) as Json;
  }

  @override
  Future<void> saveStudy(String notebookId, Json json) async {
    if (notebooks.containsKey(notebookId)) study[notebookId] = jsonEncode(json);
  }

  @override
  Future<Json?> loadDecks() async => decks == null ? null : _copy(decks!);

  @override
  Future<void> saveDecks(Json d) async => decks = _copy(d);

  Json? calendar;
  Json? planner;

  @override
  Future<Json?> loadCalendar() async => calendar == null ? null : _copy(calendar!);

  @override
  Future<void> saveCalendar(Json c) async => calendar = _copy(c);

  @override
  Future<Json?> loadPlanner() async => planner == null ? null : _copy(planner!);

  @override
  Future<void> savePlanner(Json p) async => planner = _copy(p);
}
