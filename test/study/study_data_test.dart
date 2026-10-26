import 'dart:convert';
import 'dart:ui';

import 'package:endless/board/codec.dart';
import 'package:endless/board/model.dart';
import 'package:endless/board/store.dart';
import 'package:endless/library/library.dart';
import 'package:endless/recognition/handwriting_index.dart';
import 'package:endless/recognition/recognized.dart';
import 'package:endless/search/search.dart';
import 'package:endless/search/search_text.dart';
import 'package:endless/state/notebook.dart';
import 'package:endless/state/settings.dart';
import 'package:endless/study/fsrs.dart';
import 'package:endless/study/reminders.dart';
import 'package:endless/study/remember.dart';
import 'package:endless/study/study_rows.dart';
import 'package:endless/study/study_state.dart';
import 'package:endless/theme/tokens.g.dart' as tokens;
import 'package:endless/transfer/board_file.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../recognition/fake_ink.dart';

final _t = DateTime.utc(2026, 9, 25, 10);

TextItem _text(String id, String text, {Json? remember}) => TextItem(
      id: id,
      x: 100,
      y: 300,
      z: 5,
      createdAt: _t,
      remember: remember,
      wrap: 300,
      text: text,
      color: tokens.inkDefaults[0],
    );

FlashcardItem _card(String id, {List<String> front = const [], List<String> back = const [], String backText = ''}) =>
    FlashcardItem(
      id: id,
      x: 10,
      y: 20,
      z: 9,
      createdAt: _t,
      deck: 'dk_1',
      deckName: 'Physics — Momentum',
      front: CardSide(ids: front),
      back: CardSide(ids: back, text: backText),
      reverse: true,
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<T> _wait<T>(WidgetTester tester, Future<T> f) async {
  T? out;
  Object? error;
  var done = false;
  f.then((v) {
    out = v;
    done = true;
  }, onError: (Object e) {
    error = e;
    done = true;
  });
  for (var i = 0; i < 500 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  if (error != null) throw error!;
  expect(done, isTrue, reason: 'never finished');
  return out as T;
}

Future<ProviderContainer> _open(MemoryBoardStore store, String id, {ReminderService reminders = const NoReminders()}) async {
  final c = ProviderContainer(overrides: await testOverrides(store, reminders: reminders));
  addTearDown(c.dispose);
  c.listen(settingsProvider, (_, _) {});
  c.listen(libraryProvider, (_, _) {});
  c.listen(loadedNotebookProvider(id), (_, _) {});
  await c.read(loadedNotebookProvider(id).future);
  c.listen(notebookProvider(id), (_, _) {});
  return c;
}

void main() {
  group('in the page file', () {
    test('a flashcard round-trips, unknown fields and all', () {
      final card = _card('fc_1', front: ['a', 'b'], back: ['c'], backText: 'why it matters');
      final json = {...card.toJson(), 'later': 1};
      final back = decodeItem(jsonDecode(jsonEncode(json)) as Json);
      expect(back, isA<FlashcardItem>());
      final f = back as FlashcardItem;
      expect(f.front.ids, ['a', 'b']);
      expect(f.back.ids, ['c']);
      expect(f.back.text, 'why it matters');
      expect(f.reverse, isTrue);
      expect(f.deck, 'dk_1');
      expect(f.deckName, 'Physics — Momentum');
      expect(f.toJson()['later'], 1);
      expect(jsonDecode(jsonEncode(f.toJson())), jsonDecode(jsonEncode(json)));
      // Without a deck it can't be read: kept as it was.
      expect(decodeItem({...json}..remove('deck')), isA<UnknownItem>());
    });

    test('remembering changes only the mark, on any kind of item', () {
      final mark = const RememberMark(id: 'rm_1', why: 'on the exam', remind: RemindKind.tomorrow).toJson()
        ..['remindAt'] = '2026-09-26T09:00:00.000Z';
      final items = <Item>[
        strokeFrom([const Offset(0, 0), const Offset(30, 10)]),
        _text('t', 'Lab report due'),
        StickyItem(id: 's', x: 0, y: 0, z: 2, createdAt: _t, w: 242, h: 220, color: tokens.stickyColors[0], items: [_text('n', 'on it')]),
        ImageItem(id: 'i', x: 0, y: 0, z: 3, createdAt: _t, w: 200, h: 100, asset: 'abc.png'),
        UnknownItem({'id': 'u', 'type': 'hologram', 'x': 1, 'y': 2, 'z': 4, 'createdAt': '2026-09-25T10:00:00Z'}),
      ];
      for (final item in items) {
        final marked = withRemember(item, mark);
        expect(marked.runtimeType, item.runtimeType);
        expect(marked.remember, mark);
        expect({...marked.toJson()}..remove('remember'), {...item.toJson()}..remove('remember'), reason: item.type);
        final cleared = withRemember(marked, null);
        expect(cleared.remember, isNull);
        expect(jsonDecode(jsonEncode(cleared.toJson())), jsonDecode(jsonEncode(item.toJson())));
      }
    });

    test('a mark from before marks had ids is a thing of its own', () {
      final old = _text('t1', 'x', remember: {'why': 'because', 'remindAt': '2026-10-14T09:00:00Z', 'flashcard': false});
      final m = RememberMark.of(old)!;
      expect(m.id, 't1');
      expect(m.why, 'because');
      expect(m.remind, RemindKind.date);
      expect(m.remindAt, DateTime.utc(2026, 10, 14, 9));
      expect(m.flashcard, isNull);
    });

    test('things to remember: items with the same mark, the drawn star apart', () {
      const a = RememberMark(id: 'rm_a', why: 'w');
      const b = RememberMark(id: 'rm_b', drawn: true);
      final star = strokeFrom([const Offset(300, 0), const Offset(320, 20)]);
      final page = [
        _text('t1', 'one', remember: a.toJson()),
        withRemember(star, b.copyWith(star: true).toJson()),
        _text('t2', 'two', remember: a.toJson()),
        _text('t3', 'three', remember: b.toJson()),
        _text('t4', 'plain'),
        // A star whose words were erased isn't a thing to remember.
        withRemember(strokeFrom([const Offset(0, 0), const Offset(1, 1)]), const RememberMark(id: 'rm_c', star: true).toJson()),
      ];
      final groups = rememberGroups(page);
      expect(groups.map((g) => g.mark.id), ['rm_a', 'rm_b']);
      expect(groups[0].items.map((i) => i.id), ['t1', 't2']);
      expect(groups[0].mark.why, 'w');
      expect(groups[1].items.map((i) => i.id), ['t3']);
      expect(groups[1].star!.id, star.id);
      expect(groups[1].mark.drawn, isTrue);
      expect(groups[1].area.contains(const Offset(310, 10)), isTrue);
      expect(groups[1].content.contains(const Offset(310, 10)), isFalse);
    });
  });

  group('what the index keeps', () {
    test('a thing to remember: a copy of its items, its mark, and what it says', () {
      final r = FakeRecognizer();
      final ink = writeLine(r, 'total momentum', at: const Offset(100, 200));
      const mark = RememberMark(id: 'rm_1', why: 'always on the exam', remind: RemindKind.tomorrow, flashcard: 'fc_1');
      final page = BoardPage(id: 'pg_1', items: [
        for (final s in ink) withRemember(s, {...mark.toJson(), 'remindAt': '2026-09-26T09:00:00.000Z'}),
        _text('t', 'unrelated'),
      ]);
      final read = PageRecognition(language: 'en-US', lines: [
        RecognizedLine(
          key: 'k',
          strokeIds: [for (final s in ink) s.id],
          text: 'total momentum',
          words: [for (final (i, s) in ink.indexed) RecognizedWord(['total', 'momentum'][i], strokeIds: [s.id])],
          block: 0,
        ),
      ]);
      final rows = studyRowsFor('nb', page, read);
      expect(rows.single.kind, StudyKind.remember);
      final thing = RememberedThing.fromRow(rows.single);
      expect(thing.id, 'rm_1');
      expect(thing.items.map((i) => i.id), [for (final s in ink) s.id]);
      expect(thing.why, 'always on the exam');
      expect(thing.remindAt, DateTime.utc(2026, 9, 26, 9));
      expect(thing.hasReminder, isTrue);
      expect(thing.flashcard, 'fc_1');
      expect(thing.said, 'total momentum');
      expect(thing.typedOnly, isFalse);
    });

    test('a flashcard: copies of both sides as they are now, typed text, what\'s gone', () {
      final page = BoardPage(id: 'pg_1', items: [
        _text('t1', 'Impulse'),
        _text('t2', 'J = F · Δt'),
        _card('fc_1', front: ['t1'], back: ['t2', 'erased'], backText: 'a push over time'),
      ]);
      final card = StudyCard.fromRow(studyRowsFor('nb', page, null).single);
      expect(card.id, 'fc_1');
      expect(card.reverse, isTrue);
      expect(card.front.items.single.id, 't1');
      expect(card.front.said, 'Impulse');
      expect(card.back.items.map((i) => i.id), ['t2']);
      expect(card.back.missing, 1);
      expect(card.back.text, 'a push over time');
      expect(card.rect, page.items.first.extent);
    });

    testWidgets('marks reach the index soon after a change, leave it when undone or locked, and why notes are searchable',
        (tester) async {
      final store = MemoryBoardStore();
      final id = addUntitled(store);
      final c = await _open(store, id);
      final n = c.read(notebookProvider(id).notifier);
      final page = c.read(notebookProvider(id)).pages[0];
      final db = c.read(indexDbProvider);
      n.insertItems(page.id, [_text('t1', 'Lab report due Sep 30')]);
      await tester.pump(const Duration(milliseconds: 400));
      await _settle(tester);
      expect(await _wait(tester, db.studyRows()), isEmpty, reason: 'nothing marked');

      const mark = RememberMark(id: 'rm_1', why: 'submit as PDF');
      n.replaceItems(page.id, [withRemember(page['t1']!, mark.toJson())]);
      await tester.pump(const Duration(milliseconds: 400));
      await _settle(tester);
      final rows = await _wait(tester, db.studyRows());
      expect(rows.single.ref, 'rm_1');

      // "Why it matters" is typed text Search finds.
      Future<List<SearchHit>> search(String q) =>
          _wait(tester, runSearch(q, db: db, library: c.read(libraryProvider), store: store));
      await _wait(tester, c.read(handwritingIndexProvider).indexNow(id, page.id));
      final hits = await search('submit pdf');
      expect(hits.single.row.kind, SearchKind.typed);
      expect(hits.single.row.text, 'submit as PDF');

      n.undo(page.id);
      await tester.pump(const Duration(milliseconds: 400));
      await _settle(tester);
      expect(await _wait(tester, db.studyRows()), isEmpty);

      n.redo(page.id);
      await _wait(tester, c.read(handwritingIndexProvider).studyNow());
      expect(await _wait(tester, db.studyRows()), hasLength(1));

      await _wait(tester, n.lockPage(page.id, 'pw'));
      await _settle(tester);
      expect(await _wait(tester, db.studyRows()), isEmpty, reason: 'a page with a password is never indexed');
      expect(await search('submit'), isEmpty);
    });

    testWidgets('the study data: cards, what\'s due, and how well each is known, saved in study.json', (tester) async {
      final store = MemoryBoardStore();
      final id = addUntitled(store);
      final c = await _open(store, id);
      final n = c.read(notebookProvider(id).notifier);
      final page = c.read(notebookProvider(id)).pages[0];
      n.insertItems(page.id, [
        _text('t1', 'Impulse'),
        _text('t2', 'J = F · Δt'),
        _card('fc_1', front: ['t1'], back: ['t2']),
      ]);
      c.listen(studyProvider, (_, _) {});
      await tester.pump(const Duration(milliseconds: 400));
      await _wait(tester, c.read(studyProvider.notifier).refresh());
      final snap = c.read(studyProvider)!;
      expect(snap.cards.single.id, 'fc_1');
      // Front to back and back to front, both new and due.
      expect(snap.items.map((i) => i.key), ['$id/fc_1/f', '$id/fc_1/r']);
      expect(snap.dueAt(_t), 2);
      // The deck came with the card.
      expect(c.read(decksProvider).single.name, 'Physics — Momentum');
      final summary = deckSummaries(snap, c.read(decksProvider), _t).single;
      expect(summary.cards, 1);
      expect(summary.due, 2);

      final item = snap.items.first;
      final state = const Fsrs().review(null, Rating.easy, _t);
      await _wait(tester, c.read(studyProvider.notifier).record(item, state));
      expect(c.read(studyProvider)!.dueAt(_t), 1);
      final saved = await store.loadStudy(id);
      expect(((saved!['cards'] as Map)['fc_1'] as Map)['f'], state.toJson());

      // A fresh start reads it back.
      final again = ProviderContainer(overrides: await testOverrides(store, index: c.read(indexDbProvider)));
      addTearDown(again.dispose);
      again.listen(studyProvider, (_, _) {});
      await _wait(tester, again.read(studyProvider.notifier).refresh());
      expect(again.read(studyProvider)!.states['$id/fc_1/f']!.due, state.due);
    });
  });

  group('board files', () {
    test('study.json goes along for the cards exported, and comes back', () async {
      final store = MemoryBoardStore();
      final id = addUntitled(store);
      final nb = await store.loadNotebook(id);
      final page = nb!.pages.single;
      page.items.addAll([_text('t1', 'Impulse'), _card('fc_1', front: ['t1'], backText: 'push')]);
      await store.savePage(id, page);
      final state = const Fsrs().review(null, Rating.good, _t);
      await store.saveStudy(id, {
        'version': 1,
        'cards': {
          'fc_1': {'f': state.toJson()},
          'fc_gone': {'f': state.toJson()},
        },
      });
      final bytes = await exportBoardFile(store, id);
      final imported = await importBoardFile(store, bytes, folder: const [], now: _t);
      final study = await store.loadStudy(imported.notebookId);
      expect((study!['cards'] as Map).keys, ['fc_1'], reason: 'only cards that went along');
      final back = (await store.loadNotebook(imported.notebookId))!.pages.single.items.whereType<FlashcardItem>().single;
      expect(back.back.text, 'push');
      expect(studyFor({'cards': 'nope'}, {'a'}), isNull);
    });
  });

  group('reminders', () {
    RememberedThing thing(String id, {DateTime? at, String why = '', String said = ''}) => RememberedThing.fromRow(StudyRow(
          notebookId: 'nb',
          pageId: 'pg',
          kind: StudyKind.remember,
          ref: id,
          rect: const Rect.fromLTWH(10, 20, 30, 40),
          at: _t,
          data: {
            'items': const [],
            'why': why,
            'said': said,
            if (at != null) ...{'remind': 'date', 'remindAt': at.toIso8601String()},
          },
        ));

    test('one for each future reminder, saying what it is', () {
      final list = remindersFor([
        thing('a', at: _t.add(const Duration(days: 1)), why: 'on the exam', said: 'total momentum'),
        thing('b', at: _t.subtract(const Duration(hours: 1))),
        thing('c'),
        thing('d', at: _t.add(const Duration(hours: 2))),
      ], {'nb': 'Physics'}, _t);
      expect(list.map((r) => r.id), [reminderId('nb', 'a'), reminderId('nb', 'd')]);
      expect(list.first.title, 'Need to remember');
      expect(list.first.body, 'total momentum\n“on the exam”');
      expect(list.last.body, 'What you marked in Physics');
      final target = ReminderTarget.parse(list.first.payload)!;
      expect(target.notebookId, 'nb');
      expect(target.pageId, 'pg');
      expect(target.rect, const Rect.fromLTWH(10, 20, 30, 40));
      expect(reminderId('nb', 'a'), reminderId('nb', 'a'));
      expect(reminderId('nb', 'a'), isNot(reminderId('nb', 'b')));
      expect(reminderId('nb', 'a'), lessThan(1 << 31));
      expect(ReminderTarget.parse('{'), isNull);
    });

    testWidgets('kept in step with what\'s remembered: set, moved, and cancelled', (tester) async {
      final store = MemoryBoardStore();
      final id = addUntitled(store);
      final fake = FakeReminders();
      // A reminder left over from before, for something no longer remembered.
      fake.set[42] = Reminder(id: 42, at: _t.add(const Duration(days: 3)), title: 't', body: 'b', payload: '{}');
      final c = await _open(store, id, reminders: fake);
      c.read(reminderSyncProvider);
      final n = c.read(notebookProvider(id).notifier);
      final page = c.read(notebookProvider(id)).pages[0];
      final at = DateTime.utc(2026, 9, 26, 9);
      final mark = {...const RememberMark(id: 'rm_1', remind: RemindKind.tomorrow).toJson(), 'remindAt': at.toIso8601String()};
      n.insertItems(page.id, [_text('t1', 'Lab report due', remember: mark)]);
      await tester.pump(const Duration(milliseconds: 400));
      await _settle(tester);
      expect(fake.set.keys, [reminderId(id, 'rm_1')]);
      expect(fake.set.values.single.at, at);
      expect(fake.set.values.single.body, 'Lab report due');

      // Another time.
      final later = at.add(const Duration(days: 2));
      n.replaceItems(page.id, [withRemember(page['t1']!, {...mark, 'remindAt': later.toIso8601String()})]);
      await tester.pump(const Duration(milliseconds: 400));
      await _settle(tester);
      expect(fake.set.values.single.at, later);

      // No longer remembered.
      n.replaceItems(page.id, [withRemember(page['t1']!, null)]);
      await tester.pump(const Duration(milliseconds: 400));
      await _settle(tester);
      expect(fake.set, isEmpty);
      expect(fake.cancelled, containsAll([42, reminderId(id, 'rm_1')]));
    });
  });
}
