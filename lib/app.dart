import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'calendar/calendar_model.dart' show parseDay;
import 'calendar/calendar_sync.dart';
import 'calendar/feed_sync.dart';
import 'canvas/pane.dart';
import 'library/library.dart';
import 'recognition/handwriting_index.dart';
import 'state/settings.dart';
import 'study/reminders.dart';
import 'transfer/board_file.dart' show ImportProblem;
import 'transfer/incoming.dart';
import 'transfer/transfer.dart';
import 'ui/common.dart' show showNote;
import 'ui/dialogs.dart' show showMessage;
import 'ui/transfer/transfer_dialog.dart' show showSameNotebook;
import 'sync/sync_state.dart';
import 'theme/app_theme.dart';
import 'ui/calendar/calendar_screen.dart';
import 'ui/calendar/planner_screen.dart';
import 'ui/canvas/canvas_screen.dart';
import 'ui/library/library_screen.dart';
import 'ui/library/start_screen.dart';
import 'ui/routes.dart';
import 'ui/search/search_screen.dart';
import 'ui/settings/settings_screen.dart';
import 'ui/split/split_screen.dart';
import 'ui/study/remember_screen.dart';
import 'ui/study/stickies_screen.dart';
import 'ui/study/study_screen.dart';
import 'state/journal.dart' show initialRecoveryProvider;

/// Where the app opens. Tests start straight in a notebook.
final initialLocationProvider = Provider<String>((ref) => Routes.start);

/// Where the app opens: the Start page, or with Settings › General › Open
/// to "Last note I was in", that notebook (if it's still there). After an
/// unexpected exit, the notebook being written in, so its last strokes come
/// back (Recovery.png).
String _openingLocation(Ref ref) {
  final location = ref.read(initialLocationProvider);
  final settings = ref.read(settingsProvider);
  final lost = ref.read(initialRecoveryProvider);
  if (location == Routes.start && lost != null) {
    final entry = ref.read(libraryProvider).byId(lost);
    if (entry != null && !entry.trashed) return Routes.notebook(lost, page: entry.lastPage);
  }
  final last = settings.lastNotebookId;
  if (location != Routes.start || !settings.openLastNote || last == null) return location;
  final entry = ref.read(libraryProvider).byId(last);
  if (entry == null || entry.trashed) return location;
  return Routes.notebook(last, page: entry.lastPage);
}

