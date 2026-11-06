import 'dart:convert';
import 'dart:typed_data';

import '../board/codec.dart';
import '../board/model.dart';
import 'stamps.dart';

// A notebook as sync sees it: its files as JSON (so fields and item types
// this version doesn't know are carried along untouched) with a stamp for
// each part, saying when it last changed.
//
// Two copies of a notebook merge item by item: for each id, the copy with
// the newer stamp wins, and an item deleted on one device is kept as a
// deletion ("gone") with a stamp, so it isn't brought back by a device that
// still has it. The merge gives the same notebook whichever order copies
// meet in, so devices that sync at the same moment still end up alike.

/// Notebook fields that aren't synced as fields.
const _notMerged = {'id', 'format', 'version', 'createdAt', 'updatedAt', 'sync'};

/// Stamps for one page: its own fields (title, paper, template…), each
/// item, and items deleted.
class PageStamps {
  PageStamps({this.page, Map<String, String>? items, Map<String, String>? gone})
      : items = items ?? {},
        gone = gone ?? {};

  String? page;
  final Map<String, String> items;
  final Map<String, String> gone;

  /// The newest change to this page.
  String? get latest {
    String? best = page;
    for (final s in items.values) {
      best = newest(best, s);
    }
    return best;
  }

  PageStamps copy() => PageStamps(page: page, items: {...items}, gone: {...gone});

  Json toJson() => {
        if (page != null) 'page': page,
        'items': items,
        if (gone.isNotEmpty) 'gone': gone,
      };

  static PageStamps fromJson(Object? j) {
    if (j is! Map) return PageStamps();
    return PageStamps(
      page: j['page'] as String?,
      items: _strings(j['items']),
      gone: _strings(j['gone']),
    );
  }
}

Map<String, String> _strings(Object? j) => {
      if (j is Map)
        for (final e in j.entries)
          if (e.value is String) e.key.toString(): e.value as String,
    };

/// Stamps for a whole notebook.
class DocStamps {
  DocStamps({
    Map<String, String>? fields,
    Map<String, PageStamps>? pages,
    Map<String, String>? gonePages,
    Map<String, String>? sealed,
    this.lockNotebook,
    this.study,
  })  : fields = fields ?? {},
        pages = pages ?? {},
        gonePages = gonePages ?? {},
        sealed = sealed ?? {};

  /// notebook.json's fields (title, folder, cover, page order…).
  final Map<String, String> fields;
  final Map<String, PageStamps> pages;

  /// Pages deleted.
  final Map<String, String> gonePages;

  /// Pages with a password, kept sealed (their items can't be read
  /// without it, so a sealed page changes as a whole).
  final Map<String, String> sealed;

  /// lock.json's notebook password.
  String? lockNotebook;

  /// study.json.
  String? study;

  PageStamps page(String id) => pages[id] ??= PageStamps();

  /// The newest change anywhere in the notebook.
  String? get latest {
    String? best = lockNotebook;
    best = newest(best, study);
    for (final s in [...fields.values, ...gonePages.values, ...sealed.values]) {
      best = newest(best, s);
    }
    for (final p in pages.values) {
      best = newest(best, p.latest);
      for (final g in p.gone.values) {
        best = newest(best, g);
      }
    }
    return best;
  }

  DocStamps copy() => DocStamps(
        fields: {...fields},
        pages: {for (final e in pages.entries) e.key: e.value.copy()},
        gonePages: {...gonePages},
        sealed: {...sealed},
        lockNotebook: lockNotebook,
        study: study,
      );

  /// Every stamp, so a clock can move past them.
  Iterable<String> get all sync* {
    yield* fields.values;
    yield* gonePages.values;
    yield* sealed.values;
    if (lockNotebook != null) yield lockNotebook!;
    if (study != null) yield study!;
    for (final p in pages.values) {
      if (p.page != null) yield p.page!;
      yield* p.items.values;
      yield* p.gone.values;
    }
  }

  Json toJson({bool withPages = true}) => {
        'fields': fields,
        if (gonePages.isNotEmpty) 'gonePages': gonePages,
        if (sealed.isNotEmpty) 'sealed': sealed,
        if (lockNotebook != null) 'lockNotebook': lockNotebook,
        if (study != null) 'study': study,
        if (withPages) 'pages': {for (final e in pages.entries) e.key: e.value.toJson()},
      };

