import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'state/settings.dart';
import 'theme/app_theme.dart';
import 'ui/canvas/canvas_screen.dart';

/// Routes. Phase 1 opens straight into the last notebook's canvas; Start,
/// Library, Calendar, Flashcards, Remember and Settings join in later phases.
final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (context, state) => const CanvasScreen()),
  ]);
  ref.onDispose(router.dispose);
  return router;
});

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
