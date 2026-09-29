import 'dart:math' as math;

import 'package:endless/board/codec.dart';
import 'package:endless/board/lock.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/library/index_db.dart';
import 'package:endless/library/library.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// The library from the design (Start.png, Main.png): School, Work, Personal
/// and Sketches, with "Physics — Lecture notes" left on page 3 of 12 and
/// "Thesis brainstorm" locked with the password `thesis`. Returns the store
/// and an index that remembers where this tablet left each notebook.
Future<(MemoryBoardStore, IndexDb)> sampleLibrary() async {
  final store = MemoryBoardStore();
  final db = IndexDb.memory();
  addTearDown(db.close);
  final blue = tokens.coverColors[0], clay = tokens.coverColors[1], moss = tokens.coverColors[2];
  final plum = tokens.coverColors[3];
  final ink = tokens.inkDefaults[0];

  List<Offset> wave(Offset from, double length) => [
        for (var i = 0; i <= 60; i++) Offset(from.dx + length * i / 60, from.dy + 5 * math.sin(i / 60 * length / 9)),
      ];
  List<Offset> line(Offset a, Offset b) => [for (var i = 0; i <= 12; i++) Offset.lerp(a, b, i / 12)!];
  List<Offset> circle(Offset c, double r) => [
        for (var i = 0; i <= 40; i++)
          Offset(c.dx + r * math.cos(i / 40 * 2 * math.pi), c.dy + r * math.sin(i / 40 * 2 * math.pi)),
      ];
  List<Item> lines(List<(double, double, double)> rows, {Color? accent, List<Offset>? extra}) => [
        for (final (x, y, w) in rows) strokeFrom(wave(Offset(x, y), w), color: ink, width: 2.5),
        if (extra != null) strokeFrom(extra, color: accent ?? blue, width: 3),
      ];

  final covers = <String, List<Item>>{
    'nb_calc': [
      strokeFrom(line(const Offset(40, 240), const Offset(40, 40)), color: ink, width: 2.5),
      strokeFrom(line(const Offset(30, 230), const Offset(380, 230)), color: ink, width: 2.5),
      strokeFrom(
        [for (var i = 0; i <= 60; i++) Offset(50 + i * 5.0, 200 - 120 * math.sin(i / 60 * math.pi * 1.3))],
        color: ink,
        width: 2.5,
      ),
      strokeFrom(circle(const Offset(290, 130), 22), color: clay, width: 3),
    ],
    'nb_lab': lines([(40, 60, 170), (40, 110, 120)], accent: moss, extra: line(const Offset(180, 170), const Offset(40, 170))),
    'nb_plan': lines([(80, 60, 160), (80, 120, 220), (80, 180, 130)]),
    'nb_formula': lines(
      [(40, 60, 110), (220, 60, 130), (40, 130, 150), (240, 130, 110)],
      extra: line(const Offset(30, 90), const Offset(400, 90)),
    ),
    'nb_team': lines([(40, 60, 200), (40, 110, 160)]),
    'nb_garden': lines([(40, 60, 120), (40, 110, 220)], accent: moss, extra: circle(const Offset(320, 90), 30)),
  };

  var n = 0;
  Future<void> add(
    String id,
    String title,
    List<String> folder,
    Color cover,
    int pages,
    DateTime edited, {
    bool pinned = false,
    List<BoardPage>? content,
  }) async {
    n++;
    final list = content ??
        [
          for (var i = 0; i < pages; i++) BoardPage(id: '${id}_p$i', items: i == 0 ? [...?covers[id]] : []),
        ];
    final nb = Notebook(
      id: id,
      title: title,
      folderPath: folder,
      coverColor: colorToHex(cover),
      createdAt: edited.subtract(Duration(days: 20 + n)).toUtc(),
      updatedAt: edited.toUtc(),
      pageIds: [for (final p in list) p.id],
      pinned: pinned,
    );
    for (final p in list) {
      await store.savePage(id, p);
    }
    await store.saveNotebook(nb);
  }

  final physics = sampleNotebook().pages.take(3).toList();
  await add('nb_physics', 'Physics — Lecture notes', ['School'], blue, 12, testNow.subtract(const Duration(hours: 2)),
      content: [...physics, for (var i = 3; i < 12; i++) BoardPage(id: 'nb_physics_p$i')]);
  await add('nb_calc', 'Calculus II', ['School'], clay, 8, DateTime(2026, 9, 24, 17));
  await add('nb_lab', 'Lab journal', ['School'], moss, 5, DateTime(2026, 9, 21, 16), pinned: true);
  await add('nb_plan', 'Study plan', ['School'], plum, 1, DateTime(2026, 9, 18, 12), pinned: true);
  await add('nb_formula', 'Formula sheet', ['School'], blue, 2, DateTime(2026, 9, 12, 12), pinned: true);
  await add('nb_thesis', 'Thesis brainstorm', ['School'], clay, 3, DateTime(2026, 9, 3, 12));
  await add('nb_team', 'Team meeting', ['Work'], clay, 2, DateTime(2026, 9, 21, 9));
  await add('nb_garden', 'Garden ideas', ['Personal'], moss, 1, DateTime(2026, 9, 19, 12));
  for (final (id, title) in [
    ('nb_kin', 'Kinematics'),
    ('nb_waves', 'Waves'),
    ('nb_optics', 'Optics'),
    ('nb_thermo', 'Thermodynamics'),
  ]) {
    await add(id, title, ['School', 'Physics'], blue, 3, DateTime(2026, 8, 20));
  }
  for (final (id, title) in [('nb_limits', 'Limits'), ('nb_series', 'Series')]) {
    await add(id, title, ['School', 'Calculus'], blue, 2, DateTime(2026, 8, 10));
  }

  // "Thesis brainstorm" has a notebook password.
  final (entry, key) = await testCrypto.create('thesis', hint: 'the usual');
  await store.saveLock('nb_thesis', LockFile(notebook: entry).toJson());
  final thesis = (await store.loadNotebook('nb_thesis'))!;
  for (final p in thesis.pages) {
    await store.saveSealedPage('nb_thesis', p.id, await testCrypto.seal(key, encodePage(p)));
  }
  await store.saveNotebook(thesis.notebook..locked = true);

  store.library = {
    'version': 1,
    'folders': [
      for (final (path, color) in [
        (['School'], blue),
        (['Work'], clay),
        (['Personal'], moss),
        (['Sketches'], plum),
        (['School', 'Physics'], blue),
        (['School', 'Calculus'], blue),
      ])
        {'path': path, 'color': colorToHex(color)},
    ],
  };
  store.settings = AppSettings(userName: 'Kieth').toJson();
  store.pageWrites = 0;

  // This tablet last had Physics open on page 3.
  await db.upsert(NotebookEntry(
    id: 'nb_physics',
    title: '',
    folder: const [],
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    pageCount: 0,
    lastPage: 2,
    openedAt: testNow.subtract(const Duration(hours: 1)).toUtc(),
  ));
  return (store, db);
}
