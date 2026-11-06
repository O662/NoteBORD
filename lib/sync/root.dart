import 'dart:convert';

import '../board/model.dart' show Json;
import 'stamps.dart';

// What isn't in any notebook but is synced too: folders (with their colors,
// so empty ones show), flashcard decks, and notebooks deleted for good (so
// another device doesn't bring them back). Each is a set of entries by key,
// merged like items: the newer change to an entry wins, and a deleted entry
// is kept as a deletion with a stamp.

/// Entries by key, with stamps.
class Keyed {
  Keyed({Map<String, Object?>? values, Map<String, String>? stamps, Map<String, String>? gone})
      : values = values ?? {},
        stamps = stamps ?? {},
        gone = gone ?? {};

  final Map<String, Object?> values;
  final Map<String, String> stamps;
  final Map<String, String> gone;

  Json toJson() => {'values': values, 'stamps': stamps, if (gone.isNotEmpty) 'gone': gone};

  static Keyed fromJson(Object? j) {
    if (j is! Map) return Keyed();
    Map<String, String> strings(Object? m) => {
          if (m is Map)
            for (final e in m.entries)
              if (e.value is String) e.key.toString(): e.value as String,
        };
    return Keyed(
      values: {if (j['values'] is Map) ...(j['values'] as Map).cast<String, Object?>()},
      stamps: strings(j['stamps']),
      gone: strings(j['gone']),
    );
  }

  Iterable<String> get allStamps => [...stamps.values, ...gone.values];
}

/// Stamps entries of [now] that changed since [known] (key → hash, updated
/// to [now]'s), keeping [previous]'s stamps for the rest.
Keyed stampKeyed(Map<String, Object?> now, Map<String, String> known, Keyed previous, Stamper stamper) {
  final out = Keyed(values: {...now}, stamps: {...previous.stamps}, gone: {...previous.gone});
  for (final e in now.entries) {
    final h = hashJson(e.value);
    if (known[e.key] != h || out.stamps[e.key] == null) {
      out.stamps[e.key] = stamper.after(newest(out.stamps[e.key], out.gone.remove(e.key)));
    }
  }
  for (final k in known.keys) {
    if (!now.containsKey(k)) {
      out.gone[k] = stamper.after(out.stamps.remove(k));
    }
  }
  known
    ..clear()
    ..addAll({for (final e in now.entries) e.key: hashJson(e.value)});
  return out;
}

/// [a] and [b] put together: the newer of each entry; a deletion wins over
/// an entry no newer than it.
Keyed mergeKeyed(Keyed a, Keyed b) {
  final out = Keyed();
  for (final k in {...a.values.keys, ...b.values.keys, ...a.gone.keys, ...b.gone.keys}) {
    final gone = newest(a.gone[k], b.gone[k]);
    final inA = a.values.containsKey(k), inB = b.values.containsKey(k);
    bool fromB;
    if (inA && inB) {
      final sa = a.stamps[k], sb = b.stamps[k];
      fromB = sa == sb ? hashJson(b.values[k]).compareTo(hashJson(a.values[k])) > 0 : newer(sb, sa);
    } else {
      fromB = inB;
    }
    final present = fromB ? inB : inA;
    final stamp = fromB ? b.stamps[k] : a.stamps[k];
    if (!present || gone != null && !newer(stamp, gone)) {
      if (gone != null) out.gone[k] = gone;
      continue;
    }
    out.values[k] = (fromB ? b : a).values[k];
    if (stamp != null) out.stamps[k] = stamp;
  }
  return out;
}

/// The app-wide part, as one document (`endless.json` in the cloud).
class RootDoc {
  RootDoc({Keyed? folders, Keyed? decks, Keyed? notebooks})
      : folders = folders ?? Keyed(),
        decks = decks ?? Keyed(),
        notebooks = notebooks ?? Keyed();

  /// Folders: key `jsonEncode(path)`, value `{path, color}`.
  final Keyed folders;

  /// Flashcard decks by id: the deck's JSON.
  final Keyed decks;

  /// Only deletions: notebooks deleted for good.
  final Keyed notebooks;

  String encode() => const JsonEncoder.withIndent('  ').convert({
        'format': 'endless.sync',
        'version': 1,
        'folders': folders.toJson(),
        'decks': decks.toJson(),
        'notebooks': notebooks.toJson(),
      });

  static RootDoc decode(String source) {
    final j = jsonDecode(source);
    if (j is! Map || j['format'] != 'endless.sync') return RootDoc();
    return RootDoc(
      folders: Keyed.fromJson(j['folders']),
      decks: Keyed.fromJson(j['decks']),
      notebooks: Keyed.fromJson(j['notebooks']),
    );
  }

  RootDoc merge(RootDoc other) => RootDoc(
        folders: mergeKeyed(folders, other.folders),
        decks: mergeKeyed(decks, other.decks),
        notebooks: mergeKeyed(notebooks, other.notebooks),
      );

  Iterable<String> get allStamps => [...folders.allStamps, ...decks.allStamps, ...notebooks.allStamps];
}

/// The key a folder is kept under.
String folderKey(List<String> path) => jsonEncode(path);
