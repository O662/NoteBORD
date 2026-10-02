import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../board/codec.dart';
import '../board/ids.dart';
import '../board/model.dart';
import '../board/store.dart';
import '../state/assets.dart';

// A `.board` file is the notebook's package folder, zipped
// (docs/BOARD_FORMAT.md). Export writes what is on disk, so locked pages
// stay sealed; import makes a new notebook from one.

/// Raised when a file can't be imported; [message] is shown as it is.
class ImportProblem implements Exception {
  const ImportProblem(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Files a `.board` may hold, and limits that keep a hostile one from
/// filling the tablet.
const _maxEntries = 50000;
const _maxTotalBytes = 2 * 1024 * 1024 * 1024;
final _pageIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,100}$');
final _assetPattern = RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9._-]{0,199}$');

/// Zips notebook [notebookId] as read from [store]. [pageIds] (in any
/// order) limits it to those pages, kept in the notebook's order. Without
/// [includeAssets] the pictures are left out (they show as empty boxes).
Future<Uint8List> exportBoardFile(
  BoardStore store,
  String notebookId, {
  Set<String>? pageIds,
  bool includeAssets = true,
}) async {
  final loaded = await store.loadNotebook(notebookId);
  if (loaded == null) throw StateError('Notebook $notebookId was not found');
  final nb = loaded.notebook;
  final pages = [
    for (final p in loaded.pages)
      if (pageIds == null || pageIds.contains(p.id)) p,
  ];
  final archive = Archive();
  void add(String name, List<int> bytes, {bool compress = true}) => archive.addFile(
        compress ? ArchiveFile.bytes(name, bytes) : ArchiveFile.noCompress(name, bytes.length, bytes),
      );

  final meta = Notebook(
    id: nb.id,
    title: nb.title,
    folderPath: nb.folderPath,
    coverColor: nb.coverColor,
    createdAt: nb.createdAt,
    updatedAt: nb.updatedAt,
    pageIds: [for (final p in pages) p.id],
    defaultPaper: nb.defaultPaper,
    theme: nb.theme,
    locked: nb.locked,
    pinned: nb.pinned,
    trashedAt: nb.trashedAt,
    extra: nb.extra,
    extraDefaults: nb.extraDefaults,
  );
  add('notebook.json', utf8.encode(encodeNotebook(meta)));

  final refs = <String>{};
  var anySealed = false;
  for (final p in pages) {
    final sealed = loaded.sealed[p.id];
    if (sealed != null) {
      anySealed = true;
      add('pages/${p.id}.json.enc', sealed, compress: false);
    } else {
      add('pages/${p.id}.json', utf8.encode(encodePage(p)));
      for (final item in p.items) {
        refs.addAll(assetRefs(item.toJson()));
      }
    }
  }

  final lock = loaded.lock;
  if (lock != null) {
    final kept = {
      for (final e in ((lock['pages'] as Map?) ?? const {}).entries)
        if (pages.any((p) => p.id == e.key)) e.key: e.value,
    };
    if (lock['notebook'] != null || kept.isNotEmpty) {
      add('lock.json', utf8.encode(const JsonEncoder.withIndent('  ').convert({...lock, 'pages': kept})));
    }
  }

  if (includeAssets) {
    for (final name in await store.listAssets(notebookId)) {
      final sealed = name.endsWith('.enc');
      final base = sealed ? name.substring(0, name.length - 4) : name;
      // The whole notebook takes every file. Some pages take the files
      // they use, and, when a locked page goes along, the sealed files
      // (which pages use them can't be read without the password).
      final wanted = pageIds == null || refs.contains(base) || (sealed && anySealed);
      if (!wanted) continue;
      final bytes = await store.loadAsset(notebookId, name);
      if (bytes != null) add('assets/$name', bytes, compress: false);
    }
  }
  return ZipEncoder().encodeBytes(archive);
}

/// What [importBoardFile] made.
class ImportedBoard {
  const ImportedBoard(this.notebookId, {this.unreadablePages = 0});

