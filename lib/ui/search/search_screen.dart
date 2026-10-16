import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../board/model.dart';
import '../../canvas/page_runtime.dart';
import '../../library/library.dart';
import '../../recognition/handwriting_index.dart';
import '../../recognition/models.dart';
import '../../recognition/reader.dart' show visibleInk;
import '../../recognition/segment.dart' show inkRect;
import '../../search/search.dart';
import '../../search/search_text.dart';
import '../../state/notebook.dart';
import '../../state/settings.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../icons.dart';
import '../routes.dart';
import 'write_query.dart';

/// Handwriting search (design/screens/Search.png): every notebook's
/// recognized handwriting, typed text and text inside PDFs, with the match
/// shown on its page and "Open at this spot".
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.query = ''});

  final String query;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final _field = TextEditingController(text: widget.query);
  final _focus = FocusNode();
  Timer? _debounce;
  List<SearchHit> _hits = const [];
  String _searched = '';
  bool _searching = false;
  int _run = 0;

  var _filter = SearchFilter.all;
  List<String>? _folder;
  var _date = SearchDate.any;
  int _picked = 0;

  late final HandwritingIndex _index = ref.read(handwritingIndexProvider);

  @override
  void initState() {
    super.initState();
    _index.revision.addListener(_indexChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.query.isEmpty) _focus.requestFocus();
      _search();
      // Bring the index up to date: the model comes down if it isn't here
      // yet, then older notebooks are read.
      final lang = _index.language;
      unawaited(ref.read(inkModelsProvider.notifier).ensure(lang).then((_) => mounted ? _index.catchUp() : null));
    });
  }

  @override
  void dispose() {
    _index.revision.removeListener(_indexChanged);
    _debounce?.cancel();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _indexChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _search);
  }

  void _typed(String _) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), _search);
  }

  Future<void> _search() async {
    final q = _field.text.trim();
    final mine = ++_run;
    if (q.isEmpty) {
      setState(() {
        _hits = const [];
        _searched = '';
      });
      return;
    }
    setState(() => _searching = true);
    final hits = await runSearch(
      q,
      db: ref.read(indexDbProvider),
      library: ref.read(libraryProvider),
      store: ref.read(boardStoreProvider),
      unlocked: _index.unlockedRows,
    );
    if (!mounted || mine != _run) return;
    final keep = _picked < _hits.length ? _hits[_picked] : null;
    setState(() {
      _hits = hits;
      _searched = q;
      _searching = false;
      // The picked match stays picked when the results refresh.
      final again = keep == null ? -1 : hits.indexWhere((h) => h.row.ref == keep.row.ref && h.row.pageId == keep.row.pageId);
      _picked = again < 0 ? 0 : again;
    });
  }

  void _clear() {
    _field.clear();
    _focus.requestFocus();
    _search();
  }

  Future<void> _write() async {
    final text = await showWriteQuery(context);
    if (text == null || text.trim().isEmpty || !mounted) return;
    _field.text = text.trim();
    _search();
  }

  void _open(SearchHit hit, Rect spot) {
    ref.read(libraryProvider.notifier).recordOpened(hit.notebook.id, hit.pageIndex);
    // Handwriting on a slide the card isn't showing, or on a note under a
    // stack's top one: the card turns to it, the note comes to the top.
    final holder = hit.row.holder, sub = hit.row.sub;
    final turn = holder != null && sub != null ? (holder, sub) : null;
    context.pushReplacement(Routes.notebook(hit.notebook.id, page: hit.pageIndex, spot: spot, turn: turn));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = ref.read(clockProvider)();
    final narrowed = narrow(_hits, folder: _folder, date: _date, now: now);
    final shown = [for (final h in narrowed) if (_filter.takes(h.row.kind)) h];
    final picked = shown.isEmpty ? null : shown[_picked.clamp(0, shown.length - 1)];
    final terms = searchTerms(_searched);

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(28, 18, 28, 14),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
              Row(spacing: 12, children: [
                _Square(label: 'Back', icon: EIcons.back, size: 22, onTap: () => leaveNotebook(context)),
                Expanded(
                  child: _SearchField(
                    controller: _field,
                    focus: _focus,
                    onChanged: _typed,
                    onWrite: _write,
                    onClear: _clear,
                  ),
                ),
              ]),
              Padding(
                padding: const EdgeInsets.only(left: 56),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(spacing: 8, children: [
                    for (final f in SearchFilter.values)
                      _FilterChip(
                        label: f.label,
                        count: narrowed.where((h) => f.takes(h.row.kind)).length,
                        on: _filter == f,
                        onTap: () => setState(() {
                          _filter = f;
                          _picked = 0;
                        }),
                      ),
                    Container(width: 1, height: 24, color: c.line, margin: const EdgeInsets.symmetric(horizontal: 6)),
                    _Dropdown<List<String>?>(
                      label: _folder == null ? 'All folders' : _folder!.join(' › '),
                      semantic: 'Folder',
                      options: [
                        (null, 'All folders'),
                        for (final f in ref.watch(libraryProvider).folders) (f.path, f.path.join(' › ')),
                      ],
                      onPick: (f) => setState(() {
                        _folder = f;
                        _picked = 0;
                      }),
                    ),
                    _Dropdown<SearchDate>(
                      label: _date.label,
                      semantic: 'Date',
                      options: [for (final d in SearchDate.values) (d, d.label)],
                      onPick: (d) => setState(() {
                        _date = d;
                        _picked = 0;
                      }),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                width: 500,
                decoration: BoxDecoration(border: Border(right: BorderSide(color: c.line))),
                child: Semantics(
                  container: true,
                  label: 'Results',
                  explicitChildNodes: true,
                  child: _Results(
                    hits: shown,
                    total: _hits.length,
                    picked: picked,
                    terms: terms,
                    searched: _searched,
                    searching: _searching,
                    onPick: (h) => setState(() => _picked = shown.indexOf(h)),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 28, 18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
                    Expanded(
                      child: picked == null
                          ? const SizedBox.shrink()
                          : _Preview(key: ValueKey('${picked.row.notebookId}/${picked.row.ref}'), hit: picked, terms: terms, onOpen: _open),
                    ),
                    _Footer(index: _index),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focus,
    required this.onChanged,
    required this.onWrite,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onChanged;
  final VoidCallback onWrite;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 54,
      padding: const EdgeInsets.fromLTRB(18, 0, 8, 0),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.accent, width: 2),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(spacing: 12, children: [
        EIcon(EIcons.search, size: 22, color: c.accent),
        Expanded(
          child: Semantics(
            label: 'Search notes and handwriting',
            textField: true,
            child: TextField(
              controller: controller,
              focusNode: focus,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: TextStyle(fontSize: 18, color: c.text),
              cursorColor: c.accent,
              decoration: InputDecoration.collapsed(
                hintText: 'Search notes and handwriting',
                hintStyle: TextStyle(fontSize: 18, color: c.textFaint),
              ),
            ),
          ),
        ),
        _Square(label: 'Write your search with the S Pen', icon: EIcons.pen, filled: true, onTap: onWrite),
        _Square(label: 'Clear search', icon: EIcons.close, size: 18, muted: true, onTap: onClear),
      ]),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.hits,
    required this.total,
    required this.picked,
    required this.terms,
    required this.searched,
    required this.searching,
    required this.onPick,
  });

  final List<SearchHit> hits;

  /// Matches before the chips, folder and date narrowed them.
  final int total;
  final SearchHit? picked;
  final List<String> terms;
  final String searched;
  final bool searching;
  final ValueChanged<SearchHit> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final notebooks = {for (final h in hits) h.notebook.id}.length;
    final summary = searched.isEmpty
        ? 'Search your handwriting, typed text and PDFs in every notebook.'
        : hits.isEmpty
            ? (searching ? 'Searching…' : total > 0 ? 'No matches with these filters' : 'No matches for “$searched”')
            : '${hits.length} ${hits.length == 1 ? 'match' : 'matches'} in $notebooks ${notebooks == 1 ? 'notebook' : 'notebooks'}';
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 18, 16, 18),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
          child: Semantics(liveRegion: true, child: Text(summary, style: TextStyle(fontSize: 14, color: c.textMuted))),
        ),
        for (final h in hits)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ResultRow(hit: h, terms: terms, selected: identical(h, picked), onTap: () => onPick(h)),
          ),
      ],
    );
  }
}