  static DocStamps fromJson(Object? j) {
    if (j is! Map) return DocStamps();
    return DocStamps(
      fields: _strings(j['fields']),
      pages: {
        if (j['pages'] is Map)
          for (final e in (j['pages'] as Map).entries) e.key.toString(): PageStamps.fromJson(e.value),
      },
      gonePages: _strings(j['gonePages']),
      sealed: _strings(j['sealed']),
      lockNotebook: j['lockNotebook'] as String?,
      study: j['study'] as String?,
    );
  }
}

/// A notebook's files, as JSON, with their stamps.
class BoardDoc {
  BoardDoc({
    required this.notebook,
    Map<String, Json>? pages,
    Map<String, Uint8List>? sealed,
    this.lock,
    this.study,
    Set<String>? assets,
    DocStamps? stamps,
  })  : pages = pages ?? {},
        sealed = sealed ?? {},
        assets = assets ?? {},
        stamps = stamps ?? DocStamps();

  /// notebook.json, without `sync`.
  Json notebook;

  /// Pages in the clear, by id, without `sync`.
  final Map<String, Json> pages;

  /// Pages with a password: their encrypted files.
  final Map<String, Uint8List> sealed;
  Json? lock;
  Json? study;

  /// File names in assets/.
  final Set<String> assets;
  final DocStamps stamps;

  String get id => notebook['id'] as String;

  List<String> get pageOrder => [...((notebook['pages'] as List?) ?? const []).whereType<String>()];

  /// Every page that's here, clear or sealed.
  Set<String> get pageIds => {...pages.keys, ...sealed.keys};
}

// Normalizing: a notebook that comes from another device is put through
// this version's reader and writer first, so it's exactly what this device
// would write, and comparing it with what's on the disk shows only real
// changes (never a number written another way).

/// [page] as this version writes it.
Json normalizePage(Json page) => jsonDecode(encodePage(decodePage(jsonEncode(_withoutSync(page))))) as Json;

/// notebook.json as this version writes it.
Json normalizeNotebook(Json nb) => jsonDecode(encodeNotebook(decodeNotebook(jsonEncode(_withoutSync(nb))))) as Json;

Json _withoutSync(Json j) => {
      for (final e in j.entries)
        if (e.key != 'sync') e.key: e.value,
    };

List<Json> _items(Json page) => [...((page['items'] as List?) ?? const []).whereType<Map>().map((m) => m.cast<String, dynamic>())];

String? _itemId(Json item) => item['id'] as String?;

/// A page's own fields (everything but its items and id).
Json _pageHead(Json page) => {
      for (final e in page.entries)
        if (e.key != 'items' && e.key != 'id' && e.key != 'sync') e.key: e.value,
    };

/// What this device last knew of a notebook: a hash of each part, so a
/// change since is seen and stamped.
class Known {
  Known({
    Map<String, String>? fields,
    Map<String, String>? pageHeads,
    Map<String, Map<String, String>>? items,
    Map<String, String>? sealed,
    this.lockNotebook,
    this.study,
    DocStamps? stamps,
  })  : fields = fields ?? {},
        pageHeads = pageHeads ?? {},
        items = items ?? {},
        sealed = sealed ?? {},
        stamps = stamps ?? DocStamps();

  final Map<String, String> fields;
  final Map<String, String> pageHeads;
  final Map<String, Map<String, String>> items;
  final Map<String, String> sealed;
  String? lockNotebook;
  String? study;
  DocStamps stamps;

  Json toJson() => {
        'fields': fields,
        'pageHeads': pageHeads,
        'items': items,
        'sealed': sealed,
        if (lockNotebook != null) 'lockNotebook': lockNotebook,
        if (study != null) 'study': study,
        'stamps': stamps.toJson(),
      };

  static Known fromJson(Object? j) {
    if (j is! Map) return Known();
    return Known(
      fields: _strings(j['fields']),
      pageHeads: _strings(j['pageHeads']),
      items: {
        if (j['items'] is Map)
          for (final e in (j['items'] as Map).entries) e.key.toString(): _strings(e.value),
      },
      sealed: _strings(j['sealed']),
      lockNotebook: j['lockNotebook'] as String?,
      study: j['study'] as String?,
      stamps: DocStamps.fromJson(j['stamps']),
    );
  }

