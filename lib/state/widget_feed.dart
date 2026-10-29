import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../calendar/calendar_state.dart';
import '../canvas/widget_items.dart';
import '../library/library.dart';
import '../planner/planner_state.dart';
import '../study/study_state.dart';

// What the widgets on the page show (WidgetBoard.png), gathered from the
// calendar, the planner and the study data. A canvas watching it draws its
// widgets again when it changes; painters read [widgetFeed], so thumbnails
// and exports show the same.

final widgetFeedProvider = Provider<WidgetFeed>((ref) {
  final library = ref.watch(libraryProvider);
  final feed = WidgetFeed(
    calendar: ref.watch(calendarProvider),
    deadlines: ref.watch(deadlinesProvider),
    planner: ref.watch(plannerProvider),
    study: ref.watch(studyProvider),
    decks: ref.watch(decksProvider),
    notebooks: {for (final n in library.notebooks) n.id: (title: n.title, folder: n.folder)},
  );
  widgetFeed = feed;
  return feed;
});
