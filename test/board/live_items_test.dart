// Charts and live items as items (Phase 7b): round trips with unknown
// fields kept, checklist rows and the ink written on them, and what clocks,
// dates and time stamps say.

import 'dart:convert';

import 'package:endless/board/codec.dart';
import 'package:endless/board/model.dart';
import 'package:endless/canvas/live_items.dart';
import 'package:endless/recognition/handwriting_index.dart' show rowsFor;
import 'package:endless/recognition/reader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../live_samples.dart';

final _at = DateTime.utc(2026, 9, 28, 20);

Item _byId(BoardPage page, String id) => page.items.firstWhere((i) => i.id == id);

T _roundTrip<T extends Item>(T item) {
  final json = jsonDecode(jsonEncode(item.toJson())) as Json;
  final back = decodeItem(json);
  expect(back, isA<T>());
  expect(jsonEncode(back.toJson()), jsonEncode(item.toJson()));
  return back as T;
}

ChecklistItem _list(List<ChecklistEntry> entries, {double unit = 1, double rotation = 0}) => ChecklistItem(
      id: 'it_list',
      x: 100,
      y: 50,
      rotation: rotation,
      z: 1,
      createdAt: _at,
      w: ChecklistItem.width * unit,
      title: 'Before the lab',
      entries: entries,
      unit: unit,
    );

