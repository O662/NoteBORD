// Golden images of math mode at the tablet size (1280×800). Compare with
// design/screens/Math.png and MathKit.png.
//
// Regenerate after an intended visual change:
//   flutter test --update-goldens test/golden/phase6_golden_test.dart
@Tags(['golden'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:endless/board/ids.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/canvas/math_mode.dart';
import 'package:endless/canvas/selection.dart';
import 'package:endless/math/linear.dart';
import 'package:endless/math/math_pictures.dart';
import 'package:endless/math/math_reader.dart';
import 'package:endless/state/notebook.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// Reads any ink as [latex].
class _Reader extends MathReader {
  _Reader(this.latex) : super(() async => throw UnsupportedError('no model in tests'));

  final String latex;

  @override
  Future<MathReading?> read(List<StrokeItem> strokes) async => MathReading(latex);
}

/// flutter_math_fork's KaTeX fonts, so typeset math renders for real.
Future<void> _loadMathFonts() async {
  const fonts = {
    'KaTeX_Main': ['Regular', 'Italic', 'Bold', 'BoldItalic'],
    'KaTeX_Math': ['Italic', 'BoldItalic'],
    'KaTeX_AMS': ['Regular'],
    'KaTeX_Size1': ['Regular'],
    'KaTeX_Size2': ['Regular'],
    'KaTeX_Size3': ['Regular'],
    'KaTeX_Size4': ['Regular'],
  };
  for (final e in fonts.entries) {
    final loader = FontLoader('packages/flutter_math_fork/${e.key}');
    for (final style in e.value) {
      loader.addFont(rootBundle.load('packages/flutter_math_fork/lib/katex_fonts/fonts/${e.key}-$style.ttf'));
    }
    await loader.load();
  }
}

Future<void> _withShadows(Future<void> Function() body) async {
  debugDisableShadows = false;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
  }
}

/// Pen strokes from MathWriting (f⁻¹(y) = √y), moved to [at] at [height].
List<StrokeItem> _handwriting(Offset at, double height) {
  final sample = (jsonDecode(File('test/fixtures/math/ink_samples.json').readAsStringSync()) as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((s) => s['label'] == r'f^{-1}(y)=\sqrt{y}');
  final strokes = [
    for (final stroke in sample['strokes'] as List)
      [for (final p in stroke as List) Offset((p[0] as num).toDouble(), (p[1] as num).toDouble())],
  ];
  var top = double.infinity, left = double.infinity, bottom = -double.infinity;
  for (final s in strokes) {
    for (final p in s) {
      top = p.dy < top ? p.dy : top;
      left = p.dx < left ? p.dx : left;
      bottom = p.dy > bottom ? p.dy : bottom;
    }
  }
  final k = height / (bottom - top);
  final now = DateTime.utc(2026, 10, 15, 9);
  return [
    for (final (i, s) in strokes.indexed)
      StrokeItem.fromPagePoints(
        id: 'it_ink$i',
        z: 10 + i,
        createdAt: now,
        tool: InkTool.pen,
        penType: PenType.ballpoint,
        color: const Color(0xFF1E1C19),
        width: 3,
        usePressure: false,
        pagePoints: [for (final p in s) InkPoint(at.dx + (p.dx - left) * k, at.dy + (p.dy - top) * k, 0.5, 0)],
      ),
  ];
}

const _row = [
  r'F=\frac{dp}{dt}',
  r'J=\int_{t_{0}}^{t_{1}}F\,dt=\Delta p',
  r'KE=\frac{1}{2}mv^{2}',
  r'\Sigma p_{before}=\Sigma p_{after}',
];
const _omega = r'\omega=\frac{\Delta\theta}{\Delta t}';
const _graphed = [r'y=\frac{x^{2}}{2}', r'y=2\sin x', r'y=x+1'];

MemoryBoardStore _store() {
  final now = DateTime.utc(2026, 10, 15, 9);
  final items = <Item>[
    TextItem(
      id: 'it_title',
      x: 110,
      y: 92,
      z: 1,
      createdAt: now,
      wrap: 700,
      text: 'Lecture 4 — Energy & impulse',
      font: 'hand',
      size: 46,
      color: const Color(0xFF2B5A8C),
      autoWidth: true,
    ),
    ..._handwriting(const Offset(130, 168), 52),
  ];
  return storeWith(LoadedNotebook(
    Notebook(id: newId('nb'), title: 'Physics — Lecture notes', createdAt: now, updatedAt: now, pageIds: ['pg_math']),
    [BoardPage(id: 'pg_math', items: items)],
  ));
}

/// Typesets [latex] for real (KaTeX fonts, SVG pieces and all).
Future<void> _typeset(WidgetTester tester, ProviderContainer c, List<String> latex) async {
  await tester.runAsync(() async {
    for (final l in latex) {
      expect(await c.read(mathPicturesProvider).load(l), isNotNull, reason: l);
    }
  });
}

/// Pumps until the live math widgets' SVG pieces have arrived.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(milliseconds: 400));
}

/// Math items like Math.png's row, measured by the typesetter.
List<MathItem> _mathRow(ProviderContainer c) {
  final now = DateTime.utc(2026, 10, 15, 9);
  final pictures = c.read(mathPicturesProvider);
  var x = 110.0;
  return [
    for (final (i, latex) in _row.indexed)
      () {
        final box = MathItem.boxFor(pictures.picture(latex)!.size, mathReferenceSize, 30);
        final m = MathItem(id: 'it_row$i', x: x, y: 316, z: 30 + i, createdAt: now, latex: latex, w: box.width, h: box.height, size: 30, color: const Color(0xFF1E1C19));
        x += box.width + 16;
        return m;
      }(),
  ];
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    await _loadMathFonts();
  });

  testWidgets('math', (tester) => _withShadows(() async {
        final c = await pumpCanvas(tester, store: _store(), extra: [mathReaderProvider.overrideWithValue(_Reader(r'f^{-1}(y)=\sqrt{y}'))]);
        await _typeset(tester, c, [..._row, _omega, r'f^{-1}(y)=\sqrt{y}']);
        final notebook = c.read(notebookProvider(canvasPane.notebookId).notifier);
        final now = DateTime.utc(2026, 10, 15, 9);
        final omega = c.read(mathPicturesProvider).picture(_omega)!;
        final box = MathItem.boxFor(omega.size, mathReferenceSize, 30);
        notebook.insertItems('pg_math', [
          ..._mathRow(c),
          MathItem(id: 'it_omega', x: 900, y: 156, z: 40, createdAt: now, latex: _omega, w: box.width, h: box.height, size: 30, color: const Color(0xFF1E1C19)),
        ]);
        await tester.tap(byLabel('Study & math'));
        await tester.pump();
        await tester.tap(find.text('Math & graphs'));
        await tester.pump();
        // Typing ω = Δθ / Δt, while the handwriting is picked up.
        canvasPane.math.type(MathDraft(itemId: 'it_omega', at: const Offset(900, 196), text: latexToLinear(_omega)));
        await tester.pump();
        final ink = [for (final i in shownPage(c).items) if (i is StrokeItem) i];
        final area = ink.map((s) => s.bounds).reduce((a, b) => a.expandToInclude(b)).inflate(14);
        canvasPane.selection
          ..menu = SelectionMenu.math
          ..select(
            [for (final s in ink) s.id],
            outline: Path()..addRRect(RRect.fromRectAndRadius(area, Radius.circular(area.shortestSide / 2))),
            revision: shownNotebook(c).revision,
          );
        await _settle(tester);

        await expectLater(find.byType(MaterialApp), matchesGoldenFile('math.png'));
        await tester.pump(const Duration(seconds: 5));
      }));

  testWidgets('math_kit', (tester) => _withShadows(() async {
        final c = await pumpCanvas(tester, store: _store());
        await _typeset(tester, c, [..._row, ..._graphed]);
        final now = DateTime.utc(2026, 10, 15, 9);
        c.read(notebookProvider(canvasPane.notebookId).notifier).insertItems('pg_math', [
          ..._mathRow(c),
          GraphItem(
            id: 'it_graph',
            x: 110,
            y: 430,
            z: 50,
            createdAt: now,
            w: 600,
            h: 350,
            functions: const [
              GraphLine(r'y=\frac{x^{2}}{2}', Color(0xFF2B5A8C)),
              GraphLine(r'y=2\sin x', Color(0xFFB5532A)),
              GraphLine(r'y=x+1', Color(0xFF3E7B4F)),
            ],
            view: const Rect.fromLTRB(-5, -3, 5, 8),
          ),
        ]);
        await tester.tap(byLabel('Study & math'));
        await tester.pump();
        await tester.tap(find.text('Math tools'));
        await tester.pump();
        await _settle(tester);

        await expectLater(find.byType(MaterialApp), matchesGoldenFile('math_kit.png'));
        await tester.pump(const Duration(seconds: 5));
      }));
}
