import 'package:endless/board/ids.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/recognition/recognizer.dart';
import 'package:endless/recognition/segment.dart';
import 'package:endless/state/device_keyboard.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/state/settings.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../recognition/fake_ink.dart';

/// Convert.png's page: the paragraph to convert, and a formula under it.
({MemoryBoardStore store, List<StrokeItem> para, List<StrokeItem> formula}) _page(FakeRecognizer r) {
  final para = [
    ...writeLine(r, 'total momentum is conserved', at: const Offset(310, 260), height: 36),
    ...writeLine(r, 'in a closed system', at: const Offset(310, 312), height: 36, z: 10),
  ];
  final formula = writeLine(r, 'p = mv', at: const Offset(310, 560), height: 36, z: 20);
  final now = DateTime.utc(2026, 9, 25, 9);
  final page = BoardPage(id: newId('pg'), items: [...para, ...formula]);
  final nb = Notebook(id: newId('nb'), title: 'Physics — Lecture notes', createdAt: now, updatedAt: now, pageIds: [page.id]);
  return (store: storeWith(LoadedNotebook(nb, [page])), para: para, formula: formula);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Selects [ink] with the lasso and opens Convert to text.
Future<void> _convert(WidgetTester tester, ProviderContainer c, List<StrokeItem> ink) async {
  c.read(settingsProvider.notifier).apply((s) => s.copyWith(tool: CanvasTool.lasso));
  await tester.pump();
  canvasPane.selection.select([for (final s in ink) s.id]);
  await tester.pump();
  await tester.tap(find.bySemanticsLabel('Convert to text'));
  await _settle(tester);
}

String _field(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField)).controller!.text;

