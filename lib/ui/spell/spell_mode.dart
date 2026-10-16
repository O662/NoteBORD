import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../canvas/canvas_view.dart';
import '../../canvas/page_runtime.dart';
import '../../canvas/pane.dart';
import '../../recognition/handwriting_index.dart';
import '../../recognition/recognized.dart';
import '../../spelling/my_handwriting.dart';
import '../../spelling/spell_check.dart';
import '../../spelling/spelling_state.dart';
import '../../state/notebook.dart';
import '../../state/settings.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../icons.dart';

// Spell check mode (design/screens/Spell.png, Spell.dc.html): the dark bar
// with "n of m", previous / next, Fix all and Done; wavy red underlines;
// and the suggestion card.

/// What spell check mode knows about the page it's checking.
class SpellController extends ChangeNotifier {
  SpellController(this.ref, this.pane) {
    _subs = [
      ref.listenManual(notebookProvider(pane.notebookId), (_, _) => _pageEdited()),
      ref.listenManual(spellerProvider, (_, _) {
        if (ref.read(spellerProvider).value case final speller?) {
          _speller = speller;
          _suggestions.clear();
          _recompute();
        }
      }),
    ];
    _index.revision.addListener(_reread);
    pane.addListener(_paneChanged);
    _pageId = _page.id;
    _start();
  }

  final WidgetRef ref;
  final Pane pane;
  late final List<ProviderSubscription<Object?>> _subs;
  late final HandwritingIndex _index = ref.read(handwritingIndexProvider);
  bool _disposed = false;

  /// Still reading the page or loading the word list.
  bool loading = true;

  /// The misspelled words on the page, in reading order.
  List<SpellIssue> issues = const [];
  String? _currentId;

  /// Until a word is picked (a tap, previous or next), the card is about
  /// the word at [_autoAt] in reading order, whatever the list becomes as
  /// the page is read: the first, or the one after a fixed or ignored word.
  bool _auto = true;
  int _autoAt = 0;

  /// Where words were fixed this time (page space), shown in green.
  final fixed = <Rect>[];

  /// Words ignored this time, which Start over brings back.
  final _ignoredNow = <String>{};
  final _suggestions = <String, List<String>>{};
  Speller? _speller;
  PageRecognition? _read;
  late String _pageId;

  NotebookNotifier get _notebook => ref.read(notebookProvider(pane.notebookId).notifier);

  PageRuntime get _page => ref.read(notebookProvider(pane.notebookId)).pageAt(pane.page);

  SpellIssue? get current => issues.where((i) => i.id == _currentId).firstOrNull;

  int get position => current == null ? -1 : issues.indexOf(current!);

  /// "1 of 4", or "All clear".
  String get countLabel => issues.isEmpty ? (loading ? '' : 'All clear') : '${position + 1} of ${issues.length}';

  Future<void> _start() async {
    try {
      _speller = await ref.read(spellerProvider.future);
    } on Object catch (e) {
      debugPrint('Spell check: $e');
    }
    if (_disposed) return;
    // New writing is read now, not after the usual pause.
    await _index.indexNow(pane.notebookId, _pageId);
    loading = false;
    await _reread();
  }

  Future<void> _reread() async {
    final pageId = _pageId;
    final read = await _index.pageRecognition(pane.notebookId, pageId);
    if (_disposed || pageId != _pageId) return;
    _read = read;
    _recompute();
  }

  /// The page changed (a fix, Undo): checked again now, and its handwriting
  /// read again so the words line up with the ink.
  void _pageEdited() {
    _recompute();
    if (loading) return;
    if (_reading) {
      _readAgain = true;
      return;
    }
    _reading = true;
    () async {
      do {
        _readAgain = false;
        await _index.indexNow(pane.notebookId, _pageId);
        await _reread();
      } while (_readAgain && !_disposed);
    }()
        .whenComplete(() => _reading = false);
  }

  bool _reading = false, _readAgain = false;

  void _paneChanged() {
    if (_page.id == _pageId) return;
    _pageId = _page.id;
    _read = null;
    _currentId = null;
    _auto = true;
    _autoAt = 0;
    fixed.clear();
    _ignoredNow.clear();
    loading = true;
    notifyListeners();
    _start();
  }

  void _recompute() {
    final speller = _speller;
    if (_disposed || speller == null) return;
    final before = position;
    issues = findIssues(_page.page, _read, speller);
    if (current == null) {
      // Fixed or ignored: on to the one that took its place.
      _auto = true;
      if (before >= 0) _autoAt = before;
    }
    if (_auto) _currentId = loading || issues.isEmpty ? null : issues[_autoAt.clamp(0, issues.length - 1)].id;
    notifyListeners();
  }

