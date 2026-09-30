import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:endless/app.dart';
import 'package:endless/board/ids.dart';
import 'package:endless/board/lock.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/canvas/page_runtime.dart';
import 'package:endless/canvas/pane.dart';
import 'package:endless/library/index_db.dart';
import 'package:endless/state/assets.dart';
import 'package:endless/state/biometric.dart';
import 'package:endless/state/bootstrap.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/state/photos.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:endless/ui/canvas/canvas_screen.dart';
import 'package:endless/ui/common.dart';
import 'package:endless/ui/routes.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// Finds a chrome button by its accessible label.
Finder byLabel(String label) => find.byWidgetPredicate((w) => w is ChromeButton && w.label == label);

/// Loads the bundled fonts so text renders for real (not as boxes) in goldens.
Future<void> loadAppFonts() async {
  const families = {
    'Figtree': ['Regular', 'Medium', 'SemiBold', 'Bold'],
    'Newsreader': ['Regular', 'Medium', 'Italic', 'MediumItalic'],
    'Caveat': ['Regular', 'SemiBold'],
  };
  for (final e in families.entries) {
    final loader = FontLoader(e.key);
    for (final style in e.value) {
      loader.addFont(rootBundle.load('assets/fonts/${e.key}-$style.ttf'));
    }
    await loader.load();
  }
}

/// "Now" in tests and goldens: Friday, September 25, 2026, 10:00 (like the design).
final testNow = DateTime(2026, 9, 25, 10);

/// Real Argon2id and AES, with cheap parameters and no isolates.
final testCrypto = LockCrypto(kdf: const Argon2Kdf(background: false), params: KdfParams.fast, background: false);

/// A fingerprint reader that always recognizes the finger (unless [fail]).
class FakeBiometric implements BiometricUnlock {
  final saved = <String, Uint8List>{};
  bool available = true;
  bool fail = false;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> save(String slot, Uint8List key) async => saved[slot] = key;

  @override
  Future<Uint8List?> read(String slot, {required String reason}) async => fail ? null : saved[slot];

  @override
  Future<void> delete(String slot) async => saved.remove(slot);
}

/// A photo picker that hands back [bytes] (null: the user backed out).
class FakePhotoPicker implements PhotoPicker {
  FakePhotoPicker(this.bytes, {this.hasCamera = false});

  Uint8List? bytes;
  final asked = <PhotoOrigin>[];

  @override
  final bool hasCamera;

  @override
  Future<Uint8List?> pick(PhotoOrigin origin) async {
    asked.add(origin);
    return bytes;
  }
}

/// Bytes that start like a PNG file. Tests decode them with [decodeAs].
Uint8List fakePng([int seed = 1]) =>
    Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, for (var i = 0; i < 40; i++) (seed * 31 + i) % 256]);

/// A picture made without a codec (which needs real async): a sky, a hill
/// and a sun, [w] × [h].
ui.Image testPicture({int w = 400, int h = 300}) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final size = Size(w.toDouble(), h.toDouble());
  canvas
    ..drawRect(Offset.zero & size, ui.Paint()..color = const Color(0xFFBFD7EA))
    ..drawCircle(Offset(size.width * 0.75, size.height * 0.3), size.height * 0.12, ui.Paint()..color = const Color(0xFFF6DE7A))
    ..drawPath(
      ui.Path()
        ..moveTo(0, size.height)
        ..lineTo(size.width * 0.35, size.height * 0.45)
        ..lineTo(size.width * 0.6, size.height * 0.8)
        ..lineTo(size.width * 0.8, size.height * 0.6)
        ..lineTo(size.width, size.height * 0.85)
        ..lineTo(size.width, size.height)
        ..close(),
      ui.Paint()..color = const Color(0xFF4E7A52),
    );
  final picture = recorder.endRecording();
  final image = picture.toImageSync(w, h);
  picture.dispose();
  return image;
}

/// Makes every image file decode to (a copy of) [image].
Override decodeAs(ui.Image image) => imageDecoderProvider.overrideWithValue((_) async => image.clone());