List<StrokeItem> _strokes(ProviderContainer c) => shownPage(c).items.whereType<StrokeItem>().toList();
List<TextItem> _texts(ProviderContainer c) => shownPage(c).items.whereType<TextItem>().toList();

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the preview shows the text, the word it isn’t sure of, and replaces the ink in one undo step', (tester) async {
    final r = FakeRecognizer()..alts['conserved'] = ['conversed', 'concerned'];
    final p = _page(r);
    final c = await pumpCanvas(tester, store: p.store, recognizer: r);
    await _convert(tester, c, p.para);

    expect(find.bySemanticsLabel('Handwriting to text'), findsOneWidget);
    expect(_field(tester), 'Total momentum is conserved in a closed system.');
    expect(find.text('Not sure about one word:'), findsOneWidget);
    for (final w in ['conserved', 'conversed', 'concerned']) {
      expect(find.bySemanticsLabel(w), findsOneWidget, reason: w);
    }
    expect(find.bySemanticsLabel('Handwriting language: English'), findsOneWidget);
    // Nothing changes until Convert.
    expect(_strokes(c), hasLength(p.para.length + p.formula.length));

    await tester.tap(find.bySemanticsLabel('concerned'));
    await tester.pump();
    expect(_field(tester), 'Total momentum is concerned in a closed system.');
    await tester.tap(find.bySemanticsLabel('conserved'));
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Convert'));
    await tester.pump();
    expect(find.bySemanticsLabel('Handwriting to text'), findsNothing);
    expect(_strokes(c).map((s) => s.id), [for (final s in p.formula) s.id]);
    final t = _texts(c).single;
    expect(t.text, 'Total momentum is conserved in a closed system.');
    expect((t.x, t.y), (310, 260));
    expect(t.font, 'serif');
    expect(find.text('Handwriting converted to text'), findsOneWidget);
    // The new text is selected.
    expect(canvasPane.selection.ids, {t.id});

    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(_texts(c), isEmpty);
    expect(_strokes(c), hasLength(p.para.length + p.formula.length));
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('keep ink too: the text goes where the ink was and the ink moves down under it', (tester) async {
    final r = FakeRecognizer();
    final p = _page(r);
    final c = await pumpCanvas(tester, store: p.store, recognizer: r);
    await _convert(tester, c, p.para);
    expect(find.text('Not sure about one word:'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Keep ink too'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Convert'));
    await tester.pump();
    final t = _texts(c).single;
    expect(t.y, 260);
    final ink = strokesRect([for (final s in _strokes(c)) if (p.para.any((o) => o.id == s.id)) s])!;
    expect(ink.top, closeTo(260 + t.h + 12, 0.5));
    expect(find.text('Text added above your ink'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('copy text only puts it on the clipboard and leaves the page alone', (tester) async {
    final r = FakeRecognizer();
    final p = _page(r);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final c = await pumpCanvas(tester, store: p.store, recognizer: r);
    await _convert(tester, c, p.para);
    await tester.tap(find.bySemanticsLabel('Copy text only'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Copy text'));
    await tester.pump();
    expect(copied, 'Total momentum is conserved in a closed system.');
    expect(_texts(c), isEmpty);
    expect(_strokes(c), hasLength(p.para.length + p.formula.length));
    expect(find.text('Copied the text'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('convert the whole page reads every paragraph; each becomes its own text box', (tester) async {
    final r = FakeRecognizer();
    final p = _page(r);
    final c = await pumpCanvas(tester, store: p.store, recognizer: r);
    await _convert(tester, c, p.formula);
    expect(_field(tester), 'P = mv');
    await tester.tap(find.bySemanticsLabel('Convert the whole page'));
    await _settle(tester);
    expect(_field(tester), 'Total momentum is conserved in a closed system.\n\nP = mv');
    expect(find.bySemanticsLabel('Convert the whole page'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Convert'));
    await tester.pump();
    expect(_strokes(c), isEmpty);
    expect(_texts(c).map((t) => t.text), ['Total momentum is conserved in a closed system.', 'P = mv']);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('another language reads it again, downloading that language first', (tester) async {
    final r = FakeRecognizer()..translate = (w, lang) => lang == 'de-DE' && w == 'total' ? 'gesamt' : w;
    final p = _page(r);
    final c = await pumpCanvas(tester, store: p.store, recognizer: r);
    await _convert(tester, c, p.para);
    await tester.tap(find.bySemanticsLabel('Handwriting language: English'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deutsch').last);
    await _settle(tester);
    expect(r.downloaded, 1);
    expect(r.languages, contains('de-DE'));
    expect(_field(tester), startsWith('Gesamt momentum'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Handwriting language: Deutsch'), findsOneWidget);
    // The language for search stays as it was.
    expect(c.read(settingsProvider).handwritingLanguage, isNull);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('without a recognizer the text can be typed in, and Cancel changes nothing', (tester) async {
    final r = FakeRecognizer();
    final p = _page(r);
    final c = await pumpCanvas(tester, store: p.store, recognizer: const NoInkRecognizer());
    await _convert(tester, c, p.para);
    expect(find.textContaining('Handwriting recognition runs on the tablet'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Cancel'));
    await tester.pump();
    expect(find.bySemanticsLabel('Handwriting to text'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Convert to text'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), 'Typed by hand');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Convert'));
    await tester.pump();
    expect(_texts(c).single.text, 'Typed by hand');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('if the recognizer breaks, the panel says so and the text can be typed (never stuck on Reading)', (tester) async {
    final r = _Broken();
    final p = _page(r);
    final c = await pumpCanvas(tester, store: p.store, recognizer: r);
    await _convert(tester, c, p.para);
    expect(find.text('Reading your handwriting…'), findsNothing);
    expect(find.textContaining('Couldn’t read this in English'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Typed instead');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Convert'));
    await tester.pump();
    expect(_texts(c).single.text, 'Typed instead');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a selection with no handwriting says so', (tester) async {
    final r = FakeRecognizer();
    final p = _page(r);
    final c = await pumpCanvas(tester, store: p.store, recognizer: r);
    final marker = strokeFrom([const Offset(800, 300), const Offset(900, 320)], tool: InkTool.marker);
    c.read(settingsProvider.notifier).apply((s) => s.copyWith(tool: CanvasTool.lasso));
    await tester.pump();
    c.read(notebookProvider(canvasPane.notebookId).notifier).addStroke(shownPage(c).id, marker);
    await tester.pump();
    canvasPane.selection.select([marker.id]);
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Convert to text'));
    await tester.pump();
    expect(find.text('No handwriting here to convert'), findsOneWidget);
    expect(find.bySemanticsLabel('Handwriting to text'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('backspace and show keyboard under the text', (tester) async {
    final r = FakeRecognizer();
    final p = _page(r);
    final c = await pumpCanvas(tester, store: p.store, recognizer: r);
    await _convert(tester, c, p.para);
    expect(_field(tester), 'Total momentum is conserved in a closed system.');
    final field = tester.widget<TextField>(find.byType(TextField));

    // No cursor yet: the last character goes.
    await tester.tap(find.bySemanticsLabel('Backspace'));
    await tester.pump();
    expect(_field(tester), 'Total momentum is conserved in a closed system');
    // At the cursor, and a selection.
    field.controller!.selection = const TextSelection.collapsed(offset: 5);
    await tester.tap(find.bySemanticsLabel('Backspace'));
    await tester.pump();
    expect(_field(tester), 'Tota momentum is conserved in a closed system');
    field.controller!.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    await tester.tap(find.bySemanticsLabel('Backspace'));
    await tester.pump();
    expect(_field(tester), 'momentum is conserved in a closed system');

    // Held down, it keeps deleting.
    field.controller!.selection = const TextSelection.collapsed(offset: 8);
    final hold = await tester.startGesture(tester.getCenter(find.bySemanticsLabel('Backspace')));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump(const Duration(milliseconds: 70));
    await tester.pump(const Duration(milliseconds: 70));
    await hold.up();
    await tester.pump(const Duration(milliseconds: 500));
    expect(_field(tester), 'momen is conserved in a closed system');

    // The tablet's keyboard, for the text.
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.tap(find.bySemanticsLabel('Show keyboard'));
    await tester.pump();
    await tester.pump();
    expect(field.focusNode!.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('with the S Pen, show keyboard and backspace keep the cursor in the text', (tester) async {
    final r = FakeRecognizer();
    final p = _page(r);
    final c = await pumpCanvas(tester, store: p.store, recognizer: r);
    await _convert(tester, c, p.para);
    final field = tester.widget<TextField>(find.byType(TextField));

    // The S Pen puts the cursor in the text.
    await tester.tap(find.byType(TextField), kind: PointerDeviceKind.stylus);
    await tester.pump();
    expect(field.focusNode!.hasFocus, isTrue);
    field.controller!.selection = const TextSelection.collapsed(offset: 5);
    await tester.pump();

    // On Android a pen tap outside a text field takes the cursor out; these buttons don't.
    await tester.tap(find.bySemanticsLabel('Show keyboard'), kind: PointerDeviceKind.stylus);
    await tester.pump();
    await tester.pump();
    expect(field.focusNode!.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.bySemanticsLabel('Backspace'), kind: PointerDeviceKind.stylus);
    await tester.pump();
    expect(_field(tester), 'Tota momentum is conserved in a closed system.');
    expect(field.focusNode!.hasFocus, isTrue);
    expect(field.controller!.selection, const TextSelection.collapsed(offset: 4));
    await tester.pump(const Duration(seconds: 5));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('when the tablet holds its keyboard back for a physical one, show keyboard says so', (tester) async {
    final r = FakeRecognizer();
    final p = _page(r);
    final keyboard = _HeldBackKeyboard();
    final c = await pumpCanvas(
      tester,
      store: p.store,
      recognizer: r,
      extra: [deviceKeyboardProvider.overrideWithValue(keyboard)],
    );
    await _convert(tester, c, p.para);
    // The keyboard comes up after all: nothing to say.
    tester.view.viewInsets = const FakeViewPadding(bottom: 600);
    await tester.tap(find.bySemanticsLabel('Show keyboard'));
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump();
    expect(find.textContaining('thinks a physical keyboard is connected'), findsNothing);
    // It doesn't.
    tester.view.resetViewInsets();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.bySemanticsLabel('Show keyboard'));
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump();
    expect(find.textContaining('thinks a physical keyboard is connected'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Settings'));
    await tester.pump();
    expect(keyboard.opened, 1);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('letters straightened with Straighten lines are converted with the rest', (tester) async {
    final r = FakeRecognizer();
    final ink = writeLine(r, 'total momentum is conserved', at: const Offset(310, 260), height: 36);
    // "is" (x 534–562) straightened into a line, as the toolbar's Straighten lines does to an l.
    final straight = ink[2].copyWith(
      pagePoints: const [InkPoint(548, 260, 0.5, 0), InkPoint(548, 296, 0.5, 10)],
      shape: () => 'line',
    );
    r.labelAt(const Offset(548, 260), 'is');
    final page = BoardPage(id: newId('pg'), items: [ink[0], ink[1], straight, ink[3]]);
    final now = DateTime.utc(2026, 9, 25, 9);
    final nb = Notebook(id: newId('nb'), title: 'Straight', createdAt: now, updatedAt: now, pageIds: [page.id]);
    final c = await pumpCanvas(tester, store: storeWith(LoadedNotebook(nb, [page])), recognizer: r);
    await _convert(tester, c, [ink[0], ink[1], straight, ink[3]]);
    expect(_field(tester), 'Total momentum is conserved.');

    await tester.tap(find.bySemanticsLabel('Convert'));
    await tester.pump();
    // The straightened letter goes with the rest of the ink.
    expect(_strokes(c), isEmpty);
    expect(_texts(c).single.text, 'Total momentum is conserved.');
    await tester.pump(const Duration(seconds: 5));
  });
}

/// A recognizer whose native side fails in a way nobody planned for.
class _Broken extends FakeRecognizer {
  @override
  Future<List<String>> recognize(
    List<List<InkSamplePoint>> strokes, {
    required String language,
    String preContext = '',
    Size? area,
  }) async =>
      throw StateError('native side went away');
}

/// A tablet that thinks a physical keyboard is attached.
class _HeldBackKeyboard implements DeviceKeyboard {
  int opened = 0;

  @override
  Future<bool> heldBack() async => true;

  @override
  Future<bool> openSettings() async {
    opened++;
    return true;
  }
}
