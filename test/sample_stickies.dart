import 'dart:math' as math;

import 'package:endless/board/ids.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/library/index_db.dart';
import 'package:endless/study/study_rows.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

// Sticky notes in several notebooks, for the library's Sticky notes
// (Stickies.png): loose notes, a stack, a locked notebook and a page with a
// password.

/// A wavy line of "handwriting" across a note, in note coordinates.
StrokeItem noteInk(double y, {double length = 180}) => strokeFrom(
      [for (var i = 0; i <= 120; i++) Offset(20 + length * i / 120 + 6 * math.cos(i / 4), y + 9 * math.sin(i / 4))],
      width: 2.5,
    );

final stickyAt = DateTime.utc(2026, 9, 20);

StickyItem stickyNote(String text, {Color? color, List<StickyNote> under = const [], double x = 100, int day = 0}) => StickyItem(
      id: newId('it'),
      x: x,
      y: 100,
      z: 1,
      createdAt: stickyAt.add(Duration(days: day)),
      w: 242,
      h: 220,
      color: color ?? tokens.stickyColors[0],
      items: [
        TextItem(id: newId('it'), x: 16, y: 14, z: 1, createdAt: stickyAt, text: text, size: 22, color: tokens.inkDefaults[0], wrap: 210),
      ],
      under: under,
    );

/// Two notebooks with sticky notes (one a stack), one locked, one with a
/// page with a password; their rows in the index.
Future<(MemoryBoardStore, IndexDb)> stickyLibrary() async {
  final store = MemoryBoardStore();
  final db = IndexDb.memory();
  addTearDown(db.close);
  Future<void> book(String id, String title, List<BoardPage> pages, {bool locked = false, String? cover}) async {
    await store.saveNotebook(Notebook(
      id: id,
      title: title,
      coverColor: cover,
      createdAt: stickyAt,
      updatedAt: stickyAt,
      pageIds: [for (final p in pages) p.id],
      locked: locked,
    ));
    for (final p in pages) {
      await store.savePage(id, p);
      if (!locked && !p.locked) await db.replacePageStudy(id, p.id, studyRowsFor(id, p, null));
    }
  }

  await book('nb_phys', 'Physics — Lecture notes', [
    BoardPage(id: 'pg_1'),
    BoardPage(id: 'pg_2', title: 'Exam notes', items: [
      stickyNote('Ask in office hours: impulse vs. force?', day: 3),
      stickyNote('Exam topics', color: tokens.stickyColors[1], x: 400, day: 2, under: [
        StickyNote(color: tokens.stickyColors[2], items: [
          TextItem(id: newId('it'), x: 16, y: 14, z: 1, createdAt: stickyAt, text: 'Conservation laws', size: 22, color: tokens.inkDefaults[0], wrap: 210),
        ]),
        StickyNote(color: tokens.stickyColors[3]),
      ]),
    ]),
    BoardPage(id: 'pg_3', locked: true),
  ], cover: '#2B5A8C');
  await book('nb_lab', 'Lab journal', [
    BoardPage(id: 'pg_l1', title: 'Results', items: [stickyNote('Email Maya the trial data', color: tokens.stickyColors[3], day: 1)]),
  ], cover: '#3E7B4F');
  await book('nb_secret', 'Diary', [
    BoardPage(id: 'pg_s1', items: [stickyNote('secret')]),
  ], locked: true);
  store.pageWrites = 0;
  return (store, db);
}