  /// Corrections for [issue], best first.
  List<String> suggestionsFor(SpellIssue issue) =>
      _suggestions[issue.id] ??= _speller?.suggest(issue.word, hints: issue.hints) ?? const [];

  void select(String id) {
    _auto = false;
    if (id == _currentId) return;
    _currentId = id;
    notifyListeners();
  }

  void step(int by) {
    if (issues.isEmpty) return;
    final at = math.max(position, 0);
    select(issues[(at + by) % issues.length].id);
  }

  /// Puts [word] in place of the current word: one undo step.
  void fix(String word) {
    final issue = current;
    if (issue == null) return;
    _apply([(issue, word)]);
    pane.toast('Changed “${issue.word}” to “$word”', undoPageId: _pageId);
  }

  /// Every word gets its first suggestion (words with none stay): one undo
  /// step.
  Future<void> fixAll() async {
    final fixes = <(SpellIssue, String)>[];
    for (final issue in [...issues]) {
      final s = suggestionsFor(issue);
      if (s.isNotEmpty) fixes.add((issue, s.first));
      // Suggestions take a moment each: let a frame through between them.
      await Future<void>.delayed(Duration.zero);
      if (_disposed) return;
    }
    if (fixes.isEmpty) return;
    _apply(fixes);
    pane.toast(fixes.length == 1 ? 'Fixed 1 word' : 'Fixed ${fixes.length} words', undoPageId: _pageId);
  }

  /// The user's letters, when fixes are to be written in them.
  MyHandwriting? get _hand => ref.read(settingsProvider).fixInHandwriting ? ref.read(myHandwritingProvider) : null;

  void _apply(List<(SpellIssue, String)> fixes) {
    final page = _page;
    final edit = planFixes(page.page, fixes, z: page.nextZ, now: DateTime.now().toUtc(), hand: _hand);
    if (edit.isEmpty) return;
    fixed.addAll(fixes.map((f) => f.$1.rect));
    _notebook.edit(page.id, remove: edit.remove, replace: edit.replace, insert: edit.insert);
  }

  /// Ignores the current word on this page.
  void ignore() {
    final issue = current;
    if (issue == null) return;
    final words = [..._page.page.spellIgnore];
    if (!words.any((w) => w.toLowerCase() == issue.word.toLowerCase())) words.add(issue.word);
    _ignoredNow.add(issue.word);
    _notebook.setSpellIgnore(_pageId, words);
  }

  /// Adds the current word to "my dictionary", for every notebook.
  void addToDictionary() {
    final issue = current;
    if (issue == null) return;
    ref.read(settingsProvider.notifier).apply((s) {
      if (s.myWords.any((w) => w.toLowerCase() == issue.word.toLowerCase())) return s;
      return s.copyWith(myWords: [...s.myWords, issue.word]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())));
    });
  }

  /// Brings back the words ignored this time and checks again.
  void startOver() {
    final ignored = {for (final w in _ignoredNow) w.toLowerCase()};
    _notebook.setSpellIgnore(_pageId, [
      for (final w in _page.page.spellIgnore)
        if (!ignored.contains(w.toLowerCase())) w,
    ]);
    _ignoredNow.clear();
    fixed.clear();
    _currentId = null;
    _auto = true;
    _autoAt = 0;
    _recompute();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final s in _subs) {
      s.close();
    }
    _index.revision.removeListener(_reread);
    pane.removeListener(_paneChanged);
    super.dispose();
  }
}

/// The dark bar in place of the tool pill (Spell.dc.html's toolbar).
class SpellBar extends StatelessWidget {
  const SpellBar({super.key, required this.spell, required this.onDone});

