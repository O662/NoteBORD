// Golden images of Phase 7a at the tablet size (1280×800). Compare with
// design/screens/FlashMake.png, Study.png, RememberMark.png and
// Remember.png.
//
// Regenerate after an intended visual change:
//   flutter test --update-goldens test/golden/phase7_golden_test.dart
@Tags(['golden'])
library;

import 'dart:math' as math;

import 'package:endless/board/codec.dart' show withRemember;
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/study/remember.dart';
import 'package:endless/ui/routes.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../study/shapes.dart';
import '../study/study_samples.dart';

Future<void> _withShadows(Future<void> Function() body) async {
  debugDisableShadows = false;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _pen(WidgetTester tester, List<Offset> points) async {
  final g = await tester.createGesture(kind: PointerDeviceKind.stylus);
  var t = const Duration(seconds: 20);
  await g.down(points.first, timeStamp: t);
  for (final p in points.skip(1)) {
    t += const Duration(milliseconds: 8);
    await g.moveTo(p, timeStamp: t);
  }
  await g.up(timeStamp: t);
  await tester.pump();
}

/// A loop round [r], a little wobbly, as a hand draws it.
List<Offset> _loop(Rect r) => [
      for (var i = 0; i <= 48; i++)
        r.center +
            Offset(math.cos(i / 48 * 2 * math.pi) * r.width / 2 * (1 + 0.03 * math.sin(i)),
                math.sin(i / 48 * 2 * math.pi) * r.height / 2),
    ];

/// A loop round [r] with round corners (RememberMark.png's lasso).
List<Offset> _roundLoop(Rect r, {double radius = 36}) {
  final path = Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)));
  final m = path.computeMetrics().first;
  return [for (var d = 0.0; d <= m.length; d += 12) m.getTangentForOffset(d)!.position];
}

final _at = DateTime.utc(2026, 9, 25, 9);
const _blue = Color(0xFF2B5A8C);
const _clay = Color(0xFFB5532A);

StrokeItem _line(String id, Offset a, Offset b, {Color color = const Color(0xFF1E1C19), double width = 3}) =>
    StrokeItem.fromPagePoints(
      id: id,
      z: 30,
      createdAt: _at,
      tool: InkTool.pen,
      penType: PenType.ballpoint,
      color: color,
      width: width,
      usePressure: false,
      pagePoints: [
        for (var i = 0; i <= 12; i++) InkPoint(a.dx + (b.dx - a.dx) * i / 12, a.dy + (b.dy - a.dy) * i / 12, 0.5, i * 10),
      ],
    );

/// The block on a slope (FlashMake.png's back).
List<StrokeItem> _slope(Offset o) => [
      _line('sl_1', o + const Offset(0, 100), o + const Offset(170, 100)),
      _line('sl_2', o + const Offset(170, 100), o + const Offset(170, 18)),
      _line('sl_3', o + const Offset(170, 18), o + const Offset(0, 100)),
      _line('sl_4', o + const Offset(70, 52), o + const Offset(100, 38)),
      _line('sl_5', o + const Offset(100, 38), o + const Offset(108, 54)),
      _line('sl_6', o + const Offset(108, 54), o + const Offset(78, 68)),
      _line('sl_7', o + const Offset(78, 68), o + const Offset(70, 52)),
      _line('sl_8', o + const Offset(112, 40), o + const Offset(144, 24), color: _blue),
    ];

MemoryBoardStore _store(List<Item> items, {List<Map<String, Object?>> decks = const []}) {
  final page = BoardPage(id: 'pg_3', items: items);
  final pages = [BoardPage(id: 'pg_1'), BoardPage(id: 'pg_2'), page];
  final nb = Notebook(
    id: 'nb_phys',
    title: 'Physics — Lecture notes',
    folderPath: const ['School', 'Physics'],
    createdAt: _at,
    updatedAt: _at,
    pageIds: [for (final p in pages) p.id],
  );
  final store = storeWith(LoadedNotebook(nb, pages), settings: AppSettings(lastDeck: decks.isEmpty ? null : decks.first['id'] as String));
  if (decks.isNotEmpty) store.decks = {'version': 1, 'decks': decks};
  return store;
}

