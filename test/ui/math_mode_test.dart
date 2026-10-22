import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:endless/board/ids.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/canvas/selection.dart';
import 'package:endless/math/math_pictures.dart';
import 'package:endless/math/math_reader.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/ui/canvas/canvas_screen.dart' show mathHint;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// Reads any ink as [latex] (null: as nothing).
class FakeMathReader extends MathReader {
  FakeMathReader(this.latex) : super(() async => throw UnsupportedError('no model in tests'));

  String? latex;
  int reads = 0;

  @override
  Future<MathReading?> read(List<StrokeItem> strokes) async {
    reads++;
    return latex == null ? null : MathReading(latex!);
  }
}

/// Typesets as a box 10 px a character wide (the real typesetter waits for
/// SVG pieces read on another isolate, which fake time can't).
Future<MathPicture?> fakeTypeset(String latex) async {
  final size = Size(latex.length * 10.0, 40);
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(Offset.zero & size, Paint());
  return MathPicture(recorder.endRecording(), size);
}

List<Override> mathOverrides(FakeMathReader reader) => [
      mathReaderProvider.overrideWithValue(reader),
      mathPicturesProvider.overrideWith((ref) {
        final p = MathPictures(typeset: fakeTypeset);
        ref.onDispose(p.dispose);
        return p;
      }),
    ];

List<StrokeItem> _strokes(ProviderContainer c) => shownPage(c).items.whereType<StrokeItem>().toList();
List<MathItem> _math(ProviderContainer c) => shownPage(c).items.whereType<MathItem>().toList();
List<GraphItem> _graphs(ProviderContainer c) => shownPage(c).items.whereType<GraphItem>().toList();

/// Writes with the S Pen along [points], 8 ms apart; with [hold], the pen
/// stays down at the end that long.
Future<void> _pen(WidgetTester tester, List<Offset> points, {Duration? hold}) async {
  final g = await tester.createGesture(kind: PointerDeviceKind.stylus);
  var t = const Duration(seconds: 20);
  await g.down(points.first, timeStamp: t);
  for (final p in points.skip(1)) {
    t += const Duration(milliseconds: 8);
    await g.moveTo(p, timeStamp: t);
  }
  if (hold != null) {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(hold - const Duration(milliseconds: 200));
  }
  await g.up(timeStamp: t + (hold ?? Duration.zero));
  await tester.pump();
}

List<Offset> _line(Offset a, Offset b, {int n = 12}) => [for (var i = 0; i <= n; i++) Offset.lerp(a, b, i / n)!];

/// "v = 2", roughly: four short strokes on one line.
Future<void> _writeMath(WidgetTester tester, {Offset at = const Offset(400, 300)}) async {
  await _pen(tester, _line(at, at + const Offset(10, 30)));
  await _pen(tester, _line(at + const Offset(10, 30), at + const Offset(20, 0)));
  await _pen(tester, _line(at + const Offset(40, 12), at + const Offset(60, 12)));
  await _pen(tester, _line(at + const Offset(40, 20), at + const Offset(60, 20)));
}

/// The math keyboard's Insert (the rail has an Insert too).
final _insert = find.descendant(of: find.bySemanticsLabel('Math keyboard'), matching: find.bySemanticsLabel('Insert'));