  final SpellController spell;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: spell,
      builder: (context, _) {
        final some = spell.issues.isNotEmpty;
        return Semantics(
          container: true,
          label: 'Spell check',
          explicitChildNodes: true,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
            decoration: BoxDecoration(
              color: c.inverse,
              borderRadius: BorderRadius.circular(Radii.pill),
              boxShadow: c.pillShadow,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
              // "abc✓": the bundled fonts have no ✓, so it's the check icon.
              ExcludeSemantics(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(
                    'abc',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: -0.28, color: c.onInverse),
                  ),
                  EIcon(EIcons.check, size: 13, color: c.inverseTick),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text('Spell check', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.onInverse)),
              ),
              Semantics(
                liveRegion: true,
                child: Text(
                  spell.countLabel,
                  style: TextStyle(
                    fontSize: 13,
                    color: c.onInverseMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              _BarButton(label: 'Previous issue', icon: EIcons.chevronLeft, onTap: some ? () => spell.step(-1) : null),
              _BarButton(label: 'Next issue', icon: EIcons.chevronRight, onTap: some ? () => spell.step(1) : null),
              _BarButton(label: 'Fix all', onTap: some ? spell.fixAll : null),
              _BarButton(label: 'Done', done: true, onTap: onDone),
            ]),
          ),
        );
      },
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({required this.label, this.icon, required this.onTap, this.done = false});

  final String label;
  final EIconData? icon;
  final VoidCallback? onTap;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = done ? c.text : c.onInverse;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: Material(
          color: done ? c.surface : c.inverseRaised,
          borderRadius: BorderRadius.circular(Radii.button),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.button),
            onTap: onTap,
            child: Container(
              height: 44,
              constraints: const BoxConstraints(minWidth: 44),
              padding: EdgeInsets.symmetric(horizontal: icon != null ? 0 : (done ? 16 : 12)),
              alignment: Alignment.center,
              child: icon != null
                  ? EIcon(icon!, size: 16, color: fg)
                  : Text(label, style: TextStyle(fontSize: 14, fontWeight: done ? FontWeight.w700 : FontWeight.w600, color: fg)),
            ),
          ),
        ),
      ),
    );
  }
}

/// The suggestion card (Spell.dc.html's "Spelling suggestion").
class SpellCard extends StatelessWidget {
  const SpellCard({
    super.key,
    required this.spell,
    required this.width,
    required this.onLookUp,
    required this.onTeach,
  });

  final SpellController spell;
  final double width;
  final ValueChanged<String> onLookUp;

  /// Opens "Teach Endless your handwriting"; true once a sample is saved.
  final Future<bool> Function() onTeach;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: spell,
      builder: (context, _) {
        final issue = spell.current;
        return Semantics(
          container: true,
          label: 'Spelling suggestion',
          explicitChildNodes: true,
          child: Container(
            width: width,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(Radii.dialog),
              boxShadow: c.dialogShadow,
            ),
            child: spell.loading && issue == null
                ? _Checking()
                : issue == null
                    ? _AllClear(onStartOver: spell.startOver)
                    : _Issue(spell: spell, issue: issue, onLookUp: onLookUp, onTeach: onTeach),
          ),
        );
      },
    );
  }
}

class _Checking extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 60,
      child: Row(spacing: 12, children: [
        SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.accent)),
        Text('Checking this page…', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.text)),
      ]),
    );
  }
}

class _AllClear extends StatelessWidget {
  const _AllClear({required this.onStartOver});

  final VoidCallback onStartOver;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Row(spacing: 12, children: [
        EIcon(EIcons.check, size: 24, color: c.green),
        Expanded(
          child: Text(
            'No spelling issues left on this page',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.text),
          ),
        ),
        _OutlineButton(label: 'Start over', onTap: onStartOver, padding: 14),
      ]),
    );
  }
}

class _Issue extends ConsumerWidget {
  const _Issue({required this.spell, required this.issue, required this.onLookUp, required this.onTeach});

  final SpellController spell;
  final SpellIssue issue;
  final ValueChanged<String> onLookUp;
  final Future<bool> Function() onTeach;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final hand = ref.watch(myHandwritingProvider);
    final inHand = hand != null && ref.watch(settingsProvider.select((s) => s.fixInHandwriting));
    final suggestions = spell.suggestionsFor(issue);
    final ink = issue.kind == SpellKind.handwriting;
    final wavy = TextStyle(
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.wavy,
      decorationColor: c.spellUnderline,
      decorationThickness: 2,
      color: c.text,
    );
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        spacing: 10,
        children: [
          Text('Not in the dictionary:', style: TextStyle(fontSize: 13, color: c.textMuted)),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                issue.word,
                overflow: TextOverflow.ellipsis,
                style: ink
                    ? wavy.copyWith(fontFamily: FontFamilies.handwritingSample, fontSize: 30, height: 1.2)
                    : wavy.copyWith(fontSize: 18, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          Text(issue.kind.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.textMuted)),
        ],
      ),
      if (suggestions.isEmpty)
        SizedBox(
          height: 44,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('No suggestions. Ignore it, or add it to your dictionary.',
                style: TextStyle(fontSize: 14, color: c.textMuted)),
          ),
        )
      else
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (i, s) in suggestions.indexed) _Suggestion(label: s, first: i == 0, onTap: () => spell.fix(s)),
        ]),
      Container(
        padding: const EdgeInsets.only(top: 10),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: c.lineSoft))),
        child: Row(spacing: 8, children: [
          // Typed text is fixed as text: the box is only for handwriting.
          Expanded(
            child: ink
                ? _InHandwriting(
                    checked: inHand,
                    onTap: () async {
                      if (hand == null) {
                        await onTeach();
                      } else {
                        ref.read(settingsProvider.notifier).apply((s) => s.copyWith(fixInHandwriting: !s.fixInHandwriting));
                      }
                    },
                  )
                : const SizedBox(height: 44),
          ),
          _OutlineButton(
            label: 'Look up',
            onTap: () => onLookUp(suggestions.isEmpty ? issue.word : suggestions.first.toLowerCase()),
          ),
          _OutlineButton(label: 'Ignore', onTap: spell.ignore),
          _OutlineButton(label: 'Add to my dictionary', onTap: spell.addToDictionary),
        ]),
      ),
    ]);
  }
}