void main() {
  group('round trips', () {
    test('charts, with what this version does not know kept', () {
      final (nb, _, _) = chartsSample();
      for (final chart in nb.pages.single.items.whereType<ChartItem>()) {
        final back = _roundTrip(chart);
        expect(back.cells, chart.cells);
        expect(back.source, chart.source);
      }
      final json = (_byId(nb.pages.single, 'it_week') as ChartItem).toJson()
        ..['legend'] = 'top'
        ..['snapshot'] = {...(_byId(nb.pages.single, 'it_week') as ChartItem).toJson()['snapshot'] as Map, 'at': '2026-09-28'}
        ..['source'] = {...(_byId(nb.pages.single, 'it_week') as ChartItem).toJson()['source'] as Map, 'header': true};
      final back = decodeItem(json) as ChartItem;
      expect(back.toJson()['legend'], 'top');
      expect((back.toJson()['snapshot'] as Map)['at'], '2026-09-28');
      expect((back.toJson()['source'] as Map)['header'], true);
      expect(back.colors.single, (_byId(nb.pages.single, 'it_week') as ChartItem).colors.single);
      expect(back.suffix, 'h');
      // An unlinked chart with no source: a snapshot.
      final snapshot = _roundTrip((_byId(nb.pages.single, 'it_week') as ChartItem).copyWith(linked: false, source: () => null));
      expect(snapshot.live, isFalse);
    });

    test('clocks, dates, time stamps and checklists', () {
      for (final item in liveSample().pages.single.items) {
        if (item is LiveItem || item is ChecklistItem) _roundTrip(item);
      }
      final digital = _roundTrip(LiveItem(id: 'it_c', x: 0, y: 0, z: 1, createdAt: _at, data: const ClockData(analog: false), unit: 1.5));
      expect((digital.data as ClockData).analog, isFalse);
      expect(digital.toJson()['type'], 'widget');
      expect(digital.toJson()['widget'], 'clock');
      expect(digital.w, 280 * 1.5);
      final stamp = _roundTrip(LiveItem(id: 'it_s', x: 0, y: 0, z: 1, createdAt: _at, data: StampData(_at, ago: true)));
      expect(stamp.toJson()['type'], 'timestamp');
      expect((stamp.data as StampData).at, _at);

      final clock = LiveItem(id: 'it_c', x: 0, y: 0, z: 1, createdAt: _at, data: const ClockData()).toJson()
        ..['config'] = {'style': 'analog', 'seconds': false};
      expect(((decodeItem(clock) as LiveItem).toJson()['config'] as Map)['seconds'], false);
      // Another kind of widget is kept as it was.
      expect(decodeItem({...clock, 'widget': 'calendar'}), isA<UnknownItem>());

      final list = _byId(liveSample().pages.single, 'it_list') as ChecklistItem;
      final json = list.toJson();
      (json['entries'] as List).first = <String, dynamic>{...(json['entries'] as List).first as Map, 'due': 'Friday'};
      final back = decodeItem(jsonDecode(jsonEncode(json)) as Json) as ChecklistItem;
      expect(back.entries.first.extra['due'], 'Friday');
      expect(back.entries.first.ink.single.id, 'it_entry0');
      expect(back.doneCount, 2);
    });
  });

  group('checklists', () {
    test('LiveItems.dc.html\'s sizes: five rows are 382 tall', () {
      final list = _byId(liveSample().pages.single, 'it_list') as ChecklistItem;
      expect(list.entries.length, 5);
      expect(list.h, closeTo(382, 0.5));
      expect(list.rows.first, (ChecklistItem.rowsTop, ChecklistItem.rowMin));
      expect(_list(const []).h, closeTo(127, 0.5));
      // Writing taller than a row makes it taller.
      final tall = _list([
        ChecklistEntry(ink: [strokeFrom(const [Offset(0, 0), Offset(10, 70)])]),
      ]);
      expect(tall.rows.first.$2, greaterThan(70));
    });

    test('ink on a row joins its entry; on "write another item…" it starts one', () {
      var list = _list(const [ChecklistEntry(text: 'safety goggles')]);
      final slot = list.toPage(list.slot.center);
      expect(list.takesInkAt(slot), isTrue);
      list = list.withInk(strokeFrom([slot, slot + const Offset(60, 4)]));
      expect(list.entries.length, 2);
      expect(list.entries.last.ink.length, 1);
      // The ink stays where it was written.
      expect(list.pageInk.single.bounds.center.dx, closeTo(slot.dx + 30, 0.5));
      expect(list.pageInk.single.bounds.center.dy, closeTo(slot.dy + 2, 0.5));
      // A second stroke where the slot was goes on that new entry.
      list = list.withInk(strokeFrom([slot + const Offset(70, 0), slot + const Offset(90, 2)]));
      expect(list.entries.length, 2);
      expect(list.entries.last.ink.length, 2);
      // Written from the slot's left edge: moved clear of the new box (the
      // tablet, 2026-10-28).
      final edge = list.toPage(list.slot.centerLeft + const Offset(4, 0));
      final fromEdge = list.withInk(strokeFrom([edge, edge + const Offset(80, 0)]));
      expect(fromEdge.entries.last.ink.single.bounds.left, greaterThanOrEqualTo(0));
      expect(fromEdge.pageInk.last.bounds.left, greaterThan(fromEdge.toPage(fromEdge.boxRect(fromEdge.entries.length - 1).centerRight).dx));
      // Not on the box or the title.
      expect(list.takesInkAt(list.toPage(list.boxRect(0).center)), isFalse);
      expect(list.takesInkAt(list.toPage(const Offset(200, 20))), isFalse);
    });

    test('scaled, the ink stays where it was written; turned, on its row', () {
      final list = _list(const [ChecklistEntry(text: 'a')], unit: 2);
      final at = list.toPage(list.slot.center * 2);
      final written = list.withInk(strokeFrom([at, at + const Offset(40, 0)]));
      expect(written.entries.length, 2);
      expect(written.pageInk.single.pagePoints.first.dx, closeTo(at.dx, 0.01));
      expect(written.pageInk.single.pagePoints.first.dy, closeTo(at.dy, 0.01));
      expect(written.entries.last.ink.single.width, closeTo(2.5 / 2, 1e-9));
      // Turned, it turns about its middle, which moves down as it grows.
      final turned = _list(const [ChecklistEntry(text: 'a')], rotation: 15);
      final row = turned.toPage(turned.rowRect(0).center + const Offset(60, 0));
      final onRow = turned.withInk(strokeFrom([row, row + const Offset(30, 0)]));
      expect(onRow.entries.length, 1);
      expect(onRow.entries.single.ink, hasLength(1));
    });

    test('erasing an entry\'s ink takes the entry; a copy has ink of its own', () {
      final a = strokeFrom(const [Offset(0, 10), Offset(40, 12)]);
      final b = strokeFrom(const [Offset(0, 10), Offset(30, 12)]);
      final list = _list([
        ChecklistEntry(ink: [a]),
        ChecklistEntry(ink: [b], done: true),
      ]);
      // Its row stays until the eraser lifts; then the empty entry goes.
      final left = list.withoutInk({a.id});
      expect(left.entries.length, 2);
      expect(left.rows.last, list.rows.last);
      expect(left.pruned.entries.single.done, isTrue);
      expect(identical(list.pruned, list), isTrue);
      final moved = list.replaceInk(b.id, list.pageInk.last.mapped((p) => p + const Offset(5, 0)));
      expect(moved.entries.last.ink.single.bounds.left, closeTo(b.bounds.left + 5, 0.01));
      final copy = list.withBox(id: 'it_copy', x: 0, y: 0, w: list.w, h: list.h);
      expect(copy.ink.map((s) => s.id).toSet().intersection(list.ink.map((s) => s.id).toSet()), isEmpty);
    });

    test('its boxes, a 44 px square each', () {
      final list = _byId(liveSample().pages.single, 'it_list') as ChecklistItem;
      expect(checklistBoxAt(list, list.boxRect(2).center), 2);
      expect(checklistBoxAt(list, list.boxRect(2).center + const Offset(20, 0)), 2);
      expect(checklistBoxAt(list, list.boxRect(2).center + const Offset(40, 0)), isNull);
      expect(checklistText(list), 'Checklist · Before the lab');
    });

    test('its handwriting is read, and found as on a checklist', () {
      final page = liveSample().pages.single;
      final groups = inkGroupsOf(page).where((g) => g.holder == 'it_list').toList();
      expect(groups.single.strokes.length, 5);
      // Where they are on the card: one row under the other.
      final tops = [for (final s in groups.single.strokes) s.bounds.top];
      expect(tops, orderedEquals([...tops]..sort()));
      expect(visibleInk(page).keys, containsAll(['it_entry0', 'it_entry4']));
      expect(allInk(page).keys, contains('it_entry3'));
      final rows = rowsFor('nb', page, null);
      expect(rows.where((r) => r.text.contains('Before the lab')), isNotEmpty);
    });
  });

  group('what they say', () {
    test('the time, how long ago, the date', () {
      expect(clockText(DateTime(2026, 9, 28, 21, 23, 53)), '9:23:53 PM');
      expect(clockText(DateTime(2026, 9, 28, 0, 5), seconds: false), '12:05 AM');
      expect(clockText(DateTime(2026, 9, 28, 12, 0), seconds: false), '12:00 PM');
      final now = DateTime(2026, 9, 28, 21, 23, 53);
      expect(agoText(now.subtract(const Duration(seconds: 20)), now), 'just now');
      expect(agoText(now.subtract(const Duration(minutes: 12)), now), '12 min ago');
      expect(agoText(now.subtract(const Duration(hours: 3)), now), '3 h ago');
      expect(agoText(now.subtract(const Duration(days: 2)), now), '2 days ago');
      expect(stampLabel(StampData(now.subtract(const Duration(minutes: 47)).toUtc()), now), '8:36 PM');
      expect(stampLabel(StampData(now.subtract(const Duration(minutes: 47)).toUtc(), ago: true), now), '47 min ago');
      final page = liveSample().pages.single;
      expect(liveText(_byId(page, 'it_date') as LiveItem, now), 'Monday, September 28');
    });

    test('when they need drawing again', () {
      final now = DateTime(2026, 9, 28, 21, 23, 53);
      final page = liveSample().pages.single;
      final clock = liveKey(page.items, now);
      expect(liveKey(page.items, now.add(const Duration(seconds: 1))), isNot(clock));
      final noClock = [for (final i in page.items) if (i is! LiveItem || i.data is! ClockData) i];
      // The date: once a minute.
      expect(liveKey(noClock, now.add(const Duration(seconds: 1))), liveKey(noClock, now));
      expect(liveKey(noClock, now.add(const Duration(minutes: 1))), isNot(liveKey(noClock, now)));
      // Stamps showing clock time never change.
      expect(liveKey([for (final i in noClock) if (i is! LiveItem || i.data is StampData) i], now), '');
    });

    test('the clock\'s Analog and Digital, and a stamp, are buttons', () {
      final clock = LiveItem(id: 'it_c', x: 0, y: 0, z: 1, createdAt: _at, data: const ClockData(), unit: 2);
      final (analog, digital) = clockButtons(const ClockData());
      expect(liveHitAt(clock, analog.center * 2), LivePart.analog);
      expect(liveHitAt(clock, digital.center * 2), LivePart.digital);
      expect(liveHitAt(clock, const Offset(280, 400)), isNull);
      expect(digital.right, closeTo(280 - 18, 0.01));
      final stamp = LiveItem(id: 'it_s', x: 0, y: 0, z: 1, createdAt: _at, data: StampData(_at));
      expect(liveHitAt(stamp, const Offset(20, 13)), LivePart.stamp);
      expect(liveHitAt(LiveItem(id: 'it_d', x: 0, y: 0, z: 1, createdAt: _at, data: const DateData()), const Offset(20, 13)), isNull);
    });
  });
}
