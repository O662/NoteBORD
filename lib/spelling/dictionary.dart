import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' show Database, OpenMode, sqlite3;

// The dictionary and thesaurus (design/screens/Spell.png): definitions,
// examples, similar words and opposites from Open English WordNet, with a
// pronunciation respelled from the CMU Pronouncing Dictionary. Bundled as
// assets/dictionary/en_dictionary.sqlite.gz (tool/build_dictionary.py) and
// unpacked once, so it works offline.

const englishDictionaryAsset = 'assets/dictionary/en_dictionary.sqlite.gz';

/// Bump with DICTIONARY_VERSION in tool/build_dictionary.py, so tablets
/// unpack the new file.
const dictionaryVersion = 1;

enum WordClass {
  noun('noun'),
  verb('verb'),
  adjective('adjective'),
  adverb('adverb');

  const WordClass(this.label);

  final String label;

  static WordClass fromCode(String code) => switch (code) {
        'v' => verb,
        'a' => adjective,
        'r' => adverb,
        _ => noun,
      };
}

/// One meaning of a word.
@immutable
class DictSense {
  const DictSense(this.wordClass, this.definition, {this.example});

  final WordClass wordClass;
  final String definition;

  /// A sentence using it, or null.
  final String? example;
}

/// What the dictionary says about a word.
@immutable
class DictEntry {
  const DictEntry({
    required this.word,
    this.say,
    required this.senses,
    this.similar = const [],
    this.opposites = const [],
  });

  /// The headword, as the dictionary writes it ("conserve" for "conserved").
  final String word;

  /// How it's said ("kən-SURV"), or null if the dictionary doesn't know.
  final String? say;

  /// Most used first, the word class with most meanings first.
  final List<DictSense> senses;

  /// Similar words (the thesaurus), closest first.
  final List<String> similar;
  final List<String> opposites;

  /// The meanings grouped by word class, in order.
  List<(WordClass, List<DictSense>)> get groups {
    final out = <(WordClass, List<DictSense>)>[];
    for (final s in senses) {
      if (out.isEmpty || out.last.$1 != s.wordClass) {
        out.add((s.wordClass, [s]));
      } else {
        out.last.$2.add(s);
      }
    }
    return out;
  }
}

/// The bundled dictionary, opened read-only.
class Dictionary {
  Dictionary(this._db);

  final Database _db;

  /// Opens the dictionary in [dir], unpacking it from the app's assets the
  /// first time (and after an update that changed it).
  static Future<Dictionary> open(AssetBundle bundle, Directory dir) async {
    final file = File(p.join(dir.path, 'en-dictionary-v$dictionaryVersion.sqlite'));
    if (!await file.exists() || await file.length() == 0) {
      await dir.create(recursive: true);
      final data = await bundle.load(englishDictionaryAsset);
      final packed = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final part = File('${file.path}.part');
      await compute(_unpack, (packed, part.path));
      await part.rename(file.path);
      // Older versions go.
      await for (final old in dir.list()) {
        final name = p.basename(old.path);
        if (old is File && name.startsWith('en-dictionary-v') && old.path != file.path) {
          await old.delete().catchError((_) => old);
        }
      }
    }
    return Dictionary(sqlite3.open(file.path, mode: OpenMode.readOnly));
  }

  static Future<void> _unpack((Uint8List, String) job) => File(job.$2).writeAsBytes(gzip.decode(job.$1), flush: true);

  void close() => _db.close();

  /// The entry for [query], or for the word it's a form of ("conserved",
  /// "geese"); null if there's none.
  DictEntry? lookup(String query) {
    final key = normalizeLookup(query);
    if (key.isEmpty) return null;
    for (final k in _candidates(key)) {
      final entry = _entry(k);
      if (entry != null) return entry;
    }
    return null;
  }

  /// [key] itself, the words it's an irregular form of, then what taking
  /// off an ending gives (WordNet's "morphy" rules).
  Iterable<String> _candidates(String key) sync* {
    yield key;
    for (final row in _db.select('SELECT key FROM forms WHERE form = ?', [key])) {
      yield row['key'] as String;
    }
    for (final (end, put) in _endings) {
      if (key.length > end.length + 1 && key.endsWith(end)) {
        final base = key.substring(0, key.length - end.length) + put;
        yield base;
        // stopped → stop, bigger → big
        if (put.isEmpty && base.length > 2 && base[base.length - 1] == base[base.length - 2]) {
          yield base.substring(0, base.length - 1);
        }
      }
    }
  }

