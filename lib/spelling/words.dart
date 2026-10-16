import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle;

// The words spell check accepts (assets/dictionary/en_words.txt.gz, built
// by tool/build_dictionary.py from SCOWL and Open English WordNet), and
// spelling suggestions.

/// Where the bundled English word list is.
const englishWordsAsset = 'assets/dictionary/en_words.txt.gz';

/// Every word spell check knows, with how common each one is.
class WordList {
  WordList._(this._levels, this._written, this._byLength);

  /// Lower case → its SCOWL level: 10 for the most common words, up to 80
  /// for rare ones.
  final Map<String, int> _levels;

  /// Lower case → as it's written, for words with capitals ("sunday" →
  /// "Sunday").
  final Map<String, String> _written;

  /// Lower-case words by length, for suggestions.
  final Map<int, List<String>> _byLength;

  /// Reads the list's text: `#<level>` lines, each followed by its words.
  factory WordList.parse(String text) {
    final levels = <String, int>{};
    final written = <String, String>{};
    final lower = <String>{};
    var level = 80;
    for (final line in const LineSplitter().convert(text)) {
      if (line.isEmpty) continue;
      if (line.startsWith('#')) {
        level = int.tryParse(line.substring(1)) ?? level;
        continue;
      }
      final key = line.toLowerCase();
      final before = levels[key];
      if (before == null || level < before) levels[key] = level;
      // A lower-case spelling wins: "march" over "March".
      if (line == key) {
        lower.add(key);
        written.remove(key);
      } else if (!lower.contains(key)) {
        written.putIfAbsent(key, () => line);
      }
    }
    final byLength = <int, List<String>>{};
    for (final w in levels.keys) {
      (byLength[w.length] ??= []).add(w);
    }
    return WordList._(levels, written, byLength);
  }

  /// A list of just [words] (for tests).
  factory WordList.of(Map<String, int> words) =>
      WordList.parse([for (final e in words.entries) '#${e.value}\n${e.key}'].join('\n'));

  /// Loads the bundled list, unpacking it on a background isolate.
  static Future<WordList> load(AssetBundle bundle, {String asset = englishWordsAsset}) async {
    final data = await bundle.load(asset);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    return compute(_unpack, bytes);
  }

  static WordList _unpack(Uint8List bytes) => WordList.parse(utf8.decode(gzip.decode(bytes)));

  int get length => _levels.length;

  /// Its level (lower is more common), or null if it isn't a word.
  int? levelOf(String word) => _levels[word.toLowerCase()];

  bool contains(String word) => _levels.containsKey(word.toLowerCase());

  /// How [key] (lower case) is written in the list.
  String writtenAs(String key) => _written[key] ?? key;

  /// Up to [count] words close to [word], best first. [hints] (other
  /// readings of a handwritten word) come first when they are words.
  List<String> suggest(String word, {Iterable<String> hints = const [], int count = 3}) {
    final key = word.toLowerCase();
    final scored = <String, double>{};
    for (final h in hints) {
      final k = h.toLowerCase();
      if (k != key && _levels.containsKey(k)) scored[k] = -1 + _commonness(k);
    }
    for (var len = math.max(1, key.length - 2); len <= key.length + 2; len++) {
      for (final w in _byLength[len] ?? const <String>[]) {
        if (scored.containsKey(w) || w == key) continue;
        final d = spellingDistance(key, w);
        if (d > maxSuggestDistance) continue;
        scored[w] = d + _commonness(w) + (w[0] == key[0] ? 0 : 0.4);
      }
    }
    final best = scored.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    return [for (final e in best.take(count)) matchCase(writtenAs(e.key), word)];
  }

  /// A little extra distance for rarer words.
  double _commonness(String key) => switch (_levels[key] ?? 80) {
        <= 10 => 0,
        <= 20 => 0.05,
        <= 35 => 0.1,
        <= 40 => 0.15,
        <= 50 => 0.25,
        <= 55 => 0.3,
        <= 60 => 0.35,
        <= 70 => 0.45,
        _ => 0.6,
      };
}

/// How far off a suggestion may be.
const maxSuggestDistance = 2.0;

bool _vowel(int c) => c == 0x61 || c == 0x65 || c == 0x69 || c == 0x6F || c == 0x75 || c == 0x79;

/// An edit distance tuned for misspellings: a vowel for another vowel
/// (sistem → system) costs 0.7, a doubled or undoubled letter (colision →
/// collision) 0.6, two letters swapped (recieve → receive) 0.8, anything
/// else 1. Stops early once it's past [maxSuggestDistance] (and then says
/// so by returning something larger).
double spellingDistance(String a, String b) {
  final n = a.length, m = b.length;
  if ((n - m).abs() > maxSuggestDistance) return maxSuggestDistance + 1;
  var prev2 = Float64List(m + 1);
  var prev = Float64List(m + 1);
  var row = Float64List(m + 1);
  for (var j = 0; j <= m; j++) {
    prev[j] = j.toDouble();
  }
  for (var i = 1; i <= n; i++) {
    final ca = a.codeUnitAt(i - 1);
    row[0] = i.toDouble();
    var best = row[0];
    for (var j = 1; j <= m; j++) {
      final cb = b.codeUnitAt(j - 1);
      final sub = ca == cb ? 0.0 : (_vowel(ca) && _vowel(cb) ? 0.7 : 1.0);
      // Deleting a's letter, or inserting b's: cheaper when it doubles the one beside it.
      final del = (i >= 2 && a.codeUnitAt(i - 2) == ca) || (i < n && a.codeUnitAt(i) == ca) ? 0.6 : 1.0;
      final ins = (j >= 2 && b.codeUnitAt(j - 2) == cb) || (j < m && b.codeUnitAt(j) == cb) ? 0.6 : 1.0;
      var v = math.min(prev[j - 1] + sub, math.min(prev[j] + del, row[j - 1] + ins));
      if (i >= 2 && j >= 2 && ca == b.codeUnitAt(j - 2) && a.codeUnitAt(i - 2) == cb && ca != cb) {
        v = math.min(v, prev2[j - 2] + 0.8);
      }
      row[j] = v;
      if (v < best) best = v;
    }
    if (best > maxSuggestDistance) return maxSuggestDistance + 1;
    final t = prev2;
    prev2 = prev;
    prev = row;
    row = t;
  }
  return prev[m];
}

/// [word] with the capitals of [like]: all capitals, a first capital, or
/// as it is.
String matchCase(String word, String like) {
  if (like.length > 1 && like == like.toUpperCase() && like != like.toLowerCase()) return word.toUpperCase();
  if (like.isNotEmpty && like[0] != like[0].toLowerCase()) return word[0].toUpperCase() + word.substring(1);
  return word;
}
