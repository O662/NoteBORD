import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'canvas/pane.dart';
import 'library/library.dart';
import 'recognition/handwriting_index.dart';
import 'state/settings.dart';
import 'study/reminders.dart';
import 'theme/app_theme.dart';
import 'ui/canvas/canvas_screen.dart';
import 'ui/library/library_screen.dart';
import 'ui/library/start_screen.dart';
import 'ui/routes.dart';
import 'ui/search/search_screen.dart';
import 'ui/split/split_screen.dart';
import 'ui/study/remember_screen.dart';
import 'ui/study/study_screen.dart';

/// Where the app opens. Tests start straight in a notebook.
final initialLocationProvider = Provider<String>((ref) => Routes.start);

/// Routes (see [Routes]). Library pages sit under Start, so back from the
/// library returns to Start; notebooks and Split view are pushed on top.
final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: ref.read(initialLocationProvider),
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
  Widget build(BuildContext context) =>
      NotebookGate(pane: pane, builder: (context) => CanvasScreen(pane: pane));
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
    // one opens the notebook where it is.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final service = ref.read(reminderServiceProvider);
      if (!service.available) return;
      service.start(_openReminder);
      ref.read(reminderSyncProvider);
    });
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
    return MaterialApp.router(
      title: 'Endless',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
