import 'dart:ui';

import 'package:endless/board/codec.dart' show withRemember;
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/recognition/handwriting_index.dart';
import 'package:endless/study/fsrs.dart';
import 'package:endless/study/remember.dart';
import 'package:endless/study/study_state.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// The design's sample data for Need to remember and Flashcards
// (Remember.dc.html, Study.dc.html), made of real notebooks.

final _made = DateTime.utc(2026, 9, 1, 14);

Color get _black => tokens.inkDefaults[0];
Color get _blue => tokens.inkDefaults[1];
Color get _clay => tokens.inkDefaults[2];
Color get _green => const Color(0xFF2F5D3A);

/// Words in Caveat (looks like handwriting) or Figtree ([typed]).
TextItem sampleText(String id, String text, {required Offset at, double size = 34, Color? color, bool typed = false, double wrap = 520}) =>
    TextItem(
      id: id,
      x: at.dx,
      y: at.dy,
      z: 1,
      createdAt: _made,
      wrap: wrap,
      text: text,
      // Hugging its words, as a new text box does.
      autoWidth: !typed,
      font: typed ? 'ui' : 'hand',
      size: size,
      color: color ?? _black,
    );

Json _mark(String id, {String why = '', DateTime? remindAt, String? card, bool drawn = false, required DateTime at}) => {
      ...RememberMark(
        id: id,
        why: why,
        remind: remindAt == null ? RemindKind.none : RemindKind.date,
        remindAt: remindAt,
        flashcard: card,
        drawn: drawn,
        at: at,
      ).toJson(),
    };

void _add(MemoryBoardStore store, String id, String title, List<String> folder, List<BoardPage> pages, {Color? cover}) {
  final nb = Notebook(
    id: id,
    title: title,
    folderPath: folder,
    coverColor: cover == null ? null : colorToHex(cover),
    createdAt: _made,
    updatedAt: DateTime.utc(2026, 9, 25, 9),
    pageIds: [for (final p in pages) p.id],
  );
  for (final p in pages) {
    store.savePage(id, p);
  }
  store.saveNotebook(nb);
}

/// Pages before [page] so it's "p. [n]".
List<BoardPage> _pagesUpTo(String prefix, int n, BoardPage page) => [
      for (var i = 1; i < n; i++) BoardPage(id: '${prefix}_$i'),
      page,
    ];