  /// Records [doc] (with its stamps) as what this device has now.
  void record(BoardDoc doc) {
    fields
      ..clear()
      ..addAll(_fieldHashes(doc.notebook));
    pageHeads.clear();
    items.clear();
    for (final e in doc.pages.entries) {
      pageHeads[e.key] = hashJson(_pageHead(e.value));
      items[e.key] = {
        for (final i in _items(e.value))
          if (_itemId(i) != null) _itemId(i)!: hashJson(i),
      };
    }
    sealed
      ..clear()
      ..addAll({for (final e in doc.sealed.entries) e.key: hashBytes(e.value)});
    lockNotebook = _lockNotebookHash(doc.lock);
    study = doc.study == null ? null : hashJson(doc.study);
    stamps = doc.stamps.copy();
  }
}

Map<String, String> _fieldHashes(Json nb) => {
      for (final e in nb.entries)
        if (!_notMerged.contains(e.key)) e.key: hashJson(e.value),
    };

String? _lockNotebookHash(Json? lock) => lock?['notebook'] == null ? null : hashJson(lock!['notebook']);

/// Stamps what changed in [doc] since [known] (when this device last
/// synced it), as changes made at [editedAt] (the notebook's last edit),
/// and records [doc] as known. [doc] gets the stamps.
void stampChanges(BoardDoc doc, Known known, Stamper stamper, {DateTime? editedAt}) {
  final s = known.stamps.copy();
  String stamp(String? previous) => stamper.after(previous, editedAt);

  // Notebook fields.
  final fields = _fieldHashes(doc.notebook);
  for (final e in fields.entries) {
    if (known.fields[e.key] != e.value) s.fields[e.key] = stamp(s.fields[e.key]);
  }
  for (final k in known.fields.keys) {
    if (!fields.containsKey(k)) s.fields[k] = stamp(s.fields[k]);
  }

  // Pages in the clear.
  for (final e in doc.pages.entries) {
    final pid = e.key;
    final ps = s.page(pid);
    s.gonePages.remove(pid);
    final head = hashJson(_pageHead(e.value));
    if (known.pageHeads[pid] != head) ps.page = stamp(ps.page);
    final before = known.items[pid] ?? const {};
    final now = <String>{};
    for (final item in _items(e.value)) {
      final id = _itemId(item);
      if (id == null) continue;
      now.add(id);
      if (before[id] != hashJson(item) || ps.items[id] == null) {
        ps.items[id] = stamp(newest(ps.items[id], ps.gone[id]));
        ps.gone.remove(id);
      }
    }
    for (final id in before.keys) {
      if (!now.contains(id)) {
        ps.gone[id] = stamp(ps.items.remove(id));
      }
    }
  }

  // Sealed pages.
  for (final e in doc.sealed.entries) {
    final h = hashBytes(e.value);
    if (known.sealed[e.key] != h || s.sealed[e.key] == null) s.sealed[e.key] = stamp(newest(s.sealed[e.key], s.pages[e.key]?.page));
    s.gonePages.remove(e.key);
  }

  // Pages deleted since.
  final here = doc.pageIds;
  for (final pid in {...known.pageHeads.keys, ...known.sealed.keys}) {
    if (!here.contains(pid)) s.gonePages[pid] = stamp(newest(s.pages[pid]?.latest, s.sealed[pid]));
  }
  // A page that went from sealed to clear (its password removed) or back
  // keeps the other form's stamps for comparing; drop what can't apply.
  for (final pid in doc.pages.keys) {
    s.sealed.remove(pid);
  }
  for (final pid in doc.sealed.keys) {
    final ps = s.pages[pid];
    if (ps != null) s.pages[pid] = PageStamps(page: ps.page, gone: ps.gone);
  }

  final ln = _lockNotebookHash(doc.lock);
  if (ln != known.lockNotebook) s.lockNotebook = stamp(s.lockNotebook);
  final st = doc.study == null ? null : hashJson(doc.study);
  if (st != known.study) s.study = st == null ? null : stamp(s.study);

  doc.stamps
    ..fields.clear()
    ..fields.addAll(s.fields)
    ..pages.clear()
    ..pages.addAll(s.pages)
    ..gonePages.clear()
    ..gonePages.addAll(s.gonePages)
    ..sealed.clear()
    ..sealed.addAll(s.sealed)
    ..lockNotebook = s.lockNotebook
    ..study = s.study;
  known.record(doc);
}

/// How two copies of a notebook changed on two devices are put together.
enum MergePolicy {
  /// Item by item: every stroke, note and card is kept; where the same one
  /// changed on both, the newer change wins.
  mergeBoth,

  /// The copy changed last wins as a whole (the other is kept in version
  /// history).
  newestWins,
}