String _where(SearchHit h) {
  final folder = h.notebook.folder.join(' › ');
  final pdfPage = h.row.data['page'];
  if (h.row.kind == SearchKind.pdf && pdfPage is int) {
    return 'Page $pdfPage · Imported into ${folder.isEmpty ? h.notebook.title : folder}';
  }
  return folder.isEmpty ? 'Page ${h.pageIndex + 1}' : 'Page ${h.pageIndex + 1} · $folder';
}

String _title(SearchHit h) {
  final name = h.row.fileName;
  if (h.row.kind == SearchKind.pdf && name != null && name.isNotEmpty) return name;
  return h.notebook.title.trim().isEmpty ? 'Untitled notebook' : h.notebook.title;
}

Color _kindColor(SearchKind k, EndlessColors c) => switch (k) {
      SearchKind.ink => c.accent,
      SearchKind.typed => c.greenDeep,
      SearchKind.pdf || SearchKind.office => c.clayDeep,
    };

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.hit, required this.terms, required this.selected, required this.onTap});

  final SearchHit hit;
  final List<String> terms;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = _title(hit);
    return Semantics(
      button: true,
      selected: selected,
      label: '$title, ${_where(hit)}, ${hit.row.label}${hit.row.private ? ', unlocked page' : ''}: ${hit.row.text}',
      excludeSemantics: true,
      child: Material(
        color: selected ? c.surface : Colors.transparent,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: selected ? c.accent : Colors.transparent, width: 2),
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.card),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(spacing: 14, children: [
              _Thumb(hit: hit, terms: terms),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                  Text(_where(hit),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.textMuted)),
                  Row(spacing: 6, children: [
                    if (hit.row.private) EIcon(EIcons.lock, size: 13, color: c.textMuted),
                    Flexible(
                      child: Text(hit.row.private ? '${hit.row.label} · unlocked for now' : hit.row.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kindColor(hit.row.kind, c))),
                    ),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The match on a small piece of paper: the line's ink with the matched
/// words highlighted, or the words around a match in typed text.
class _Thumb extends ConsumerWidget {
  const _Thumb({required this.hit, required this.terms});

  final SearchHit hit;
  final List<String> terms;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    Widget inside;
    if (hit.row.kind == SearchKind.ink) {
      // An unlocked page with a password is sealed on disk: draw it as open.
      final page = hit.row.private
          ? ref.read(handwritingIndexProvider).openPage(hit.notebook.id, hit.row.pageId)
          : ref.watch(searchPagesProvider(hit.notebook.id)).value?[hit.row.pageId];
      final strokes = page == null ? const <StrokeItem>[] : _lineStrokes(page, hit.row.strokeIds);
      inside = strokes.isEmpty
          ? _Snippet(text: hit.row.text, terms: terms, hand: true)
          : CustomPaint(
              size: const Size(132, 72),
              painter: _ThumbPainter(strokes, hit.matchedStrokes.toSet(), Theme.of(context).brightness, c),
            );
    } else {
      inside = _Snippet(text: _around(hit.row.text, terms, 26), terms: terms);
    }
    return Container(
      width: 132,
      height: 72,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.cardLine),
        borderRadius: BorderRadius.circular(Radii.small),
      ),
      child: CustomPaint(painter: _DotsPainter(c.dot, 12, 1), child: Center(child: inside)),
    );
  }
}

