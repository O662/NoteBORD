import 'dart:convert';
import 'dart:typed_data';

import '../board/store.dart';
import 'stamps.dart';

// Earlier versions of each page, kept on this device (version history,
// from ⋯ → Version history). A version is the page's file as it was:
// `versions/<notebook>/<page>/<ms>-<why>.json`, or `.json.enc` (sealed
// with the page's key) on a page with a password.
//
// One is kept while you write (at most every 10 minutes), one before sync
// changes the page with another device's changes, and one before a
// restore. Older ones are thinned out: everything from the last hour, one
// per 10 minutes for a day, one per day after that, and never more than
// [VersionStore.maxPerPage].
//
// Update 04 (History.png): a version can be named ("Before the midterm").
// Named versions are kept until they're deleted; the others go after
// [VersionStore.keepDays] days (30; Settings › Notebooks & pages). The names
// are in `names.json` beside the versions.

/// Why a version was kept.
enum VersionReason {
  edit,
  sync,
  restore,

  /// Another device's version of a page changed on both (Update 04, a page
  /// to check): kept so either side can be chosen.
  remote;

  static VersionReason parse(String s) => values.where((v) => v.name == s).firstOrNull ?? edit;
}

class PageVersion {
  const PageVersion(this.name, this.at, this.reason, {required this.sealed, this.device, this.label});

  final String name;

  /// The name given to it ("Before the midterm"), or null.
  final String? label;

  PageVersion withLabel(String? label) => PageVersion(name, at, reason, sealed: sealed, device: device, label: label);
  final DateTime at;
  final VersionReason reason;

  /// Kept sealed (the page has a password).
  final bool sealed;

  /// The device whose changes came in (for [VersionReason.sync]): its name.
  final String? device;

  static PageVersion? parse(String name) {
    final m = RegExp(r'^(\d+)-([a-z]+)(?:-([^.]*))?\.json(\.enc)?$').firstMatch(name);
    if (m == null) return null;
    return PageVersion(
      name,
      DateTime.fromMillisecondsSinceEpoch(int.parse(m[1]!), isUtc: true),
      VersionReason.parse(m[2]!),
      sealed: m[4] != null,
      device: m[3] == null || m[3]!.isEmpty ? null : Uri.decodeComponent(m[3]!),
    );
  }
}

class VersionStore {
  VersionStore(this.store, {DateTime Function()? clock, int Function()? keepDays})
      : _clock = clock ?? DateTime.now,
        _keepDays = keepDays ?? (() => 30);

  static const maxPerPage = 100;

  /// The file holding the names given to versions (not a version).
  static const namesFile = 'names.json';

  /// How long a version without a name is kept.
  int get keepDays => _keepDays();
  final int Function() _keepDays;

  /// While writing, a version at most this often.
  static const editEvery = Duration(minutes: 10);

  final BoardStore store;
  final DateTime Function() _clock;
  final _lastEdit = <String, DateTime>{};
  final _lastHash = <String, String>{};

  /// Newest first, with their names.
  Future<List<PageVersion>> list(String notebookId, String pageId) async {
    final labels = await _labels(notebookId, pageId);
    final out = [
      for (final n in await store.listVersions(notebookId, pageId))
        if (PageVersion.parse(n) case final v?) v.withLabel(labels[v.name]),
    ]..sort((a, b) => b.at.compareTo(a.at));
    return out;
  }

  Future<Map<String, String>> _labels(String notebookId, String pageId) async {
    final bytes = await store.loadVersion(notebookId, pageId, namesFile);
    if (bytes == null) return {};
    try {
      final j = jsonDecode(utf8.decode(bytes));
      return {
        if (j is Map)
          for (final e in j.entries)
            if (e.value is String) e.key.toString(): e.value as String,
      };
    } on FormatException {
      return {};
    }
  }

  /// Names version [name] [label] (kept until deleted), or takes its name
  /// away ([label] null or empty: it goes after [keepDays] like the others).
  Future<void> setLabel(String notebookId, String pageId, String name, String? label) async {
    final labels = await _labels(notebookId, pageId);
    final l = label?.trim();
    if (l == null || l.isEmpty) {
      labels.remove(name);
    } else {
      labels[name] = l;
    }
    await store.saveVersion(notebookId, pageId, namesFile, Uint8List.fromList(utf8.encode(jsonEncode(labels))));
  }

  Future<Uint8List?> load(String notebookId, String pageId, String name) => store.loadVersion(notebookId, pageId, name);

  /// Keeps [bytes] as a version of the page, unless it's the same as the
  /// newest one kept. Returns the version's file name (the newest one's,
  /// when it's the same).
  Future<String?> keep(
    String notebookId,
    String pageId,
    Uint8List bytes, {
    required VersionReason reason,
    bool sealed = false,
    String? device,
  }) async {
    final key = '$notebookId/$pageId';
    final hash = hashBytes(bytes);
    final known = await list(notebookId, pageId);
    if (_lastHash[key] == null && known.isNotEmpty) {
      final latest = await load(notebookId, pageId, known.first.name);
      if (latest != null) _lastHash[key] = hashBytes(latest);
    }
    if (_lastHash[key] == hash) return known.firstOrNull?.name;
    final now = _clock().toUtc();
    final who = device == null ? '' : '-${Uri.encodeComponent(device).replaceAll('.', '%2E')}';
    final name = '${now.millisecondsSinceEpoch}-${reason.name}$who.json${sealed ? '.enc' : ''}';
    await store.saveVersion(notebookId, pageId, name, bytes);
    _lastHash[key] = hash;
    await _thin(notebookId, pageId, [PageVersion.parse(name)!, ...known]);
    return name;
  }

  /// While writing: keeps [bytes] if the last one kept while writing this
  /// page is more than [editEvery] ago (or none was, since the app started).
  Future<void> keepWhileEditing(String notebookId, String pageId, Uint8List Function() bytes, {bool sealed = false}) async {
    final key = '$notebookId/$pageId';
    final now = _clock().toUtc();
    final last = _lastEdit[key];
    if (last != null && now.difference(last) < editEvery) return;
    _lastEdit[key] = now;
    await keep(notebookId, pageId, bytes(), reason: VersionReason.edit, sealed: sealed);
  }

  Future<void> _thin(String notebookId, String pageId, List<PageVersion> versions) async {
    final now = _clock().toUtc();
    final kept = <PageVersion>[];
    final buckets = <String>{};
    final keep = Duration(days: keepDays);
    for (final v in versions) {
      // Named versions stay until they're deleted.
      if (v.label != null) continue;
      final age = now.difference(v.at);
      if (age >= keep) {
        await store.deleteVersion(notebookId, pageId, v.name);
        continue;
      }
      final String? bucket;
      if (age < const Duration(hours: 1)) {
        bucket = null; // all kept
      } else if (age < const Duration(days: 1)) {
        bucket = 'm${v.at.millisecondsSinceEpoch ~/ editEvery.inMilliseconds}';
      } else {
        bucket = 'd${v.at.millisecondsSinceEpoch ~/ const Duration(days: 1).inMilliseconds}';
      }
      // Newest first, so the newest in each bucket is the one kept.
      if (bucket == null || buckets.add(bucket)) {
        kept.add(v);
      } else {
        await store.deleteVersion(notebookId, pageId, v.name);
      }
    }
    for (final v in kept.skip(maxPerPage)) {
      await store.deleteVersion(notebookId, pageId, v.name);
    }
  }
}