  final String notebookId;

  /// Pages whose file was damaged; they come in empty.
  final int unreadablePages;
}

/// Makes a new notebook in [folder] from the `.board` file [bytes]. It gets
/// a new id, so importing the same file twice makes two notebooks; items
/// keep their ids. Throws [ImportProblem] if it isn't a board file.
Future<ImportedBoard> importBoardFile(
  BoardStore store,
  Uint8List bytes, {
  required List<String> folder,
  required DateTime now,
}) async {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } on Object {
    throw const ImportProblem('This file isn’t a board file, or it’s damaged.');
  }
  final files = [for (final f in archive.files) if (f.isFile) f];
  if (files.length > _maxEntries || files.fold<int>(0, (n, f) => n + f.size) > _maxTotalBytes) {
    throw const ImportProblem('This board file is too large to import.');
  }

  // Our files have notebook.json at the top; a zipped package folder has it
  // one level down.
  final metaFile = files.where((f) => f.name == 'notebook.json').firstOrNull ??
      files.where((f) => RegExp(r'^[^/]+/notebook\.json$').hasMatch(f.name)).firstOrNull;
  if (metaFile == null) throw const ImportProblem('This file isn’t a board file: it has no notebook.json.');
  final root = metaFile.name.substring(0, metaFile.name.length - 'notebook.json'.length);
  final byName = {
    for (final f in files)
      if (f.name.startsWith(root)) f.name.substring(root.length): f,
  };
  Uint8List? read(String name) => byName[name]?.readBytes();

  final Notebook source;
  try {
    source = decodeNotebook(utf8.decode(read('notebook.json')!));
  } on Object {
    throw const ImportProblem('This board file’s notebook.json can’t be read.');
  }

  final id = newId('nb', now: now);
  final pageIds = <String>[];
  var unreadable = 0;
  for (final pageId in source.pageIds) {
    if (!_pageIdPattern.hasMatch(pageId) || pageIds.contains(pageId)) continue;
    pageIds.add(pageId);
    final sealed = read('pages/$pageId.json.enc');
    if (sealed != null) {
      await store.saveSealedPage(id, pageId, sealed);
      continue;
    }
    final clear = read('pages/$pageId.json');
    var page = BoardPage(id: pageId);
    if (clear != null) {
      try {
        page = decodePage(utf8.decode(clear));
      } on Object {
        unreadable++;
      }
    }
    if (page.id != pageId) {
      page = BoardPage(
        id: pageId,
        title: page.title,
        paper: page.paper,
        template: page.template,
        locked: page.locked,
        items: page.items,
        extra: page.extra,
      );
    }
    await store.savePage(id, page);
  }
  if (pageIds.isEmpty) {
    final page = BoardPage(id: newId('pg', now: now), paper: source.defaultPaper);
    pageIds.add(page.id);
    await store.savePage(id, page);
  }

  final lock = read('lock.json');
  if (lock != null) {
    try {
      await store.saveLock(id, jsonDecode(utf8.decode(lock)) as Json);
    } on Object {
      throw const ImportProblem('This board file’s password information is damaged.');
    }
  }

  for (final entry in byName.entries) {
    if (!entry.key.startsWith('assets/')) continue;
    final name = entry.key.substring('assets/'.length);
    if (!_assetPattern.hasMatch(name) || name.endsWith('.tmp')) continue;
    final data = entry.value.readBytes();
    if (data != null) await store.saveAsset(id, name, data);
  }

  // notebook.json last, so the library never lists a half-written notebook.
  await store.saveNotebook(Notebook(
    id: id,
    title: source.title,
    folderPath: [...folder],
    coverColor: source.coverColor,
    createdAt: source.createdAt,
    updatedAt: now.toUtc(),
    pageIds: pageIds,
    defaultPaper: source.defaultPaper,
    theme: source.theme,
    locked: source.locked,
    extra: source.extra,
    extraDefaults: source.extraDefaults,
  ));
  return ImportedBoard(id, unreadablePages: unreadable);
}