/// Remember.png: eight things to remember in six notebooks.
MemoryBoardStore rememberSample() {
  final store = MemoryBoardStore();
  DateTime day(int d, [int h = 9]) => DateTime(2026, 9, d, h).toUtc();
  final physics = BoardPage(id: 'pg_phys', items: [
    withRemember(
      sampleText('t_mom', 'total momentum is conserved\nin a closed system', at: const Offset(120, 190)),
      _mark('rm_mom', why: 'always on the exam', remindAt: DateTime(2026, 10, 14, 9).toUtc(), at: day(25, 8)),
    ),
    // Caveat has no Greek, and tests have no fallback font for it.
    withRemember(sampleText('t_imp', 'J = F · t = p₂ − p₁', at: const Offset(126, 414), size: 42), _mark('rm_imp', card: 'fc_imp', at: day(25, 7))),
    withRemember(sampleText('t_dp', 'p₂ − p₁ = m·v₂ − m·v₁', at: const Offset(126, 540), size: 40), _mark('rm_dp', drawn: true, at: day(24, 7))),
    FlashcardItem(
      id: 'fc_imp',
      x: 126,
      y: 414,
      z: 9,
      createdAt: _made,
      deck: 'dk_mom',
      deckName: 'Physics — Momentum',
      front: const CardSide(ids: ['t_imp']),
      back: const CardSide(),
    ),
  ]);
  _add(store, 'nb_phys', 'Physics — Lecture notes', ['School', 'Physics'], _pagesUpTo('pp', 3, physics), cover: tokens.inkDefaults[1]);
  _add(store, 'nb_lab', 'Lab journal', ['School', 'Physics'], _pagesUpTo('pl', 2, BoardPage(id: 'pg_lab', items: [
    withRemember(sampleText('t_track', 'track must be level!', at: const Offset(200, 200), size: 30), _mark('rm_track', at: day(23))),
  ])), cover: const Color(0xFF4E7A52));
  _add(store, 'nb_plan', 'Study plan', ['School'], [
    BoardPage(id: 'pg_plan', items: [
      withRemember(
        sampleText('t_lab', 'Lab report due Sep 30, 11:59 PM — submit as PDF', at: const Offset(80, 80), size: 18, typed: true, wrap: 300),
        _mark('rm_lab', remindAt: DateTime(2026, 9, 29, 18).toUtc(), at: day(22)),
      ),
    ]),
  ], cover: const Color(0xFF7A4E73));
  _add(store, 'nb_calc', 'Calculus II', ['School', 'Calculus'], _pagesUpTo('pc', 8, BoardPage(id: 'pg_calc', items: [
    withRemember(sampleText('t_int', 'd/dx (x²/2) = x', at: const Offset(100, 100), size: 40, color: _clay), _mark('rm_int', at: day(21))),
  ])), cover: _clay);
  _add(store, 'nb_team', 'Team meeting', ['Work'], [
    BoardPage(id: 'pg_team', items: [
      withRemember(
        sampleText('t_slides', 'Send slides before Monday stand-up', at: const Offset(60, 60), size: 18, typed: true, wrap: 300),
        _mark('rm_slides', remindAt: DateTime(2026, 9, 28, 9).toUtc(), at: day(20)),
      ),
    ]),
  ], cover: _clay);
  _add(store, 'nb_garden', 'Garden ideas', ['Personal'], [
    BoardPage(id: 'pg_garden', items: [
      withRemember(
        sampleText('t_tom', 'tomatoes: 6 hrs sun,\nwater at the base', at: const Offset(60, 60), size: 30, color: _green),
        _mark('rm_tom', at: day(19)),
      ),
    ]),
  ], cover: const Color(0xFF4E7A52));
  store.library = {
    'version': 1,
    'folders': [
      {'path': ['School'], 'color': colorToHex(tokens.inkDefaults[1])},
      {'path': ['School', 'Physics'], 'color': colorToHex(tokens.inkDefaults[1])},
      {'path': ['School', 'Calculus'], 'color': colorToHex(_clay)},
      {'path': ['Work'], 'color': colorToHex(_clay)},
      {'path': ['Personal'], 'color': colorToHex(const Color(0xFF4E7A52))},
    ],
  };
  store.pageWrites = 0;
  return store;
}

FlashcardItem _flash(String id, String front, String back, {String deck = 'dk_mom', String deckName = 'Physics — Momentum', bool reverse = false}) =>
    FlashcardItem(
      id: id,
      x: 0,
      y: 0,
      z: 50,
      createdAt: _made,
      deck: deck,
      deckName: deckName,
      front: CardSide(ids: [front]),
      back: CardSide(ids: [back]),
      reverse: reverse,
    );