/// Routes (see [Routes]). Library pages sit under Start, so back from the
/// library returns to Start; notebooks and Split view are pushed on top.
final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: _openingLocation(ref),
    routes: [
      GoRoute(
        path: Routes.start,
        builder: (context, state) => const StartScreen(),
        routes: [
          GoRoute(
            path: 'library',
            builder: (context, state) => LibraryScreen(folder: state.uri.queryParametersAll['f'] ?? const []),
          ),
          GoRoute(path: 'trash', builder: (context, state) => const LibraryScreen(trash: true)),
        ],
      ),
      GoRoute(
        path: '/notebook/:id',
        builder: (context, state) => NotebookRoute(
          id: state.pathParameters['id']!,
          page: int.tryParse(state.uri.queryParameters['page'] ?? ''),
          spot: Routes.spotFrom(state.uri.queryParameters['spot']),
          turn: Routes.turnFrom(state.uri.queryParameters['turn']),
        ),
      ),
      GoRoute(path: Routes.remember, builder: (context, state) => const RememberScreen()),
      GoRoute(path: Routes.stickies, builder: (context, state) => const StickiesScreen()),
      GoRoute(
        path: '/settings',
        builder: (context, state) => SettingsScreen(section: SettingsSection.parse(state.uri.queryParameters['s'])),
      ),
      GoRoute(
        path: Routes.calendar,
        builder: (context, state) => CalendarScreen(
          view: CalendarView.values.where((v) => v.name == state.uri.queryParameters['view']).firstOrNull ?? CalendarView.week,
          day: parseDay(state.uri.queryParameters['day']),
        ),
      ),
      GoRoute(path: Routes.planner, builder: (context, state) => const PlannerScreen()),
      GoRoute(
        path: '/flashcards',
        builder: (context, state) => StudyScreen(deck: state.uri.queryParameters['deck']),
      ),
      GoRoute(
        path: '/search',
        builder: (context, state) => SearchScreen(query: state.uri.queryParameters['q'] ?? ''),
      ),
      GoRoute(
        path: '/split',
        builder: (context, state) {
          final q = state.uri.queryParameters;
          return SplitScreen(
            left: (q['a'] ?? '', int.tryParse(q['ap'] ?? '') ?? 0),
            right: (q['b'] ?? q['a'] ?? '', int.tryParse(q['bp'] ?? '') ?? 0),
          );
        },
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// The Canvas screen for one notebook.
class NotebookRoute extends ConsumerStatefulWidget {
  const NotebookRoute({super.key, required this.id, this.page, this.spot, this.turn});

  final String id;
  final int? page;

  /// A place on the page to show and highlight (from Search).
  final Rect? spot;

  /// An Office card to turn to one of its pages first (from Search).
  final (String, int)? turn;

  @override
  ConsumerState<NotebookRoute> createState() => _NotebookRouteState();
}

class _NotebookRouteState extends ConsumerState<NotebookRoute> {
  late final pane = Pane(
    widget.id,
    page: widget.page ?? ref.read(libraryProvider).byId(widget.id)?.lastPage ?? 0,
  )
    ..spot = widget.spot
    ..spotTurn = widget.turn;

  @override
  void dispose() {
    pane.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NotebookGate(
        pane: pane,
        // "Continue writing" comes back to this page under its new number.
        onFollowed: () => ref.read(libraryProvider.notifier).recordOpened(pane.notebookId, pane.page),
        builder: (context) => CanvasScreen(pane: pane),
      );
}

class EndlessApp extends ConsumerStatefulWidget {
  const EndlessApp({super.key});

  /// How long after starting the app goes through older notebooks' handwriting.
  static const catchUpAfter = Duration(seconds: 4);

  @override
  ConsumerState<EndlessApp> createState() => _EndlessAppState();
}

class _EndlessAppState extends ConsumerState<EndlessApp> {
  Timer? _catchUp;

  @override
  void initState() {
    super.initState();
    // Notebooks written before (or on another device) become searchable in
    // the background, once the first screen is up.
    if (ref.read(catchUpOnStartProvider)) {
      _catchUp = Timer(EndlessApp.catchUpAfter, () => ref.read(handwritingIndexProvider).catchUp());
    }
    // Reminders from Need to remember follow what's remembered; a tapped
    // one opens the notebook where it is. Calendar links show their last
    // copy, then are read again.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(feedSyncProvider.notifier).start());
      // Google and Outlook calendars sync both ways, if one is connected.
      if (ref.read(autoCalendarSyncProvider)) unawaited(ref.read(calendarSyncProvider.notifier).start());
      // Cloud sync (if it's set up) starts a moment after the app does.
      ref.read(syncProvider.notifier).start();
      // A board file opened with Endless from another app is imported.
      final incoming = ref.read(incomingFilesProvider);
      incoming.listen(() => unawaited(_openIncoming()));
      unawaited(_openIncoming());
      final service = ref.read(reminderServiceProvider);
      if (!service.available) return;
      service.start(_openReminder);
      ref.read(reminderSyncProvider);
    });
  }

  /// Imports files opened with Endless from another app (a board file from
  /// Gmail, Drive, OneDrive or Files) into All notebooks, and opens the
  /// notebook. One already here asks Replace or Keep both, as Import does.
  Future<void> _openIncoming() async {
    final files = await ref.read(incomingFilesProvider).take();
    if (files.isEmpty || !mounted) return;
    final router = ref.read(routerProvider);
    BuildContext? here() => router.routerDelegate.navigatorKey.currentContext;
    try {
      final outcome = await ref.read(transfersProvider).import(
        files,
        const ImportTarget.folder([]),
        sameNotebook: (title) async {
          final c = here();
          return c == null || !c.mounted ? SameNotebook.keepBoth : showSameNotebook(c, title);
        },
      );
      if (!mounted) return;
      if (outcome.openNotebook case final id?) router.push(Routes.notebook(id));
      final c = here();
      if (c != null && c.mounted) showNote(c, outcome.message);
    } on ImportProblem catch (e) {
      final c = here();
      if (c != null && c.mounted) await showMessage(c, title: 'Can’t open this file', message: e.message);
    }
  }

  Future<void> _openReminder(String payload) async {
    final target = ReminderTarget.parse(payload);
    if (target == null || !mounted) return;
    final pages = (await ref.read(boardStoreProvider).loadNotebookMeta(target.notebookId))?.pageIds;
    if (pages == null || !mounted) return;
    final page = pages.indexOf(target.pageId);
    ref.read(routerProvider).push(Routes.notebook(target.notebookId, page: page < 0 ? 0 : page, spot: page < 0 ? null : target.rect));
  }

  @override
  void dispose() {
    _catchUp?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final (theme, accent) = ref.watch(settingsProvider.select((s) => (s.theme, s.accent)));
    return MaterialApp.router(
      title: 'Endless',
      debugShowCheckedModeBanner: false,
      theme: themeFor(theme, accent, Brightness.light),
      darkTheme: themeFor(theme, accent, Brightness.dark),
      themeMode: themeMode,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