/// The line's strokes as they show on [page] (on the page, a sticky note's
/// top note, or the slide an Office card shows); none if they don't show.
List<StrokeItem> _lineStrokes(BoardPage page, List<String> ids) {
  final shown = visibleInk(page);
  return [for (final id in ids) ?shown[id]];
}

/// A stretch of [text] around its first match, about [chars] long.
String _around(String text, List<String> terms, int chars) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final ranges = matchRanges(flat, terms);
  if (flat.length <= chars || ranges.isEmpty) {
    return flat.length <= chars ? flat : '${flat.substring(0, chars).trimRight()}…';
  }
  final (s, e) = ranges.first;
  var from = math.max(0, s - (chars - (e - s)) ~/ 2);
  final to = math.min(flat.length, from + chars);
  from = math.max(0, to - chars);
  // Whole words at the edges.
  if (from > 0) {
    final space = flat.indexOf(' ', from);
    if (space >= 0 && space < s) from = space + 1;
  }
  var end = to;
  if (to < flat.length) {
    final space = flat.lastIndexOf(' ', to);
    if (space > e) end = space;
  }
  return '${from > 0 ? '…' : ''}${flat.substring(from, end)}${end < flat.length ? '…' : ''}';
}

class _Snippet extends StatelessWidget {
  const _Snippet({required this.text, required this.terms, this.hand = false});