/// [a] and [b] put together (see [MergePolicy]). Neither is changed.
BoardDoc mergeDocs(BoardDoc a, BoardDoc b, {MergePolicy policy = MergePolicy.mergeBoth}) {
  if (policy == MergePolicy.newestWins) {
    final la = a.stamps.latest, lb = b.stamps.latest;
    if (la != lb) {
      final win = newer(la, lb) ? a : b;
      final out = _copyDoc(win);
      out.assets.addAll(a.assets);
      out.assets.addAll(b.assets);
      return out;
    }
  }
  final sa = a.stamps, sb = b.stamps;
  final out = DocStamps();

  // Notebook fields: the newer of each.
  final nb = <String, dynamic>{
    for (final e in a.notebook.entries)
      if (_notMerged.contains(e.key)) e.key: e.value,
  };
  for (final k in {...a.notebook.keys, ...b.notebook.keys, ...sa.fields.keys, ...sb.fields.keys}) {
    if (_notMerged.contains(k)) continue;
    final fromB = _wins(sb.fields[k], sa.fields[k], () => hashJson(b.notebook[k]), () => hashJson(a.notebook[k]));
    final src = fromB ? b.notebook : a.notebook;
    final stamp = fromB ? sb.fields[k] : sa.fields[k];
    if (stamp != null) out.fields[k] = stamp;
    if (src.containsKey(k)) nb[k] = src[k];
  }
  // Last edited: the later; made: the earlier.
  nb['updatedAt'] = _later(a.notebook['updatedAt'], b.notebook['updatedAt']);
  final ca = a.notebook['createdAt'], cb = b.notebook['createdAt'];
  nb['createdAt'] = ca is String && cb is String && cb.compareTo(ca) < 0 ? cb : (ca ?? cb);

  // Pages.
  final pages = <String, Json>{};
  final sealed = <String, Uint8List>{};
  final sealedFrom = <String, BoardDoc>{};
  for (final pid in {...a.pageIds, ...b.pageIds, ...sa.gonePages.keys, ...sb.gonePages.keys}) {
    final gone = newest(sa.gonePages[pid], sb.gonePages[pid]);
    final life = newest(_life(a, pid), _life(b, pid));
    if (gone != null && !newer(life, gone)) {
      out.gonePages[pid] = gone;
      continue;
    }
    final aClear = a.pages[pid], bClear = b.pages[pid];
    final aSealed = a.sealed[pid], bSealed = b.sealed[pid];
    if (aClear != null && bClear != null) {
      final (page, ps) = _mergePage(aClear, sa.page(pid), bClear, sb.page(pid));
      pages[pid] = page;
      out.pages[pid] = ps;
      continue;
    }
    // A page sealed on one device: the sealed copy wins unless the page
    // itself changed (its password removed) later on the other.
    BoardDoc? sealedWin;
    BoardDoc? clearWin;
    if (aSealed != null && bSealed != null) {
      sealedWin = _wins(sb.sealed[pid], sa.sealed[pid], () => hashBytes(bSealed), () => hashBytes(aSealed)) ? b : a;
    } else if (aSealed != null && bClear != null) {
      newer(sb.pages[pid]?.page, sa.sealed[pid]) ? clearWin = b : sealedWin = a;
    } else if (bSealed != null && aClear != null) {
      newer(sa.pages[pid]?.page, sb.sealed[pid]) ? clearWin = a : sealedWin = b;
    } else if (aSealed != null) {
      sealedWin = a;
    } else if (bSealed != null) {
      sealedWin = b;
    } else if (aClear != null) {
      clearWin = a;
    } else if (bClear != null) {
      clearWin = b;
    }
    if (sealedWin != null) {
      sealed[pid] = sealedWin.sealed[pid]!;
      sealedFrom[pid] = sealedWin;
      final st = sealedWin.stamps.sealed[pid];
      if (st != null) out.sealed[pid] = st;
      final ps = sealedWin.stamps.pages[pid];
      if (ps != null) out.pages[pid] = PageStamps(page: ps.page, gone: {...ps.gone});
    } else if (clearWin != null) {
      pages[pid] = _copyJson(clearWin.pages[pid]!);
      out.pages[pid] = clearWin.stamps.page(pid).copy();
    }
  }

  // Page order: from the copy whose order changed last, with pages only
  // the other has after the page before them there.
  final orderFromB = _wins(sb.fields['pages'], sa.fields['pages'], () => hashJson(b.pageOrder), () => hashJson(a.pageOrder));
  final keep = {...pages.keys, ...sealed.keys};
  nb['pages'] = mergeOrder(
    orderFromB ? b.pageOrder : a.pageOrder,
    orderFromB ? a.pageOrder : b.pageOrder,
    keep,
  );

  // Passwords: the notebook's from the newer; each page's goes with its
  // sealed copy.
  final lockFromB = _wins(sb.lockNotebook, sa.lockNotebook, () => hashJson(b.lock?['notebook']), () => hashJson(a.lock?['notebook']));
  final lockSrc = lockFromB ? b : a;
  out.lockNotebook = lockFromB ? sb.lockNotebook : sa.lockNotebook;
  final lockPages = <String, dynamic>{};
  for (final e in sealedFrom.entries) {
    final entry = (e.value.lock?['pages'] as Map?)?[e.key];
    if (entry != null) lockPages[e.key] = entry;
  }
  final lockNotebook = lockSrc.lock?['notebook'];
  final lock = lockNotebook == null && lockPages.isEmpty
      ? null
      : <String, dynamic>{...?lockSrc.lock, ...?_otherLockFields(lockFromB ? a.lock : b.lock, lockSrc.lock), 'version': 1, 'notebook': lockNotebook, 'pages': lockPages};

  // Study progress: the newer copy.
  final studyFromB = _wins(sb.study, sa.study, () => hashJson(b.study), () => hashJson(a.study));
  out.study = studyFromB ? sb.study : sa.study;
  final study = studyFromB ? b.study : a.study;

  return BoardDoc(
    notebook: nb,
    pages: pages,
    sealed: sealed,
    lock: lock,
    study: study == null ? null : _copyJson(study),
    assets: {...a.assets, ...b.assets},
    stamps: out,
  );
}

