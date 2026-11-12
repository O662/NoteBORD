import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../canvas/pane.dart';
import '../library/library.dart';
import '../state/notebook.dart';
import '../state/settings.dart' show boardStoreProvider;
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

  /// [spot] (page coordinates) is shown in the middle and highlighted for
  /// a moment ("Open at this spot" in Search).
  ///
  /// [turn] (an Office card's id and a page of it, or a sticky stack's id
  /// and a note under its top one) turns the card to that page, or brings
  /// that note to the top, first.
  static String notebook(String id, {int? page, Rect? spot, (String, int)? turn}) {
    final q = {
      if (page != null) 'page': '$page',
      if (turn != null) 'turn': '${turn.$1}:${turn.$2}',
      if (spot != null) 'spot': [spot.left, spot.top, spot.width, spot.height].map((v) => v.toStringAsFixed(1)).join(','),
    };
    return Uri(path: '/notebook/$id', queryParameters: q.isEmpty ? null : q).toString();
  }

  /// Settings, on a section (Sync.png: `sync`).
  static String settings([String section = 'general']) => Uri(path: '/settings', queryParameters: {'s': section}).toString();

  /// Need to remember (Remember.png).
  static const remember = '/remember';

  /// Sticky notes from every notebook (Stickies.png).
  static const stickies = '/stickies';
  static const calendar = '/calendar';
  static const planner = '/planner';

  /// The calendar's Day view on [day].
  static String calendarOn(DateTime day) => Uri(path: calendar, queryParameters: {
        'day': '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
        'view': 'day',
      }).toString();

  /// Flashcards (Study.png), on [deck] if given.
  static String flashcards([String? deck]) =>
      Uri(path: '/flashcards', queryParameters: deck == null ? null : {'deck': deck}).toString();

  /// Handwriting search, optionally with a query.
  static String search([String query = '']) =>
      Uri(path: '/search', queryParameters: query.isEmpty ? null : {'q': query}).toString();

  /// The spot in a notebook location's `spot` parameter.
  static Rect? spotFrom(String? param) {
    final v = param?.split(',').map(double.tryParse).toList();
    if (v == null || v.length != 4 || v.any((x) => x == null)) return null;
    return Rect.fromLTWH(v[0]!, v[1]!, v[2]!, v[3]!);
  }

  /// The card and page in a notebook location's `turn` parameter.
  static (String, int)? turnFrom(String? param) {
    final i = param?.lastIndexOf(':') ?? -1;
    if (i <= 0) return null;
    final page = int.tryParse(param!.substring(i + 1));
    return page == null ? null : (param.substring(0, i), page);
  }

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

/// Opens [pageId] of a notebook with [spot] in the middle, highlighted
/// (from Remember, Flashcards and reminders). [replace] swaps the screen
/// showing for it.
Future<void> openSpot(
  BuildContext context,
  WidgetRef ref,
  String notebookId,
  String pageId,
  Rect? spot, {
  bool replace = false,
}) async {
  final pages = (await ref.read(boardStoreProvider).loadNotebookMeta(notebookId))?.pageIds;
  final index = pages?.indexOf(pageId) ?? -1;
  final page = index >= 0 ? index : ref.read(libraryProvider).byId(notebookId)?.lastPage ?? 0;
  if (!context.mounted) return;
  ref.read(libraryProvider.notifier).recordOpened(notebookId, page);
  final to = Routes.notebook(notebookId, page: page, spot: index >= 0 ? spot : null);
  if (replace) {
    context.pushReplacement(to);
  } else {
    context.push(to);
  }
}

/// Opens a notebook where this device left it.
void openNotebook(BuildContext context, WidgetRef ref, String id) {
  final page = ref.read(libraryProvider).byId(id)?.lastPage ?? 0;
  context.push(Routes.notebook(id, page: page));
}

/// Loads a notebook, then shows [builder] with it open. Keeps the notebook
/// open (and autosaving) while this is on screen, and keeps the pane on its
/// page while pages are added, removed or moved before it.
class NotebookGate extends ConsumerStatefulWidget {
  const NotebookGate({super.key, required this.pane, required this.builder, this.compact = false, this.onFollowed});

  final Pane pane;
  final WidgetBuilder builder;

  /// Inside a split pane: no full-screen error page.
  final bool compact;

  /// Called (once the frame is drawn) when the pane's page number was
  /// changed to keep it on its page: the place this device is at in the
  /// notebook has another number now.
  final VoidCallback? onFollowed;

  @override
  ConsumerState<NotebookGate> createState() => _NotebookGateState();
}

class _NotebookGateState extends ConsumerState<NotebookGate> {
  Pane get pane => widget.pane;

  /// The page the pane was on when last looked at, and how many times it
  /// had been sent somewhere by then (see [_keepOnPage]).
  ({String notebookId, String pageId, int sends})? _shown;

  @override
  void didUpdateWidget(NotebookGate old) {
    super.didUpdateWidget(old);
    if (old.pane != widget.pane) _shown = null;
  }

  /// A pane holds its page's number. When pages are added, removed or moved
  /// before that page by something other than this pane (another device's
  /// changes coming in with sync, or the other side of Split view), the
  /// number is changed so the same page stays on screen. A pane that has
  /// been sent somewhere since is left where it was sent, and one whose
  /// page is gone shows the page now in its place.
  void _keepOnPage(NotebookState nb) {
    final pages = nb.pages;
    if (pages.isEmpty) return;
    final was = _shown;
    if (was != null && was.notebookId == pane.notebookId && was.sends == pane.sends) {
      final at = nb.indexOf(was.pageId);
      if (at >= 0 && at != pane.page) {
        pane.follow(at);
        _followed();
      }
    }
    pane.clampTo(pages.length);
    _shown = (notebookId: pane.notebookId, pageId: pages[pane.page].id, sends: pane.sends);
  }

  bool _telling = false;

  /// Says so after this frame (never while widgets are being built).
  void _followed() {
    if (_telling || widget.onFollowed == null) return;
    _telling = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _telling = false;
      if (mounted) widget.onFollowed?.call();
    });
  }

  /// Which pages the notebook has, in order (changes when one is added,
  /// removed or moved; not when one is written on).
  static String _pageIds(NotebookState s) => [for (final p in s.pages) p.id].join('\n');

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: pane,
        // A Consumer, so switching the pane's notebook drops the old one.
        builder: (context, _) => Consumer(builder: (context, ref, _) {
          final id = pane.notebookId;
          final loaded = ref.watch(loadedNotebookProvider(id));
          return loaded.when(
            skipLoadingOnReload: true,
            data: (_) {
              final notebook = notebookProvider(id);
              // As the pages change, not a frame later: a stroke finished in
              // between goes on the page being written on.
              ref.listen(notebook.select(_pageIds), (_, _) {
                if (mounted && pane.notebookId == id) _keepOnPage(ref.read(notebook));
              });
              // Watching keeps the notebook open for as long as this is shown.
              ref.watch(notebook.select(_pageIds));
              _keepOnPage(ref.read(notebook));
              return widget.builder(context);
            },
            loading: () => ColoredBox(color: context.colors.bg),
            error: (e, _) => _Missing(compact: widget.compact),
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
