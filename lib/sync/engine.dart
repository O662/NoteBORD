import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../board/codec.dart';
import '../board/model.dart';
import '../board/store.dart';
import 'cloud.dart';
import 'doc.dart';
import 'root.dart';
import 'stamps.dart';
import 'versions.dart';

// Copies notebooks between this device and a cloud folder, both ways:
//
//   <folder>/endless.json             folders, decks, notebooks deleted for good
//   <folder>/<title> · <id>.board/notebook.json  the package, as on the
//   <folder>/<title> · <id>.board/pages/…        tablet, with stamps
//   <folder>/<title> · <id>.board/assets/…       (docs/BOARD_FORMAT.md, "Sync")
//   <folder>/PDF/<title>.pdf          the PDF copy, if asked for
//
// For each notebook: read the cloud's notebook.json, fetch only the files
// whose hash changed since this device last saw them, stamp what changed
// here since the last sync, merge (doc.dart), write the result here (into
// the notebook if it's open), then send what the cloud doesn't have yet,
// notebook.json last. Everything on the tablet works without any of this.

/// What the engine needs from the app.
abstract class SyncHost {
  /// Whether notebook [id] is open (its changes then go through it).
  bool isOpen(String id);

  /// Writes the open notebook's unsaved changes.
  Future<void> flush(String id);

  /// Puts [to] into the open notebook, which was [from] when it was read,
  /// keeping anything written since. False if it's not open any more or
  /// can't take these changes now (a password changed): try again later.
  bool applyOpen(String id, BoardDoc from, BoardDoc to);

  /// Notebook [id]'s files were written by sync (new, or changed while it
  /// was closed).
  Future<void> notebookWritten(String id, {required bool added});

  /// Notebook [id] was deleted for good on another device.
  Future<void> deleteNotebook(String id);

  /// Folders or decks changed on another device: from [from] to [to] (the
  /// values of [RootDoc.folders] and [RootDoc.decks]).
  Future<void> applyRoot({
    required Map<String, Object?> foldersFrom,
    required Map<String, Object?> foldersTo,
    required Map<String, Object?> decksFrom,
    required Map<String, Object?> decksTo,
  });

  /// A PDF of notebook [id] (for "Also save a PDF copy"), or null.
  Future<Uint8List?> pdfOf(String id);

  /// Runs [task] with no notebook being opened or saved meanwhile.
  Future<T> exclusive<T>(Future<T> Function() task);
}

/// What to sync.
@immutable
class SyncOptions {
  const SyncOptions({
    this.boardFiles = true,
    this.pdfCopy = false,
    this.media = true,
    this.policy = MergePolicy.mergeBoth,
    this.deviceName = 'this device',
  });

  /// Notebooks as board files (off: only PDF copies are sent).
  final bool boardFiles;
  final bool pdfCopy;

  /// Images and imported PDFs (other files, like recordings, always go).
  final bool media;
  final MergePolicy policy;

  /// What other devices' version history calls this one.
  final String deviceName;
}

/// How a sync went.
class SyncReport {
  /// Notebooks whose copy here changed (another device's changes came in).
  final changedHere = <String>{};

  /// Notebooks sent to the cloud.
  final sent = <String>{};

  /// Notebooks that couldn't sync this time (open with a password change
  /// coming in), to try again.
  final waiting = <String>{};

  /// Notebook id → when the version synced was last edited, for each
  /// notebook now the same here and in the cloud.
  final synced = <String, DateTime>{};
}

class SyncEngine {
  SyncEngine({
    required this.store,
    required this.host,
    required this.stamper,
    required this.versions,
    this.options = const SyncOptions(),
  });

  final BoardStore store;
  final SyncHost host;
  final Stamper stamper;
  final VersionStore versions;
  SyncOptions options;

  static const rootFile = 'endless.json';
  static const _pdfDir = 'PDF';