Json? _otherLockFields(Json? other, Json? src) => other == null
    ? null
    : {
        for (final e in other.entries)
          if (src == null || !src.containsKey(e.key)) e.key: e.value,
      };

/// Whether the copy stamped [sb] wins over the one stamped [sa]. Equal
/// stamps (which should mean equal contents) are settled by hash, so both
/// devices pick the same.
bool _wins(String? sb, String? sa, String Function() hb, String Function() ha) {
  if (sb == sa) return hb().compareTo(ha()) > 0;
  return newer(sb, sa);
}

String? _later(Object? a, Object? b) {
  if (a is! String) return b as String?;
  if (b is! String) return a;
  final da = DateTime.tryParse(a), db = DateTime.tryParse(b);
  if (da == null || db == null) return a;
  return db.isAfter(da) ? b : a;
}

/// The newest change to page [pid] in [doc], clear or sealed.
String? _life(BoardDoc doc, String pid) {
  if (!doc.pageIds.contains(pid)) return null;
  return newest(doc.stamps.pages[pid]?.latest, doc.stamps.sealed[pid]);
}

(Json, PageStamps) _mergePage(Json a, PageStamps sa, Json b, PageStamps sb) {
  final out = PageStamps();
  // The page's own fields: the newer.
  final headFromB = _wins(sb.page, sa.page, () => hashJson(_pageHead(b)), () => hashJson(_pageHead(a)));
  final head = headFromB ? b : a;
  out.page = headFromB ? sb.page : sa.page;

  final ia = {for (final i in _items(a)) if (_itemId(i) != null) _itemId(i)!: i};
  final ib = {for (final i in _items(b)) if (_itemId(i) != null) _itemId(i)!: i};
  final merged = <String, Json>{};
  for (final id in {...ia.keys, ...ib.keys, ...sa.gone.keys, ...sb.gone.keys}) {
    final gone = newest(sa.gone[id], sb.gone[id]);
    final xa = ia[id], xb = ib[id];
    final ta = xa == null ? null : sa.items[id] ?? '', tb = xb == null ? null : sb.items[id] ?? '';
    Json? win;
    String? stamp;
    if (xa != null && xb != null) {
      final fromB = _wins(tb, ta, () => hashJson(xb), () => hashJson(xa));
      win = fromB ? xb : xa;
      stamp = fromB ? tb : ta;
    } else if (xa != null) {
      (win, stamp) = (xa, ta);
    } else if (xb != null) {
      (win, stamp) = (xb, tb);
    }
    if (win == null || gone != null && !newer(stamp, gone)) {
      if (gone != null) out.gone[id] = gone;
      continue;
    }
    merged[id] = win;
    if (stamp != null && stamp.isNotEmpty) out.items[id] = stamp;
  }

  // Their order: the copy changed last, with items only the other has
  // after the item before them there.
  final orderFromB = _wins(sb.latest, sa.latest, () => hashJson(ib.keys.toList()), () => hashJson(ia.keys.toList()));
  final order = mergeOrder(
    orderFromB ? ib.keys.toList() : ia.keys.toList(),
    orderFromB ? ia.keys.toList() : ib.keys.toList(),
    merged.keys.toSet(),
  );
  final page = <String, dynamic>{
    ..._pageHead(head),
    'id': a['id'] ?? b['id'],
    'items': [for (final id in order) _copyJson(merged[id]!)],
  };
  return (page, out);
}