  static const _endings = [
    ('ies', 'y'), ('ses', 's'), ('xes', 'x'), ('zes', 'z'), ('ches', 'ch'), ('shes', 'sh'), ('men', 'man'), //
    ('es', 'e'), ('es', ''), ('s', ''), ('ed', 'e'), ('ed', ''), ('ing', 'e'), ('ing', ''),
    ('est', 'e'), ('est', ''), ('er', 'e'), ('er', ''),
  ];

  DictEntry? _entry(String key) {
    final rows = _db.select(
      'SELECT s.word, s.pos, s.synset, s.ants, y.def, y.ex, y.similar '
      'FROM senses s JOIN synsets y ON y.id = s.synset WHERE s.key = ? ORDER BY s.word DESC, s.pos, s.n',
      [key],
    );
    if (rows.isEmpty) return null;
    // "march" before "March": lower case sorts after capitals, hence DESC.
    final word = rows.first['word'] as String;
    final byClass = <WordClass, List<(DictSense, int, String?, String?)>>{};
    for (final r in rows) {
      final wc = WordClass.fromCode(r['pos'] as String);
      final examples = ((r['ex'] as String?) ?? '').split('\n').where((e) => e.isNotEmpty).toList();
      final sense = DictSense(wc, r['def'] as String, example: _bestExample(examples, key));
      (byClass[wc] ??= []).add((sense, r['synset'] as int, r['ants'] as String?, r['similar'] as String?));
    }
    // The class with the most meanings first ("conserve" is mostly a verb).
    final classes = byClass.keys.toList()
      ..sort((a, b) {
        final c = byClass[b]!.length.compareTo(byClass[a]!.length);
        return c != 0 ? c : a.index.compareTo(b.index);
      });
    final ordered = [for (final c in classes) ...byClass[c]!];

    final similar = <String>[];
    final seen = {key};
    void add(String w) {
      final k = w.toLowerCase();
      // Not the word's own plural, nor a plural of one already listed ("conserves", "preserves").
      if (k == '${key}s' || k == '${key}es' || (k.endsWith('s') && seen.contains(k.substring(0, k.length - 1)))) return;
      if (similar.length < 30 && seen.add(k)) similar.add(w);
    }

    final synsets = [for (final o in ordered) o.$2];
    final members = _members([...synsets, for (final o in ordered) ..._ids(o.$4)]);
    for (final id in synsets) {
      members[id]?.forEach(add);
    }
    // Adjectives: the words of similar meanings too.
    for (final o in ordered) {
      for (final id in _ids(o.$4)) {
        members[id]?.forEach(add);
      }
    }
    final opposites = <String>[];
    for (final o in ordered) {
      for (final a in (o.$3 ?? '').split('|')) {
        if (a.isNotEmpty && !opposites.contains(a)) opposites.add(a);
      }
    }
    final say = _db.select('SELECT say FROM say WHERE key = ?', [key]).firstOrNull?['say'] as String?;
    return DictEntry(
      word: word,
      say: say,
      senses: [for (final o in ordered) o.$1],
      similar: similar,
      opposites: opposites,
    );
  }

  static List<int> _ids(String? similar) => [
        for (final s in (similar ?? '').split(' ')) ?int.tryParse(s),
      ];

  /// The words of each synset in [ids].
  Map<int, List<String>> _members(List<int> ids) {
    if (ids.isEmpty) return const {};
    final unique = ids.toSet().toList();
    final out = <int, List<String>>{};
    final marks = List.filled(unique.length, '?').join(',');
    for (final r in _db.select('SELECT synset, word FROM senses WHERE synset IN ($marks)', unique)) {
      (out[r['synset'] as int] ??= []).add(r['word'] as String);
    }
    return out;
  }

  /// The example that uses the word itself, if one does; else the first.
  static String? _bestExample(List<String> examples, String key) {
    if (examples.isEmpty) return null;
    final stem = key.length > 4 ? key.substring(0, key.length - 2) : key;
    return examples.firstWhere((e) => e.toLowerCase().contains(stem), orElse: () => examples.first);
  }
}

/// How a typed or tapped word is looked up: lower case, straight
/// apostrophes, single spaces, no punctuation around it.
String normalizeLookup(String query) => query
    .trim()
    .toLowerCase()
    .replaceAll('’', "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp(r"^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$", unicode: true), '');
