import 'dart:io';

import 'package:endless/spelling/dictionary.dart';
import 'package:endless/spelling/speech.dart';
import 'package:endless/spelling/spelling_state.dart';
import 'package:endless/spelling/words.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

// The real word list and dictionary, loaded once per test file (widget
// tests run on fake time, which can't wait for an isolate or the disk).

WordList? _words;
Dictionary? _dictionary;
Directory? _dir;

/// Loads them; call from setUpAll.
Future<void> loadSpelling() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  _words ??=await WordList.load(rootBundle);
  if (_dictionary == null) {
    _dir = Directory.systemTemp.createTempSync('endless_dictionary_test');
    _dictionary = await Dictionary.open(rootBundle, _dir!);
    addTearDown(() {
      _dictionary?.close();
      _dictionary = null;
      _dir?.deleteSync(recursive: true);
    });
  }
}

WordList get testWords => _words!;
Dictionary get testDictionary => _dictionary!;

class FakeSpeech implements Speech {
  @override
  bool available = true;
  final said = <String>[];

  @override
  Future<bool> say(String text, {String language = 'en-US'}) async {
    said.add(text);
    return true;
  }
}

/// The loaded word list and dictionary, and [speech].
List<Override> spellingOverrides({Speech? speech}) => [
      wordListProvider.overrideWith((ref) => testWords),
      dictionaryProvider.overrideWith((ref) => testDictionary),
      speechProvider.overrideWithValue(speech ?? FakeSpeech()),
    ];
