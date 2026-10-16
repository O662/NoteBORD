import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../state/settings.dart';
import 'dictionary.dart';
import 'spell_check.dart';
import 'words.dart';

/// The bundled English word list, loaded once.
final wordListProvider = FutureProvider<WordList>((ref) => WordList.load(rootBundle));

/// The word list plus "my dictionary".
final spellerProvider = FutureProvider<Speller>((ref) async {
  final words = await ref.watch(wordListProvider.future);
  return Speller(words, mine: ref.watch(settingsProvider.select((s) => s.myWords)));
});

/// Where the dictionary is unpacked: the app's support folder (set in
/// main.dart), else a temporary folder.
final dictionaryDirProvider =
    Provider<Directory>((ref) => Directory(p.join(Directory.systemTemp.path, 'endless_dictionary')));

/// The dictionary and thesaurus, unpacked on first use.
final dictionaryProvider = FutureProvider<Dictionary>((ref) async {
  final dictionary = await Dictionary.open(rootBundle, ref.read(dictionaryDirProvider));
  ref.onDispose(dictionary.close);
  return dictionary;
});
