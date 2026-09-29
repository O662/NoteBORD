import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../canvas/pane.dart';
import '../library/library.dart';
import '../state/notebook.dart';
import '../theme/colors.dart';
import '../theme/tokens.g.dart';
import 'dialogs.dart';

/// App locations. Start → Library (`/library`, a folder, or `/trash`) →
/// a notebook (`/notebook/:id`) → Split view (`/split`).
abstract final class Routes {
  static const start = '/';
  static const all = '/library';
  static const trash = '/trash';

  /// A folder in the library; `[]` is All notebooks.
  static String library([List<String> folder = const []]) =>
      Uri(path: all, queryParameters: folder.isEmpty ? null : {'f': folder}).toString();

  static String notebook(String id, {int? page}) =>
      Uri(path: '/notebook/$id', queryParameters: page == null ? null : {'page': '$page'}).toString();

  /// Two panes: (notebook id, page index) on the left and right.
  static String split((String, int) left, (String, int) right) => Uri(path: '/split', queryParameters: {
        'a': left.$1,
        'ap': '${left.$2}',
        'b': right.$1,
        'bp': '${right.$2}',
      }).toString();
}

/// Back from a notebook: to wherever it was opened from, else the library.
void leaveNotebook(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(Routes.all);
  }
}

/// Opens a notebook where this device left it.
void openNotebook(BuildContext context, WidgetRef ref, String id) {
  final page = ref.read(libraryProvider).byId(id)?.lastPage ?? 0;
  context.push(Routes.notebook(id, page: page));
}

/// Loads a notebook, then shows [builder] with it open. Keeps the notebook
/// open (and autosaving) while this is on screen.
class NotebookGate extends ConsumerWidget {
  const NotebookGate({super.key, required this.pane, required this.builder, this.compact = false});

  final Pane pane;
  final WidgetBuilder builder;

  /// Inside a split pane: no full-screen error page.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListenableBuilder(
        listenable: pane,
        // A Consumer, so switching the pane's notebook drops the old one.
        builder: (context, _) => Consumer(builder: (context, ref, _) {
          final loaded = ref.watch(loadedNotebookProvider(pane.notebookId));
          return loaded.when(
            skipLoadingOnReload: true,
            data: (_) {
              // Watching keeps the notebook open for as long as this is shown.
              pane.clampTo(ref.watch(notebookProvider(pane.notebookId).select((s) => s.pages.length)));
              return builder(context);
            },
            loading: () => ColoredBox(color: context.colors.bg),
            error: (e, _) => _Missing(compact: compact),
          );
        }),
      );
}

class _Missing extends StatelessWidget {
  const _Missing({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final body = Center(
      child: Column(mainAxisSize: MainAxisSize.min, spacing: 14, children: [
        Text(
          'This notebook couldn’t be opened',
          style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 28, color: c.text),
        ),
        Text('It may have been deleted on another device.', style: TextStyle(fontSize: 15, color: c.textMuted)),
        if (!compact) SecondaryButton(label: 'Back to library', onPressed: () => context.go(Routes.all)),
      ]),
    );
    return compact ? ColoredBox(color: c.bg, child: body) : Scaffold(body: body);
  }
}