/// "Fix it in my handwriting": the box and its label. Before there's a
/// sample, a tap opens "Teach Endless your handwriting".
class _InHandwriting extends StatelessWidget {
  const _InHandwriting({required this.checked, required this.onTap});

  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      checked: checked,
      label: 'Fix it in my handwriting',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.small),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(spacing: 8, children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: checked ? c.accent : Colors.transparent,
                border: checked ? null : Border.all(color: c.lineStrong, width: 1.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: checked ? Center(child: EIcon(EIcons.check, size: 14, color: c.onAccent)) : null,
            ),
            Flexible(child: Text('Fix it in my handwriting', style: TextStyle(fontSize: 14, color: c.text))),
          ]),
        ),
      ),
    );
  }
}

class _Suggestion extends StatelessWidget {
  const _Suggestion({required this.label, required this.first, required this.onTap});

  final String label;
  final bool first;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'Change to $label',
      excludeSemantics: true,
      child: Material(
        color: first ? c.inverse : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.button),
          side: first ? BorderSide.none : BorderSide(color: c.lineStrong),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.button),
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: first ? c.onInverse : c.text),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({required this.label, required this.onTap, this.padding = 12});

  final String label;
  final VoidCallback onTap;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.key),
          side: BorderSide(color: c.lineStrong),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.key),
          onTap: onTap,
          child: Container(
            height: 40,
            padding: EdgeInsets.symmetric(horizontal: padding),
            alignment: Alignment.center,
            child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text)),
          ),
        ),
      ),
    );
  }
}

/// Wavy red lines under the misspelled words, a wash behind the one the
/// card is about, and green behind the words fixed this time.
class SpellMarksPainter extends CustomPainter {
  SpellMarksPainter(this.view, this.spell, this.colors) : super(repaint: Listenable.merge([view, spell]));

  final CanvasView view;
  final SpellController spell;
  final EndlessColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final current = spell.current;
    for (final r in spell.fixed) {
      final box = Rect.fromPoints(view.toScreen(r.topLeft), view.toScreen(r.bottomRight)).inflate(4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(6)),
        Paint()..color = colors.green.withValues(alpha: 0.12),
      );
    }
    final wave = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = colors.spellUnderline;
    for (final issue in spell.issues) {
      final q = [for (final p in issue.quad) view.toScreen(p)];
      if (issue.id == current?.id) {
        // The wash: the word's box, a little bigger, turned with it.
        final mid = (q[0] + q[2]) / 2;
        final grown = [for (final p in q) mid + (p - mid) * 1.0 + _away(p - mid, 4)];
        canvas.drawPath(
          Path()..addPolygon(grown, true),
          Paint()
            ..color = colors.spellUnderline.withValues(alpha: 0.12)
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = 8
            ..style = PaintingStyle.fill,
        );
      }
      canvas.drawPath(_wavy(q[3], q[2], below: q[3] - q[0]), wave);
    }
  }

  static Offset _away(Offset d, double by) => d.distance == 0 ? Offset.zero : Offset(d.dx.sign * by, d.dy.sign * by);

  /// A wave from [a] to [b], 4 px under the word (on the side [below] points to).
  static Path _wavy(Offset a, Offset b, {required Offset below}) {
    final along = b - a;
    final length = along.distance;
    final path = Path();
    if (length < 1) return path;
    final dir = along / length;
    var normal = Offset(-dir.dy, dir.dx);
    if (normal.dx * below.dx + normal.dy * below.dy < 0) normal = -normal;
    final start = a + normal * 4;
    const wavelength = 6.0, amplitude = 1.8;
    path.moveTo(start.dx, start.dy);
    for (var t = 0.0; t < length; t += wavelength / 2) {
      final up = ((t / (wavelength / 2)).round() % 2 == 0) ? 1 : -1;
      final end = math.min(t + wavelength / 2, length);
      final ctrl = start + dir * ((t + end) / 2) + normal * (amplitude * 2 * up);
      final to = start + dir * end;
      path.quadraticBezierTo(ctrl.dx, ctrl.dy, to.dx, to.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(SpellMarksPainter old) => old.spell != spell || old.colors != colors || old.view != view;
}
