import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'codec.dart';
import 'model.dart';

/// A notebook as loaded from storage: its metadata and pages in order.
class LoadedNotebook {
  LoadedNotebook(this.notebook, this.pages);

  final Notebook notebook;
  final List<BoardPage> pages;
}

/// Local-first storage. Each notebook is a `.board` package laid out as a
/// folder (docs/BOARD_FORMAT.md), so exporting is just zipping the folder.
abstract class BoardStore {
  Future<Json?> loadSettings();
  Future<void> saveSettings(Json settings);

  Future<List<String>> listNotebookIds();
  Future<LoadedNotebook?> loadNotebook(String id);
  Future<void> saveNotebook(Notebook notebook);
  Future<void> savePage(String notebookId, BoardPage page);
}

class FileBoardStore implements BoardStore {
  FileBoardStore(this.root);

  /// e.g. `<app documents>/Endless`.
  final Directory root;

  Directory get _notebooks => Directory(p.join(root.path, 'notebooks'));
  Directory _notebookDir(String id) => Directory(p.join(_notebooks.path, '$id.board'));
  File get _settingsFile => File(p.join(root.path, 'settings.json'));

  @override
  Future<Json?> loadSettings() async {
    final f = _settingsFile;
    if (!await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString()) as Json;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> saveSettings(Json settings) =>
      _writeAtomic(_settingsFile, const JsonEncoder.withIndent('  ').convert(settings));

  @override
  Future<List<String>> listNotebookIds() async {
    if (!await _notebooks.exists()) return [];
    return [
      await for (final e in _notebooks.list())
        if (e is Directory && e.path.endsWith('.board')) p.basenameWithoutExtension(e.path),
    ];
  }

  @override
  Future<LoadedNotebook?> loadNotebook(String id) async {
    final dir = _notebookDir(id);
    final meta = File(p.join(dir.path, 'notebook.json'));
    if (!await meta.exists()) return null;
    final notebook = decodeNotebook(await meta.readAsString());
    final pages = <BoardPage>[];
    for (final pageId in notebook.pageIds) {
      final f = File(p.join(dir.path, 'pages', '$pageId.json'));
      // A page listed but never written (crash before its first save) loads empty.
      pages.add(await f.exists() ? decodePage(await f.readAsString()) : BoardPage(id: pageId));
    }
    return LoadedNotebook(notebook, pages);
  }

  @override
  Future<void> saveNotebook(Notebook notebook) =>
      _writeAtomic(File(p.join(_notebookDir(notebook.id).path, 'notebook.json')), encodeNotebook(notebook));

  @override
  Future<void> savePage(String notebookId, BoardPage page) =>
      _writeAtomic(File(p.join(_notebookDir(notebookId).path, 'pages', '${page.id}.json')), encodePage(page));

  /// Write to a temp file, flush, then rename over the target, so a crash
  /// mid-write leaves the previous version intact.
  Future<void> _writeAtomic(File target, String contents) async {
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(contents, flush: true);
    await tmp.rename(target.path);
  }
}

/// In-memory store for tests.
class MemoryBoardStore implements BoardStore {
  Json? settings;
  final notebooks = <String, String>{};
  final pages = <String, Map<String, String>>{};
  int pageWrites = 0;

  @override
  Future<Json?> loadSettings() async => settings == null ? null : jsonDecode(jsonEncode(settings)) as Json;

  @override
  Future<void> saveSettings(Json s) async => settings = jsonDecode(jsonEncode(s)) as Json;

  @override
  Future<List<String>> listNotebookIds() async => notebooks.keys.toList();

  @override
  Future<LoadedNotebook?> loadNotebook(String id) async {
    final src = notebooks[id];
    if (src == null) return null;
    final nb = decodeNotebook(src);
    return LoadedNotebook(nb, [
      for (final pid in nb.pageIds)
        pages[id]?[pid] == null ? BoardPage(id: pid) : decodePage(pages[id]![pid]!),
    ]);
  }

  @override
  Future<void> saveNotebook(Notebook notebook) async => notebooks[notebook.id] = encodeNotebook(notebook);

  @override
  Future<void> savePage(String notebookId, BoardPage page) async {
    pageWrites++;
    (pages[notebookId] ??= {})[page.id] = encodePage(page);
  }
}
