import 'package:flutter_riverpod/misc.dart' show Override;

import '../board/store.dart';
import '../library/index_db.dart';
import '../library/library.dart';
import '../templates/templates.dart';
import 'settings.dart';

/// Loads settings, the library (refreshing the index from the `.board`
/// files) and saved templates, and returns the overrides the app starts with.
Future<List<Override>> bootstrap(BoardStore store, {IndexDb? index, DateTime Function() clock = DateTime.now}) async {
  final json = await store.loadSettings();
  final settings = json == null ? AppSettings() : AppSettings.fromJson(json);
  final db = index ?? IndexDb.memory();
  final library = await loadLibrary(store, db, clock().toUtc());
  final templates = await loadUserTemplates(store);

  return [
    boardStoreProvider.overrideWithValue(store),
    initialSettingsProvider.overrideWithValue(settings),
    indexDbProvider.overrideWithValue(db),
    initialLibraryProvider.overrideWithValue(library),
    initialTemplatesProvider.overrideWithValue(templates),
    clockProvider.overrideWithValue(clock),
  ];
}
