import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'canvas/pane.dart';
import 'library/library.dart';
import 'state/settings.dart';
import 'theme/app_theme.dart';
import 'ui/canvas/canvas_screen.dart';
import 'ui/library/library_screen.dart';
import 'ui/library/start_screen.dart';
import 'ui/routes.dart';
import 'ui/split/split_screen.dart';

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
        ),
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
  const NotebookRoute({super.key, required this.id, this.page});

  final String id;
  final int? page;

  @override
  ConsumerState<NotebookRoute> createState() => _NotebookRouteState();
}

class _NotebookRouteState extends ConsumerState<NotebookRoute> {
  late final pane = Pane(
    widget.id,
    page: widget.page ?? ref.read(libraryProvider).byId(widget.id)?.lastPage ?? 0,
  );

  @override
  void dispose() {
    pane.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotebookGate(pane: pane, builder: (context) => CanvasScreen(pane: pane));
}

class EndlessApp extends ConsumerWidget {
  const EndlessApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