  final String text;
  final List<String> terms;
  final bool hand;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text.rich(
        _marked(text, terms, c, TextStyle(
          fontFamily: hand ? FontFamilies.handwritingSample : FontFamilies.ui,
          fontSize: hand ? 22 : 14,
          height: 1.1,
          color: c.text,
        )),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// [text] with [terms] marked as Search.png marks them.
TextSpan _marked(String text, List<String> terms, EndlessColors c, TextStyle style) {
  final ranges = matchRanges(text, terms);
  final children = <TextSpan>[];
  var at = 0;
  for (final (s, e) in ranges) {
    if (s > at) children.add(TextSpan(text: text.substring(at, s)));
    children.add(TextSpan(text: text.substring(s, e), style: TextStyle(backgroundColor: c.searchHit)));
    at = e;
  }
  if (at < text.length) children.add(TextSpan(text: text.substring(at)));
  return TextSpan(style: style, children: children);
}

class _ThumbPainter extends CustomPainter {
  _ThumbPainter(this.strokes, this.matched, this.brightness, this.colors);

  final List<StrokeItem> strokes;
  final Set<String> matched;
  final Brightness brightness;
  final EndlessColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    Rect? r;
    for (final s in strokes) {
      r = r == null ? s.bounds : r.expandToInclude(s.bounds);
    }
    if (r == null) return;
    final area = (Offset.zero & size).deflate(8);
    final k = math.min(math.min(area.width / r.width, area.height / r.height), 1.5);
    canvas
      ..save()
      ..translate(area.center.dx, area.center.dy)
      ..scale(k)
      ..translate(-r.center.dx, -r.center.dy);
    _paintHits(canvas, [for (final s in strokes) if (matched.contains(s.id)) s], colors, radius: 4 / k, pad: 3 / k);
    for (final s in strokes) {
      paintStroke(canvas, s, displayInk(s.color, brightness));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ThumbPainter old) =>
      old.strokes != strokes || old.matched != matched || old.brightness != brightness || old.colors != colors;
}

/// The highlight behind matched ink: one box per run of strokes that sit
/// together (a word).
void _paintHits(Canvas canvas, List<StrokeItem> strokes, EndlessColors colors, {required double radius, required double pad}) {
  if (strokes.isEmpty) return;
  Rect? box;
  for (final s in strokes) {
    final r = inkRect(s);
    box = box == null ? r : box.expandToInclude(r);
  }
  canvas.drawRRect(
    RRect.fromRectAndRadius(box!.inflate(pad), Radius.circular(radius)),
    Paint()..color = colors.searchHit,
  );
}

class _DotsPainter extends CustomPainter {
  _DotsPainter(this.color, this.spacing, this.radius);

  final Color color;
  final double spacing;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var y = spacing / 2; y < size.height; y += spacing) {
      for (var x = spacing / 2; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.color != color || old.spacing != spacing;
}

/// The picked match on its page, with "Open at this spot".
class _Preview extends ConsumerWidget {
  const _Preview({super.key, required this.hit, required this.terms, required this.onOpen});

  final SearchHit hit;
  final List<String> terms;
  final void Function(SearchHit hit, Rect spot) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final id = hit.notebook.id;
    // Open the notebook while it's shown, for its pictures and newest ink.
    final loaded = ref.watch(loadedNotebookProvider(id));
    PageRuntime? page;
    if (loaded.hasValue) {
      final nb = ref.watch(notebookProvider(id));
      final i = nb.indexOf(hit.row.pageId);
      if (i >= 0 && !nb.isSealed(hit.row.pageId)) page = nb.pages[i];
    }
    final strokes = page == null ? const <String, StrokeItem>{} : visibleInk(page.page);
    final spot = spotOf(hit, strokes);
    final label = switch (hit.row.kind) {
      SearchKind.ink => 'Recognized as',
      SearchKind.typed => 'Typed text',
      SearchKind.pdf => 'Text inside PDF',
      SearchKind.office => 'Text inside file',
    };
    final said = hit.row.kind == SearchKind.ink
        ? (hit.row.context.isEmpty ? hit.row.text : hit.row.context)
        : _around(hit.row.text, terms, 160);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
      Row(spacing: 16, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            Text(_title(hit),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 26, color: c.text)),
            Text(_where(hit), style: TextStyle(fontSize: 13, color: c.textMuted)),
          ]),
        ),
        Semantics(
          button: true,
          label: 'Open at this spot',
          excludeSemantics: true,
          child: Material(
            color: c.inverse,
            borderRadius: BorderRadius.circular(Radii.button),
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.button),
              onTap: () => onOpen(hit, spot),
              child: Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
                  Text('Open at this spot', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.onInverse)),
                  EIcon(EIcons.arrowRight, size: 18, color: c.onInverse),
                ]),
              ),
            ),
          ),
        ),
      ]),
      Expanded(
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
          child: Stack(fit: StackFit.expand, children: [
            CustomPaint(painter: _DotsPainter(c.dot, 24, 1.2)),
            if (page != null)
              CustomPaint(
                painter: _PagePainter(
                  page,
                  ref.watch(notebookProvider(id).select((s) => s.revision)),
                  hit,
                  spot,
                  strokes,
                  Theme.of(context).brightness,
                  c,
                ),
              ),
            Positioned(
              left: 48,
              bottom: 20,
              right: 48,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 520),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: c.surface,
                    border: Border.all(color: c.line),
                    borderRadius: BorderRadius.circular(Radii.button),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, spacing: 4, children: [
                    Text(label.toUpperCase(), style: TypeScale.sectionLabel.copyWith(color: c.textMuted)),
                    Text.rich(
                      _marked(hit.row.kind == SearchKind.ink ? '“$said”' : said, terms, c, TextStyle(fontSize: 16, color: c.text)),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}

/// The page around the match: the words that matched highlighted under
/// the ink, and the match outlined.
class _PagePainter extends CustomPainter {
  _PagePainter(this.page, this.revision, this.hit, this.spot, this.strokes, this.brightness, this.colors);

  final PageRuntime page;
  final int revision;
  final SearchHit hit;
  final Rect spot;
  final Map<String, StrokeItem> strokes;
  final Brightness brightness;
  final EndlessColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final line = hit.row.kind == SearchKind.ink
        ? (hit.row.strokeIds.map((id) => strokes[id]).nonNulls.fold<Rect?>(null, (r, s) => r == null ? inkRect(s) : r.expandToInclude(inkRect(s))) ??
            hit.row.rect)
        : hit.row.rect;
    final content = page.contentBounds ?? line;
    // Writing size where it fits; the match placed upper left of middle.
    final k = math.min(1.0, math.max(0.3, (size.width - 96) / math.max(line.width, 1) * 0.9));
    final view = Size(size.width / k, size.height / k);
    var left = line.left - 48 / k;
    if (content.left < left && line.right - content.left + 96 / k <= view.width) left = content.left - 48 / k;
    final top = line.center.dy - view.height * 0.38;
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..scale(k)
      ..translate(-left, -top);
    final r = 10 / k;
    if (hit.row.kind == SearchKind.ink) {
      // Each matched word on its own.
      for (final i in hit.matchedWords) {
        if (i >= hit.row.words.length) continue;
        final ink = [for (final id in hit.row.words[i].$2) ?strokes[id]];
        _paintHits(canvas, ink, colors, radius: r / 2, pad: 4 / k);
      }
    } else {
      canvas.drawRRect(RRect.fromRectAndRadius(spot.inflate(4 / k), Radius.circular(r)), Paint()..color = colors.searchHit);
    }
    canvas.drawPicture(page.fullPicture(brightness, colors));
    canvas.drawRRect(
      RRect.fromRectAndRadius(line.inflate(8 / k), Radius.circular(r)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 / k
        ..color = colors.accent,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PagePainter old) =>
      old.page != page ||
      old.revision != revision ||
      old.hit != hit ||
      old.brightness != brightness ||
      old.colors != colors;
}

class _Footer extends ConsumerWidget {
  const _Footer({required this.index});

  final HandwritingIndex index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final note = ref.watch(inkModelsProvider);
    return ValueListenableBuilder<int>(
      valueListenable: index.pending,
      builder: (context, pending, _) {
        final busy = pending > 0 || note?.phase == ModelPhase.downloading;
        final text = note?.phase == ModelPhase.downloading || note?.phase == ModelPhase.failed
            ? note!.text
            : pending > 0
                ? 'Reading handwriting in your notebooks…'
                : index.canRecognize
                    ? 'Handwriting is recognized on this tablet, so search works offline. '
                        'New ink is indexed a few seconds after you stop writing.'
                    : 'Handwriting is recognized on the tablet. Here, search finds typed text, text inside PDFs, '
                        'and handwriting the tablet has read.';
        return Semantics(
          liveRegion: true,
          child: Row(spacing: 8, children: [
            if (busy)
              SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.textMuted))
            else
              EIcon(EIcons.searchCheck, size: 16, color: c.green),
            Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: c.textMuted))),
          ]),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.count, required this.on, required this.onTap});

  final String label;
  final int count;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = on ? c.onInverse : c.text;
    return Semantics(
      button: true,
      selected: on,
      label: '$label, $count',
      excludeSemantics: true,
      child: Material(
        color: on ? c.inverse : Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: on ? c.inverse : c.lineStrong)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
              Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: fg)),
              Text('$count', style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.8))),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({required this.label, required this.semantic, required this.options, required this.onPick});

  final String label;
  final String semantic;
  final List<(T, String)> options;
  final ValueChanged<T> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopupMenuButton<int>(
      tooltip: '',
      color: c.surface,
      constraints: const BoxConstraints(maxHeight: 420, minWidth: 180),
      onSelected: (i) => onPick(options[i].$1),
      itemBuilder: (context) => [
        for (final (i, (_, name)) in options.indexed)
          PopupMenuItem(value: i, height: 44, child: Text(name, style: TextStyle(fontSize: 14, color: c.text))),
      ],
      child: Semantics(
        button: true,
        label: '$semantic: $label',
        excludeSemantics: true,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: c.lineStrong),
            borderRadius: BorderRadius.circular(Radii.chip),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
            Text(label, style: TextStyle(fontSize: 14, color: c.text)),
            EIcon(EIcons.chevronDown, size: 14, color: c.text),
          ]),
        ),
      ),
    );
  }
}

class _Square extends StatelessWidget {
  const _Square({
    required this.label,
    required this.icon,
    required this.onTap,
    this.size = 20,
    this.filled = false,
    this.muted = false,
  });

  final String label;
  final EIconData icon;
  final VoidCallback onTap;
  final double size;
  final bool filled;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: filled ? c.side : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.button),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.button),
          onTap: onTap,
          child: SizedBox.square(
            dimension: 44,
            child: Center(child: EIcon(icon, size: size, color: muted ? c.textMuted : c.text)),
          ),
        ),
      ),
    );
  }
}