/// [primary]'s ids that are in [keep], with [secondary]'s others each
/// placed after the one before it in [secondary] (first if none).
List<String> mergeOrder(List<String> primary, List<String> secondary, Set<String> keep) {
  final out = [for (final id in primary) if (keep.contains(id)) id];
  final placed = out.toSet();
  String? prev;
  for (final id in secondary) {
    if (!keep.contains(id)) continue;
    if (!placed.contains(id)) {
      out.insert(prev == null ? 0 : out.indexOf(prev) + 1, id);
      placed.add(id);
    }
    prev = id;
  }
  // Anything in neither list (shouldn't happen) goes last, in a fixed order.
  out.addAll(keep.difference(placed).toList()..sort());
  return out;
}

Json _copyJson(Json j) => jsonDecode(jsonEncode(j)) as Json;

BoardDoc _copyDoc(BoardDoc d) => BoardDoc(
      notebook: _copyJson(d.notebook),
      pages: {for (final e in d.pages.entries) e.key: _copyJson(e.value)},
      sealed: {...d.sealed},
      lock: d.lock == null ? null : _copyJson(d.lock!),
      study: d.study == null ? null : _copyJson(d.study!),
      assets: {...d.assets},
      stamps: d.stamps.copy(),
    );

// The copy in the cloud: the same files as on the tablet (it's a .board
// package), with each page's stamps in its own file (`sync`), so a page
// and its stamps are always written together, and the notebook's stamps,
// a hash of each file and the assets list in notebook.json's `sync`.
//
// Every file but notebook.json is named after its contents
// (`pages/<id>.<hash>.json`, `lock.<hash>.json`), so a file is never
// written over: two devices sending at the same moment can't replace each
// other's pages, and whichever notebook.json lands last lists a whole,
// consistent notebook. The device whose notebook.json was replaced sees
// that on its next sync and merges again.

/// Where the file known as [logical] (`pages/pg_1.json`) with contents
/// [hash] is kept in the cloud: `pages/pg_1.<hash>.json`.
String remoteFileName(String logical, String hash) {
  final slash = logical.lastIndexOf('/');
  final dot = logical.indexOf('.', slash + 1);
  if (dot < 0) return '$logical.$hash';
  return '${logical.substring(0, dot)}.$hash${logical.substring(dot)}';
}

/// A page as it's written to the cloud.
String encodeRemotePage(Json page, PageStamps stamps) => canonicalJson({...page, 'sync': stamps.toJson()});

/// A page read from the cloud, and its stamps.
(Json, PageStamps) decodeRemotePage(String source) {
  final j = jsonDecode(source) as Json;
  return (normalizePage(j), PageStamps.fromJson(j['sync']));
}

/// notebook.json as it's written to the cloud. [files] is the hash of each
/// other file in the package (by path, e.g. `pages/pg_1.json`).
String encodeRemoteNotebook(BoardDoc doc, Map<String, String> files) => sortedJson({
      ...doc.notebook,
      'sync': {
        'v': 1,
        ...doc.stamps.toJson(withPages: false),
        'files': files,
        'assets': doc.assets.toList()..sort(),
      },
    });

/// What a cloud notebook.json says about the rest of the package.
class RemoteManifest {
  RemoteManifest(this.notebook, this.stamps, this.files, this.assets, {this.device});

  /// The device that wrote it ("Kim's tablet").
  final String? device;

  /// Without `sync`, normalized.
  final Json notebook;

  /// The notebook's stamps (pages' are in their files).
  final DocStamps stamps;
  final Map<String, String> files;
  final Set<String> assets;

  static RemoteManifest decode(String source) {
    final j = jsonDecode(source) as Json;
    final sync = (j['sync'] as Map?)?.cast<String, dynamic>() ?? const {};
    return RemoteManifest(
      normalizeNotebook(j),
      DocStamps.fromJson(sync),
      _strings(sync['files']),
      {...((sync['assets'] as List?) ?? const []).whereType<String>()},
      device: sync['device'] as String?,
    );
  }
}