/// Bootstraps [store] with the test clock, crypto and fingerprint reader.
Future<List<Override>> testOverrides(
  MemoryBoardStore store, {
  String? location,
  FakeBiometric? biometric,
  IndexDb? index,
}) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final db = index ?? IndexDb.memory();
  if (index == null) addTearDown(db.close);
  return [
    ...await bootstrap(store, index: db, clock: () => testNow),
    lockCryptoProvider.overrideWithValue(testCrypto),
    biometricProvider.overrideWithValue(biometric ?? FakeBiometric()),
    if (location != null) initialLocationProvider.overrideWithValue(location),
  ];
}

/// Pumps the whole app at the tablet size (1280×800), starting at [location].
Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  MemoryBoardStore? store,
  String location = Routes.start,
  FakeBiometric? biometric,
  IndexDb? index,
  List<Override> extra = const [],
}) async {
  tester.view.physicalSize = tokens.Sizes.tabletFrame;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final overrides =
      await testOverrides(store ?? MemoryBoardStore(), location: location, biometric: biometric, index: index);
  await tester.pumpWidget(ProviderScope(overrides: [...overrides, ...extra], child: const EndlessApp()));
  await tester.pump();
  await tester.pump();
  return ProviderScope.containerOf(tester.element(find.byType(EndlessApp)));
}

/// Adds an empty "Untitled notebook" to [store] and returns its id.
String addUntitled(MemoryBoardStore store) {
  final now = DateTime.utc(2026, 9, 25, 9);
  final page = BoardPage(id: newId('pg'));
  final nb = Notebook(id: newId('nb'), title: 'Untitled notebook', createdAt: now, updatedAt: now, pageIds: [page.id]);
  store.savePage(nb.id, page);
  store.saveNotebook(nb);
  store.pageWrites = 0;
  return nb.id;
}

/// The pane of the Canvas screen pumped by [pumpCanvas].
late Pane canvasPane;

/// The notebook and page that screen shows.
NotebookState shownNotebook(ProviderContainer c) => c.read(notebookProvider(canvasPane.notebookId));
PageRuntime shownPage(ProviderContainer c) => shownNotebook(c).pageAt(canvasPane.page);

/// Pumps the app straight into a notebook's canvas: [notebookId], or the
/// store's first notebook (an empty one is created if there is none).
Future<ProviderContainer> pumpCanvas(
  WidgetTester tester, {
  MemoryBoardStore? store,
  String? notebookId,
  FakeBiometric? biometric,
  List<Override> extra = const [],
}) async {
  final s = store ?? MemoryBoardStore();
  final id = notebookId ?? (s.notebooks.isEmpty ? addUntitled(s) : s.notebooks.keys.first);
  final c = await pumpApp(tester, store: s, location: Routes.notebook(id), biometric: biometric, extra: extra);
  canvasPane = tester.widget<CanvasScreen>(find.byType(CanvasScreen)).pane;
  return c;
}

/// A store holding one notebook; optional settings.
MemoryBoardStore storeWith(LoadedNotebook nb, {AppSettings? settings}) {
  final store = MemoryBoardStore();
  store.saveNotebook(nb.notebook);
  for (final p in nb.pages) {
    store.savePage(nb.notebook.id, p);
  }
  store.pageWrites = 0;
  if (settings != null) store.settings = settings.toJson();
  return store;
}

StrokeItem strokeFrom(
  List<Offset> pts, {
  Color? color,
  double width = 2.5,
  InkTool tool = InkTool.pen,
  double Function(int i)? pressure,
  int z = 1,
}) =>
    StrokeItem.fromPagePoints(
      id: newId('it'),
      z: z,
      createdAt: DateTime.utc(2026, 9, 25, 10),
      tool: tool,
      penType: PenType.ballpoint,
      color: color ?? tokens.inkDefaults[0],
      width: width,
      usePressure: true,
      pagePoints: [
        for (final (i, p) in pts.indexed) InkPoint(p.dx, p.dy, pressure?.call(i) ?? 0.5, i * 8),
      ],
    );