void main() {
  setUpAll(loadAppFonts);

  // FlashMake.png: the front circled, the back circled, three cards made.
  testWidgets('flash_make', (tester) => _withShadows(() async {
        FlashcardItem card(String id, List<String> front, List<String> back) => FlashcardItem(
              id: id,
              x: 0,
              y: 0,
              z: 60,
              createdAt: _at,
              deck: 'dk_mom',
              deckName: 'Physics — Momentum',
              front: CardSide(ids: front),
              back: CardSide(ids: back),
            );
        final store = _store([
          sampleText('t_title', 'Lecture 3 — Momentum', at: const Offset(720, 124), size: 50, color: _blue),
          sampleText('t_p', 'p = m · v', at: const Offset(740, 182), size: 42),
          sampleText('t_mom', 'total momentum is conserved\nin a closed system', at: const Offset(730, 246), size: 34),
          sampleText('t_imp', 'Impulse', at: const Offset(150, 190), size: 48, color: _blue),
          sampleText('t_j', 'J = F · t = p₂ − p₁', at: const Offset(160, 296), size: 40),
          ..._slope(const Offset(196, 352)),
          card('fc_1', ['t_mom'], ['t_title']),
          card('fc_2', ['t_p'], ['t_mom']),
        ], decks: [
          {'id': 'dk_mom', 'name': 'Physics — Momentum', 'createdAt': '2026-09-01T14:00:00.000Z'},
        ]);
        await pumpCanvas(tester, store: store);
        canvasPane.goTo(2);
        await tester.pump();
        await tester.tap(byLabel('Study & math'));
        await tester.pump();
        await tester.tap(find.text('Make flashcards'));
        await tester.pump();
        await _pen(tester, _loop(const Rect.fromLTWH(124, 178, 226, 92)));
        await _pen(tester, _loop(const Rect.fromLTWH(132, 284, 342, 196)));
        await _settle(tester);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('flash_make.png'));
        await tester.pump(const Duration(seconds: 5));
      }));

  // RememberMark.png: lassoed, with Remember this open; something already
  // remembered, and a drawn star.
  testWidgets('remember_mark', (tester) => _withShadows(() async {
        final star = StrokeItem.fromPagePoints(
          id: 'st_star',
          z: 40,
          createdAt: _at,
          tool: InkTool.pen,
          penType: PenType.ballpoint,
          color: _clay,
          width: 2.5,
          usePressure: false,
          pagePoints: [for (final p in pentagram(const Offset(340, 576), 26)) InkPoint(p.dx, p.dy, 0.5, 0)],
        );
        final ring = StrokeItem.fromPagePoints(
          id: 'st_ring',
          z: 41,
          createdAt: _at,
          tool: InkTool.pen,
          penType: PenType.ballpoint,
          color: _clay,
          width: 2.5,
          usePressure: false,
          pagePoints: [
            for (var i = 0; i <= 60; i++)
              InkPoint(208 + math.cos(i / 60 * 2.1 * math.pi - 2.4) * 84, 574 + math.sin(i / 60 * 2.1 * math.pi - 2.4) * 28, 0.5, 0),
          ],
        );
        const drawn = RememberMark(id: 'rm_exam', drawn: true);
        final store = _store([
          sampleText('t_title', 'Lecture 3 — Momentum', at: const Offset(110, 96), size: 50, color: _blue),
          sampleText('t_mom', 'total momentum is conserved\nin a closed system', at: const Offset(120, 184), size: 42),
          withRemember(sampleText('t_j', 'J = F · t = p₂ − p₁', at: const Offset(126, 410), size: 42), const RememberMark(id: 'rm_j').toJson()),
          withRemember(ring, drawn.toJson()),
          withRemember(sampleText('t_exam', 'on exam!', at: const Offset(150, 552), size: 36, color: _clay), drawn.toJson()),
          withRemember(star, drawn.copyWith(star: true).toJson()),
          ..._slope(const Offset(850, 600)).map((s) => s.mapped((p) => Offset(850 + (p.dx - 850) * 1.7, 600 + (p.dy - 600) * 1.4))),
        ]);
        await pumpCanvas(tester, store: store);
        // Page 3, as in the design.
        canvasPane.goTo(2);
        await tester.pump();
        await tester.tap(byLabel('Study & math'));
        await tester.pump();
        await tester.tap(find.text('Need to remember'));
        await tester.pump();
        await _pen(tester, _roundLoop(const Rect.fromLTWH(100, 172, 548, 136)));
        await tester.tap(find.bySemanticsLabel('Remember'));
        await tester.pump();
        await tester.enterText(find.byType(TextField), 'always on the exam — know it cold');
        await tester.tap(find.bySemanticsLabel('Tomorrow'));
        await tester.pump();
        FocusManager.instance.primaryFocus?.unfocus();
        await _settle(tester);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('remember_mark.png'));
        await tester.pump(const Duration(seconds: 5));
      }));

  // Remember.png: eight things from six notebooks.
  for (final (name, mode) in [('remember', ThemeMode.light), ('remember_dark', ThemeMode.dark)]) {
    testWidgets(name, (tester) => _withShadows(() async {
          final store = rememberSample()..settings = AppSettings(themeMode: mode).toJson();
          final c = await pumpApp(tester, store: store, location: Routes.remember);
          await indexAll(tester, c);
          await _settle(tester);
          await expectLater(find.byType(MaterialApp), matchesGoldenFile('$name.png'));
        }));
  }

  // Study.png: card 3 of 5 due in Physics — Momentum.
  testWidgets('study', (tester) => _withShadows(() async {
        final c = await pumpApp(tester, store: studySample(), location: Routes.flashcards('dk_mom'));
        await indexAll(tester, c);
        await _settle(tester);
        for (var i = 0; i < 2; i++) {
          await tester.tap(find.bySemanticsLabel('Show answer'));
          await tester.pump();
          await tester.tap(find.bySemanticsLabel(RegExp('^Good, next in ')));
          await _settle(tester);
        }
        expect(find.text('Card 3 of 5 due'), findsOneWidget);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('study.png'));
      }));

  // All cards: the whole Physics — Momentum deck (owner's request, 2026-10-27).
  testWidgets('study_all_cards', (tester) => _withShadows(() async {
        final c = await pumpApp(tester, store: studySample(), location: Routes.flashcards('dk_mom'));
        await indexAll(tester, c);
        await _settle(tester);
        await tester.tap(find.text('All cards'));
        await _settle(tester);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('study_all_cards.png'));
      }));

  // Its back, rated (Study.dc.html's second state).
  testWidgets('study_back', (tester) => _withShadows(() async {
        final c = await pumpApp(tester, store: studySample(), location: Routes.flashcards('dk_mom'));
        await indexAll(tester, c);
        await _settle(tester);
        await tester.tap(find.bySemanticsLabel('Show answer'));
        await _settle(tester);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('study_back.png'));
      }));
}
