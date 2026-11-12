import 'package:flutter_riverpod/misc.dart' show Override;

import '../board/store.dart';
import '../calendar/calendar_model.dart';
import '../calendar/calendar_state.dart';
import '../library/index_db.dart';
import '../library/library.dart';
import '../planner/planner_model.dart';
import '../planner/planner_state.dart';
import '../spelling/my_handwriting.dart';
import '../study/study_state.dart';
import '../sync/sync_state.dart';
import '../templates/templates.dart';
import 'journal.dart' show initialRecoveryProvider;
import 'settings.dart';

/// Loads settings, the library (refreshing the index from the `.board`
/// files), saved templates, the flashcard decks, the calendar and the
/// planner, and returns the
/// overrides the app starts with.
Future<List<Override>> bootstrap(BoardStore store, {IndexDb? index, DateTime Function() clock = DateTime.now}) async {
  final json = await store.loadSettings();
  final settings = json == null ? AppSettings() : AppSettings.fromJson(json);
  final db = index ?? IndexDb.memory();
  final library = await loadLibrary(store, db, clock().toUtc());
  final templates = await loadUserTemplates(store);
  final hand = MyHandwriting.fromJson(await store.loadHandwriting());
  final decks = decksFromJson(await store.loadDecks());
  final calendar = CalendarData.fromJson(await store.loadCalendar());
  final planner = PlannerData.fromJson(await store.loadPlanner());
  final sync = await loadSyncSettings(store);
  // A notebook with strokes in its journal: Endless closed before they
  // were saved (crash recovery). The one written in last opens.
  final journals = await store.listJournals();
  final lost = journals.isEmpty
      ? null
      : (library.notebooks.where((n) => journals.contains(n.id)).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)))
          .firstOrNull
          ?.id;

  return [
    boardStoreProvider.overrideWithValue(store),
    initialSettingsProvider.overrideWithValue(settings),
    indexDbProvider.overrideWithValue(db),
    initialLibraryProvider.overrideWithValue(library),
    initialTemplatesProvider.overrideWithValue(templates),
    initialHandwritingProvider.overrideWithValue(hand),
    initialDecksProvider.overrideWithValue(decks),
    initialCalendarProvider.overrideWithValue(calendar),
    initialPlannerProvider.overrideWithValue(planner),
    initialSyncSettingsProvider.overrideWithValue(sync),
    clockProvider.overrideWithValue(clock),
    initialRecoveryProvider.overrideWithValue(lost),
  ];
}