/// "Physics — Lecture notes": 4 pages, ink on page 3, page 4 locked.
LoadedNotebook sampleNotebook() {
  final blue = tokens.inkDefaults[1];
  final clay = tokens.inkDefaults[2];
  final amber = tokens.extraInkDefaults[3];
  var z = 1;

  List<Offset> curve(Offset from, double length, double amp, double freq, {int n = 90}) => [
        for (var i = 0; i <= n; i++)
          Offset(from.dx + length * i / n, from.dy + amp * math.sin(i / n * freq * math.pi * 2)),
      ];
  List<Offset> ellipse(Offset c, double rx, double ry, {double turns = 1.08}) => [
        for (var i = 0; i <= 120; i++)
          Offset(c.dx + rx * math.cos(i / 120 * turns * 2 * math.pi - 2.2),
              c.dy + ry * math.sin(i / 120 * turns * 2 * math.pi - 2.2)),
      ];
  List<Offset> line(Offset a, Offset b) => [for (var i = 0; i <= 20; i++) Offset.lerp(a, b, i / 20)!];
  // Loopy "handwriting" line.
  List<Offset> scrawl(Offset from, double length, {double size = 14}) => [
        for (var i = 0; i <= 220; i++)
          Offset(from.dx + length * i / 220 + size * 0.5 * math.cos(i / 6), from.dy + size * math.sin(i / 6) * 0.9),
      ];
  double wobble(int i) => 0.35 + 0.35 * (1 + math.sin(i / 7)) / 2;

  final ink = <Item>[
    strokeFrom(scrawl(const Offset(730, 150), 380, size: 18), color: blue, width: 4, pressure: wobble, z: z++),
    strokeFrom(curve(const Offset(720, 184), 370, 3, 0.8), color: blue, width: 3, z: z++),
    strokeFrom(curve(const Offset(724, 296), 352, 1.5, 0.5), color: amber, width: 10, tool: InkTool.marker, z: z++),
    strokeFrom(scrawl(const Offset(736, 232), 150, size: 11), width: 3, pressure: wobble, z: z++),
    strokeFrom(scrawl(const Offset(736, 296), 330, size: 10), width: 2.5, pressure: wobble, z: z++),
    strokeFrom(scrawl(const Offset(736, 342), 200, size: 10), width: 2.5, pressure: wobble, z: z++),
    strokeFrom([...line(const Offset(726, 558), const Offset(1016, 558)), ...line(const Offset(1016, 558), const Offset(1016, 418)),
      ...line(const Offset(1016, 418), const Offset(726, 558))], width: 2.5, z: z++),
    strokeFrom(line(const Offset(884, 464), const Offset(884, 538)), color: clay, width: 2.5, z: z++),
    strokeFrom(line(const Offset(912, 452), const Offset(968, 425)), color: blue, width: 2.5, z: z++),
    strokeFrom(scrawl(const Offset(122, 376), 96, size: 14), color: blue, width: 3.5, pressure: wobble, z: z++),
    strokeFrom(scrawl(const Offset(132, 432), 130, size: 14), width: 3, pressure: wobble, z: z++),
    strokeFrom(ellipse(const Offset(204, 574), 78, 26), color: clay, width: 2.5, z: z++),
    strokeFrom(scrawl(const Offset(152, 574), 100, size: 10), color: clay, width: 3, pressure: wobble, z: z++),
    strokeFrom(scrawl(const Offset(128, 704), 220, size: 13), width: 3, pressure: wobble, z: z++),
  ];

  final pages = [
    BoardPage(id: 'pg_01'),
    BoardPage(id: 'pg_02'),
    BoardPage(id: 'pg_03', title: 'Lecture 3 — Momentum', items: ink),
    BoardPage(id: 'pg_04', locked: true),
  ];
  final nb = Notebook(
    id: 'nb_sample',
    title: 'Physics — Lecture notes',
    folderPath: ['School', 'Physics'],
    createdAt: DateTime.utc(2026, 9, 1, 14),
    updatedAt: DateTime.utc(2026, 9, 25, 10),
    pageIds: [for (final p in pages) p.id],
  );
  return LoadedNotebook(nb, pages);
}