/// Study.png: three decks. "Physics — Momentum" has 5 cards due (and 12 in
/// all, from 2 notebooks), "Calculus II — Integrals" 2, and "Lab safety" is
/// all caught up.
MemoryBoardStore studySample({DateTime? now}) {
  final store = MemoryBoardStore();
  final t = now ?? DateTime.utc(2026, 9, 25, 10);
  const fsrs = Fsrs();
  // Learned long ago, and due again now; or learned just now (due later).
  final dueNow = fsrs.review(null, Rating.good, t.subtract(const Duration(days: 30)));
  CardState later() => fsrs.review(fsrs.review(null, Rating.good, t), Rating.good, t.add(const Duration(minutes: 10)));

  final physics = <Item>[];
  final calc = <Item>[];
  final lab = <Item>[];
  final states = <String, Map<String, Map<String, Object?>>>{};
  void card(List<Item> page, String nb, String id, String front, String back, {required bool due, Color? color, String deck = 'dk_mom', String deckName = 'Physics — Momentum'}) {
    final y = 100.0 + page.length * 40;
    page
      ..add(sampleText('${id}_f', front, at: Offset(100, y), size: 48, color: color ?? _blue))
      ..add(sampleText('${id}_b', back, at: Offset(500, y), size: 40))
      ..add(_flash(id, '${id}_f', '${id}_b', deck: deck, deckName: deckName));
    (states[nb] ??= {})[id] = {'f': (due ? dueNow : later()).toJson()};
  }

  for (final (i, (f, b)) in [
    ('Impulse', 'J = F · t = p₂ − p₁'),
    ('p = ?', 'm · v  (kg·m/s)'),
    ('Momentum is…', 'conserved in a closed system'),
    ('Elastic collision', 'kinetic energy kept'),
    ('Newton\'s 2nd law', 'F = Δp / Δt'),
    ('Units of impulse', 'N·s'),
    ('Inelastic collision', 'objects stick together'),
  ].indexed) {
    card(physics, 'nb_phys', 'fc_p$i', f, b, due: i < 5);
  }
  for (final (i, (f, b)) in [('Recoil', 'm₁v₁ = −m₂v₂'), ('Δp of a ball', 'm(v₂ − v₁)'), ('Rocket thrust', 'v · dm/dt'), ('Centre of mass', 'Σmx / Σm'), ('Closed system', 'no outside force')].indexed) {
    card(lab, 'nb_lab', 'fc_l$i', f, b, due: false);
  }
  for (final (i, (f, b)) in [('area under x', 'x²/2 + C'), ('area under eˣ', 'eˣ + C'), ('area under 1/x', 'ln|x| + C')].indexed) {
    card(calc, 'nb_calc', 'fc_c$i', f, b, due: i < 2, color: _clay, deck: 'dk_calc', deckName: 'Calculus II — Integrals');
  }
  for (final (i, (f, b)) in [('Goggles?', 'always'), ('Spill', 'tell the teacher'), ('Fire blanket', 'by the door')].indexed) {
    card(calc, 'nb_calc', 'fc_s$i', f, b, due: false, deck: 'dk_lab', deckName: 'Lab safety');
  }

  _add(store, 'nb_phys', 'Physics — Lecture notes', ['School', 'Physics'], _pagesUpTo('pp', 3, BoardPage(id: 'pg_phys', items: physics)));
  // The rest of Physics — Momentum (5 cards), from another notebook.
  _add(store, 'nb_lab', 'Lab journal', ['School', 'Physics'], [BoardPage(id: 'pg_lab', items: lab)]);
  _add(store, 'nb_calc', 'Calculus II', ['School', 'Calculus'], [BoardPage(id: 'pg_calc', items: calc)]);
  for (final e in states.entries) {
    store.saveStudy(e.key, {'version': 1, 'cards': e.value});
  }
  store.decks = {
    'version': 1,
    'decks': [
      {'id': 'dk_mom', 'name': 'Physics — Momentum', 'createdAt': '2026-09-01T14:00:00.000Z'},
      {'id': 'dk_calc', 'name': 'Calculus II — Integrals', 'createdAt': '2026-09-02T14:00:00.000Z'},
      {'id': 'dk_lab', 'name': 'Lab safety', 'createdAt': '2026-09-03T14:00:00.000Z'},
    ],
  };
  store.pageWrites = 0;
  return store;
}

/// Reads every notebook into the index (as the app does after it starts)
/// and the study data from it.
Future<void> indexAll(WidgetTester tester, ProviderContainer c) async {
  var done = false;
  c.read(handwritingIndexProvider).catchUp().then((_) => done = true);
  for (var i = 0; i < 400 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done, isTrue, reason: 'indexing never finished');
  done = false;
  c.read(studyProvider.notifier).refresh().then((_) => done = true);
  for (var i = 0; i < 400 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump();
}