  /// Image and PDF files (left out when [SyncOptions.media] is off).
  static bool isMedia(String asset) {
    final name = asset.endsWith('.enc') ? asset.substring(0, asset.length - 4) : asset;
    return const {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.pdf'}.contains(p.extension(name).toLowerCase());
  }

  bool _sends(String asset) => options.media || !isMedia(asset);

  String _sidecar(String id) => 'nb_$id';

  /// A notebook's folder in the cloud: its title (so people can tell which
  /// is which), then its id (which is how Endless knows it).
  static String folderNameFor(String title, String id) {
    var t = title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F·]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length > 60) t = t.substring(0, 60).trim();
    while (t.endsWith('.')) {
      t = t.substring(0, t.length - 1).trim();
    }
    return t.isEmpty ? '$id.board' : '$t · $id.board';
  }

  /// The notebook id a cloud folder holds (`Title · <id>.board`, or
  /// `<id>.board` as before), or null if it isn't a notebook's.
  static String? idOfFolder(String name) {
    if (!name.endsWith('.board')) return null;
    final base = name.substring(0, name.length - 6);
    final at = base.lastIndexOf(' · ');
    final id = (at < 0 ? base : base.substring(at + 3)).trim();
    return id.isEmpty ? null : id;
  }

  /// Syncs everything with [cloud]. Throws [CloudException] when the cloud
  /// can't be reached (nothing here is lost: it's tried again later).
  ///
  /// With [only], a quick sync while writing: just those notebooks (that
  /// are on this device), both ways, and nothing else (no folders or decks,
  /// no deletions, no PDF copies: the next full sync does those).
  Future<SyncReport> syncAll(CloudDrive cloud, {Set<String>? only}) async {
    final report = SyncReport();
    final listing = await cloud.list('');
    // Notebook id → its folders (one, unless two devices named it
    // differently at the same moment).
    final remoteDirs = <String, List<String>>{};
    for (final e in listing) {
      final id = e.folder ? idOfFolder(e.name) : null;
      if (id != null) (remoteDirs[id] ??= []).add(e.name);
    }
    for (final dirs in remoteDirs.values) {
      dirs.sort();
    }
    final remoteIds = remoteDirs.keys.toSet();
    final localIds = (await store.listNotebookIds()).toSet();

    if (only != null) {
      if (!options.boardFiles) return report;
      for (final id in only.intersection(localIds)) {
        if (await _goesElsewhere(cloud, id, remoteDirs[id])) continue;
        await _syncNotebook(cloud, id, dirs: remoteDirs[id] ?? const [], report: report);
        await _handedOff(cloud, id, report);
      }
      return report;
    }

    // Notebooks deleted here since they were last synced.
    final known = {
      for (final n in await store.listSyncFiles())
        if (n.startsWith('nb_')) n.substring(3),
    };
    final deletedHere = known.difference(localIds);

    final root = await _syncRoot(cloud, deletedHere);
    final gone = root.notebooks.gone;

    if (options.boardFiles) {
      for (final id in {...localIds, ...remoteIds}) {
        final tomb = gone[id];
        if (tomb != null && !localIds.contains(id) || deletedHere.contains(id)) {
          for (final d in remoteDirs[id] ?? const <String>[]) {
            await cloud.delete(d);
          }
          await store.saveSyncFile(_sidecar(id), null);
          continue;
        }
        if (localIds.contains(id) && await _goesElsewhere(cloud, id, remoteDirs[id])) continue;
        await _syncNotebook(cloud, id, dirs: remoteDirs[id] ?? const [], tomb: tomb, report: report, local: localIds.contains(id));
        await _handedOff(cloud, id, report);
      }
    }
    if (options.pdfCopy) {
      final pdfs = <String>[];
      for (final id in localIds) {
        if (gone.containsKey(id) && !report.synced.containsKey(id)) continue;
        if (_goesTo((await store.loadNotebookMeta(id))?.saveTo, cloud.kind)) pdfs.add(id);
      }
      await _sendPdfs(cloud, pdfs, report);
    }
    return report;
  }

  // Where each notebook is saved (Update 02): a notebook goes only to its
  // own cloud (`saveTo`), or, from before there was a choice, to every
  // cloud that's on. One moved elsewhere is synced to the cloud it left
  // one last time, so that cloud's copy says where it went and other
  // devices stop syncing it there too; it isn't sent there again.

  static bool _goesTo(String? saveTo, CloudKind kind) => saveTo == null || saveTo == kind.name;

  /// Whether local notebook [id] is saved somewhere other than [cloud] and
  /// that cloud has already been told (or never had it).
  Future<bool> _goesElsewhere(CloudDrive cloud, String id, List<String>? dirs) async {
    final saveTo = (await store.loadNotebookMeta(id))?.saveTo;
    if (_goesTo(saveTo, cloud.kind)) return false;
    if (dirs == null || dirs.isEmpty) return true;
    final side = await store.loadSyncFile(_sidecar(id)) ?? {};
    return (side['left'] as Map?)?[cloud.kind.name] == saveTo;
  }

  /// Records that [cloud] has been told notebook [id] is saved elsewhere
  /// now (or forgets it, if it's saved there again).
  Future<void> _handedOff(CloudDrive cloud, String id, SyncReport report) async {
    // Not synced this time (open and busy): it's told next time.
    if (report.waiting.contains(id)) return;
    final saveTo = (await store.loadNotebookMeta(id))?.saveTo;
    final side = await store.loadSyncFile(_sidecar(id));
    if (side == null) return;
    final left = {...?(side['left'] as Map?)?.cast<String, dynamic>()};
    final was = left[cloud.kind.name];
    if (_goesTo(saveTo, cloud.kind)) {
      if (was == null) return;
      left.remove(cloud.kind.name);
    } else {
      if (was == saveTo) return;
      left[cloud.kind.name] = saveTo;
    }
    await store.saveSyncFile(_sidecar(id), {...side, 'left': left});
  }

  // The app-wide part.

  Future<RootDoc> _syncRoot(CloudDrive cloud, Set<String> deletedHere) async {
    final side = await store.loadSyncFile('root') ?? {};
    final knownFolders = _strings(side['folders']);
    final knownDecks = _strings(side['decks']);
    final prev = RootDoc.decode(jsonEncode(side['doc'] ?? {'format': 'endless.sync'}));

    final lib = await store.loadLibrary();
    final folders = <String, Object?>{
      for (final f in (lib?['folders'] as List?) ?? const [])
        if (f is Map && f['path'] is List) folderKey([...(f['path'] as List).cast<String>()]): {'path': f['path'], 'color': f['color']},
    };
    final decksJson = await store.loadDecks();
    final decks = <String, Object?>{
      for (final d in (decksJson?['decks'] as List?) ?? const [])
        if (d is Map && d['id'] is String) d['id'] as String: d,
    };
    final here = RootDoc(
      folders: stampKeyed(folders, knownFolders, prev.folders, stamper),
      decks: stampKeyed(decks, knownDecks, prev.decks, stamper),
      notebooks: Keyed(gone: {
        ...prev.notebooks.gone,
        for (final id in deletedHere) id: stamper.after(prev.notebooks.gone[id]),
      }),
    );

    final remoteBytes = await cloud.read(rootFile);
    final remote = remoteBytes == null ? null : RootDoc.decode(utf8.decode(remoteBytes));
    final merged = remote == null ? here : here.merge(remote);

    if (hashJson(merged.folders.values) != hashJson(here.folders.values) ||
        hashJson(merged.decks.values) != hashJson(here.decks.values)) {
      await host.applyRoot(
        foldersFrom: here.folders.values,
        foldersTo: merged.folders.values,
        decksFrom: here.decks.values,
        decksTo: merged.decks.values,
      );
    }
    final text = merged.encode();
    if (remoteBytes == null || utf8.decode(remoteBytes) != text) {
      await cloud.write(rootFile, Uint8List.fromList(utf8.encode(text)));
    }
    await store.saveSyncFile('root', {
      'folders': {for (final e in merged.folders.values.entries) e.key: hashJson(e.value)},
      'decks': {for (final e in merged.decks.values.entries) e.key: hashJson(e.value)},
      'doc': jsonDecode(text),
    });
    return merged;
  }

  // One notebook.

  Future<void> _syncNotebook(
    CloudDrive cloud,
    String id,
    {required List<String> dirs,
    String? tomb,
    required SyncReport report,
    bool local = true}) async {
    final remote = dirs.isNotEmpty;
    // Its folder: the one there (named as the notebook was then), or one
    // named now for a notebook new to the cloud.
    var dir = remote ? dirs.first : '';
    final side = await store.loadSyncFile(_sidecar(id)) ?? {};
    final known = Known.fromJson(side['known']);
    final seen = _strings((side['remote'] as Map?)?[cloud.kind.name]);

    // What the cloud has, fetching only files changed since last seen.
    final manifestBytes = remote ? await cloud.read('$dir/notebook.json') : null;
    RemoteManifest? manifest;
    if (manifestBytes != null) {
      try {
        manifest = RemoteManifest.decode(utf8.decode(manifestBytes));
      } on Object catch (e) {
        debugPrint('Sync: unreadable notebook.json for $id: $e');
      }
    }
    // A notebook this device doesn't have, saved to another cloud now (the
    // copy left here when it moved): it isn't brought down from this one.
    if (!local && manifest != null && !_goesTo(manifest.notebook['saveTo'] as String?, cloud.kind)) return;
    final fetched = <String, Uint8List>{};
    if (manifest != null) {
      for (final e in manifest.files.entries) {
        if (seen[e.key] == e.value) continue;
        final bytes = await cloud.read('$dir/${remoteFileName(e.key, e.value)}');
        // Gone (replaced since by another device): read again next time.
        if (bytes == null || hashBytes(bytes) != e.value) continue;
        fetched[e.key] = bytes;
      }
    }

    // Files this device doesn't have yet, fetched first (outside the time
    // saving is held up). Their names are their contents, so a file
    // fetched is never out of date.
    final fetchedAssets = <String>{};
    if (manifest != null) {
      final here = {...await store.listAssets(id)};
      for (final a in manifest.assets) {
        if (here.contains(a) || !_sends(a)) continue;
        final bytes = await cloud.read('$dir/assets/$a');
        if (bytes == null) continue;
        await store.saveAsset(id, a, bytes);
        fetchedAssets.add(a);
      }
    }

    final open = host.isOpen(id);
    if (open) await host.flush(id);
    if (!remote) {
      final meta = await store.loadNotebookMeta(id);
      dir = folderNameFor(meta?.title ?? '', id);
    }

    Future<_Outcome?> mergeAndWrite() async {
      final local = await _readLocal(id);
      if (local != null) stampChanges(local, known, stamper, editedAt: _updatedAt(local.notebook));
      if (local == null && manifest == null) return null;

      // Deleted for good on another device, and not changed here since.
      if (local != null && tomb != null && !newer(local.stamps.latest, tomb)) {
        return const _Outcome.deleted();
      }

      final remoteDoc = manifest == null ? null : _remoteDoc(manifest, fetched, local);
      final merged = remoteDoc == null
          ? local!
          : local == null
              ? remoteDoc
              : mergeDocs(local, remoteDoc, policy: options.policy);

      // What's here now (a file this device doesn't fetch stays in the
      // cloud only).
      final here = {...?local?.assets, ...fetchedAssets};
      merged.assets
        ..clear()
        ..addAll(here);

      if (local == null) {
        await _write(id, null, merged);
        return _Outcome(merged, added: true, changedHere: true);
      }
      final changes = _differs(local, merged);
      if (!changes) return _Outcome(merged);
      if (open) {
        if (_locksDiffer(local, merged)) return const _Outcome.waiting();
        await _keepVersions(id, local, merged, remoteDevice: _deviceOf(manifest));
        if (!host.applyOpen(id, local, merged)) return const _Outcome.waiting();
        return _Outcome(merged, changedHere: true, applied: true);
      }
      await _keepVersions(id, local, merged, remoteDevice: _deviceOf(manifest));
      await _write(id, local, merged);
      return _Outcome(merged, changedHere: true);
    }

    final outcome = open ? await mergeAndWrite() : await host.exclusive(mergeAndWrite);
    if (outcome == null) return;
    if (outcome.deleted) {
      await host.deleteNotebook(id);
      if (remote) await cloud.delete(dir);
      await store.saveSyncFile(_sidecar(id), null);
      return;
    }
    if (outcome.waiting) {
      report.waiting.add(id);
      return;
    }
    var doc = outcome.doc!;
    if (outcome.changedHere) report.changedHere.add(id);
    if (outcome.applied) {
      // The open notebook took the changes; send what it has now (with
      // anything written meanwhile, stamped).
      await host.flush(id);
      final now = await _readLocal(id);
      if (now != null) {
        known.stamps = doc.stamps.copy();
        known.record(doc);
        stampChanges(now, known, stamper, editedAt: _updatedAt(now.notebook));
        doc = now;
      }
    } else {
      known.record(doc);
    }
    if (!outcome.applied && !outcome.added && outcome.changedHere) {
      await host.notebookWritten(id, added: false);
    } else if (outcome.added) {
      await host.notebookWritten(id, added: true);
    }

    // Send what the cloud doesn't have.
    final files = <String, String>{};
    final sends = <String, Uint8List>{};
    for (final e in doc.pages.entries) {
      final path = 'pages/${e.key}.json';
      final text = encodeRemotePage(e.value, doc.stamps.page(e.key));
      final bytes = Uint8List.fromList(utf8.encode(text));
      files[path] = hashBytes(bytes);
      sends[path] = bytes;
    }
    for (final e in doc.sealed.entries) {
      final path = 'pages/${e.key}.json.enc';
      files[path] = hashBytes(e.value);
      sends[path] = e.value;
    }
    if (doc.lock != null) {
      final bytes = Uint8List.fromList(utf8.encode(canonicalJson(doc.lock)));
      files['lock.json'] = hashBytes(bytes);
      sends['lock.json'] = bytes;
    }
    if (doc.study != null) {
      final bytes = Uint8List.fromList(utf8.encode(canonicalJson(doc.study)));
      files['study.json'] = hashBytes(bytes);
      sends['study.json'] = bytes;
    }
    var wrote = false;
    for (final e in sends.entries) {
      if (manifest?.files[e.key] == files[e.key]) continue;
      await cloud.write('$dir/${remoteFileName(e.key, files[e.key]!)}', e.value);
      wrote = true;
    }
    // Assets: sent once (their names are their contents' hash).
    var listed = false;
    final remoteAssets = <String>{...?manifest?.assets};
    for (final a in doc.assets) {
      if (!_sends(a) || remoteAssets.contains(a)) continue;
      if (!listed) {
        listed = true;
        remoteAssets.addAll((await cloud.list('$dir/assets')).map((e) => e.name));
        if (remoteAssets.contains(a)) continue;
      }
      final path = store.assetPath(id, a);
      if (path != null) {
        await cloud.upload('$dir/assets/$a', File(path));
      } else {
        final bytes = await store.loadAsset(id, a);
        if (bytes == null) continue;
        await cloud.write('$dir/assets/$a', bytes);
      }
      remoteAssets.add(a);
      wrote = true;
    }
    final replaced = [
      for (final e in manifest?.files.entries ?? const <MapEntry<String, String>>[])
        if (files[e.key] != e.value) remoteFileName(e.key, e.value),
    ];
    final assetsThere = BoardDoc(notebook: doc.notebook, stamps: doc.stamps, assets: remoteAssets);
    final nbText = encodeRemoteNotebook(assetsThere, files);
    if (wrote || manifestBytes == null || _withoutDevice(utf8.decode(manifestBytes)) != nbText) {
      await cloud.write('$dir/notebook.json', Uint8List.fromList(utf8.encode(_withDevice(nbText))));
      report.sent.add(id);
      // The files the last notebook.json listed that this one doesn't (old
      // versions, deleted pages).
      for (final name in replaced) {
        await cloud.delete('$dir/$name');
      }
    }

    // Named after the notebook as it is now (renamed with it); a second
    // folder for it, from another device at the same moment, goes (that
    // device still has its changes, and sends them again).
    for (final extra in dirs.skip(1)) {
      await cloud.delete(extra);
    }
    final named = folderNameFor(doc.notebook['title'] as String? ?? '', id);
    if (named != dir) await cloud.rename(dir, named);

    await store.saveSyncFile(_sidecar(id), {
      'known': known.toJson(),
      'remote': {
        ...?(side['remote'] as Map?)?.cast<String, dynamic>(),
        cloud.kind.name: files,
      },
      'syncedAt': _updatedAt(doc.notebook)?.toIso8601String(),
    });
    final at = _updatedAt(doc.notebook);
    if (at != null) report.synced[id] = at;
  }

  /// Marks notebook.json with the device that wrote it last (for version
  /// history: "before Kim's tablet's changes").
  String _withDevice(String nbText) {
    final j = jsonDecode(nbText) as Json;
    (j['sync'] as Map)['device'] = options.deviceName;
    return sortedJson(j);
  }

  /// [nbText] as written before [_withDevice], to compare.
  static String _withoutDevice(String nbText) {
    try {
      final j = jsonDecode(nbText) as Json;
      (j['sync'] as Map?)?.remove('device');
      return sortedJson(j);
    } on Object {
      return nbText;
    }
  }

  static String? _deviceOf(RemoteManifest? m) => m?.device;

  BoardDoc _remoteDoc(RemoteManifest m, Map<String, Uint8List> fetched, BoardDoc? local) {
    final doc = BoardDoc(notebook: m.notebook, stamps: m.stamps.copy(), assets: {...m.assets});
    doc.stamps.pages.clear();
    for (final e in fetched.entries) {
      final path = e.key;
      if (path.startsWith('pages/') && path.endsWith('.json')) {
        final (page, stamps) = decodeRemotePage(utf8.decode(e.value));
        final pid = page['id'] as String? ?? p.basenameWithoutExtension(path);
        doc.pages[pid] = page;
        doc.stamps.pages[pid] = stamps;
      } else if (path.startsWith('pages/') && path.endsWith('.json.enc')) {
        final pid = p.basename(path).replaceAll('.json.enc', '');
        doc.sealed[pid] = e.value;
        final ps = local?.stamps.pages[pid];
        if (ps != null) doc.stamps.pages[pid] = PageStamps(page: ps.page, gone: {...ps.gone});
      } else if (path == 'lock.json') {
        doc.lock = (jsonDecode(utf8.decode(e.value)) as Map).cast<String, dynamic>();
      } else if (path == 'study.json') {
        doc.study = (jsonDecode(utf8.decode(e.value)) as Map).cast<String, dynamic>();
      }
    }
    // Files not fetched are as this device last saw them, which its own
    // copy already has: use its own, so they merge to what's here.
    if (local != null) {
      if (!fetched.containsKey('lock.json')) {
        doc.lock = local.lock;
        doc.stamps.lockNotebook = local.stamps.lockNotebook;
      }
      if (!fetched.containsKey('study.json')) {
        doc.study = local.study;
        doc.stamps.study = local.stamps.study;
      }
    }
    return doc;
  }

  Future<BoardDoc?> _readLocal(String id) async {
    final loaded = await store.loadNotebook(id);
    if (loaded == null) return null;
    return BoardDoc(
      notebook: jsonDecode(encodeNotebook(loaded.notebook)) as Json,
      pages: {
        for (final page in loaded.pages)
          if (!loaded.sealed.containsKey(page.id)) page.id: jsonDecode(encodePage(page)) as Json,
      },
      sealed: {...loaded.sealed},
      lock: loaded.lock,
      study: await store.loadStudy(id),
      assets: {...await store.listAssets(id)},
    );
  }

  static DateTime? _updatedAt(Json nb) => DateTime.tryParse(nb['updatedAt'] as String? ?? '');

  /// Whether [to] differs from [from] in anything written to the disk.
  static bool _differs(BoardDoc from, BoardDoc to) {
    if (hashJson(_comparable(from.notebook)) != hashJson(_comparable(to.notebook))) return true;
    if (!setEquals(from.pageIds, to.pageIds)) return true;
    for (final e in to.pages.entries) {
      final was = from.pages[e.key];
      if (was == null || hashJson(was) != hashJson(e.value)) return true;
    }
    for (final e in to.sealed.entries) {
      final was = from.sealed[e.key];
      if (was == null || !listEquals(was, e.value)) return true;
    }
    if (hashJson(from.lock) != hashJson(to.lock)) return true;
    if (to.study != null && hashJson(from.study) != hashJson(to.study)) return true;
    return false;
  }

  static Json _comparable(Json nb) => {
        for (final e in nb.entries)
          if (e.key != 'updatedAt') e.key: e.value,
      };

  static bool _locksDiffer(BoardDoc from, BoardDoc to) {
    if (hashJson(from.lock) != hashJson(to.lock)) return true;
    for (final e in to.sealed.entries) {
      final was = from.sealed[e.key];
      if (was == null || !listEquals(was, e.value)) return true;
    }
    return from.sealed.keys.any((k) => !to.sealed.containsKey(k));
  }

  /// Keeps the pages sync is about to change in version history.
  Future<void> _keepVersions(String id, BoardDoc from, BoardDoc to, {String? remoteDevice}) async {
    for (final pid in from.pageIds) {
      final clear = from.pages[pid];
      if (clear != null) {
        final now = to.pages[pid];
        if (now != null && hashJson(now) == hashJson(clear)) continue;
        await versions.keep(id, pid, Uint8List.fromList(utf8.encode(jsonEncode(clear))),
            reason: VersionReason.sync, device: remoteDevice);
      } else {
        final sealed = from.sealed[pid]!;
        final now = to.sealed[pid];
        if (now != null && listEquals(now, sealed)) continue;
        await versions.keep(id, pid, sealed, reason: VersionReason.sync, sealed: true, device: remoteDevice);
      }
    }
  }

  /// Writes [to] (merged) over [from] (what's here; null for a notebook
  /// new to this device). Pages first, notebook.json last, so it never
  /// lists a page that isn't written.
  Future<void> _write(String id, BoardDoc? from, BoardDoc to) async {
    for (final e in to.pages.entries) {
      final was = from?.pages[e.key];
      if (was != null && hashJson(was) == hashJson(e.value)) continue;
      await store.savePage(id, decodePage(jsonEncode(e.value)));
    }
    for (final e in to.sealed.entries) {
      final was = from?.sealed[e.key];
      if (was != null && listEquals(was, e.value)) continue;
      await store.saveSealedPage(id, e.key, e.value);
    }
    if (from == null || hashJson(from.lock) != hashJson(to.lock)) await store.saveLock(id, to.lock);
    if (to.study != null && (from == null || hashJson(from.study) != hashJson(to.study))) {
      await store.saveStudy(id, to.study!);
    }
    await store.saveNotebook(decodeNotebook(jsonEncode(to.notebook)));
  }

  // PDF copies.

  Future<void> _sendPdfs(CloudDrive cloud, Iterable<String> ids, SyncReport report) async {
    final side = await store.loadSyncFile('pdf') ?? {};
    final sent = ((side[cloud.kind.name] as Map?) ?? const {}).cast<String, dynamic>();
    final out = <String, dynamic>{};
    for (final id in ids) {
      final meta = await store.loadNotebookMeta(id);
      if (meta == null || meta.trashedAt != null || meta.locked) continue;
      final name = '${_safeName(meta.title)} (${id.substring(id.length - 4)}).pdf';
      final was = (sent[id] as Map?)?.cast<String, dynamic>();
      final stamp = meta.updatedAt.toUtc().toIso8601String();
      if (was != null && was['at'] == stamp && was['name'] == name) {
        out[id] = was;
        continue;
      }
      final bytes = await host.pdfOf(id);
      if (bytes == null) continue;
      await cloud.write('$_pdfDir/$name', bytes);
      if (was != null && was['name'] != name) await cloud.delete('$_pdfDir/${was['name']}');
      out[id] = {'at': stamp, 'name': name};
    }
    // PDFs of notebooks gone from here.
    for (final e in sent.entries) {
      if (!out.containsKey(e.key) && !ids.contains(e.key) && e.value is Map) {
        await cloud.delete('$_pdfDir/${(e.value as Map)['name']}');
      }
    }
    await store.saveSyncFile('pdf', {...side, cloud.kind.name: out});
  }

  static String _safeName(String title) {
    final t = title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ').trim();
    return t.isEmpty ? 'Untitled' : (t.length > 80 ? t.substring(0, 80) : t);
  }
}

class _Outcome {
  const _Outcome(this.doc, {this.added = false, this.changedHere = false, this.applied = false})
      : deleted = false,
        waiting = false;

  const _Outcome.deleted()
      : doc = null,
        added = false,
        changedHere = false,
        applied = false,
        deleted = true,
        waiting = false;

  const _Outcome.waiting()
      : doc = null,
        added = false,
        changedHere = false,
        applied = false,
        deleted = false,
        waiting = true;

  final BoardDoc? doc;
  final bool added;
  final bool changedHere;
  final bool applied;
  final bool deleted;
  final bool waiting;
}

Map<String, String> _strings(Object? j) => {
      if (j is Map)
        for (final e in j.entries)
          if (e.value is String) e.key.toString(): e.value as String,
    };