Future<void> _openMath(WidgetTester tester, String item) async {
  await tester.tap(byLabel('Study & math'));
  await tester.pump();
  await tester.tap(find.text(item));
  await tester.pump();
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

MemoryBoardStore _storeWithMath(String latex) {
  final now = DateTime.utc(2026, 10, 15, 9);
  final page = BoardPage(id: newId('pg'), items: [
    MathItem(id: 'it_math', x: 400, y: 300, z: 1, createdAt: now, latex: latex, w: 200, h: 60, color: const Color(0xFF1E1C19)),
  ]);
  final nb = Notebook(id: newId('nb'), title: 'Physics — Lecture notes', createdAt: now, updatedAt: now, pageIds: [page.id]);
  return storeWith(LoadedNotebook(nb, [page]));
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('Study & math → Math & graphs: the math bar instead of the tools (Math.png), Done leaves', (tester) async {
    await pumpCanvas(tester, extra: mathOverrides(FakeMathReader(null)));
    await _openMath(tester, 'Math & graphs');

    expect(canvasPane.math.on, isTrue);
    expect(find.text('Math mode'), findsOneWidget);
    expect(find.text('Handwriting converts as you go'), findsOneWidget);
    for (final label in ['Lasso', 'Formulas & tools', 'Add a graph', 'Done']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
    expect(find.text(mathHint), findsOneWidget);
    // The rail, the tool pill and the zoom pill make way.
    expect(byLabel('Study & math'), findsNothing);
    expect(byLabel('Pen'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Done'));
    await tester.pump();
    expect(canvasPane.math.on, isFalse);
    expect(find.text('Math mode'), findsNothing);
    expect(byLabel('Study & math'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('what the pen writes is picked up when it rests, with a preview; Convert to math is one undo step', (tester) async {
    final reader = FakeMathReader(r'v=2');
    final c = await pumpCanvas(tester, extra: mathOverrides(reader));
    await _openMath(tester, 'Math & graphs');
    await _writeMath(tester);
    expect(_strokes(c), hasLength(4));
    // Not while the pen is still busy.
    await tester.pump(const Duration(milliseconds: 600));
    expect(canvasPane.selection.isEmpty, isTrue);

    await tester.pump(const Duration(milliseconds: 700));
    await _settle(tester);
    expect(canvasPane.selection.ids, {for (final s in _strokes(c)) s.id});
    expect(find.bySemanticsLabel('Convert to math'), findsOneWidget);
    expect(find.bySemanticsLabel('Graph it'), findsOneWidget);
    expect(find.bySemanticsLabel('Copy as LaTeX'), findsOneWidget);
    expect(find.text('PREVIEW'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Convert to math'));
    await _settle(tester);
    expect(_strokes(c), isEmpty);
    final m = _math(c).single;
    expect(m.latex, r'v=2');
    // Where the writing was: from its left edge, on its line.
    expect(m.center.dy, closeTo(315, 6));
    expect(find.text('Converted to math — tap to edit'), findsOneWidget);
    expect(canvasPane.selection.isEmpty, isTrue);

    final notebook = c.read(notebookProvider(canvasPane.notebookId).notifier);
    notebook.undo(shownPage(c).id);
    await tester.pump();
    expect(_strokes(c), hasLength(4));
    expect(_math(c), isEmpty);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('ink that isn’t math says so, and nothing changes', (tester) async {
    final c = await pumpCanvas(tester, extra: mathOverrides(FakeMathReader(null)));
    await _openMath(tester, 'Math & graphs');
    await _writeMath(tester);
    await tester.pump(const Duration(milliseconds: 1300));
    await _settle(tester);
    expect(find.text('Can’t read this as math. Try writing it again'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Convert to math'));
    await _settle(tester);
    expect(_strokes(c), hasLength(4));
    expect(find.text('Couldn’t read that as math. Try writing it again'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Copy as LaTeX copies the reading; Graph it graphs a function beside the ink', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final reader = FakeMathReader(r'y=\frac{x^{2}}{2}');
    final c = await pumpCanvas(tester, extra: mathOverrides(reader));
    await _openMath(tester, 'Math & graphs');
    await _writeMath(tester);
    await tester.pump(const Duration(milliseconds: 1300));
    await _settle(tester);

    await tester.tap(find.bySemanticsLabel('Copy as LaTeX'));
    await _settle(tester);
    expect(copied, [r'y=\frac{x^{2}}{2}']);
    expect(find.text('Copied the LaTeX'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Graph it'));
    await _settle(tester);
    final g = _graphs(c).single;
    expect(g.functions.single.expr, r'y=\frac{x^{2}}{2}');
    expect(g.view.left, -5);
    // The ink stays; the graph is to its right.
    expect(_strokes(c), hasLength(4));
    expect(g.x, greaterThan(_strokes(c).map((s) => s.bounds.right).reduce((a, b) => a > b ? a : b)));
    expect(find.text('Graphed it'), findsOneWidget);

    // Something that isn't a function of x isn't graphed.
    reader.latex = r'E=mc^{2}';
    canvasPane.selection.clear();
    await tester.pump();
    canvasPane.selection
      ..menu = SelectionMenu.math
      ..select([for (final s in _strokes(c)) s.id]);
    await _settle(tester);
    await tester.tap(find.bySemanticsLabel('Graph it'));
    await _settle(tester);
    expect(_graphs(c), hasLength(1));
    expect(find.text('Only a function of x can be graphed, like y = x²'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a tap on math opens the keyboard on it; Insert changes it in one undo step', (tester) async {
    final c = await pumpCanvas(tester, store: _storeWithMath(r'\omega=\frac{\Delta\theta}{\Delta t}'), extra: mathOverrides(FakeMathReader(null)));
    await tester.tapAt(const Offset(500, 330));
    await _settle(tester);

    expect(find.bySemanticsLabel('Math keyboard'), findsOneWidget);
    final draft = canvasPane.math.draft!;
    expect(draft.itemId, 'it_math');
    expect(draft.text.text, 'ω = Δθ / Δt');
    // Math.png's tabs and the Greek keys, 12 to a row.
    for (final tab in ['Greek', 'Operators', 'Structures', 'Units']) {
      expect(find.bySemanticsLabel(tab), findsOneWidget, reason: tab);
    }
    final alpha = tester.getRect(find.bySemanticsLabel('Insert α'));
    final mu = tester.getRect(find.bySemanticsLabel('Insert μ'));
    final nu = tester.getRect(find.bySemanticsLabel('Insert ν'));
    expect(mu.top, alpha.top);
    expect(nu.top, greaterThan(alpha.top));
    expect(alpha.height, 48);

    // Keys type at the cursor: after "ω".
    draft.text.selection = const TextSelection.collapsed(offset: 1);
    await tester.tap(find.bySemanticsLabel('Insert α'));
    await tester.pump();
    expect(draft.text.text, 'ωα = Δθ / Δt');
    await tester.tap(find.bySemanticsLabel('Delete last symbol'));
    await tester.pump();
    expect(draft.text.text, 'ω = Δθ / Δt');

    await tester.tap(find.bySemanticsLabel('Structures'));
    await tester.pump();
    draft.text.selection = TextSelection.collapsed(offset: draft.text.text.length);
    await tester.tap(find.bySemanticsLabel('Insert Power'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Units'));
    await tester.pump();
    expect(find.bySemanticsLabel('Insert m/s²'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Greek'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Insert π'));
    await tester.pump();
    expect(draft.text.text, 'ω = Δθ / Δt^π');

    await tester.tap(_insert);
    await _settle(tester);
    expect(find.bySemanticsLabel('Math keyboard'), findsNothing);
    expect(_math(c).single.latex, r'\omega=\frac{\Delta\theta}{\Delta t^{\pi}}');
    expect(find.text('Changed the math'), findsOneWidget);

    c.read(notebookProvider(canvasPane.notebookId).notifier).undo(shownPage(c).id);
    await tester.pump();
    expect(_math(c).single.latex, r'\omega=\frac{\Delta\theta}{\Delta t}');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('in math mode a finger tap on the paper types new math there', (tester) async {
    final c = await pumpCanvas(tester, extra: mathOverrides(FakeMathReader(null)));
    await _openMath(tester, 'Math & graphs');
    await tester.tapAt(const Offset(300, 200));
    await _settle(tester);
    final draft = canvasPane.math.draft!;
    expect(draft.itemId, isNull);
    await tester.tap(find.bySemanticsLabel('Structures'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Insert Square root'));
    await tester.pump();
    // The cursor waits between the brackets.
    expect(draft.text.text, '√()');
    expect(draft.text.selection.baseOffset, 2);
    await tester.tap(find.bySemanticsLabel('Greek'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Insert π'));
    await tester.pump();
    await tester.tap(_insert);
    await _settle(tester);
    final m = _math(c).single;
    expect(m.latex, r'\sqrt{\pi}');
    // Its left edge where the finger tapped, on that line.
    final tapped = canvasPane.view.toPage(const Offset(300, 200));
    expect(m.x, closeTo(tapped.dx, 0.5));
    expect(m.center.dy, closeTo(tapped.dy, 0.5));
    expect(find.text('Added the math to the page'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Math tools: its bar, and the one keyboard on its Symbols tab; formulas go straight onto the page', (tester) async {
    final c = await pumpCanvas(tester, extra: mathOverrides(FakeMathReader(null)));
    await _openMath(tester, 'Math tools');
    final math = canvasPane.math;
    expect(math.draft, isNotNull);
    expect(math.tools, isTrue);
    // MathKit.png's bar.
    for (final label in ['Number line', 'Unit circle', 'Polar grid', 'Graph', 'Done']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
    expect(find.text('Math mode'), findsNothing);
    expect(find.bySemanticsLabel('Math keyboard'), findsOneWidget);
    // MathKit.png's symbols and formulas are tabs of the keyboard.
    for (final tab in ['Greek', 'Operators', 'Structures', 'Units', 'Symbols', 'Math', 'Physics']) {
      expect(find.bySemanticsLabel(tab), findsOneWidget, reason: tab);
    }
    expect(find.text('Formulas & symbols'), findsNothing);
    // Only the keyboard, along the bottom: the page above it is free.
    final board = tester.getRect(find.bySemanticsLabel('Math keyboard'));
    expect(board.top, greaterThan(400));

    // The symbols, 12 to a row like the other keys; a tap types at the cursor.
    final pi = tester.getRect(find.bySemanticsLabel('Insert pi'));
    final tau = tester.getRect(find.bySemanticsLabel('Insert tau'));
    expect(tau.top, pi.top);
    await tester.tap(find.bySemanticsLabel('Insert pi'));
    await tester.pump();
    expect(math.draft!.text.text, 'π');

    // A formula, a tab along, goes on the page with one tap, clear of the
    // keyboard; one undo step.
    await tester.tap(find.bySemanticsLabel('Math'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Insert Area of a circle'));
    await _settle(tester);
    final area = _math(c).single;
    expect(area.latex, r'A=\pi r^{2}');
    expect(find.text('Added A = πr² to the page'), findsOneWidget);
    expect(canvasPane.view.toScreen(area.extent.bottomLeft).dy, lessThan(board.top));
    expect(math.draft!.text.text, 'π', reason: 'what was being typed stays');
    await tester.tap(find.bySemanticsLabel('Physics'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Insert Kinetic energy'));
    await _settle(tester);
    expect(_math(c), hasLength(2));
    // Not on top of the first.
    expect(_math(c).last.extent.overlaps(area.extent), isFalse);
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(_math(c), hasLength(1));

    // Insert puts what was typed on the page.
    math.draft!.text.text = 'KE = 1/2 mv²';
    await tester.tap(_insert);
    await _settle(tester);
    expect(_math(c).map((m) => m.latex), contains(r'KE=\frac{1}{2}mv^{2}'));

    // Done goes back to math mode's bar.
    await tester.tap(find.bySemanticsLabel('Done'));
    await tester.pump();
    expect(math.tools, isFalse);
    expect(find.text('Math mode'), findsOneWidget);

    // With the keyboard open on other math, Formulas & tools turns it to Symbols.
    await tester.tapAt(const Offset(900, 150));
    await _settle(tester);
    final draft = math.draft;
    expect(draft, isNotNull);
    // It opens on the tab last used.
    expect(find.bySemanticsLabel('Insert Kinetic energy'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Greek'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Formulas & tools'));
    await tester.pump();
    expect(math.draft, same(draft));
    expect(math.tools, isTrue);
    expect(find.bySemanticsLabel('Insert pi'), findsOneWidget);
    // Esc: the keyboard, then Math tools, then math mode.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect((math.draft, math.tools, math.on), (null, true, true));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect((math.tools, math.on), (false, true));
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Add a graph: type a function, Insert graphs it', (tester) async {
    final c = await pumpCanvas(tester, extra: mathOverrides(FakeMathReader(null)));
    await _openMath(tester, 'Math & graphs');
    await tester.tap(find.bySemanticsLabel('Add a graph'));
    await _settle(tester);
    final draft = canvasPane.math.draft!;
    expect((draft.graph, draft.text.text), (true, 'y = '));
    draft.text.text = 'y = 2 sin x';
    await tester.tap(_insert);
    await _settle(tester);
    expect(_graphs(c).single.functions.single.expr, r'y=2\sin x');
    expect(_math(c), isEmpty);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('in math mode ink stays as written: a 2 isn’t made an arrow, a hold doesn’t straighten', (tester) async {
    final c = await pumpCanvas(tester, extra: mathOverrides(FakeMathReader(null)));
    await _openMath(tester, 'Math & graphs');
    // A real 2 (MathWriting's 2^{k}t_{0}): its turn into the base line looks
    // like a flick back to the arrow gesture.
    final sample = (jsonDecode(File('test/fixtures/math/ink_samples.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((s) => s['label'] == r'2^{k}t_{0}');
    final strokes = [
      for (final st in sample['strokes'] as List)
        [for (final p in st as List) Offset((p[0] as num).toDouble(), (p[1] as num).toDouble())],
    ];
    final all = strokes.expand((st) => st);
    final left = all.map((p) => p.dx).reduce(math.min), top = all.map((p) => p.dy).reduce(math.min);
    final k = 70 / (all.map((p) => p.dy).reduce(math.max) - top);
    final two = [for (final p in strokes.first) Offset(300 + (p.dx - left) * k, 300 + (p.dy - top) * k)];
    await _pen(tester, two);
    final s = _strokes(c).single;
    expect(s.arrow, isNull);
    expect(s.pageInk, hasLength(two.length));

    // Held still at the end of a line: no straightening.
    await _pen(tester, _line(const Offset(400, 450), const Offset(700, 340), n: 30), hold: const Duration(milliseconds: 700));
    expect(_strokes(c).last.straightened, isNull);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the lasso in math mode gets the math toolbar', (tester) async {
    final c = await pumpCanvas(tester, extra: mathOverrides(FakeMathReader('x')));
    await _openMath(tester, 'Math & graphs');
    await _writeMath(tester);
    await tester.tap(find.bySemanticsLabel('Lasso'));
    await tester.pump();
    expect(c.read(settingsProvider).tool, CanvasTool.lasso);
    canvasPane.selection.clear();
    await tester.pump();
    await _pen(tester, [
      for (var i = 0; i <= 24; i++)
        const Offset(430, 315) + Offset.fromDirection(i / 24 * 6.3, 70),
    ]);
    await _settle(tester);
    expect(canvasPane.selection.menu, SelectionMenu.math);
    expect(find.bySemanticsLabel('Convert to math'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
